docker build -t basic-bot .
az acr login --name <acrName>
az acr list --resource-group <rg> --query "[].{acrLoginServer:loginServer}" --output table
docker tag basic-bot:latest <acrLoginServer>/basic-bot:latest
docker push <acrLoginServer>/basic-bot:latest
az aks install-cli
az aks get-credentials --resource-group <rg> --name <aksName>
kubectl apply -f basic-bot.yaml