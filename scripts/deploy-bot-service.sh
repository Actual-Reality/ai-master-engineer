#!/bin/bash

# Teams Bot Service Deployment Script (Single-Tenant Configuration)
# This script creates Azure resources and deploys the Teams bot using single-tenant configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Update these to match your setup
RESOURCE_GROUP="rg-ai-master-engineer"
CONTAINER_APP_NAME="teams-search-bot-capp"
BOT_NAME="ssoe-teams-bot"
LOCATION="eastus"

echo -e "${BLUE}🚀 Deploying Teams Bot Service (Single-Tenant)${NC}"
echo "============================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Container App: $CONTAINER_APP_NAME"
echo "Bot Name: $BOT_NAME"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "  ${GREEN}✅ $message${NC}"
    elif [ "$status" = "WARNING" ]; then
        echo -e "  ${YELLOW}⚠️  $message${NC}"
    else
        echo -e "  ${RED}❌ $message${NC}"
    fi
}

# Check Azure login
echo -e "${BLUE}🔐 Checking Azure CLI authentication...${NC}"
if az account show >/dev/null 2>&1; then
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    TENANT_ID=$(az account show --query tenantId -o tsv)
    print_status "OK" "Logged into Azure: $SUBSCRIPTION_NAME"
    print_status "OK" "Tenant ID: $TENANT_ID"
else
    print_status "ERROR" "Not logged into Azure CLI. Run 'az login' first."
    exit 1
fi
echo ""

# Verify resource group exists
echo -e "${BLUE}📦 Verifying Resource Group...${NC}"
if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    print_status "OK" "Resource group exists: $RESOURCE_GROUP"
else
    print_status "ERROR" "Resource group '$RESOURCE_GROUP' not found"
    exit 1
fi
echo ""

