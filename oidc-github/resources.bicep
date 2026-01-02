param sa_name string
param sa_sku string
param sc_name string
param tag string
param location string

resource tf_sa 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: sa_name
  location: location
  tags: {
    environment: tag
    managedBy: 'tfScaffolding'
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

resource tf_sb 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: tf_sa
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
      allowPermanentDelete: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
      allowPermanentDelete: false
    }
  }
}

resource tf_sc 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: tf_sb
  name: sc_name
}
