"""Unit-style tests for auth service edge cases."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.refresh_token import EmailLoginCode, PasswordResetToken
from app.models.user import User
from app.services.auth_service import AuthService, _hash_email_verification_token


def _service(db_session) -> AuthService:
    service = AuthService(db_session)
    service.email_service = SimpleNamespace(
        send_login_code=AsyncMock(),
        send_verification_email=AsyncMock(),
    )
    service.session_service = SimpleNamespace(
        issue_session=AsyncMock(return_value=("access", "refresh")),
        revoke_all_sessions=AsyncMock(),
        refresh_access_token=AsyncMock(return_value=("access", None)),
    )
    return service


@pytest.mark.asyncio
async def test_send_email_login_code_throttles_recent_requests(auth_db_session):
    service = _service(auth_db_session)
    auth_db_session.add(
        EmailLoginCode(
            email="user@example.com",
            code_hash="hash",
            expires_at=datetime.now(UTC) + timedelta(minutes=10),
            created_at=datetime.now(UTC),
        )
    )
    await auth_db_session.commit()

    with pytest.raises(ValueError) as exc_info:
        await service.send_email_login_code("user@example.com")

    assert "too frequently" in str(exc_info.value)


@pytest.mark.asyncio
async def test_send_email_login_code_deletes_record_when_delivery_fails(
    auth_db_session,
):
    service = _service(auth_db_session)
    service.email_service.send_login_code = AsyncMock(side_effect=ValueError("boom"))

    with pytest.raises(ValueError):
        await service.send_email_login_code("user@example.com")

    records = (await auth_db_session.execute(select(EmailLoginCode))).scalars().all()
    assert records == []


@pytest.mark.asyncio
async def test_verify_email_login_code_marks_code_used_after_five_failures(
    auth_db_session,
):
    service = _service(auth_db_session)
    code_record = EmailLoginCode(
        email="user@example.com",
        code_hash=service._hash_email_login_code("user@example.com", "123456"),
        expires_at=datetime.now(UTC) + timedelta(minutes=10),
        attempts=4,
    )
    auth_db_session.add(code_record)
    await auth_db_session.commit()

    with pytest.raises(ValueError):
        await service.verify_email_login_code("user@example.com", "000000")

    stored = (
        await auth_db_session.execute(
            select(EmailLoginCode).where(EmailLoginCode.id == code_record.id)
        )
    ).scalar_one()
    assert stored.attempts == 5
    assert stored.used_at is not None


@pytest.mark.asyncio
async def test_resend_verification_email_rejects_missing_and_verified_users(
    auth_db_session,
):
    service = _service(auth_db_session)

    with pytest.raises(ValueError) as missing_exc:
        await service.resend_verification_email("missing@example.com")
    assert str(missing_exc.value) == "User not found"

    user = User(
        id=uuid4(),
        email="verified@example.com",
        email_verified=True,
        subscription_tier="trial",
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    with pytest.raises(ValueError) as verified_exc:
        await service.resend_verification_email("verified@example.com")
    assert str(verified_exc.value) == "Email already verified"


@pytest.mark.asyncio
async def test_resend_verification_email_rolls_back_token_when_delivery_fails(
    auth_db_session,
):
    service = _service(auth_db_session)
    user = User(
        id=uuid4(),
        email="pending@example.com",
        email_verified=False,
        subscription_tier="trial",
        email_verification_token="existing-token-hash",
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    service.email_service.send_verification_email = AsyncMock(
        side_effect=ValueError("delivery failed")
    )

    with pytest.raises(ValueError):
        await service.resend_verification_email("Pending@Example.com")

    await auth_db_session.refresh(user)
    assert user.email_verification_token == "existing-token-hash"


@pytest.mark.asyncio
async def test_resend_verification_email_normalizes_email_before_lookup_and_send(
    auth_db_session,
):
    service = _service(auth_db_session)
    user = User(
        id=uuid4(),
        email="normalized@example.com",
        email_verified=False,
        subscription_tier="trial",
        email_verification_token="old-token-hash",
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    raw_token = await service.resend_verification_email("Normalized@Example.com")

    service.email_service.send_verification_email.assert_awaited_once_with(
        to_email="normalized@example.com",
        token=raw_token,
    )
    await auth_db_session.refresh(user)
    assert user.email_verification_token == _hash_email_verification_token(raw_token)


@pytest.mark.asyncio
async def test_reset_password_rejects_expired_token(auth_db_session):
    service = _service(auth_db_session)
    user = User(
        id=uuid4(),
        email="reset@example.com",
        password_hash="old-hash",
        subscription_tier="trial",
    )
    auth_db_session.add(user)
    await auth_db_session.flush()
    auth_db_session.add(
        PasswordResetToken(
            user_id=user.id,
            token="legacy-token",
            expires_at=datetime.now(UTC) - timedelta(minutes=1),
        )
    )
    await auth_db_session.commit()

    with pytest.raises(ValueError) as exc_info:
        await service.reset_password("legacy-token", "SecurePass123!")

    assert "expired" in str(exc_info.value).lower()


@pytest.mark.asyncio
async def test_reset_password_rejects_when_token_user_is_missing(auth_db_session):
    service = _service(auth_db_session)
    user = User(
        id=uuid4(),
        email="deleted@example.com",
        subscription_tier="trial",
    )
    auth_db_session.add(user)
    await auth_db_session.flush()
    auth_db_session.add(
        PasswordResetToken(
            user_id=user.id,
            token="legacy-token",
            expires_at=datetime.now(UTC) + timedelta(hours=1),
        )
    )
    await auth_db_session.commit()
    user.deleted_at = datetime.now(UTC)
    await auth_db_session.commit()

    with pytest.raises(ValueError) as exc_info:
        await service.reset_password("legacy-token", "SecurePass123!")

    assert str(exc_info.value) == "User not found"


@pytest.mark.asyncio
async def test_delete_account_marks_user_deleted_and_revokes_sessions(auth_db_session):
    service = _service(auth_db_session)
    user = User(
        id=uuid4(),
        email="delete@example.com",
        subscription_tier="trial",
    )
    auth_db_session.add(user)
    await auth_db_session.commit()

    await service.delete_account(user.id)

    stored = (
        await auth_db_session.execute(select(User).where(User.id == user.id))
    ).scalar_one()
    assert stored.deleted_at is not None
    service.session_service.revoke_all_sessions.assert_awaited_once_with(user.id)
