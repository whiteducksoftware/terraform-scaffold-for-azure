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
    Environment: tag
  }
  sku: {
    name: sa_sku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    supportsHttpsTrafficOnly: true
  }
}

// Blob Service
resource tf_sb 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: tf_sa
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: false
    }
  }
}

// Storage Container
resource tf_sc 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: tf_sb
  name: sc_name
  properties: {
    publicAccess: 'None'
  }
}
