# JWT Authentication + App Store Subscription System Design

**Date**: 2026-03-02
**Author**: Claude
**Status**: Approved

## Executive Summary

Replace Clerk authentication with custom JWT auth system and integrate App Store in-app purchases for subscription management. The system supports:

- **Email + Password** authentication with email verification and password reset (Resend)
- **Apple Sign In** for seamless macOS native experience
- **Two-tier subscription** (Basic $4.99/mo, Pro $9.99/mo) with 7-day free trial
- **StoreKit 2** native integration for in-app purchases
- **Multi-user local cache** that preserves data when switching accounts
- **SQLAdmin** backend dashboard for user and subscription management

## Goals

1. Remove dependency on Clerk (reduce costs, increase control)
2. Implement secure JWT-based authentication
3. Integrate App Store subscriptions for monetization
4. Support Apple Sign In (App Store requirement)
5. Preserve local cache across user sessions
6. Provide admin tools for user and subscription management

## Non-Goals

- Third-party subscription management (RevenueCat)
- Free tier (all users require subscription after trial)
- Web-based payment (only App Store IAP)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     macOS Client (Swift)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ AuthService  │  │ StoreManager │  │ Login/Register   │  │
│  │              │  │ (StoreKit 2) │  │    Views         │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────┘  │
│         │                 │                                  │
│         │          ┌──────┴───────┐                         │
│         │          │ LocalDatabase│ (multi-user cache)      │
│         │          │   + GRDB     │                         │
│         │          └──────────────┘                         │
└─────────┼─────────────────┼──────────────────────────────────┘
          │                 │
          │ HTTPS           │ App Store Server API
          ↓                 ↓
┌─────────────────────────────────────────────────────────────┐
│                  Backend (FastAPI + PostgreSQL)              │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Authentication Module                   │   │
│  │  • POST /auth/register (Email + Password)           │   │
│  │  • POST /auth/login (access + refresh tokens)       │   │
│  │  • POST /auth/refresh                               │   │
│  │  • POST /auth/verify-email                          │   │
│  │  • POST /auth/reset-password                        │   │
│  │  • POST /auth/apple-signin                          │   │
│  │  • DELETE /auth/account (user deletion)             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Subscription Module                     │   │
│  │  • POST /subscription/verify-receipt                │   │
│  │  • POST /subscription/webhook (App Store)           │   │
│  │  • GET /subscription/status                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Admin Module (SQLAdmin)                 │   │
│  │  • /admin/ (Web UI)                                 │   │
│  │  • User management                                   │   │
│  │  • Subscription override                            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                    Database                          │   │
│  │  • users (id, email, apple_id, subscription_tier)   │   │
│  │  • refresh_tokens (token, user_id, expires_at)      │   │
│  │  • password_reset_tokens                            │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
          ↑
          │ HTTPS Webhooks
          │
┌─────────────────────────────────────────────────────────────┐
│              Apple Services                                  │
│  • Sign in with Apple (OAuth)                               │
│  • App Store Server API (Receipt Verification)              │
│  • App Store Server Notifications v2 (Subscription Events)  │
└─────────────────────────────────────────────────────────────┘
```

## Database Design

### New Tables (Backend PostgreSQL)

```sql
-- Users table (replaces Clerk user_id)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255),              -- bcrypt (NULL for Apple Sign In)
    apple_id VARCHAR(255) UNIQUE,            -- Apple Sign In sub claim

    -- Subscription
    subscription_tier VARCHAR(20) NOT NULL DEFAULT 'trial',
    trial_expires_at TIMESTAMP,              -- 7 days from registration
    subscription_expires_at TIMESTAMP,

    -- Apple receipt tracking
    apple_original_transaction_id VARCHAR(255),
    apple_receipt_data TEXT,

    -- Email verification
    email_verified BOOLEAN DEFAULT FALSE,
    email_verification_token VARCHAR(64),

    -- Audit
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_login_at TIMESTAMP,
    deleted_at TIMESTAMP,                    -- Soft delete (Apple requirement)

    CHECK (email IS NOT NULL OR apple_id IS NOT NULL)
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_apple_id ON users(apple_id);
CREATE UNIQUE INDEX idx_users_email_active ON users(email) WHERE deleted_at IS NULL;


