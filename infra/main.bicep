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

@description('Deploy a VNet, Private DNS zone, and a private endpoint for Grafana (everything that supports Private Link). Recommended for security-conscious customers.')
param enablePrivateNetworking bool = true

@allowed([
  'Enabled'
  'Disabled'
])
@description('Grafana public network access when private networking is enabled. Default Disabled = private-endpoint-only. NOTE: the Azure SRE Agent is a Microsoft-managed service; if it cannot reach a private Grafana, set this to Enabled (a private endpoint is still created for admins/data paths). Ignored when enablePrivateNetworking is false (forced Enabled).')
param grafanaPublicNetworkAccess string = 'Disabled'

@description('Address space for the deployed VNet (only used when enablePrivateNetworking is true).')
param vnetAddressPrefix string = '10.42.0.0/24'

@description('Subnet prefix that hosts private endpoints (only used when enablePrivateNetworking is true).')
param privateEndpointSubnetPrefix string = '10.42.0.0/26'

// ── Naming ──────────────────────────────────────────────────────────────────

var abbrs = loadJsonContent('abbreviations.json')

var rgName = empty(resourceGroupName) ? '${abbrs.resourcesResourceGroups}${environmentName}-sre' : resourceGroupName

var names = {
  identity: '${abbrs.managedIdentityUserAssignedIdentities}${environmentName}'
  grafana: '${abbrs.dashboardGrafana}${environmentName}'
  sreAgent: '${abbrs.appAgents}${environmentName}'
  vnet: '${abbrs.networkVirtualNetworks}${environmentName}'
  grafanaPrivateEndpoint: '${abbrs.networkPrivateEndpoints}${environmentName}-grafana'
}

// When private networking is off, Grafana must stay publicly reachable.
var effectiveGrafanaPublicAccess = enablePrivateNetworking ? grafanaPublicNetworkAccess : 'Enabled'

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
    publicNetworkAccess: effectiveGrafanaPublicAccess
  }
}

// ── Private networking (VNet + Private DNS + Grafana private endpoint) ───────

module network 'modules/network.bicep' = if (enablePrivateNetworking) {
  name: 'network'
  scope: rg
  params: {
    vnetName: names.vnet
    location: location
    tags: commonTags
    addressPrefix: vnetAddressPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
  }
}

module grafanaPrivateEndpoint 'modules/privateEndpoints.bicep' = if (enablePrivateNetworking) {
  name: 'grafanaPrivateEndpoint'
  scope: rg
  params: {
    name: names.grafanaPrivateEndpoint
    location: location
    tags: commonTags
    grafanaId: grafana.outputs.resourceId
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    grafanaPrivateDnsZoneId: network.outputs.grafanaPrivateDnsZoneId
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
output AZURE_GRAFANA_PUBLIC_NETWORK_ACCESS string = effectiveGrafanaPublicAccess

output AZURE_PRIVATE_NETWORKING_ENABLED bool = enablePrivateNetworking
output AZURE_VNET_ID string = enablePrivateNetworking ? network.outputs.vnetId : ''

output AZURE_SRE_AGENT_ID string = sreAgent.outputs.resourceId
output AZURE_SRE_AGENT_NAME string = sreAgent.outputs.name
