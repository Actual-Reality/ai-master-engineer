# Microsoft 365 Agent Deployment Script (PowerShell)
# This script deploys the Microsoft 365 RAG Agent to Azure

param(
    [string]$DeploymentMethod = "appservice",
    [string]$EnvironmentFile = ".env"
)

# Function to print colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check if required tools are installed
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI is not installed. Please install it first."
        exit 1
    }
    
    # Check if Python is installed
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        Write-Error "Python is not installed. Please install it first."
        exit 1
    }
    
    # Check if pip is installed
    if (-not (Get-Command pip -ErrorAction SilentlyContinue)) {
        Write-Error "pip is not installed. Please install it first."
        exit 1
    }
    
    Write-Success "All prerequisites are installed."
}

# Load environment variables
function Load-Environment {
    Write-Status "Loading environment variables..."
    
    if (Test-Path $EnvironmentFile) {
        Get-Content $EnvironmentFile | ForEach-Object {
            if ($_ -match '^([^#][^=]+)=(.*)$') {
                [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
            }
        }
        Write-Success "Environment variables loaded from $EnvironmentFile file."
    } else {
        Write-Warning "No $EnvironmentFile file found. Using system environment variables."
    }
    
    # Required environment variables
    $RequiredVars = @(
        "AZURE_SUBSCRIPTION_ID",
        "AZURE_RESOURCE_GROUP",
        "AZURE_LOCATION",
        "BOT_SERVICE_NAME",
        "MICROSOFT_APP_ID",
        "MICROSOFT_APP_PASSWORD",
        "BACKEND_URL",
        "TENANT_ID",
        "CLIENT_ID",
        "CLIENT_SECRET"
    )
    
    foreach ($var in $RequiredVars) {
        if (-not [Environment]::GetEnvironmentVariable($var)) {
            Write-Error "Required environment variable $var is not set."
            exit 1
        }
    }
    
    Write-Success "All required environment variables are set."
}

# Install Python dependencies
function Install-Dependencies {
    Write-Status "Installing Python dependencies..."
    
    if (Test-Path "requirements.txt") {
        pip install -r requirements.txt
        Write-Success "Python dependencies installed."
    } else {
        Write-Error "requirements.txt not found."
        exit 1
    }
}

# Create Azure Bot Service
function New-BotService {
    Write-Status "Creating Azure Bot Service..."
    
    $BotServiceName = [Environment]::GetEnvironmentVariable("BOT_SERVICE_NAME")
    $ResourceGroup = [Environment]::GetEnvironmentVariable("AZURE_RESOURCE_GROUP")
    $Location = [Environment]::GetEnvironmentVariable("AZURE_LOCATION")
    $AppId = [Environment]::GetEnvironmentVariable("MICROSOFT_APP_ID")
    $AppPassword = [Environment]::GetEnvironmentVariable("MICROSOFT_APP_PASSWORD")
    
    # Check if bot service already exists
    $BotExists = az bot show --name $BotServiceName --resource-group $ResourceGroup 2>$null
    if ($BotExists) {
        Write-Warning "Bot service $BotServiceName already exists. Skipping creation."
        return
    }
    
    # Create the bot service
    az bot create `
        --name $BotServiceName `
        --resource-group $ResourceGroup `
        --location $Location `
        --kind "sdk" `
        --sku "F0" `
        --app-id $AppId `
        --app-password $AppPassword `
        --endpoint "https://$BotServiceName.azurewebsites.net/api/messages" `
        --description "Microsoft 365 RAG Agent Bot" `
        --display-name "RAG Agent Bot"
    
    Write-Success "Azure Bot Service created successfully."
}

# Configure Microsoft Teams channel
function Set-TeamsChannel {
    Write-Status "Configuring Microsoft Teams channel..."
    
    $BotServiceName = [Environment]::GetEnvironmentVariable("BOT_SERVICE_NAME")
    $ResourceGroup = [Environment]::GetEnvironmentVariable("AZURE_RESOURCE_GROUP")
    
    # Enable Teams channel
    az bot msteams create `
        --name $BotServiceName `
        --resource-group $ResourceGroup
    
    Write-Success "Microsoft Teams channel configured successfully."
}

# Deploy the agent application
function Deploy-Agent {
    Write-Status "Deploying agent application..."
    
    $BotServiceName = [Environment]::GetEnvironmentVariable("BOT_SERVICE_NAME")
    $ResourceGroup = [Environment]::GetEnvironmentVariable("AZURE_RESOURCE_GROUP")
    
    # Create deployment package
    Write-Status "Creating deployment package..."
    
    # Create a temporary directory for deployment
    $DeployDir = "deploy_temp"
    New-Item -ItemType Directory -Path $DeployDir -Force | Out-Null
    
    # Copy necessary files
    Copy-Item -Path "." -Destination $DeployDir -Recurse -Exclude @("tests", "scripts", ".git", "__pycache__", ".pytest_cache", ".env*")
    
    Set-Location $DeployDir
    
    # Create deployment zip
    Compress-Archive -Path "*" -DestinationPath "../agent-deployment.zip" -Force
    
    Set-Location ".."
    Remove-Item -Path $DeployDir -Recurse -Force
    
    Write-Success "Deployment package created: agent-deployment.zip"
    
    # Deploy to Azure Web App (if using App Service)
    if ($DeploymentMethod -eq "appservice") {
        Write-Status "Deploying to Azure App Service..."
        
        $AppServicePlan = [Environment]::GetEnvironmentVariable("APP_SERVICE_PLAN")
        
        # Create App Service if it doesn't exist
        $AppExists = az webapp show --name $BotServiceName --resource-group $ResourceGroup 2>$null
        if (-not $AppExists) {
            az webapp create `
                --name $BotServiceName `
                --resource-group $ResourceGroup `
                --plan $AppServicePlan `
                --runtime "PYTHON|3.11"
        }
        
        # Deploy the application
        az webapp deployment source config-zip `
            --name $BotServiceName `
            --resource-group $ResourceGroup `
            --src "agent-deployment.zip"
        
        Write-Success "Application deployed to Azure App Service."
    }
    
    # Clean up deployment package
    Remove-Item -Path "agent-deployment.zip" -Force
}

# Configure application settings
function Set-AppSettings {
    Write-Status "Configuring application settings..."
    
    $BotServiceName = [Environment]::GetEnvironmentVariable("BOT_SERVICE_NAME")
    $ResourceGroup = [Environment]::GetEnvironmentVariable("AZURE_RESOURCE_GROUP")
    $BackendUrl = [Environment]::GetEnvironmentVariable("BACKEND_URL")
    $TenantId = [Environment]::GetEnvironmentVariable("TENANT_ID")
    $ClientId = [Environment]::GetEnvironmentVariable("CLIENT_ID")
    $ClientSecret = [Environment]::GetEnvironmentVariable("CLIENT_SECRET")
    $AppId = [Environment]::GetEnvironmentVariable("MICROSOFT_APP_ID")
    $AppPassword = [Environment]::GetEnvironmentVariable("MICROSOFT_APP_PASSWORD")
    $AgentName = [Environment]::GetEnvironmentVariable("AGENT_NAME")
    $AgentDescription = [Environment]::GetEnvironmentVariable("AGENT_DESCRIPTION")
    
    # Set environment variables for the bot service
    az bot update `
        --name $BotServiceName `
        --resource-group $ResourceGroup `
        --endpoint "https://$BotServiceName.azurewebsites.net/api/messages"
    
    # Configure app settings if using App Service
    if ($DeploymentMethod -eq "appservice") {
        az webapp config appsettings set `
            --name $BotServiceName `
            --resource-group $ResourceGroup `
            --settings `
                "BACKEND_URL=$BackendUrl" `
                "TENANT_ID=$TenantId" `
                "CLIENT_ID=$ClientId" `
                "CLIENT_SECRET=$ClientSecret" `
                "MICROSOFT_APP_ID=$AppId" `
                "MICROSOFT_APP_PASSWORD=$AppPassword" `
                "AGENT_NAME=$AgentName" `
                "AGENT_DESCRIPTION=$AgentDescription"
    }
    
    Write-Success "Application settings configured."
}

# Create Teams app package
function New-TeamsApp {
    Write-Status "Creating Teams app package..."
    
    $AppId = [Environment]::GetEnvironmentVariable("MICROSOFT_APP_ID")
    
    # Create Teams app manifest
    $Manifest = @{
        '$schema' = 'https://developer.microsoft.com/en-us/json-schemas/teams/v1.16/MicrosoftTeams.schema.json'
        manifestVersion = '1.16'
        version = '1.0.0'
        id = $AppId
        packageName = 'com.yourorganization.ragagent'
        developer = @{
            name = 'Your Organization'
            websiteUrl = 'https://your-organization.com'
            privacyUrl = 'https://your-organization.com/privacy'
            termsOfUseUrl = 'https://your-organization.com/terms'
        }
        icons = @{
            outline = 'outline.png'
            color = 'color.png'
        }
        name = @{
            short = 'RAG Agent'
            full = 'Microsoft 365 RAG Agent'
        }
        description = @{
            short = 'AI-powered document search and analysis assistant'
            full = 'Microsoft 365 RAG Agent for structural engineering document search and analysis'
        }
        accentColor = '#FFFFFF'
        bots = @(
            @{
                botId = $AppId
                scopes = @('personal', 'team', 'groupchat')
                commandLists = @()
                isNotificationOnly = $false
                supportsCalling = $false
                supportsVideo = $false
                supportsFiles = $true
            }
        )
        composeExtensions = @()
        permissions = @('identity', 'messageTeamMembers')
        validDomains = @()
    }
    
    $Manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath "teams-app-manifest.json" -Encoding UTF8
    
    # Create Teams app package
    Compress-Archive -Path "teams-app-manifest.json" -DestinationPath "teams-app-package.zip" -Force
    
    Write-Success "Teams app package created: teams-app-package.zip"
    Write-Status "Upload this package to Teams Admin Center or distribute to users."
}

# Main deployment function
function Main {
    Write-Status "Starting Microsoft 365 Agent deployment..."
    
    Test-Prerequisites
    Load-Environment
    Install-Dependencies
    New-BotService
    Set-TeamsChannel
    Deploy-Agent
    Set-AppSettings
    New-TeamsApp
    
    Write-Success "Microsoft 365 Agent deployment completed successfully!"
    Write-Status "Next steps:"
    Write-Status "1. Upload teams-app-package.zip to Teams Admin Center"
    Write-Status "2. Configure your Microsoft 365 tenant permissions"
    Write-Status "3. Test the bot in Microsoft Teams"
    Write-Status "4. Distribute the Teams app to your organization"
}

# Run main function
Main