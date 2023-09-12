
## Overview

This document introduces how to deploy a Teams application to either Azure Kubernetes Service, Azure Container Apps or Azure App Service. Here is the document that compares the different container compute services in Azure: https://learn.microsoft.com/en-us/azure/container-apps/compare-options.

The following are the steps you need to take to deploy your Teams application:

1. [Create Teams App and Bot Registration](#use-teams-toolkit-to-create-a-teams-app)
1. [Build the docker image](#build-the-docker-image)
    - [Verify the docker image](#optional-test-the-docker-image-locally)
1. [Push the docker image to Azure Container Registry](#push-the-docker-image-to-azure-container-registry)
1. Deploy your application.
    - [[Option 1] Deploy to Azure Kubernetes Service](#option-1---deploy-to-azure-kubernetes-service)
        - [Setup TLS with an ingress controller](#setup-tls)
    - [[Option 2] Deploy to Azure Container Apps](#option-2---deploy-to-azure-container-apps)
    - [[Option 3] Deploy to Azure App Service](#option-3---deploy-to-azure-app-service)
1. [Update the Teams app bot registration](#update-the-bot-registration-and-preview-the-bot-in-teams-client)

## Prerequisites

* Teams Toolkit
* Azure CLI
* Helm
* Kubectl
* Docker

## Use Teams Toolkit to create a Teams app

1. The Teams Toolkit project file [teamsapp.yml](./teamsapp.yml) contains the commands to build and deploy your application.
1. Run `Teams: Provision` command from VS Code command palette.
1. Find your bot registration id and teams app id from [.env.dev](./env/.env.dev)
    ```
    TEAMS_APP_ID=
    BOT_ID=
    ```
1. Go to Teams Developer Portal and find your bot registration in [https://dev.teams.microsoft.com/bots/\<bot-id\>/configure](https://dev.teams.microsoft.com/bots/). We will need to update the bot endpoint later.


## Build the docker image

1. This project includes an example [Dockerfile](./Dockerfile).
1. Build the docker image.

    ```
    docker build -t basic-bot .
    ```

1. Verify the image is built.

    ```
    $ docker images
    REPOSITORY                         TAG       IMAGE ID       CREATED          SIZE
    basic-bot                          latest    90b8333d2be9   28 minutes ago   1.18GB
    ```

## (Optional) Test the docker image locally

1. Run the docker image locally

    ```
    docker run -p 80:80 basic-bot
    ```
1. Tunnel your localhost to a public url using a tool such as [ngrok](https://ngrok.com/).

    ```
    ngrok http https://localhost:80
    ```
1. Update the bot endpoint to the ngrok https endpoint in Teams Developer Portal (linked to above). For example, https://75fe5c3e.ngrok.io/api/messages
1. Launch the Teams web client and install the teams app to test the bot: https://teams.microsoft.com/l/app/\<Teams-app-id\>?installAppPackage=true&webjoin=true

## Push the docker image to Azure Container Registry

1. Follow this document to create an Azure Container Registry instance: https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-prepare-acr?tabs=azure-cli

1. Verify that the instance was created successfully with the following commands:
    ```
    az acr login --name <acrName>
    az acr list --resource-group <rg> --query "[].{acrLoginServer:loginServer}" --output table
    ```

1. Tag the application image and push this image to the registry.

    ```
    docker tag basic-bot:latest <acrLoginServer>/basic-bot:v1
    docker push <acrLoginServer>/basic-bot:v1
    ```

## Option 1 - Deploy to Azure Kubernetes Service

### Create a Kubernetes cluster and deploy the application

1. Follow this document to create an Azure Kubernetes Service cluster: https://learn.microsoft.com/en-us/azure/aks/tutorial-kubernetes-deploy-cluster?tabs=azure-cli
1. Open the deployment file [basic-bot.yaml](./basic-bot.yaml) included in this project.
1. Update the image name in deployment file.
1. Deploy the container.

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

### Setup TLS

Teams application endpoints must be an HTTPS endpoint. To set this up:

1. Refer to this document to create an ingress controller: https://learn.microsoft.com/en-us/azure/aks/ingress-basic?tabs=azure-cli
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

1. Refer to this document to use TLS with Let's Encrypt certificates: https://learn.microsoft.com/en-us/azure/aks/ingress-tls?tabs=azure-cli#use-tls-with-lets-encrypt-certificates
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

1. Install cert-manager with Helm.

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

## Option 2 - Deploy to Azure Container Apps

    ```
    $ az extension add --name containerapp --upgrade
    $ az provider register --namespace Microsoft.App
    $ az provider register --namespace Microsoft.OperationalInsights
    $ az containerapp up -n <container-app-name> -g <rg> --location eastus --environment 'basic-bot' --image <acrLoginServer>/basic-bot:v1 --target-port 80 --ingress external --query properties.configuration.ingress.fqdn
    ```

## Option 3 - Deploy to Azure App Service

    ```
    $ az extension add --name containerapp --upgrade
    $ az provider register --namespace Microsoft.App
    $ az provider register --namespace Microsoft.OperationalInsights
    $ az containerapp up -n <container-app-name> -g <rg> -l
    ```

## Update the bot registration and preview the bot in Teams client

Regardless of where you deployed your application, the final step is to update the bot registration to refer to the endpoint of your application.

1. Go to dev portal and update the bot endpoint to <your-FQDN>/api/messages: https://dev.teams.microsoft.com/bots/\<botId>/configure. In this sample case, the endpoint is https://<unique-appname>.azurewebsites.net/api/messages.
1. Launch a Teams web client and install the teams app to test the bot: https://teams.microsoft.com/l/app/\<Teams-app-id\>?installAppPackage=true&webjoin=true
