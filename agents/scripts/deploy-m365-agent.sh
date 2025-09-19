#!/bin/bash

# Microsoft 365 Agent Deployment Script
# This script deploys the Microsoft 365 RAG Agent to Azure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Python is installed
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if pip is installed
    if ! command -v pip3 &> /dev/null; then
        print_error "pip3 is not installed. Please install it first."
        exit 1
    fi
    
    print_success "All prerequisites are installed."
}

# Load environment variables
load_environment() {
    print_status "Loading environment variables..."
    
    if [ -f ".env" ]; then
        export $(cat .env | grep -v '^#' | xargs)
        print_success "Environment variables loaded from .env file."
    else
        print_warning "No .env file found. Using system environment variables."
    fi
    
    # Required environment variables
    REQUIRED_VARS=(
        "AZURE_SUBSCRIPTION_ID"
        "AZURE_RESOURCE_GROUP"
        "AZURE_LOCATION"
        "BOT_SERVICE_NAME"
        "MICROSOFT_APP_ID"
        "MICROSOFT_APP_PASSWORD"
        "BACKEND_URL"
        "TENANT_ID"
        "CLIENT_ID"
        "CLIENT_SECRET"
    )
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            print_error "Required environment variable $var is not set."
            exit 1
        fi
    done
    
    print_success "All required environment variables are set."
}

# Install Python dependencies
install_dependencies() {
    print_status "Installing Python dependencies..."
    
    if [ -f "requirements.txt" ]; then
        pip3 install -r requirements.txt
        print_success "Python dependencies installed."
    else
        print_error "requirements.txt not found."
        exit 1
    fi
}

# Create Azure Bot Service
create_bot_service() {
    print_status "Creating Azure Bot Service..."
    
    # Check if bot service already exists
    if az bot show --name "$BOT_SERVICE_NAME" --resource-group "$AZURE_RESOURCE_GROUP" &> /dev/null; then
        print_warning "Bot service $BOT_SERVICE_NAME already exists. Skipping creation."
        return
    fi
    
    # Create the bot service
    az bot create \
        --name "$BOT_SERVICE_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --kind "sdk" \
        --sku "F0" \
        --app-id "$MICROSOFT_APP_ID" \
        --app-password "$MICROSOFT_APP_PASSWORD" \
        --endpoint "https://$BOT_SERVICE_NAME.azurewebsites.net/api/messages" \
        --description "Microsoft 365 RAG Agent Bot" \
        --display-name "RAG Agent Bot"
    
    print_success "Azure Bot Service created successfully."
}

# Configure Microsoft Teams channel
configure_teams_channel() {
    print_status "Configuring Microsoft Teams channel..."
    
    # Enable Teams channel
    az bot msteams create \
        --name "$BOT_SERVICE_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP"
    
    print_success "Microsoft Teams channel configured successfully."
}

# Deploy the agent application
deploy_agent() {
    print_status "Deploying agent application..."
    
    # Create deployment package
    print_status "Creating deployment package..."
    
    # Create a temporary directory for deployment
    DEPLOY_DIR="deploy_temp"
    mkdir -p "$DEPLOY_DIR"
    
    # Copy necessary files
    cp -r . "$DEPLOY_DIR/"
    cd "$DEPLOY_DIR"
    
    # Remove unnecessary files
    rm -rf tests/ scripts/ .git/ __pycache__/ .pytest_cache/
    rm -f .env .env.test .env.example
    
    # Create deployment zip
    zip -r ../agent-deployment.zip .
    cd ..
    rm -rf "$DEPLOY_DIR"
    
    print_success "Deployment package created: agent-deployment.zip"
    
    # Deploy to Azure Web App (if using App Service)
    if [ "$DEPLOYMENT_METHOD" = "appservice" ]; then
        print_status "Deploying to Azure App Service..."
        
        # Create App Service if it doesn't exist
        if ! az webapp show --name "$BOT_SERVICE_NAME" --resource-group "$AZURE_RESOURCE_GROUP" &> /dev/null; then
            az webapp create \
                --name "$BOT_SERVICE_NAME" \
                --resource-group "$AZURE_RESOURCE_GROUP" \
                --plan "$APP_SERVICE_PLAN" \
                --runtime "PYTHON|3.11"
        fi
        
        # Deploy the application
        az webapp deployment source config-zip \
            --name "$BOT_SERVICE_NAME" \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --src "agent-deployment.zip"
        
        print_success "Application deployed to Azure App Service."
    fi
    
    # Clean up deployment package
    rm -f agent-deployment.zip
}

