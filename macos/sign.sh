#!/bin/bash
# sign.sh — Build Readless as a proper .app bundle with Sign in with Apple support.
#
# Why a bundle? The com.apple.developer.applesignin entitlement is a privileged
# entitlement. AMFI validates it against an embedded provisioning profile, which
# can only be embedded inside an .app bundle (Contents/embedded.provisionprofile).
set -e

IDENTITY="Apple Development: Yixiao Wang (QQG4GHX8SN)"
PROFILE="/Users/wangyixiao/Library/Developer/Xcode/UserData/Provisioning Profiles/9d0f5a2a-ad7b-4756-8697-a1e5d347a264.provisionprofile"
ENTITLEMENTS="Sources/App/Resources/App.entitlements"
BINARY=".build/arm64-apple-macosx/debug/App"
BUNDLE="Readless.app"
# Default local test builds to production backend.
# Override for local backend testing:
#   READLESS_API_BASE_URL=http://localhost:8000 bash sign.sh
BACKEND_URL="${READLESS_API_BASE_URL:-https://readless.cc}"

echo "🔨 Building..."
swift build
echo ""

# Kill any stale instance (launchd won't spawn a second one for the same bundle ID)
killall App 2>/dev/null || true
sleep 0.5

echo "📦 Assembling .app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# Executable
cp "$BINARY" "$BUNDLE/Contents/MacOS/App"
chmod +x "$BUNDLE/Contents/MacOS/App"

# Info.plist
cp "Sources/App/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

# PkgInfo — required by Launch Services to recognise the bundle as a valid .app
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"
echo "  ✓ PkgInfo written"

# Embed provisioning profile — AMFI checks this for privileged entitlements
cp "$PROFILE" "$BUNDLE/Contents/embedded.provisionprofile"
echo "  ✓ Provisioning profile embedded"

# Strip any quarantine / extended attributes that block Gatekeeper launch
chmod -R u+w "$BUNDLE"
xattr -cr "$BUNDLE"
echo "  ✓ Quarantine attributes cleared"

echo ""
echo "🌐 Configuring backend..."
defaults write com.readless.app apiBaseURL "$BACKEND_URL"
echo "  ✓ apiBaseURL = $BACKEND_URL"

echo ""
echo "✍️  Signing..."
# Sign the whole bundle in one pass.
# --generate-entitlement-der: required for AMFI on macOS 12+ (encodes entitlements as DER
#   blob alongside the XML plist; without it macOS 26 AMFI rejects privileged entitlements)
codesign --force \
    --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --generate-entitlement-der \
    "$BUNDLE"
echo ""

echo "✅ Verifying..."
codesign --verify --verbose "$BUNDLE" 2>&1
codesign -dvvv "$BUNDLE" 2>&1 | grep -E "(Identifier|TeamIdentifier|Authority)"
echo ""

echo "🔑 Embedded entitlements:"
codesign --display --entitlements - "$BUNDLE" 2>&1
echo ""

echo "📋 Provisioning profile entitlements (what AMFI sees):"
security cms -D -i "$BUNDLE/Contents/embedded.provisionprofile" 2>/dev/null \
    | grep -A 40 "<key>Entitlements</key>" | head -40
echo ""

echo "🚀 Launching Readless.app..."
# 'open' rejects apps outside /Applications / ~/Applications with error -600.
# Run the binary directly instead — safe now that get-task-allow is omitted and
# all entitlements are a strict subset of what the provisioning profile authorises.
"$BUNDLE/Contents/MacOS/App"
