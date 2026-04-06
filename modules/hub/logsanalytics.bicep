@description('Name of the Application Insights resource.')
param appInsightName string = 'xelaAppsInsight${take(uniqueString(resourceGroup().id), 4)}'
@description('Name of the Log Analytics Workspace.')
param logAnalyticsWorkspaceName string = 'xelaLogs${take(uniqueString(resourceGroup().id), 4)}'
param location string
@description('Retention period for logs in Log Analytics (in days).')
param retentionInDays int

// --- Hardening & cost guardrails ---
@description('Disable shared keys; require Entra ID/RBAC for workspace.')
param workspaceDisableLocalAuth bool = true

@description('Daily GB cap; 0 = unlimited. Set >0 to cap ingestion during tests/incidents.')
@minValue(0)
param workspaceDailyQuotaGb int = 0

@allowed(['Enabled', 'Disabled'])
@description('Public network access for ingestion.')
param laPublicNetworkAccessForIngestion string = 'Enabled'

@allowed(['Enabled', 'Disabled'])
@description('Public network access for query.')
param laPublicNetworkAccessForQuery string = 'Enabled'

// App Insights options (workspace-based)
@description('Disable local auth/keys for the AI component.')
param appInsightsDisableLocalAuth bool = true

@description('Only enable if you want to export AI logs to a different destination; otherwise it can duplicate data when AI is workspace-based.')
param enableAppInsightsDiagExport bool = false

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: {
    Service: 'Logs'
    SecurityControl: 'Ignore'
  }
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    publicNetworkAccessForIngestion: laPublicNetworkAccessForIngestion
    publicNetworkAccessForQuery: laPublicNetworkAccessForQuery
    features: {
      disableLocalAuth: workspaceDisableLocalAuth
      enableLogAccessUsingOnlyResourcePermissions: true
      // immediatePurgeDataOn30Days: false // optional
    }
    workspaceCapping: workspaceDailyQuotaGb > 0
      ? {
          dailyQuotaGb: workspaceDailyQuotaGb
        }
      : null
  }
}
// ------------------ APPLICATION INSIGHTS (workspace-based) ------------------
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightName
  location: location
  tags: {
    Service: 'Applications'
    SecurityControl: 'Ignore'
  }
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: appInsightsDisableLocalAuth
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}
// (Optional) Smart Detection rule example
resource proactiveDetection 'Microsoft.Insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  name: 'longdependencyduration'
  parent: appInsights
  location: location
  properties: {
    ruleDefinitions: {
      Name: 'longdependencyduration'
      DisplayName: 'Long dependency duration'
      Description: 'Smart Detection rules notify you of performance anomaly issues.'
      IsHidden: false
      IsEnabledByDefault: true
      IsInPreview: false
      SupportsEmailNotifications: true
    }
    enabled: true
    sendEmailsToSubscriptionOwners: true
    customEmails: []
  }
}

// Failure Anomalies smart detector alert rule (requires Microsoft.AlertsManagement provider)
resource failureAnomaliesRule 'microsoft.alertsmanagement/smartdetectoralertrules@2021-04-01' = {
  name: 'failure anomalies - ${appInsightName}'
  location: 'global'
  properties: {
    description: 'Failure Anomalies notifies you of an unusual rise in the rate of failed HTTP requests or dependency calls.'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'PT1M'
    detector: {
      id: 'FailureAnomaliesDetector'
    }
    scope: [
      appInsights.id
    ]
    actionGroups: {
      groupIds: []
    }
  }
}
// ------------------ DIAGNOSTIC SETTINGS ------------------
// NOTE: When AI is workspace-based, sending these categories to the SAME workspace
// via diag settings will DUPLICATE data. Keep this gated.
param diagAppSettingName string = 'xelaDiagnostics'
resource diagAppSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableAppInsightsDiagExport) {
  name: diagAppSettingName
  scope: appInsights
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      { category: 'AppRequests', enabled: true }
      { category: 'AppDependencies', enabled: true }
      { category: 'AppExceptions', enabled: true }
      { category: 'AppTraces', enabled: true }
      { category: 'AppMetrics', enabled: true }
    ]
  }
}

