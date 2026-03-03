"""StoreKit 2 receipt verification utilities."""

from datetime import UTC, datetime

import jwt
from fastapi import HTTPException
from jwt import PyJWKClient

# App Store's JWKS endpoint for receipt verification
APPSTORE_JWKS_URL = "https://appleid.apple.com/auth/keys"

# Product ID to subscription tier mapping
PRODUCT_TIER_MAP = {
    "com.readless.basic.monthly": "basic",
    "com.readless.pro.monthly": "pro",
}


async def verify_storekit_receipt(jws_receipt: str) -> dict:
    """
    Verify StoreKit 2 JWS receipt and extract subscription information.

    Args:
        jws_receipt: JWS format receipt from StoreKit Transaction.jwsRepresentation

    Returns:
        dict with:
            - transaction_id: Unique transaction ID
            - original_transaction_id: Original transaction ID (for renewals)
            - product_id: Product identifier (e.g., com.readless.pro.monthly)
            - subscription_tier: Mapped tier (basic/pro)
            - purchase_date: When purchased (datetime)
            - expires_date: When subscription expires (datetime)
            - is_trial: Whether this is a trial period

    Raises:
        HTTPException: If receipt is invalid or verification fails
    """
    _fail_msg = (
        "Subscription verification failed."
        " Please try 'Restore Purchases'"
        " or contact support."
    )

    try:
        # Fetch App Store's public keys
        jwks_client = PyJWKClient(APPSTORE_JWKS_URL, cache_keys=True)
        signing_key = jwks_client.get_signing_key_from_jwt(jws_receipt)

        # Decode and verify the JWS
        payload = jwt.decode(
            jws_receipt,
            signing_key.key,
            algorithms=["ES256"],  # App Store uses ES256 (ECDSA)
            options={
                "verify_signature": True,
                "verify_exp": False,  # Receipts don't have exp claim
            }
        )

        # Extract transaction information
        transaction_id = payload.get("transactionId")
        original_transaction_id = payload.get("originalTransactionId")
        product_id = payload.get("productId")
        purchase_date_ms = payload.get("purchaseDate")
        expires_date_ms = payload.get("expiresDate")
        transaction_type = payload.get("type")
        offer_type = payload.get("offerType")

        # Validate required fields
        if not transaction_id or not product_id:
            raise HTTPException(
                status_code=400,
                detail=_fail_msg,
            )

        # Map product ID to subscription tier
        subscription_tier = PRODUCT_TIER_MAP.get(product_id)
        if not subscription_tier:
            raise HTTPException(
                status_code=400,
                detail=_fail_msg,
            )

        # Convert timestamps (milliseconds to datetime)
        purchase_date = None
        if purchase_date_ms:
            purchase_date = datetime.fromtimestamp(purchase_date_ms / 1000, tz=UTC)

        expires_date = None
        if expires_date_ms:
            expires_date = datetime.fromtimestamp(expires_date_ms / 1000, tz=UTC)

        # Determine if this is a trial period
        is_trial = (offer_type == 1)  # 1 = introductory offer (trial)

        return {
            "transaction_id": transaction_id,
            "original_transaction_id": original_transaction_id or transaction_id,
            "product_id": product_id,
            "subscription_tier": subscription_tier,
            "purchase_date": purchase_date,
            "expires_date": expires_date,
            "is_trial": is_trial,
            "transaction_type": transaction_type,
        }

    except jwt.PyJWTError:
        raise HTTPException(
            status_code=400,
            detail=_fail_msg,
        )
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=500,
            detail=_fail_msg,
        )


def is_subscription_active(expires_date: datetime | None) -> bool:
    """Check if subscription is currently active based on expiration date."""
    if not expires_date:
        return False
    # Normalize naive datetimes (e.g. from SQLite in tests) to UTC
    if expires_date.tzinfo is None:
        expires_date = expires_date.replace(tzinfo=UTC)
    return expires_date > datetime.now(UTC)
