import sys
import os
from pathlib import Path
import asyncio
import aiohttp

# Add your existing backend to path
backend_path = Path(__file__).parent.parent / "app" / "backend"
sys.path.append(str(backend_path))

class RAGBridge:
    def __init__(self, backend_url: str = None):
        self.backend_url = backend_url or "https://capps-backend-nnsnw2zar7dok.salmoncliff-681251ec.eastus.azurecontainerapps.io"
        
    async def process_query(self, query: str, history: list = None, user_context: dict = None) -> dict:
        """Process query through existing RAG pipeline"""
        
        # Prepare request payload matching your existing API
        messages = (history or []) + [{"role": "user", "content": query}]
        
        payload = {
            "messages": messages,
            "context": {
                "overrides": {
                    "top": 3,
                    "temperature": 0.3,
                    "minimum_search_score": 0.0,
                    "minimum_reranker_score": 0.0
                }
            }
        }
        
        try:
            # Call your existing /chat endpoint
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30)) as session:
                async with session.post(
                    f"{self.backend_url}/chat",
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    if response.status == 200:
                        result = await response.json()
                        return self.format_response(result)
                    elif response.status == 401:
                        return {
                            "answer": "Authentication error with the search service. Please contact your administrator.",
                            "citations": []
                        }
                    elif response.status >= 500:
                        return {
                            "answer": "The search service is temporarily unavailable. Please try again in a few minutes.",
                            "citations": []
                        }
                    else:
                        error_text = await response.text()
                        print(f"RAG Bridge HTTP error {response.status}: {error_text}")
                        return {
                            "answer": "I couldn't process your request right now. Please try again later.",
                            "citations": []
                        }
        except asyncio.TimeoutError:
            print("RAG Bridge timeout error")
            return {
                "answer": "The search is taking too long. Please try a simpler question or try again later.",
                "citations": []
            }
        except Exception as e:
            print(f"RAG Bridge error: {str(e)}")
            return {
                "answer": "I'm having trouble connecting to the search service. Please try again.",
                "citations": []
            }
    
    def format_response(self, rag_response: dict) -> dict:
        """Format response from your RAG pipeline for Teams display"""
        
        # Handle different response formats from the backend
        if isinstance(rag_response, dict):
            # Check for message content (new format)
            if "message" in rag_response and "content" in rag_response["message"]:
                answer = rag_response["message"]["content"]
            # Check for direct answer field (old format)
            elif "answer" in rag_response:
                answer = rag_response["answer"]
            else:
                answer = "No answer found"
            
            citations = []
            
            # Parse citations from context (new format)
            if "context" in rag_response:
                context = rag_response["context"]
                if "data_points" in context:
                    for data_point in context["data_points"]:
                        if isinstance(data_point, dict):
                            citations.append({
                                "title": data_point.get("sourcefile", data_point.get("title", "Document")),
                                "content": data_point.get("content", ""),
                                "url": data_point.get("sourcepage", ""),
                                "filepath": data_point.get("sourcefile", "")
                            })
            
            # Fallback to direct citations field (old format)
            elif "citations" in rag_response:
                for citation in rag_response["citations"]:
                    citations.append({
                        "title": citation.get("title", "Document"),
                        "content": citation.get("content", ""),
                        "url": citation.get("url", ""),
                        "filepath": citation.get("filepath", "")
                    })
            
            return {
                "answer": answer,
                "citations": citations
            }
        else:
            return {
                "answer": "Unexpected response format from search service",
                "citations": []
            }
