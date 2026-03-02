# App Store Connect Setup Guide

Complete guide for configuring Readless subscription products in App Store Connect.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Product Overview](#product-overview)
3. [Create Subscription Group](#create-subscription-group)
4. [Create Products](#create-products)
5. [Configure Pricing & Trial](#configure-pricing--trial)
6. [Add Product Metadata](#add-product-metadata)
7. [Testing in Sandbox](#testing-in-sandbox)
8. [Backend Configuration](#backend-configuration)
9. [Production Checklist](#production-checklist)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

- **Apple Developer Program membership** ($99/year)
  - Enroll at [developer.apple.com/programs](https://developer.apple.com/programs/)
  - Wait 24-48 hours for enrollment approval

- **App Store Connect access**
  - Sign in at [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
  - Verify you have "Admin" or "App Manager" role

- **Bundle ID configured**
  - Bundle ID: `com.readless.app` (must match `Package.swift`)
  - Create at: Certificates, Identifiers & Profiles → Identifiers
  - Enable **In-App Purchase** capability

- **Paid Applications Agreement signed**
  - App Store Connect → Agreements, Tax, and Banking
  - Complete banking and tax information
  - Sign the Paid Applications Agreement

> **Note**: You cannot test or submit in-app purchases until the Paid Applications Agreement is fully executed.

---

## Product Overview

Readless offers two auto-renewable subscription tiers:

| Product | Product ID | Price | Trial | Features |
|---------|-----------|-------|-------|----------|
| **Basic Monthly** | `com.readless.basic.monthly` | $4.99/month | 7 days | Content ingestion, L0/L1 summaries, basic search |
| **Pro Monthly** | `com.readless.pro.monthly` | $9.99/month | 7 days | All Basic + L2/L3 summaries, AI podcasts, agentic search, priority support |

---

## Create Subscription Group

Subscription groups organize related subscription products and define upgrade/downgrade relationships.

### Steps

1. **Navigate to In-App Purchases**
   - App Store Connect → My Apps → [Select Readless] → In-App Purchases

2. **Create Subscription Group**
   - Click **"+"** button → **Subscription Group**
   - Screenshot: Subscription group creation screen

3. **Configure Group**
   - **Reference Name**: `Readless Subscriptions` (internal only)
   - **App Name**: Leave empty (uses app name)

4. **Save Group**
   - Click **Create**

> **Note**: You can only have one subscription group per app for related products. All tiers should be in the same group.

---

## Create Products

Create two subscription products within the subscription group.

### Product 1: Basic Monthly

1. **Start Product Creation**
   - In subscription group → Click **"+"** → **Add Subscription**

2. **Product ID**
   - **Product ID**: `com.readless.basic.monthly`
   - **Reference Name**: `Basic Monthly Subscription` (internal only)
   - Click **Create**

   > **Warning**: Product ID cannot be changed after creation. Double-check before clicking Create.

3. **Duration**
   - **Subscription Duration**: `1 month`

4. **Save**
   - Click **Save** at top right

### Product 2: Pro Monthly

Repeat the same steps with:
- **Product ID**: `com.readless.pro.monthly`
- **Reference Name**: `Pro Monthly Subscription`
- **Subscription Duration**: `1 month`

> **Note**: Products must be created before you can configure pricing and metadata.

---

## Configure Pricing & Trial

Set pricing tiers and free trial for both products.

### Basic Monthly Pricing

1. **Navigate to Product**
   - Select `com.readless.basic.monthly` from subscription group

2. **Add Pricing**
   - Scroll to **Subscription Prices** section
   - Click **"+"** to add pricing

3. **Select Price**
   - **Price**: Select **$4.99 USD (Tier 5)**
   - **Availability**: Choose countries/regions (select "All Territories" or specific regions)

4. **Free Trial**
   - Scroll to **Free Trial** section
   - Click **Set Up Offer** (if first time) or **"+"** to add offer
   - **Offer Type**: `Introductory Offer`
   - **Duration**: `1 week` (7 days)
   - **Price**: `Free`
   - **Eligibility**: `New Subscribers` (default)
   - Click **Save**

   > **Note**: StoreKit shows trial in product info automatically. No additional code needed.

5. **Save Pricing**
   - Click **Save** at top right

### Pro Monthly Pricing

Repeat for `com.readless.pro.monthly`:
- **Price**: $9.99 USD (Tier 10)
- **Free Trial**: 1 week (7 days), Free
- **Availability**: Same as Basic (all territories)

---

## Add Product Metadata

Add localized descriptions and metadata for each product.

### Basic Monthly Metadata

1. **Navigate to Product**
   - Select `com.readless.basic.monthly`

2. **Add Localization**
   - Scroll to **Subscription Localizations**
   - Click **"+"** to add localization

3. **Select Language**
   - Choose **English (U.S.)**
   - Click **Create**

4. **Fill in Details**

   **Subscription Display Name** (30 chars max):
   ```
   Basic Monthly
   ```

   **Description** (no char limit):
   ```
   Get started with Readless Basic:

   • Ingest articles, PDFs, and images
   • AI-powered L0 (one-liner) and L1 (outline) summaries
   • Basic full-text search across your library
   • Organize content with tags
   • Keyboard shortcuts for productivity

   7-day free trial. Cancel anytime.
   ```

5. **Save**
   - Click **Save**

6. **Add Additional Languages** (Optional)
   - Repeat for Chinese (Simplified) if targeting Chinese users:

   **Subscription Display Name**:
   ```
   基础月订阅
   ```

   **Description**:
   ```
   Readless 基础版功能:

   • 摄取文章、PDF 和图片
   • AI 驱动的 L0（一句话）和 L1（大纲）摘要
   • 全文搜索内容库
   • 标签管理内容
   • 键盘快捷键提升效率

   7 天免费试用，随时取消。
   ```

### Pro Monthly Metadata

Repeat for `com.readless.pro.monthly`:

**Subscription Display Name** (English):
```
Pro Monthly
```

**Description** (English):
```
Unlock the full power of Readless Pro:

• Everything in Basic, plus:
• L2 (detailed) and L3 (Q&A) summaries
• AI-generated podcasts with natural voices
• Agentic search with intelligent answers
• Priority support and faster processing

7-day free trial. Cancel anytime.
```

**Subscription Display Name** (Chinese):
```
专业月订阅
```

**Description** (Chinese):
```
解锁 Readless 专业版全部功能:

• 基础版所有功能，另加:
• L2（详细）和 L3（问答）摘要
• AI 生成的自然语音播客
• 智能搜索与答案生成
• 优先支持和更快处理速度

7 天免费试用，随时取消。
```

---

## Testing in Sandbox

Test the subscription flow before going live using Apple's Sandbox environment.

### Create Sandbox Test Accounts

1. **Navigate to Sandbox Testers**
   - App Store Connect → Users and Access → Sandbox Testers

2. **Add Tester**
   - Click **"+"**
   - Fill in details:
     - **Email**: Use a non-existent email (e.g., `test1@readless.test`)
     - **Password**: Create a strong password
     - **First Name**: `Test`
     - **Last Name**: `User 1`
     - **Country/Region**: `United States`
   - Click **Invite**

3. **Create Multiple Testers**
   - Create 2-3 test accounts for different scenarios
   - Use different emails: `test1@readless.test`, `test2@readless.test`, etc.

   > **Note**: These emails don't need to be real. Sandbox accounts are isolated from production.

### Configure macOS for Sandbox Testing

1. **Sign out of Production App Store**
   - macOS System Settings → Media & Purchases → Sign Out
   - Or: App Store app → Store menu → Sign Out

2. **Build and Run App**
   ```bash
   cd /Users/wangyixiao/WorkSpace/readless/macos
   swift build -c release
   swift run App
   ```

3. **Trigger Purchase Flow**
   - In Readless app → Settings/Subscription screen
   - Click "Subscribe to Basic" or "Subscribe to Pro"

4. **Sign In with Sandbox Account**
   - When prompted by StoreKit sheet, enter sandbox test account credentials
   - Example: `test1@readless.test` / `password`

   > **Warning**: Always sign in with sandbox account in the StoreKit purchase sheet, NOT in System Settings.

### Test Scenarios

#### Test 1: New Purchase with Trial

1. Sign in with `test1@readless.test`
2. Purchase **Basic Monthly**
3. **Expected**:
   - "7 days free, then $4.99/month" displayed
   - Purchase succeeds
   - Backend verifies receipt
   - User subscription tier updated to `basic`
4. **Verify**:
   - Check app shows "Basic" badge
   - Backend logs show receipt verification success
   - Check sandbox transaction in App Store Connect

#### Test 2: Restore Purchases

1. Sign out of app (clear auth token)
2. Sign back in with same Clerk account
3. Tap "Restore Purchases" button
4. **Expected**:
   - StoreKit restores subscription
   - Backend re-verifies receipt
   - User subscription tier restored to `basic`

#### Test 3: Upgrade Basic → Pro

1. Already subscribed to Basic Monthly
2. Purchase **Pro Monthly**
3. **Expected**:
   - StoreKit shows upgrade confirmation
   - Basic subscription cancelled
   - Pro subscription starts immediately
   - Backend verifies new receipt
   - User tier updated to `pro`

#### Test 4: Trial Expiry (Accelerated)

Sandbox subscriptions renew at accelerated rates:

| Real Duration | Sandbox Duration |
|---------------|------------------|
| 1 week trial  | 3 minutes |
| 1 month       | 5 minutes |

1. Purchase Basic Monthly with trial
2. Wait 3 minutes (trial expires in sandbox)
3. Wait 5 more minutes (first paid renewal)
4. **Expected**:
   - StoreKit auto-renews subscription
   - `StoreManager.transactionListener` receives update
   - Backend verifies renewal receipt
   - User subscription remains active

#### Test 5: Cancellation

1. Cancel subscription via System Settings:
   - System Settings → Your Name → Media & Purchases → Manage → Subscriptions
   - Select Readless subscription → Cancel Subscription

2. Wait for expiry (5 minutes in sandbox)
3. **Expected**:
   - Subscription expires after current period
   - StoreKit reports expiration
   - Backend marks subscription as expired
   - User tier downgraded to `free`

### Verify Backend Receipt Processing

Check backend logs during testing:

```bash
# If running local backend
tail -f backend/logs/app.log

# Or check Docker logs
docker compose logs -f api
```

**Expected log output**:
```
[INFO] Receipt verification started: transaction_id=2000000123456789
[INFO] StoreKit JWS decoded successfully
[INFO] Apple receipt validated: product_id=com.readless.basic.monthly
[INFO] Subscription updated: user_id=user_2abc123, tier=basic, expires_at=2026-03-09T12:34:56Z
[INFO] Receipt verification completed
```

---

## Backend Configuration

Ensure the backend is configured to verify App Store receipts.

### Environment Variables

In `backend/.env`:

```env
# Apple App Store
APPLE_BUNDLE_ID=com.readless.app
APPLE_SHARED_SECRET=your_shared_secret_here  # Optional: for receipt validation API v1

# Optional: Server-to-Server Notifications (webhook)
APPLE_SERVER_NOTIFICATION_ENDPOINT=/api/v1/webhooks/apple
```

### Get Shared Secret (Optional)

If using receipt validation API v1 (deprecated but still works):

1. App Store Connect → My Apps → Readless → App Information
2. Scroll to **App-Specific Shared Secret**
3. Click **Generate** (if not already generated)
4. Copy the shared secret
5. Add to backend `.env`: `APPLE_SHARED_SECRET=xxx`

> **Note**: StoreKit 2 uses JWS signatures and doesn't require shared secrets. The backend should verify the JWS directly.

### Verify Backend Endpoint

The backend should have a receipt verification endpoint:

```
POST /api/v1/subscriptions/verify-receipt
Authorization: Bearer <clerk-jwt>

{
  "transaction_id": "2000000123456789",
  "verification_data": "eyJhbGc...",  // JWS from StoreKit
  "product_id": "com.readless.basic.monthly"
}

Response:
{
  "subscription_tier": "basic",
  "expires_at": "2026-03-09T12:34:56Z"
}
```

Check `backend/app/routers/subscriptions.py` for implementation details.

### Test Backend Locally

```bash
cd /Users/wangyixiao/WorkSpace/readless/backend

# Run backend
uvicorn app.main:app --reload

# In another terminal, test health endpoint
curl http://localhost:8000/health

# Test receipt verification (with valid JWT and receipt)
curl -X POST http://localhost:8000/api/v1/subscriptions/verify-receipt \
  -H "Authorization: Bearer <clerk-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"transaction_id":"xxx","verification_data":"yyy","product_id":"com.readless.basic.monthly"}'
```

---

## Production Checklist

Before submitting to App Store with in-app purchases:

### 1. Products Reviewed

- [ ] Both products (`basic.monthly` and `pro.monthly`) created in subscription group
- [ ] Pricing configured ($4.99 and $9.99)
- [ ] 7-day free trial enabled for both products
- [ ] Product metadata added (English + Chinese if applicable)
- [ ] Screenshots provided (if required by App Store)

### 2. Backend Configured

- [ ] `APPLE_BUNDLE_ID=com.readless.app` in `.env`
- [ ] Receipt verification endpoint implemented and tested
- [ ] Database has `subscriptions` table with columns:
  - `user_id` (foreign key to users)
  - `subscription_tier` (enum: free, basic, pro)
  - `transaction_id` (Apple transaction ID)
  - `product_id` (Apple product ID)
  - `expires_at` (timestamp)
  - `is_trial` (boolean)
  - `is_active` (boolean)
- [ ] Backend deployed to production (`https://readless.cc`)

### 3. macOS App Configured

- [ ] `StoreManager.swift` references correct product IDs
- [ ] App uses production backend URL (`https://readless.cc`)
  ```bash
  defaults write com.readless.app apiBaseURL "https://readless.cc"
  ```
- [ ] Subscription UI implemented (Settings/Subscription screen)
- [ ] "Restore Purchases" button implemented
- [ ] App shows subscription status and tier badge

### 4. Sandbox Tested

- [ ] Purchase flow works (new subscription)
- [ ] Free trial flow works (7 days → paid)
- [ ] Restore purchases works
- [ ] Upgrade Basic → Pro works
- [ ] Backend verifies receipts successfully
- [ ] Subscription expiry handled correctly

### 5. TestFlight Testing

Before production release, test with TestFlight:

1. **Upload Build**
   ```bash
   # Archive app with Xcode
   # Or use xcodebuild
   ```

2. **Add TestFlight Testers**
   - App Store Connect → TestFlight → Testers
   - Add internal testers (your team)
   - Add external testers (beta users)

3. **Enable Sandbox Testing**
   - TestFlight uses Sandbox environment automatically
   - Testers can purchase with sandbox accounts

4. **Gather Feedback**
   - Ensure subscription flow works for external testers
   - Fix any issues before production launch

### 6. App Store Submission

- [ ] App binary uploaded to App Store Connect
- [ ] App metadata filled (name, description, screenshots, keywords)
- [ ] In-app purchases enabled in app version
- [ ] In-app purchases submitted for review WITH app
  - Go to: App Store Connect → My Apps → Readless → [Version] → In-App Purchases
  - Select both products and submit for review
- [ ] Privacy policy URL provided (required for subscriptions)
- [ ] Terms of Service URL provided (optional but recommended)

> **Important**: In-app purchases MUST be submitted with the first app version that uses them. They cannot be reviewed separately.

### 7. Post-Launch

- [ ] Monitor subscription metrics in App Store Connect:
  - Dashboard → Subscriptions → Performance
  - Track: new subscriptions, renewals, cancellations, trial conversions
- [ ] Set up App Store Server Notifications (webhook) for real-time updates:
  - App Store Connect → My Apps → Readless → App Information
  - Scroll to **App Store Server Notifications**
  - Enter webhook URL: `https://readless.cc/api/v1/webhooks/apple`
- [ ] Monitor backend logs for receipt verification errors
- [ ] Respond to customer support requests about subscriptions

---

## Troubleshooting

### Products Not Loading in App

**Symptom**: `StoreManager.loadProducts()` returns empty array.

**Possible Causes**:
1. **Product IDs don't match**
   - Verify: `StoreManager.swift` product IDs match App Store Connect exactly
   - Check: `com.readless.basic.monthly` (no typos)

2. **Products not approved**
   - Products must be submitted and approved with first app version
   - In sandbox: Products are available immediately without approval

3. **Bundle ID mismatch**
   - Verify: `Package.swift` bundle ID is `com.readless.app`
   - Verify: Products created under correct app in App Store Connect

4. **StoreKit not initialized**
   - Check: App has StoreKit entitlement
   - Check: App is code-signed correctly

**Solution**:
```bash
# Clean build
cd macos
rm -rf .build
swift build

# Check product IDs in code
grep -r "com.readless" Sources/App/Services/StoreManager.swift
```

### Purchase Fails with "Cannot Connect to App Store"

**Symptom**: StoreKit shows error when attempting purchase.

**Possible Causes**:
1. **Not signed in to sandbox account**
   - Solution: Sign out of production App Store, then sign in with sandbox account IN THE STOREKIT SHEET

2. **Network issue**
   - Solution: Check internet connection

3. **Sandbox environment unavailable**
   - Solution: Try again later (rare)

### Backend Receipt Verification Fails

**Symptom**: Purchase succeeds in StoreKit but backend returns error.

**Possible Causes**:
1. **Backend not configured**
   - Check: `APPLE_BUNDLE_ID` in `.env`
   - Check: Receipt verification endpoint exists

2. **JWS parsing error**
   - Check: Backend correctly decodes StoreKit JWS
   - Verify: Using correct Apple public keys

3. **Database error**
   - Check: `subscriptions` table exists
   - Check: Backend logs for SQL errors

**Solution**:
```bash
# Check backend logs
tail -f backend/logs/app.log

# Or if using Docker
docker compose logs -f api | grep "receipt"
```

### Subscription Not Restored

**Symptom**: "Restore Purchases" doesn't restore subscription.

**Possible Causes**:
1. **Signed in with different sandbox account**
   - Solution: Use same sandbox account as original purchase

2. **Subscription expired**
   - Sandbox subscriptions expire quickly (5 min = 1 month)
   - Solution: Purchase again

3. **Backend not updating user**
   - Check: Backend verifies restored receipt
   - Check: User subscription tier updated in database

### Trial Not Working

**Symptom**: User charged immediately instead of starting trial.

**Possible Causes**:
1. **Trial already used**
   - Each Apple ID can only use trial once per product
   - Solution: Use different sandbox account

2. **Trial not configured in App Store Connect**
   - Verify: Introductory offer created and set to "Free" for "1 week"

3. **App not reading trial info**
   - Check: `Product.subscription?.introductoryOffer` exists
   - Display trial info in UI before purchase

### Sandbox Subscriptions Not Renewing

**Symptom**: Subscription expires after trial, doesn't auto-renew.

**Possible Causes**:
1. **Renewal limit reached**
   - Sandbox subscriptions auto-renew max 6 times, then auto-cancel
   - Solution: Use different sandbox account

2. **"Cancel Subscription" tapped**
   - Check: System Settings → Subscriptions → verify not cancelled

---

## Additional Resources

- **Apple Documentation**:
  - [In-App Purchase Guide](https://developer.apple.com/in-app-purchase/)
  - [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit)
  - [Testing In-App Purchases](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases)

- **App Store Connect**:
  - [My Apps](https://appstoreconnect.apple.com/apps)
  - [Sandbox Testers](https://appstoreconnect.apple.com/access/testers)
  - [Subscriptions Dashboard](https://appstoreconnect.apple.com)

- **WWDC Videos**:
  - [Meet StoreKit 2 (WWDC 2021)](https://developer.apple.com/videos/play/wwdc2021/10114/)
  - [Manage In-App Purchases (WWDC 2022)](https://developer.apple.com/videos/play/wwdc2022/10039/)

---

## Summary

You've now configured:
1. Subscription group with two products
2. Pricing ($4.99 and $9.99) with 7-day trials
3. Product metadata in English and Chinese
4. Sandbox testing environment
5. Backend receipt verification

**Next Steps**:
1. Test thoroughly in sandbox
2. Submit app + in-app purchases for review
3. Launch and monitor subscription metrics

For questions or issues, refer to the Troubleshooting section or contact Apple Developer Support.
