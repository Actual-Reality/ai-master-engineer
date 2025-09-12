import os
import json
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from azure.data.tables import TableServiceClient, TableEntity
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
import logging

logger = logging.getLogger(__name__)

class ConversationStorage:
    def __init__(self, connection_string: str = None, storage_account_name: str = None, table_name: str = "ConversationHistory"):
        """
        Initialize conversation storage with Azure Table Storage
        
        Args:
            connection_string: Azure Storage connection string (legacy)
            storage_account_name: Azure Storage account name for managed identity
            table_name: Name of the table to store conversations
        """
        self.table_name = table_name
        self.storage_account_name = storage_account_name or os.environ.get("AZURE_STORAGE_ACCOUNT_NAME")
        self.connection_string = connection_string or os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
        
        # Try managed identity first, then connection string, then fallback to memory
        if self.storage_account_name:
            try:
                # Use managed identity for authentication
                credential = DefaultAzureCredential()
                account_url = f"https://{self.storage_account_name}.table.core.windows.net"
                self.table_service_client = TableServiceClient(account_url=account_url, credential=credential)
                self.use_memory_fallback = False
                logger.info(f"Using managed identity authentication for storage account: {self.storage_account_name}")
                self._ensure_table_exists()
            except Exception as e:
                logger.error(f"Failed to initialize with managed identity: {str(e)}")
                self._fallback_to_memory()
        elif self.connection_string:
            try:
                # Use connection string authentication
                self.table_service_client = TableServiceClient.from_connection_string(self.connection_string)
                self.use_memory_fallback = False
                logger.info("Using connection string authentication for Azure Table Storage")
                self._ensure_table_exists()
            except Exception as e:
                logger.error(f"Failed to initialize with connection string: {str(e)}")
                self._fallback_to_memory()
        else:
            logger.warning("No Azure Storage configuration provided. Using in-memory storage.")
            self._fallback_to_memory()
    
    def _fallback_to_memory(self):
        """Initialize memory fallback storage"""
        self.use_memory_fallback = True
        self.memory_storage = {}
        logger.info("Initialized memory fallback storage")
    
    def _ensure_table_exists(self):
        """Ensure the conversation table exists"""
        try:
            self.table_service_client.create_table(self.table_name)
            logger.info(f"Created table: {self.table_name}")
        except ResourceExistsError:
            logger.debug(f"Table {self.table_name} already exists")
        except Exception as e:
            logger.error(f"Failed to create/access table {self.table_name}: {str(e)}")
            # Fall back to memory storage if table operations fail
            self.use_memory_fallback = True
            self.memory_storage = {}
    
    def get_conversation_history(self, conversation_id: str, max_messages: int = 20) -> List[Dict]:
        """
        Get conversation history for a given conversation ID
        
        Args:
            conversation_id: Unique identifier for the conversation
            max_messages: Maximum number of messages to return
            
        Returns:
            List of message dictionaries in chronological order
        """
        if self.use_memory_fallback:
            return self.memory_storage.get(conversation_id, [])[-max_messages:]
        
        try:
            table_client = self.table_service_client.get_table_client(self.table_name)
            
            # Query messages for this conversation, ordered by timestamp
            filter_query = f"PartitionKey eq '{conversation_id}'"
            entities = table_client.query_entities(
                query_filter=filter_query,
                select=["RowKey", "Role", "Content", "Timestamp"]
            )
            
            # Convert to list and sort by timestamp (RowKey contains timestamp)
            messages = []
            for entity in entities:
                messages.append({
                    "role": entity.get("Role"),
                    "content": entity.get("Content"),
                    "timestamp": entity.get("Timestamp")
                })
            
            # Sort by timestamp and return most recent messages
            messages.sort(key=lambda x: x.get("timestamp", ""))
            return messages[-max_messages:]
            
        except Exception as e:
            logger.error(f"Failed to get conversation history for {conversation_id}: {str(e)}")
            return []
    
    def add_message(self, conversation_id: str, role: str, content: str) -> bool:
        """
        Add a message to the conversation history
        
        Args:
            conversation_id: Unique identifier for the conversation
            role: Message role ('user' or 'assistant')
            content: Message content
            
        Returns:
            True if successful, False otherwise
        """
        if self.use_memory_fallback:
            if conversation_id not in self.memory_storage:
                self.memory_storage[conversation_id] = []
            
            self.memory_storage[conversation_id].append({
                "role": role,
                "content": content,
                "timestamp": datetime.utcnow().isoformat()
            })
            
            # Keep only last 20 messages in memory
            if len(self.memory_storage[conversation_id]) > 20:
                self.memory_storage[conversation_id] = self.memory_storage[conversation_id][-20:]
            
            return True
        
        try:
            table_client = self.table_service_client.get_table_client(self.table_name)
            
            # Create unique row key using timestamp
            timestamp = datetime.utcnow()
            row_key = timestamp.strftime("%Y%m%d%H%M%S%f")
            
            entity = TableEntity()
            entity["PartitionKey"] = conversation_id
            entity["RowKey"] = row_key
            entity["Role"] = role
            entity["Content"] = content
            entity["Timestamp"] = timestamp.isoformat()
            entity["CreatedAt"] = timestamp
            
            table_client.create_entity(entity)
            logger.debug(f"Added message to conversation {conversation_id}")
            
            # Clean up old messages to prevent unlimited growth
            self._cleanup_old_messages(conversation_id)
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to add message to conversation {conversation_id}: {str(e)}")
            return False
    
    def clear_conversation(self, conversation_id: str) -> bool:
        """
        Clear all messages for a conversation
        
        Args:
            conversation_id: Unique identifier for the conversation
            
        Returns:
            True if successful, False otherwise
        """
        if self.use_memory_fallback:
            self.memory_storage[conversation_id] = []
            return True
        
        try:
            table_client = self.table_service_client.get_table_client(self.table_name)
            
            # Query all entities for this conversation
            filter_query = f"PartitionKey eq '{conversation_id}'"
            entities = table_client.query_entities(query_filter=filter_query)
            
            # Delete all entities
            for entity in entities:
                table_client.delete_entity(
                    partition_key=entity["PartitionKey"],
                    row_key=entity["RowKey"]
                )
            
            logger.info(f"Cleared conversation history for {conversation_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to clear conversation {conversation_id}: {str(e)}")
            return False
    
    def _cleanup_old_messages(self, conversation_id: str, keep_count: int = 50):
        """
        Clean up old messages to prevent unlimited storage growth
        
        Args:
            conversation_id: Conversation to clean up
            keep_count: Number of recent messages to keep
        """
        try:
            table_client = self.table_service_client.get_table_client(self.table_name)
            
            # Get all messages for this conversation
            filter_query = f"PartitionKey eq '{conversation_id}'"
            entities = list(table_client.query_entities(
                query_filter=filter_query,
                select=["RowKey", "Timestamp"]
            ))
            
            # If we have more than keep_count messages, delete the oldest ones
            if len(entities) > keep_count:
                # Sort by timestamp (RowKey) and get oldest messages to delete
                entities.sort(key=lambda x: x["RowKey"])
                messages_to_delete = entities[:-keep_count]
                
                for entity in messages_to_delete:
                    table_client.delete_entity(
                        partition_key=conversation_id,
                        row_key=entity["RowKey"]
                    )
                
                logger.info(f"Cleaned up {len(messages_to_delete)} old messages for conversation {conversation_id}")
                
        except Exception as e:
            logger.error(f"Failed to cleanup old messages for {conversation_id}: {str(e)}")
    
    def get_conversation_stats(self, conversation_id: str) -> Dict:
        """
        Get statistics about a conversation
        
        Args:
            conversation_id: Conversation to analyze
            
        Returns:
            Dictionary with conversation statistics
        """
        if self.use_memory_fallback:
            messages = self.memory_storage.get(conversation_id, [])
            return {
                "message_count": len(messages),
                "user_messages": len([m for m in messages if m.get("role") == "user"]),
                "assistant_messages": len([m for m in messages if m.get("role") == "assistant"]),
                "storage_type": "memory"
            }
        
        try:
            table_client = self.table_service_client.get_table_client(self.table_name)
            
            filter_query = f"PartitionKey eq '{conversation_id}'"
            entities = list(table_client.query_entities(
                query_filter=filter_query,
                select=["Role"]
            ))
            
            user_count = len([e for e in entities if e.get("Role") == "user"])
            assistant_count = len([e for e in entities if e.get("Role") == "assistant"])
            
            return {
                "message_count": len(entities),
                "user_messages": user_count,
                "assistant_messages": assistant_count,
                "storage_type": "azure_table"
            }
            
        except Exception as e:
            logger.error(f"Failed to get conversation stats for {conversation_id}: {str(e)}")
            return {
                "message_count": 0,
                "user_messages": 0,
                "assistant_messages": 0,
                "storage_type": "error"
            }
