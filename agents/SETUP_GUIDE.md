# Teams 365 SDK Integration Setup Guide

This guide will help you set up and test the Teams 365 SDK integration for the AI Master Engineer project.

## ✅ What's Already Implemented

The following components have been implemented and are ready for testing:

1. **TeamsHandler** - Complete Teams-specific message handler with adaptive cards
2. **TeamsResponseAdapter** - Teams-specific response formatting
3. **TeamsComponents** - Adaptive card components for Teams UI
4. **TeamsTextConstants** - All text constants and formatting
5. **RAGService Integration** - Backend API integration for document search
6. **AuthService** - Microsoft 365 authentication
7. **Test Suite** - Comprehensive unit and integration tests

## 🚀 Quick Start

### 1. Environment Setup

```bash
# Navigate to the agents directory
cd agents

# Create virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env  # or use your preferred editor
```

Required environment variables:
```bash
# Bot Framework Configuration
MICROSOFT_APP_ID=your_bot_app_id_here
MICROSOFT_APP_PASSWORD=your_bot_app_password_here

# Microsoft 365 Configuration
AZURE_TENANT_ID=your_tenant_id_here
AZURE_CLIENT_ID=your_client_id_here
AZURE_CLIENT_SECRET=your_client_secret_here

# Backend API Configuration
BACKEND_URL=http://localhost:50505

# Azure OpenAI Configuration (reuse from existing app)
AZURE_OPENAI_ENDPOINT=your_openai_endpoint_here
AZURE_OPENAI_API_KEY=your_openai_key_here
AZURE_OPENAI_CHATGPT_DEPLOYMENT=your_deployment_name_here

# Azure Search Configuration (reuse from existing app)
AZURE_SEARCH_ENDPOINT=your_search_endpoint_here
AZURE_SEARCH_KEY=your_search_key_here
AZURE_SEARCH_INDEX=your_search_index_here
```

### 3. Start Backend Service

```bash
# In a separate terminal, start the backend
cd ../app/backend
python main.py
```

Ensure the backend is running on `http://localhost:50505`.

### 4. Run Tests

```bash
# Run unit tests
python -m pytest tests/ -v

# Run integration tests
python scripts/test_teams_integration.py
python scripts/test_backend_integration.py

# Run implementation test
python test_implementation.py
```

### 5. Start Agent Server

```bash
# Start the Teams agent server
python main.py
```

## 🔧 Azure Setup

### 1. Create Bot Framework App

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to "Azure Bot" → "Create"
3. Fill in the required details:
   - **Bot handle**: `ai-master-engineer-teams`
   - **Subscription**: Your subscription
   - **Resource group**: Your resource group
   - **Pricing tier**: F0 (Free) or S1 (Standard)
   - **Type of App**: Multi-tenant
4. Click "Review + Create" → "Create"

### 2. Configure Teams Channel

1. In your Azure Bot resource, go to "Channels"
2. Click "Microsoft Teams" → "Apply"
3. Agree to the terms of service

### 3. Set Messaging Endpoint

1. In your Azure Bot resource, go to "Configuration"
2. Set **Messaging endpoint** to: `https://your-domain.com/api/messages`
3. For local testing, use ngrok: `https://your-ngrok-url.ngrok.io/api/messages`

### 4. Get App Credentials

1. In your Azure Bot resource, go to "Configuration"
2. Copy the **Microsoft App ID** and **Microsoft App Password**
3. Add these to your `.env` file

## 🧪 Testing

### Unit Tests

```bash
# Run all unit tests
python -m pytest tests/ -v

# Run specific test file
python -m pytest tests/test_teams_handler.py -v

# Run with coverage
python -m pytest tests/ --cov=. --cov-report=html
```

### Integration Tests

```bash
# Test Teams integration
python scripts/test_teams_integration.py

# Test backend integration
python scripts/test_backend_integration.py
```

### Manual Testing

1. **Start the agent server**:
   ```bash
   python main.py
   ```

2. **Test with ngrok** (for local development):
   ```bash
   # Install ngrok
   npm install -g ngrok
   
   # Expose local server
   ngrok http 5000
   
   # Use the ngrok URL in your bot's messaging endpoint
   ```

3. **Test in Teams**:
   - Add your bot to a Teams channel
   - Mention the bot: `@RAG Assistant help`
   - Upload a document and ask questions
   - Test adaptive card interactions

## 📁 Project Structure

```
agents/
├── handlers/
│   ├── message_handler.py      # Base message handler
│   └── teams_handler.py        # Teams-specific handler
├── services/
│   ├── rag_service.py          # RAG service for document search
│   └── auth_service.py         # Microsoft 365 authentication
├── adapters/
│   ├── response_adapter.py     # Base response adapter
│   └── teams_response_adapter.py # Teams response adapter
├── components/
│   └── teams_components.py     # Teams UI components
├── constants/
│   └── teams_text.py           # Text constants
├── tests/                       # Unit tests
├── scripts/                     # Integration test scripts
├── requirements.txt            # Dependencies
├── .env.example               # Environment template
└── main.py                    # Main application entry point
```

## 🔍 Key Features

### Adaptive Cards
- Rich welcome cards with bot information
- Interactive help cards with quick actions
- Response cards with sources and citations
- Action buttons for follow-up questions

### Teams Integration
- Bot mention detection and removal
- File upload handling
- Channel and team context extraction
- Microsoft 365 authentication

### RAG Integration
- Document search and retrieval
- Conversation history management
- Source citation and transparency
- Token usage tracking

## 🐛 Troubleshooting

### Common Issues

1. **Import Errors**:
   ```bash
   # Ensure virtual environment is activated
   source venv/bin/activate
   
   # Reinstall dependencies
   pip install -r requirements.txt
   ```

2. **Backend Connection Issues**:
   - Ensure backend is running on `http://localhost:50505`
   - Check `BACKEND_URL` in `.env` file
   - Verify backend API endpoints are accessible

3. **Authentication Issues**:
   - Verify Azure app registration credentials
   - Check tenant ID and client ID/secret
   - Ensure proper permissions are granted

4. **Teams Bot Issues**:
   - Verify messaging endpoint is correct
   - Check bot is added to Teams channel
   - Ensure bot has proper permissions

### Debug Mode

```bash
# Enable debug logging
export LOG_LEVEL=DEBUG
python main.py
```

## 📚 Next Steps

1. **Complete Azure Setup**: Register bot and configure Teams channel
2. **Test Integration**: Run all tests and verify functionality
3. **Deploy**: Deploy to Azure App Service or Container Apps
4. **Monitor**: Set up logging and monitoring
5. **Scale**: Configure for production use

## 🤝 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the test output for specific errors
3. Check Azure Bot logs in the Azure Portal
4. Verify all environment variables are set correctly

---

**Ready to test!** 🚀

Follow the steps above to get your Teams 365 SDK integration up and running.