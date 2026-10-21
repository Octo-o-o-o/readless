# Subscription Purchase Flow Testing Guide

Comprehensive manual testing documentation for Readless in-app purchase subscription flows.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Test Environment Setup](#test-environment-setup)
3. [Test Scenarios](#test-scenarios)
4. [Verification Checklist](#verification-checklist)
5. [Sandbox Behaviors](#sandbox-behaviors)
6. [Debugging Tips](#debugging-tips)
7. [Production Readiness](#production-readiness)

---

## Prerequisites

Before testing, ensure the following are complete:

### 1. App Store Connect Configuration

- [ ] Bundle ID `com.readless.app` registered with In-App Purchase capability
- [ ] Paid Applications Agreement signed
- [ ] Banking and tax information complete
- [ ] Subscription group "Readless Subscriptions" created
- [ ] Products created and configured:
  - `com.readless.basic.monthly` - $4.99/month, 7-day trial
  - `com.readless.pro.monthly` - $9.99/month, 7-day trial
- [ ] Product metadata added (English, optionally Chinese)

See [APP_STORE_SETUP.md](APP_STORE_SETUP.md) for detailed setup instructions.

### 2. Sandbox Test Accounts

Create 3-4 sandbox test accounts for different scenarios:

1. **App Store Connect → Users and Access → Sandbox Testers**
2. Create accounts:
   - `test1@readless.test` - For first-time purchases
   - `test2@readless.test` - For upgrade/downgrade testing
   - `test3@readless.test` - For restore purchases
   - `test4@readless.test` - For trial expiration testing

> **Note**: Use non-existent email addresses. These are isolated from production.

### 3. macOS App Built

```bash
cd /Users/wangyixiao/WorkSpace/readless/macos
swift build -c release
```

### 4. Backend Running

**Option A: Use Production (Recommended)**
```bash
# Configure app to use production backend
defaults write com.readless.app apiBaseURL "https://readless.cc"

# Verify
curl https://readless.cc/health
```

**Option B: Run Local Backend**
```bash
cd /Users/wangyixiao/WorkSpace/readless/backend
uvicorn app.main:app --reload

# Configure app to use localhost
defaults delete com.readless.app apiBaseURL
```

---

## Test Environment Setup

### 1. Sign Out of Production App Store

Before testing, sign out of production App Store to avoid conflicts:

1. **macOS System Settings → Media & Purchases → Sign Out**
2. Or: **App Store app → Store menu → Sign Out**

> **Critical**: Do NOT sign in to sandbox account in System Settings. Only sign in when prompted by StoreKit purchase sheet.

### 2. Launch Readless App

```bash
cd /Users/wangyixiao/WorkSpace/readless/macos
open Readless.xcodeproj
```

### 3. Authenticate with Readless account

- Sign in to Readless with your Readless account
- This is separate from App Store sandbox account
- Readless account authenticates with backend; sandbox account purchases products

---

## Test Scenarios

### A. First-Time Purchase: Basic Monthly

Test the complete purchase flow for a new user subscribing to Basic.

#### Test Steps

1. **Sign in to Readless** with your Readless account
2. **Navigate to Subscription/Settings screen**
3. **Verify UI shows**:
   - [ ] "Basic Monthly" product card with $4.99/month
   - [ ] "7 days free, then $4.99/month" trial info
   - [ ] "Subscribe" button enabled
   - [ ] No active subscription badge
4. **Click "Subscribe to Basic"**
5. **StoreKit purchase sheet appears**:
   - [ ] Product name: "Basic Monthly"
   - [ ] Price: "$4.99/month"
   - [ ] Trial: "7 days free"
   - [ ] "Subscribe" button
6. **Sign in with sandbox account**:
   - Email: `test1@readless.test`
   - Password: [your test password]
   - Sign in IN THE STOREKIT SHEET (not System Settings)
7. **Confirm purchase** by clicking "Subscribe"
8. **Wait for purchase to complete** (~5-10 seconds)

#### Expected Results

**UI State**:
- [ ] Loading spinner shown during purchase
- [ ] Success message or UI update after purchase
- [ ] "Basic" subscription badge displayed
- [ ] "Subscribe" button changes to "Manage Subscription"
- [ ] Trial expiration date shown (7 days from now)

**Backend Behavior**:
- [ ] StoreKit returns `.success(verificationResult)`
- [ ] `StoreManager.purchase()` extracts transaction ID
- [ ] `APIClient.verifyReceipt()` called with JWS receipt
- [ ] Backend receives `POST /api/v1/subscription/verify-receipt`
- [ ] Backend validates JWS with Apple
- [ ] User subscription record created/updated in database:
  - `subscription_tier` = `basic`
  - `product_id` = `com.readless.basic.monthly`
  - `transaction_id` = [transaction ID from StoreKit]
  - `expires_at` = [trial end date, ~7 days]
  - `is_trial` = `true`
  - `is_active` = `true`
- [ ] Backend returns `200 OK` with subscription data
- [ ] StoreKit transaction finished via `transaction.finish()`

**Verification**:
```bash
# Check backend logs (if running locally)
tail -f backend/logs/app.log | grep "verify-receipt"

# Or Docker logs
docker compose logs -f api | grep "verify-receipt"

# Expected log output:
# [INFO] Receipt verification started: transaction_id=2000000123456789
# [INFO] StoreKit JWS decoded successfully
# [INFO] Apple receipt validated: product_id=com.readless.basic.monthly
# [INFO] Subscription updated: user_id=user_abc123, tier=basic, expires_at=2026-03-09T12:34:56Z
# [INFO] Receipt verification completed
```

#### Transaction Verification

**StoreKit Console Output** (in Xcode Console or app logs):
```
[StoreManager] Starting purchase for: com.readless.basic.monthly
[StoreManager] ✅ Purchase successful, transaction ID: 2000000123456789
[StoreManager] Verifying receipt for transaction: 2000000123456789
[StoreManager] ✅ Receipt verified - tier: basic, expires: 2026-03-09 12:34:56 +0000
[StoreManager] ✅ Purchase completed and verified
[StoreManager] Updated purchased products: ["com.readless.basic.monthly"]
```

---

### B. First-Time Purchase: Pro Monthly

Same as Test A, but for Pro tier.

#### Test Steps

1. Use a **different sandbox account**: `test2@readless.test`
2. Navigate to Subscription screen
3. Click "Subscribe to Pro"
4. Sign in with sandbox account when prompted
5. Confirm purchase

#### Expected Results

- [ ] Pro subscription activated
- [ ] Backend updates `subscription_tier` to `pro`
- [ ] `product_id` = `com.readless.pro.monthly`
- [ ] UI shows "Pro" badge
- [ ] Trial period: 7 days
- [ ] Price: $9.99/month shown

---

### C. Upgrade Flow: Basic → Pro

Test upgrading from Basic Monthly to Pro Monthly.

#### Test Steps

1. **Pre-condition**: User already subscribed to Basic Monthly (from Test A)
2. Navigate to Subscription screen
3. **Verify current state**:
   - [ ] "Basic" badge shown
   - [ ] Basic subscription active
   - [ ] Pro product card shows "Upgrade to Pro"
4. **Click "Upgrade to Pro"**
5. **StoreKit upgrade sheet appears**:
   - [ ] Shows upgrade confirmation
   - [ ] Shows prorated pricing info (if applicable)
   - [ ] "Subscribe" button
6. **Confirm upgrade**
7. Wait for upgrade to complete

#### Expected Results

**Immediate Effects**:
- [ ] Basic subscription cancelled/replaced
- [ ] Pro subscription starts immediately (no waiting for next renewal)
- [ ] UI updates to show "Pro" badge
- [ ] Backend receives new receipt verification request
- [ ] Database updated:
  - Old Basic subscription marked inactive
  - New Pro subscription created with `is_active=true`
  - `subscription_tier` = `pro`
  - `product_id` = `com.readless.pro.monthly`
  - `expires_at` = [new expiration date]

**Prorated Refund**:
- [ ] StoreKit automatically calculates prorated refund for unused Basic time
- [ ] User charged difference: $9.99 - (prorated $4.99 refund)
- [ ] No manual refund handling needed (Apple handles this)

**Verification**:
```bash
# Check updated subscription in backend logs
# Should see:
# [INFO] Subscription updated: user_id=user_abc123, tier=pro, expires_at=...
```

---

### D. Downgrade Flow: Pro → Basic

Test downgrading from Pro Monthly to Basic Monthly.

#### Test Steps

1. **Pre-condition**: User subscribed to Pro Monthly
2. Navigate to Subscription screen
3. Click "Downgrade to Basic"
4. **StoreKit downgrade sheet appears**:
   - [ ] Shows downgrade will take effect at next renewal
   - [ ] Pro access continues until current period ends
   - [ ] "Subscribe" button
5. Confirm downgrade

#### Expected Results

**Immediate Effects**:
- [ ] Pro subscription remains active until expiration
- [ ] UI shows "Pro (expires [date], switching to Basic)"
- [ ] Basic subscription scheduled to start after Pro expires
- [ ] Backend records pending downgrade

**At Renewal Time** (5 minutes in sandbox):
- [ ] Pro subscription expires
- [ ] Basic subscription activates
- [ ] UI updates to show "Basic" badge
- [ ] Backend updates `subscription_tier` to `basic`
- [ ] User charged $4.99 for Basic renewal

**Verification**:
- [ ] Check subscription auto-renewal status in System Settings
- [ ] Wait for renewal time (5 minutes in sandbox)
- [ ] Verify UI and backend update correctly

---

### E. Restore Purchases

Test restoring a previous subscription after reinstalling the app.

#### Test Steps

1. **Pre-condition**: User has active Basic subscription
2. **Simulate reinstall**:
   - Quit Readless app
   - Clear UserDefaults (simulates reinstall):
     ```bash
     defaults delete com.readless.app
     ```
   - Relaunch app
3. **Sign in to Readless** with the same Readless account
4. **Verify initial state**:
   - [ ] No subscription badge shown (app doesn't know about purchase yet)
   - [ ] "Subscribe" buttons enabled
5. **Navigate to Subscription screen**
6. **Click "Restore Purchases"**
7. **StoreKit prompts for App Store credentials**:
   - Sign in with same sandbox account used for original purchase
8. Wait for restore to complete

#### Expected Results

**Restore Process**:
- [ ] `StoreManager.restorePurchases()` iterates `Transaction.currentEntitlements`
- [ ] Finds active Basic subscription transaction
- [ ] Re-verifies receipt with backend
- [ ] Backend updates user subscription (or confirms existing)
- [ ] UI updates to show "Basic" badge

**UI State**:
- [ ] Loading indicator during restore
- [ ] Success message: "Subscription restored"
- [ ] "Basic" badge appears
- [ ] Subscription details shown (expiration, trial status)

**Backend Behavior**:
- [ ] Receives `POST /api/v1/subscription/verify-receipt` for restored transaction
- [ ] Validates transaction is still active
- [ ] Updates user subscription record (or confirms no changes needed)
- [ ] Returns subscription data

**Verification**:
```bash
# Check logs for restore operation
# Expected:
# [StoreManager] Restoring purchases...
# [StoreManager] Found transaction: 2000000123456789 for product: com.readless.basic.monthly
# [StoreManager] Verifying receipt for transaction: 2000000123456789
# [StoreManager] ✅ Receipt verified - tier: basic, expires: ...
# [StoreManager] ✅ Restore completed - found active subscriptions
```

---

### F. Trial Period Testing (New User)

Test the 7-day free trial flow for a new user.

#### Test Steps

1. Use a **brand new sandbox account**: `test4@readless.test`
   - Must never have purchased this product before
2. Navigate to Subscription screen
3. **Verify trial eligibility**:
   - [ ] "7 days free" displayed on product card
   - [ ] StoreKit shows trial in purchase sheet
4. Purchase Basic Monthly
5. **Verify trial started**:
   - [ ] UI shows "Trial: ends in 7 days"
   - [ ] `is_trial` = `true` in backend
   - [ ] No charge yet (trial is free)
6. **Wait 3 minutes** (trial expires in sandbox: 1 week = 3 minutes)

#### Expected Results

**During Trial**:
- [ ] Full Basic features available
- [ ] UI shows trial status and expiration
- [ ] Backend `is_trial` = `true`
- [ ] No payment charged

**After 3 Minutes (Trial Expires in Sandbox)**:
- [ ] Trial converts to paid subscription automatically
- [ ] StoreKit charges $4.99 for first month
- [ ] Transaction listener receives renewal event
- [ ] Backend updates:
  - `is_trial` = `false`
  - `expires_at` = [1 month from now]
- [ ] UI updates: "Trial: ends in 7 days" → "Renews on [date]"

**Verification**:
```bash
# Watch transaction listener logs
# After 3 minutes, should see:
# [StoreManager] 🔔 Transaction update: 2000000123456790 for product: com.readless.basic.monthly
# [StoreManager] Verifying receipt for transaction: 2000000123456790
# [StoreManager] ✅ Receipt verified - tier: basic, expires: ...
# [StoreManager] ✅ Transaction update processed
```

---

### G. Trial Expiration (User Cancels Before Trial Ends)

Test what happens when user cancels during trial period.

#### Test Steps

1. **Pre-condition**: User has active trial (from Test F)
2. **Cancel subscription via System Settings**:
   - System Settings → [Your Name] → Media & Purchases → Manage → Subscriptions
   - Select "Readless - Basic Monthly"
   - Click "Cancel Subscription"
   - Confirm cancellation
3. **Return to Readless app**
4. Wait for trial to expire (3 minutes in sandbox)

#### Expected Results

**During Trial (After Cancellation)**:
- [ ] Trial continues until expiration
- [ ] Full Basic features still available
- [ ] UI shows "Trial expires [date], will not renew"
- [ ] No auto-renewal scheduled

**After Trial Expires**:
- [ ] Subscription expires (no charge)
- [ ] UI updates to "Free" tier
- [ ] Backend updates:
  - `is_active` = `false`
  - `subscription_tier` = `free`
- [ ] User prompted to subscribe again

**Verification**:
- [ ] No charge on sandbox account
- [ ] Subscription status in System Settings shows "Expired"

---

### H. Purchase After Trial Expires

Test re-subscribing after a trial has expired.

#### Test Steps

1. **Pre-condition**: User's trial expired (from Test G)
2. Navigate to Subscription screen
3. **Verify trial is no longer available**:
   - [ ] "7 days free" NOT shown (trial already used)
   - [ ] Shows "$4.99/month" immediately
4. Click "Subscribe to Basic"
5. Confirm purchase

#### Expected Results

- [ ] No trial offered (each Apple ID gets one trial per product)
- [ ] Charged $4.99 immediately
- [ ] Subscription starts immediately
- [ ] Backend records:
  - `is_trial` = `false`
  - `subscription_tier` = `basic`
  - `expires_at` = [1 month from now]

---

### I. Purchase Errors

Test error handling for various failure scenarios.

#### Test 1: Insufficient Funds

1. Configure sandbox account with no payment method
2. Attempt to purchase Basic Monthly
3. **Expected**:
   - [ ] StoreKit shows "Cannot Connect to iTunes Store" or payment error
   - [ ] `StoreManager` returns `.purchaseFailed` error
   - [ ] UI shows user-friendly error: "Purchase failed. Please check your payment method."
   - [ ] App remains functional (no crash)
   - [ ] User can retry

#### Test 2: Invalid Payment Method

1. Use sandbox account with expired/invalid payment info
2. Attempt purchase
3. **Expected**:
   - [ ] StoreKit shows payment validation error
   - [ ] Error propagated to UI
   - [ ] User prompted to update payment method
   - [ ] No partial subscription created

#### Test 3: Backend Offline

1. Stop backend server:
   ```bash
   # If running locally
   # Kill uvicorn process

   # If using Docker
   docker compose down
   ```
2. Attempt purchase
3. **Expected**:
   - [ ] StoreKit purchase succeeds
   - [ ] Receipt verification fails (network error)
   - [ ] `StoreManager` shows error: "Receipt verification failed"
   - [ ] UI shows: "Purchase completed, but verification failed. Try 'Restore Purchases'."
   - [ ] Transaction NOT finished (will retry later)
   - [ ] User can restore after backend is back online

#### Test 4: Receipt Verification Failure

1. Backend running but returns error (e.g., invalid JWS)
2. Attempt purchase
3. **Expected**:
   - [ ] StoreKit purchase succeeds
   - [ ] Backend returns 400/500 error
   - [ ] Error logged in app console
   - [ ] UI shows error message
   - [ ] Transaction NOT finished (will retry)

**Recovery**:
- [ ] Fix backend issue
- [ ] Click "Restore Purchases"
- [ ] Receipt re-verified successfully
- [ ] Subscription activated

---

### J. Network Failure Scenarios

Test resilience to network issues.

#### Test 1: Purchase with No Internet

1. Disconnect from network (turn off Wi-Fi)
2. Attempt purchase
3. **Expected**:
   - [ ] StoreKit shows "Cannot Connect to App Store"
   - [ ] Purchase fails before reaching backend
   - [ ] User shown network error
   - [ ] No partial transaction created

#### Test 2: Network Drops During Receipt Verification

1. Start purchase
2. Disconnect network right after StoreKit purchase succeeds
3. **Expected**:
   - [ ] Receipt verification fails (timeout/network error)
   - [ ] Transaction listener will retry when network restored
   - [ ] User can manually retry via "Restore Purchases"

#### Test 3: Network Restored

1. Reconnect network
2. Click "Restore Purchases"
3. **Expected**:
   - [ ] Receipt re-verified successfully
   - [ ] Subscription activated
   - [ ] Transaction finished

---

### K. Multiple Devices

Test subscription syncing across multiple devices.

#### Test Steps

**Device A** (Initial Purchase):
1. Mac A: Sign in with `test1@readless.test` (Readless account)
2. Purchase Basic Monthly
3. Verify subscription active

**Device B** (Sync Subscription):
1. Mac B: Sign in with the same Readless account
2. Navigate to Subscription screen
3. **Verify initial state**:
   - [ ] No subscription shown (haven't synced yet)
4. Click "Restore Purchases"
5. Sign in with same sandbox account: `test1@readless.test`

#### Expected Results

- [ ] Device B restores subscription successfully
- [ ] Same subscription data loaded (tier, expiration)
- [ ] Both devices show "Basic" badge
- [ ] Backend recognizes the same user account
- [ ] Only ONE active subscription (not duplicate)

**Verification**:
- [ ] Check backend database: only one subscription record per user
- [ ] Both devices functional with Basic features

---

### L. Auto-Renewal Testing

Test automatic subscription renewal in sandbox.

#### Sandbox Renewal Rates

Sandbox subscriptions renew at accelerated rates:

| Real Duration | Sandbox Duration |
|---------------|------------------|
| 1 week trial  | 3 minutes |
| 1 month       | 5 minutes |
| 1 year        | 1 hour |

#### Test Steps

1. **Purchase Basic Monthly** with new sandbox account
2. **Wait 3 minutes** (trial expires → first paid renewal)
3. **Observe transaction listener**
4. **Wait another 5 minutes** (second renewal)
5. Repeat up to 6 times (sandbox limit)

#### Expected Results

**After Each Renewal**:
- [ ] Transaction listener receives renewal event
- [ ] `StoreManager` prints: "🔔 Transaction update: [transaction_id]"
- [ ] Receipt auto-verified with backend
- [ ] Backend updates `expires_at` to next period
- [ ] Transaction finished automatically
- [ ] UI updates expiration date
- [ ] User charged $4.99 (in sandbox, no real charge)

**After 6 Renewals**:
- [ ] Sandbox auto-cancels subscription (limit reached)
- [ ] Subscription expires
- [ ] User tier downgraded to `free`

**Verification**:
```bash
# Watch logs continuously
tail -f backend/logs/app.log

# Expected every 5 minutes:
# [INFO] Receipt verification started: transaction_id=2000000123456XXX
# [INFO] Subscription updated: user_id=user_abc123, tier=basic, expires_at=[new date]
```

---

## Verification Checklist

For each test scenario, verify the following:

### Client-Side (macOS App)

- [ ] **Loading States**: Spinner/indicator shown during purchase/restore
- [ ] **Success States**: UI updates immediately after successful operation
- [ ] **Error Messages**: Clear, user-friendly error messages displayed
- [ ] **Subscription Badge**: Correct tier badge ("Free"/"Basic"/"Pro") shown
- [ ] **Trial Status**: Trial expiration displayed during trial period
- [ ] **Renewal Date**: Next renewal date shown for active subscriptions
- [ ] **Button States**: "Subscribe" / "Manage" / "Restore" buttons correct
- [ ] **No Crashes**: App remains stable during all operations

### Backend

- [ ] **Receipt Received**: `POST /api/v1/subscription/verify-receipt` called
- [ ] **JWS Valid**: StoreKit JWS decoded and validated successfully
- [ ] **Apple Verified**: Receipt validated with Apple (JWS signature)
- [ ] **Database Updated**: User subscription record created/updated:
  - `user_id` matches the same Readless user
  - `subscription_tier` correct (`free`/`basic`/`pro`)
  - `product_id` correct (`com.readless.basic.monthly` or `.pro.monthly`)
  - `transaction_id` from StoreKit
  - `expires_at` correct timestamp
  - `is_trial` correct boolean
  - `is_active` correct boolean
- [ ] **Response Sent**: Backend returns 200 OK with subscription data
- [ ] **Logs Clean**: No errors in backend logs (400/500 responses)

### StoreKit Transaction

- [ ] **Purchase Succeeds**: StoreKit returns `.success(verificationResult)`
- [ ] **Transaction Valid**: `VerificationResult` is `.verified` (not `.unverified`)
- [ ] **Transaction Finished**: `transaction.finish()` called after verification
- [ ] **Entitlements Updated**: `Transaction.currentEntitlements` includes new purchase
- [ ] **Receipt Available**: JWS representation available from verification result

### System Settings

- [ ] **Subscription Listed**: Readless subscription appears in System Settings
- [ ] **Correct Tier**: Shows correct product (Basic/Pro)
- [ ] **Renewal Status**: Shows auto-renew status (on/off)
- [ ] **Next Billing**: Shows next billing date
- [ ] **Cancellable**: User can cancel subscription from Settings

---

## Sandbox Behaviors

Sandbox environment behaves differently from production. Be aware of these differences during testing.

### 1. Accelerated Subscription Durations

| Real Duration | Sandbox Duration | Use Case |
|---------------|------------------|----------|
| 3 days        | 2 minutes        | Promo offers |
| 1 week        | 3 minutes        | Trial periods |
| 1 month       | 5 minutes        | Monthly subscriptions |
| 2 months      | 10 minutes       | Bi-monthly subscriptions |
| 3 months      | 15 minutes       | Quarterly subscriptions |
| 6 months      | 30 minutes       | Semi-annual subscriptions |
| 1 year        | 1 hour           | Annual subscriptions |

**Test Strategy**:
- Wait 3 minutes to test trial → paid conversion
- Wait 5 minutes to test monthly renewal
- Use multiple sandbox accounts for long-term testing

### 2. Renewal Limits

- **Sandbox subscriptions auto-renew maximum 6 times**
- After 6 renewals, subscription auto-expires
- To continue testing, use a different sandbox account
- **Production**: Subscriptions renew indefinitely until cancelled

### 3. Refunds and Cancellations

- **Sandbox**: Refunds process instantly
- **Sandbox**: Cancellations take effect immediately (not at period end)
- **Production**: Refunds take 1-3 days
- **Production**: Cancellations take effect at end of billing period

### 4. Trial Eligibility

- **Each sandbox account can only use trial once per product**
- To test trial again, use a different sandbox account
- **Production**: Same (one trial per Apple ID per product)

### 5. Payment Validation

- **Sandbox**: All purchases succeed (no real payment)
- **Sandbox**: Payment method errors are simulated (not real)
- **Production**: Real payment processing, real errors

### 6. Receipt Validation

- **Sandbox**: Use Apple sandbox verification servers:
  - Environment: `Sandbox`
  - JWS header: `"x5c"` field contains sandbox certificates
- **Production**: Use production verification servers
- **Backend must detect environment and use correct validation**

### 7. Server Notifications

- **Sandbox**: Webhooks sent to test endpoint
- **Sandbox**: Notification delays may vary (faster than production)
- **Production**: Real-time webhook delivery (1-2 minutes delay)

---

## Debugging Tips

Use these techniques to diagnose issues during testing.

### 1. View StoreKit Transaction Logs

**macOS Console App**:
1. Open Console.app (Applications → Utilities → Console)
2. Select your Mac in sidebar
3. Search for: `StoreManager`
4. Filter by: `Readless` or `com.readless.app`

**Expected Logs**:
```
[StoreManager] Loading products...
[StoreManager] ✅ Loaded 2 products
[StoreManager] Product: com.readless.basic.monthly - Basic Monthly - $4.99
[StoreManager] Starting purchase for: com.readless.basic.monthly
[StoreManager] ✅ Purchase successful, transaction ID: 2000000123456789
[StoreManager] Verifying receipt for transaction: 2000000123456789
[StoreManager] ✅ Receipt verified - tier: basic, expires: 2026-03-09 12:34:56 +0000
[StoreManager] ✅ Purchase completed and verified
```

### 2. Verify Backend Receipt Verification

**Check Backend Logs**:
```bash
# Local backend
tail -f backend/logs/app.log | grep "verify-receipt"

# Docker backend
docker compose logs -f api | grep "verify-receipt"

# Production backend (SSH to server)
ssh -p 52941 root@172.245.55.158
cd /root/backend
docker compose -f docker-compose.prod.yml logs --tail=100 api | grep "verify-receipt"
```

**Expected Log Pattern**:
```
[INFO] Receipt verification started: transaction_id=2000000123456789
[INFO] StoreKit JWS decoded successfully
[INFO] Apple receipt validated: product_id=com.readless.basic.monthly, environment=Sandbox
[INFO] Subscription updated: user_id=user_abc123, tier=basic, expires_at=2026-03-09T12:34:56Z
[INFO] Receipt verification completed successfully
```

### 3. Check Backend Webhook Delivery

**View App Store Server Notifications Logs**:
```bash
# Local backend
tail -f backend/logs/app.log | grep "webhook"

# Expected (if webhook configured):
# [INFO] App Store webhook received: event_type=SUBSCRIBED
# [INFO] Processing webhook for user: user_abc123
# [INFO] Webhook processed successfully
```

**Manually Test Webhook** (not available in sandbox, production only):
1. App Store Connect → My Apps → Readless → App Information
2. Scroll to **App Store Server Notifications**
3. Click "Test Notification" → Select notification type
4. Verify backend receives and processes webhook

### 4. Inspect Database State

**Check User Subscription Record**:
```bash
# SSH to production backend
ssh -p 52941 root@172.245.55.158

# Access PostgreSQL
docker compose -f docker-compose.prod.yml exec db psql -U readless readless

# Query subscriptions
SELECT user_id, subscription_tier, product_id, expires_at, is_trial, is_active
FROM subscriptions
WHERE user_id = 'user_abc123';

# Expected result:
#  user_id     | subscription_tier |          product_id           |     expires_at      | is_trial | is_active
# -------------+-------------------+-------------------------------+---------------------+----------+-----------
#  user_abc123 | basic             | com.readless.basic.monthly    | 2026-03-09 12:34:56 | true     | true
```

### 5. Debug Purchase Failures

**Issue: Products Not Loading**

```bash
# Check product IDs match
grep -r "com.readless" /Users/wangyixiao/WorkSpace/readless/macos/Sources/App/Services/StoreManager.swift

# Expected output:
#     "com.readless.basic.monthly",
#     "com.readless.pro.monthly"

# Verify bundle ID
grep -r "com.readless.app" /Users/wangyixiao/WorkSpace/readless/macos/Package.swift
```

**Issue: Purchase Fails with "Cannot Connect to App Store"**

1. Verify signed out of production App Store
2. Try signing in to sandbox account in StoreKit sheet (not System Settings)
3. Check internet connection
4. Restart app and try again

**Issue: Backend Receipt Verification Fails**

1. Check backend is running:
   ```bash
   curl https://readless.cc/health
   # or
   curl http://localhost:8000/health
   ```
2. Verify app is configured correctly:
   ```bash
   defaults read com.readless.app apiBaseURL
   # Should return: https://readless.cc
   ```
3. Check backend logs for specific error
4. Verify backend environment variables (`APPLE_BUNDLE_ID`, etc.)

### 6. Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| "Product not found" | Product ID mismatch or not configured | Verify product IDs in App Store Connect match code |
| "User not authenticated" | Readless authentication failed | Sign in to Readless with your Readless account |
| "Purchase cancelled" | User tapped "Cancel" in StoreKit sheet | Normal user action, no fix needed |
| "Receipt verification failed" | Backend unreachable or returned error | Check backend status, use "Restore Purchases" |
| "Cannot Connect to App Store" | Not signed in to sandbox account | Sign in with sandbox account in purchase sheet |
| "Invalid transaction" | JWS verification failed | Check backend validation logic, ensure using correct Apple public keys |

---

## Production Readiness

Before launching subscriptions to production, complete this checklist.

### 1. Sandbox Testing Complete

- [ ] **All test scenarios passed** (A through L)
- [ ] **Purchase flow works** (Basic and Pro)
- [ ] **Trial flow works** (7-day trial → paid conversion)
- [ ] **Restore purchases works** (multiple devices)
- [ ] **Upgrade/downgrade works** (Basic ↔ Pro)
- [ ] **Auto-renewal tested** (at least 3 renewals observed)
- [ ] **Error handling works** (network failures, payment errors)
- [ ] **UI states correct** (loading, success, error, trial, active)
- [ ] **Backend verification works** (all receipts verified successfully)
- [ ] **Transaction listener works** (renewal events processed)

### 2. App Store Connect Configuration

- [ ] **Products approved**:
  - `com.readless.basic.monthly` - Ready for Sale
  - `com.readless.pro.monthly` - Ready for Sale
- [ ] **Pricing configured** ($4.99 and $9.99)
- [ ] **Trial configured** (7-day free trial)
- [ ] **Metadata complete** (English + Chinese)
- [ ] **Screenshots uploaded** (if required)
- [ ] **In-app purchases submitted with app** (not separately)

### 3. Backend Production Configuration

- [ ] **Environment variables set** in production `.env`:
  ```env
  APPLE_BUNDLE_ID=com.readless.app
  DATABASE_URL=postgresql+asyncpg://...  (production DB)
  ```
- [ ] **Receipt verification endpoint deployed**:
  ```bash
  curl https://readless.cc/api/v1/subscription/verify-receipt -v
  # Should return: 405 Method Not Allowed (expected without body)
  ```
- [ ] **Database migration run**:
  ```sql
  -- Verify subscriptions table exists
  SELECT table_name FROM information_schema.tables
  WHERE table_name = 'subscriptions';
  ```
- [ ] **Backend production tested**:
  - Health check: `curl https://readless.cc/health`
  - API docs: `curl https://readless.cc/docs`
- [ ] **Logging configured** (production logs to file/service)
- [ ] **Error monitoring** (Sentry or similar)

### 4. macOS App Production Configuration

- [ ] **Product IDs correct** in `StoreManager.swift`:
  ```swift
  private static let productIDs = [
      "com.readless.basic.monthly",
      "com.readless.pro.monthly"
  ]
  ```
- [ ] **Backend URL configured** for production:
  ```bash
  defaults write com.readless.app apiBaseURL "https://readless.cc"
  ```
- [ ] **Bundle ID matches** (`com.readless.app` in all configs)
- [ ] **Code signing configured** (Development or Distribution certificate)
- [ ] **Entitlements correct** (In-App Purchase capability enabled)
- [ ] **Build configuration** (Release build for submission)

### 5. TestFlight Beta Testing

Before production release, test with real users via TestFlight:

1. **Upload Build to App Store Connect**:
   ```bash
   # Archive app with Xcode
   # Product → Archive
   # Distribute App → App Store Connect
   ```
2. **Add TestFlight Testers**:
   - Internal testers (your team)
   - External testers (beta users, 10-100 people)
3. **TestFlight Test Scenarios**:
   - [ ] Purchase flow works (TestFlight uses sandbox)
   - [ ] Trial works
   - [ ] Restore purchases works
   - [ ] Features unlock correctly (Basic/Pro)
   - [ ] UI is clear and user-friendly
4. **Gather Feedback**:
   - [ ] No crashes reported
   - [ ] Purchase flow intuitive
   - [ ] Pricing clear
   - [ ] Trial terms understood
5. **Fix Issues** before production launch

### 6. App Store Submission

- [ ] **App binary uploaded** to App Store Connect
- [ ] **App metadata complete**:
  - Name: Readless
  - Subtitle: AI-Powered Content Summarization
  - Description: [Full app description]
  - Keywords: summary, AI, productivity, reading, PDF
  - Screenshots: [macOS screenshots showing features]
  - App Icon: [1024x1024 icon]
- [ ] **In-app purchases enabled** in app version settings
- [ ] **In-app purchases submitted WITH app** (not separately):
  1. App Store Connect → My Apps → Readless → [Version]
  2. In-App Purchases section → Add both products
  3. Submit entire version for review
- [ ] **Privacy policy URL** provided (REQUIRED for subscriptions):
  - Example: `https://readless.cc/privacy`
- [ ] **Terms of Service URL** (optional but recommended):
  - Example: `https://readless.cc/terms`
- [ ] **Age rating** appropriate (likely 4+)
- [ ] **Export compliance** answered (encryption usage)

> **Critical**: In-app purchases MUST be submitted with the first app version that includes them. They cannot be reviewed separately.

### 7. App Store Server Notifications (Webhook)

Configure webhook for real-time subscription events:

1. **App Store Connect → My Apps → Readless → App Information**
2. Scroll to **App Store Server Notifications**
3. **Production Server URL (Version 2)**:
   ```
   https://readless.cc/api/v1/subscription/webhook
   ```
4. **Sandbox Server URL** (optional, for testing):
   ```
   https://readless.cc/api/v1/subscription/webhook-sandbox
   ```
5. **Verify webhook endpoint** returns 200 OK:
   ```bash
   curl -X POST https://readless.cc/api/v1/subscription/webhook \
     -H "Content-Type: application/json" \
     -d '{"signedPayload":"test"}'
   # Should return: 200 OK (even if payload invalid, endpoint should exist)
   ```
6. **Test notification** (after webhook configured):
   - App Store Connect → Test Notification
   - Select notification type (e.g., "SUBSCRIBED")
   - Verify backend receives and logs webhook

### 8. Post-Launch Monitoring

After app is live, monitor these metrics:

**App Store Connect Metrics**:
- [ ] **Subscriptions Dashboard**:
  - New subscriptions
  - Renewal rate
  - Cancellation rate
  - Trial conversion rate
- [ ] **Proceed to Review** regularly

**Backend Monitoring**:
- [ ] **Receipt verification success rate** (target: >99%)
- [ ] **API error rate** (`/api/v1/subscription/*` endpoints)
- [ ] **Webhook delivery** (App Store Server Notifications)
- [ ] **Database subscription records** (consistency with StoreKit)

**User Support**:
- [ ] **Monitor support requests** about subscriptions
- [ ] **Common issues**:
  - Cannot restore purchases → Guide to "Restore Purchases" button
  - Charged but no access → Backend verification issue, escalate
  - Cancel subscription → Direct to System Settings
- [ ] **Response time**: <24 hours for subscription issues

**Financial**:
- [ ] **Revenue tracking** (App Store Connect → Sales and Trends)
- [ ] **Refund requests** (App Store Connect → Ratings and Reviews)
- [ ] **Payout schedule** (App Store pays monthly, 45 days after month end)

### 9. Legal & Compliance

- [ ] **Privacy policy** includes subscription data handling
- [ ] **Terms of service** includes subscription terms:
  - Auto-renewal terms
  - Cancellation policy
  - Refund policy (defer to Apple's policy)
  - Trial terms (7 days, auto-converts to paid)
- [ ] **App Store Guidelines compliance**:
  - 3.1.1 In-App Purchase (use StoreKit, not external payment)
  - 3.1.2 Subscriptions (clear pricing, cancellation terms)
- [ ] **GDPR compliance** (if serving EU users):
  - User can delete account and subscription data
  - Privacy policy includes data retention policy

### 10. Production Deployment Verification

**Final checks before marking ready for sale**:

1. **Test on fresh Mac** (not development machine):
   ```bash
   # Download app from App Store
   # Sign in with a new Readless account
   # Purchase subscription
   # Verify all features work
   ```
2. **Production purchase** (use real Apple ID, small test):
   - Purchase Basic Monthly (real charge)
   - Verify backend verification works
   - Test restore purchases
   - Cancel subscription (refund if needed)
3. **Monitor logs** during first 24 hours:
   ```bash
   ssh -p 52941 root@172.245.55.158
   docker compose -f docker-compose.prod.yml logs -f api | grep subscription
   ```
4. **Check metrics** after 1 week:
   - Conversion rate (free → paid)
   - Trial conversion rate
   - Renewal rate (after first month)

---

## Summary

This guide covered comprehensive testing for Readless subscription flows:

- **12 test scenarios** (A-L) covering all purchase paths
- **Verification checklist** for client, backend, and StoreKit
- **Sandbox behaviors** and limitations
- **Debugging tips** for common issues
- **Production readiness checklist** (10 categories)

**Testing Timeline**:
- **Day 1-2**: Run scenarios A-E (basic purchase flows)
- **Day 3**: Run scenarios F-H (trial testing, 3-5 minute waits)
- **Day 4**: Run scenarios I-K (error handling, multi-device)
- **Day 5**: Run scenario L (auto-renewal, 30 minute waits)
- **Day 6-7**: TestFlight beta testing with real users
- **Day 8**: Final production verification and submission

**Key Success Criteria**:
- ✅ All 12 test scenarios pass without errors
- ✅ Backend verifies 100% of receipts successfully
- ✅ UI states are clear and user-friendly
- ✅ No crashes or data loss
- ✅ Transaction listener processes renewals automatically
- ✅ Restore purchases works on multiple devices

**Next Steps**:
1. Complete sandbox testing (this guide)
2. Fix any issues found
3. Run TestFlight beta testing
4. Complete production readiness checklist
5. Submit to App Store with in-app purchases
6. Monitor post-launch metrics

For questions or issues, refer to:
- [APP_STORE_SETUP.md](APP_STORE_SETUP.md) - App Store Connect configuration
- [Apple StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit)
- [App Store Connect Support](https://developer.apple.com/support/app-store-connect/)

---

**Last Updated**: 2026-03-02
**Version**: 1.0
**Status**: Ready for testing