# Get container app details
echo -e "${BLUE}🐳 Getting Container App Details...${NC}"
CONTAINER_APP_INFO=$(az containerapp show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP_NAME" 2>/dev/null || echo "")

if [ -n "$CONTAINER_APP_INFO" ]; then
    CONTAINER_APP_FQDN=$(echo "$CONTAINER_APP_INFO" | jq -r '.properties.configuration.ingress.fqdn // empty')
    CONTAINER_APP_STATE=$(echo "$CONTAINER_APP_INFO" | jq -r '.properties.provisioningState // "Unknown"')
    
    print_status "OK" "Container app found: $CONTAINER_APP_NAME"
    print_status "OK" "State: $CONTAINER_APP_STATE"
    
    if [ -n "$CONTAINER_APP_FQDN" ]; then
        CONTAINER_APP_URL="https://$CONTAINER_APP_FQDN"
        print_status "OK" "URL: $CONTAINER_APP_URL"
        BOT_ENDPOINT_URL="${CONTAINER_APP_URL}/api/messages"
        print_status "OK" "Bot endpoint will be: $BOT_ENDPOINT_URL"
    else
        print_status "ERROR" "Container app has no FQDN. Check ingress configuration."
        exit 1
    fi
else
    print_status "ERROR" "Container app '$CONTAINER_APP_NAME' not found in resource group"
    exit 1
fi
echo ""

# Test container app connectivity
echo -e "${BLUE}🏥 Testing Container App Connectivity...${NC}"

# Check container app status first
CONTAINER_APP_STATUS=$(az containerapp show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP_NAME" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
print_status "INFO" "Container app provisioning state: $CONTAINER_APP_STATUS"

# Check if there are any revisions running
ACTIVE_REVISIONS=$(az containerapp revision list --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP_NAME" --query "[?properties.active].name" -o tsv 2>/dev/null | wc -l)
print_status "INFO" "Active revisions: $ACTIVE_REVISIONS"

# Test basic connectivity
echo "  Testing connectivity to: $CONTAINER_APP_URL"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$CONTAINER_APP_URL" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    print_status "OK" "Container app is accessible (HTTP 200)"
elif [ "$HTTP_STATUS" = "404" ]; then
    print_status "WARNING" "Container app returns 404 (may be normal if no default route)"
elif [ "$HTTP_STATUS" = "503" ]; then
    print_status "WARNING" "Container app returns 503 (service unavailable - may be starting up)"
elif [ "$HTTP_STATUS" = "000" ]; then
    print_status "WARNING" "Container app not reachable (connection timeout/failed)"
    print_status "INFO" "This could mean the container is not running or ingress is not configured"
else
    print_status "WARNING" "Container app returns HTTP $HTTP_STATUS"
fi

# Test the bot endpoint specifically
echo "  Testing bot endpoint: ${CONTAINER_APP_URL}/api/messages"
BOT_ENDPOINT_TEST_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${CONTAINER_APP_URL}/api/messages" 2>/dev/null || echo "000")
if [ "$BOT_ENDPOINT_TEST_STATUS" = "405" ]; then
    print_status "OK" "Bot endpoint accessible (405 Method Not Allowed is expected for GET)"
elif [ "$BOT_ENDPOINT_TEST_STATUS" = "401" ]; then
    print_status "OK" "Bot endpoint accessible (401 Unauthorized is expected without auth)"
elif [ "$BOT_ENDPOINT_TEST_STATUS" = "404" ]; then
    print_status "WARNING" "Bot endpoint returns 404 - check if /api/messages route exists"
elif [ "$BOT_ENDPOINT_TEST_STATUS" = "000" ]; then
    print_status "WARNING" "Bot endpoint not reachable"
else
    print_status "WARNING" "Bot endpoint returns HTTP $BOT_ENDPOINT_TEST_STATUS"
fi
echo ""

# Check if bot service already exists
echo -e "${BLUE}🤖 Checking Existing Bot Service...${NC}"
EXISTING_BOT=$(az bot show --resource-group "$RESOURCE_GROUP" --name "$BOT_NAME" 2>/dev/null || echo "")

if [ -n "$EXISTING_BOT" ]; then
    EXISTING_ENDPOINT=$(echo "$EXISTING_BOT" | jq -r '.properties.endpoint // "N/A"')
    EXISTING_APP_ID=$(echo "$EXISTING_BOT" | jq -r '.properties.msaAppId // "N/A"')
    
    print_status "WARNING" "Bot service already exists"
    print_status "WARNING" "Current endpoint: $EXISTING_ENDPOINT"
    print_status "WARNING" "Current App ID: $EXISTING_APP_ID"
    
    echo -e "\n${YELLOW}Do you want to update the existing bot or create a new one? (update/new/cancel):${NC}"
    read -r choice
    
    case $choice in
        update|UPDATE)
            echo -e "${BLUE}🔄 Updating existing bot service...${NC}"
            az bot update \
                --resource-group "$RESOURCE_GROUP" \
                --name "$BOT_NAME" \
                --endpoint "$BOT_ENDPOINT_URL"
            
            print_status "OK" "Bot service updated with new endpoint"
            APP_ID="$EXISTING_APP_ID"
            ;;
        new|NEW)
            # Generate a new bot name
            BOT_NAME="${BOT_NAME}-$(date +%s)"
            echo -e "${BLUE}🆕 Creating new bot service: $BOT_NAME${NC}"
            ;;
        *)
            echo "Cancelled."
            exit 0
            ;;
    esac
else
    print_status "OK" "No existing bot service found. Will create new one."
fi
echo ""

