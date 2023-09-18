@maxLength(20)
@minLength(4)
@description('Used to generate names for all resources in this file')
param resourceBaseName string

@description('Specifies the docker container image to deploy.')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Minimum number of replicas that will be deployed')
@minValue(0)
@maxValue(25)
param minReplica int = 1

@description('Maximum number of replicas that will be deployed')
@minValue(0)
@maxValue(25)
param maxReplica int = 3

var location = resourceGroup().location
// https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#acrpull
var acrPullRole = resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

module acr 'containerRegistry.bicep' = {
  name: 'acr'
  params: {
    containerRegistryName: resourceBaseName
  }
}

@description('This module seeds the ACR with the public version of the app')
module acrImportImage 'br/public:deployment-scripts/import-acr:3.0.1' =  {
  name: 'importContainerImage'
  params: {
    acrName: acr.outputs.name
    location: location
    images: array(containerImage)
  }
}

resource containerAppEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: resourceBaseName
  location: location
  properties: {}
}

resource uai 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${resourceBaseName}'
  location: location
}

@description('This allows the managed identity of the container app to access the registry, note scope is applied to the wider ResourceGroup not the ACR')
resource uaiRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, uai.id, acrPullRole)
  properties: {
    roleDefinitionId: acrPullRole
    principalId: uai.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: resourceBaseName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uai.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          identity: uai.id
          server: acr.outputs.loginServer
        }
      ]
    }
    template: {
      revisionSuffix: 'firstrevision'
      containers: [
        {
          name: resourceBaseName
          image: acrImportImage.outputs.importedImages[0].acrHostedImage
          resources: {
            cpu: json('.25')
            memory: '.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: minReplica
        maxReplicas: maxReplica
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

output contaierAppFQDN string = containerApp.properties.configuration.ingress.fqdn
output containerImage string = acrImportImage.outputs.importedImages[0].acrHostedImage
