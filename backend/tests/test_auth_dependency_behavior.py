"""Behavior tests for the auth dependency."""

from __future__ import annotations

from unittest.mock import patch

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from jwt import InvalidTokenError


@pytest.mark.asyncio
async def test_get_current_user_id_rejects_missing_header():
    from app.auth import get_current_user_id

    with patch("app.auth.settings.disable_auth", False):
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user_id(credentials=None)

    assert exc_info.value.status_code == 401
    assert exc_info.value.detail == "Missing authorization header"


@pytest.mark.asyncio
async def test_get_current_user_id_maps_expired_token_to_friendly_message():
    from app.auth import get_current_user_id

    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="expired-token",
    )

    with patch("app.auth.settings.disable_auth", False), patch(
        "app.auth.verify_access_token",
        side_effect=InvalidTokenError("Signature has expired"),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user_id(credentials=credentials)

    assert exc_info.value.status_code == 401
    assert "expired" in exc_info.value.detail.lower()


@pytest.mark.asyncio
async def test_get_current_user_id_rejects_payload_without_subject():
    from app.auth import get_current_user_id

    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="token-without-sub",
    )

    with patch("app.auth.settings.disable_auth", False), patch(
        "app.auth.verify_access_token",
        return_value={},
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_current_user_id(credentials=credentials)

    assert exc_info.value.status_code == 401
    assert "invalid authentication token" in exc_info.value.detail.lower()


@pytest.mark.asyncio
async def test_get_current_user_id_returns_subject_from_valid_token():
    from app.auth import get_current_user_id

    credentials = HTTPAuthorizationCredentials(
        scheme="Bearer",
        credentials="valid-token",
    )

    with patch("app.auth.settings.disable_auth", False), patch(
        "app.auth.verify_access_token",
        return_value={"sub": "user-123"},
    ):
        user_id = await get_current_user_id(credentials=credentials)

    assert user_id == "user-123"
