@description('Virtual network name.')
param vnetName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('VNet address space.')
param addressPrefix string = '10.42.0.0/24'

@description('Subnet used to host private endpoints.')
param privateEndpointSubnetPrefix string = '10.42.0.0/26'

@description('Private DNS zone name for Azure Managed Grafana private endpoints.')
param grafanaPrivateDnsZoneName string = 'privatelink.grafana.azure.com'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Private DNS zone so the Grafana private endpoint resolves to its private IP.
resource grafanaZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: grafanaPrivateDnsZoneName
  location: 'global'
  tags: tags
}

resource grafanaZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: grafanaZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output vnetId string = vnet.id
output privateEndpointSubnetId string = vnet.properties.subnets[0].id
output grafanaPrivateDnsZoneId string = grafanaZone.id
