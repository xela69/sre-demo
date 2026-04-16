param appID string = take(uniqueString(resourceGroup().name), 4)
param location string
param containerAppName string = 'xela${appID}'
param containerAppEnvName string = 'xelaenv${appID}'
param acrLoginServer string
@description('Caller public IP to temporarily allow access (e.g. natPublicIP). Leave empty to skip restriction.')
param natPublicIP string = ''
@description('User-Assigned Managed Identity Resource ID')
param managedIdentityId string
@description('The image to use for the container. Defaults to public quickstart placeholder until xelatech-webapp:latest is pushed to ACR.')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart:latest'
@description('Log Analytics workspace resource ID for diagnostics.')
param logAnalyticsWorkspaceId string = ''

// ── AVM: Managed Environment ──
// https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/app/managed-environment
module containerAppEnv 'br/public:avm/res/app/managed-environment:0.13.1' = {
  name: '${containerAppEnvName}-env'
  params: {
    name: containerAppEnvName
    location: location
    tags: { SecurityControl: 'Ignore' }
    zoneRedundant: false
    // mTLS disabled; peerTrafficEncryption is a bool (default true)
    peerAuthentication: {
      mtls: { enabled: false }
    }
    peerTrafficEncryption: false
    publicNetworkAccess: 'Enabled'
    // Log Analytics integration via appLogsConfiguration
    appLogsConfiguration: empty(logAnalyticsWorkspaceId)
      ? { destination: 'azure-monitor' }
      : {
          destination: 'log-analytics'
          logAnalyticsWorkspaceResourceId: logAnalyticsWorkspaceId
        }
  }
}

// ── Diagnostic Settings on the Managed Environment (native resource — AVM 0.13.1 has no diagnosticSettings param) ──
resource existingEnv 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: containerAppEnvName
  dependsOn: [containerAppEnv]
}

resource envDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'diag-${containerAppEnvName}'
  scope: existingEnv
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

// ── AVM: Container App ──
// https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/app/container-app
module containerApp 'br/public:avm/res/app/container-app:0.22.0' = {
  name: '${containerAppName}-app'
  params: {
    name: containerAppName
    location: location
    tags: { webapp: 'containerApp', SecurityControl: 'Ignore' }

    // Managed Environment
    environmentResourceId: containerAppEnv.outputs.resourceId

    // User-assigned identity for ACR pull (no username/password)
    managedIdentities: {
      userAssignedResourceIds: [managedIdentityId]
    }

    // Ingress: external HTTP on port 80 — perimeter protected by Azure Firewall
    // WAF (App Gateway) restriction to be added once xelawafgw module is built
    ingressExternal: true
    ingressTargetPort: 80
    ingressAllowInsecure: true
    ingressTransport: 'auto'
    traffic: [
      {
        weight: 100
        latestRevision: true
      }
    ]
    ipSecurityRestrictions: empty(natPublicIP)
      ? []
      : [
          {
            name: 'AllowNatIP'
            description: 'Temporary: allow from deploy NAT IP until WAF is wired in'
            ipAddressRange: '${natPublicIP}/32'
            action: 'Allow'
          }
        ]

    // ACR pull via managed identity
    registries: [
      {
        server: acrLoginServer
        identity: managedIdentityId
      }
    ]

    // Container definition
    containers: [
      {
        name: containerAppName
        image: containerImage
        resources: {
          cpu: json('1.0')
          memory: '2.0Gi'
        }
      }
    ]

    // Scale: 0–10 replicas driven by HTTP concurrency, CPU and memory
    scaleSettings: {
      minReplicas: 0
      maxReplicas: 10
      rules: [
        {
          name: 'http-scaling-rule'
          http: {
            metadata: {
              concurrentRequests: '50'
            }
          }
        }
        {
          name: 'cpu-scaling-rule'
          custom: {
            type: 'cpu'
            metadata: {
              type: 'Utilization'
              value: '75'
            }
          }
        }
        {
          name: 'memory-scaling-rule'
          custom: {
            type: 'memory'
            metadata: {
              type: 'Utilization'
              value: '80'
            }
          }
        }
      ]
    }

    // App-level diagnostics: all logs + all metrics → Log Analytics
    diagnosticSettings: empty(logAnalyticsWorkspaceId)
      ? []
      : [
          {
            workspaceResourceId: logAnalyticsWorkspaceId
            logAnalyticsDestinationType: 'Dedicated'
            logCategoriesAndGroups: [{ categoryGroup: 'allLogs' }]
            metricCategories: [{ category: 'AllMetrics' }]
          }
        ]
  }
}

output containerAppFqdn string = containerApp.outputs.fqdn
output containerAppEnvName string = containerAppEnv.outputs.name
output containerAppResourceId string = containerApp.outputs.resourceId