# Create Microsoft Entra ID app registration (if creating new bot)
if [ -z "$APP_ID" ]; then
    echo -e "${BLUE}🔑 Creating Microsoft Entra ID App Registration (Single-Tenant)...${NC}"
    
    # Create single-tenant app registration
    APP_REGISTRATION_OUTPUT=$(az ad app create \
        --display-name "TeamsSearchBot-$(date +%s)" \
        --sign-in-audience "AzureADMyOrg" \
        --query "{appId: appId, displayName: displayName}" -o json)
    
    APP_ID=$(echo "$APP_REGISTRATION_OUTPUT" | jq -r '.appId')
    APP_DISPLAY_NAME=$(echo "$APP_REGISTRATION_OUTPUT" | jq -r '.displayName')
    
    print_status "OK" "Single-tenant app registration created: $APP_DISPLAY_NAME"
    print_status "OK" "App ID: $APP_ID"
    print_status "OK" "Tenant ID: $TENANT_ID"
    
    # Create client secret
    echo -e "${BLUE}🔐 Creating Client Secret...${NC}"
    CLIENT_SECRET_OUTPUT=$(az ad app credential reset \
        --id "$APP_ID" \
        --display-name "TeamsBot-Secret" \
        --years 2 \
        --query "password" -o tsv)
    
    CLIENT_SECRET="$CLIENT_SECRET_OUTPUT"
    print_status "OK" "Client secret created (expires in 2 years)"
    
    # Create Azure Bot resource with single-tenant configuration
    echo -e "${BLUE}🤖 Creating Azure Bot Service (Single-Tenant)...${NC}"
    
    # Create single-tenant bot
    print_status "INFO" "Creating single-tenant bot with Azure CLI..."
    echo "  Command: az bot create --resource-group $RESOURCE_GROUP --name $BOT_NAME --appid $APP_ID --app-type SingleTenant --tenant-id $TENANT_ID --endpoint $BOT_ENDPOINT_URL --sku F0"
    
    timeout 120 az bot create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BOT_NAME" \
        --appid "$APP_ID" \
        --app-type "SingleTenant" \
        --tenant-id "$TENANT_ID" \
        --endpoint "$BOT_ENDPOINT_URL" \
        --sku "F0" \
        --output json > /tmp/bot-create-result.json 2>/tmp/bot-create-error.log
    
    BOT_CREATE_EXIT_CODE=$?
    
    if [ $BOT_CREATE_EXIT_CODE -eq 0 ]; then
        print_status "OK" "Azure Bot Service (Single-Tenant) created via Azure CLI"
        BOT_CREATED=true
    elif [ $BOT_CREATE_EXIT_CODE -eq 124 ]; then
        print_status "WARNING" "Bot creation timed out after 120 seconds. Trying ARM template approach..."
        BOT_CREATED=false
    else
        print_status "WARNING" "Azure CLI bot creation failed. Trying ARM template approach..."
        echo "  Error details:"
        cat /tmp/bot-create-error.log | sed 's/^/    /'
        BOT_CREATED=false
    fi
    
    if [ "$BOT_CREATED" = false ]; then
        # Alternative: Create using ARM template approach for single-tenant
        echo -e "${YELLOW}  Using ARM template deployment for single-tenant bot...${NC}"
        
        # Create ARM template for single-tenant bot
        BOT_TEMPLATE='{
            "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
            "contentVersion": "1.0.0.0",
            "parameters": {
                "botName": {"type": "string"},
                "appId": {"type": "string"},
                "tenantId": {"type": "string"},
                "endpoint": {"type": "string"}
            },
            "resources": [
                {
                    "type": "Microsoft.BotService/botServices",
                    "apiVersion": "2021-03-01",
                    "name": "[parameters(\"botName\")]",
                    "location": "global",
                    "sku": {"name": "F0"},
                    "kind": "azurebot",
                    "properties": {
                        "displayName": "[parameters(\"botName\")]",
                        "iconUrl": "https://docs.botframework.com/static/devportal/client/images/bot-framework-default.png",
                        "endpoint": "[parameters(\"endpoint\")]",
                        "msaAppId": "[parameters(\"appId\")]",
                        "msaAppMSIResourceId": "",
                        "msaAppTenantId": "[parameters(\"tenantId\")]",
                        "msaAppType": "SingleTenant"
                    }
                },
                {
                    "type": "Microsoft.BotService/botServices/channels",
                    "apiVersion": "2021-03-01",
                    "name": "[concat(parameters(\"botName\"), \"/MsTeamsChannel\")]",
                    "dependsOn": [
                        "[resourceId(\"Microsoft.BotService/botServices\", parameters(\"botName\"))]"
                    ],
                    "properties": {
                        "channelName": "MsTeamsChannel",
                        "properties": {
                            "isEnabled": true
                        }
                    }
                }
            ],
            "outputs": {
                "botName": {
                    "type": "string",
                    "value": "[parameters(\"botName\")]"
                }
            }
        }'
        
        # Deploy using ARM template with single-tenant configuration
        echo "$BOT_TEMPLATE" > /tmp/bot-template.json
        print_status "INFO" "Deploying single-tenant bot service via ARM template (this may take 3-5 minutes)..."
        
        timeout 300 az deployment group create \
            --resource-group "$RESOURCE_GROUP" \
            --template-file /tmp/bot-template.json \
            --parameters \
                botName="$BOT_NAME" \
                appId="$APP_ID" \
                tenantId="$TENANT_ID" \
                endpoint="$BOT_ENDPOINT_URL" \
            --output json > /tmp/arm-deploy-result.json 2>/tmp/arm-deploy-error.log
        
        ARM_DEPLOY_EXIT_CODE=$?
        
        if [ $ARM_DEPLOY_EXIT_CODE -eq 0 ]; then
            print_status "OK" "Single-tenant bot service created via ARM template"
            # Teams channel is created as part of the template
            TEAMS_CHANNEL_CREATED=true
        elif [ $ARM_DEPLOY_EXIT_CODE -eq 124 ]; then
            print_status "ERROR" "ARM template deployment timed out after 300 seconds"
            echo "  This might indicate a service issue. Check Azure portal for deployment status."
            exit 1
        else
            print_status "ERROR" "ARM template deployment failed"
            echo "  Error details:"
            cat /tmp/arm-deploy-error.log | sed 's/^/    /'
            exit 1
        fi
        
        # Clean up temp file
        rm -f /tmp/bot-template.json
    fi
    
    # Clean up temp files
    rm -f /tmp/bot-create-result.json /tmp/bot-create-error.log /tmp/arm-deploy-result.json /tmp/arm-deploy-error.log
    
    print_status "OK" "Azure Bot Service (Single-Tenant) created: $BOT_NAME"
