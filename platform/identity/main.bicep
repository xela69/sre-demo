targetScope = 'subscription'

@description('Name of the resource group that will host shared identity resources (managed identities, Key Vault, etc.).')
param identityResourceGroupName string = 'rg-platform-identity'

@description('Azure region for the shared identity resource group.')
param location string = deployment().location

@description('Toggle to deploy the managed identity set for the landing zone.')
param deployManagedIdentities bool = true

@description('Friendly names used to derive user-assigned managed identity names.')
param identityNames object = {
  waf: 'xelawafgw'
  keyVault: 'xelavault'
  appService: 'xelaweb'
  vpnGateway: 'xelavpngw'
  firewall: 'xelaAzFirewall'
  acr: 'xelaAcr'
  storage: 'xelaStorage'
}

@description('Standard tags applied to the shared identity resource group and identities.')
param identityTags object = {
  Service: 'PlatformIdentity'
  CostCenter: 'Infrastructure'
  Environment: 'Production'
  Owner: 'Xelatech'
}

@description('Granular toggles for each identity. Set values to false if a workload does not need that identity.')
param identityToggles object = {
  waf: true
  keyVault: true
  appService: true
  firewall: true
  storage: true
  vpnGateway: true
  acr: true
}

resource identityResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: identityResourceGroupName
  location: location
  tags: identityTags
}

module managedIdentities './mgnt-Identity.bicep' = if (deployManagedIdentities) {
  name: 'managedIdentities'
  scope: resourceGroup(identityResourceGroup.name)
  params: {
    location: location
    wafGwName: identityNames.waf
    keyVaultName: identityNames.keyVault
    appServiceName: identityNames.appService
    vpnGwName: identityNames.vpnGateway
    firewallName: identityNames.firewall
    acrName: identityNames.acr
    storageName: identityNames.storage
    commonTags: identityTags
    identityToggles: identityToggles
    deploy: true
  }
}

var managedIdentityMap = deployManagedIdentities ? managedIdentities.outputs.managedIdentityMap : {}

output resourceGroupName string = identityResourceGroup.name
output managedIdentities object = managedIdentityMap
