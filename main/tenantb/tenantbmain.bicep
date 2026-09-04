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

@description('FortiGate licensing model. PAYG bundles the license into hourly billing (requires a supported payment instrument); BYOL requires a Fortinet license file.')
@allowed([
  'PAYG'
  'BYOL'
])
param licenseModel string = 'PAYG'

@secure()
@description('FortiGate BYOL license (.lic) content. Ignored for PAYG. Leave empty for validation; supply the free-trial or paid license at deployment to activate the appliance.')
param fortigateLicenseContent string = ''

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
    licenseModel: licenseModel
    fortigateLicenseContent: fortigateLicenseContent
  }
}

output tenantBFortigatePublicIp string = tenantBResources.outputs.tenantBFortigatePublicIp
output tenantBAddressPrefixes array = tenantBResources.outputs.tenantBAddressPrefixes
output fortigateInternalPrivateIp string = tenantBResources.outputs.fortigateInternalPrivateIp
output mcapsAddressPrefixes array = tenantBResources.outputs.mcapsAddressPrefixes
output fortigateResourceId string = tenantBResources.outputs.fortigateResourceId
