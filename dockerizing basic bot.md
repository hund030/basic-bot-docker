## Prerequisite

* Az CLI
* Helm
* Kubectl
* Docker

## Leverage Teams Toolkit to create Teams app, bot registration

1. Refer to the Teams Toolkit project file [teamsapp.yml](./teamsapp.yml)
1. Run `Teams: Provision` command from VS Code command palette

1. Find your bot registration id and teams app id from [.env.local](./env/.env.local)
    ```
    TEAMS_APP_ID=
    BOT_ID=
    ```
1. Go to dev portal and find your bot registration in [https://dev.teams.microsoft.com/bots/\<bot-id\>/configure](https://dev.teams.microsoft.com/bots/). We need to update the bot endpoint later.


## Build the docker image

1. Refer to the [Dockerfile](./Dockerfile)
1. Build the docker image

    ```
    docker build -t basic-bot .
    ```

1. Check the image

    ```
    $ docker images
    REPOSITORY                         TAG       IMAGE ID       CREATED          SIZE
    basic-bot                          latest    90b8333d2be9   28 minutes ago   1.18GB
    ```

## (Optional) Verify the docker image

1. Run the docker image locally

    ```
    docker run -p 80:80 basic-bot
    ```
1. Tunnel your localhost to public url with [ngrok](https://ngrok.com/)

    ```
    ngrok http https://localhost:80
    ```
1. Update the bot endpoint to your ngrok https endpoint in dev portal. For example, https://75fe5c3e.ngrok.io/api/messages
1. Launch a Teams web client and install the teams app to test the bot: https://teams.microsoft.com/l/app/\<Teams-app-id\>?installAppPackage=true&webjoin=true

## Deploy the docker image to Azure Container Registry

1. Follow the document to create container registry: https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-prepare-acr?tabs=azure-cli

    ```
    az acr login --name <acrName>
    az acr list --resource-group <rg> --query "[].{acrLoginServer:loginServer}" --output table
    ```

1. Tag the image and push to registry.

    ```
    docker tag basic-bot:latest <acrLoginServer>/basic-bot:v1
    docker push <acrLoginServer>/basic-bot:v1
    ```

## Create Kubernetes cluster and deploy the application

1. Follow the document to create Azure Kubernetes Service cluster: https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-deploy-cluster?tabs=azure-cli
1. Refer the the deployment file [basic-bot.yaml](./basic-bot.yaml)
1. Update the image name in deployment file.

    ```
    containers:
        - name: basic-bot
          image: <acrLoginServer>/basic-bot:v1
    ```

1. Apply the deployment file to AKS.

    ```
    $ az aks install-cli
    $ az aks get-credentials --resource-group <rg> --name <aksName>
    $ kubectl apply -f basic-bot.yaml

    deployment "basic-bot" created
    service "basic-bot" created
    ```

1. Check the service status.

    ```
    $ kubectl get service basic-bot
    NAME        TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)         AGE
    basic-bot   LoadBalancer   10.0.218.138   20.241.162.9   80:31421/TCP   5h4m
    ```

## Setup TLS with an ingress controller

Since Teams bot endpoint must be a HTTPS endpoint. We need to setup TLS for the server.

1. Follow the document to create an ingress controller: https://learn.microsoft.com/en-us/azure/aks/ingress-basic?tabs=azure-cli
1. Create a basic NGINX ingress controller.

    ```
    $ NAMESPACE=ingress-basic

    $ helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    $ helm repo update

    $ helm install ingress-nginx ingress-nginx/ingress-nginx \
    --create-namespace \
    --namespace $NAMESPACE \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

    $ kubectl get services --namespace ingress-basic -o wide -w ingress-nginx-controller

    NAME                       TYPE           CLUSTER-IP    EXTERNAL-IP     PORT(S)                      AGE    SELECTOR
    ingress-nginx-controller   LoadBalancer   10.0.14.224   20.246.235.30   80:32514/TCP,443:32226/TCP   142m   app.kubernetes.io/component=controller,app.kubernetes.io/instance=ingress-nginx,app.kubernetes.io/name=ingress-nginx
    ```

1. Follow the document to use TLS with Let's Encrypt certificates: https://learn.microsoft.com/en-us/azure/aks/ingress-tls?tabs=azure-cli#use-tls-with-lets-encrypt-certificates
1. Import the cert-manager images used by the Helm chart into your ACR

    ```
    REGISTRY_NAME=<REGISTRY_NAME>
    CERT_MANAGER_REGISTRY=quay.io
    CERT_MANAGER_TAG=v1.8.0
    CERT_MANAGER_IMAGE_CONTROLLER=jetstack/cert-manager-controller
    CERT_MANAGER_IMAGE_WEBHOOK=jetstack/cert-manager-webhook
    CERT_MANAGER_IMAGE_CAINJECTOR=jetstack/cert-manager-cainjector

    az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CONTROLLER:$CERT_MANAGER_TAG
    az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_WEBHOOK:$CERT_MANAGER_TAG
    az acr import --name $REGISTRY_NAME --source $CERT_MANAGER_REGISTRY/$CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG --image $CERT_MANAGER_IMAGE_CAINJECTOR:$CERT_MANAGER_TAG
    ```

1. Use a dynamic public IP address and configure the public IP with an FQDN.

    ```
    # Public IP address of your ingress controller
    $ IP="MY_EXTERNAL_IP" // 20.246.235.30 in the sample case
    $ DNSLABEL="aliasbasicbot"
    $ PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)

    $ az network public-ip update --ids $PUBLICIPID --dns-name $DNSLABEL
    $ az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv

    aliasbasicbot.eastus.cloudapp.azure.com
    ```

1. Install cert-manager with helm.

    ```
    ACR_URL=<REGISTRY_URL> // basicbotacr.azurecr.io in this sample case

    kubectl label namespace ingress-basic cert-manager.io/disable-validation=true
    helm repo add jetstack https://charts.jetstack.io
    helm repo update

    helm install cert-manager jetstack/cert-manager \
    --namespace ingress-basic \
    --version=$CERT_MANAGER_TAG \
    --set installCRDs=true \
    --set nodeSelector."kubernetes\.io/os"=linux \
    --set image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CONTROLLER \
    --set image.tag=$CERT_MANAGER_TAG \
    --set webhook.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_WEBHOOK \
    --set webhook.image.tag=$CERT_MANAGER_TAG \
    --set cainjector.image.repository=$ACR_URL/$CERT_MANAGER_IMAGE_CAINJECTOR \
    --set cainjector.image.tag=$CERT_MANAGER_TAG
    ```

1. Create a CA cluster issuer. Refer to [deploy/cluster-issuer.yaml](./deploy/cluster-issuer.yaml).

    ```
    kubectl apply -f deploy/cluster-issuer.yaml --namespace ingress-basic
    ```

1. Create ingress routes. In this sample case, we have only one bot service, so all of the traffic is routed to `basic-bot` service. Refer to [deploy/basic-bot-ingress.yaml](./deploy/basic-bot-ingress.yaml)

    ```
    # Update the spec.tls.hosts and spec.rules.host to the FQDN before applying the deployment.
    kubectl apply -f deploy/basic-bot-ingress.yaml --namespace ingress-basic
    ```

1. Verify the certificate.

```
$ kubectl get certificate --namespace ingress-basic --watch
NAME         READY   SECRET       AGE
tls-secret   False   tls-secret   11s
tls-secret   True    tls-secret   25s
```

## Update the bot endpoint and preview the bot in Teams client

1. Go to dev portal and update the bot endpoint to <your-FQDN>/api/messages: https://dev.teams.microsoft.com/bots/\<botId>/configure. In this sample case, the endpoint is https://aliasbasicbot.eastus.cloudapp.azure.com/api/messages.
1. Launch a Teams web client and install the teams app to test the bot: https://teams.microsoft.com/l/app/\<Teams-app-id\>?installAppPackage=true&webjoin=true
