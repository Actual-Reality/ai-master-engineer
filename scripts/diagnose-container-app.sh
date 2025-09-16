#!/bin/bash

# Quick Container App Diagnosis
# Run this to check the status of your container app

RESOURCE_GROUP="rg-ai-master-engineer"
CONTAINER_APP_NAME="teams-search-bot-capp"

echo "🔍 Container App Quick Diagnosis"
echo "================================="

echo "📊 Container App Details:"
az containerapp show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP_NAME" \
    --query "{name:name, state:properties.provisioningState, fqdn:properties.configuration.ingress.fqdn, replicas:properties.template.scale.minReplicas}" \
    -o table

echo ""
echo "🔄 Active Revisions:"
az containerapp revision list --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP_NAME" \
    --query "[].{Name:name, Active:properties.active, CreatedTime:properties.createdTime, Replicas:properties.replicas}" \
    -o table

echo ""
echo "⚙️ Environment Variables:"
az containerapp show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP_NAME" \
    --query "properties.template.containers[0].env[].{Name:name, Value:value}" \
    -o table

echo ""
echo "📝 Recent Logs (last 20 lines):"
az containerapp logs show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_APP_NAME" --tail 20

echo ""
echo "🌐 Testing Connectivity:"
CONTAINER_URL="https://teams-search-bot-capp.salmoncliff-681251ec.eastus.azurecontainerapps.io"

echo "Testing root URL: $CONTAINER_URL"
curl -v --max-time 10 "$CONTAINER_URL" 2>&1 | head -20

echo ""
echo "Testing bot endpoint: $CONTAINER_URL/api/messages"
curl -v --max-time 10 "$CONTAINER_URL/api/messages" 2>&1 | head -20