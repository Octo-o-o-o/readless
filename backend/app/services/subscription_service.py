"""Subscription management service."""

from collections.abc import Callable
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.services.storekit_receipt import (
    VerifiedNotification,
    VerifiedRenewalInfo,
    VerifiedTransaction,
    is_subscription_active,
    verify_app_store_notification,
    verify_storekit_receipt,
)


class SubscriptionService:
    """Service for subscription operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def verify_and_update_subscription(
        self,
        user_id: UUID,
        jws_receipt: str,
        transaction_id: str | None = None,
        product_id: str | None = None,
    ) -> dict:
        """
        Verify receipt and update user's subscription.

        Returns subscription information.
        """
        user = await self._get_user_by_id(user_id)
        receipt_payload = await verify_storekit_receipt(jws_receipt)
        receipt_data = self._coerce_transaction(receipt_payload)
        self._validate_receipt_binding(
            receipt_data=receipt_data,
            user_id=user_id,
            request_transaction_id=transaction_id,
            request_product_id=product_id,
        )

        self._apply_transaction_state(
            user,
            transaction_info=receipt_data,
            raw_receipt=jws_receipt,
            auto_renew_enabled=True,
        )

        await self.db.commit()
        await self.db.refresh(user)

        return {
            "subscription_tier": user.subscription_tier,
            "expires_at": user.subscription_expires_at,
            "is_trial": receipt_data.is_trial,
            "product_id": receipt_data.product_id,
        }

    async def get_subscription_status(self, user_id: UUID) -> dict:
        """Get user's current subscription status."""
        user = await self._get_user_by_id(user_id)

        current_tier = user.get_effective_tier()
        is_trial = (current_tier == "trial")
        subscription_active = is_subscription_active(user.subscription_expires_at)

        auto_renew_enabled = False
        if subscription_active:
            if user.subscription_auto_renew_enabled is None:
                auto_renew_enabled = True
            else:
                auto_renew_enabled = user.subscription_auto_renew_enabled

        return {
            "current_tier": current_tier,
            "is_trial": is_trial,
            "trial_expires_at": user.trial_expires_at,
            "subscription_expires_at": user.subscription_expires_at,
            "product_id": (
                self._tier_to_product_id(user.subscription_tier)
                if subscription_active
                else None
            ),
            "auto_renew_enabled": auto_renew_enabled,
        }

    async def process_app_store_notification(
        self,
        signed_payload: str,
        *,
        environment_name: str | None = None,
    ) -> dict:
        """Apply an App Store Server Notification v2 to the user record."""
        notification_payload = await verify_app_store_notification(
            signed_payload,
            environment_name=environment_name,
        )
        notification_data = self._coerce_notification(notification_payload)

        if notification_data.notification_type == "TEST":
            return {
                "status": "processed",
                "applied": False,
                "notification_type": "TEST",
                "subtype": notification_data.subtype,
                "reason": "test_notification",
            }

        user = await self._resolve_user_for_notification(notification_data)
        if user is None:
            return {
                "status": "ignored",
                "applied": False,
                "notification_type": notification_data.notification_type,
                "subtype": notification_data.subtype,
                "reason": "user_not_found",
            }

        applied = self._apply_notification_state(user, notification_data)
        if applied:
            await self.db.commit()
            await self.db.refresh(user)

        return {
            "status": "processed" if applied else "ignored",
            "applied": applied,
            "notification_type": notification_data.notification_type,
            "subtype": notification_data.subtype,
            "user_id": str(user.id),
            "current_tier": user.get_effective_tier(),
            "auto_renew_enabled": (
                user.subscription_auto_renew_enabled
                if user.subscription_auto_renew_enabled is not None
                else None
            ),
        }

    async def _get_user_by_id(self, user_id: UUID) -> User:
        result = await self.db.execute(
            select(User).where(User.id == user_id, User.deleted_at.is_(None))
        )
        user = result.scalar_one_or_none()

        if not user:
            raise ValueError("User not found")

        return user

    async def _resolve_user_for_notification(
        self,
        notification_data: VerifiedNotification,
    ) -> User | None:
        transaction_info = notification_data.transaction_info
        renewal_info = notification_data.renewal_info

        original_transaction_id = None
        if transaction_info:
            original_transaction_id = transaction_info.original_transaction_id
        elif renewal_info:
            original_transaction_id = renewal_info.original_transaction_id

        if original_transaction_id:
            result = await self.db.execute(
                select(User).where(
                    User.apple_original_transaction_id == original_transaction_id,
                    User.deleted_at.is_(None),
                )
            )
            user = result.scalar_one_or_none()
            if user is not None:
                return user

        if transaction_info and transaction_info.app_account_token:
            try:
                user_id = UUID(transaction_info.app_account_token)
            except ValueError:
                return None

            result = await self.db.execute(
                select(User).where(User.id == user_id, User.deleted_at.is_(None))
            )
            return result.scalar_one_or_none()

        return None

    def _validate_receipt_binding(
        self,
        *,
        receipt_data: VerifiedTransaction,
        user_id: UUID,
        request_transaction_id: str | None,
        request_product_id: str | None,
    ) -> None:
        if (
            request_transaction_id
            and receipt_data.transaction_id != request_transaction_id
        ):
            raise ValueError("Receipt transaction does not match request")

        if request_product_id and receipt_data.product_id != request_product_id:
            raise ValueError("Receipt product does not match request")

        app_account_token = receipt_data.app_account_token
        if not app_account_token:
            return

        try:
            bound_user_id = UUID(app_account_token)
        except ValueError as exc:
            raise ValueError("Receipt account binding is invalid") from exc

        if bound_user_id != user_id:
            raise ValueError("Receipt does not belong to current user")

    def _apply_notification_state(
        self,
        user: User,
        notification_data: VerifiedNotification,
    ) -> bool:
        transaction_info = notification_data.transaction_info
        renewal_info = notification_data.renewal_info
        applied = False

        if transaction_info:
            self._apply_transaction_state(
                user,
                transaction_info=transaction_info,
                raw_receipt=notification_data.signed_transaction_info,
                auto_renew_enabled=(
                    renewal_info.auto_renew_enabled
                    if renewal_info
                    else None
                ),
            )
            applied = True

        if renewal_info and renewal_info.auto_renew_enabled is not None:
            user.subscription_auto_renew_enabled = renewal_info.auto_renew_enabled
            applied = True

        handler = self._notification_handlers().get(notification_data.notification_type)
        if handler is not None:
            applied = handler(user, notification_data) or applied

        return applied

    def _apply_transaction_state(
        self,
        user: User,
        *,
        transaction_info: VerifiedTransaction,
        raw_receipt: str | None,
        auto_renew_enabled: bool | None,
    ) -> None:
        effective_expires_at = (
            transaction_info.revocation_date
            or transaction_info.expires_date
        )

        user.subscription_tier = transaction_info.subscription_tier
        user.subscription_expires_at = effective_expires_at
        user.apple_original_transaction_id = transaction_info.original_transaction_id
        if raw_receipt:
            user.apple_receipt_data = raw_receipt

        if auto_renew_enabled is not None:
            user.subscription_auto_renew_enabled = auto_renew_enabled

        if not transaction_info.is_trial:
            user.trial_expires_at = None

    def _coerce_transaction(
        self,
        payload: VerifiedTransaction | dict,
    ) -> VerifiedTransaction:
        if isinstance(payload, VerifiedTransaction):
            return payload
        return VerifiedTransaction.from_dict(payload)

    def _coerce_renewal(
        self,
        payload: VerifiedRenewalInfo | dict | None,
    ) -> VerifiedRenewalInfo | None:
        if payload is None:
            return None
        if isinstance(payload, VerifiedRenewalInfo):
            return payload
        return VerifiedRenewalInfo.from_dict(payload)

    def _coerce_notification(
        self,
        payload: VerifiedNotification | dict,
    ) -> VerifiedNotification:
        if isinstance(payload, VerifiedNotification):
            return payload

        transaction_info = payload.get("transaction_info")
        renewal_info = payload.get("renewal_info")
        return VerifiedNotification.from_dict(
            {
                **payload,
                "transaction_info": (
                    self._coerce_transaction(transaction_info)
                    if transaction_info is not None
                    else None
                ),
                "renewal_info": self._coerce_renewal(renewal_info),
            }
        )

    def _notification_handlers(
        self,
    ) -> dict[str, Callable[[User, VerifiedNotification], bool]]:
        return {
            "EXPIRED": self._handle_expired_notification,
            "GRACE_PERIOD_EXPIRED": self._handle_expired_notification,
            "REFUND": self._handle_refund_or_revoke_notification,
            "REVOKE": self._handle_refund_or_revoke_notification,
        }

    def _handle_expired_notification(
        self,
        user: User,
        notification: VerifiedNotification,
    ) -> bool:
        user.subscription_auto_renew_enabled = False
        if (
            notification.renewal_info
            and notification.renewal_info.grace_period_expires_date
        ):
            user.subscription_expires_at = (
                notification.renewal_info.grace_period_expires_date
            )
        else:
            user.subscription_expires_at = datetime.now(UTC)
        return True

    def _handle_refund_or_revoke_notification(
        self,
        user: User,
        notification: VerifiedNotification,
    ) -> bool:
        if notification.transaction_info is not None:
            return False
        user.subscription_auto_renew_enabled = False
        user.subscription_expires_at = datetime.now(UTC)
        return True

    def _tier_to_product_id(self, tier: str) -> str | None:
        """Map tier to product ID."""
        tier_map = {
            "basic": "com.readless.basic.monthly",
            "pro": "com.readless.pro.monthly",
        }
        return tier_map.get(tier)
