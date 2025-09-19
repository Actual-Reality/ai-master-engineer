@description('Name of the container app')
param containerAppName string

@description('Location for the container app')
param location string = resourceGroup().location

@description('Container app environment name')
param containerAppEnvironmentName string

@description('Container image')
param containerImage string

@description('Container registry server')
param containerRegistryServer string

@description('Container registry username')
param containerRegistryUsername string

@description('Container registry password')
@secure()
param containerRegistryPassword string

@description('CPU and memory configuration')
param cpuConfiguration object = {
  cpu: 0.5
  memory: '1Gi'
}

@description('Min replicas')
param minReplicas int = 1

@description('Max replicas')
param maxReplicas int = 10

@description('Environment variables')
param environmentVariables array = []

@description('Secrets')
param secrets array = []

@description('Tags to apply to the container app')
param tags object = {}

// Container app environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: ''
        sharedKey: ''
      }
    }
  }
  tags: tags
}

// Container app
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistryServer
          username: containerRegistryUsername
          passwordSecretRef: 'container-registry-password'
        }
      ]
      secrets: union(secrets, [
        {
          name: 'container-registry-password'
          value: containerRegistryPassword
        }
      ])
    }
    template: {
      containers: [
        {
          name: 'm365-agent'
          image: containerImage
          resources: {
            cpu: cpuConfiguration.cpu
            memory: cpuConfiguration.memory
          }
          env: environmentVariables
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '30'
              }
            }
          }
        ]
      }
    }
  }
  tags: tags
}

output containerAppId string = containerApp.id
output containerAppName string = containerApp.name
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppEnvironmentId string = containerAppEnvironment.id