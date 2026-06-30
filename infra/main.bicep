targetScope = 'subscription'

// ============================================================================
// Minimal Azure SRE Agent + Managed Grafana sandbox.
// The SRE Agent reaches data only through Grafana's MCP endpoint, so the only
// services required are the agent, its identity, and Managed Grafana. Bring your
// own Grafana data sources (e.g. Prometheus/Loki/Tempo restored from backup).
// ============================================================================

@minLength(1)
@maxLength(32)
@description('Environment name used for deterministic resource naming.')
param environmentName string

@minLength(1)
@description('Azure region. Must be an SRE Agent-supported region (see scripts/preflight-region).')
param location string

@description('Optional resource group name. Defaults to rg-<environmentName>-sre.')
param resourceGroupName string = ''

@description('Tags applied to every resource.')
param tags object = {}

@description('Optional principal ID (user or group) granted access to USE the SRE Agent (SRE Agent Standard User). With azd this defaults to the deploying user. Empty = grant manually post-deploy.')
param agentAccessPrincipalId string = ''

@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
@description('Principal type for the SRE Agent access assignment.')
param agentAccessPrincipalType string = 'User'

// ── Naming ──────────────────────────────────────────────────────────────────

var abbrs = loadJsonContent('abbreviations.json')

var rgName = empty(resourceGroupName) ? '${abbrs.resourcesResourceGroups}${environmentName}-sre' : resourceGroupName

var names = {
  identity: '${abbrs.managedIdentityUserAssignedIdentities}${environmentName}'
  grafana: '${abbrs.dashboardGrafana}${environmentName}'
  sreAgent: '${abbrs.appAgents}${environmentName}'
}

var commonTags = union(tags, {
  'azd-env-name': environmentName
  workload: 'sre-agent-grafana'
})

// ── Resource group ──────────────────────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: commonTags
}

// ── Identity ────────────────────────────────────────────────────────────────

module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    name: names.identity
    location: location
    tags: commonTags
  }
}

// ── Managed Grafana ─────────────────────────────────────────────────────────

module grafana 'modules/grafana.bicep' = {
  name: 'grafana'
  scope: rg
  params: {
    name: names.grafana
    location: location
    tags: commonTags
  }
}

// ── SRE Agent ───────────────────────────────────────────────────────────────

module sreAgent 'modules/sreAgent.bicep' = {
  name: 'sreAgent'
  scope: rg
  params: {
    name: names.sreAgent
    location: location
    tags: commonTags
    userAssignedIdentityId: identity.outputs.resourceId
    accessPrincipalId: agentAccessPrincipalId
    accessPrincipalType: agentAccessPrincipalType
  }
}

// ── RBAC (least privilege) ──────────────────────────────────────────────────

module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  scope: rg
  params: {
    agentPrincipalId: identity.outputs.principalId
    grafanaName: names.grafana
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name

output AZURE_USER_ASSIGNED_IDENTITY_ID string = identity.outputs.resourceId
output AZURE_USER_ASSIGNED_IDENTITY_CLIENT_ID string = identity.outputs.clientId
output AZURE_USER_ASSIGNED_IDENTITY_PRINCIPAL_ID string = identity.outputs.principalId

output AZURE_GRAFANA_ID string = grafana.outputs.resourceId
output AZURE_GRAFANA_ENDPOINT string = grafana.outputs.endpoint
output AZURE_GRAFANA_MCP_ENDPOINT string = '${grafana.outputs.endpoint}/api/azure-mcp'

output AZURE_SRE_AGENT_ID string = sreAgent.outputs.resourceId
output AZURE_SRE_AGENT_NAME string = sreAgent.outputs.name
