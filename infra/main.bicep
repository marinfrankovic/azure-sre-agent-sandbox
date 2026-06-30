targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@minLength(1)
@maxLength(32)
@description('Environment name used for deterministic resource naming.')
param environmentName string

@minLength(1)
@description('Azure region for all resources in the sandbox.')
param location string

@description('Optional resource group name. Defaults to rg-<environmentName>-sre.')
param resourceGroupName string = ''

@description('Tags applied to every resource.')
param tags object = {}

// ============================================================================
// Naming
// ============================================================================

var abbrs = loadJsonContent('abbreviations.json')
var token = toLower(uniqueString(subscription().id, environmentName))
var envClean = toLower(replace(environmentName, '-', ''))

var rgName = empty(resourceGroupName) ? '${abbrs.resourcesResourceGroups}${environmentName}-sre' : resourceGroupName

var names = {
  identity: '${abbrs.managedIdentityUserAssignedIdentities}${environmentName}'
  logAnalytics: '${abbrs.operationalInsightsWorkspaces}${environmentName}'
  appInsights: '${abbrs.insightsComponents}${environmentName}'
  monitorWorkspace: '${abbrs.monitorAccounts}${environmentName}'
  dataCollectionEndpoint: '${abbrs.dataCollectionEndpoints}${environmentName}'
  dataCollectionRule: '${abbrs.dataCollectionRules}${environmentName}'
  storage: take('${abbrs.storageStorageAccounts}${envClean}${token}', 24)
  keyVault: take('${abbrs.keyVaultVaults}${envClean}${token}', 24)
  dataExplorer: take('${abbrs.kustoClusters}${envClean}${token}', 22)
  grafana: '${abbrs.dashboardGrafana}${environmentName}'
  sreAgent: '${abbrs.appAgents}${environmentName}'
}

var commonTags = union(tags, {
  'azd-env-name': environmentName
  workload: 'sre-agent-sandbox'
})

// ============================================================================
// Resource group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: commonTags
}

// ============================================================================
// Identity
// ============================================================================

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    name: names.identity
    location: location
    tags: commonTags
  }
}

// ============================================================================
// Observability platform
// ============================================================================

module logAnalytics 'modules/logAnalytics.bicep' = {
  name: 'logAnalytics'
  scope: rg
  params: {
    name: names.logAnalytics
    location: location
    tags: commonTags
    retentionInDays: 30
  }
}

module appInsights 'modules/appInsights.bicep' = {
  name: 'appInsights'
  scope: rg
  params: {
    name: names.appInsights
    location: location
    tags: commonTags
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
  }
}

module monitorWorkspace 'modules/monitorWorkspace.bicep' = {
  name: 'monitorWorkspace'
  scope: rg
  params: {
    name: names.monitorWorkspace
    dataCollectionEndpointName: names.dataCollectionEndpoint
    dataCollectionRuleName: names.dataCollectionRule
    location: location
    tags: commonTags
  }
}

// ============================================================================
// Data plane
// ============================================================================

module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: names.storage
    location: location
    tags: commonTags
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
  }
}

module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: names.keyVault
    location: location
    tags: commonTags
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
  }
}

module dataExplorer 'modules/dataExplorer.bicep' = {
  name: 'dataExplorer'
  scope: rg
  params: {
    clusterName: names.dataExplorer
    databaseName: 'sreagent'
    location: location
    tags: commonTags
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
    readerPrincipalId: identity.outputs.principalId
  }
}

// ============================================================================
// Grafana + SRE Agent
// ============================================================================

module grafana 'modules/grafana.bicep' = {
  name: 'grafana'
  scope: rg
  params: {
    name: names.grafana
    location: location
    tags: commonTags
    azureMonitorWorkspaceResourceId: monitorWorkspace.outputs.resourceId
    logAnalyticsWorkspaceId: logAnalytics.outputs.resourceId
  }
}

module sreAgent 'modules/sreAgent.bicep' = {
  name: 'sreAgent'
  scope: rg
  params: {
    name: names.sreAgent
    location: location
    tags: commonTags
    userAssignedIdentityId: identity.outputs.resourceId
  }
}

// ============================================================================
// RBAC (least privilege)
// ============================================================================

module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  scope: rg
  params: {
    agentPrincipalId: identity.outputs.principalId
    grafanaPrincipalId: grafana.outputs.systemAssignedPrincipalId
    storageAccountName: names.storage
    keyVaultName: names.keyVault
    grafanaName: names.grafana
    monitorWorkspaceName: names.monitorWorkspace
    appInsightsName: names.appInsights
    logAnalyticsName: names.logAnalytics
  }
}

// ============================================================================
// Outputs
// ============================================================================

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name

output AZURE_USER_ASSIGNED_IDENTITY_ID string = identity.outputs.resourceId
output AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID string = identity.outputs.clientId
output AZURE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID string = identity.outputs.principalId

output AZURE_LOG_ANALYTICS_WORKSPACE_ID string = logAnalytics.outputs.resourceId
output AZURE_LOG_ANALYTICS_CUSTOMER_ID string = logAnalytics.outputs.customerId
output AZURE_APPLICATION_INSIGHTS_ID string = appInsights.outputs.resourceId
output AZURE_APPLICATION_INSIGHTS_CONNECTION_STRING string = appInsights.outputs.connectionString
output AZURE_MONITOR_WORKSPACE_ID string = monitorWorkspace.outputs.resourceId
output AZURE_MONITOR_WORKSPACE_PROMETHEUS_QUERY_ENDPOINT string = monitorWorkspace.outputs.prometheusQueryEndpoint
output AZURE_DATA_COLLECTION_ENDPOINT_ID string = monitorWorkspace.outputs.dataCollectionEndpointId
output AZURE_DATA_COLLECTION_RULE_ID string = monitorWorkspace.outputs.dataCollectionRuleId

output AZURE_STORAGE_ACCOUNT_ID string = storage.outputs.resourceId
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_BLOB_ENDPOINT string = storage.outputs.blobEndpoint

output AZURE_KEY_VAULT_ID string = keyVault.outputs.resourceId
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_URI string = keyVault.outputs.vaultUri

output AZURE_DATA_EXPLORER_CLUSTER_ID string = dataExplorer.outputs.clusterId
output AZURE_DATA_EXPLORER_CLUSTER_URI string = dataExplorer.outputs.clusterUri
output AZURE_DATA_EXPLORER_DATABASE_NAME string = dataExplorer.outputs.databaseName

output AZURE_GRAFANA_ID string = grafana.outputs.resourceId
output AZURE_GRAFANA_ENDPOINT string = grafana.outputs.endpoint
output AZURE_GRAFANA_MCP_ENDPOINT string = '${grafana.outputs.endpoint}/api/azure-mcp'
output AZURE_GRAFANA_PRINCIPAL_ID string = grafana.outputs.systemAssignedPrincipalId

output AZURE_SRE_AGENT_ID string = sreAgent.outputs.resourceId
output AZURE_SRE_AGENT_NAME string = sreAgent.outputs.name