# Configure application settings
configure_app_settings() {
    print_status "Configuring application settings..."
    
    # Set environment variables for the bot service
    az bot update \
        --name "$BOT_SERVICE_NAME" \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --endpoint "https://$BOT_SERVICE_NAME.azurewebsites.net/api/messages"
    
    # Configure app settings if using App Service
    if [ "$DEPLOYMENT_METHOD" = "appservice" ]; then
        az webapp config appsettings set \
            --name "$BOT_SERVICE_NAME" \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --settings \
                "BACKEND_URL=$BACKEND_URL" \
                "TENANT_ID=$TENANT_ID" \
                "CLIENT_ID=$CLIENT_ID" \
                "CLIENT_SECRET=$CLIENT_SECRET" \
                "MICROSOFT_APP_ID=$MICROSOFT_APP_ID" \
                "MICROSOFT_APP_PASSWORD=$MICROSOFT_APP_PASSWORD" \
                "AGENT_NAME=$AGENT_NAME" \
                "AGENT_DESCRIPTION=$AGENT_DESCRIPTION"
    fi
    
    print_success "Application settings configured."
}

# Create Teams app package
create_teams_app() {
    print_status "Creating Teams app package..."
    
    # Create Teams app manifest
    cat > teams-app-manifest.json << EOF
{
  "\$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.16/MicrosoftTeams.schema.json",
  "manifestVersion": "1.16",
  "version": "1.0.0",
  "id": "$MICROSOFT_APP_ID",
  "packageName": "com.yourorganization.ragagent",
  "developer": {
    "name": "Your Organization",
    "websiteUrl": "https://your-organization.com",
    "privacyUrl": "https://your-organization.com/privacy",
    "termsOfUseUrl": "https://your-organization.com/terms"
  },
  "icons": {
    "outline": "outline.png",
    "color": "color.png"
  },
  "name": {
    "short": "RAG Agent",
    "full": "Microsoft 365 RAG Agent"
  },
  "description": {
    "short": "AI-powered document search and analysis assistant",
    "full": "Microsoft 365 RAG Agent for structural engineering document search and analysis"
  },
  "accentColor": "#FFFFFF",
  "bots": [
    {
      "botId": "$MICROSOFT_APP_ID",
      "scopes": ["personal", "team", "groupchat"],
      "commandLists": [],
      "isNotificationOnly": false,
      "supportsCalling": false,
      "supportsVideo": false,
      "supportsFiles": true
    }
  ],
  "composeExtensions": [],
  "permissions": [
    "identity",
    "messageTeamMembers"
  ],
  "validDomains": []
}
EOF
    
    # Create Teams app package
    zip -r teams-app-package.zip teams-app-manifest.json
    
    print_success "Teams app package created: teams-app-package.zip"
    print_status "Upload this package to Teams Admin Center or distribute to users."
}

# Main deployment function
main() {
    print_status "Starting Microsoft 365 Agent deployment..."
    
    # Set default deployment method
    DEPLOYMENT_METHOD=${DEPLOYMENT_METHOD:-"appservice"}
    
    check_prerequisites
    load_environment
    install_dependencies
    create_bot_service
    configure_teams_channel
    deploy_agent
    configure_app_settings
    create_teams_app
    
    print_success "Microsoft 365 Agent deployment completed successfully!"
    print_status "Next steps:"
    print_status "1. Upload teams-app-package.zip to Teams Admin Center"
    print_status "2. Configure your Microsoft 365 tenant permissions"
    print_status "3. Test the bot in Microsoft Teams"
    print_status "4. Distribute the Teams app to your organization"
}

# Run main function
main "$@"