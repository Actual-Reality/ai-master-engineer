#!/bin/bash

# Teams Bot ACR Deployment Script
# Automates the build and deployment process with version incrementing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="rg-ai-master-engineer"
CONTAINER_APP_NAME="teams-search-bot-capp"
ACR_NAME="aimasterengineeracrnnsnw2zar7dok"
IMAGE_NAME="teams-search-bot"

# Get current version from parameter or auto-increment
if [ "$1" ]; then
    NEW_VERSION="$1"
else
    # Auto-increment version by checking existing tags
    echo -e "${BLUE}🔍 Checking existing image versions...${NC}"
    
    # Get latest version from ACR
    LATEST_TAG=$(az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_NAME" --query "max([])" -o tsv 2>/dev/null || echo "v0")
    
    if [ "$LATEST_TAG" = "v0" ] || [ -z "$LATEST_TAG" ]; then
        NEW_VERSION="v1"
        echo "No previous versions found. Starting with v1"
    else
        # Extract number from version (e.g., v5 -> 5)
        CURRENT_NUM=$(echo "$LATEST_TAG" | sed 's/v//')
        NEW_NUM=$((CURRENT_NUM + 1))
        NEW_VERSION="v$NEW_NUM"
        echo "Latest version: $LATEST_TAG -> New version: $NEW_VERSION"
    fi
fi

# Generate revision suffix (4-digit padded)
VERSION_NUM=$(echo "$NEW_VERSION" | sed 's/v//')
REVISION_SUFFIX=$(printf "%04d" "$VERSION_NUM")

echo ""
echo -e "${BLUE}🚀 Teams Bot Deployment${NC}"
echo "========================"
echo "Resource Group: $RESOURCE_GROUP"
echo "Container App: $CONTAINER_APP_NAME"
echo "ACR: $ACR_NAME"
echo "Image: $IMAGE_NAME:$NEW_VERSION"
echo "Revision Suffix: $REVISION_SUFFIX"
echo ""

# Determine the teams_bot directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAMS_BOT_DIR="$(dirname "$SCRIPT_DIR")/teams_bot"

echo -e "${BLUE}📁 Directory Setup:${NC}"
echo "Script location: $SCRIPT_DIR"
echo "Teams bot directory: $TEAMS_BOT_DIR"
echo ""

# Check if teams_bot directory exists and has required files
if [ ! -d "$TEAMS_BOT_DIR" ]; then
    echo -e "${RED}❌ Error: teams_bot directory not found at $TEAMS_BOT_DIR${NC}"
    echo "Expected structure:"
    echo "  ~/teams_bot/app.py"
    echo "  ~/teams_bot/teams_bot.py"
    echo "  ~/scripts/deploy-acr.sh"
    exit 1
fi

if [ ! -f "$TEAMS_BOT_DIR/app.py" ] || [ ! -f "$TEAMS_BOT_DIR/teams_bot.py" ]; then
    echo -e "${RED}❌ Error: Required files not found in $TEAMS_BOT_DIR${NC}"
    echo "Missing files:"
    [ ! -f "$TEAMS_BOT_DIR/app.py" ] && echo "  - app.py"
    [ ! -f "$TEAMS_BOT_DIR/teams_bot.py" ] && echo "  - teams_bot.py"
    echo ""
    echo "Current contents of $TEAMS_BOT_DIR:"
    ls -la "$TEAMS_BOT_DIR" 2>/dev/null || echo "  (directory not accessible)"
    exit 1
fi

# Change to teams_bot directory for build
cd "$TEAMS_BOT_DIR"
echo -e "${GREEN}✅ Changed to teams_bot directory for build${NC}"

# Check Azure CLI login
echo -e "${BLUE}🔐 Checking Azure authentication...${NC}"
if ! az account show >/dev/null 2>&1; then
    echo -e "${RED}❌ Not logged into Azure CLI${NC}"
    echo "Please run: az login"
    exit 1
fi

SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
echo -e "${GREEN}✅ Logged into Azure: $SUBSCRIPTION_NAME${NC}"

# Check if ACR exists and we have access
echo -e "${BLUE}🏗️ Checking ACR access...${NC}"
if ! az acr show --name "$ACR_NAME" >/dev/null 2>&1; then
    echo -e "${RED}❌ Cannot access ACR: $ACR_NAME${NC}"
    echo "Make sure you have access to the registry"
    exit 1
fi

echo -e "${GREEN}✅ ACR access confirmed${NC}"

# Build and push image
echo ""
echo -e "${BLUE}🔨 Building container image...${NC}"
echo "Command: az acr build --registry $ACR_NAME --image $IMAGE_NAME:$NEW_VERSION ."

# Show what files will be included in the build
echo ""
echo -e "${BLUE}📁 Files to be built from $TEAMS_BOT_DIR:${NC}"
echo "Core files:"
[ -f "app.py" ] && echo "  ✅ app.py" || echo "  ❌ app.py (missing!)"
[ -f "teams_bot.py" ] && echo "  ✅ teams_bot.py" || echo "  ❌ teams_bot.py (missing!)"
[ -f "rag_bridge.py" ] && echo "  ✅ rag_bridge.py" || echo "  ⚠️ rag_bridge.py (missing)"
[ -f "conversation_storage.py" ] && echo "  ✅ conversation_storage.py" || echo "  ⚠️ conversation_storage.py (missing)"
[ -f "requirements.txt" ] && echo "  ✅ requirements.txt" || echo "  ⚠️ requirements.txt (missing)"
[ -f "Dockerfile" ] && echo "  ✅ Dockerfile" || echo "  ⚠️ Dockerfile (missing)"

echo ""
echo -e "${YELLOW}⏳ Building image (this may take 2-5 minutes)...${NC}"

# Build with timeout
timeout 600 az acr build \
    --registry "$ACR_NAME" \
    --image "$IMAGE_NAME:$NEW_VERSION" \
    . || {
    echo -e "${RED}❌ Build failed or timed out${NC}"
    exit 1
}

echo -e "${GREEN}✅ Image built successfully: $ACR_NAME.azurecr.io/$IMAGE_NAME:$NEW_VERSION${NC}"

# Update container app
echo ""
echo -e "${BLUE}🚢 Updating container app...${NC}"
echo "Command: az containerapp update --resource-group $RESOURCE_GROUP --name $CONTAINER_APP_NAME --image $ACR_NAME.azurecr.io/$IMAGE_NAME:$NEW_VERSION --revision-suffix $REVISION_SUFFIX"

az containerapp update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP_NAME" \
    --image "$ACR_NAME.azurecr.io/$IMAGE_NAME:$NEW_VERSION" \
    --revision-suffix "$REVISION_SUFFIX" || {
    echo -e "${RED}❌ Container app update failed${NC}"
    exit 1
}

