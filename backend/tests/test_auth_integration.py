"""Integration tests for authentication flows.

Tests complete end-to-end authentication workflows:
- User registration with trial
- Login and token generation
- Token refresh
- Apple Sign In
- Email verification
- Password reset
- Account deletion

All tests use in-memory SQLite database and mock external services.
"""

from datetime import UTC, datetime
from uuid import UUID

import pytest
from sqlalchemy import select

from app.models.refresh_token import EmailLoginCode, RefreshToken
from app.models.user import User

# ==================== Registration Tests ====================


@pytest.mark.asyncio
async def test_complete_registration_flow(test_client, auth_db_session):
    """Test complete user registration flow with trial."""
    # Register new user
    response = await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "newuser@example.com",
            "password": "SecurePass123!",
        },
    )

    assert response.status_code == 201
    data = response.json()

    # Verify response structure
    assert data["message"] == "Registration successful. Please verify your email."
    assert "user_id" in data
    assert "trial_expires_at" in data

    # Verify user created in database
    result = await auth_db_session.execute(
        select(User).where(User.email == "newuser@example.com")
    )
    user = result.scalar_one_or_none()

    assert user is not None
    assert user.email == "newuser@example.com"
    assert user.subscription_tier == "trial"
    assert user.trial_expires_at is not None
    assert user.email_verified is False
    assert user.email_verification_token is not None

    # Verify trial period is ~7 days
    # SQLite doesn't preserve timezone info, so make trial_expires_at aware
    if user.trial_expires_at.tzinfo is None:
        trial_expires_aware = user.trial_expires_at.replace(tzinfo=UTC)
    else:
        trial_expires_aware = user.trial_expires_at
    trial_duration_days = (
        (trial_expires_aware - datetime.now(UTC)).total_seconds()
        / 86400
    )
    assert 6.9 < trial_duration_days < 7.1


@pytest.mark.asyncio
async def test_registration_with_existing_email(test_client, auth_db_session):
    """Test registration fails with duplicate email."""
    # Register first user
    await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "duplicate@example.com",
            "password": "SecurePass123!",
        },
    )

    # Try to register with same email
    response = await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "duplicate@example.com",
            "password": "DifferentPass456!",
        },
    )

    assert response.status_code == 400
    detail = response.json()["detail"].lower()
    assert "already exists" in detail or "already registered" in detail


@pytest.mark.asyncio
async def test_registration_with_weak_password(test_client):
    """Test registration fails with invalid password."""
    response = await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "test@example.com",
            "password": "weak",
        },
    )

    assert response.status_code == 400
    assert "password" in response.json()["detail"].lower()


# ==================== Login Tests ====================


@pytest.mark.asyncio
async def test_complete_login_flow(test_client, auth_db_session):
    """Test complete login flow with token generation."""
    # First register a user
    await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "login@example.com",
            "password": "SecurePass123!",
        },
    )

    # Login with correct credentials
    response = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "login@example.com",
            "password": "SecurePass123!",
        },
    )

    assert response.status_code == 200
    data = response.json()

    # Verify tokens returned
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["expires_in"] == 900  # 15 minutes
    assert "user" in data

    # Verify user data in response
    user_data = data["user"]
    assert user_data["email"] == "login@example.com"
    assert user_data["subscription_tier"] == "trial"
    assert user_data["email_verified"] is False

    # Verify last_login_at updated in database
    result = await auth_db_session.execute(
        select(User).where(User.email == "login@example.com")
    )
    user = result.scalar_one_or_none()
    assert user.last_login_at is not None

    # Verify refresh token stored in database
    result = await auth_db_session.execute(
        select(RefreshToken).where(RefreshToken.user_id == user.id)
    )
    refresh_token = result.scalar_one_or_none()
    assert refresh_token is not None
    assert refresh_token.token == data["refresh_token"]


@pytest.mark.asyncio
async def test_login_with_wrong_password(test_client):
    """Test login fails with incorrect password."""
    # Register user
    await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "user@example.com",
            "password": "CorrectPass123!",
        },
    )

    # Try to login with wrong password
    response = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "user@example.com",
            "password": "WrongPass123!",
        },
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_login_with_nonexistent_email(test_client):
    """Test login fails with non-existent email."""
    response = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "nonexistent@example.com",
            "password": "SomePass123!",
        },
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


# ==================== Email Code Login Tests ====================


