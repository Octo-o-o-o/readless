#!/bin/bash
# Deploy Readless Landing Page to production server
# Usage: bash landing/deploy-landing.sh
#
# Prerequisites:
#   - SSH access to readless.cc server
#   - nginx installed on server

set -euo pipefail

SERVER="root@172.245.55.158"
PORT=52941
REMOTE_DIR="/var/www/readless-landing"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Readless Landing Page Deployment ==="
echo ""

# 1. Backup current nginx config
echo "[1/5] Backing up nginx configuration..."
ssh -p "$PORT" "$SERVER" "
  if [ -f /etc/nginx/sites-available/readless.cc ]; then
    cp /etc/nginx/sites-available/readless.cc /etc/nginx/sites-available/readless.cc.bak.\$(date +%Y%m%d-%H%M%S)
    echo 'Backup created'
  else
    echo 'No existing config to backup'
  fi
"

# 2. Create remote directory and upload files
echo ""
echo "[2/5] Uploading landing page files..."
ssh -p "$PORT" "$SERVER" "mkdir -p $REMOTE_DIR/landing-assets"
scp -P "$PORT" "$SCRIPT_DIR/index.html" "$SERVER:$REMOTE_DIR/"
scp -P "$PORT" "$SCRIPT_DIR/privacy.html" "$SERVER:$REMOTE_DIR/"
scp -P "$PORT" "$SCRIPT_DIR/terms.html" "$SERVER:$REMOTE_DIR/"
scp -P "$PORT" "$SCRIPT_DIR/robots.txt" "$SERVER:$REMOTE_DIR/"
scp -P "$PORT" "$SCRIPT_DIR/landing-assets/style.css" "$SERVER:$REMOTE_DIR/landing-assets/"
scp -P "$PORT" "$SCRIPT_DIR/landing-assets/main.js" "$SERVER:$REMOTE_DIR/landing-assets/"

# Upload favicon if exists
if [ -f "$SCRIPT_DIR/favicon.ico" ]; then
  scp -P "$PORT" "$SCRIPT_DIR/favicon.ico" "$SERVER:$REMOTE_DIR/"
fi

echo "Files uploaded."

# 3. Upload nginx config snippet
echo ""
echo "[3/5] Uploading nginx configuration snippet..."
scp -P "$PORT" "$SCRIPT_DIR/nginx-landing.conf" "$SERVER:/tmp/readless-landing.conf"
echo "Config uploaded to /tmp/readless-landing.conf"
echo ""
echo "⚠️  MANUAL STEP: Merge /tmp/readless-landing.conf into /etc/nginx/sites-available/readless.cc"
echo "   Insert the location blocks BEFORE the existing 'location /' block."
echo ""

# 4. Test nginx config
echo "[4/5] Testing nginx configuration..."
ssh -p "$PORT" "$SERVER" "nginx -t" && echo "✅ Nginx config test passed" || {
  echo "❌ Nginx config test FAILED. Rolling back..."
  ssh -p "$PORT" "$SERVER" "
    LATEST_BACKUP=\$(ls -t /etc/nginx/sites-available/readless.cc.bak.* 2>/dev/null | head -1)
    if [ -n \"\$LATEST_BACKUP\" ]; then
      cp \"\$LATEST_BACKUP\" /etc/nginx/sites-available/readless.cc
      nginx -t && nginx -s reload
      echo 'Rolled back to previous config'
    fi
  "
  exit 1
}

# 5. Reload nginx and verify
echo ""
echo "[5/5] Reloading nginx and verifying..."
ssh -p "$PORT" "$SERVER" "nginx -s reload"
sleep 2

echo ""
echo "=== Verification ==="

# Check landing page
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "https://readless.cc/")
echo "Landing page (GET /): HTTP $HTTP_CODE"

# Check API health (regression test)
API_CODE=$(curl -s -o /dev/null -w '%{http_code}' "https://readless.cc/health")
echo "API health (GET /health): HTTP $API_CODE"

# Check API docs
DOCS_CODE=$(curl -s -o /dev/null -w '%{http_code}' "https://readless.cc/docs")
echo "API docs (GET /docs): HTTP $DOCS_CODE"

# Check static assets
CSS_CODE=$(curl -s -o /dev/null -w '%{http_code}' "https://readless.cc/landing-assets/style.css?v=1")
echo "CSS (GET /landing-assets/style.css): HTTP $CSS_CODE"

echo ""
if [ "$API_CODE" = "200" ]; then
  echo "✅ API regression test passed"
else
  echo "❌ API regression test FAILED — consider rolling back"
fi

echo ""
echo "=== Deployment Complete ==="
echo "Visit: https://readless.cc"
