// Description: This module creates private DNS zones and links them to the hub VNet.
// It also outputs the DNS zone names, link names, and IDs for further use.
@description('Location for Private DNS zones (always global).')
param location string = 'global'

@description('Existing hub VNet (name and RG).')
param hubVnetName string
param hubVnetResourceGroup string
@description('The name of the hub VNet')
// Reference existing hub VNet by name and resource group
resource hubVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: hubVnetName
  scope: resourceGroup(hubVnetResourceGroup)
}
// Normalize cloud-specific suffixes
var kvSuffixRaw = environment().suffixes.keyvaultDns // e.g. vaultcore.azure.net
var sqlSuffixRaw = environment().suffixes.sqlServerHostname // e.g. database.windows.net
var storageSuffix = environment().suffixes.storage // e.g. core.windows.net
var kvSuffix = startsWith(kvSuffixRaw, '.') ? substring(kvSuffixRaw, 1) : kvSuffixRaw
var sqlSuffix = startsWith(sqlSuffixRaw, '.') ? substring(sqlSuffixRaw, 1) : sqlSuffixRaw

// === Canonical Private DNS zones ===
// Docs: Private Endpoint DNS values + product docs
// Storage (incl. ADLS Gen2 + static sites), Web, Messaging, Data, Secrets, ACR, APIM, etc.
var dnsZones = [
  // Azure Storage
  'privatelink.blob.${storageSuffix}'
  'privatelink.file.${storageSuffix}'
  'privatelink.queue.${storageSuffix}'
  'privatelink.table.${storageSuffix}'
  'privatelink.dfs.${storageSuffix}'
  'privatelink.web.${storageSuffix}' // Static website endpoint

  // App Service (needs app + scm)
  'privatelink.azurewebsites.net'
  'scm.privatelink.azurewebsites.net' // Kudu/SCM

  // Messaging / integration
  'privatelink.servicebus.windows.net'
  'privatelink.eventgrid.azure.net'

  // Databases
  'privatelink.${sqlSuffix}' // Azure SQL DB
  'privatelink.mysql.database.azure.com'
  'privatelink.postgres.database.azure.com'

  // Cosmos DB (SQL + common API endpoints)
  'privatelink.documents.azure.com' // Cosmos DB for NoSQL (SQL)
  'privatelink.mongo.cosmos.azure.com' // Cosmos DB for Mongo
  'privatelink.cassandra.cosmos.azure.com' // Cosmos DB for Cassandra
  'privatelink.gremlin.cosmos.azure.com' // Cosmos DB for Gremlin
  'privatelink.table.cosmos.azure.com' // Cosmos DB Table API

  // Data factory & Synapse
  'privatelink.datafactory.azure.net'
  'privatelink.adf.azure.com' // ADF Studio portal
  'privatelink.azuresynapse.net' // Dev/Ws
  'privatelink.dev.azuresynapse.net' // Studio
  'privatelink.sql.azuresynapse.net' // Dedicated/Serverless SQL

  // Secrets & config
  'privatelink.${kvSuffix}' // Key Vault
  'privatelink.azconfig.io' // App Configuration

  // Containers & APIs
  'privatelink.azurecr.io' // ACR (override for gov/china if needed)
  'privatelink.azure-api.net' // API Management

  // AMPLS  Azure Monitor zones
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
]

// Create the private DNS zones
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zoneName in dnsZones: {
    name: zoneName
    location: location
    tags: {
      Service: 'DNS'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'ArnoldP'
      SecurityControl: 'Ignore'
    }
  }
]
// Link hubVNet to each DNS zone
resource hubDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zoneName, i) in dnsZones: {
    name: 'link-hub-to-${replace(zoneName, '.', '-')}' // stable name
    parent: privateDnsZones[i]
    location: 'global'
    tags: {
      Service: 'DNS'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'ArnoldP'
      SecurityControl: 'Ignore'
    }
    properties: {
      virtualNetwork: {
        id: hubVnet.id
      }
      registrationEnabled: false
      resolutionPolicy: 'NxDomainRedirect' // set to NxDomainRedirect to allow fallthrough to other zones
    }
  }
]
@description('Array of spoke virtual network resource IDs to link')
param spokeVnetIds array = [
  '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/AppsRG/providers/Microsoft.Network/virtualNetworks/AppsRG-VNet'
  '/subscriptions/8cbc59b1-7d9e-4cf1-8851-58fffe68fb79/resourceGroups/DataRG/providers/Microsoft.Network/virtualNetworks/DataRG-VNet'
]
param spokeVnetLinks bool = false
// Link each spoke VNet to the DNS zones
resource spokeDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for i in range(0, length(dnsZones) * length(spokeVnetIds)): if (spokeVnetLinks) {
    name: 'link-spoke-${i % length(spokeVnetIds)}-to-${replace(dnsZones[i / length(spokeVnetIds)], '.', '-')}'
    parent: privateDnsZones[i / length(spokeVnetIds)]
    location: 'global'
    tags: {
      Service: 'DNS'
      CostCenter: 'Infrastructure'
      Environment: 'Production'
      Owner: 'ArnoldP'
      SecurityControl: 'Ignore'
    }
    properties: {
      virtualNetwork: {
        id: spokeVnetIds[i % length(spokeVnetIds)]
      }
      registrationEnabled: false
      resolutionPolicy: 'NxDomainRedirect'
    }
  }
]
// Outputs
output dnsZoneNames array = [for i in range(0, length(dnsZones)): privateDnsZones[i].name]
output hubDnsLinkNames array = [for i in range(0, length(dnsZones)): hubDnsLinks[i].name]
output dnsZoneIds array = [for i in range(0, length(dnsZones)): privateDnsZones[i].id]
