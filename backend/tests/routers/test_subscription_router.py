"""Router-focused tests for subscription endpoints."""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException

from app.schemas.subscription import AppStoreWebhookRequest, VerifyReceiptRequest


@pytest.mark.asyncio
async def test_verify_receipt_rejects_invalid_session_user_id(auth_db_session):
    from app.routers.subscription import verify_receipt

    with pytest.raises(HTTPException) as exc_info:
        await verify_receipt(
            request=VerifyReceiptRequest(
                transaction_id="txn-1",
                verification_data="receipt",
                product_id="com.readless.pro.monthly",
            ),
            user_id="not-a-uuid",
            db=auth_db_session,
        )

    assert exc_info.value.status_code == 401
    assert "Invalid session" in exc_info.value.detail


@pytest.mark.asyncio
async def test_get_status_rejects_invalid_session_user_id(auth_db_session):
    from app.routers.subscription import get_status

    with pytest.raises(HTTPException) as exc_info:
        await get_status(user_id="not-a-uuid", db=auth_db_session)

    assert exc_info.value.status_code == 401
    assert "Invalid session" in exc_info.value.detail


@pytest.mark.asyncio
async def test_webhook_routes_forward_environment_name(auth_db_session):
    from app.routers.subscription import app_store_webhook, app_store_webhook_sandbox

    fake_result = {
        "status": "processed",
        "applied": True,
        "notification_type": "DID_RENEW",
        "subtype": None,
        "user_id": None,
        "current_tier": None,
        "auto_renew_enabled": None,
    }

    with patch(
        "app.services.subscription_service.SubscriptionService.process_app_store_notification",
        new=AsyncMock(return_value=fake_result),
    ) as mock_process:
        request = AppStoreWebhookRequest(signedPayload="signed-payload")
        production = await app_store_webhook(request=request, db=auth_db_session)
        sandbox = await app_store_webhook_sandbox(
            request=request,
            db=auth_db_session,
        )

    assert production.status == "processed"
    assert sandbox.status == "processed"
    assert mock_process.await_args_list[0].args == ("signed-payload",)
    assert mock_process.await_args_list[0].kwargs == {"environment_name": None}
    assert mock_process.await_args_list[1].args == ("signed-payload",)
    assert mock_process.await_args_list[1].kwargs == {
        "environment_name": "Sandbox",
    }
