"""Pydantic schemas for subscription endpoints."""

from datetime import datetime

from pydantic import BaseModel


class VerifyReceiptRequest(BaseModel):
    """Receipt verification request."""
    transaction_id: str
    verification_data: str  # JWS receipt
    product_id: str


class VerifyReceiptResponse(BaseModel):
    """Receipt verification response."""
    subscription_tier: str
    expires_at: datetime
    is_trial: bool
    product_id: str


class SubscriptionStatusResponse(BaseModel):
    """Subscription status response."""
    current_tier: str
    is_trial: bool
    trial_expires_at: datetime | None
    subscription_expires_at: datetime | None
    product_id: str | None
    auto_renew_enabled: bool


class AppStoreWebhookRequest(BaseModel):
    """App Store Server Notifications v2 request payload."""

    signedPayload: str  # noqa: N815 - matches Apple's webhook payload


class AppStoreWebhookResponse(BaseModel):
    """App Store webhook processing result."""

    status: str
    applied: bool
    notification_type: str | None
    subtype: str | None = None
    user_id: str | None = None
    current_tier: str | None = None
    auto_renew_enabled: bool | None = None
    reason: str | None = None
