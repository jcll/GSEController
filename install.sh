#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

ICON_DIR="GSEController/Assets.xcassets/AppIcon.appiconset"

if [ ! -f make_icon.swift ]; then
    echo "❌  make_icon.swift not found — cannot generate icon"
    exit 1
fi

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
    -showBuildSettings 2>&1 \
    | awk '/BUILT_PRODUCTS_DIR =/ { print $NF; exit }')

if [ -z "$BUILD_DIR" ]; then
    echo "❌  Could not determine BUILT_PRODUCTS_DIR — is Xcode installed?"
    exit 1
fi

BUILD_LOG=$(mktemp /tmp/gse_build.XXXXXX)
trap 'rm -f "$BUILD_LOG"' EXIT

echo "🔨  Building release..."
xcodebuild -project GSEController.xcodeproj \
           -scheme GSEController \
           -configuration Release \
           build \
           2>&1 | tee "$BUILD_LOG" | \
           grep -Ev "^$|^note:|appintentsmetadata|^    " | \
           grep -E "error:|BUILD|warning:" || true

if grep -q "BUILD FAILED" "$BUILD_LOG"; then
    echo "❌  Build failed"
    exit 1
fi

APP_SRC="$BUILD_DIR/GSEController.app"
APP_DST="/Applications/GSEController.app"

if [ ! -d "$APP_SRC" ]; then
    echo "❌  Built app not found at $APP_SRC"
    exit 1
fi

echo "📦  Installing to /Applications..."
[ -d "$APP_DST" ] && rm -rf "$APP_DST"
cp -r "$APP_SRC" "$APP_DST"
xattr -cr "$APP_DST"

echo ""
echo "✅  GSE Controller installed!"
echo "    Open it from Launchpad or Spotlight, or run:  open -a GSEController"
