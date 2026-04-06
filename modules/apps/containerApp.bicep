param appID string = take(uniqueString(resourceGroup().name), 4)
param location string
param containerAppName string = 'xela${appID}'
param containerAppEnvName string = 'xelaenv${appID}'
param acrLoginServer string
param publicIP string 
@description('User-Assigned Managed Identity Resource ID')
param managedIdentityId string
@description('The image to use for the container')
param containerImage string = '${acrLoginServer}/xelatech-webapp:latest'
//param customDomain string = 'xelatech.net' param certificateName string = 'xelatech.net-cert'
// Managed Environment for the Container App
/*customDomains: [
  {
    name: customDomain
    certificateId: resourceId(
      'Microsoft.App/managedEnvironments/managedCertificates',
      containerAppEnvName,
      certificateName
    )
    bindingType: 'SniEnabled'
  }
]*/
resource containerAppEnv 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: containerAppEnvName
  location: location
  properties: {
    peerAuthentication: {
      mtls: {
        enabled: false
      }
    }
    peerTrafficConfiguration: {
      encryption: {
        enabled: false
      }
    }
  }
}
// Container App resource definition
resource containerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: containerAppName
  location: location
  tags: {
    webapp: 'containerApp'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  } // managed ID rather than user/pwd
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: true
        transport: 'auto' // 'auto' for HTTP/HTTPS, 'http' for HTTP only, 'https' for HTTPS only
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
        ipSecurityRestrictions: [
          {
            name: 'WafSubnet'
            description: 'WAF Subnet'
            ipAddressRange:  '${publicIP}/32'  //'10.1.3.0/27' waf subnet
            action: 'Allow'
          }
        ]
      }
      registries: [
        {
          server: acrLoginServer
          identity: managedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: containerImage
          resources: {
            cpu: 1 // 1 vCPU (use 2 for 2 vCPUs)
            memory: '2.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 10
        rules: [
          {
            name: 'http-scaling-rule'
            http: {
              metadata: {
                concurrentRequests: '50' // Maximum concurrent HTTP requests per instance before scaling up
              }
            }
          }
          {
            name: 'cpu-memory-scaling-rule'
            custom: {
              type: 'cpu'
              metadata: {
                value: '75' // Scale when CPU utilization exceeds 75%
              }
            }
          }
          {
            name: 'memory-scaling-rule'
            custom: {
              type: 'memory'
              metadata: {
                value: '80' // Scale when memory utilization exceeds 80%
              }
            }
          }
        ]
      }
    }
  }
}

// output principalId string = containerApp.identity.principalId
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
output containerAppEnvName string = containerAppEnv.name
