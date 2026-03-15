#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

ICON_DIR="GSEController/Assets.xcassets/AppIcon.appiconset"

echo "🎨  Generating icon..."
swift make_icon.swift "$ICON_DIR"

cat > "$ICON_DIR/Contents.json" << 'EOF'
{
  "images" : [
    { "filename": "icon_16x16.png",      "idiom": "mac", "scale": "1x", "size": "16x16"   },
    { "filename": "icon_16x16@2x.png",   "idiom": "mac", "scale": "2x", "size": "16x16"   },
    { "filename": "icon_32x32.png",      "idiom": "mac", "scale": "1x", "size": "32x32"   },
    { "filename": "icon_32x32@2x.png",   "idiom": "mac", "scale": "2x", "size": "32x32"   },
    { "filename": "icon_128x128.png",    "idiom": "mac", "scale": "1x", "size": "128x128" },
    { "filename": "icon_128x128@2x.png", "idiom": "mac", "scale": "2x", "size": "128x128" },
    { "filename": "icon_256x256.png",    "idiom": "mac", "scale": "1x", "size": "256x256" },
    { "filename": "icon_256x256@2x.png", "idiom": "mac", "scale": "2x", "size": "256x256" },
    { "filename": "icon_512x512.png",    "idiom": "mac", "scale": "1x", "size": "512x512" },
    { "filename": "icon_512x512@2x.png", "idiom": "mac", "scale": "2x", "size": "512x512" }
  ],
  "info" : { "author": "xcode", "version": 1 }
}
EOF

BUILD_DIR=$(xcodebuild -project GSEController.xcodeproj \
    -scheme GSEController \
    -configuration Release \
    -showBuildSettings 2>/dev/null \
    | grep -m1 'BUILT_PRODUCTS_DIR' | sed 's/.*= //')

echo "🔨  Building release..."
xcodebuild -project GSEController.xcodeproj \
           -scheme GSEController \
           -configuration Release \
           build \
           2>&1 | grep -Ev "^$|^note:|appintentsmetadata|^    " | grep -E "error:|BUILD|warning:" || true

APP_SRC="$BUILD_DIR/GSEController.app"
APP_DST="/Applications/GSEController.app"

echo "📦  Installing to /Applications..."
[ -d "$APP_DST" ] && rm -rf "$APP_DST"
cp -r "$APP_SRC" "$APP_DST"

echo ""
echo "✅  GSE Controller installed!"
echo "    Open it from Launchpad or Spotlight, or run:  open -a GSEController"
