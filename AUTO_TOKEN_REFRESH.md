# Auto Token Refresh Implementation

## Problem

JWT tokens have a limited lifetime (typically 1 hour). When a token expires, API requests fail with:
```
401 Unauthorized
{"detail":"Token expired"}
```

## Solution

Implemented automatic token refresh with retry mechanism.

## How It Works

### 1. Token Expiration Detection (APIClient)

When a request fails with 401 and "Token expired":

```swift
// APIClient.swift - request() method
if http.statusCode == 401 && errorMessage.contains("Token expired") && !isRetry {
    print("[APIClient] 🔄 Token expired, attempting refresh and retry...")

    // Notify AuthManager to refresh token
    await MainActor.run {
        NotificationCenter.default.post(name: .refreshAuthToken, object: nil)
    }

    // Wait for refresh
    try await Task.sleep(for: .milliseconds(500))

    // Retry the request once
    return try await request(path, method: method, body: body, isRetry: true)
}
```

### 2. Token Refresh (AuthManager)

AuthManager listens for refresh notifications:

```swift
// AuthManager.swift - init()
NotificationCenter.default.addObserver(
    forName: .refreshAuthToken,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in
        try await self?.refreshToken()
    }
}
```

The `refreshToken()` method:
1. Gets a fresh token from Clerk session: `session.getToken()`
2. Updates `APIClient.shared.authToken`
3. Logs the refresh

### 3. Request Retry

After token refresh, the original request is automatically retried **once**:
- Uses `isRetry` flag to prevent infinite loops
- If retry fails, the error is propagated to the caller

## Flow Diagram

```
User Action (cmd+k)
    ↓
APIClient.createContent()
    ↓
request() with expired token
    ↓
Backend returns 401 "Token expired"
    ↓
APIClient detects expiration
    ↓
Posts .refreshAuthToken notification
    ↓
AuthManager receives notification
    ↓
AuthManager.refreshToken()
    ↓
Calls Clerk session.getToken()
    ↓
Updates APIClient.shared.authToken
    ↓
APIClient retries request with fresh token
    ↓
Backend returns 200 Success ✅
```

## Benefits

1. **Transparent**: User doesn't see any error or interruption
2. **Efficient**: Only refreshes when needed (on 401)
3. **Safe**: Retry limit prevents infinite loops
4. **Decoupled**: Uses NotificationCenter for loose coupling

## Log Output

Successful auto-refresh looks like:

```
[APIClient] 🔐 Request to https://readless.cc/api/v1/content/ with auth token (length: 764)
[APIClient] 📡 Response status: 401
[APIClient] ❌ Server error: 401
[APIClient] Error response: {"detail":"Token expired"}
[APIClient] 🔄 Token expired, attempting refresh and retry...
[AuthManager] ✅ Token refreshed and synced to APIClient
[AuthManager] Token preview: eyJhbGciOiJSUzI1NiIs...
[AuthManager] API base URL: https://readless.cc
[APIClient] 🔐 Request to https://readless.cc/api/v1/content/ with auth token (length: 764)
[APIClient] 📡 Response status: 200
```

## Token Lifetime

- **Default**: 1 hour (3600 seconds)
- **Configurable**: Can be adjusted in Clerk Dashboard
- **Refresh**: Happens automatically via `session.getToken()`

## Edge Cases Handled

1. **No active session**: `refreshToken()` checks for `clerk.session` first
2. **Refresh fails**: Error is logged, original 401 error is thrown
3. **Retry fails**: Error is propagated to caller (no infinite retry)
4. **Network errors**: Not retried (only token expiration)

## Future Improvements

1. **Proactive refresh**: Refresh token before it expires (e.g., at 50 minutes)
2. **Background refresh**: Periodically refresh in background
3. **Exponential backoff**: For temporary network failures
4. **Token caching**: Cache valid token with expiration time

## Related Files

- `macos/Sources/Networking/APIClient.swift` - Request retry logic
- `macos/Sources/App/Services/AuthManager.swift` - Token refresh handler
- `macos/Sources/App/ReadlessApp.swift` - AuthManager initialization

## Testing

To test token refresh:
1. Wait for token to expire (1 hour)
2. Try to import content via cmd+k
3. Check logs for auto-refresh messages
4. Verify request succeeds after refresh

Or manually trigger expiration:
```swift
// In AuthManager.swift (for testing only)
APIClient.shared.authToken = "expired_token"
```
