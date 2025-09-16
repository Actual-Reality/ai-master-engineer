from botbuilder.core import ActivityHandler, MessageFactory, TurnContext
from botbuilder.core.teams import TeamsActivityHandler
from botbuilder.schema import Attachment, ChannelAccount
import re
import json
import logging

logger = logging.getLogger(__name__)

class TeamsRAGBot(TeamsActivityHandler):
    def __init__(self, rag_bridge):
        self.rag_bridge = rag_bridge
        # Simple in-memory storage for conversation context
        self.conversation_state = {}

    async def on_message_activity(self, turn_context: TurnContext):
        """Handle incoming messages"""
        try:
            # Handle special commands first
            if await self.handle_commands(turn_context):
                return

            # Clean and process user message
            user_query = self.clean_teams_message(turn_context)
            if not user_query:
                await turn_context.send_activity(
                    MessageFactory.text("Please ask me a question about your documents!")
                )
                return

            # Process user query (typing indicator removed to avoid errors)
            
            # Get conversation context
            conversation_id = turn_context.activity.conversation.id
            history = self.get_conversation_history(conversation_id)

            # Process through RAG pipeline
            response = await self.rag_bridge.process_query(
                query=user_query,
                history=history,
                user_context=await self.get_user_context(turn_context)
            )

            # Update conversation history
            self.update_conversation_history(conversation_id, user_query, response)

            # Format and send response
            response_card = self.format_response_card(response)
            await turn_context.send_activity(MessageFactory.attachment(response_card))

        except Exception as e:
            logger.error(f"Error in on_message_activity: {str(e)}", exc_info=True)
            error_message = "I'm having trouble processing your request. Please try again."
            try:
                await turn_context.send_activity(MessageFactory.text(error_message))
            except Exception as send_error:
                logger.error(f"Could not send error message: {send_error}")

    async def on_members_added_activity(self, members_added: list[ChannelAccount], turn_context: TurnContext):
        """Welcome message when bot is added"""
        for member in members_added:
            if member.id != turn_context.activity.recipient.id:
                welcome_card = self.create_welcome_card()
                await turn_context.send_activity(MessageFactory.attachment(welcome_card))

    def clean_teams_message(self, turn_context: TurnContext) -> str:
        """Remove @mentions and clean message text"""
        text = turn_context.activity.text or ""
        
        # Remove @mentions
        if hasattr(turn_context.activity, 'entities') and turn_context.activity.entities:
            for entity in turn_context.activity.entities:
                if hasattr(entity, 'type') and entity.type == "mention":
                    mention_text = getattr(entity, 'text', '')
                    if mention_text:
                        text = text.replace(mention_text, "").strip()
        
        # Remove HTML tags and extra whitespace
        text = re.sub(r'<[^>]+>', '', text)
        text = re.sub(r'\s+', ' ', text)  # Normalize whitespace
        return text.strip()

    async def handle_commands(self, turn_context: TurnContext) -> bool:
        """Handle special bot commands"""
        message = self.clean_teams_message(turn_context).lower()
        
        if message.startswith('/help') or message == 'help':
            help_card = self.create_help_card()
            await turn_context.send_activity(MessageFactory.attachment(help_card))
            return True
        
        elif message.startswith('/clear') or message == 'clear':
            conversation_id = turn_context.activity.conversation.id
            self.conversation_state[conversation_id] = []
            await turn_context.send_activity(
                MessageFactory.text("✅ Conversation history cleared!")
            )
            return True
        
        return False

    def format_response_card(self, response) -> Attachment:
        """Create Adaptive Card for RAG response"""
        answer = response.get("answer", "No answer found")
        citations = response.get("citations", [])
        
        card = {
            "type": "AdaptiveCard",
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "version": "1.4",
            "body": [
                {
                    "type": "TextBlock",
                    "text": "🤖 AI Search Results",
                    "weight": "Bolder",
                    "size": "Medium",
                    "color": "Accent"
                },
                {
                    "type": "TextBlock",
                    "text": answer,
                    "wrap": True,
                    "separator": True,
                    "spacing": "Medium"
                }
            ]
        }

        # Add citations if available
        if citations:
            card["body"].append({
                "type": "TextBlock",
                "text": f"**📚 Sources ({len(citations)} found):**",
                "weight": "Bolder",
                "spacing": "Medium"
            })

            # Limit to 3 citations to avoid card being too large
            for i, citation in enumerate(citations[:3]):
                title = citation.get('title', f'Document {i+1}')
                content = citation.get("content", "")
                
                # Truncate content if too long
                if len(content) > 200:
                    content = content[:200] + "..."
                
                citation_container = {
                    "type": "Container",
                    "style": "emphasis",
                    "spacing": "Small",
                    "items": [
                        {
                            "type": "TextBlock",
                            "text": f"📄 {title}",
                            "weight": "Bolder",
                            "size": "Small"
                        },
                        {
                            "type": "TextBlock",
                            "text": content,
                            "wrap": True,
                            "isSubtle": True,
                            "spacing": "Small"
                        }
                    ]
                }
                card["body"].append(citation_container)

        return Attachment(
            content_type="application/vnd.microsoft.card.adaptive",
            content=card
        )

    def create_welcome_card(self) -> Attachment:
        """Create welcome card when bot is first added"""
        card = {
            "type": "AdaptiveCard",
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "version": "1.4",
            "body": [
                {
                    "type": "TextBlock",
                    "text": "👋 Welcome to AI Search Assistant!",
                    "weight": "Bolder",
                    "size": "Large"
                },
                {
                    "type": "TextBlock",
                    "text": "I can help you find information from your organizational documents using natural language questions.",
                    "wrap": True,
                    "spacing": "Medium"
                },
                {
                    "type": "TextBlock",
                    "text": "**Try asking me:**",
                    "weight": "Bolder",
                    "spacing": "Medium"
                },
                {
                    "type": "TextBlock",
                    "text": "• What's our vacation policy?\n• Tell me about Q3 results\n• How do I submit expenses?",
                    "wrap": True,
                    "spacing": "Small"
                },
                {
                    "type": "TextBlock",
                    "text": "Type `/help` anytime for more information!",
                    "wrap": True,
                    "spacing": "Medium",
                    "isSubtle": True
                }
            ]
        }

        return Attachment(
            content_type="application/vnd.microsoft.card.adaptive",
            content=card
        )

    def create_help_card(self) -> Attachment:
        """Create help card with bot instructions"""
        card = {
            "type": "AdaptiveCard",
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            "version": "1.4",
            "body": [
                {
                    "type": "TextBlock",
                    "text": "🤖 AI Search Assistant Help",
                    "weight": "Bolder",
                    "size": "Medium"
                },
                {
                    "type": "TextBlock",
                    "text": "Ask me questions about your organizational documents and I'll search for relevant information!",
                    "wrap": True,
                    "separator": True
                },
                {
                    "type": "TextBlock",
                    "text": "**Example questions:**",
                    "weight": "Bolder",
                    "spacing": "Medium"
                },
                {
                    "type": "TextBlock",
                    "text": "• What's our vacation policy?\n• Tell me about Q3 financial results\n• How do I submit expense reports?\n• What are the safety procedures?",
                    "wrap": True,
                    "spacing": "Small"
                },
                {
                    "type": "TextBlock",
                    "text": "**Available commands:**",
                    "weight": "Bolder",
                    "spacing": "Medium"
                },
                {
                    "type": "TextBlock",
                    "text": "• `/help` - Show this help message\n• `/clear` - Clear conversation history",
                    "wrap": True,
                    "spacing": "Small"
                },
                {
                    "type": "TextBlock",
                    "text": "**Tips:**",
                    "weight": "Bolder",
                    "spacing": "Medium"
                },
                {
                    "type": "TextBlock",
                    "text": "• Be specific in your questions\n• I remember our conversation context\n• I'll show sources for my answers",
                    "wrap": True,
                    "spacing": "Small"
                }
            ]
        }

        return Attachment(
            content_type="application/vnd.microsoft.card.adaptive",
            content=card
        )

    def get_conversation_history(self, conversation_id: str) -> list:
        """Get conversation history for context"""
        return self.conversation_state.get(conversation_id, [])

    def update_conversation_history(self, conversation_id: str, query: str, response: dict):
        """Update conversation history"""
        if conversation_id not in self.conversation_state:
            self.conversation_state[conversation_id] = []
        
        # Add user message and assistant response
        self.conversation_state[conversation_id].extend([
            {"role": "user", "content": query},
            {"role": "assistant", "content": response.get("answer", "")}
        ])
        
        # Keep only last 10 exchanges (20 messages) to manage memory
        if len(self.conversation_state[conversation_id]) > 20:
            self.conversation_state[conversation_id] = self.conversation_state[conversation_id][-20:]

    async def get_user_context(self, turn_context: TurnContext) -> dict:
        """Extract user context for authentication/authorization"""
        try:
            user_id = turn_context.activity.from_property.id if turn_context.activity.from_property else "unknown"
            user_name = turn_context.activity.from_property.name if turn_context.activity.from_property else "Unknown User"
            conversation_type = turn_context.activity.conversation.conversation_type if turn_context.activity.conversation else "unknown"
            
            return {
                "user_id": user_id,
                "user_name": user_name,
                "conversation_type": conversation_type
            }
        except Exception as e:
            logger.warning(f"Could not extract user context: {e}")
            return {
                "user_id": "unknown",
                "user_name": "Unknown User",
                "conversation_type": "unknown"
            }