-- Refresh tokens (long-lived, revocable)
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token VARCHAR(255) UNIQUE NOT NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL,           -- 30 days
    created_at TIMESTAMP DEFAULT NOW(),
    last_used_at TIMESTAMP,
    device_name VARCHAR(255),
    device_id VARCHAR(255)
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);


-- Password reset tokens (short-lived)
CREATE TABLE password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token VARCHAR(64) UNIQUE NOT NULL,
    expires_at TIMESTAMP NOT NULL,           -- 15 minutes
    created_at TIMESTAMP DEFAULT NOW(),
    used_at TIMESTAMP
);
```

### Existing Tables Migration

```sql
-- Migrate existing tables to use new user_id (UUID)
-- Since no production data, safe to truncate and alter

TRUNCATE TABLE content_tags, user_tags, paragraphs, podcasts, channels, content CASCADE;

ALTER TABLE content ALTER COLUMN user_id TYPE UUID USING user_id::uuid;
ALTER TABLE user_tags ALTER COLUMN user_id TYPE UUID USING user_id::uuid;
ALTER TABLE content_tags ALTER COLUMN user_id TYPE UUID USING user_id::uuid;

ALTER TABLE content
    ADD CONSTRAINT fk_content_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
```

### Local Database Updates (macOS GRDB)

```sql
-- v4: Add user support to local cache
ALTER TABLE contents ADD COLUMN user_id TEXT;
CREATE INDEX idx_contents_user_id ON contents(user_id);

-- Cache user info locally
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    email TEXT,
    subscription_tier TEXT NOT NULL,
    trial_expires_at DATETIME,
    subscription_expires_at DATETIME,
    cached_at DATETIME NOT NULL
);
```

## API Design

### Authentication Endpoints

#### POST /auth/register
```json
Request:
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}

Response 201:
{
  "message": "Registration successful. Please verify your email.",
  "user_id": "uuid",
  "trial_expires_at": "2026-03-09T12:00:00Z"
}
```

#### POST /auth/login
```json
Request:
{
  "email": "user@example.com",
  "password": "password123"
}

Response 200:
{
  "access_token": "eyJhbGc...",      // JWT, 15 min
  "refresh_token": "uuid-string",    // 30 days
  "expires_in": 900,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "subscription_tier": "trial",
    "subscription_expires_at": "2026-03-09T12:00:00Z"
  }
}
```

#### POST /auth/refresh
```json
Request:
{
  "refresh_token": "uuid-string"
}

Response 200:
{
  "access_token": "eyJhbGc...",
  "expires_in": 900
}
```

#### POST /auth/apple-signin
```json
Request:
{
  "identity_token": "eyJraWQ...",           // Apple JWT
  "authorization_code": "c123...",          // Optional, first login
  "user_info": {                            // Optional, first login
    "email": "user@privaterelay.appleid.com",
    "name": {"firstName": "John", "lastName": "Doe"}
  }
}

Response 200:
{
  "access_token": "eyJhbGc...",
  "refresh_token": "uuid-string",
  "expires_in": 900,
  "user": {...},
  "is_new_user": false
}
```

#### DELETE /auth/account
```json
Request:
Headers: Authorization: Bearer <access_token>
Body: {"confirmation": "DELETE"}

Response 200:
{"message": "Account deleted successfully"}
```

### Subscription Endpoints

#### POST /subscription/verify-receipt
```json
Request:
Headers: Authorization: Bearer <access_token>
Body:
{
  "transaction_id": "2000000123456789",
  "verification_data": "eyJhbGc...",  // JWS from StoreKit
  "product_id": "com.readless.pro.monthly"
}

