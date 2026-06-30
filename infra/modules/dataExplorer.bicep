@description('Name of the Azure Data Explorer cluster.')
param clusterName string

@description('Name of the Azure Data Explorer database.')
param databaseName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Log Analytics workspace resource ID for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('Principal ID granted Viewer access to the database (least privilege).')
param readerPrincipalId string

resource cluster 'Microsoft.Kusto/clusters@2024-04-13' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Dev(No SLA)_Standard_E2a_v4'
    tier: 'Basic'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enableStreamingIngest: true
    enablePurge: false
    publicNetworkAccess: 'Enabled'
  }
}

resource database 'Microsoft.Kusto/clusters/databases@2024-04-13' = {
  parent: cluster
  name: databaseName
  location: location
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: 'P30D'
    hotCachePeriod: 'P7D'
  }
}

resource databaseViewer 'Microsoft.Kusto/clusters/databases/principalAssignments@2024-04-13' = {
  parent: database
  name: guid(database.id, readerPrincipalId, 'Viewer')
  properties: {
    principalId: readerPrincipalId
    principalType: 'App'
    role: 'Viewer'
    tenantId: subscription().tenantId
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-${clusterName}'
  scope: cluster
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Command'
        enabled: true
      }
      {
        category: 'Query'
        enabled: true
      }
      {
        category: 'Journal'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output clusterId string = cluster.id
output clusterName string = cluster.name
output clusterUri string = cluster.properties.uri
output databaseName string = database.name
