import os
import sys
from aiohttp import web
from botbuilder.core import BotFrameworkAdapter, BotFrameworkAdapterSettings
from botbuilder.integration.aiohttp import BotFrameworkHttpAdapter
from teams_bot import TeamsRAGBot
from rag_bridge import RAGBridge

# Get port from environment variable, default to 8000 for container apps
PORT = int(os.environ.get("PORT", 8000))

# Bot Framework configuration
MICROSOFT_APP_ID = os.environ.get("MicrosoftAppId", "")
MICROSOFT_APP_PASSWORD = os.environ.get("MicrosoftAppPassword", "")
MICROSOFT_APP_TYPE = os.environ.get("MicrosoftAppType", "SingleTenant")
MICROSOFT_APP_TENANT_ID = os.environ.get("MicrosoftAppTenantId", "")

# Log configuration for debugging
print(f"Starting Teams Bot on port {PORT}")
print(f"MicrosoftAppId configured: {'Yes' if MICROSOFT_APP_ID else 'No'}")
print(f"MicrosoftAppPassword configured: {'Yes' if MICROSOFT_APP_PASSWORD else 'No'}")
print(f"MicrosoftAppType: {MICROSOFT_APP_TYPE}")
print(f"MicrosoftAppTenantId configured: {'Yes' if MICROSOFT_APP_TENANT_ID else 'No'}")

# Bot Framework configuration
SETTINGS = BotFrameworkAdapterSettings(
    app_id=MICROSOFT_APP_ID,
    app_password=MICROSOFT_APP_PASSWORD
)

# Create adapter and bot
ADAPTER = BotFrameworkHttpAdapter(SETTINGS)

# RAG Bridge configuration
RAG_BACKEND_URL = os.environ.get("RAG_BACKEND_URL", "https://capps-backend-nnsnw2zar7dok.salmoncliff-681251ec.eastus.azurecontainerapps.io")
RAG_BRIDGE = RAGBridge(backend_url=RAG_BACKEND_URL)

# Create bot without storage for now to avoid initialization issues
BOT = TeamsRAGBot(RAG_BRIDGE)

# Error handler
async def on_error(context, error):
    print(f"\n [on_turn_error] unhandled error: {error}", file=sys.stderr)
    await context.send_activity("The bot encountered an error or bug.")

ADAPTER.on_turn_error = on_error

async def messages(req: web.Request) -> web.Response:
    """Handle bot messages"""
    print("Received POST request to /api/messages")
    
    try:
        # The BotFrameworkHttpAdapter.process() method expects:
        # - request: aiohttp Request object
        # - ws_response: None (for regular HTTP, not WebSocket)
        # - bot: Bot instance
        
        # Use the aiohttp-specific adapter process method
        response = await ADAPTER.process(req, None, BOT)
        
        # If response is None, return 200 OK
        if response is None:
            return web.Response(status=200)
        else:
            return response
        
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

if __name__ == "__main__":
    try:
        print(f"Starting Teams Bot server on 0.0.0.0:{PORT}")
        print(f"Bot Type: {MICROSOFT_APP_TYPE}")
        print(f"Health check available at: http://localhost:{PORT}/health")
        print(f"Bot endpoint available at: http://localhost:{PORT}/api/messages")
        
        if MICROSOFT_APP_TYPE == "SingleTenant":
            print(f"Single-tenant configuration - Tenant ID: {MICROSOFT_APP_TENANT_ID[:8] if MICROSOFT_APP_TENANT_ID else 'NOT SET'}...")
        
        web.run_app(APP, host="0.0.0.0", port=PORT)
    except Exception as error:
        print(f"Failed to start server: {error}")
        sys.exit(1)