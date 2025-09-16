#!/bin/bash

# Comprehensive Bot Framework Authentication Debugging
# Deep dive into authentication issues

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
RESOURCE_GROUP="rg-ai-master-engineer"
CONTAINER_APP_NAME="teams-search-bot-capp"
BOT_NAME="ssoe-teams-bot"
APP_ID="93221cd2-29ca-47fb-a025-b1a3a7d8a9d6"

echo -e "${BLUE}🔍 Comprehensive Bot Authentication Debugging${NC}"
echo "============================================="
echo ""

# Get tenant and subscription info
TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
ACCOUNT_NAME=$(az account show --query user.name -o tsv)

echo -e "${BLUE}📋 Environment Information:${NC}"
echo "Tenant ID: $TENANT_ID"
echo "Subscription ID: $SUBSCRIPTION_ID"
echo "Account: $ACCOUNT_NAME"
echo ""

# Check app registration in detail
echo -e "${BLUE}🔍 Detailed App Registration Analysis:${NC}"
APP_DETAILS=$(az ad app show --id "$APP_ID" 2>/dev/null || echo "NOT_FOUND")

if [ "$APP_DETAILS" = "NOT_FOUND" ]; then
    echo -e "${RED}❌ CRITICAL: App registration not found!${NC}"
    echo "This explains the authentication error."
    
    # List available apps to find alternatives
    echo ""
    echo -e "${BLUE}Available app registrations:${NC}"
    az ad app list --query "[?contains(displayName, 'Teams') || contains(displayName, 'Bot')].{Name:displayName, AppId:appId, Created:createdDateTime}" --output table
    
    exit 1
else
    echo -e "${GREEN}✅ App registration found${NC}"
    
    # Extract key details
    APP_NAME=$(echo "$APP_DETAILS" | jq -r '.displayName')
    SIGN_IN_AUDIENCE=$(echo "$APP_DETAILS" | jq -r '.signInAudience')
    CREATED_DATE=$(echo "$APP_DETAILS" | jq -r '.createdDateTime')
    
    echo "App Name: $APP_NAME"
    echo "Sign-in Audience: $SIGN_IN_AUDIENCE"
    echo "Created: $CREATED_DATE"
    
    # Check redirect URIs
    REDIRECT_URIS=$(echo "$APP_DETAILS" | jq -r '.web.redirectUris[]?' 2>/dev/null || echo "None")
    echo "Redirect URIs: $REDIRECT_URIS"
    
    # Check if app has secrets
    SECRETS=$(az ad app credential list --id "$APP_ID" --query "length(@)" -o tsv)
    echo "Number of secrets: $SECRETS"
    
    if [ "$SECRETS" = "0" ]; then
        echo -e "${RED}❌ No client secrets found!${NC}"
    else
        echo -e "${GREEN}✅ Client secrets exist${NC}"
        
        # Check secret expiration
        SECRET_INFO=$(az ad app credential list --id "$APP_ID" --query "[].{DisplayName:displayName, Expires:endDateTime}" --output table)
        echo ""
        echo "Secret details:"
        echo "$SECRET_INFO"
    fi
fi

echo ""

# Check service principal
echo -e "${BLUE}🔍 Service Principal Analysis:${NC}"
SP_EXISTS=$(az ad sp show --id "$APP_ID" 2>/dev/null || echo "NOT_FOUND")

if [ "$SP_EXISTS" = "NOT_FOUND" ]; then
    echo -e "${YELLOW}⚠️ Service principal not found${NC}"
    echo "Creating service principal for the app..."
    
    SP_CREATE_RESULT=$(az ad sp create --id "$APP_ID" 2>/dev/null || echo "FAILED")
    
    if [ "$SP_CREATE_RESULT" = "FAILED" ]; then
        echo -e "${RED}❌ Failed to create service principal${NC}"
    else
        echo -e "${GREEN}✅ Service principal created${NC}"
    fi
else
    echo -e "${GREEN}✅ Service principal exists${NC}"
    SP_OBJECT_ID=$(echo "$SP_EXISTS" | jq -r '.id')
    echo "Service Principal Object ID: $SP_OBJECT_ID"
fi

echo ""

