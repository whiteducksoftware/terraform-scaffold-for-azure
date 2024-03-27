param vault_name string
param vault_sku string
param sa_name string
param sa_sku string
param sc_name string
param tenant_id string
param user_id string
param tag string
param location string
param roleId string = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Officer


resource tf_akv 'Microsoft.KeyVault/vaults@2022-07-01' = {
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
    enableRbacAuthorization: true
    enabledForDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
  }
}

resource tf_sa 'Microsoft.Storage/storageAccounts@2022-09-01' = {
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
    minimumTlsVersion: 'TLS1_2'
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

resource tf_sb 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' existing = {
  parent: tf_sa
  name: 'default'
}

resource tf_sc 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: tf_sb
  name: sc_name
}

// Assign Role Key Vault Officer to User
resource keyVaultAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, tf_akv.name, user_id)
  scope: tf_akv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalId: user_id
    principalType: 'User'
  }
}
