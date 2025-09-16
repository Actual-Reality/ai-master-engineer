#!/bin/bash

# Teams Bot Diagnostic Script
# This script identifies Azure resources and performs health checks for the Teams bot deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Updated for your actual setup
RESOURCE_GROUP="rg-ai-master-engineer"
CONTAINER_APP_NAME="teams-search-bot-capp"
BOT_NAME="ssoe-teams-bot"
EXPECTED_ENDPOINT_PATH="/api/messages"

echo -e "${BLUE}🔍 Teams Bot Diagnostics${NC}"
echo "==============================="
echo "$(date)"
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

# Function to check if Azure CLI is logged in
check_azure_login() {
    echo -e "${BLUE}🔐 Checking Azure CLI authentication...${NC}"
    if az account show >/dev/null 2>&1; then
        SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        print_status "OK" "Logged into Azure subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    else
        print_status "ERROR" "Not logged into Azure CLI. Run 'az login' first."
        exit 1
    fi
    echo ""
}

# Function to identify resource group
identify_resource_group() {
    echo -e "${BLUE}📦 Identifying Resource Group...${NC}"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
        print_status "OK" "Resource group found: $RESOURCE_GROUP (Location: $LOCATION)"
        
        # List all resources in the group
        echo "  Resources in group:"
        az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" -o table | sed 's/^/    /'
    else
        print_status "ERROR" "Resource group '$RESOURCE_GROUP' not found"
        echo "  Available resource groups containing 'teams' or 'bot':"
        az group list --query "[?contains(name, 'teams') || contains(name, 'bot')].{Name:name, Location:location}" -o table | sed 's/^/    /'
        return 1
    fi
    echo ""
}

