// ── Grubify Frontend Container App ──────────────────────────────────────────
// Deploys the Grubify React/Nginx frontend as a second Container App reusing
// the existing Container App Environment in AppsRG-ContainerApp.
// The API base URL is injected via the REACT_APP_API_URL env var so the
// frontend can reach the grubify-api container app over its external FQDN.
// ─────────────────────────────────────────────────────────────────────────────

param location string
param frontendAppName string = 'grubify-frontend'

@description('Resource ID of the existing Container App Environment.')
param containerAppEnvResourceId string

@description('ACR login server (e.g. xelaacr1234.azurecr.io).')
param acrLoginServer string

@description('User-Assigned Managed Identity Resource ID for ACR pull.')
param managedIdentityId string

@description('Grubify frontend image. Defaults to quickstart until image is pushed.')
param frontendImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Public FQDN of the grubify-api container app (without https://).')
param apiUrl string = ''

@description('App Insights connection string for telemetry.')
@secure()
param appInsightsConnectionString string = ''

@description('Log Analytics workspace resource ID for diagnostics.')
param logAnalyticsWorkspaceId string = ''

// ── AVM: Grubify Frontend Container App ─────────────────────────────────────
module frontendApp 'br/public:avm/res/app/container-app:0.22.0' = {
  name: '${frontendAppName}-app'
  params: {
    name: frontendAppName
    location: location
    tags: { app: 'grubify-frontend', SecurityControl: 'Ignore' }

    environmentResourceId: containerAppEnvResourceId

    managedIdentities: {
      userAssignedResourceIds: [managedIdentityId]
    }

    // External ingress on port 80 — Nginx serves the React build
    ingressExternal: true
    ingressTargetPort: 80
    ingressAllowInsecure: true
    ingressTransport: 'auto'
    traffic: [{ weight: 100, latestRevision: true }]

    registries: [
      {
        server: acrLoginServer
        identity: managedIdentityId
      }
    ]

    containers: [
      {
        name: frontendAppName
        image: frontendImage
        resources: {
          cpu: json('0.5')
          memory: '1.0Gi'
        }
        env: concat(
          empty(apiUrl) ? [] : [{ name: 'REACT_APP_API_BASE_URL', value: 'https://${apiUrl}/api' }],
          empty(appInsightsConnectionString)
            ? []
            : [
                {
                  name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
                  secretRef: 'appinsights-connstr'
                }
              ]
        )
      }
    ]

    secrets: empty(appInsightsConnectionString)
      ? []
      : [
          {
            name: 'appinsights-connstr'
            value: appInsightsConnectionString
          }
        ]

    scaleSettings: {
      minReplicas: 0
      maxReplicas: 5
      rules: [
        {
          name: 'http-scaling-rule'
          http: { metadata: { concurrentRequests: '50' } }
        }
      ]
    }

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

output frontendFqdn string = frontendApp.outputs.fqdn
output frontendResourceId string = frontendApp.outputs.resourceId
