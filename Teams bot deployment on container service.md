# Deploying a Teams Bot to a Container Service

This guide will help you deploy a Teams bot to a container service. We'll cover the deployment process in three sections: Azure Container Apps, Azure Kubernetes Service, and On-Premise Kubernetes Cluster.

## Prerequisites

You can download the [sample application](https://github.com/OfficeDev/TeamsFx-Samples/tree/dev/bot-sso-docker) used in this tutorial from the Teams Toolkit sample gallery. This sample provides a ready-to-use experience for Azure Container Apps development. With a few configuration adjustments, you can also deploy it to Azure Kubernetes Service or an on-premise Kubernetes cluster.

You'll need an Azure Account and the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) for ACA or AKS deployment. 

> Please note that the commands in this tutorial are based on Bash. You may need to adjust them to work in other command line interfaces.

## Deploying to Azure Container Apps

Azure Container Apps is a fully managed service that lets you run containerized applications in the cloud. It's an excellent choice if you don't require direct access to all native Kubernetes APIs and cluster management, and prefer a fully managed experience based on best practices.

With the sample application, you can simply run the `provision` and `deploy` commands in Teams Toolkit. Teams Toolkit will create an Azure Container Registry and an Azure Container Apps for you, build your application into a container image, and deploy it to Azure Container Apps.

The `provision` command creates and configures the following resources:

* A Teams app with bot capability
* An Azure Container Registry to host your container image
* An Azure Container App Environment and an Azure Container Apps to host your bot application
* An Azure Entra App for authentication
* An Azure Bot Service to channel Teams client and Azure Container Apps

The `deploy` command performs the following:

* Builds the application into a container image
* Pushes the container image to Azure Container Registry
* Deploys the image to Azure Container Apps

## Deploying to Azure Kubernetes Service

Azure Kubernetes Service (AKS) is a managed container orchestration service provided by Azure. If you're looking for a fully managed version of Kubernetes in Azure, AKS is an ideal choice. 

### Architecture

![image](https://github.com/hund030/basic-bot-docker/assets/26134943/29fb7c78-2f3b-4bb6-aa04-5b26b00a02b1)

The Teams backend server communicates with your bot via the Azure Bot Service, which requires your bot to have a public HTTPS address. To achieve this, you will need to deploy an ingress controller and provision a TLS certificate on your Kubernetes.

Your bot authenticates with the Azure Bot Service using Microsoft Entra ID, so you should provision a secret that contains the App ID and password on your Kubernetes and reference it in your container runtime.

### Setup ingress with HTTPS on AKS

1. Ensure you have an existing Azure Kubernetes Service connected to your Azure Container Registry, which hosts your container images. If you do not have one, please refer to this tutorial: [AKS Tutorials](https://learn.microsoft.com/azure/aks/learn/quick-kubernetes-deploy-cli).
1. Run the following commands to install ingress controller and certificate manager. This is not the only way to set up ingress and TLS certificates on your Kubernetes cluster. For more information, refer to [Create an ingress controller](https://learn.microsoft.com/azure/aks/ingress-basic?tabs=azure-cli) and [Use TLS with Let's Encrypt certificates](https://learn.microsoft.com/azure/aks/ingress-tls?tabs=azure-cli#use-tls-with-lets-encrypt-certificates).
    ```
    NAMESPACE=ingress-basic

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm install ingress-nginx ingress-nginx/ingress-nginx --create-namespace --namespace $NAMESPACE \
        --set controller.nodeSelector."kubernetes\.io/os"=linux  \
        --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux  \
        --set controller.healthStatus=true \
        --set controller.service.externalTrafficPolicy=Local \
        --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz 

    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install cert-manager jetstack/cert-manager --namespace $NAMESPACE --set installCRDs=true --set nodeSelector."kubernetes\.io/os"=linux
    ```
1. Update the DNS for the ingress public IP and get the ingress endpoint.
    ```
    > kubectl get services --namespace $NAMESPACE -w ingress-nginx-controller

    NAME TYPE CLUSTER-IP EXTERNAL-IP PORT(S)
    ingress-nginx-controller LoadBalancer $CLUSTER_IP $EXTERNAL_IP 80:32514/TCP,443:32226/TCP

    > PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$EXTERNAL_IP')].[id]" --output tsv)
    > az network public-ip update --ids $PUBLICIPID --dns-name $DNSLABEL
    > az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv

    $DNSLABEL.$REGION.cloudapp.azure.com
    ```

### Provision resources with Teams Toolkit

You can leverage the provision command in Teams Toolkit to create the Teams app with bot capability, the Azure Bot Service and the Microsoft Entra ID for authentication. 
You can make some updates to the sample code to make it works with your Azure Kubernetes Service.

1. Fill the BOT_DOMAIN value in `env/.env.${envName}` with your FQDN.

1. Update the `arm/deploy` action in `teamsapp.yml` so that Teams Toolkit will provision an Azure Bot Service when running `provision` command. 
    ```
    - uses: arm/deploy 
      with:
        subscriptionId: ${{AZURE_SUBSCRIPTION_ID}} 
        resourceGroupName: ${{AZURE_RESOURCE_GROUP_NAME}} 
        templates:
          - path: ./infra/botRegistration/azurebot.bicep
            parameters: ./infra/botRegistration/azurebot.parameters.json
            deploymentName: Create-resources-for-bot
        bicepCliVersion: v0.9.1
    ```

1. Run the `provision` command in Teams Toolkit.

1. After provisioning, you can find the `BOT_ID` in `env/.env.${envName}` file and the encrypted `SECRET_BOT_PASSWORD` in `env/.env.${envName}.user` file. Click the `Decrypt secret` annotation to get the real value of `BOT_PASSWORD`.

1. Create a Kubernetes secret that contains `BOT_ID` and `BOT_PASSWORD`. You can store the key-value pair in the `./deploy/.env.dev-secrets` first and run the following command to provision the secret.
    ```
    kubectl create secret generic dev-secrets --from-env-file ./deploy/.env.dev-secrets -n $NAMESPACE
    ```

### Apply the deployment

The sample contains an example deployment file `deploy/sso-bot.yaml` for your reference. You need to update the placeholders before applying it.

1. Update the `<image>` placeholder with your image. For example, `myacr.azurecr.io/sso-bot:latest`.

1. Update the `<hostname>` with your ingress FQDN

1. Update the `<email>` with your email address for generating TLS certificate.

1. Apply `deploy/sso-bot.yaml`.
    ```
    kubectl apply -f deploy/sso-bot.yaml -n $NAMESPACE
    ```

1. In VS Code `Run and Debug` panel, select the `Launch Remote` configuration and press F5 to preview the Teams bot application that deployed on AKS.

## Deploying to an On-Premise Kubernetes Cluster

You can deploy a Teams bot to your own Kubernetes cluster or Kubernetes service in other Cloud services, which involves similar steps to deploying on Azure Kubernetes Service. Here are the steps:

### Architecture

![image](https://github.com/hund030/basic-bot-docker/assets/26134943/29fb7c78-2f3b-4bb6-aa04-5b26b00a02b1)

Teams backend server communicates with your bot via the Azure Bot Service, so the bot definitely needs a public HTTPS address. You need to deploy an ingress controller and provision a TLS certificate on your Kubernetes.

The bot needs to authenticate to Azure Bot Service by Microsoft Entra ID, so you should provision a secret that contains the App ID and password on your Kubernetes and refer to it in your container runtime.

### Provision resources with Teams Toolkit

You can leverage the provision command in Teams Toolkit to create the Teams app with bot capability, the Azure Bot Service and the Microsoft Entra ID for authentication. 

You can make some updates to the sample code to make it works with your Kubernetes Service.

1. Fill the BOT_DOMAIN value in `env/.env.${envName}` with your FQDN.

1. Update the `arm/deploy` action in `teamsapp.yml` so that Teams Toolkit will provision an Azure Bot Service when running `provision` command. 
    ```yaml
    - uses: arm/deploy 
      with:
        subscriptionId: ${{AZURE_SUBSCRIPTION_ID}} 
        resourceGroupName: ${{AZURE_RESOURCE_GROUP_NAME}} 
        templates:
          - path: ./infra/botRegistration/azurebot.bicep
            parameters: ./infra/botRegistration/azurebot.parameters.json
            deploymentName: Create-resources-for-bot
        bicepCliVersion: v0.9.1
    ```

1. It is recommended to use Azure Bot Service for channeling. If you don't have an Azure account and cannot create Azure Bot Service, you can create a bot registration as an alternative. Add the `botFramework/create` action in the provision stage in `teamsapp.yml` to leverage Teams Toolkit to create a bot registration with the correct messaging endpoint.
    ```yaml
    - uses: botFramework/create
        with:
        botId: ${{BOT_ID}}
        name: <Bot display name>
        messagingEndpoint: https://${{BOT_DOMAIN}}/api/messages
        description: ""
        channels:
            - name: msteams
    ```

    You can remove the `arm/deploy` action in `teamsapp.yml` file since we do not need any Azure resources.

1. Run the `provision` command in Teams Toolkit.

1. After provisioning, you can find the `BOT_ID` in `env/.env.${envName}` file and the encrypted `SECRET_BOT_PASSWORD` in `env/.env.${envName}.user` file. Click the `Decrypt secret` annotation to get the real value of `BOT_PASSWORD`.

1. Create a Kubernetes secret that contains `BOT_ID` and `BOT_PASSWORD`. You can store the key-value pair in the `./deploy/.env.dev-secrets` first and run the following command to provision the secret.
    ```
    kubectl create secret generic dev-secrets --from-env-file ./deploy/.env.dev-secrets -n $NAMESPACE
    ```

### Apply the deployment

The sample contains an example deployment file `deploy/sso-bot.yaml` for your reference. You need to update the placeholders before applying it.

1. Update the `<image>` placeholder with your image. For example, `myacr.azurecr.io/sso-bot:latest`.

1. Update the `<hostname>` with your ingress FQDN

1. Update the `<email>` with your email address for generating TLS certificate.

1. Apply `deploy/sso-bot.yaml`.
    ```
    kubectl apply -f deploy/sso-bot.yaml -n $NAMESPACE
    ```

1. In VS Code `Run and Debug` panel, select the `Launch Remote` configuration and press F5 to preview the Teams bot application that deployed on AKS.
