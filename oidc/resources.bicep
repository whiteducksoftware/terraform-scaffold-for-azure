// Parameters
param sa_name string
param sa_sku string
param sc_name string
param tag string
param location string

// Storage Account
resource tf_sa 'Microsoft.Storage/storageAccounts@2025-06-01' = {
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

// Blob Service
resource tf_sb 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' existing = {
  parent: tf_sa
  name: 'default'
}

// Storage Container
resource tf_sc 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: tf_sb
  name: sc_name
}
