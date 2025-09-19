# Microsoft 365 RAG Agent Deployment Guide

This guide provides comprehensive instructions for deploying the Microsoft 365 RAG Agent across different platforms and environments.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Azure Bot Service Deployment](#azure-bot-service-deployment)
4. [Container Deployment](#container-deployment)
5. [Kubernetes Deployment](#kubernetes-deployment)
6. [Teams App Configuration](#teams-app-configuration)
7. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)

## Prerequisites

### Required Tools
- Azure CLI (latest version)
- Python 3.11+
- Docker (for containerized deployment)
- kubectl (for Kubernetes deployment)
- PowerShell (for Windows deployment scripts)

### Required Azure Resources
- Azure Subscription
- Azure Resource Group
- Azure Bot Service
- Microsoft 365 App Registration
- Azure Container Registry (for container deployment)
- Azure Key Vault (for secrets management)

## Environment Setup

### 1. Create Environment File

Create a `.env` file in the agents directory:

```bash
# Azure Configuration
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_RESOURCE_GROUP=your-resource-group
AZURE_LOCATION=East US

# Bot Service Configuration
BOT_SERVICE_NAME=your-bot-service-name
MICROSOFT_APP_ID=your-microsoft-app-id
MICROSOFT_APP_PASSWORD=your-microsoft-app-password

# Backend Configuration
BACKEND_URL=https://your-backend.azurewebsites.net

# Microsoft 365 Configuration
TENANT_ID=your-tenant-id
CLIENT_ID=your-client-id
CLIENT_SECRET=your-client-secret

# Agent Configuration
AGENT_NAME=Structural Engineering Assistant
AGENT_DESCRIPTION=AI-powered structural engineering document search and analysis assistant

# Optional: App Service Configuration
APP_SERVICE_PLAN=your-app-service-plan
```

### 2. Microsoft 365 App Registration

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** > **App registrations**
3. Click **New registration**
4. Configure the app:
   - **Name**: Microsoft 365 RAG Agent
   - **Supported account types**: Accounts in this organizational directory only
   - **Redirect URI**: Web - `https://your-bot-service.azurewebsites.net/api/messages`
5. After creation, note the **Application (client) ID**
6. Go to **Certificates & secrets** > **New client secret**
7. Create a secret and note the **Value**
8. Go to **API permissions** and add:
   - Microsoft Graph > User.Read
   - Microsoft Graph > Group.Read.All
   - Microsoft Graph > Directory.Read.All
9. Grant admin consent for the permissions

## Azure Bot Service Deployment

### Option 1: Automated Deployment (Recommended)

#### Linux/macOS
```bash
cd agents
chmod +x scripts/deploy-m365-agent.sh
./scripts/deploy-m365-agent.sh
```

#### Windows
```powershell
cd agents
.\scripts\deploy-m365-agent.ps1
```

### Option 2: Manual Deployment

1. **Create Bot Service**:
```bash
az bot create \
  --name "your-bot-service-name" \
  --resource-group "your-resource-group" \
  --location "East US" \
  --kind "sdk" \
  --sku "F0" \
  --app-id "your-microsoft-app-id" \
  --app-password "your-microsoft-app-password" \
  --endpoint "https://your-bot-service.azurewebsites.net/api/messages"
```

2. **Enable Teams Channel**:
```bash
az bot msteams create \
  --name "your-bot-service-name" \
  --resource-group "your-resource-group"
```

3. **Deploy Application**:
```bash
# Create deployment package
zip -r agent-deployment.zip . -x "tests/*" "scripts/*" ".git/*" "__pycache__/*"

# Deploy to App Service
az webapp deployment source config-zip \
  --name "your-bot-service-name" \
  --resource-group "your-resource-group" \
  --src "agent-deployment.zip"
```

## Container Deployment

### Docker Build and Run

1. **Build the container**:
```bash
docker build -t m365-agent .
```

2. **Run locally**:
```bash
docker run -p 8000:8000 \
  -e BACKEND_URL="https://your-backend.azurewebsites.net" \
  -e TENANT_ID="your-tenant-id" \
  -e CLIENT_ID="your-client-id" \
  -e CLIENT_SECRET="your-client-secret" \
  -e MICROSOFT_APP_ID="your-microsoft-app-id" \
  -e MICROSOFT_APP_PASSWORD="your-microsoft-app-password" \
  m365-agent
```

3. **Using Docker Compose**:
```bash
docker-compose up -d
```

### Azure Container Registry

1. **Create Container Registry**:
```bash
az acr create \
  --name "your-registry-name" \
  --resource-group "your-resource-group" \
  --sku "Basic"
```

2. **Build and push**:
```bash
az acr build --registry "your-registry-name" --image m365-agent .
```

3. **Deploy to Container Apps**:
```bash
az containerapp create \
  --name "m365-agent" \
  --resource-group "your-resource-group" \
  --environment "your-container-app-environment" \
  --image "your-registry-name.azurecr.io/m365-agent:latest" \
  --target-port 8000 \
  --ingress external
```

## Kubernetes Deployment

1. **Create namespace**:
```bash
kubectl create namespace m365-agent
```

2. **Create secrets**:
```bash
kubectl create secret generic m365-agent-secrets \
  --from-literal=backend-url="https://your-backend.azurewebsites.net" \
  --from-literal=tenant-id="your-tenant-id" \
  --from-literal=client-id="your-client-id" \
  --from-literal=client-secret="your-client-secret" \
  --from-literal=microsoft-app-id="your-microsoft-app-id" \
  --from-literal=microsoft-app-password="your-microsoft-app-password" \
  --namespace=m365-agent
```

3. **Deploy application**:
```bash
kubectl apply -f k8s/deployment.yaml
```

4. **Check deployment status**:
```bash
kubectl get pods -n m365-agent
kubectl get services -n m365-agent
```

## Teams App Configuration

### 1. Create Teams App Package

The deployment script automatically creates a `teams-app-package.zip` file. This contains:
- `teams-app-manifest.json` - Teams app manifest
- Required icons (outline.png, color.png)

### 2. Upload to Teams Admin Center

1. Go to [Teams Admin Center](https://admin.teams.microsoft.com)
2. Navigate to **Teams apps** > **Manage apps**
3. Click **Upload** and select `teams-app-package.zip`
4. Review and approve the app

### 3. Distribute to Organization

1. In Teams Admin Center, go to **Teams apps** > **Manage apps**
2. Find your app and click **Publish**
3. Select **Publish to your organization**
4. Configure permissions and policies as needed

## Monitoring and Troubleshooting

### Health Checks

The agent includes health check endpoints:
- **Health endpoint**: `GET /health`
- **Readiness endpoint**: `GET /ready`

### Logging

Logs are available in:
- **Azure Portal**: App Service > Logs
- **Container Logs**: `docker logs <container-id>`
- **Kubernetes Logs**: `kubectl logs -f deployment/m365-agent`

### Common Issues

1. **Authentication Errors**:
   - Verify Microsoft App ID and password
   - Check tenant ID and client credentials
   - Ensure proper permissions are granted

2. **Backend Connection Issues**:
   - Verify BACKEND_URL is correct
   - Check network connectivity
   - Ensure backend is running and accessible

3. **Teams Integration Issues**:
   - Verify Teams channel is enabled
   - Check app manifest configuration
   - Ensure proper permissions in Teams Admin Center

### Performance Tuning

1. **Scaling**:
   - Adjust replica count in Kubernetes
   - Configure auto-scaling rules
   - Monitor resource usage

2. **Caching**:
   - Enable token caching
   - Configure response caching
   - Monitor cache hit rates

## Security Considerations

1. **Secrets Management**:
   - Use Azure Key Vault for production
   - Rotate secrets regularly
   - Never commit secrets to source control

2. **Network Security**:
   - Use private endpoints where possible
   - Configure proper firewall rules
   - Enable HTTPS only

3. **Access Control**:
   - Implement proper RBAC
   - Use managed identities
   - Regular security audits

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review application logs
3. Contact your system administrator
4. Create an issue in the project repository