targetScope = 'resourceGroup'

@description('Azure region for the shared management resources.')
param location string

@description('Name of the shared Log Analytics workspace.')
param logAnalyticsWorkspaceName string

@description('Name of the Automation Account linked to Log Analytics.')
param automationAccountName string

@description('Tags applied to the management resources.')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: tags
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2024-10-23' = {
  name: automationAccountName
  location: location
  properties: {
    sku: {
      name: 'Free'
    }
    publicNetworkAccess: true
  }
  tags: tags
}

resource linkedAutomation 'Microsoft.OperationalInsights/workspaces/linkedServices@2025-02-01' = {
  name: 'Automation'
  parent: logAnalyticsWorkspace
  properties: {
    resourceId: automationAccount.id
  }
}

output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output automationAccountId string = automationAccount.id
