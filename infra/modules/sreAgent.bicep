@description('Name of the Azure SRE Agent.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('User-assigned managed identity resource ID attached to the agent.')
param userAssignedIdentityId string

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

output resourceId string = sreAgent.id
output name string = sreAgent.name
