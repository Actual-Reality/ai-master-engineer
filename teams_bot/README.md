# Teams Bot for Azure Search OpenAI Demo

This Teams bot provides a conversational interface to your existing Azure Search OpenAI RAG pipeline, allowing users to ask questions and receive AI-powered answers with citations directly in Microsoft Teams.

## Architecture

```
Teams User → Teams Bot → RAG Bridge → Existing Backend API → Azure OpenAI + Search
```

## Features

- 🤖 Natural conversation in Teams (personal, group chats, channels)
- 📚 Rich responses with source citations using Adaptive Cards
- 💬 Persistent conversation history with Azure Table Storage
- 🔐 Managed identity authentication for secure Azure integration
- 🔍 Integration with existing RAG pipeline
- ⚡ Commands: `/help`, `/clear`

## Quick Start

### Prerequisites

- Python 3.11+
- Azure CLI installed and logged in
- Existing azure-search-openai-demo deployment
- Teams admin access for app installation

### 1. Local Development Setup

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export MicrosoftAppId=""  # Leave empty for local testing
export MicrosoftAppPassword=""  # Leave empty for local testing
export RAG_BACKEND_URL="http://localhost:50505"  # Your backend URL

# Run locally
python app.py
```

### 2. Test with Bot Framework Emulator

1. Download [Bot Framework Emulator](https://github.com/Microsoft/BotFramework-Emulator)
2. Connect to `http://localhost:3978/api/messages`
3. Test bot responses and conversation flow

### 3. Deploy to Azure

```bash
# Run deployment script
../scripts/deploy-teams-bot.sh

# Follow the output instructions for:
# - Git deployment
# - Teams manifest creation
# - App installation
```

## File Structure

```
teams_bot/
├── app.py                    # Main bot application (aiohttp server)
├── teams_bot.py             # Core bot logic and message handling
├── rag_bridge.py            # Integration with existing RAG pipeline
├── conversation_storage.py  # Persistent conversation state management
├── requirements.txt         # Python dependencies
├── Dockerfile              # Container deployment
├── DEPLOYMENT.md           # Detailed deployment guide
├── README.md               # This file
└── manifest/
    └── manifest.json       # Teams app manifest template

../scripts/
├── deploy-teams-bot.sh     # Azure deployment script
├── create-manifest.sh      # Teams app manifest generator
└── test-local.sh          # Local development testing

../tests/
├── test-bot.py                      # Bot component tests
├── test_conversation_storage.py     # Storage functionality tests
└── test_managed_identity_storage.py # Azure storage tests
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MicrosoftAppId` | Bot Framework App ID | "" |
| `MicrosoftAppPassword` | Bot Framework App Password | "" |
| `MicrosoftAppType` | App type (MultiTenant/SingleTenant) | "MultiTenant" |
| `RAG_BACKEND_URL` | Your existing backend API URL | "https://capps-backend-nnsnw2zar7dok.salmoncliff-681251ec.eastus.azurecontainerapps.io" |
| `AZURE_STORAGE_ACCOUNT_NAME` | Storage account for conversation persistence | "stnnsnw2zar7dok" |

### RAG Backend Integration

The bot connects to your existing backend via the `/chat` endpoint with this payload:

```json
{
  "messages": [
    {"role": "user", "content": "user question"}
  ],
  "context": {
    "overrides": {
      "top": 3,
      "temperature": 0.3,
      "minimum_search_score": 0.0,
      "minimum_reranker_score": 0.0
    }
  }
}
```

## Deployment Options

### Option 1: Azure App Service (Recommended)

```bash
../scripts/deploy-teams-bot.sh
```

This creates:
- Resource group
- Entra ID app registration
- App Service plan and web app
- Azure Bot Service
- Teams channel configuration

### Option 2: Container Deployment

```bash
# Build container
docker build -t teams-search-bot .

# Run locally
docker run -p 3978:3978 \
  -e RAG_BACKEND_URL="your-backend-url" \
  teams-search-bot

# Deploy to Azure Container Apps
az containerapp create \
  --resource-group rg-teams-search-bot \
  --name teams-search-bot \
  --image teams-search-bot \
  --target-port 3978 \
  --ingress external
```

## Teams App Installation

### 1. Create App Package

```bash
# Generate manifest with your App ID
../scripts/create-manifest.sh <YOUR-APP-ID>

# This creates teams-app-package.zip
```

### 2. Install in Teams

**Option A: Teams Admin Center**
1. Go to Teams Admin Center → Teams apps → Manage apps
2. Upload `teams-app-package.zip`
3. Set permissions and availability

**Option B: Developer Portal**
1. Go to [Teams Developer Portal](https://dev.teams.microsoft.com/)
2. Import app package
3. Publish to your organization

**Option C: Sideload (Development)**
1. In Teams, go to Apps → Manage your apps
2. Upload a custom app → Upload `teams-app-package.zip`

## Usage

### Starting a Conversation

**Personal Chat:**
- Search for "AI Search Assistant" in Teams
- Start typing questions directly

**Group Chat/Channel:**
- Add the bot to the chat/channel
- @mention the bot: `@AI Search Assistant what is our vacation policy?`

### Example Interactions

```
User: What's our company vacation policy?
Bot: [Adaptive Card with answer and source citations]

User: /help
Bot: [Help card with commands and examples]

User: /clear
Bot: ✅ Conversation history cleared!
```

## Troubleshooting

### Common Issues

**Bot not responding:**
- Check endpoint URL in Azure Bot registration
- Verify App ID and password in app settings
- Ensure Teams channel is enabled

**RAG integration errors:**
- Verify `RAG_BACKEND_URL` is accessible
- Check backend API is running and responding
- Validate API payload format

**Authentication issues:**
- Confirm Entra ID app permissions
- Check App ID/password configuration
- Verify bot registration settings

### Debugging

```bash
# Check logs in Azure
az webapp log tail --resource-group rg-teams-search-bot --name your-web-app

# Local debugging
python app.py  # Check console output for errors
```

## Security Considerations

- Store secrets in Azure Key Vault
- Use managed identity for Azure services
- Implement proper error handling
- Monitor conversation logs for sensitive data

## Performance Optimization

- Connection pooling for backend calls
- Caching for frequent queries
- Persistent conversation state with Azure Table Storage and managed identity
- Rate limiting for API calls
- Automatic conversation history cleanup (keeps last 20 messages)

## Monitoring

- Application Insights for telemetry
- Bot Analytics in Azure portal
- Custom metrics for conversation success rates
- Error rate and response time alerts

## Contributing

1. Test changes locally with Bot Framework Emulator
2. Validate RAG integration with your backend
3. Test in Teams before deploying to production
4. Update documentation for new features
