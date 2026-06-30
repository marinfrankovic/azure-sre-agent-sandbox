@description('Private endpoint name.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Resource ID of the Managed Grafana instance to expose privately.')
param grafanaId string

@description('Subnet resource ID that hosts the private endpoint.')
param privateEndpointSubnetId string

@description('Private DNS zone resource ID for privatelink.grafana.azure.com.')
param grafanaPrivateDnsZoneId string

resource grafanaPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-grafana'
        properties: {
          privateLinkServiceId: grafanaId
          groupIds: [
            'grafana'
          ]
        }
      }
    ]
  }
}

resource grafanaDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: grafanaPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'grafana'
        properties: {
          privateDnsZoneId: grafanaPrivateDnsZoneId
        }
      }
    ]
  }
}

output privateEndpointId string = grafanaPrivateEndpoint.id
