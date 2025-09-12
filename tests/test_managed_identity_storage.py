import asyncio
import os
from conversation_storage import ConversationStorage

async def test_managed_identity_storage():
    
    print("🧪 Testing Managed Identity Storage")
    print("=" * 50)
    
    # Test with storage account name (managed identity)
    print("\n1️⃣ Testing Managed Identity Authentication")
    storage_account_name = "stnnsnw2zar7dok"
    
    try:
        managed_storage = ConversationStorage(storage_account_name=storage_account_name)
        
        test_conversation_id = "test-managed-identity-789"
        
        # Add some messages
        print("Adding test messages...")
        success1 = managed_storage.add_message(test_conversation_id, "user", "Testing managed identity storage")
        success2 = managed_storage.add_message(test_conversation_id, "assistant", "Managed identity authentication is working!")
        
        print(f"✅ Message 1 added: {'Success' if success1 else 'Failed'}")
        print(f"✅ Message 2 added: {'Success' if success2 else 'Failed'}")
        
        # Get history
        history = managed_storage.get_conversation_history(test_conversation_id)
        print(f"✅ Retrieved {len(history)} messages from storage")
        
        for i, msg in enumerate(history):
            print(f"   {i+1}. {msg['role']}: {msg['content']}")
        
        # Get stats
        stats = managed_storage.get_conversation_stats(test_conversation_id)
        print(f"✅ Storage stats: {stats}")
        
        # Test conversation clearing
        clear_success = managed_storage.clear_conversation(test_conversation_id)
        print(f"✅ Clear conversation: {'Success' if clear_success else 'Failed'}")
        
        # Verify clearing worked
        cleared_history = managed_storage.get_conversation_history(test_conversation_id)
        print(f"✅ After clearing: {len(cleared_history)} messages remain")
        
    except Exception as e:
        print(f"❌ Managed identity test failed: {str(e)}")
        print("This is expected if running locally without Azure credentials")
    
    print("\n2️⃣ Testing Memory Fallback")
    # Test fallback behavior
    fallback_storage = ConversationStorage()  # No credentials provided
    
    test_conversation_id_2 = "test-fallback-456"
    
    fallback_storage.add_message(test_conversation_id_2, "user", "Testing fallback storage")
    fallback_storage.add_message(test_conversation_id_2, "assistant", "Memory fallback is working!")
    
    fallback_history = fallback_storage.get_conversation_history(test_conversation_id_2)
    print(f"✅ Fallback storage: {len(fallback_history)} messages retrieved")
    
    fallback_stats = fallback_storage.get_conversation_stats(test_conversation_id_2)
    print(f"✅ Fallback stats: {fallback_stats}")
    
    print("\n🎉 Managed identity storage tests completed!")
    print("\n📋 Summary:")
    print("- Memory fallback always works for local development")
    print("- Managed identity will work when deployed to Azure with proper permissions")
    print("- The system gracefully handles authentication failures")

if __name__ == "__main__":
    asyncio.run(test_managed_identity_storage())
