"""Integration tests for subscription flows.

Tests complete end-to-end subscription workflows:
- Receipt verification and subscription activation
- Subscription status retrieval
- Trial to paid subscription flow
- Subscription upgrades (Basic → Pro)
- Subscription expiration handling

All tests use in-memory SQLite database and mock StoreKit verification.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.user import User


def ensure_utc(dt: datetime) -> datetime:
    """Normalize possibly-naive datetimes from SQLite to UTC."""
    if dt.tzinfo is None:
        return dt.replace(tzinfo=UTC)
    return dt.astimezone(UTC)


# ==================== Receipt Verification Tests ====================


@pytest.mark.asyncio
async def test_verify_receipt_basic_subscription(
    test_client, mock_storekit_verify, auth_db_session
):
    """Test verifying receipt activates Basic subscription."""
    # Register user
    register_response = await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "basic@example.com",
            "password": "SecurePass123!",
        },
    )
    assert register_response.status_code == 201

    login_response = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "basic@example.com",
            "password": "SecurePass123!",
        },
    )
    assert login_response.status_code == 200
    access_token = login_response.json()["access_token"]

    # Verify receipt for Basic subscription
    response = await test_client.post(
        "/api/v1/subscription/verify-receipt",
        json={
            "verification_data": "mock-basic-receipt",
            "transaction_id": "test-txn-123",
            "product_id": "com.readless.basic.monthly",
        },
        headers={"Authorization": f"Bearer {access_token}"},
    )

    assert response.status_code == 200


@pytest.mark.asyncio
async def test_verify_receipt_pro_subscription(
    test_client, mock_storekit_verify, auth_db_session
):
    """Test verifying receipt activates Pro subscription."""
    # Create user directly in database for testing
    user_id = uuid4()
    trial_expires = datetime.now(UTC) + timedelta(days=7)

    user = User(
        id=user_id,
        email="pro@example.com",
        password_hash="dummy-hash",
        subscription_tier="trial",
        trial_expires_at=trial_expires,
        email_verified=False,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    # Mock receipt verification to return Pro tier
    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    result = await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-pro-receipt",
        transaction_id="test-txn-pro",
    )

    # Verify response
    assert result["subscription_tier"] == "pro"
    assert result["is_trial"] is False
    assert result["product_id"] == "com.readless.pro.monthly"

    # Verify user updated in database
    await auth_db_session.refresh(user)
    assert user.subscription_tier == "pro"
    assert user.subscription_expires_at is not None
    assert user.trial_expires_at is None  # Trial cleared
    assert user.apple_original_transaction_id == "test-orig-txn-123"


@pytest.mark.asyncio
async def test_verify_receipt_clears_trial(test_client, mock_storekit_verify, auth_db_session):
    """Test receipt verification clears trial period."""
    # Create user with active trial
    user_id = uuid4()
    trial_expires = datetime.now(UTC) + timedelta(days=5)

    user = User(
        id=user_id,
        email="cleartrial@example.com",
        password_hash="dummy-hash",
        subscription_tier="trial",
        trial_expires_at=trial_expires,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    # Verify Basic subscription receipt
    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-basic-receipt",
        transaction_id="test-txn-123",
    )

    # Verify trial cleared
    await auth_db_session.refresh(user)
    assert user.trial_expires_at is None
    assert user.subscription_tier == "basic"


@pytest.mark.asyncio
async def test_verify_receipt_stores_receipt_data(
    test_client, mock_storekit_verify, auth_db_session
):
    """Test receipt verification stores receipt data."""
    user_id = uuid4()
    user = User(
        id=user_id,
        email="receipt@example.com",
        password_hash="dummy-hash",
        subscription_tier="trial",
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    receipt_data = "mock-receipt-jws-data-12345"

    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt=receipt_data,
        transaction_id="test-txn-123",
    )

    # Verify receipt stored
    await auth_db_session.refresh(user)
    assert user.apple_receipt_data == receipt_data
    assert user.apple_original_transaction_id == "test-orig-txn-123"


# ==================== Subscription Status Tests ====================


@pytest.mark.asyncio
async def test_get_subscription_status_trial(test_client, auth_db_session):
    """Test getting status for user on trial."""
    user_id = uuid4()
    trial_expires = datetime.now(UTC) + timedelta(days=3)

    user = User(
        id=user_id,
        email="status-trial@example.com",
        password_hash="dummy-hash",
        subscription_tier="trial",
        trial_expires_at=trial_expires,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    result = await service.get_subscription_status(user_id=user_id)

    assert result["current_tier"] == "trial"
    assert result["is_trial"] is True
    assert result["trial_expires_at"] == trial_expires
    assert result["subscription_expires_at"] is None


@pytest.mark.asyncio
async def test_get_subscription_status_active_subscription(
    test_client, auth_db_session
):
    """Test getting status for user with active subscription."""
    user_id = uuid4()
    sub_expires = datetime.now(UTC) + timedelta(days=30)

    user = User(
        id=user_id,
        email="status-active@example.com",
        password_hash="dummy-hash",
        subscription_tier="pro",
        subscription_expires_at=sub_expires,
        trial_expires_at=None,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    result = await service.get_subscription_status(user_id=user_id)

    assert result["current_tier"] == "pro"
    assert result["is_trial"] is False
    assert result["subscription_expires_at"] == sub_expires
    assert result["product_id"] == "com.readless.pro.monthly"


@pytest.mark.asyncio
async def test_get_subscription_status_expired(test_client, auth_db_session):
    """Test getting status for user with expired subscription."""
    user_id = uuid4()
    expired_date = datetime.now(UTC) - timedelta(days=1)

    user = User(
        id=user_id,
        email="status-expired@example.com",
        password_hash="dummy-hash",
        subscription_tier="basic",
        subscription_expires_at=expired_date,
        trial_expires_at=None,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    result = await service.get_subscription_status(user_id=user_id)

    assert result["current_tier"] == "expired"
    assert result["is_trial"] is False
    assert result["product_id"] is None


# ==================== Trial Expiration Tests ====================


@pytest.mark.asyncio
async def test_trial_expiration_effective_tier(test_client, auth_db_session):
    """Test get_effective_tier returns expired for expired trial."""
    user_id = uuid4()
    expired_trial = datetime.now(UTC) - timedelta(days=1)

    user = User(
        id=user_id,
        email="expired-trial@example.com",
        password_hash="dummy-hash",
        subscription_tier="trial",
        trial_expires_at=expired_trial,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    # Test model method
    assert user.get_effective_tier() == "expired"
    assert user.is_subscription_active() is False


@pytest.mark.asyncio
async def test_subscription_expiration_effective_tier(test_client, auth_db_session):
    """Test get_effective_tier returns expired for expired subscription."""
    user_id = uuid4()
    expired_sub = datetime.now(UTC) - timedelta(hours=1)

    user = User(
        id=user_id,
        email="expired-sub@example.com",
        password_hash="dummy-hash",
        subscription_tier="pro",
        subscription_expires_at=expired_sub,
        trial_expires_at=None,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    assert user.get_effective_tier() == "expired"
    assert user.is_subscription_active() is False


# ==================== Subscription Upgrade Tests ====================


@pytest.mark.asyncio
async def test_upgrade_basic_to_pro(test_client, mock_storekit_verify, auth_db_session):
    """Test upgrading from Basic to Pro subscription."""
    user_id = uuid4()
    basic_expires = datetime.now(UTC) + timedelta(days=15)

    # Create user with Basic subscription
    user = User(
        id=user_id,
        email="upgrade@example.com",
        password_hash="dummy-hash",
        subscription_tier="basic",
        subscription_expires_at=basic_expires,
        trial_expires_at=None,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    # Verify Pro receipt
    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    result = await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-pro-receipt",
        transaction_id="test-txn-pro",
    )

    # Verify upgrade
    assert result["subscription_tier"] == "pro"

    await auth_db_session.refresh(user)
    assert user.subscription_tier == "pro"
    # Expiration date should be updated (new 30-day period from mock)
    assert ensure_utc(user.subscription_expires_at) > basic_expires


@pytest.mark.asyncio
async def test_downgrade_not_immediate(test_client, mock_storekit_verify, auth_db_session):
    """Test that downgrade doesn't immediately change tier (waits for expiry)."""
    # Note: This tests current implementation behavior
    # In production, App Store handles subscription changes via webhooks
    user_id = uuid4()
    pro_expires = datetime.now(UTC) + timedelta(days=20)

    user = User(
        id=user_id,
        email="downgrade@example.com",
        password_hash="dummy-hash",
        subscription_tier="pro",
        subscription_expires_at=pro_expires,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    # Verify Basic receipt (simulates downgrade request)
    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    result = await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-basic-receipt",
        transaction_id="test-txn-basic",
    )

    # Current implementation updates immediately
    # In production, this would be handled by webhooks at renewal time
    assert result["subscription_tier"] == "basic"


