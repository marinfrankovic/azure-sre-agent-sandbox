@description('Name of the Azure SRE Agent.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('User-assigned managed identity resource ID attached to the agent.')
param userAssignedIdentityId string

@description('Optional principal (user/group/service principal) granted access to USE the agent. Empty = skip (grant manually post-deploy).')
param accessPrincipalId string = ''

@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
@description('Principal type for the agent access assignment.')
param accessPrincipalType string = 'User'

@description('SRE Agent data-plane role to grant. Default: SRE Agent Standard User (run investigations).')
param accessRoleDefinitionId string = '2d84a65a-63b2-4343-bbb6-31105d857bc1'

// Azure SRE Agent — resource provider Microsoft.App/agents.
// Supported regions (as of 2026-01): swedencentral, uksouth, eastus2,
// australiaeast, francecentral, canadacentral, koreacentral. Region support is
// validated up front by scripts/preflight-region.
resource sreAgent 'Microsoft.App/agents@2026-01-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {}
}

// Grant a human/group access to USE the agent. The Azure SRE Agent requires a
// data-plane RBAC role (SRE Agent Reader or higher) on the agent resource —
// subscription Owner/Contributor is NOT sufficient to open the agent.
resource agentAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(accessPrincipalId)) {
  name: guid(sreAgent.id, accessPrincipalId, accessRoleDefinitionId)
  scope: sreAgent
  properties: {
    principalId: accessPrincipalId
    principalType: accessPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', accessRoleDefinitionId)
  }
}

output resourceId string = sreAgent.id
output name string = sreAgent.name
