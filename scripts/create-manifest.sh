#!/bin/bash

# Script to create Teams app manifest with correct App ID
# Usage: ./create-manifest.sh <APP_ID>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <APP_ID>"
    echo "Example: $0 12345678-1234-1234-1234-123456789012"
    exit 1
fi

APP_ID=$1
MANIFEST_DIR="manifest"

echo "🔧 Creating Teams app manifest with App ID: $APP_ID"

# Create manifest directory if it doesn't exist
mkdir -p "$MANIFEST_DIR"

# Update manifest.json with the correct App ID
sed "s/00000000-0000-0000-0000-000000000000/$APP_ID/g" "$MANIFEST_DIR/manifest.json" > "$MANIFEST_DIR/manifest_updated.json"
mv "$MANIFEST_DIR/manifest_updated.json" "$MANIFEST_DIR/manifest.json"

echo "✅ Updated manifest.json with App ID: $APP_ID"

# Create simple icon files (placeholder - replace with actual icons)
echo "🎨 Creating placeholder icon files..."

# Create a simple SVG for color icon (192x192)
cat > "$MANIFEST_DIR/color.png.svg" << 'EOF'
<svg width="192" height="192" xmlns="http://www.w3.org/2000/svg">
  <rect width="192" height="192" fill="#0078d4"/>
  <text x="96" y="110" font-family="Arial" font-size="48" fill="white" text-anchor="middle">🤖</text>
  <text x="96" y="140" font-family="Arial" font-size="16" fill="white" text-anchor="middle">AI Search</text>
</svg>
EOF

# Create a simple SVG for outline icon (32x32)
cat > "$MANIFEST_DIR/outline.png.svg" << 'EOF'
<svg width="32" height="32" xmlns="http://www.w3.org/2000/svg">
  <rect width="32" height="32" fill="none" stroke="#242424" stroke-width="2"/>
  <text x="16" y="22" font-family="Arial" font-size="16" fill="#242424" text-anchor="middle">🤖</text>
</svg>
EOF

echo "📦 Creating Teams app package..."

# Create app package (zip file)
cd "$MANIFEST_DIR"
zip -r "../teams-app-package.zip" manifest.json *.png *.svg 2>/dev/null || echo "Note: Add actual PNG icon files to complete the package"
cd ..

echo "
✅ Teams app manifest created successfully!

📋 Files created:
- manifest/manifest.json (updated with App ID)
- manifest/color.png.svg (placeholder - convert to PNG 192x192)
- manifest/outline.png.svg (placeholder - convert to PNG 32x32)
- teams-app-package.zip (app package for Teams)

📝 Next steps:
1. Convert SVG files to PNG format:
   - color.png: 192x192 pixels
   - outline.png: 32x32 pixels
2. Update manifest/manifest.json with your organization details
3. Upload teams-app-package.zip to Teams Admin Center or Developer Portal

🔗 Useful links:
- Teams Developer Portal: https://dev.teams.microsoft.com/
- Icon guidelines: https://docs.microsoft.com/en-us/microsoftteams/platform/concepts/build-and-test/apps-package
"