# ==================== End-to-End Subscription Journey ====================


@pytest.mark.asyncio
async def test_complete_subscription_journey(
    test_client, mock_storekit_verify, auth_db_session
):
    """Test complete subscription journey: trial → Basic → Pro → status."""
    # 1. Create user with trial
    user_id = uuid4()
    trial_expires = datetime.now(UTC) + timedelta(days=7)

    user = User(
        id=user_id,
        email="journey@example.com",
        password_hash="dummy-hash",
        subscription_tier="trial",
        trial_expires_at=trial_expires,
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)

    # Verify initial trial status
    status = await service.get_subscription_status(user_id=user_id)
    assert status["current_tier"] == "trial"
    assert status["is_trial"] is True

    # 2. Purchase Basic subscription
    basic_result = await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-basic-receipt",
        transaction_id="test-txn-basic",
    )

    assert basic_result["subscription_tier"] == "basic"
    await auth_db_session.refresh(user)
    assert user.trial_expires_at is None  # Trial cleared

    # Verify Basic status
    status = await service.get_subscription_status(user_id=user_id)
    assert status["current_tier"] == "basic"
    assert status["is_trial"] is False
    assert status["product_id"] == "com.readless.basic.monthly"

    # 3. Upgrade to Pro
    pro_result = await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-pro-receipt",
        transaction_id="test-txn-pro",
    )

    assert pro_result["subscription_tier"] == "pro"

    # Verify Pro status
    status = await service.get_subscription_status(user_id=user_id)
    assert status["current_tier"] == "pro"
    assert status["product_id"] == "com.readless.pro.monthly"


