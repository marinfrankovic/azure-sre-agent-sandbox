@description('Principal ID of the SRE Agent workload identity (user-assigned).')
param agentPrincipalId string

@description('System-assigned principal ID of Azure Managed Grafana.')
param grafanaPrincipalId string

@description('Storage account name.')
param storageAccountName string

@description('Key vault name.')
param keyVaultName string

@description('Grafana instance name.')
param grafanaName string

@description('Azure Monitor workspace name.')
param monitorWorkspaceName string

@description('Application Insights component name.')
param appInsightsName string

@description('Log Analytics workspace name.')
param logAnalyticsName string

// Built-in role definition IDs
var roles = {
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  monitoringReader: '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
  monitoringDataReader: 'b0d8363b-8ddd-447d-831f-62ca05bff136'
  logAnalyticsReader: '73c42c96-874c-492b-b04d-ab87d138a893'
  grafanaViewer: '60921a7e-fef1-4a43-9b16-a26c52ad4769'
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

// Existing resources (scoped to this resource group)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' existing = {
  name: grafanaName
}

resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' existing = {
  name: monitorWorkspaceName
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

// ── Agent (user-assigned identity) ──────────────────────────────────────────

resource agentReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, agentPrincipalId, roles.reader)
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.reader)
  }
}

resource agentLogAnalyticsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalytics.id, agentPrincipalId, roles.logAnalyticsReader)
  scope: logAnalytics
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.logAnalyticsReader)
  }
}

resource agentAppInsightsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appInsights.id, agentPrincipalId, roles.monitoringReader)
  scope: appInsights
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.monitoringReader)
  }
}

resource agentMonitorDataReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(monitorWorkspace.id, agentPrincipalId, roles.monitoringDataReader)
  scope: monitorWorkspace
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.monitoringDataReader)
  }
}

resource agentStorageReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, agentPrincipalId, roles.storageBlobDataReader)
  scope: storageAccount
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataReader)
  }
}

resource agentGrafanaViewer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, agentPrincipalId, roles.grafanaViewer)
  scope: grafana
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.grafanaViewer)
  }
}

resource agentKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, agentPrincipalId, roles.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsUser)
  }
}

// ── Grafana (system-assigned identity) ──────────────────────────────────────

resource grafanaMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, grafanaPrincipalId, roles.monitoringReader)
  properties: {
    principalId: grafanaPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.monitoringReader)
  }
}

resource grafanaMonitorDataReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(monitorWorkspace.id, grafanaPrincipalId, roles.monitoringDataReader)
  scope: monitorWorkspace
  properties: {
    principalId: grafanaPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.monitoringDataReader)
  }
}