# Check current container app configuration in detail
echo -e "${BLUE}📱 Container App Configuration Analysis:${NC}"
CURRENT_ENV=$(az containerapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP_NAME" \
    --query "properties.template.containers[0].env" -o json)

echo "Environment Variables:"
echo "$CURRENT_ENV" | jq -r '.[] | "\(.name): \(if .value then "SET" else if .secretRef then "SECRET" else "EMPTY" end)"'

# Check if secrets are properly configured
CURRENT_SECRETS=$(az containerapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP_NAME" \
    --query "properties.configuration.secrets[].name" -o tsv)

echo ""
echo "Container App Secrets:"
if [ -n "$CURRENT_SECRETS" ]; then
    echo "$CURRENT_SECRETS" | while read -r secret; do
        echo "  - $secret"
    done
else
    echo "  No secrets configured"
fi

echo ""

# Check bot service configuration
echo -e "${BLUE}🤖 Bot Service Configuration Analysis:${NC}"
BOT_INFO=$(az bot show --resource-group "$RESOURCE_GROUP" --name "$BOT_NAME" 2>/dev/null || echo "NOT_FOUND")

if [ "$BOT_INFO" = "NOT_FOUND" ]; then
    echo -e "${RED}❌ Bot service not found${NC}"
else
    BOT_APP_ID=$(echo "$BOT_INFO" | jq -r '.properties.msaAppId')
    BOT_ENDPOINT=$(echo "$BOT_INFO" | jq -r '.properties.endpoint')
    BOT_KIND=$(echo "$BOT_INFO" | jq -r '.kind')
    BOT_SKU=$(echo "$BOT_INFO" | jq -r '.sku.name')
    
    echo "Bot App ID: $BOT_APP_ID"
    echo "Bot Endpoint: $BOT_ENDPOINT"
    echo "Bot Kind: $BOT_KIND"
    echo "Bot SKU: $BOT_SKU"
    
    if [ "$BOT_APP_ID" != "$APP_ID" ]; then
        echo -e "${RED}❌ MISMATCH: Bot Service App ID differs from Container App ID${NC}"
    else
        echo -e "${GREEN}✅ App IDs match${NC}"
    fi
fi

echo ""

# Test authentication manually
echo -e "${BLUE}🔐 Manual Authentication Test:${NC}"

# Try to get a token using the app credentials
echo "Testing OAuth token acquisition..."

# First, let's check if we can get the current app password from container app
APP_PASSWORD_SECRET=$(echo "$CURRENT_ENV" | jq -r '.[] | select(.name=="MicrosoftAppPassword") | .secretRef // .value // "NOT_SET"')

if [ "$APP_PASSWORD_SECRET" = "NOT_SET" ] || [ "$APP_PASSWORD_SECRET" = "null" ]; then
    echo -e "${RED}❌ MicrosoftAppPassword not properly configured${NC}"
    
    echo "Generating new client secret..."
    NEW_SECRET=$(az ad app credential reset \
        --id "$APP_ID" \
        --display-name "Debug Test $(date +%Y%m%d%H%M)" \
        --years 1 \
        --query "password" -o tsv)
    
    echo "Updating container app with new secret..."
    az containerapp update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_APP_NAME" \
        --set-env-vars "MicrosoftAppPassword=$NEW_SECRET"
    
    echo -e "${GREEN}✅ New secret generated and configured${NC}"
else
    echo -e "${GREEN}✅ MicrosoftAppPassword is configured${NC}"
fi

echo ""

# Check Teams channel configuration
echo -e "${BLUE}📱 Teams Channel Configuration:${NC}"
TEAMS_CHANNEL=$(az bot show --resource-group "$RESOURCE_GROUP" --name "$BOT_NAME" \
    --query "properties.configuredChannels" -o json 2>/dev/null || echo "[]")

echo "Configured Channels:"
if [ "$TEAMS_CHANNEL" != "[]" ]; then
    echo "$TEAMS_CHANNEL" | jq -r '.[]'
else
    echo "No channels configured"
    
    echo "Enabling Teams channel..."
    az bot msteams create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BOT_NAME" 2>/dev/null || echo "Teams channel may already exist"
fi

echo ""

# Provide comprehensive recommendations
echo -e "${BLUE}💡 Diagnosis and Recommendations:${NC}"
echo ""

if [ "$APP_DETAILS" = "NOT_FOUND" ]; then
    echo -e "${RED}CRITICAL ISSUE: App Registration Missing${NC}"
    echo "The app ID $APP_ID does not exist in your Azure AD tenant."
    echo "This is the root cause of the authentication error."
    echo ""
    echo "SOLUTION:"
    echo "1. Create a new app registration:"
    echo "   az ad app create --display-name 'Teams Search Bot New' --sign-in-audience 'AzureADMyOrg'"
    echo "2. Update all configurations with the new App ID"
    
elif [ "$SP_EXISTS" = "NOT_FOUND" ]; then
    echo -e "${YELLOW}Issue: Missing Service Principal${NC}"
    echo "The app registration exists but doesn't have a service principal."
    echo "This may cause authentication issues."
    
elif [ "$APP_PASSWORD_SECRET" = "NOT_SET" ]; then
    echo -e "${YELLOW}Issue: Missing or Invalid Client Secret${NC}"
    echo "The app password is not properly configured in the container app."
    
else
    echo -e "${YELLOW}Complex Authentication Issue${NC}"
    echo "The app registration and configuration appear correct, but authentication is still failing."
    echo ""
    echo "Possible causes:"
    echo "1. Azure AD propagation delay (wait 10-15 minutes)"
    echo "2. Tenant-specific authentication policies"
    echo "3. Bot Framework service issues"
    echo "4. Incorrect OAuth scope or audience configuration"
fi

echo ""
echo -e "${BLUE}🔧 Next Steps:${NC}"
echo "1. If app registration is missing, create a new one"
echo "2. Wait 15 minutes for Azure AD changes to propagate"
echo "3. Test the bot again"
echo "4. If still failing, check Azure AD app logs"
echo ""

echo -e "${GREEN}🔍 Debugging complete!${NC}"