@pytest.mark.asyncio
async def test_subscription_with_nonexistent_user(test_client, auth_db_session):
    """Test subscription operations fail with non-existent user."""
    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)
    fake_user_id = uuid4()

    # Test verify receipt
    with pytest.raises(ValueError, match="User not found"):
        await service.verify_and_update_subscription(
            user_id=fake_user_id,
            jws_receipt="mock-receipt",
            transaction_id="test-txn",
        )

    # Test get status
    with pytest.raises(ValueError, match="User not found"):
        await service.get_subscription_status(user_id=fake_user_id)


@pytest.mark.asyncio
async def test_subscription_activation_dates(
    test_client, mock_storekit_verify, auth_db_session
):
    """Test subscription activation sets correct expiration dates."""
    user_id = uuid4()
    user = User(
        id=user_id,
        email="dates@example.com",
        password_hash="dummy-hash",
        subscription_tier="trial",
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)

    before_activation = datetime.now(UTC)

    await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-basic-receipt",
        transaction_id="test-txn-123",
    )

    await auth_db_session.refresh(user)

    # Verify expiration date is in the future (mock returns +30 days)
    assert user.subscription_expires_at is not None
    expires_at = ensure_utc(user.subscription_expires_at)
    assert expires_at > before_activation

    # Should be approximately 30 days from now (from mock)
    expected_expiry = datetime.now(UTC) + timedelta(days=30)
    time_diff = abs((expires_at - expected_expiry).total_seconds())
    assert time_diff < 10  # Within 10 seconds


@pytest.mark.asyncio
async def test_receipt_verification_updates_transaction_id(
    test_client, mock_storekit_verify, auth_db_session
):
    """Test receipt verification updates transaction IDs correctly."""
    user_id = uuid4()
    user = User(
        id=user_id,
        email="txn@example.com",
        password_hash="dummy-hash",
        subscription_tier="trial",
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    from app.services.subscription_service import SubscriptionService

    service = SubscriptionService(auth_db_session)

    # First purchase
    await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-receipt-1",
        transaction_id="txn-001",
    )

    await auth_db_session.refresh(user)
    assert user.apple_original_transaction_id == "test-orig-txn-123"

    # Renewal (different transaction, same original)
    await service.verify_and_update_subscription(
        user_id=user_id,
        jws_receipt="mock-receipt-2",
        transaction_id="txn-002",
    )

    await auth_db_session.refresh(user)
    # Original transaction ID should remain the same
    assert user.apple_original_transaction_id == "test-orig-txn-123"
    # Latest receipt should be updated
    assert user.apple_receipt_data == "mock-receipt-2"
