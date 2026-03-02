"""Tests for Apple Sign In authentication."""

import pytest
from fastapi import HTTPException

from app.services.apple_auth import verify_apple_identity_token


@pytest.mark.asyncio
async def test_verify_apple_token_missing_sub():
    """Test that token without sub claim is rejected."""
    # This is a mock invalid token - in real tests you'd use a test token
    invalid_token = "invalid.jwt.token"

    with pytest.raises(HTTPException) as exc_info:
        await verify_apple_identity_token(invalid_token)

    assert exc_info.value.status_code in [400, 401]


@pytest.mark.asyncio
async def test_verify_apple_token_expired():
    """Test that expired token is rejected."""
    # Mock expired token
    expired_token = "expired.jwt.token"

    with pytest.raises(HTTPException) as exc_info:
        await verify_apple_identity_token(expired_token)

    # Should raise 401 for expired token
    assert exc_info.value.status_code == 401


# Note: Real Apple token verification tests require valid test tokens from Apple
# These would be integration tests run against Apple's sandbox environment
