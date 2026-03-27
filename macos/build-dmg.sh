#!/bin/bash
set -euo pipefail

# =============================================================================
# Readless — Build, Sign, Notarize, and Package as DMG
# =============================================================================
# Prerequisites:
#   - Xcode with Developer ID Application certificate
#   - xcodegen (brew install xcodegen)
#   - create-dmg (brew install create-dmg)
#   - Notarization credentials stored: xcrun notarytool store-credentials "notary"
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Readless"
SIGNING_IDENTITY="Developer ID Application: Yixiao Wang (5CS6HUB4P2)"
TEAM_ID="5CS6HUB4P2"
NOTARY_PROFILE="notary"

# Clean build directory
echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# =============================================================================
# Step 1: Regenerate Xcode project (in case sources changed)
# =============================================================================
echo "==> Regenerating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate 2>&1

# =============================================================================
# Step 2: Archive with automatic signing
# =============================================================================
echo "==> Archiving $APP_NAME (Release)..."
xcodebuild \
    -project "$PROJECT_DIR/Readless.xcodeproj" \
    -scheme Readless \
    -configuration Release \
    -archivePath "$BUILD_DIR/Readless.xcarchive" \
    CODE_SIGN_STYLE="Automatic" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    archive \
    2>&1 | tail -5

APP_PATH="$BUILD_DIR/Readless.xcarchive/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_NAME.app not found in archive!"
    exit 1
fi
echo "==> Archived: $APP_PATH"

# =============================================================================
# Step 3: Re-sign with Developer ID Application
# =============================================================================
echo "==> Re-signing with Developer ID Application..."

# Remove development provisioning profile (causes mismatch with Developer ID signing)
rm -f "$APP_PATH/Contents/embedded.provisionprofile"

# Entitlements for Developer ID distribution
# NOTE: com.apple.developer.applesignin is excluded because it requires a
# Developer ID provisioning profile. Without it, the app will crash on launch.
cat > "$BUILD_DIR/entitlements.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF

# Re-sign frameworks and dylibs first (inside-out)
find "$APP_PATH" -name "*.dylib" -type f 2>/dev/null | while read lib; do
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$lib"
done
find "$APP_PATH/Contents/Frameworks" -name "*.framework" -type d 2>/dev/null | while read fw; do
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime "$fw"
done

# Re-sign main app bundle
codesign --force --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --entitlements "$BUILD_DIR/entitlements.plist" \
    "$APP_PATH"

# Verify
codesign --verify --deep --strict "$APP_PATH" 2>&1
echo "==> Signature verified (Developer ID Application + Hardened Runtime)"

# =============================================================================
# Step 4: Create DMG
# =============================================================================
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
echo "==> Creating DMG..."

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 175 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 425 190 \
    "$DMG_PATH" \
    "$STAGING_DIR" \
    2>&1 || {
        echo "==> create-dmg had issues, falling back to hdiutil..."
        rm -f "$DMG_PATH"
        hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
    }

# Sign the DMG
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
echo "==> DMG created and signed: $DMG_PATH"

# =============================================================================
# Step 5: Notarize
# =============================================================================
echo "==> Submitting for notarization (may take a few minutes)..."

xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait \
    2>&1 | tee "$BUILD_DIR/notarization-result.txt"

if grep -q "status: Accepted" "$BUILD_DIR/notarization-result.txt"; then
    echo "==> Notarization ACCEPTED!"
else
    echo "==> Notarization failed. Check $BUILD_DIR/notarization-result.txt"
    echo "    Details: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
    exit 1
fi

# =============================================================================
# Step 6: Staple
# =============================================================================
echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "============================================="
echo "  SUCCESS! Notarized DMG ready for distribution:"
echo "  $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "============================================="
