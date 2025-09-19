"""
Main entry point for the Microsoft 365 Agent.
This module starts the agent application and handles incoming requests.
"""

import asyncio
import logging
import os
from typing import Optional

from botbuilder.core import BotFrameworkAdapter, BotFrameworkAdapterSettings
from botbuilder.schema import Activity, ActivityTypes
from quart import Quart, request, jsonify

from config.agent_config import AgentConfig
from agent_app import AgentApplication
from health import HealthChecker, setup_health_routes


# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class AgentServer:
    """
    Server that hosts the Microsoft 365 Agent.
    This server handles incoming requests and routes them to the agent.
    """
    
    def __init__(self):
        self.app = Quart(__name__)
        self.agent_app: Optional[AgentApplication] = None
        self.adapter: Optional[BotFrameworkAdapter] = None
        self.health_checker: Optional[HealthChecker] = None
        
        # Configure routes
        self._setup_routes()
    
    def _setup_routes(self):
        """Set up the Quart routes."""
        
        @self.app.route("/", methods=["GET"])
        async def health_check():
            """Health check endpoint."""
            return jsonify({
                "status": "healthy",
                "service": "Microsoft 365 RAG Agent",
                "version": "1.0.0"
            })
        
        @self.app.route("/api/messages", methods=["POST"])
        async def messages():
            """Main endpoint for Bot Framework messages."""
            try:
                if not self.agent_app:
                    return jsonify({"error": "Agent not initialized"}), 500
                
                # Get the request body
                body = await request.get_json()
                
                # Create activity from request
                activity = Activity().deserialize(body)
                
                # Process the activity
                response = await self.agent_app.process_activity(activity)
                
                return jsonify(response.serialize())
                
            except Exception as e:
                logger.error(f"Error processing message: {e}")
                return jsonify({"error": "Internal server error"}), 500
        
        @self.app.route("/api/health", methods=["GET"])
        async def health():
            """Detailed health check."""
            try:
                if not self.health_checker:
                    return jsonify({
                        "status": "unhealthy",
                        "error": "Health checker not initialized"
                    }), 500
                
                health_data = await self.health_checker.get_health_status()
                status_code = 200 if health_data["status"] == "healthy" else 503
                return jsonify(health_data), status_code
                
            except Exception as e:
                logger.error(f"Error in health check: {e}")
                return jsonify({
                    "status": "unhealthy",
                    "error": str(e)
                }), 500
        
        @self.app.route("/api/config", methods=["GET"])
        async def config():
            """Get agent configuration (non-sensitive parts)."""
            try:
                if not self.agent_app:
                    return jsonify({"error": "Agent not initialized"}), 500
                
                config_info = {
                    "agent_name": self.agent_app.config.agent_name,
                    "agent_description": self.agent_app.config.agent_description,
                    "max_conversation_turns": self.agent_app.config.max_conversation_turns,
                    "channels": {
                        "teams": self.agent_app.config.enable_teams,
                        "copilot": self.agent_app.config.enable_copilot,
                        "web_chat": self.agent_app.config.enable_web_chat
                    }
                }
                
                return jsonify(config_info)
                
            except Exception as e:
                logger.error(f"Error getting config: {e}")
                return jsonify({"error": "Internal server error"}), 500
    
    async def initialize(self):
        """Initialize the agent application."""
        try:
            # Load configuration
            config = AgentConfig.from_environment()
            config.validate()
            
            # Initialize the agent application
            self.agent_app = AgentApplication(config)
            
            # Get the adapter
            self.adapter = self.agent_app.get_adapter()
            
            # Initialize health checker
            self.health_checker = HealthChecker(
                config=config,
                auth_service=self.agent_app.auth_service,
                rag_service=self.agent_app.rag_service
            )
            
            # Set up health check routes
            setup_health_routes(self.app, self.health_checker)
            
            logger.info("Agent application initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize agent application: {e}")
            raise
    
    async def run(self, host: str = "0.0.0.0", port: int = 8000):
        """Run the agent server."""
        try:
            # Initialize the agent
            await self.initialize()
            
            # Start the server
            logger.info(f"Starting agent server on {host}:{port}")
            await self.app.run_task(host=host, port=port)
            
        except Exception as e:
            logger.error(f"Failed to run agent server: {e}")
            raise


async def main():
    """Main function to start the agent server."""
    try:
        # Create and run the server
        server = AgentServer()
        await server.run()
        
    except KeyboardInterrupt:
        logger.info("Agent server stopped by user")
    except Exception as e:
        logger.error(f"Agent server failed: {e}")
        raise


if __name__ == "__main__":
    # Run the agent server
    asyncio.run(main())