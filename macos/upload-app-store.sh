#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$ROOT_DIR/Readless.xcodeproj"
SCHEME="Readless"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/ExportOptions-AppStore.plist"

KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"
P8_PATH="${APP_STORE_CONNECT_P8_PATH:-}"

if [[ -z "$KEY_ID" || -z "$ISSUER_ID" ]]; then
  echo "Set APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID before running." >&2
  exit 1
fi

if [[ -z "$P8_PATH" ]]; then
  P8_PATH="$HOME/Downloads/AuthKey_${KEY_ID}.p8"
fi

if [[ ! -f "$P8_PATH" ]]; then
  echo "Auth key file not found: $P8_PATH" >&2
  exit 1
fi

ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/app-store/Readless.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/build/app-store/export}"

mkdir -p "$(dirname "$ARCHIVE_PATH")"
rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"

echo "==> Archiving $SCHEME for App Store Connect"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$P8_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID" \
  archive

echo "==> Exporting App Store package"
xcodebuild \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$P8_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID" \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

PKG_PATH="$(find "$EXPORT_PATH" -maxdepth 1 -name '*.pkg' -print -quit)"
if [[ -z "$PKG_PATH" ]]; then
  echo "No .pkg found in $EXPORT_PATH" >&2
  exit 1
fi

echo "==> Uploading $PKG_PATH"
xcrun altool \
  --upload-app \
  -f "$PKG_PATH" \
  --type osx \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID" \
  --p8-file-path "$P8_PATH" \
  --output-format json