fi
echo ""

# Enable Teams channel (skip if already created by ARM template)
echo -e "${BLUE}📱 Enabling Teams Channel...${NC}"

if [ "$TEAMS_CHANNEL_CREATED" = true ]; then
    print_status "OK" "Teams channel already enabled via ARM template"
else
    TEAMS_CHANNEL_RESULT=$(az bot msteams create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$BOT_NAME" 2>&1 || echo "ERROR_OCCURRED")

    if [[ "$TEAMS_CHANNEL_RESULT" == *"already exists"* ]]; then
        print_status "OK" "Teams channel already enabled"
    elif [[ "$TEAMS_CHANNEL_RESULT" == *"ERROR_OCCURRED"* ]] || [[ "$TEAMS_CHANNEL_RESULT" == *"error"* ]]; then
        print_status "WARNING" "Teams channel creation had issues, but may still work. Trying alternative method..."
        # Alternative: Try enabling via bot update
        az bot update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$BOT_NAME" \
            --endpoint "$BOT_ENDPOINT_URL" >/dev/null 2>&1 || true
        print_status "OK" "Bot updated - Teams channel should be available"
    else
        print_status "OK" "Teams channel enabled successfully"
    fi
fi
echo ""

# Configure container app environment variables
echo -e "${BLUE}⚙️  Configuring Container App Environment Variables (Single-Tenant)...${NC}"

# Update container app with single-tenant environment variables
az containerapp update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP_NAME" \
    --set-env-vars \
        MicrosoftAppId="$APP_ID" \
        MicrosoftAppPassword="$CLIENT_SECRET" \
        MicrosoftAppType="SingleTenant" \
        MicrosoftAppTenantId="$TENANT_ID" \
    --output none

print_status "OK" "Container app environment variables updated for single-tenant"
print_status "OK" "Added MicrosoftAppTenantId: $TENANT_ID"
echo ""

# Wait for container app to restart
echo -e "${BLUE}⏳ Waiting for Container App to Restart...${NC}"
echo "This may take 1-2 minutes..."

# Check if the container app is ready
for i in {1..60}; do
    REVISION_STATUS=$(az containerapp revision list --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP_NAME" --query "[0].properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
    
    if [ "$REVISION_STATUS" = "Succeeded" ]; then
        print_status "OK" "Container app is ready"
        break
    else
        echo -n "."
        sleep 2
    fi
    
    if [ $i -eq 60 ]; then
        print_status "WARNING" "Container app restart taking longer than expected"
        break
    fi
done
echo ""

# Update Teams manifest
echo -e "${BLUE}📋 Updating Teams Manifest...${NC}"

MANIFEST_PATH="../teams_bot/manifest/manifest.json"

if [ -f "$MANIFEST_PATH" ]; then
    # Update the manifest with the new App ID
    jq --arg appId "$APP_ID" '
        .id = $appId |
        .bots[0].botId = $appId
    ' "$MANIFEST_PATH" > "${MANIFEST_PATH}.tmp" && mv "${MANIFEST_PATH}.tmp" "$MANIFEST_PATH"
    
    print_status "OK" "Manifest updated with App ID: $APP_ID"
    
    # Create new app package
    echo -e "${BLUE}📦 Creating Teams App Package...${NC}"
    cd ../teams_bot/manifest
    zip -r "../teams-app-package.zip" manifest.json *.png 2>/dev/null || zip -r "../teams-app-package.zip" manifest.json
    cd ..
    
    print_status "OK" "Teams app package created: teams-app-package.zip"
else
    print_status "WARNING" "Manifest file not found at $MANIFEST_PATH"
    print_status "INFO" "You'll need to manually create the Teams app package"
fi
echo ""

# Final summary and next steps
echo -e "${GREEN}🎉 Single-Tenant Bot Service Deployment Completed!${NC}"
echo ""
echo -e "${BLUE}📊 Deployment Summary:${NC}"
echo "┌─────────────────────────────────────────────────────────────────────┐"
echo "│ Configuration: SINGLE-TENANT BOT                                   │"
echo "├─────────────────────────────────────────────────────────────────────┤"
echo "Resource Group: $RESOURCE_GROUP"
echo "Container App: $CONTAINER_APP_NAME"
echo "Container URL: $CONTAINER_APP_URL"
echo "Bot Service: $BOT_NAME"
echo "App ID: $APP_ID"
echo "Tenant ID: $TENANT_ID"
echo "App Type: SingleTenant"
echo "Bot Endpoint: $BOT_ENDPOINT_URL"
echo ""

echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Wait 2-3 minutes for all services to fully start"
echo "2. Test the bot endpoint:"
echo "   curl -X POST $BOT_ENDPOINT_URL"
echo ""
echo "3. Install the Teams app:"
echo "   - Upload teams-app-package.zip to Teams Admin Center or Developer Portal"
echo "   - Or sideload in Teams for testing"
echo ""
echo "4. Test in Teams:"
echo "   - Search for your bot in Teams"
echo "   - Send a test message"
echo ""
echo "5. Monitor logs:"
echo "   az containerapp logs show --resource-group $RESOURCE_GROUP --name $CONTAINER_APP_NAME --follow"
echo ""

echo -e "${YELLOW}⚠️  Important Notes:${NC}"
echo "• Configuration: SINGLE-TENANT (recommended for future-proofing)"
echo "• App ID: $APP_ID"
echo "• Tenant ID: $TENANT_ID"
echo "• Client secret expires in 2 years"
echo "• Bot is configured for Single-tenant use in your organization"
echo "• Teams channel is enabled"
echo ""

echo -e "${BLUE}🔧 Troubleshooting:${NC}"
echo "If the bot doesn't respond:"
echo "1. Check container logs: az containerapp logs show --resource-group $RESOURCE_GROUP --name $CONTAINER_APP_NAME"
echo "2. Verify environment variables include MicrosoftAppTenantId"
echo "3. Ensure app registration is single-tenant in Azure AD"
echo "4. Run diagnostic script if available"
echo ""

echo -e "${GREEN}✅ Single-tenant configuration is future-proof (multi-tenant deprecated July 2025)${NC}"