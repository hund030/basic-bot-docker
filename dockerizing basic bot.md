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

## Create Azure App Service and deploy the image to it

    ```
    $ az group create --name DockerRG --location <region>
    $ az appservice plan create -n myappserviceplan -g DockerRG --is-linux
    $ az webapp create -n <unique-appname> -g DockerRG -p myappserviceplan -i <acrLoginServer>/basic-bot:v1
    ```

## Update the bot endpoint and preview the bot in Teams client

1. Go to dev portal and update the bot endpoint to <your-FQDN>/api/messages: https://dev.teams.microsoft.com/bots/\<botId>/configure. In this sample case, the endpoint is https://<unique-appname>.azurewebsites.net/api/messages.
1. Launch a Teams web client and install the teams app to test the bot: https://teams.microsoft.com/l/app/\<Teams-app-id\>?installAppPackage=true&webjoin=true
