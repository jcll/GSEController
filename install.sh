#!/bin/bash
set -euo pipefail

# Build-and-install helper for local source checkouts. The script keeps the
# documented install path short while still failing clearly and avoiding
# destructive replacement until a new app bundle is staged successfully.

# Resolve repo-relative paths so the script behaves the same from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_FILE="GSEController.xcodeproj"
SCHEME="GSEController"
CONFIGURATION="Release"
DESTINATION="generic/platform=macOS"
APP_NAME="GSEController.app"
ICON_DIR="GSEController/Assets.xcassets/AppIcon.appiconset"
APP_DST="/Applications/$APP_NAME"

BUILD_LOG=""
KEEP_BUILD_LOG=0
APP_STAGE=""
APP_BACKUP=""

cleanup() {
    if [ -n "$BUILD_LOG" ] && [ "$KEEP_BUILD_LOG" -eq 0 ]; then
        rm -f "$BUILD_LOG"
    fi
    if [ -n "$APP_STAGE" ] && [ -d "$APP_STAGE" ]; then
        rm -rf "$APP_STAGE"
    fi
    if [ -n "$APP_BACKUP" ] && [ -d "$APP_BACKUP" ] && [ ! -d "$APP_DST" ]; then
        mv "$APP_BACKUP" "$APP_DST" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

die() {
    echo "❌  $*" >&2
    exit 1
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        die "$1 not found. Install Xcode and its command-line tools, then retry."
    fi
}

require_file() {
    if [ ! -f "$1" ]; then
        die "$2"
    fi
}

require_dir() {
    if [ ! -d "$1" ]; then
        die "$2"
    fi
}

# Bootstrap the local xcconfig on fresh clones so bundle IDs resolve before the
# first Xcode build.
if [ ! -f LocalConfig.xcconfig ]; then
    if [ -f LocalConfig.xcconfig.template ]; then
        echo "🧩  Creating LocalConfig.xcconfig from template..."
        cp LocalConfig.xcconfig.template LocalConfig.xcconfig
    else
        echo "🧩  Creating LocalConfig.xcconfig..."
        cat > LocalConfig.xcconfig << 'EOF'
// LocalConfig.xcconfig
// Your personal bundle ID prefix. Change this if you're building a fork.
BUNDLE_ID_PREFIX = com.example
PRODUCT_BUNDLE_IDENTIFIER = $(BUNDLE_ID_PREFIX).GSEController
EOF
    fi
fi

require_tool swift
require_tool xcodebuild
require_tool xattr

# Verify Xcode version — this project requires macOS 26 Tahoe+ and Xcode 26+.
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 | sed -E 's/Xcode ([0-9]+)\.([0-9]+).*/\1/')
if [ -z "$XCODE_VERSION" ] || [ "$XCODE_VERSION" -lt 16 ]; then
    die "Xcode 16.0 or later is required (found: $(xcodebuild -version 2>/dev/null | head -1 || echo 'unknown')). Install the latest Xcode from the Mac App Store or Apple Developer portal."
fi
require_file make_icon.swift "make_icon.swift not found — cannot generate icon"
require_dir "$PROJECT_FILE" "$PROJECT_FILE not found"
require_dir "$ICON_DIR" "$ICON_DIR not found"

# Regenerate the icon set and Contents.json rather than relying on committed
# generated metadata staying in sync with the script.
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

# Ask xcodebuild for the actual Release products directory instead of guessing
# the DerivedData layout.
if ! BUILD_DIR=$(xcodebuild -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -showBuildSettings 2>&1 \
    | awk -F ' = ' '$1 ~ /^[[:space:]]*BUILT_PRODUCTS_DIR$/ { buildDir=$2 } END { if (buildDir) print buildDir }'); then
    die "Could not read build settings — is Xcode installed?"
fi

if [ -z "$BUILD_DIR" ]; then
    die "Could not determine BUILT_PRODUCTS_DIR — is Xcode installed?"
fi

BUILD_LOG=$(mktemp /tmp/gse_build.XXXXXX)

# Keep the console output terse, but preserve a full log when the build fails.
echo "🔨  Building release..."
set +e
xcodebuild -project "$PROJECT_FILE" \
           -scheme "$SCHEME" \
           -configuration "$CONFIGURATION" \
           -destination "$DESTINATION" \
           build \
           2>&1 | tee "$BUILD_LOG" | \
           grep -Ev "^$|^note:|appintentsmetadata|^    " | \
           grep -E "error:|BUILD|warning:"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [ "$BUILD_STATUS" -ne 0 ] || grep -q "BUILD FAILED" "$BUILD_LOG"; then
    KEEP_BUILD_LOG=1
    echo "❌  Build failed (full log retained at $BUILD_LOG)"
    exit 1
fi

APP_SRC="$BUILD_DIR/$APP_NAME"

if [ ! -d "$APP_SRC" ]; then
    die "Built app not found at $APP_SRC"
fi

# Stage first, then swap into /Applications. If the final move fails, try to
# restore the previous app bundle instead of leaving the user without one.
echo "📦  Installing to /Applications..."
APP_STAGE=$(mktemp -d /tmp/gse_install.XXXXXX)
cp -R "$APP_SRC" "$APP_STAGE/"
xattr -cr "$APP_STAGE/$APP_NAME"

if [ -e "$APP_DST" ] && [ ! -d "$APP_DST" ]; then
    die "$APP_DST exists but is not an app bundle directory"
fi

if [ -d "$APP_DST" ]; then
    APP_BACKUP="/Applications/$APP_NAME.previous.$$"
    if [ -e "$APP_BACKUP" ]; then
        die "Temporary backup path already exists: $APP_BACKUP"
    fi
    mv "$APP_DST" "$APP_BACKUP"
fi

if ! mv "$APP_STAGE/$APP_NAME" "$APP_DST"; then
    if [ -n "$APP_BACKUP" ] && [ -d "$APP_BACKUP" ]; then
        mv "$APP_BACKUP" "$APP_DST" || echo "⚠️  Failed to restore previous app from $APP_BACKUP" >&2
    fi
    die "Install failed; previous app was restored if possible"
fi

if [ -n "$APP_BACKUP" ] && [ -d "$APP_BACKUP" ]; then
    rm -rf "$APP_BACKUP"
fi

echo ""
echo "✅  GSE Controller installed!"
echo "    Open it from Launchpad or Spotlight, or run:  open -a GSEController"
