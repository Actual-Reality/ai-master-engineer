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
        self.backend_url = backend_url or "http://localhost:50505"  # Your deployed backend URL
        
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
            async with aiohttp.ClientSession() as session:
                async with session.post(
                    f"{self.backend_url}/chat",
                    json=payload,
                    headers={"Content-Type": "application/json"}
                ) as response:
                    if response.status == 200:
                        result = await response.json()
                        return self.format_response(result)
                    else:
                        return {
                            "answer": "I couldn't process your request right now. Please try again later.",
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
        
        # Extract answer and citations from your existing format
        answer = rag_response.get("answer", "No answer found")
        citations = []
        
        # Parse citations from your existing format
        if "citations" in rag_response:
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
