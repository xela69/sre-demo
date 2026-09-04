targetScope = 'resourceGroup'

@description('Azure region for the TenantB source environment.')
param location string = 'westus2'

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

@description('Low-cost FortiGate VM size with two supported network interfaces. DSv4 has quota in westus2; DSv5 does not.')
param fortigateVmSize string = 'Standard_D2s_v4'

@description('FortiGate licensing model. PAYG bundles the license into hourly billing (requires a supported payment instrument); BYOL requires a Fortinet license file.')
@allowed([
  'PAYG'
  'BYOL'
])
param licenseModel string = 'PAYG'

@description('FortiGate PAYG Marketplace SKU.')
param fortigatePaygSku string = 'fortinet_fg-vm_payg_2023'

@description('FortiGate BYOL Marketplace SKU.')
param fortigateByolSku string = 'fortinet_fg-vm'

@description('Pinned FortiGate PAYG image version validated in westus2.')
param fortigatePaygVersion string = '7.4.11'

@description('Pinned FortiGate BYOL image version validated in westus2.')
param fortigateByolVersion string = '7.4.9'

@secure()
@description('FortiGate BYOL license (.lic) content. Ignored for PAYG. Leave empty for validation; supply the free-trial or paid license at deployment to activate the appliance.')
param fortigateLicenseContent string = ''

var externalSubnetPrefix = '10.61.0.0/27'
var internalSubnetPrefix = '10.61.0.32/27'
var managementSubnetPrefix = '10.61.1.0/24'
var workloadSubnetPrefix = '10.61.2.0/23'
var fortigateExternalPrivateIp = '10.61.0.4'
var fortigateInternalPrivateIp = '10.61.0.36'
var fortigateName = 'tenantb-fortigate'
var imagePublisher = 'fortinet'
var imageOffer = 'fortinet_fortigate-vm_v5'
var isPayg = licenseModel == 'PAYG'
var imageSku = isPayg ? fortigatePaygSku : fortigateByolSku
var imageVersion = isPayg ? fortigatePaygVersion : fortigateByolVersion

resource externalNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'TenantB-FortiGate-External-NSG'
  location: location
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
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'FortiGateExternalSubnet')
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
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'FortiGateInternalSubnet')
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
        version: imageVersion
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: union(
      {
        computerName: fortigateName
        adminUsername: adminUsername
        adminPassword: adminPassword
        linuxConfiguration: {
          disablePasswordAuthentication: false
        }
      },
      empty(fortigateLicenseContent) || isPayg
        ? {}
        : {
            customData: base64(fortigateLicenseContent)
          }
    )
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
