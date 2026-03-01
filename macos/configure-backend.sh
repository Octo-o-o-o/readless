#!/bin/bash

# Readless macOS App - Backend Configuration Script
# Usage: ./configure-backend.sh [URL]
# Example: ./configure-backend.sh https://api.readless.cc

set -e

echo "🔧 Readless Backend Configuration"
echo ""

# Check if URL is provided
if [ -z "$1" ]; then
    echo "Usage: ./configure-backend.sh <backend-url>"
    echo ""
    echo "Examples:"
    echo "  ./configure-backend.sh https://api.readless.cc"
    echo "  ./configure-backend.sh http://localhost:8000"
    echo ""

    # Show current configuration
    CURRENT=$(defaults read com.readless.app apiBaseURL 2>/dev/null || echo "http://localhost:8000 (default)")
    echo "Current backend URL: $CURRENT"
    echo ""

    echo "To reset to default (localhost):"
    echo "  defaults delete com.readless.app apiBaseURL"
    echo ""
    exit 1
fi

BACKEND_URL="$1"

# Validate URL format
if [[ ! "$BACKEND_URL" =~ ^https?:// ]]; then
    echo "❌ Error: URL must start with http:// or https://"
    echo "   Provided: $BACKEND_URL"
    exit 1
fi

# Remove trailing slash if present
BACKEND_URL="${BACKEND_URL%/}"

echo "Setting backend URL to: $BACKEND_URL"
defaults write com.readless.app apiBaseURL "$BACKEND_URL"

echo "✅ Configuration saved!"
echo ""
echo "Next steps:"
echo "1. Restart the Readless app if it's running"
echo "2. The app will now connect to: $BACKEND_URL"
echo ""
echo "To verify the configuration:"
echo "  defaults read com.readless.app apiBaseURL"
echo ""
echo "To test the backend connection:"
echo "  curl $BACKEND_URL/health"
echo ""
