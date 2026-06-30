@description('Name of the Azure Monitor workspace (Managed Prometheus).')
param name string

@description('Name of the data collection endpoint.')
param dataCollectionEndpointName string

@description('Name of the data collection rule for Prometheus metrics.')
param dataCollectionRuleName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: name
  location: location
  tags: tags
}

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: dataCollectionEndpointName
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dataCollectionRuleName
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: [
            'Microsoft-PrometheusMetrics'
          ]
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          name: 'MonitoringAccountDestination'
          accountResourceId: monitorWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-PrometheusMetrics'
        ]
        destinations: [
          'MonitoringAccountDestination'
        ]
      }
    ]
  }
}

output resourceId string = monitorWorkspace.id
output name string = monitorWorkspace.name
output prometheusQueryEndpoint string = monitorWorkspace.properties.metrics.prometheusQueryEndpoint
output dataCollectionEndpointId string = dataCollectionEndpoint.id
output dataCollectionRuleId string = dataCollectionRule.id
