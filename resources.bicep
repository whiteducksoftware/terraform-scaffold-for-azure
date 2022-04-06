param vault_name string
param vault_sku string
param sa_name string
param sa_sku string
param sc_name string
param tenant_id string
param user_id string
param tag string
param location string

resource tf_akv 'Microsoft.KeyVault/vaults@2021-04-01-preview' = {
  name: vault_name
  location: location
  tags: {
    environment: tag
  }
  properties: {
    sku: {
      family: 'A'
      name: vault_sku
    }
    tenantId: tenant_id
    accessPolicies: [
      {
        tenantId: tenant_id
        objectId: user_id
        permissions: {
          keys: []
          secrets: [
            'get'
            'list'
            'set'
            'delete'
            'backup'
            'restore'
            'recover'
          ]
          certificates: []
          storage: []
        }
      }
    ]
    enabledForDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
  }
}

resource tf_sa 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: sa_name
  location: location
  tags: {
    environment: tag
  }
  sku: {
    name: sa_sku
  }
  kind: 'StorageV2'
  properties: {
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          enabled: true
        }
        blob: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource tf_sc 'Microsoft.Storage/storageAccounts/blobServices/containers@2018-07-01' = {
  name: '${sa_name}/default/${sc_name}'
  dependsOn: [
    tf_sa
  ]
}