@pytest.mark.asyncio
async def test_send_email_login_code(test_client, auth_db_session, mock_resend_email):
    """Test sending email login code stores hashed code and triggers email."""
    response = await test_client.post(
        "/api/v1/auth/email/send-code",
        json={"email": "code@example.com"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "Verification code sent."
    assert data["expires_in"] == 600
    assert len(mock_resend_email) == 1
    assert mock_resend_email[0][0] == "code@example.com"

    result = await auth_db_session.execute(
        select(EmailLoginCode).where(EmailLoginCode.email == "code@example.com")
    )
    code_record = result.scalar_one_or_none()
    assert code_record is not None
    assert code_record.code_hash != mock_resend_email[0][1]
    assert code_record.used_at is None


@pytest.mark.asyncio
async def test_email_code_login_creates_user_if_missing(
    test_client, auth_db_session, mock_resend_email
):
    """Test email code login auto-creates new trial user."""
    await test_client.post(
        "/api/v1/auth/email/send-code",
        json={"email": "newcode@example.com"},
    )
    code = mock_resend_email[0][1]

    response = await test_client.post(
        "/api/v1/auth/email/verify-code",
        json={"email": "newcode@example.com", "code": code},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["is_new_user"] is True
    assert data["user"]["email"] == "newcode@example.com"
    assert data["user"]["subscription_tier"] == "trial"
    assert "access_token" in data
    assert "refresh_token" in data

    result = await auth_db_session.execute(
        select(User).where(User.email == "newcode@example.com")
    )
    user = result.scalar_one_or_none()
    assert user is not None
    assert user.email_verified is True


@pytest.mark.asyncio
async def test_email_code_login_invalid_code(test_client, mock_resend_email):
    """Test email code login rejects invalid code."""
    await test_client.post(
        "/api/v1/auth/email/send-code",
        json={"email": "badcode@example.com"},
    )
    assert len(mock_resend_email) == 1

    response = await test_client.post(
        "/api/v1/auth/email/verify-code",
        json={"email": "badcode@example.com", "code": "000000"},
    )

    assert response.status_code == 400
    assert "invalid or expired" in response.json()["detail"].lower()


# ==================== Token Refresh Tests ====================


@pytest.mark.asyncio
async def test_token_refresh_flow(test_client):
    """Test refresh token flow to get new access token."""
    # Register and login
    await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "refresh@example.com",
            "password": "SecurePass123!",
        },
    )

    login_response = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "refresh@example.com",
            "password": "SecurePass123!",
        },
    )
    refresh_token = login_response.json()["refresh_token"]

    # Use refresh token to get new access token
    response = await test_client.post(
        "/api/v1/auth/refresh",
        json={
            "refresh_token": refresh_token,
        },
    )

    assert response.status_code == 200
    data = response.json()

    assert "access_token" in data
    assert data["expires_in"] == 900
    # Refresh token should still be valid (not rotated)
    assert "refresh_token" not in data


@pytest.mark.asyncio
async def test_refresh_with_invalid_token(test_client):
    """Test refresh fails with invalid token."""
    response = await test_client.post(
        "/api/v1/auth/refresh",
        json={
            "refresh_token": "invalid-token-123",
        },
    )

    assert response.status_code == 401
    assert "invalid" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_refresh_updates_last_used(test_client, auth_db_session):
    """Test refresh token updates last_used_at timestamp."""
    # Register and login
    await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "lastused@example.com",
            "password": "SecurePass123!",
        },
    )

    login_response = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "lastused@example.com",
            "password": "SecurePass123!",
        },
    )
    refresh_token_str = login_response.json()["refresh_token"]

    # Get initial last_used_at
    result = await auth_db_session.execute(
        select(RefreshToken).where(RefreshToken.token == refresh_token_str)
    )
    token_before = result.scalar_one_or_none()
    initial_last_used = token_before.last_used_at

    # Wait a bit and refresh
    import asyncio
    await asyncio.sleep(0.1)

    await test_client.post(
        "/api/v1/auth/refresh",
        json={
            "refresh_token": refresh_token_str,
        },
    )

    # Verify last_used_at updated
    await auth_db_session.refresh(token_before)
    assert token_before.last_used_at > initial_last_used


# ==================== Apple Sign In Tests ====================


@pytest.mark.asyncio
async def test_apple_signin_new_user(test_client, mock_apple_verify, auth_db_session):
    """Test Apple Sign In creates new user with trial."""
    response = await test_client.post(
        "/api/v1/auth/apple-signin",
        json={
            "identity_token": "mock-apple-token",
        },
    )

    assert response.status_code == 200
    data = response.json()

    # Verify response structure
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["is_new_user"] is True
    assert data["user"]["email"] == "apple@example.com"
    assert data["user"]["subscription_tier"] == "trial"

    # Verify user created in database
    result = await auth_db_session.execute(
        select(User).where(User.apple_id == "test-apple-id-123")
    )
    user = result.scalar_one_or_none()

    assert user is not None
    assert user.email == "apple@example.com"
    assert user.email_verified is True
    assert user.subscription_tier == "trial"
    assert user.trial_expires_at is not None


