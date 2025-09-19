"""
Health check endpoints for the Microsoft 365 RAG Agent.
Provides health and readiness checks for container orchestration.
"""

import asyncio
import logging
from datetime import datetime
from typing import Dict, Any

from quart import Quart, jsonify, request
from services.auth_service import AuthService
from services.rag_service import RAGService
from config.agent_config import AgentConfig

logger = logging.getLogger(__name__)


class HealthChecker:
    """Health checker for the Microsoft 365 RAG Agent."""
    
    def __init__(self, config: AgentConfig, auth_service: AuthService, rag_service: RAGService):
        self.config = config
        self.auth_service = auth_service
        self.rag_service = rag_service
        self.start_time = datetime.now()
        self.health_status = "healthy"
        self.last_check = None
    
    async def check_auth_service(self) -> Dict[str, Any]:
        """Check authentication service health."""
        try:
            # Test if auth service can get access token
            token = await self.auth_service.get_access_token()
            return {
                "status": "healthy",
                "message": "Auth service is responding",
                "has_token": token is not None
            }
        except Exception as e:
            logger.error(f"Auth service health check failed: {e}")
            return {
                "status": "unhealthy",
                "message": f"Auth service error: {str(e)}",
                "has_token": False
            }
    
    async def check_rag_service(self) -> Dict[str, Any]:
        """Check RAG service health."""
        try:
            # Test if RAG service can connect to backend
            test_response = await self.rag_service.health_check()
            return {
                "status": "healthy",
                "message": "RAG service is responding",
                "backend_connected": test_response.get("status") == "healthy"
            }
        except Exception as e:
            logger.error(f"RAG service health check failed: {e}")
            return {
                "status": "unhealthy",
                "message": f"RAG service error: {str(e)}",
                "backend_connected": False
            }
    
    async def check_dependencies(self) -> Dict[str, Any]:
        """Check external dependencies."""
        dependencies = {
            "microsoft_graph": await self.check_auth_service(),
            "rag_backend": await self.check_rag_service()
        }
        
        overall_status = "healthy"
        for dep_name, dep_status in dependencies.items():
            if dep_status["status"] != "healthy":
                overall_status = "unhealthy"
                break
        
        return {
            "status": overall_status,
            "dependencies": dependencies
        }
    
    async def get_health_status(self) -> Dict[str, Any]:
        """Get overall health status."""
        try:
            dependencies = await self.check_dependencies()
            
            uptime = (datetime.now() - self.start_time).total_seconds()
            
            health_data = {
                "status": dependencies["status"],
                "timestamp": datetime.now().isoformat(),
                "uptime_seconds": uptime,
                "version": "1.0.0",
                "service": "m365-rag-agent",
                "dependencies": dependencies["dependencies"]
            }
            
            # Update health status
            self.health_status = dependencies["status"]
            self.last_check = datetime.now()
            
            return health_data
            
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return {
                "status": "unhealthy",
                "timestamp": datetime.now().isoformat(),
                "error": str(e),
                "service": "m365-rag-agent"
            }
    
    async def get_readiness_status(self) -> Dict[str, Any]:
        """Get readiness status for Kubernetes."""
        try:
            dependencies = await self.check_dependencies()
            
            # Service is ready if all critical dependencies are healthy
            is_ready = dependencies["status"] == "healthy"
            
            return {
                "ready": is_ready,
                "timestamp": datetime.now().isoformat(),
                "dependencies": dependencies["dependencies"]
            }
            
        except Exception as e:
            logger.error(f"Readiness check failed: {e}")
            return {
                "ready": False,
                "timestamp": datetime.now().isoformat(),
                "error": str(e)
            }


def setup_health_routes(app: Quart, health_checker: HealthChecker):
    """Set up health check routes for the Quart application."""
    
    @app.route('/health', methods=['GET'])
    async def health():
        """Health check endpoint."""
        try:
            health_data = await health_checker.get_health_status()
            status_code = 200 if health_data["status"] == "healthy" else 503
            return jsonify(health_data), status_code
        except Exception as e:
            logger.error(f"Health endpoint error: {e}")
            return jsonify({
                "status": "unhealthy",
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }), 503
    
    @app.route('/ready', methods=['GET'])
    async def ready():
        """Readiness check endpoint for Kubernetes."""
        try:
            readiness_data = await health_checker.get_readiness_status()
            status_code = 200 if readiness_data["ready"] else 503
            return jsonify(readiness_data), status_code
        except Exception as e:
            logger.error(f"Readiness endpoint error: {e}")
            return jsonify({
                "ready": False,
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }), 503
    
    @app.route('/live', methods=['GET'])
    async def live():
        """Liveness check endpoint for Kubernetes."""
        return jsonify({
            "alive": True,
            "timestamp": datetime.now().isoformat(),
            "service": "m365-rag-agent"
        }), 200
    
    @app.route('/metrics', methods=['GET'])
    async def metrics():
        """Basic metrics endpoint."""
        try:
            health_data = await health_checker.get_health_status()
            
            metrics = {
                "uptime_seconds": health_data.get("uptime_seconds", 0),
                "status": health_data.get("status", "unknown"),
                "last_check": health_checker.last_check.isoformat() if health_checker.last_check else None,
                "dependencies": {
                    dep_name: dep_data.get("status", "unknown")
                    for dep_name, dep_data in health_data.get("dependencies", {}).items()
                }
            }
            
            return jsonify(metrics), 200
            
        except Exception as e:
            logger.error(f"Metrics endpoint error: {e}")
            return jsonify({
                "error": str(e),
                "timestamp": datetime.now().isoformat()
            }), 500