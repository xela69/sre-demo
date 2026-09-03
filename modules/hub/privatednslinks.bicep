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

@description('Array of spoke virtual network resource IDs to link')
param spokeVnetIds array = [
  '/subscriptions/86d55e1e-4ca9-4ddd-85df-2e7633d77534/resourceGroups/AppsRG/providers/Microsoft.Network/virtualNetworks/AppsRG-VNet'
  '/subscriptions/8cbc59b1-7d9e-4cf1-8851-58fffe68fb79/resourceGroups/DataRG/providers/Microsoft.Network/virtualNetworks/DataRG-VNet'
]
param spokeVnetLinks bool = false

var dnsTags = {
  Service: 'DNS'
  CostCenter: 'Infrastructure'
  Environment: 'Production'
  Owner: 'ArnoldP'
  SecurityControl: 'Ignore'
  CostControl: 'Ignore'
}

// Create the private DNS zones and links via AVM.
module privateDnsZones 'br/public:avm/res/network/private-dns-zone:0.7.0' = [
  for zoneName in dnsZones: {
    name: take('pdns-${replace(zoneName, '.', '-')}', 64)
    params: {
      name: zoneName
      location: location
      tags: dnsTags
      virtualNetworkLinks: [
        for linkIndex in range(0, spokeVnetLinks ? length(spokeVnetIds) + 1 : 1): {
          name: linkIndex == 0
            ? 'link-hub-to-${replace(zoneName, '.', '-')}'
            : 'link-spoke-${linkIndex - 1}-to-${replace(zoneName, '.', '-')}'
          virtualNetworkResourceId: linkIndex == 0 ? hubVnet.id : spokeVnetIds[linkIndex - 1]
          location: 'global'
          registrationEnabled: false
          resolutionPolicy: 'NxDomainRedirect'
          tags: dnsTags
        }
      ]
    }
  }
]
// Outputs
output dnsZoneNames array = [for i in range(0, length(dnsZones)): privateDnsZones[i].outputs.name]
output hubDnsLinkNames array = [for zoneName in dnsZones: 'link-hub-to-${replace(zoneName, '.', '-')}']
output dnsZoneIds array = [for i in range(0, length(dnsZones)): privateDnsZones[i].outputs.resourceId]
