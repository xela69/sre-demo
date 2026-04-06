@description('Azure region for the identity resources.')
param location string

@description('Friendly name for the Web Application Firewall deployment.')
param wafGwName string

@description('Friendly name for the shared Key Vault.')
param keyVaultName string

@description('Friendly name for the shared App Service plan or workload.')
param appServiceName string

@description('Friendly name for the VPN gateway.')
param vpnGwName string

@description('Friendly name for the Azure Firewall.')
param firewallName string

@description('Name of the Azure Container Registry (used as-is, no "-Identity" suffix).')
param acrName string

@description('Friendly name for the shared storage account.')
param storageName string

@description('Tags applied to every managed identity created by this module.')
param commonTags object = {
  Service: 'Network'
  CostCenter: 'Infrastructure'
  Environment: 'Production'
  Owner: 'Xelatech'
  SecurityControl: 'Ignore'
}

@description('Controls which managed identities are created. Keep values true when the landing zones require the identity.')
param identityToggles object = {
  waf: true
  keyVault: true
  appService: true
  firewall: true
  storage: true
  vpnGateway: true
  acr: true
}

@description('Overall switch for deploying managed identities from this module.')
param deploy bool = true

var effectiveTags = union(
  {
    DeploymentSource: 'platform-identity'
  },
  commonTags
)

var createWaf = deploy && bool(identityToggles.waf)
var createKeyVault = deploy && bool(identityToggles.keyVault)
var createAppService = deploy && bool(identityToggles.appService)
var createFirewall = deploy && bool(identityToggles.firewall)
var createStorage = deploy && bool(identityToggles.storage)
var createVpnGateway = deploy && bool(identityToggles.vpnGateway)
var createAcr = deploy && bool(identityToggles.acr)

resource wafIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createWaf) {
  name: '${wafGwName}-Identity'
  location: location
  tags: effectiveTags
}

resource keyVaultIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createKeyVault) {
  name: '${keyVaultName}-Identity'
  location: location
  tags: effectiveTags
}

resource appServiceIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createAppService) {
  name: '${appServiceName}-Identity'
  location: location
  tags: effectiveTags
}

resource firewallIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createFirewall) {
  name: '${firewallName}-Identity'
  location: location
  tags: effectiveTags
}

resource storageIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createStorage) {
  name: '${storageName}-Identity'
  location: location
  tags: effectiveTags
}

resource vpnGatewayIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createVpnGateway) {
  name: '${vpnGwName}-Identity'
  location: location
  tags: effectiveTags
}

resource acrIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createAcr) {
  name: acrName
  location: location
  tags: effectiveTags
}

var managedIdentities = {
  waf: createWaf
    ? {
        id: wafIdentity.id
        principalId: wafIdentity.properties.principalId
      }
    : null
  firewall: createFirewall
    ? {
        id: firewallIdentity.id
        principalId: firewallIdentity.properties.principalId
      }
    : null
  storage: createStorage
    ? {
        id: storageIdentity.id
        principalId: storageIdentity.properties.principalId
      }
    : null
  keyVault: createKeyVault
    ? {
        id: keyVaultIdentity.id
        principalId: keyVaultIdentity.properties.principalId
      }
    : null
  appService: createAppService
    ? {
        id: appServiceIdentity.id
        principalId: appServiceIdentity.properties.principalId
      }
    : null
  vpnGateway: createVpnGateway
    ? {
        id: vpnGatewayIdentity.id
        principalId: vpnGatewayIdentity.properties.principalId
      }
    : null
  acr: createAcr
    ? {
        id: acrIdentity.id
        principalId: acrIdentity.properties.principalId
      }
    : null
}

output wafIdentityId string = createWaf ? wafIdentity.id : ''
output wafPrincipalId string = createWaf ? wafIdentity.properties.principalId : ''

output firewallIdentityId string = createFirewall ? firewallIdentity.id : ''
output firewallPrincipalId string = createFirewall ? firewallIdentity.properties.principalId : ''

output storageIdentityId string = createStorage ? storageIdentity.id : ''
output storagePrincipalId string = createStorage ? storageIdentity.properties.principalId : ''

output kvIdentityId string = createKeyVault ? keyVaultIdentity.id : ''
output kvPrincipalId string = createKeyVault ? keyVaultIdentity.properties.principalId : ''

output appsSvcIdentityId string = createAppService ? appServiceIdentity.id : ''
output appsSvcPrincipalId string = createAppService ? appServiceIdentity.properties.principalId : ''

output vpngwIdentityId string = createVpnGateway ? vpnGatewayIdentity.id : ''
output vpngwPrincipalId string = createVpnGateway ? vpnGatewayIdentity.properties.principalId : ''

output acrIdentityId string = createAcr ? acrIdentity.id : ''
output acrPrincipalId string = createAcr ? acrIdentity.properties.principalId : ''

output managedIdentityMap object = managedIdentities
