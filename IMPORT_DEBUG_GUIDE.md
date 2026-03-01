# Import Error Debug Guide

## Issue
After successful Google OAuth login, importing content via cmd+k fails with:
```
Import failed: The operation couldn't be completed. (Networking.APIError error 0.)
```

## Changes Made

### 1. Enhanced Logging in APIClient
Added detailed logging for all API requests:
- ✅ Request URL and method
- ✅ Auth token presence and length
- ✅ HTTP response status codes
- ✅ Network errors with descriptions
- ✅ Server error responses (with body content)

Location: `macos/Sources/Networking/APIClient.swift` lines 54-90

### 2. Enhanced Logging in AuthManager
Added logging for authentication flow:
- ✅ Initial session token sync
- ✅ Token preview (first 20 chars)
- ✅ Sign out confirmation
- ✅ Token refresh with URL display

Location: `macos/Sources/App/Services/AuthManager.swift`

### 3. Enhanced Error Handling in SimpleAuthView
Changed from silent `try?` to explicit error handling:
- ✅ Catches and logs token sync errors
- ✅ Shows user-friendly error messages
- ✅ Applies to all auth methods (email, Google, Apple)

Location: `macos/Sources/App/Views/SimpleAuthView.swift`

## Backend Verification

Tested production backend at https://readless.cc:
- ✅ Health endpoint: returns `{"status":"ok"}`
- ✅ Auth protection: content endpoint returns 401 without token
- ✅ Backend is properly configured and running

## How to Debug

### Step 1: Run the App
```bash
cd /Users/wangyixiao/WorkSpace/readless/macos
swift run App 2>&1 | tee app_log.txt
```

### Step 2: Look for These Log Messages

**On App Launch:**
```
[AuthManager] ✅ Initial session token synced to APIClient
[AuthManager] Token preview: eyJhbGciOiJSUzI1NiIsI...
[Readless] Using configured API base URL: https://readless.cc
```

**When Importing Content (cmd+k):**
```
[APIClient] 🔐 Request to https://readless.cc/api/v1/content/ with auth token (length: 450)
[APIClient] 📡 Response status: 200
```

### Step 3: Check for Error Patterns

**Pattern 1: No Auth Token**
```
[APIClient] ⚠️ Request to https://readless.cc/api/v1/content/ WITHOUT auth token
[APIClient] ❌ Server error: 401
```
**Solution:** Token not synced after login. AuthManager.refreshToken() not called.

**Pattern 2: Network Error**
```
[APIClient] ❌ Network error: The Internet connection appears to be offline.
```
**Solution:** Check internet connectivity or backend URL configuration.

**Pattern 3: Invalid Token**
```
[APIClient] 🔐 Request with auth token (length: 450)
[APIClient] ❌ Server error: 401
[APIClient] Error response: {"detail":"Invalid token"}
```
**Solution:** Token expired or invalid. Clerk JWT verification issue.

**Pattern 4: Wrong URL**
```
[APIClient] ❌ Invalid URL: /api/v1/content/ relative to http://localhost:8000
```
**Solution:** Backend URL not configured. Run:
```bash
defaults write com.readless.app apiBaseURL "https://readless.cc"
```

## Current Configuration

```bash
$ defaults read com.readless.app apiBaseURL
https://readless.cc
```

## Expected Behavior

1. User logs in via Google OAuth
2. SimpleAuthView calls `AuthManager.shared.refreshToken()`
3. AuthManager gets JWT from Clerk session
4. AuthManager sets `APIClient.shared.authToken = token`
5. User presses cmd+k to import content
6. APIClient sends POST to `/api/v1/content/` with `Authorization: Bearer <token>`
7. Backend validates JWT and creates content
8. Content appears in app

## Potential Issues

### Issue 1: Token Not Synced After Login
**Symptom:** No auth token in request
**Cause:** `AuthManager.refreshToken()` not called or failed silently
**Fix:** Now using explicit error handling instead of `try?`

### Issue 2: Clerk Session Not Persisting
**Symptom:** User logged in but `clerk.session` is nil on next launch
**Cause:** Clerk session storage issue
**Investigation:** Check if Clerk SDK persists sessions in macOS

### Issue 3: Token Format Issue
**Symptom:** Token present but 401 error
**Cause:** Backend expects Clerk JWT but receiving something else
**Investigation:** Print token format and compare with backend expectations

### Issue 4: CORS or Backend Configuration
**Symptom:** Network error or unexpected response
**Cause:** Backend not accepting requests from macOS app
**Investigation:** Check backend CORS settings and nginx configuration

## Next Steps

1. **Run the app** with the new logging
2. **Try to import content** via cmd+k
3. **Share the console output** showing the log messages
4. **Look for the error pattern** described above
5. **Apply the appropriate fix** based on the pattern

The enhanced logging will reveal exactly where the authentication flow is breaking down.
