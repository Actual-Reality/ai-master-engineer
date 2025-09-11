#!/bin/bash

# Teams Bot Deployment Script
# This script creates Azure resources and deploys the Teams bot

set -e

# Configuration variables
RESOURCE_GROUP="rg-teams-search-bot"
LOCATION="eastus"
BOT_NAME="teams-search-bot"
APP_SERVICE_PLAN="asp-teams-search-bot"
WEB_APP_NAME="teams-search-bot-$(date +%s)"  # Add timestamp for uniqueness
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "🚀 Starting Teams Bot deployment..."
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Bot Name: $BOT_NAME"
echo "Web App: $WEB_APP_NAME"

# Step 1: Create resource group
echo "📦 Creating resource group..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Step 2: Create Microsoft Entra ID app registration
echo "🔐 Creating Entra ID app registration..."
APP_REGISTRATION=$(az ad app create \
  --display-name "TeamsSearchBot" \
  --sign-in-audience "AzureADMyOrg" \
  --query "appId" -o tsv)

echo "App ID: $APP_REGISTRATION"

# Step 3: Create client secret
echo "🔑 Creating client secret..."
CLIENT_SECRET=$(az ad app credential reset \
  --id "$APP_REGISTRATION" \
  --query "password" -o tsv)

echo "Client secret created (will be used in app settings)"

# Step 4: Create App Service Plan
echo "📋 Creating App Service Plan..."
az appservice plan create \
  --name "$APP_SERVICE_PLAN" \
  --resource-group "$RESOURCE_GROUP" \
  --sku F1 \
  --is-linux

# Step 5: Create Web App
echo "🌐 Creating Web App..."
az webapp create \
  --resource-group "$RESOURCE_GROUP" \
  --plan "$APP_SERVICE_PLAN" \
  --name "$WEB_APP_NAME" \
  --runtime "PYTHON:3.11" \
  --deployment-local-git

# Get the web app URL
WEB_APP_URL="https://$WEB_APP_NAME.azurewebsites.net"
echo "Web App URL: $WEB_APP_URL"

# Step 6: Configure app settings
echo "⚙️  Configuring app settings..."

# Get the existing RAG backend URL from environment or parameters
if [ -f "../.env" ]; then
  source ../.env
fi

# Try to get backend service name from parameters or environment
BACKEND_SERVICE_NAME="${AZURE_APP_SERVICE:-$(cat ../infra/main.parameters.json | jq -r '.parameters.backendServiceName.value // "your-backend-url"' 2>/dev/null || echo "your-backend-url")}"

if [ "$BACKEND_SERVICE_NAME" != "your-backend-url" ] && [ "$BACKEND_SERVICE_NAME" != "\${AZURE_APP_SERVICE}" ]; then
  RAG_BACKEND_URL="https://$BACKEND_SERVICE_NAME.azurewebsites.net"
  echo "✅ Found existing backend service: $RAG_BACKEND_URL"
else
  RAG_BACKEND_URL="http://localhost:50505"
  echo "⚠️  Warning: Could not determine backend URL. Using localhost. Update RAG_BACKEND_URL in app settings after deployment."
  echo "    You can find your backend URL in the Azure portal or .env file"
fi

az webapp config appsettings set \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --settings \
    MicrosoftAppId="$APP_REGISTRATION" \
    MicrosoftAppPassword="$CLIENT_SECRET" \
    MicrosoftAppType="MultiTenant" \
    RAG_BACKEND_URL="$RAG_BACKEND_URL"

# Step 7: Create Azure Bot resource
echo "🤖 Creating Azure Bot resource..."
az bot create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BOT_NAME" \
  --appid "$APP_REGISTRATION" \
  --password "$CLIENT_SECRET" \
  --endpoint "$WEB_APP_URL/api/messages"

# Step 8: Enable Teams channel
echo "📱 Enabling Teams channel..."
az bot teams-channel create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BOT_NAME"

# Step 9: Get deployment credentials
echo "📤 Getting deployment credentials..."
DEPLOYMENT_URL=$(az webapp deployment source config-local-git \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WEB_APP_NAME" \
  --query "url" -o tsv)

echo "
✅ Azure resources created successfully!

📋 Deployment Summary:
- Resource Group: $RESOURCE_GROUP
- Bot Name: $BOT_NAME
- Web App: $WEB_APP_NAME
- App ID: $APP_REGISTRATION
- Web App URL: $WEB_APP_URL
- Git Deployment URL: $DEPLOYMENT_URL

🚀 Next Steps:
1. Deploy code: git remote add azure $DEPLOYMENT_URL
2. Push code: git add . && git commit -m 'Deploy Teams bot' && git push azure main
3. Create Teams app manifest with App ID: $APP_REGISTRATION
4. Test bot in Teams

📝 Important Notes:
- Client secret is configured in app settings
- Teams channel is enabled
- RAG backend URL: $RAG_BACKEND_URL
- Update RAG_BACKEND_URL if needed in Azure portal app settings
"
