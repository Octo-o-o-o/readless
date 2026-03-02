"""Tests for StoreKit receipt verification."""

import pytest
from fastapi import HTTPException

from app.services.storekit_receipt import PRODUCT_TIER_MAP, verify_storekit_receipt


@pytest.mark.asyncio
async def test_verify_receipt_invalid_jws():
    """Test that invalid JWS is rejected."""
    invalid_jws = "invalid.jws.receipt"

    with pytest.raises(HTTPException) as exc_info:
        await verify_storekit_receipt(invalid_jws)

    assert exc_info.value.status_code == 400


@pytest.mark.asyncio
async def test_product_tier_mapping():
    """Test product ID to tier mapping."""
    assert PRODUCT_TIER_MAP["com.readless.basic.monthly"] == "basic"
    assert PRODUCT_TIER_MAP["com.readless.pro.monthly"] == "pro"


# Note: Real StoreKit receipt verification tests require valid test receipts
# These would be integration tests run against App Store sandbox environment
