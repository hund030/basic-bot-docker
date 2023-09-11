param keyVaultName string
param identityObjectId string

@secure()
param botAadAppClientId string
@secure()
param botAadAppClientSecret string

var tenantId = subscription().tenantId


resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: keyVaultName
  location: resourceGroup().location
  properties: {
    tenantId: tenantId
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2019-09-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: identityObjectId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
  }
}

resource botAadAppCientId 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: keyVault
  name: 'botAadAppClientId'
  properties: {
    value: botAadAppClientId
  }
}

resource botAadAppCientSecret 'Microsoft.KeyVault/vaults/secrets@2019-09-01' = {
  parent: keyVault
  name: 'botAadAppClientSecret'
  properties: {
    value: botAadAppClientSecret
  }
}
