bg Deploying a Teams Bot to a Container Service

This guide will walk you through the process of deploying a Teams bot to a container service. The deployment process will be covered under three sections: Azure Container Apps, Azure Kubernetes Service, and On-Premise Kubernetes Cluster.

## Prerequisites

You can download the [sample application](https://github.com/OfficeDev/TeamsFx-Samples/tree/dev/bot-sso-docker) used in this tutorial from the Teams Toolkit sample gallery. This sample provides a ready-to-use experience for Azure Container Apps development. With a few configuration adjustments, you can also deploy it to Azure Kubernetes Service or an on-premise Kubernetes cluster.

## Deploying to Azure Container Apps

Azure Container Apps is a fully managed service that allows you to run containerized applications in the cloud. If you don't need direct access to all native Kubernetes APIs and cluster management, Azure Container Apps offers a fully managed experience based on best practices.

By using the sample application, you can simply run the `provision` and `deploy` commands in Teams Toolkit. Teams Toolkit will then create an Azure Container Registry and an Azure Container Apps for you, build your application into a Docker image, and deploy it to Azure Container Apps.

The `provision` command creates and configures the following resources:

* A Teams app with bot capability
* An Azure Container Registry to host your Docker image
* An Azure Container App Environment and an Azure Container Apps to host your bot application
* An Azure Entra App for authorization
* An Azure Bot Service to channel Teams client and Azure Container Apps

The `deploy` command performs the following:

* Builds the application into a Docker image
* Pushes the Docker image to Azure Container Registry
* Deploys the image to Azure Container Apps

## Deploying to Azure Kubernetes Service

Azure Kubernetes Service (AKS) is a managed container orchestration service provided by Azure. If you're looking for a fully managed version of Kubernetes in Azure, AKS is an ideal choice. 

To deploy your Teams bot on an Azure Kubernetes service, follow these steps:

1. Ensure you have an existing Azure Kubernetes Service connected to your Azure Container Registry, which hosts your container images. If you do not have one, please refer to this tutorial: [AKS Tutorials](https://learn.microsoft.com/azure/aks/tutorial-kubernetes-prepare-app).
1. Install dependencies for setting up TLS. Refer to [Create an ingress controller](https://learn.microsoft.com/azure/aks/ingress-basic?tabs=azure-cli) and [Use TLS with Let's Encrypt certificates](https://learn.microsoft.com/azure/aks/ingress-tls?tabs=azure-cli#use-tls-with-lets-encrypt-certificates).
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
1. Update the DNS for the ingress public IP.
    ```
    > kubectl get services --namespace $NAMESPACE -w ingress-nginx-controller

    NAME TYPE CLUSTER-IP EXTERNAL-IP PORT(S)
    ingress-nginx-controller LoadBalancer $CLUSTER_IP $EXTERNAL_IP 80:32514/TCP,443:32226/TCP

    > PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$EXTERNAL_IP')].[id]" --output tsv)
    > az network public-ip update --ids $PUBLICIPID --dns-name $DNSLABEL
    > az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv

    $DNSLABEL.$REGION.cloudapp.azure.com
    ```
1. It's recommended to use Azure Bot Service to channel Teams client and your bot application. To update your AKS ingress endpoint to the Azure Bot Service, fill the BOT_DOMAIN value in `env/.env.${envName}` with your FQDN. Update the `arm/deploy` action in `teamsapp.yml` and run `provision` command of Teams Toolkit to create a Teams app and a bot registration.
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
1. Your bot application typically requires `BOT_ID` and `BOT_PASSWORD` in the process environment for authorization. You can create a secret that serves as environment variables with the following command. Ensure to fill in the values in `deploy/env/.env.dev-secrets` beforehand. You can find the values in `env/.env.${envName}` and `env/.env.dev.user` after provisioning.
    ```
    kubectl create secret generic dev-secrets --from-env-file ./deploy/env/.env.dev-secrets -n $NAMESPACE
    ```
1. Update the hostname and your email in the `deploy/sso-bot.yaml` and apply it.
    ```
    kubectl apply -f deploy/sso-bot.yaml -n $NAMESPACE
    ```
1. In VS Code `Run and Debug` panel, select the `Launch Remote` configuration and press F5 to preview the Teams bot application that deployed on AKS.

## Deploying to an On-Premise Kubernetes Cluster

You can also deploy a Teams bot to your own Kubernetes cluster or Kubernetes service in other Cloud services, which involves similar steps to deploying on Azure Kubernetes Service. Here are the steps:

1. Set up ingress and TLS for your Kubernetes cluster.
1. Fill the BOT_DOMAIN value in `env/.env${envName}` with your FQDN.
1. It's recommended to use Azure Bot Service to channel Teams client and your bot application. To update your AKS ingress endpoint to the Azure Bot Service, fill the BOT_DOMAIN value in `env/.env.${envName}` with your FQDN. Update the `arm/deploy` action in `teamsapp.yml` and run `provision` command of Teams Toolkit to create a Teams app and a bot registration.
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
1. If you don't have an Azure account and cannot create Azure Bot Service, you can create a bot registration in dev.botframework.com as an alternative. Add the botFramework/create action in the provision stage in `teamsapp.yml` to leverage Teams Toolkit to create a bot registration with the correct messaging endpoint.
    ```yaml
    # Create or update the bot registration on dev.botframework.com
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

    > Note that `botFramework/create` action requires `BOT_ID` which is generated by `botAadApp/create` action. So `botFramework/create` action should follow `botAadApp/create` action.
1. Besides a bot registration, Teams Toolkit also creates a Teams app and an Azure Entra App by running the provision command, as it is defined in the provision stage in `teamsapp.yml` file.
1. Your bot application typically requires at least `BOT_ID` and `BOT_PASSWORD` in the process environment for authorization. You can create a secret that serves as environment variables with the following command. Ensure to fill in the values in `deploy/env/.env.dev-secrets` beforehand. You can find the values in `env/.env.${envName}` and `env/.env.dev.user` after provisioning.
    ```
    kubectl create secret generic dev-secrets --from-env-file ./deploy/env/.env.dev-secrets -n $NAMESPACE
    ```
1. Update the hostname and your email in the `deploy/sso-bot.yaml` and apply it.
    ```
    kubectl apply -f deploy/sso-bot.yaml -n $NAMESPACE
    ```
1. In VS Code `Run and Debug` panel, select the `Launch Remote` configuration and press F5 to preview the Teams bot application that deployed on your on-premise Kubernetes cluster.