@pytest.mark.asyncio
async def test_apple_signin_existing_user(
    test_client, mock_apple_verify, auth_db_session
):
    """Test Apple Sign In returns existing user."""
    # First sign in (creates user)
    await test_client.post(
        "/api/v1/auth/apple-signin",
        json={
            "identity_token": "mock-apple-token",
        },
    )

    # Second sign in (finds existing user)
    response = await test_client.post(
        "/api/v1/auth/apple-signin",
        json={
            "identity_token": "mock-apple-token",
        },
    )

    assert response.status_code == 200
    data = response.json()

    assert data["is_new_user"] is False
    assert data["user"]["email"] == "apple@example.com"

    # Verify only one user created
    result = await auth_db_session.execute(
        select(User).where(User.apple_id == "test-apple-id-123")
    )
    users = result.scalars().all()
    assert len(users) == 1


# ==================== End-to-End User Journey ====================


@pytest.mark.asyncio
async def test_complete_user_journey(test_client, auth_db_session):
    """Test complete user journey: register → login → refresh → verify subscription."""
    # 1. Register
    register_response = await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "journey@example.com",
            "password": "SecurePass123!",
        },
    )
    assert register_response.status_code == 201
    user_id = register_response.json()["user_id"]

    # 2. Login
    login_response = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "journey@example.com",
            "password": "SecurePass123!",
        },
    )
    assert login_response.status_code == 200
    access_token = login_response.json()["access_token"]
    refresh_token = login_response.json()["refresh_token"]

    # Verify tokens are not empty
    assert len(access_token) > 0
    assert len(refresh_token) > 0

    # 3. Refresh token
    refresh_response = await test_client.post(
        "/api/v1/auth/refresh",
        json={
            "refresh_token": refresh_token,
        },
    )
    assert refresh_response.status_code == 200
    new_access_token = refresh_response.json()["access_token"]
    assert new_access_token != access_token  # Should be different

    # 4. Verify user state in database
    result = await auth_db_session.execute(
        select(User).where(User.id == UUID(user_id))
    )
    user = result.scalar_one_or_none()

    assert user is not None
    assert user.subscription_tier == "trial"
    assert user.last_login_at is not None
    assert user.deleted_at is None


@pytest.mark.asyncio
async def test_password_validation_edge_cases(test_client):
    """Test password validation with various edge cases."""
    test_cases = [
        ("", "too short"),
        ("short", "too short"),
        ("12345678", "no uppercase"),
        ("ALLCAPS123!", "no lowercase"),
        ("NoNumbers!", "no digit"),
        ("ValidPass123!", 201),  # Valid password
    ]

    for idx, (password, expected) in enumerate(test_cases):
        response = await test_client.post(
            "/api/v1/auth/register",
            json={
                "email": f"test{idx}@example.com",
                "password": password,
            },
        )

        if isinstance(expected, int):
            assert response.status_code == expected
        else:
            assert response.status_code == 400


@pytest.mark.asyncio
async def test_multiple_refresh_tokens_per_user(test_client, auth_db_session):
    """Test user can have multiple refresh tokens (multi-device support)."""
    # Register user
    await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "multidevice@example.com",
            "password": "SecurePass123!",
        },
    )

    # Login from "device 1"
    login1 = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "multidevice@example.com",
            "password": "SecurePass123!",
        },
    )
    token1 = login1.json()["refresh_token"]

    # Login from "device 2"
    login2 = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "multidevice@example.com",
            "password": "SecurePass123!",
        },
    )
    token2 = login2.json()["refresh_token"]

    # Verify different tokens
    assert token1 != token2

    # Verify both tokens work
    refresh1 = await test_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": token1},
    )
    assert refresh1.status_code == 200

    refresh2 = await test_client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": token2},
    )
    assert refresh2.status_code == 200

    # Verify both tokens exist in database
    result = await auth_db_session.execute(
        select(RefreshToken).where(RefreshToken.token.in_([token1, token2]))
    )
    tokens = result.scalars().all()
    assert len(tokens) == 2


@pytest.mark.asyncio
async def test_trial_expiration_in_user_response(test_client, auth_db_session):
    """Test that trial expiration is correctly reflected in user response."""
    # Register user
    response = await test_client.post(
        "/api/v1/auth/register",
        json={
            "email": "trial@example.com",
            "password": "SecurePass123!",
        },
    )

    trial_expires = response.json()["trial_expires_at"]

    # Login to get full user response
    login_response = await test_client.post(
        "/api/v1/auth/login",
        json={
            "email": "trial@example.com",
            "password": "SecurePass123!",
        },
    )

    user_data = login_response.json()["user"]
    assert user_data["trial_expires_at"] == trial_expires
    assert user_data["subscription_expires_at"] is None
    assert user_data["subscription_tier"] == "trial"