echo -e "${GREEN}✅ Container app updated successfully${NC}"

# Wait for deployment to complete
echo ""
echo -e "${BLUE}⏳ Waiting for deployment to complete...${NC}"
echo "This typically takes 1-3 minutes..."

# Check deployment status
for i in {1..60}; do
    STATUS=$(az containerapp revision show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CONTAINER_APP_NAME" \
        --revision "$CONTAINER_APP_NAME--$REVISION_SUFFIX" \
        --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
    
    if [ "$STATUS" = "Succeeded" ]; then
        echo -e "${GREEN}✅ Deployment completed successfully${NC}"
        break
    elif [ "$STATUS" = "Failed" ]; then
        echo -e "${RED}❌ Deployment failed${NC}"
        break
    else
        echo -n "."
        sleep 3
    fi
    
    if [ $i -eq 60 ]; then
        echo -e "${YELLOW}⚠️ Deployment taking longer than expected${NC}"
        break
    fi
done

echo ""

# Get container app URL
CONTAINER_URL=$(az containerapp show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CONTAINER_APP_NAME" \
    --query "properties.configuration.ingress.fqdn" -o tsv)

if [ -n "$CONTAINER_URL" ]; then
    CONTAINER_URL="https://$CONTAINER_URL"
fi

# Summary
echo ""
echo -e "${GREEN}🎉 Deployment Summary${NC}"
echo "====================="
echo "Image: $ACR_NAME.azurecr.io/$IMAGE_NAME:$NEW_VERSION"
echo "Revision: $CONTAINER_APP_NAME--$REVISION_SUFFIX"
echo "URL: $CONTAINER_URL"
echo ""

# Test endpoints
echo -e "${BLUE}🧪 Testing endpoints...${NC}"

if [ -n "$CONTAINER_URL" ]; then
    echo "Testing health endpoint..."
    HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$CONTAINER_URL/health" 2>/dev/null || echo "000")
    
    if [ "$HEALTH_STATUS" = "200" ]; then
        echo -e "${GREEN}✅ Health endpoint: OK${NC}"
    else
        echo -e "${YELLOW}⚠️ Health endpoint: HTTP $HEALTH_STATUS${NC}"
    fi
    
    echo "Testing bot endpoint..."
    BOT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$CONTAINER_URL/api/messages" 2>/dev/null || echo "000")
    
    if [ "$BOT_STATUS" = "405" ] || [ "$BOT_STATUS" = "401" ]; then
        echo -e "${GREEN}✅ Bot endpoint: OK (HTTP $BOT_STATUS expected for GET)${NC}"
    else
        echo -e "${YELLOW}⚠️ Bot endpoint: HTTP $BOT_STATUS${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ Could not determine container URL for testing${NC}"
fi

echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "1. Test bot in Teams by sending a message"
echo "2. Monitor logs: az containerapp logs show --resource-group $RESOURCE_GROUP --name $CONTAINER_APP_NAME --follow"
echo "3. Check specific revision: az containerapp revision show --resource-group $RESOURCE_GROUP --name $CONTAINER_APP_NAME --revision $CONTAINER_APP_NAME--$REVISION_SUFFIX"

echo ""
echo -e "${BLUE}🐛 If issues occur:${NC}"
echo "• Check logs for errors"
echo "• Verify environment variables are set"
echo "• Test RAG backend connectivity"
echo "• Ensure Bot Framework credentials are correct"

echo ""
echo -e "${GREEN}🚀 Deployment completed successfully!${NC}"