Response 200:
{
  "subscription_tier": "pro",
  "expires_at": "2026-04-02T12:00:00Z",
  "is_trial": false,
  "product_id": "com.readless.pro.monthly"
}
```

#### GET /subscription/status
```json
Response 200:
{
  "current_tier": "pro",
  "is_trial": false,
  "trial_expires_at": null,
  "subscription_expires_at": "2026-04-02T12:00:00Z",
  "auto_renew_enabled": true
}
```

#### POST /subscription/webhook
App Store Server Notifications v2 handler (validates signedPayload).

## Security Considerations

### Password Security
- **Hashing**: bcrypt with cost factor 12
- **Minimum length**: 8 characters
- **Complexity**: Require uppercase, lowercase, digit
- **Storage**: Never store plaintext

### JWT Security
- **Access Token**: 15 minutes, HS256, stored in memory
- **Refresh Token**: 30 days, random UUID, stored in database (revocable)
- **Payload**: `{sub: user_id, email, subscription_tier, exp, jti}`
- **Secret Key**: 32+ character random string

### Apple Sign In Verification
```python
async def verify_apple_identity_token(token: str) -> dict:
    jwks_client = PyJWKClient("https://appleid.apple.com/auth/keys")
    signing_key = jwks_client.get_signing_key_from_jwt(token)

    payload = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience=settings.APPLE_BUNDLE_ID,
        issuer="https://appleid.apple.com"
    )

    return {
        "apple_id": payload["sub"],
        "email": payload.get("email")
    }
