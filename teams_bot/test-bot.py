import asyncio
import json
from rag_bridge import RAGBridge

async def test_rag_bridge():
    print("🧪 Testing RAG Bridge...")
    
    # Initialize RAG bridge with localhost (adjust URL as needed)
    rag_bridge = RAGBridge("http://localhost:50505")
    
    # Test queries
    test_queries = [
        "What is this system about?",
        "How does the search functionality work?",
        "Tell me about the architecture"
    ]
    
    for query in test_queries:
        print(f"\n📝 Testing query: '{query}'")
        try:
            response = await rag_bridge.process_query(
                query=query,
                history=[],
                user_context={"user_id": "test_user", "user_name": "Test User"}
            )
            
            print(f"✅ Response received:")
            print(f"   Answer: {response.get('answer', 'No answer')[:100]}...")
            print(f"   Citations: {len(response.get('citations', []))} found")
            
        except Exception as e:
            print(f"❌ Error: {str(e)}")
    
    print("\n🎉 RAG Bridge testing completed!")

def test_adaptive_card_format():
    print("\n🎨 Testing Adaptive Card formatting...")
    
    # Mock response data
    mock_response = {
        "answer": "This is a test answer from the AI system. It provides information about the query with relevant context and details.",
        "citations": [
            {
                "title": "Test Document 1",
                "content": "This is the content from the first test document that supports the answer.",
                "url": "https://example.com/doc1",
                "filepath": "/docs/test1.pdf"
            },
            {
                "title": "Test Document 2", 
                "content": "Additional supporting content from a second document with more details about the topic.",
                "url": "https://example.com/doc2",
                "filepath": "/docs/test2.pdf"
            }
        ]
    }
    
    # Import and test the bot's card formatting
    from teams_bot import TeamsRAGBot
    from rag_bridge import RAGBridge
    
    bot = TeamsRAGBot(RAGBridge())
    card = bot.format_response_card(mock_response)
    
    print("✅ Adaptive Card generated successfully!")
    print(f"   Card type: {card.content_type}")
    print(f"   Card content keys: {list(card.content.keys())}")
    print(f"   Body elements: {len(card.content.get('body', []))}")
    
    # Pretty print the card JSON for inspection
    print("\n📋 Card JSON structure:")
    print(json.dumps(card.content, indent=2)[:500] + "...")

async def main():
    print("🚀 Starting Teams Bot Tests\n")
    
    # Test 1: RAG Bridge
    await test_rag_bridge()
    
    # Test 2: Adaptive Card formatting
    test_adaptive_card_format()
    
    print("\n✅ All tests completed!")
    print("\n📋 Next steps:")
    print("1. Run './test-local.sh' to start the bot locally")
    print("2. Test with Bot Framework Emulator")
    print("3. Deploy to Azure with './deploy-teams-bot.sh'")

if __name__ == "__main__":
    asyncio.run(main())
