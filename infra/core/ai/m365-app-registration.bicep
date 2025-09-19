@description('Name of the Microsoft 365 app registration')
param appRegistrationName string

@description('Display name for the app registration')
param displayName string

@description('Description of the app registration')
param description string = 'Microsoft 365 RAG Agent Application'

@description('Home page URL for the app registration')
param homePageUrl string

@description('Redirect URIs for the app registration')
param redirectUris array = []

@description('Required resource access for Microsoft Graph')
param requiredResourceAccess array = [
  {
    resourceAppId: '00000003-0000-0000-c000-000000000000' // Microsoft Graph
    resourceAccess: [
      {
        id: 'e1fe6dd8-ba31-4d61-89e7-88639da4683d' // User.Read
        type: 'Scope'
      }
      {
        id: '5b567255-7703-4780-807c-7be8301ae99b' // Group.Read.All
        type: 'Role'
      }
      {
        id: '62a82d94-6d73-4d59-b170-9d70d3832abf' // Directory.Read.All
        type: 'Role'
      }
    ]
  }
]

@description('Tags to apply to the app registration')
param tags object = {}

// Note: Azure AD app registrations cannot be created via ARM/Bicep
// This module provides the configuration template and outputs
// The actual app registration must be created manually or via Azure CLI/PowerShell

var appRegistrationConfig = {
  displayName: displayName
  description: description
  homePageUrl: homePageUrl
  redirectUris: redirectUris
  requiredResourceAccess: requiredResourceAccess
  signInAudience: 'AzureADMyOrg'
  web: {
    redirectUris: redirectUris
    implicitGrantSettings: {
      enableIdTokenIssuance: false
      enableAccessTokenIssuance: false
    }
  }
  api: {
    requestedAccessTokenVersion: 2
  }
  requiredResourceAccess: requiredResourceAccess
}

output appRegistrationConfig object = appRegistrationConfig
output appRegistrationName string = appRegistrationName
output displayName string = displayName
output homePageUrl string = homePageUrl