#!/bin/bash

# Local testing script for Teams bot
# This script sets up local environment and runs the bot for testing

set -e

echo "🧪 Setting up local Teams bot testing environment..."

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔄 Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "📥 Installing dependencies..."
pip install -r requirements.txt

# Set environment variables for local testing
export MicrosoftAppId=""
export MicrosoftAppPassword=""
export MicrosoftAppType="MultiTenant"

# Try to determine RAG backend URL
if [ -f "../.env" ]; then
    echo "📄 Loading environment from ../.env"
    source ../.env
    if [ -n "$AZURE_APP_SERVICE" ]; then
        export RAG_BACKEND_URL="https://$AZURE_APP_SERVICE.azurewebsites.net"
        echo "✅ Using backend URL: $RAG_BACKEND_URL"
    fi
fi

# Default to localhost if not set
if [ -z "$RAG_BACKEND_URL" ]; then
    export RAG_BACKEND_URL="http://localhost:50505"
    echo "⚠️  Using localhost backend: $RAG_BACKEND_URL"
    echo "   Make sure your backend is running locally on port 50505"
fi

echo "
🚀 Starting Teams bot locally...

Configuration:
- Bot endpoint: http://localhost:3978/api/messages
- RAG backend: $RAG_BACKEND_URL
- App ID: (empty for local testing)

📋 Testing options:
1. Bot Framework Emulator: Connect to http://localhost:3978/api/messages
2. ngrok tunnel: Run 'ngrok http 3978' in another terminal
3. Direct HTTP testing: Use curl or Postman

Press Ctrl+C to stop the bot
"

# Run the bot
python app.py
