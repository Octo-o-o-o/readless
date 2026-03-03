"""Subscription API endpoints."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.schemas.subscription import (
    SubscriptionStatusResponse,
    VerifyReceiptRequest,
    VerifyReceiptResponse,
)
from app.services.subscription_service import SubscriptionService

router = APIRouter(prefix="/subscription", tags=["subscription"])


@router.post("/verify-receipt", response_model=VerifyReceiptResponse)
async def verify_receipt(
    request: VerifyReceiptRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Verify App Store receipt and update subscription."""
    subscription_service = SubscriptionService(db)
    try:
        user_uuid = UUID(user_id)
    except ValueError:
        raise HTTPException(
            status_code=401,
            detail="Invalid session. Please log in again.",
        )

    try:
        result = await subscription_service.verify_and_update_subscription(
            user_id=user_uuid,
            jws_receipt=request.verification_data,
            transaction_id=request.transaction_id,
        )

        return VerifyReceiptResponse(**result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except HTTPException:
        raise  # Pass through HTTP exceptions from receipt verification


@router.get("/status", response_model=SubscriptionStatusResponse)
async def get_status(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Get current subscription status."""
    subscription_service = SubscriptionService(db)
    try:
        user_uuid = UUID(user_id)
    except ValueError:
        raise HTTPException(
            status_code=401,
            detail="Invalid session. Please log in again.",
        )

    try:
        result = await subscription_service.get_subscription_status(
            user_id=user_uuid
        )

        return SubscriptionStatusResponse(**result)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/webhook")
async def app_store_webhook(
    # TODO: Implement App Store Server Notifications v2 handler
    db: AsyncSession = Depends(get_db),
):
    """
    Handle App Store Server Notifications v2.

    This endpoint receives real-time subscription events:
    - SUBSCRIBED: User subscribed
    - DID_RENEW: Subscription renewed
    - DID_FAIL_TO_RENEW: Renewal failed
    - EXPIRED: Subscription expired
    - REFUND: Purchase refunded
    """
    # TODO: Verify webhook signature
    # TODO: Parse signedPayload
    # TODO: Update user subscription based on event type
    raise HTTPException(status_code=501, detail="Webhook handler not implemented yet")