// Workspace diagnostics: use AllLogs (Audit is included)
param diagLogsSettingName string = 'diagLogs'
resource diagSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagLogsSettingName
  scope: logAnalyticsWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'AllLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

/*/ Future implementation of AMPLS for PrivateEP
@description('Name of the Azure Monitor Private Link Scope')
param amplsName string = 'ampls-${uniqueString(resourceGroup().id)}'

@description('Subnet ID for the AMPLS Private Endpoint (e.g., hub privateEPSubnet)')
param privateEndpointSubnetId string = 'privateEPSubnetID'. //call privateEP subnet from vnet module

@description('Link the required Private DNS zones to this VNet (hub VNet recommended)')
param hubVnetId string = 'hubVnetID'

@description('Include Application Insights association')
param includeAppInsights bool = false
@description('Create the 5 Azure Monitor Private DNS zones and link them to the VNet')
param createPrivateDnsZones bool = false

// ---------- AMPLS ----------
resource ampls 'Microsoft.Insights/privateLinkScopes@2023-06-01-preview' = if (createPrivateDnsZones){
  name: amplsName
  location: location
  tags: { Service: 'Monitoring' }
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

// Scope LA workspace to AMPLS
resource amplsLa 'Microsoft.Insights/privateLinkScopes/scopedResources@2023-06-01-preview' = if (createPrivateDnsZones) {
  name: 'la-${take(uniqueString(logAnalyticsWorkspace.id), 8)}'
  parent: ampls
  properties: {
    linkedResourceId: logAnalyticsWorkspace.id
  }
}

// Scope App Insights to AMPLS (optional)
resource amplsAi 'Microsoft.Insights/privateLinkScopes/scopedResources@2023-06-01-preview' = if (includeAppInsights && !empty(appInsights.id)) {
  name: 'ai-${take(uniqueString(appInsights.id), 8)}'
  parent: ampls
  properties: {
    linkedResourceId: appInsights.id
  }
}

// ---------- Private Endpoint to AMPLS ----------
resource amplsPe 'Microsoft.Network/privateEndpoints@2024-07-01' = if (createPrivateDnsZones) {
  name: '${amplsName}-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'ampls-azuremonitor'
        properties: {
          privateLinkServiceId: ampls.id
          groupIds: [ 'azuremonitor' ]
          requestMessage: 'Private access to Azure Monitor via AMPLS'
        }
      }
    ]
  }
}

// ---------- Private DNS zones (optional but recommended) ----------
var monitorDnsZones = createPrivateDnsZones ? [
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
  'privatelink.blob.${environment().suffixes.storage}'
] : []

// Create the zones (global) and link to hub VNet (no auto-registration)
resource privateMonitorZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zone in monitorDnsZones: if (createPrivateDnsZones) {
  name: zone
  location: 'global'
}]
// Link each zone to the hub VNet
resource privateZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for zone in monitorDnsZones: if (createPrivateDnsZones) {
  name: '${zone}/hubvnet-link'
  properties: {
    virtualNetwork: {
      id: hubVnetId
    }
    registrationEnabled: false
  }
  dependsOn: [
    privateMonitorZones
  ]
}]

// Attach all zones to the Private Endpoint so A-records auto-populate
resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = if (createPrivateDnsZones) {
  name: 'ampls-dnszones'
  parent: amplsPe
  properties: {
    privateDnsZoneConfigs: [for zone in monitorDnsZones: {
      name: replace(zone, '.', '-')
      properties: {
        privateDnsZoneId: resourceId('Microsoft.Network/privateDnsZones', zone)
      }
    }]
  }
  dependsOn: [
    privateZoneLink
  ]
}

// ---------- Outputs ----------
output amplsId string = ampls.id
output amplsPeIp string = last(amplsPe.properties.networkInterfaces).id*/
// ------------------ OUTPUTS ------------------
output logAnalyticsId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output appInsightsId string = appInsights.id
