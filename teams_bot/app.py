import os
from aiohttp import web
from botbuilder.core import BotFrameworkAdapter, BotFrameworkAdapterSettings
from botbuilder.integration.aiohttp import BotFrameworkHttpAdapter
from teams_bot import TeamsRAGBot
from rag_bridge import RAGBridge

# Bot Framework configuration
SETTINGS = BotFrameworkAdapterSettings(
    app_id=os.environ.get("MicrosoftAppId", ""),
    app_password=os.environ.get("MicrosoftAppPassword", ""),
    app_type=os.environ.get("MicrosoftAppType", "MultiTenant"),
    app_tenant_id=os.environ.get("MicrosoftAppTenantId", "")
)

# Create adapter and bot
ADAPTER = BotFrameworkHttpAdapter(SETTINGS)
RAG_BRIDGE = RAGBridge(backend_url=os.environ.get("RAG_BACKEND_URL", "https://capps-backend-nnsnw2zar7dok.salmoncliff-681251ec.eastus.azurecontainerapps.io"))
BOT = TeamsRAGBot(RAG_BRIDGE, storage_account_name=os.environ.get("AZURE_STORAGE_ACCOUNT_NAME", "stnnsnw2zar7dok"))

async def messages(req: web.Request) -> web.Response:
    """Handle bot messages"""
    if "application/json" in req.headers["Content-Type"]:
        body = await req.json()
    else:
        return web.Response(status=415)

    async def bot_message_handler(turn_context):
        await BOT.on_message_activity(turn_context)

    await ADAPTER.process_activity(body, req.headers.get("Authorization", ""), bot_message_handler)
    return web.Response(status=200)

# Create web application
APP = web.Application()
APP.router.add_post("/api/messages", messages)

if __name__ == "__main__":
    try:
        port = int(os.environ.get("PORT", 8000))
        web.run_app(APP, host="0.0.0.0", port=port)
    except Exception as error:
        raise error
