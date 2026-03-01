#!/bin/bash

# Test script to verify backend connectivity and authentication

echo "=== Testing Readless Backend API ==="
echo ""

# 1. Test health endpoint
echo "1. Testing health endpoint..."
curl -s https://readless.cc/health
echo ""
echo ""

# 2. Test that content endpoint requires auth
echo "2. Testing content endpoint without auth (should fail)..."
curl -s -w "\nHTTP Status: %{http_code}\n" https://readless.cc/api/v1/content/ | head -20
echo ""
echo ""

# 3. Instructions for user
echo "=== Next Steps ==="
echo "Please run the macOS app and try to import content."
echo "We've added enhanced logging that will show:"
echo "  - Whether auth token is present"
echo "  - The API base URL being used"
echo "  - HTTP response status codes"
echo "  - Any network errors"
echo ""
echo "After trying cmd+k to import, please share the console output."
