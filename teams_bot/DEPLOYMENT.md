# Teams Bot Deployment Guide

## Overview

This guide walks through deploying the Teams bot that integrates with your existing Azure Search OpenAI RAG pipeline.

## Prerequisites Checklist

- [ ] Azure CLI installed and authenticated (`az login`)
- [ ] Existing azure-search-openai-demo deployment running
- [ ] Teams admin permissions for app installation
- [ ] Python 3.11+ for local testing

## Deployment Steps

### 1. Local Testing (Recommended First)

```bash
cd teams_bot

# Test the bot components
python ../tests/test-bot.py

# Run bot locally
../scripts/test-local.sh
```

**Test with Bot Framework Emulator:**
1. Download [Bot Framework Emulator](https://github.com/Microsoft/BotFramework-Emulator)
2. Connect to `http://localhost:3978/api/messages`
3. Test conversation flow and responses

### 2. Azure Deployment

```bash
# Deploy all Azure resources
../scripts/deploy-teams-bot.sh
```

This script will:
- Create resource group `rg-teams-search-bot`
- Create Entra ID app registration
- Deploy to Azure App Service
- Configure Azure Bot Service
- Enable Teams channel

**Expected Output:**
```
✅ Azure resources created successfully!

📋 Deployment Summary:
- Resource Group: rg-teams-search-bot
- Bot Name: teams-search-bot
- Web App: teams-search-bot-1694123456
- App ID: 12345678-1234-1234-1234-123456789012
- Web App URL: https://teams-search-bot-1694123456.azurewebsites.net
```

### 3. Deploy Code to Azure

```bash
# Add Azure Git remote (from deployment script output)
git remote add azure https://teams-search-bot-1694123456.scm.azurewebsites.net:443/teams-search-bot-1694123456.git

# Commit and push
git add .
git commit -m "Deploy Teams bot"
git push azure main
```

### 4. Create Teams App Package

```bash
# Generate manifest with your App ID (from deployment output)
../scripts/create-manifest.sh 12345678-1234-1234-1234-123456789012

# This creates teams-app-package.zip
```

### 5. Install in Teams

**Option A: Teams Admin Center**
1. Go to [Teams Admin Center](https://admin.teams.microsoft.com)
2. Navigate to Teams apps → Manage apps
3. Click "Upload new app" → Upload `teams-app-package.zip`
4. Set availability and permissions

**Option B: Developer Portal**
1. Go to [Teams Developer Portal](https://dev.teams.microsoft.com/)
2. Click "Import app" → Upload `teams-app-package.zip`
3. Publish to your organization

## Configuration

### Environment Variables

The bot uses these environment variables (automatically configured by deployment script):

| Variable | Description | Example |
|----------|-------------|---------|
| `MicrosoftAppId` | Bot Framework App ID | `12345678-1234-1234-1234-123456789012` |
| `MicrosoftAppPassword` | Bot Framework App Secret | `your-secret-here` |
| `RAG_BACKEND_URL` | Your existing backend URL | `https://your-backend.azurewebsites.net` |

### Backend Integration

The bot connects to your existing RAG backend via the `/chat` endpoint. Ensure your backend is accessible and responding to requests.

## Testing in Teams

### 1. Personal Chat
1. Search for "AI Search Assistant" in Teams
2. Start a conversation: "What is our vacation policy?"
3. Verify response with citations

### 2. Group Chat/Channel
1. Add bot to chat/channel
2. @mention: `@AI Search Assistant tell me about Q3 results`
3. Test commands: `/help`, `/clear`

### 3. Expected Behavior
- Rich Adaptive Card responses
- Source citations displayed
- Conversation context maintained
- Commands working properly

## Troubleshooting

### Bot Not Responding
```bash
# Check Azure App Service logs
az webapp log tail --resource-group rg-teams-search-bot --name your-web-app-name

# Verify bot registration
az bot show --resource-group rg-teams-search-bot --name teams-search-bot
```

**Common Issues:**
- Incorrect endpoint URL in bot registration
- App ID/password mismatch
- Teams channel not enabled
- Backend URL not accessible

### RAG Integration Issues
```bash
# Test backend connectivity
curl -X POST https://your-backend.azurewebsites.net/chat \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"test"}]}'
```

**Common Issues:**
- Backend not running or accessible
- Authentication required for backend
- API payload format mismatch

### Authentication Errors
- Verify App ID in Azure portal matches manifest
- Check App secret is correctly configured
- Ensure bot registration endpoint is correct

## Monitoring and Maintenance

### Application Insights
The bot automatically logs to Application Insights (if configured in your Azure environment):
- Conversation metrics
- Error rates
- Response times
- User engagement

### Health Checks
```bash
# Test bot endpoint
curl https://your-teams-bot.azurewebsites.net/api/messages

# Check backend connectivity
curl https://your-backend.azurewebsites.net/health
```

### Updates and Maintenance
1. Update code in repository
2. Push to Azure: `git push azure main`
3. Monitor deployment logs
4. Test functionality in Teams

## Security Considerations

- App secrets stored in Azure App Service configuration
- Bot only accessible via Teams (no direct web interface)
- Backend integration uses HTTPS
- Consider implementing user authentication if needed

## Cost Optimization

- Use B1 App Service plan for development
- Scale up for production usage
- Monitor resource utilization
- Consider Azure Container Apps for better cost efficiency

## Success Criteria

✅ **Deployment Successful When:**
- Bot responds in Teams personal chat
- Bot responds to @mentions in channels
- Citations display correctly in Adaptive Cards
- Commands (`/help`, `/clear`) work
- Conversation context is maintained
- Backend integration returns relevant results

## Support and Documentation

- [Bot Framework Documentation](https://docs.microsoft.com/en-us/azure/bot-service/)
- [Teams App Development](https://docs.microsoft.com/en-us/microsoftteams/platform/)
- [Azure App Service](https://docs.microsoft.com/en-us/azure/app-service/)

## Next Steps After Deployment

1. **User Training**: Create documentation for end users
2. **Monitoring Setup**: Configure alerts and dashboards
3. **Feedback Collection**: Gather user feedback for improvements
4. **Feature Enhancement**: Add new capabilities based on usage patterns
