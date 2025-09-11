from botbuilder.core import ActivityHandler, MessageFactory, TurnContext
from botbuilder.core.teams import TeamsActivityHandler
from botbuilder.schema import Attachment
import re
import json

class TeamsRAGBot(TeamsActivityHandler):
    def __init__(self, rag_bridge):
        self.rag_bridge = rag_bridge
        self.conversation_state = {}

    async def on_message_activity(self, turn_context: TurnContext):
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

        # Send typing indicator
        await turn_context.send_activities([
            {"type": "typing"}
        ])

        try:
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
            error_message = "I'm having trouble processing your request. Please try again."
            await turn_context.send_activity(MessageFactory.text(error_message))
            # Log error for debugging
            print(f"Bot error: {str(e)}")

    def clean_teams_message(self, turn_context: TurnContext) -> str:
        """Remove @mentions and clean message text"""
        text = turn_context.activity.text or ""
        
        # Remove @mentions
        if hasattr(turn_context.activity, 'entities'):
            for entity in turn_context.activity.entities or []:
                if entity.type == "mention":
                    text = text.replace(entity.text, "").strip()
        
        # Remove HTML tags and extra whitespace
        text = re.sub(r'<[^>]+>', '', text)
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
                    "text": response.get("answer", "No answer found"),
                    "wrap": True,
                    "separator": True,
                    "spacing": "Medium"
                }
            ]
        }

        # Add citations if available
        citations = response.get("citations", [])
        if citations:
            card["body"].append({
                "type": "TextBlock",
                "text": f"**📚 Sources ({len(citations)} found):**",
                "weight": "Bolder",
                "spacing": "Medium"
            })

            for i, citation in enumerate(citations[:3]):  # Limit to 3 citations
                citation_container = {
                    "type": "Container",
                    "style": "emphasis",
                    "spacing": "Small",
                    "items": [
                        {
                            "type": "ColumnSet",
                            "columns": [
                                {
                                    "type": "Column",
                                    "width": "auto",
                                    "items": [
                                        {
                                            "type": "TextBlock",
                                            "text": f"📄 {citation.get('title', f'Document {i+1}')}",
                                            "weight": "Bolder",
                                            "size": "Small"
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            "type": "TextBlock",
                            "text": citation.get("content", "")[:200] + "..." if len(citation.get("content", "")) > 200 else citation.get("content", ""),
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
                    "text": "Ask me questions about your organizational documents!",
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
                    "text": "• What's our vacation policy?\n• Tell me about Q3 financial results\n• How do I submit expense reports?",
                    "wrap": True,
                    "spacing": "Small"
                },
                {
                    "type": "TextBlock",
                    "text": "**Commands:**",
                    "weight": "Bolder",
                    "spacing": "Medium"
                },
                {
                    "type": "TextBlock",
                    "text": "• `/help` - Show this help\n• `/clear` - Clear conversation history",
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
        
        # Keep only last 10 exchanges (20 messages)
        if len(self.conversation_state[conversation_id]) > 20:
            self.conversation_state[conversation_id] = self.conversation_state[conversation_id][-20:]

    async def get_user_context(self, turn_context: TurnContext) -> dict:
        """Extract user context for authentication/authorization"""
        return {
            "user_id": turn_context.activity.from_property.id,
            "user_name": turn_context.activity.from_property.name,
            "conversation_type": turn_context.activity.conversation.conversation_type
        }
