@description('Principal ID of the SRE Agent workload identity (user-assigned).')
param agentPrincipalId string

@description('Grafana instance name.')
param grafanaName string

// Built-in role definition IDs
var roles = {
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  grafanaViewer: '60921a7e-fef1-4a43-9b16-a26c52ad4769'
}

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' existing = {
  name: grafanaName
}

// Agent can discover resources in the sandbox resource group.
resource agentReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, agentPrincipalId, roles.reader)
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.reader)
  }
}

// Agent can query Grafana (the MCP data path).
resource agentGrafanaViewer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, agentPrincipalId, roles.grafanaViewer)
  scope: grafana
  properties: {
    principalId: agentPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.grafanaViewer)
  }
}
