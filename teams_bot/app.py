import os
import sys
from aiohttp import web
from botbuilder.core import BotFrameworkAdapter, BotFrameworkAdapterSettings
from botbuilder.integration.aiohttp import BotFrameworkHttpAdapter
from teams_bot import TeamsRAGBot
from rag_bridge import RAGBridge

# Get port from environment variable, default to 8000 for container apps
PORT = int(os.environ.get("PORT", 8000))

# Bot Framework configuration with better error handling and single-tenant support
MICROSOFT_APP_ID = os.environ.get("MicrosoftAppId", "")
MICROSOFT_APP_PASSWORD = os.environ.get("MicrosoftAppPassword", "")
MICROSOFT_APP_TYPE = os.environ.get("MicrosoftAppType", "SingleTenant")  # Default to SingleTenant
MICROSOFT_APP_TENANT_ID = os.environ.get("MicrosoftAppTenantId", "")

# Log configuration for debugging
print(f"Starting Teams Bot on port {PORT}")
print(f"MicrosoftAppId configured: {'Yes' if MICROSOFT_APP_ID else 'No'}")
print(f"MicrosoftAppPassword configured: {'Yes' if MICROSOFT_APP_PASSWORD else 'No'}")
print(f"MicrosoftAppType: {MICROSOFT_APP_TYPE}")
print(f"MicrosoftAppTenantId configured: {'Yes' if MICROSOFT_APP_TENANT_ID else 'No'}")

# Validate single-tenant configuration
if MICROSOFT_APP_TYPE == "SingleTenant" and not MICROSOFT_APP_TENANT_ID:
    print("ERROR: SingleTenant app type requires MicrosoftAppTenantId to be set")
    sys.exit(1)

# Bot Framework configuration - CORRECTED for SDK compatibility
SETTINGS = BotFrameworkAdapterSettings(
    app_id=MICROSOFT_APP_ID,
    app_password=MICROSOFT_APP_PASSWORD
)

# Create adapter and bot
ADAPTER = BotFrameworkHttpAdapter(SETTINGS)

# RAG Bridge configuration
RAG_BACKEND_URL = os.environ.get("RAG_BACKEND_URL", "https://capps-backend-nnsnw2zar7dok.salmoncliff-681251ec.eastus.azurecontainerapps.io")
RAG_BRIDGE = RAGBridge(backend_url=RAG_BACKEND_URL)

# Storage configuration
STORAGE_ACCOUNT_NAME = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME", "stnnsnw2zar7dok")
BOT = TeamsRAGBot(RAG_BRIDGE, storage_account_name=STORAGE_ACCOUNT_NAME)

# Error handler
async def on_error(context, error):
    print(f"\n [on_turn_error] unhandled error: {error}", file=sys.stderr)
    # Send a message to the user
    await context.send_activity("The bot encountered an error or bug.")

ADAPTER.on_turn_error = on_error

async def messages(req: web.Request) -> web.Response:
    """Handle bot messages - FINAL CORRECTED VERSION"""
    print("Received POST request to /api/messages")
    
    try:
        # Validate content type
        content_type = req.headers.get("Content-Type", "")
        if "application/json" not in content_type:
            print(f"Invalid content type: {content_type}")
            return web.Response(status=415, text="Unsupported Media Type")

        # Get request body as text first
        body = await req.text()
        print(f"Raw request body length: {len(body)}")
        
        # Parse JSON for logging
        import json
        try:
            json_body = json.loads(body) if body else {}
            print(f"Processing message of type: {json_body.get('type', 'unknown')}")
            
            # Log some details for debugging
            if 'from' in json_body:
                print(f"Message from: {json_body['from'].get('name', 'unknown')}")
            if 'text' in json_body:
                preview = json_body['text'][:50] + "..." if len(json_body['text']) > 50 else json_body['text']
                print(f"Message text preview: {preview}")
                
        except json.JSONDecodeError as e:
            print(f"JSON decode error: {e}")
            return web.Response(status=400, text="Invalid JSON")

    except Exception as e:
        print(f"Error parsing request: {e}")
        return web.Response(status=400, text="Bad Request")

    # Get authorization header
    authorization = req.headers.get("Authorization", "")
    print(f"Authorization header present: {'Yes' if authorization else 'No'}")
    
    async def bot_message_handler(turn_context):
        try:
            await BOT.on_message_activity(turn_context)
        except Exception as e:
            print(f"Error in bot message handler: {e}")
            raise

    try:
        # Use the HTTP adapter's process method - THE CORRECT FIX
        response = await ADAPTER.process(req, bot_message_handler)
        print("Message processed successfully")
        return response if response else web.Response(status=200)
        
    except Exception as e:
        print(f"Error processing activity: {e}")
        import traceback
        traceback.print_exc()
        return web.Response(status=500, text="Internal Server Error")

# Health check endpoint
async def health(req: web.Request) -> web.Response:
    """Health check endpoint"""
    health_status = {
        "status": "healthy",
        "app_id_configured": bool(MICROSOFT_APP_ID),
        "app_password_configured": bool(MICROSOFT_APP_PASSWORD),
        "app_type": MICROSOFT_APP_TYPE,
        "tenant_id_configured": bool(MICROSOFT_APP_TENANT_ID),
        "rag_backend_url": RAG_BACKEND_URL,
        "storage_account": STORAGE_ACCOUNT_NAME,
        "port": PORT
    }
    return web.json_response(health_status)

# Root endpoint
async def root(req: web.Request) -> web.Response:
    """Root endpoint"""
    return web.Response(
        text=f"Teams Bot is running! (Type: {MICROSOFT_APP_TYPE})", 
        content_type="text/plain"
    )

# Create web application
APP = web.Application()

# Add routes
APP.router.add_post("/api/messages", messages)
APP.router.add_get("/health", health)
APP.router.add_get("/", root)

# Add CORS headers for development
async def add_cors_headers(request, handler):
    response = await handler(request)
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    return response

APP.middlewares.append(add_cors_headers)

if __name__ == "__main__":
    try:
        print(f"Starting Teams Bot server on 0.0.0.0:{PORT}")
        print(f"Bot Type: {MICROSOFT_APP_TYPE}")
        print(f"Health check available at: http://localhost:{PORT}/health")
        print(f"Bot endpoint available at: http://localhost:{PORT}/api/messages")
        
        if MICROSOFT_APP_TYPE == "SingleTenant":
            print(f"Single-tenant configuration - Tenant ID: {MICROSOFT_APP_TENANT_ID[:8] if MICROSOFT_APP_TENANT_ID else 'NOT SET'}...")
        
        # Run the app on all interfaces for container apps
        web.run_app(APP, host="0.0.0.0", port=PORT)
    except Exception as error:
        print(f"Failed to start server: {error}")
        sys.exit(1)