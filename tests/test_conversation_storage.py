import asyncio
import os
from conversation_storage import ConversationStorage

async def test_conversation_storage():
    print("🧪 Testing Conversation Storage")
    print("=" * 50)
    
    # Test 1: Memory fallback (no connection string)
    print("\n1️⃣ Testing Memory Fallback Storage")
    memory_storage = ConversationStorage()
    
    test_conversation_id = "test-conversation-123"
    
    # Add some messages
    memory_storage.add_message(test_conversation_id, "user", "Hello, how are you?")
    memory_storage.add_message(test_conversation_id, "assistant", "I'm doing well, thank you!")
    memory_storage.add_message(test_conversation_id, "user", "What's the weather like?")
    memory_storage.add_message(test_conversation_id, "assistant", "I don't have access to current weather data.")
    
    # Get history
    history = memory_storage.get_conversation_history(test_conversation_id)
    print(f"✅ Memory storage: {len(history)} messages retrieved")
    for i, msg in enumerate(history):
        print(f"   {i+1}. {msg['role']}: {msg['content'][:50]}...")
    
    # Get stats
    stats = memory_storage.get_conversation_stats(test_conversation_id)
    print(f"✅ Stats: {stats}")
    
    # Clear conversation
    success = memory_storage.clear_conversation(test_conversation_id)
    print(f"✅ Clear conversation: {'Success' if success else 'Failed'}")
    
    # Test 2: Azure Table Storage (if connection string available)
    connection_string = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
    if connection_string:
        print("\n2️⃣ Testing Azure Table Storage")
        azure_storage = ConversationStorage(connection_string)
        
        test_conversation_id_2 = "test-azure-conversation-456"
        
        # Add messages
        azure_storage.add_message(test_conversation_id_2, "user", "Test Azure storage")
        azure_storage.add_message(test_conversation_id_2, "assistant", "Azure Table Storage is working!")
        
        # Get history
        azure_history = azure_storage.get_conversation_history(test_conversation_id_2)
        print(f"✅ Azure storage: {len(azure_history)} messages retrieved")
        
        # Get stats
        azure_stats = azure_storage.get_conversation_stats(test_conversation_id_2)
        print(f"✅ Azure stats: {azure_stats}")
        
        # Cleanup
        azure_storage.clear_conversation(test_conversation_id_2)
        print("✅ Azure conversation cleared")
    else:
        print("\n2️⃣ Skipping Azure Table Storage test (no connection string)")
        print("   Set AZURE_STORAGE_CONNECTION_STRING to test Azure integration")
    
    print("\n🎉 Conversation storage tests completed!")

if __name__ == "__main__":
    asyncio.run(test_conversation_storage())