```

### StoreKit Receipt Verification
- Verify JWS signature using Apple's public keys
- Extract `originalTransactionId`, `productId`, `expiresDate`
- Update user subscription in database
- Handle App Store Server Notifications v2 for real-time updates

### Data Isolation
- All API endpoints use `get_current_user()` dependency
- User ID extracted from JWT (cannot be forged)
- Database queries always filter by `user_id`

### Admin Access Control
- Admin endpoints protected by `X-Admin-Token` header
- Token stored in environment variables
- Consider IP whitelist for production

## Multi-User Cache Design

### Problem
Current LocalDatabase is global (no user isolation). When switching users, we must preserve cache instead of clearing it.

### Solution
Add `user_id` column to all cached tables:

```swift
extension LocalDatabase {
    // Fetch contents for specific user
    public func fetchContents(userId: String) throws -> [Content] {
        try dbQueue.read { db in
            try Content.filter(Column("user_id") == userId)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    // Save content with user association
    public func saveContent(_ content: Content, userId: String) throws {
        var mutableContent = content
        mutableContent.userId = userId
        try dbQueue.write { db in
            try mutableContent.save(db)
        }
    }
}
```

### User Switching Flow
1. User logs out → `AuthService.signOut()`
2. Clear auth state (tokens, currentUser) but **NOT** local database
3. User logs in as different user
4. `ContentManager.loadContents()` filters by new `user_id`
5. Cache remains intact for all users

## Error Handling

### Backend
```python
class APIException(Exception):
    def __init__(self, status_code: int, message: str, detail: str = None):
        self.status_code = status_code
        self.message = message
        self.detail = detail

# Common errors
class AuthenticationError(APIException):
    def __init__(self, detail: str = None):
        super().__init__(401, "Authentication failed", detail)

class SubscriptionRequiredError(APIException):
    def __init__(self):
        super().__init__(402, "Active subscription required")
```

### macOS Client
```swift
enum AppError: LocalizedError {
    case authenticationFailed(String)
    case networkError(String)
    case subscriptionRequired
    case receiptVerificationFailed

    var errorDescription: String? {
        // User-friendly messages
    }
}
```

### Trial Expiration UX
Show `SubscriptionGateView` with pricing cards when:
- Trial expires and no active subscription
- User tries to use feature requiring subscription

## Testing Strategy

### Backend Tests
- **Unit tests**: Auth logic, JWT generation, receipt verification
- **Integration tests**: Full auth flow (register → login → purchase)
- **API tests**: All endpoints with various scenarios (success, errors, edge cases)

### macOS Tests
- **Unit tests**: AuthService, StoreManager logic
- **UI tests**: Login flow, subscription purchase flow
- **Keychain tests**: Token storage and retrieval

### Manual Testing Checklist
- [ ] Email registration + verification
- [ ] Password reset flow
- [ ] Apple Sign In (first time + returning user)
- [ ] Trial period countdown
- [ ] Purchase Basic/Pro subscription
- [ ] Receipt verification success/failure
- [ ] Switch users without losing cache
- [ ] Account deletion (soft delete)

## Implementation Phases

### Phase 1: Backend Auth Foundation (2 days)
- Database migrations (users, refresh_tokens)
- JWT utilities (generate, verify)
- Auth endpoints (register, login, refresh, logout)
- Password reset with Resend

### Phase 2: Apple Sign In (1 day)
- Apple identity token verification
- Backend `/auth/apple-signin` endpoint
- User creation/lookup by `apple_id`

### Phase 3: Subscription Backend (1 day)
- StoreKit receipt verification
- `/subscription/verify-receipt` endpoint
- App Store Server Notifications v2 webhook
- Subscription status logic

### Phase 4: macOS AuthService (1 day)
- Replace AuthManager with AuthService
- Keychain token storage
- Email login UI
- Apple Sign In UI

### Phase 5: macOS StoreManager (1 day)
- StoreKit 2 integration
- Product loading
- Purchase flow
- Receipt submission to backend

### Phase 6: Multi-User Cache (0.5 day)
- LocalDatabase migrations
- User-scoped queries
- ContentManager updates

### Phase 7: Admin Backend (0.5 day)
- SQLAdmin setup
- User/subscription management UI
- Admin token auth

### Phase 8: Testing & Polish (1 day)
- Write tests
- Error handling
- UI polish
- Trial expiration flow

**Total: 8 days**

## Dependencies

### Backend
- `python-jose[cryptography]` - JWT
- `bcrypt` - Password hashing
- `pyjwt` - Apple token verification
- `sqladmin` - Admin dashboard
- `resend` - Email service

### macOS
- Remove: `ClerkKit`, `ClerkKitUI`
- Native: `AuthenticationServices` (Apple Sign In)
- Native: `StoreKit` (IAP)
- Native: `Security` (Keychain)

## Rollout Plan

1. **Development**: Implement all phases on feature branch
2. **Staging**: Test with TestFlight + Sandbox purchases
3. **Migration**: Clear old Clerk data (no prod users yet)
4. **Production**: Deploy backend → macOS app
5. **Monitor**: Check logs for auth errors, failed purchases

## Success Metrics

- Auth success rate > 95%
- Token refresh success rate > 99%
- Purchase completion rate > 80%
- Trial-to-paid conversion rate (baseline)
- Zero cache loss incidents on user switch

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Apple Sign In verification fails | High | Implement retry logic, fallback to email |
| Receipt verification broken | Critical | Thorough testing with Sandbox, monitor webhooks |
| Token refresh fails | Medium | Long-lived refresh tokens (30 days), auto-retry |
| Cache corruption on user switch | Medium | Add user_id validation, backup/restore mechanism |
| Email delivery fails | Low | Use reliable service (Resend), show retry option |

## Open Questions

- ✅ Should we support password-less email login? → No, keep it simple
- ✅ Maximum number of devices per user? → Unlimited for now
- ✅ Refresh token rotation on use? → No, static tokens simpler
- ✅ Support for annual subscriptions? → Not in MVP, monthly only

## Appendix

### JWT Payload Example
```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "subscription_tier": "pro",
  "exp": 1709467200,
  "iat": 1709466300,
  "jti": "token-id-for-revocation"
}
```

### StoreKit Product IDs
- `com.readless.basic.monthly` - Basic $4.99/month
- `com.readless.pro.monthly` - Pro $9.99/month

### Resend Email Templates
- Welcome email (registration)
- Email verification link
- Password reset link
- Subscription confirmation
