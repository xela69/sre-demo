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

@description('FortiGate Marketplace plan/SKU. BYOL is compatible with the TenantB Visual Studio subscription.')
param fortigateImageSku string = 'fortinet_fg-vm'

@description('Pinned FortiGate image version validated in westus2 for the selected SKU.')
param fortigateImageVersion string = '7.4.9'

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

module tenantBResources './tenantb-resources.bicep' = {
  name: 'tenantb-resources'
  scope: resourceGroup(networkResourceGroup.name)
  params: {
    location: location
    vnetName: vnetName
    tenantBAddressSpace: tenantBAddressSpace
    mcapsAddressPrefixes: mcapsAddressPrefixes
    managementSourcePrefixes: managementSourcePrefixes
    adminUsername: adminUsername
    adminPassword: adminPassword
    fortigateVmSize: fortigateVmSize
    fortigateImageSku: fortigateImageSku
    fortigateImageVersion: fortigateImageVersion
  }
}

output tenantBFortigatePublicIp string = tenantBResources.outputs.tenantBFortigatePublicIp
output tenantBAddressPrefixes array = tenantBResources.outputs.tenantBAddressPrefixes
output fortigateInternalPrivateIp string = tenantBResources.outputs.fortigateInternalPrivateIp
output mcapsAddressPrefixes array = tenantBResources.outputs.mcapsAddressPrefixes
output fortigateResourceId string = tenantBResources.outputs.fortigateResourceId