# Function to identify bot service
identify_bot() {
    echo -e "${BLUE}🤖 Identifying Bot Service...${NC}"
    
    # Try to find the bot
    BOT_RESOURCE=$(az bot show --resource-group "$RESOURCE_GROUP" --name "$BOT_NAME" 2>/dev/null || echo "")
    
    if [ -n "$BOT_RESOURCE" ]; then
        APP_ID=$(echo "$BOT_RESOURCE" | jq -r '.properties.msaAppId // "N/A"')
        ENDPOINT=$(echo "$BOT_RESOURCE" | jq -r '.properties.endpoint // "N/A"')
        
        print_status "OK" "Bot service found: $BOT_NAME"
        print_status "OK" "App ID: $APP_ID"
        print_status "OK" "Endpoint: $ENDPOINT"
        
        # Check if Teams channel is enabled
        TEAMS_CHANNEL=$(az bot teams-channel show --resource-group "$RESOURCE_GROUP" --name "$BOT_NAME" 2>/dev/null || echo "")
        if [ -n "$TEAMS_CHANNEL" ]; then
            print_status "OK" "Teams channel is enabled"
        else
            print_status "WARNING" "Teams channel not found or not enabled"
        fi
        
        # Extract hostname from endpoint for later use
        if [[ "$ENDPOINT" =~ https://([^/]+) ]]; then
            ENDPOINT_HOST="${BASH_REMATCH[1]}"
        else
            ENDPOINT_HOST=""
        fi
        
    else
        print_status "ERROR" "Bot service '$BOT_NAME' not found in resource group"
        echo "  Available bots in subscription:"
        az bot list --query "[].{Name:name, ResourceGroup:resourceGroup, AppId:properties.msaAppId}" -o table | sed 's/^/    /'
        return 1
    fi
    echo ""
}

# Function to identify web app or container app
identify_compute_resource() {
    echo -e "${BLUE}🌐 Identifying Compute Resource...${NC}"
    
    # First, try to find Container Apps (prioritize since user mentioned container app)
    CONTAINER_APPS=$(az containerapp list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Fqdn:properties.configuration.ingress.fqdn, ProvisioningState:properties.provisioningState}" -o json 2>/dev/null || echo "[]")
    
    if [ "$(echo "$CONTAINER_APPS" | jq length)" -gt 0 ]; then
        echo "  Found Container Apps:"
        echo "$CONTAINER_APPS" | jq -r '.[] | "    \(.Name) - \(.ProvisioningState) - https://\(.Fqdn // "No FQDN")"'
        
        # Look for the specific container app first
        SPECIFIC_CONTAINER=$(echo "$CONTAINER_APPS" | jq --arg name "$CONTAINER_APP_NAME" '.[] | select(.Name == $name)')
        
        if [ -n "$SPECIFIC_CONTAINER" ] && [ "$SPECIFIC_CONTAINER" != "null" ]; then
            CONTAINER_APP_FQDN=$(echo "$SPECIFIC_CONTAINER" | jq -r '.Fqdn // empty')
            CONTAINER_APP_STATE=$(echo "$SPECIFIC_CONTAINER" | jq -r '.ProvisioningState // "Unknown"')
            
            print_status "OK" "Found target container app: $CONTAINER_APP_NAME ($CONTAINER_APP_STATE)"
            
            if [ -n "$CONTAINER_APP_FQDN" ]; then
                CONTAINER_APP_URL="https://$CONTAINER_APP_FQDN"
                COMPUTE_TYPE="containerapp"
                COMPUTE_NAME="$CONTAINER_APP_NAME"
                COMPUTE_URL="$CONTAINER_APP_URL"
            else
                print_status "WARNING" "Container App found but no FQDN configured"
                COMPUTE_TYPE="containerapp"
                COMPUTE_NAME="$CONTAINER_APP_NAME"
                COMPUTE_URL=""
            fi
        else
            # Use the first container app found
            CONTAINER_APP_NAME_FOUND=$(echo "$CONTAINER_APPS" | jq -r '.[0].Name')
            CONTAINER_APP_FQDN=$(echo "$CONTAINER_APPS" | jq -r '.[0].Fqdn // empty')
            
            print_status "WARNING" "Target container app '$CONTAINER_APP_NAME' not found, using: $CONTAINER_APP_NAME_FOUND"
            
            if [ -n "$CONTAINER_APP_FQDN" ]; then
                CONTAINER_APP_URL="https://$CONTAINER_APP_FQDN"
                COMPUTE_TYPE="containerapp"
                COMPUTE_NAME="$CONTAINER_APP_NAME_FOUND"
                COMPUTE_URL="$CONTAINER_APP_URL"
            else
                COMPUTE_TYPE="containerapp"
                COMPUTE_NAME="$CONTAINER_APP_NAME_FOUND"
                COMPUTE_URL=""
            fi
        fi
        
    else
        # Fallback to App Services
        WEB_APPS=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, State:state, Url:defaultHostName}" -o json 2>/dev/null || echo "[]")
        
        if [ "$(echo "$WEB_APPS" | jq length)" -gt 0 ]; then
            echo "  Found App Services:"
            echo "$WEB_APPS" | jq -r '.[] | "    \(.Name) - \(.State) - https://\(.Url)"'
            
            # Get the first web app for detailed checks
            WEB_APP_NAME=$(echo "$WEB_APPS" | jq -r '.[0].Name')
            WEB_APP_URL="https://$(echo "$WEB_APPS" | jq -r '.[0].Url')"
            COMPUTE_TYPE="webapp"
            COMPUTE_NAME="$WEB_APP_NAME"
            COMPUTE_URL="$WEB_APP_URL"
            
            print_status "OK" "Using App Service: $WEB_APP_NAME"
            
        else
            print_status "ERROR" "No Container App or App Service found in resource group"
            return 1
        fi
    fi
    echo ""
}

# Function to check compute resource health
check_compute_health() {
    echo -e "${BLUE}🏥 Checking Compute Resource Health...${NC}"
    
    if [ -z "$COMPUTE_URL" ]; then
        print_status "ERROR" "No compute URL available for health check"
        return 1
    fi
    
    # Basic connectivity test
    echo "  Testing connectivity to: $COMPUTE_URL"
    if curl -s --max-time 10 "$COMPUTE_URL" >/dev/null 2>&1; then
        print_status "OK" "Base URL is accessible"
    else
        print_status "ERROR" "Base URL is not accessible"
    fi
    
    # Test bot endpoint
    BOT_ENDPOINT_URL="${COMPUTE_URL}${EXPECTED_ENDPOINT_PATH}"
    echo "  Testing bot endpoint: $BOT_ENDPOINT_URL"
    
    # Try GET first (should return 405 Method Not Allowed for bot endpoints)
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$BOT_ENDPOINT_URL" 2>/dev/null || echo "000")
    
    if [ "$HTTP_STATUS" = "405" ]; then
        print_status "OK" "Bot endpoint responding correctly (405 Method Not Allowed for GET)"
    elif [ "$HTTP_STATUS" = "200" ]; then
        print_status "WARNING" "Bot endpoint returns 200 for GET (unusual but may be OK)"
    elif [ "$HTTP_STATUS" = "000" ]; then
        print_status "ERROR" "Bot endpoint not reachable (connection failed)"
    else
        print_status "WARNING" "Bot endpoint returns HTTP $HTTP_STATUS"
    fi
    
    # Check logs if it's an App Service
    if [ "$COMPUTE_TYPE" = "webapp" ]; then
        echo "  Checking recent App Service logs..."
        RECENT_LOGS=$(az webapp log download --resource-group "$RESOURCE_GROUP" --name "$COMPUTE_NAME" --log-file "temp_logs.zip" 2>/dev/null && unzip -l temp_logs.zip 2>/dev/null | tail -5 && rm -f temp_logs.zip 2>/dev/null || echo "Could not retrieve logs")
        if [[ "$RECENT_LOGS" == *"Could not retrieve"* ]]; then
            print_status "WARNING" "Could not retrieve App Service logs"
        else
            print_status "OK" "App Service logs accessible"
        fi
    fi
    
    echo ""
}

# Function to check application configuration
check_app_configuration() {
    echo -e "${BLUE}⚙️  Checking Application Configuration...${NC}"
    
    if [ "$COMPUTE_TYPE" = "webapp" ]; then
        # Get app settings
        APP_SETTINGS=$(az webapp config appsettings list --resource-group "$RESOURCE_GROUP" --name "$COMPUTE_NAME" 2>/dev/null || echo "[]")
        
        # Check required settings
        MICROSOFT_APP_ID=$(echo "$APP_SETTINGS" | jq -r '.[] | select(.name=="MicrosoftAppId") | .value // empty')
        MICROSOFT_APP_PASSWORD=$(echo "$APP_SETTINGS" | jq -r '.[] | select(.name=="MicrosoftAppPassword") | .value // empty')
        RAG_BACKEND_URL=$(echo "$APP_SETTINGS" | jq -r '.[] | select(.name=="RAG_BACKEND_URL") | .value // empty')
        
        if [ -n "$MICROSOFT_APP_ID" ]; then
            print_status "OK" "MicrosoftAppId configured: ${MICROSOFT_APP_ID:0:8}..."
            
            # Check if it matches the bot registration
            if [ "$MICROSOFT_APP_ID" = "$APP_ID" ]; then
                print_status "OK" "App ID matches bot registration"
            else
                print_status "ERROR" "App ID mismatch! App Service: $MICROSOFT_APP_ID, Bot: $APP_ID"
            fi
        else
            print_status "ERROR" "MicrosoftAppId not configured"
        fi
        
        if [ -n "$MICROSOFT_APP_PASSWORD" ]; then
            print_status "OK" "MicrosoftAppPassword configured"
        else
            print_status "ERROR" "MicrosoftAppPassword not configured"
        fi
        
        if [ -n "$RAG_BACKEND_URL" ]; then
            print_status "OK" "RAG_BACKEND_URL configured: $RAG_BACKEND_URL"
            
            # Test RAG backend connectivity
            echo "  Testing RAG backend connectivity..."
            if curl -s --max-time 10 "$RAG_BACKEND_URL" >/dev/null 2>&1; then
                print_status "OK" "RAG backend is accessible"
            else
                print_status "WARNING" "RAG backend may not be accessible (this could be normal if it requires authentication)"
            fi
        else
            print_status "WARNING" "RAG_BACKEND_URL not configured"
        fi
        
    elif [ "$COMPUTE_TYPE" = "containerapp" ]; then
        # Get container app configuration
        CONTAINER_CONFIG=$(az containerapp show --resource-group "$RESOURCE_GROUP" --name "$COMPUTE_NAME" 2>/dev/null || echo "{}")
        
        # Check environment variables
        ENV_VARS=$(echo "$CONTAINER_CONFIG" | jq -r '.properties.template.containers[0].env // []')
        
        if [ "$(echo "$ENV_VARS" | jq length)" -gt 0 ]; then
            print_status "OK" "Environment variables configured"
            echo "$ENV_VARS" | jq -r '.[] | "    \(.name): \(.value // .secretRef // "***")"'
        else
            print_status "WARNING" "No environment variables found"
        fi
    fi
    
    echo ""
}

# Function to validate manifest
validate_manifest() {
    echo -e "${BLUE}📋 Validating Teams App Manifest...${NC}"
    
    MANIFEST_PATH="teams_bot/manifest/manifest.json"
    
    if [ -f "$MANIFEST_PATH" ]; then
        print_status "OK" "Manifest file found: $MANIFEST_PATH"
        
        # Check if App ID in manifest matches bot registration
        MANIFEST_APP_ID=$(jq -r '.id // .bots[0].botId // empty' "$MANIFEST_PATH")
        
        if [ -n "$MANIFEST_APP_ID" ]; then
            print_status "OK" "Manifest App ID: $MANIFEST_APP_ID"
            
            if [ "$MANIFEST_APP_ID" = "$APP_ID" ]; then
                print_status "OK" "Manifest App ID matches bot registration"
            else
                print_status "ERROR" "Manifest App ID mismatch! Manifest: $MANIFEST_APP_ID, Bot: $APP_ID"
            fi
        else
            print_status "ERROR" "No App ID found in manifest"
        fi
        
        # Check for required fields
        BOT_SCOPES=$(jq -r '.bots[0].scopes // [] | join(", ")' "$MANIFEST_PATH")
        if [ -n "$BOT_SCOPES" ]; then
            print_status "OK" "Bot scopes: $BOT_SCOPES"
        else
            print_status "WARNING" "No bot scopes defined"
        fi
        
        # Check for icons
        if [ -f "teams_bot/manifest/color.png" ] && [ -f "teams_bot/manifest/outline.png" ]; then
            print_status "OK" "Icon files present"
        else
            print_status "WARNING" "Icon files missing (color.png and/or outline.png)"
        fi
        
    else
        print_status "ERROR" "Manifest file not found at $MANIFEST_PATH"
    fi
    echo ""
}

# Function to provide troubleshooting recommendations
provide_recommendations() {
    echo -e "${BLUE}💡 Troubleshooting Recommendations${NC}"
    echo "======================================"
    
    echo -e "\n${YELLOW}If the bot is not responding in Teams, check:${NC}"
    echo "1. Ensure the bot endpoint URL in Azure Bot registration matches your deployed app"
    echo "2. Verify MicrosoftAppId and MicrosoftAppPassword are correctly configured"
    echo "3. Check that Teams channel is enabled for the bot"
    echo "4. Test the bot endpoint manually with Bot Framework Emulator"
    echo "5. Review application logs for error messages"
    
    echo -e "\n${YELLOW}Common issues and solutions:${NC}"
    echo "• HTTP 401 Unauthorized: Check App ID and password configuration"
    echo "• HTTP 404 Not Found: Verify endpoint URL in bot registration"
    echo "• HTTP 500 Server Error: Check application logs for Python errors"
    echo "• Bot not responding: Ensure the bot service is running and healthy"
    
    echo -e "\n${YELLOW}Testing commands:${NC}"
    echo "• Test endpoint: curl -X POST $BOT_ENDPOINT_URL (should return 401 without auth)"
    echo "• View logs: az webapp log tail --resource-group $RESOURCE_GROUP --name $COMPUTE_NAME"
    echo "• Bot Framework Emulator: Connect to $BOT_ENDPOINT_URL"
    
    if [ -n "$RAG_BACKEND_URL" ]; then
        echo "• Test RAG backend: curl $RAG_BACKEND_URL/health"
    fi
}

# Main execution
main() {
    check_azure_login
    
    if identify_resource_group && identify_bot && identify_compute_resource; then
        check_compute_health
        check_app_configuration
        validate_manifest
        
        echo -e "${GREEN}🎉 Diagnostics completed!${NC}"
        echo ""
        echo -e "${BLUE}📊 Summary:${NC}"
        echo "Resource Group: $RESOURCE_GROUP"
        echo "Bot Service: $BOT_NAME (App ID: ${APP_ID:0:8}...)"
        echo "Compute Resource: $COMPUTE_TYPE - $COMPUTE_NAME"
        if [ -n "$COMPUTE_URL" ]; then
            echo "Bot Endpoint: ${COMPUTE_URL}${EXPECTED_ENDPOINT_PATH}"
        fi
        
    else
        echo -e "${RED}❌ Diagnostics failed - missing required resources${NC}"
    fi
    
    echo ""
    provide_recommendations
}

# Run main function
main "$@"