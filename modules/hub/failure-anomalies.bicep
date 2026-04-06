// failure-anomalies.bicep — Failure Anomalies smart detector alert rule for App Insights
// Requires: Microsoft.AlertsManagement provider registered on the subscription

param appInsightsId string
param appInsightsName string

resource failureAnomaliesRule 'microsoft.alertsmanagement/smartdetectoralertrules@2021-04-01' = {
  name: 'failure anomalies - ${appInsightsName}'
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
      appInsightsId
    ]
    actionGroups: {
      groupIds: []
    }
  }
}
