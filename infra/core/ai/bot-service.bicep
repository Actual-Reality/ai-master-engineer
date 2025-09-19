@description('Name of the bot service')
param botServiceName string

@description('Location for the bot service')
param location string = resourceGroup().location

@description('SKU for the bot service')
@allowed(['F0', 'S1'])
param skuName string = 'F0'

@description('Microsoft App ID for the bot')
param microsoftAppId string

@description('Microsoft App Password for the bot')
@secure()
param microsoftAppPassword string

@description('Endpoint URL for the bot')
param endpoint string

@description('Description of the bot')
param description string = 'Microsoft 365 RAG Agent Bot'

@description('Display name of the bot')
param displayName string = 'RAG Agent Bot'

@description('Icon URL for the bot')
param iconUrl string = ''

@description('Tags to apply to the bot service')
param tags object = {}

resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botServiceName
  location: 'global'
  kind: 'sdk'
  sku: {
    name: skuName
  }
  properties: {
    displayName: displayName
    description: description
    iconUrl: iconUrl
    endpoint: endpoint
    msaAppId: microsoftAppId
    msaAppPassword: microsoftAppPassword
    developerAppInsightKey: ''
    developerAppInsightsApiKey: ''
    developerAppInsightsApplicationId: ''
    luisAppIds: []
    luisKey: ''
    isCmekEnabled: false
    cmekKeyVaultUrl: ''
    isStreamingSupported: false
    disableLocalAuth: false
    schemaTransformationVersion: ''
    storageResourceId: ''
    publicNetworkAccess: 'Enabled'
    isIsolated: false
    tenantId: subscription().tenantId
  }
  tags: tags
}

output botServiceId string = botService.id
output botServiceName string = botService.name
output botServiceEndpoint string = botService.properties.endpoint
output botServiceAppId string = botService.properties.msaAppId