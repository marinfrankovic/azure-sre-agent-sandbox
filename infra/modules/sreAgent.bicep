@description('Name of the Azure SRE Agent.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('User-assigned managed identity resource ID attached to the agent.')
param userAssignedIdentityId string

// Azure SRE Agent (preview) — resource provider Microsoft.App/agents.
// The preview type may not yet be present in the local Bicep type index
// (a BCP081 warning is expected). Confirm the latest API version before deploy:
// https://learn.microsoft.com/azure/sre-agent/deploy-iac
resource sreAgent 'Microsoft.App/agents@2025-06-01-preview' = {
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
