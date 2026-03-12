"""Subscription API endpoints."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.database import get_db
from app.schemas.subscription import (
    AppStoreWebhookRequest,
    AppStoreWebhookResponse,
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
            product_id=request.product_id,
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


@router.post("/webhook", response_model=AppStoreWebhookResponse)
async def app_store_webhook(
    request: AppStoreWebhookRequest,
    db: AsyncSession = Depends(get_db),
):
    """Handle production App Store Server Notifications v2."""
    return await _process_webhook(request=request, db=db)


@router.post("/webhook-sandbox", response_model=AppStoreWebhookResponse)
async def app_store_webhook_sandbox(
    request: AppStoreWebhookRequest,
    db: AsyncSession = Depends(get_db),
):
    """Handle Sandbox App Store Server Notifications v2."""
    return await _process_webhook(
        request=request,
        db=db,
        environment_name="Sandbox",
    )


async def _process_webhook(
    *,
    request: AppStoreWebhookRequest,
    db: AsyncSession,
    environment_name: str | None = None,
) -> AppStoreWebhookResponse:
    subscription_service = SubscriptionService(db)
    result = await subscription_service.process_app_store_notification(
        request.signedPayload,
        environment_name=environment_name,
    )
    return AppStoreWebhookResponse(**result)
