"""Subscription management service."""

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.services.storekit_receipt import verify_storekit_receipt, is_subscription_active


class SubscriptionService:
    """Service for subscription operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def verify_and_update_subscription(
        self,
        user_id: UUID,
        jws_receipt: str,
        transaction_id: str,
    ) -> dict:
        """
        Verify receipt and update user's subscription.

        Returns subscription information.
        """
        # Get user
        result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        # Verify receipt with Apple
        receipt_data = await verify_storekit_receipt(jws_receipt)

        # Update user's subscription
        user.subscription_tier = receipt_data["subscription_tier"]
        user.subscription_expires_at = receipt_data["expires_date"]
        user.apple_original_transaction_id = receipt_data["original_transaction_id"]
        user.apple_receipt_data = jws_receipt  # Store latest receipt

        # Clear trial if user purchased subscription
        if not receipt_data["is_trial"]:
            user.trial_expires_at = None

        await self.db.commit()
        await self.db.refresh(user)

        return {
            "subscription_tier": user.subscription_tier,
            "expires_at": user.subscription_expires_at,
            "is_trial": receipt_data["is_trial"],
            "product_id": receipt_data["product_id"],
        }

    async def get_subscription_status(self, user_id: UUID) -> dict:
        """Get user's current subscription status."""
        result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        # Determine current tier
        current_tier = user.get_effective_tier()
        is_trial = (current_tier == "trial")

        # Check if subscription is active
        subscription_active = is_subscription_active(user.subscription_expires_at)

        return {
            "current_tier": current_tier,
            "is_trial": is_trial,
            "trial_expires_at": user.trial_expires_at,
            "subscription_expires_at": user.subscription_expires_at,
            "product_id": self._tier_to_product_id(user.subscription_tier) if subscription_active else None,
            "auto_renew_enabled": True,  # TODO: Get from latest receipt
        }

    def _tier_to_product_id(self, tier: str) -> str | None:
        """Map tier to product ID."""
        tier_map = {
            "basic": "com.readless.basic.monthly",
            "pro": "com.readless.pro.monthly",
        }
        return tier_map.get(tier)
