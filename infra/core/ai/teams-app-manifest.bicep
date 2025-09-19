@description('Name of the Teams app')
param teamsAppName string

@description('Display name of the Teams app')
param displayName string

@description('Description of the Teams app')
param description string = 'Microsoft 365 RAG Agent for Teams'

@description('Version of the Teams app')
param version string = '1.0.0'

@description('Developer information')
param developer object = {
  name: 'Your Organization'
  websiteUrl: 'https://your-organization.com'
  privacyUrl: 'https://your-organization.com/privacy'
  termsOfUseUrl: 'https://your-organization.com/terms'
}

@description('Bot configuration')
param bot object = {
  botId: ''
  isNotificationOnly: false
  supportsCalling: false
  supportsVideo: false
  supportsFiles: true
  scopes: ['personal', 'team', 'groupchat']
  commandLists: []
}

@description('Compose extensions configuration')
param composeExtensions array = []

@description('Web application info')
param webApplicationInfo object = {
  id: ''
  resource: ''
}

@description('Permissions for the Teams app')
param permissions array = [
  'identity'
  'messageTeamMembers'
]

@description('Valid domains for the Teams app')
param validDomains array = []

@description('Tags to apply to the Teams app')
param tags object = {}

// Teams app manifest configuration
var teamsAppManifest = {
  '$schema': 'https://developer.microsoft.com/en-us/json-schemas/teams/v1.16/MicrosoftTeams.schema.json'
  manifestVersion: '1.16'
  version: version
  id: bot.botId
  packageName: 'com.yourorganization.ragagent'
  developer: developer
  icons: {
    outline: 'outline.png'
    color: 'color.png'
  }
  name: {
    short: displayName
    full: displayName
  }
  description: {
    short: description
    full: description
  }
  accentColor: '#FFFFFF'
  bots: [
    {
      botId: bot.botId
      scopes: bot.scopes
      commandLists: bot.commandLists
      isNotificationOnly: bot.isNotificationOnly
      supportsCalling: bot.supportsCalling
      supportsVideo: bot.supportsVideo
      supportsFiles: bot.supportsFiles
    }
  ]
  composeExtensions: composeExtensions
  webApplicationInfo: webApplicationInfo
  permissions: permissions
  validDomains: validDomains
}

output teamsAppManifest object = teamsAppManifest
output teamsAppName string = teamsAppName
output displayName string = displayName
output version string = version