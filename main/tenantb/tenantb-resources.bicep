targetScope = 'subscription'

@description('Azure region for the TenantB source environment.')
param location string = 'westus2'

@description('Resource group containing the TenantB network and FortiGate NVA.')
param resourceGroupName string = 'TenantB-Network-RG'

@description('TenantB virtual network name.')
param vnetName string = 'TenantB-VNet'

@description('TenantB address space. It must not overlap MCAPS.')
param tenantBAddressSpace string = '10.61.0.0/20'

@description('MCAPS prefixes routed through the FortiGate IPsec tunnel.')
param mcapsAddressPrefixes array = [
  '10.50.0.0/20'
  '10.52.0.0/20'
  '10.53.0.0/20'
]

@description('Public CIDRs allowed to administer FortiGate over HTTPS and SSH. Leave empty to deny public management.')
param managementSourcePrefixes array = []

@description('FortiGate administrator username.')
param adminUsername string = 'fortiadmin'

@secure()
@description('FortiGate administrator password. Supply securely at validation or deployment time.')
param adminPassword string

@description('Low-cost FortiGate VM size with two supported network interfaces.')
param fortigateVmSize string = 'Standard_D2s_v5'

@description('Pinned FortiGate PAYG image version validated in westus2.')
param fortigateImageVersion string = '7.4.11'

var externalSubnetPrefix = '10.61.0.0/27'
var internalSubnetPrefix = '10.61.0.32/27'
var managementSubnetPrefix = '10.61.1.0/24'
var workloadSubnetPrefix = '10.61.2.0/23'
var fortigateExternalPrivateIp = '10.61.0.4'
var fortigateInternalPrivateIp = '10.61.0.36'
var fortigateName = 'tenantb-fortigate'
var imagePublisher = 'fortinet'
var imageOffer = 'fortinet_fortigate-vm_v5'
var imageSku = 'fortinet_fg-vm_payg_2023'

resource networkResourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: {
    Environment: 'Lab'
    Owner: 'Xelatech'
    Service: 'TenantB source network'
    SecurityControl: 'FortiGate'
  }
}

resource externalNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'TenantB-FortiGate-External-NSG'
  location: location
  scope: networkResourceGroup
  properties: {
    securityRules: concat(
      [
        {
          name: 'Allow-IKE'
          properties: {
            priority: 100
            access: 'Allow'
            direction: 'Inbound'
            protocol: 'Udp'
            sourcePortRange: '*'
            destinationPortRange: '500'
            sourceAddressPrefix: 'Internet'
            destinationAddressPrefix: '*'
          }
        }
        {
          name: 'Allow-IPsec-NATT'
          properties: {
            priority: 110
            access: 'Allow'
            direction: 'Inbound'
            protocol: 'Udp'
            sourcePortRange: '*'
            destinationPortRange: '4500'
            sourceAddressPrefix: 'Internet'
            destinationAddressPrefix: '*'
          }
        }
      ],
      empty(managementSourcePrefixes)
        ? []
        : [
            {
              name: 'Allow-Restricted-Management'
              properties: {
                priority: 120
                access: 'Allow'
                direction: 'Inbound'
                protocol: 'Tcp'
                sourcePortRange: '*'
                destinationPortRanges: [
                  '22'
                  '443'
                ]
                sourceAddressPrefixes: managementSourcePrefixes
                destinationAddressPrefix: '*'
              }
            }
          ]
    )
  }
}

resource internalNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'TenantB-Internal-NSG'
  location: location
  scope: networkResourceGroup
  properties: {
    securityRules: [
      {
        name: 'Allow-TenantB-VNet'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
    ]
  }
}

resource workloadRouteTable 'Microsoft.Network/routeTables@2024-05-01' = {
  name: 'TenantB-Workload-RT'
  location: location
  scope: networkResourceGroup
  properties: {
    disableBgpRoutePropagation: true
    routes: [
      for (prefix, index) in mcapsAddressPrefixes: {
        name: 'To-MCAPS-${index}'
        properties: {
          addressPrefix: prefix
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: fortigateInternalPrivateIp
        }
      }
    ]
  }
}

resource tenantBVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  scope: networkResourceGroup
  properties: {
    addressSpace: {
      addressPrefixes: [tenantBAddressSpace]
    }
    subnets: [
      {
        name: 'FortiGateExternalSubnet'
        properties: {
          addressPrefix: externalSubnetPrefix
          networkSecurityGroup: {
            id: externalNsg.id
          }
        }
      }
      {
        name: 'FortiGateInternalSubnet'
        properties: {
          addressPrefix: internalSubnetPrefix
          networkSecurityGroup: {
            id: internalNsg.id
          }
        }
      }
      {
        name: 'ManagementSubnet'
        properties: {
          addressPrefix: managementSubnetPrefix
          networkSecurityGroup: {
            id: internalNsg.id
          }
        }
      }
      {
        name: 'SourceWorkloadSubnet'
        properties: {
          addressPrefix: workloadSubnetPrefix
          networkSecurityGroup: {
            id: internalNsg.id
          }
          routeTable: {
            id: workloadRouteTable.id
          }
        }
      }
    ]
  }
}

resource fortigatePublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'TenantB-FortiGate-PIP'
  location: location
  scope: networkResourceGroup
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
  tags: {
    Environment: 'Lab'
    Service: 'TenantB VPN endpoint'
  }
}

resource fortigateExternalNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${fortigateName}-external-nic'
  location: location
  scope: networkResourceGroup
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'external-ipconfig'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Static'
          privateIPAddress: fortigateExternalPrivateIp
          subnet: {
            id: resourceId(
              resourceGroupName,
              'Microsoft.Network/virtualNetworks/subnets',
              vnetName,
              'FortiGateExternalSubnet'
            )
          }
          publicIPAddress: {
            id: fortigatePublicIp.id
          }
        }
      }
    ]
  }
  dependsOn: [tenantBVnet]
}

resource fortigateInternalNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${fortigateName}-internal-nic'
  location: location
  scope: networkResourceGroup
  properties: {
    enableIPForwarding: true
    ipConfigurations: [
      {
        name: 'internal-ipconfig'
        properties: {
          primary: true
          privateIPAllocationMethod: 'Static'
          privateIPAddress: fortigateInternalPrivateIp
          subnet: {
            id: resourceId(
              resourceGroupName,
              'Microsoft.Network/virtualNetworks/subnets',
              vnetName,
              'FortiGateInternalSubnet'
            )
          }
        }
      }
    ]
  }
  dependsOn: [tenantBVnet]
}

resource fortigateVm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: fortigateName
  location: location
  scope: networkResourceGroup
  plan: {
    name: imageSku
    product: imageOffer
    publisher: imagePublisher
  }
  properties: {
    hardwareProfile: {
      vmSize: fortigateVmSize
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: fortigateImageVersion
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: fortigateName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: fortigateExternalNic.id
          properties: {
            primary: true
          }
        }
        {
          id: fortigateInternalNic.id
          properties: {
            primary: false
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
  tags: {
    Environment: 'Lab'
    Owner: 'Xelatech'
    Service: 'TenantB VPN endpoint'
  }
}

output tenantBFortigatePublicIp string = fortigatePublicIp.properties.ipAddress
output tenantBAddressPrefixes array = [tenantBAddressSpace]
output fortigateInternalPrivateIp string = fortigateInternalPrivateIp
output mcapsAddressPrefixes array = mcapsAddressPrefixes
output fortigateResourceId string = fortigateVm.id
