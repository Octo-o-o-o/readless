"""StoreKit 2 receipt and App Store notification verification utilities."""

from dataclasses import dataclass
from datetime import UTC, datetime
from functools import lru_cache
from pathlib import Path

from appstoreserverlibrary.models.AutoRenewStatus import AutoRenewStatus
from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.models.JWSRenewalInfoDecodedPayload import (
    JWSRenewalInfoDecodedPayload,
)
from appstoreserverlibrary.models.JWSTransactionDecodedPayload import (
    JWSTransactionDecodedPayload,
)
from appstoreserverlibrary.models.OfferType import OfferType
from appstoreserverlibrary.signed_data_verifier import (
    SignedDataVerifier,
    VerificationException,
)
from cryptography import x509
from cryptography.hazmat.primitives.serialization import Encoding
from fastapi import HTTPException

from app.config import settings

CERTIFICATE_MARKER = "-----BEGIN CERTIFICATE-----"
ROOT_CERTIFICATE_PATH = (
    Path(__file__).resolve().parents[1] / "certs" / "apple_root_certificates.txt"
)

# Product ID to subscription tier mapping
PRODUCT_TIER_MAP = {
    "com.readless.basic.monthly": "basic",
    "com.readless.pro.monthly": "pro",
}

_RECEIPT_FAIL_MSG = (
    "Subscription verification failed."
    " Please try 'Restore Purchases'"
    " or contact support."
)
_NOTIFICATION_FAIL_MSG = "App Store notification verification failed."


@dataclass(frozen=True)
class VerifiedTransaction:
    transaction_id: str
    original_transaction_id: str
    product_id: str
    subscription_tier: str
    purchase_date: datetime | None
    expires_date: datetime
    is_trial: bool
    transaction_type: str | None
    environment: str | None
    app_account_token: str | None
    revocation_date: datetime | None
    is_upgraded: bool

    @classmethod
    def from_dict(cls, payload: dict) -> "VerifiedTransaction":
        return cls(
            transaction_id=payload["transaction_id"],
            original_transaction_id=payload["original_transaction_id"],
            product_id=payload["product_id"],
            subscription_tier=payload["subscription_tier"],
            purchase_date=payload.get("purchase_date"),
            expires_date=payload["expires_date"],
            is_trial=payload.get("is_trial", False),
            transaction_type=payload.get("transaction_type"),
            environment=payload.get("environment"),
            app_account_token=payload.get("app_account_token"),
            revocation_date=payload.get("revocation_date"),
            is_upgraded=payload.get("is_upgraded", False),
        )


@dataclass(frozen=True)
class VerifiedRenewalInfo:
    original_transaction_id: str | None
    current_product_id: str | None
    auto_renew_product_id: str | None
    auto_renew_enabled: bool | None
    renewal_date: datetime | None
    grace_period_expires_date: datetime | None
    expiration_intent: str | None
    environment: str | None

    @classmethod
    def from_dict(cls, payload: dict) -> "VerifiedRenewalInfo":
        return cls(
            original_transaction_id=payload.get("original_transaction_id"),
            current_product_id=payload.get("current_product_id"),
            auto_renew_product_id=payload.get("auto_renew_product_id"),
            auto_renew_enabled=payload.get("auto_renew_enabled"),
            renewal_date=payload.get("renewal_date"),
            grace_period_expires_date=payload.get("grace_period_expires_date"),
            expiration_intent=payload.get("expiration_intent"),
            environment=payload.get("environment"),
        )


@dataclass(frozen=True)
class VerifiedNotification:
    notification_type: str
    subtype: str | None
    notification_uuid: str | None
    signed_date: datetime | None
    environment: str | None
    transaction_info: VerifiedTransaction | None
    renewal_info: VerifiedRenewalInfo | None
    signed_transaction_info: str | None
    signed_renewal_info: str | None

    @classmethod
    def from_dict(cls, payload: dict) -> "VerifiedNotification":
        transaction_info = payload.get("transaction_info")
        renewal_info = payload.get("renewal_info")
        return cls(
            notification_type=payload["notification_type"],
            subtype=payload.get("subtype"),
            notification_uuid=payload.get("notification_uuid"),
            signed_date=payload.get("signed_date"),
            environment=payload.get("environment"),
            transaction_info=(
                VerifiedTransaction.from_dict(transaction_info)
                if isinstance(transaction_info, dict)
                else transaction_info
            ),
            renewal_info=(
                VerifiedRenewalInfo.from_dict(renewal_info)
                if isinstance(renewal_info, dict)
                else renewal_info
            ),
            signed_transaction_info=payload.get("signed_transaction_info"),
            signed_renewal_info=payload.get("signed_renewal_info"),
        )


def _parse_environment(value: str) -> Environment:
    try:
        return Environment(value)
    except ValueError as exc:
        raise RuntimeError(
            f"Unsupported Apple App Store environment: {value}"
        ) from exc


@lru_cache(maxsize=1)
def _load_root_certificates() -> tuple[bytes, ...]:
    pem_data = ROOT_CERTIFICATE_PATH.read_text(encoding="utf-8").strip()
    certificates: list[bytes] = []

    for block in pem_data.split(CERTIFICATE_MARKER):
        block = block.strip()
        if not block:
            continue
        pem_certificate = f"{CERTIFICATE_MARKER}\n{block}\n".encode()
        der_certificate = x509.load_pem_x509_certificate(
            pem_certificate
        ).public_bytes(Encoding.DER)
        certificates.append(der_certificate)

    if not certificates:
        raise RuntimeError("Apple root certificates are missing")

    return tuple(certificates)


@lru_cache(maxsize=8)
def _build_transaction_verifier(environment_name: str) -> SignedDataVerifier:
    environment = _parse_environment(environment_name)
    app_apple_id = settings.apple_app_apple_id
    if environment == Environment.PRODUCTION and app_apple_id is None:
        # The official verifier requires a production appAppleId even though
        # signed transaction verification itself does not compare it.
        app_apple_id = 0

    return SignedDataVerifier(
        list(_load_root_certificates()),
        settings.apple_enable_online_checks,
        environment,
        settings.apple_bundle_id,
        app_apple_id,
    )


@lru_cache(maxsize=8)
def _build_notification_verifier(environment_name: str) -> SignedDataVerifier:
    environment = _parse_environment(environment_name)
    app_apple_id = settings.apple_app_apple_id
    if environment == Environment.PRODUCTION and app_apple_id is None:
        raise RuntimeError(
            "APPLE_APP_APPLE_ID must be configured for production "
            "App Store notifications."
        )

    return SignedDataVerifier(
        list(_load_root_certificates()),
        settings.apple_enable_online_checks,
        environment,
        settings.apple_bundle_id,
        app_apple_id,
    )


def _transaction_environment_candidates() -> tuple[Environment, ...]:
    configured = _parse_environment(settings.apple_app_store_environment)
    candidates: list[Environment] = [configured]

    if settings.apple_allow_test_environments:
        for extra in (
            Environment.SANDBOX,
            Environment.XCODE,
            Environment.LOCAL_TESTING,
        ):
            if extra not in candidates:
                candidates.append(extra)

    return tuple(candidates)


def _ms_to_datetime(value: int | None) -> datetime | None:
    if value is None:
        return None
    return datetime.fromtimestamp(value / 1000, tz=UTC)


def _notification_value(value) -> str | None:
    if value is None:
        return None
    return getattr(value, "value", value)


def _normalize_transaction(
    payload: JWSTransactionDecodedPayload,
) -> VerifiedTransaction:
    product_id = payload.productId
    subscription_tier = PRODUCT_TIER_MAP.get(product_id)
    if (
        not payload.transactionId
        or not product_id
        or not subscription_tier
        or payload.expiresDate is None
    ):
        raise HTTPException(status_code=400, detail=_RECEIPT_FAIL_MSG)

    expires_date = _ms_to_datetime(payload.expiresDate)
    if expires_date is None:
        raise HTTPException(status_code=400, detail=_RECEIPT_FAIL_MSG)

    return VerifiedTransaction(
        transaction_id=payload.transactionId,
        original_transaction_id=(
            payload.originalTransactionId or payload.transactionId
        ),
        product_id=product_id,
        subscription_tier=subscription_tier,
        purchase_date=_ms_to_datetime(payload.purchaseDate),
        expires_date=expires_date,
        is_trial=payload.offerType == OfferType.INTRODUCTORY_OFFER,
        transaction_type=_notification_value(payload.type),
        environment=_notification_value(payload.environment),
        app_account_token=payload.appAccountToken,
        revocation_date=_ms_to_datetime(payload.revocationDate),
        is_upgraded=payload.isUpgraded or False,
    )


def _normalize_renewal_info(
    payload: JWSRenewalInfoDecodedPayload,
) -> VerifiedRenewalInfo:
    auto_renew_enabled = None
    if payload.autoRenewStatus is not None:
        auto_renew_enabled = payload.autoRenewStatus == AutoRenewStatus.ON

    return VerifiedRenewalInfo(
        original_transaction_id=payload.originalTransactionId,
        current_product_id=payload.productId,
        auto_renew_product_id=payload.autoRenewProductId,
        auto_renew_enabled=auto_renew_enabled,
        renewal_date=_ms_to_datetime(payload.renewalDate),
        grace_period_expires_date=_ms_to_datetime(
            payload.gracePeriodExpiresDate
        ),
        expiration_intent=_notification_value(payload.expirationIntent),
        environment=_notification_value(payload.environment),
    )


async def verify_storekit_receipt(jws_receipt: str) -> VerifiedTransaction:
    """
    Verify StoreKit 2 JWS receipt and extract subscription information.

    Supports the configured App Store environment and, when explicitly
    enabled, Sandbox/Xcode/local testing receipts.
    """
    last_error: VerificationException | None = None

    try:
        for environment in _transaction_environment_candidates():
            try:
                payload = _build_transaction_verifier(
                    environment.value
                ).verify_and_decode_signed_transaction(jws_receipt)
                return _normalize_transaction(payload)
            except VerificationException as exc:
                last_error = exc

        raise HTTPException(status_code=400, detail=_RECEIPT_FAIL_MSG) from last_error
    except HTTPException:
        raise
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=_RECEIPT_FAIL_MSG) from exc


async def verify_app_store_notification(
    signed_payload: str,
    *,
    environment_name: str | None = None,
) -> VerifiedNotification:
    """Verify App Store Server Notifications v2 payload and nested JWS blobs."""
    environment_value = (
        environment_name or settings.apple_app_store_environment
    )

    try:
        notification = _build_notification_verifier(
            environment_value
        ).verify_and_decode_notification(signed_payload)
    except VerificationException as exc:
        raise HTTPException(status_code=400, detail=_NOTIFICATION_FAIL_MSG) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=_NOTIFICATION_FAIL_MSG) from exc

    transaction_info = None
    renewal_info = None
    data = notification.data
    verifier = _build_transaction_verifier(environment_value)

    try:
        if data and data.signedTransactionInfo:
            transaction_payload = verifier.verify_and_decode_signed_transaction(
                data.signedTransactionInfo
            )
            transaction_info = _normalize_transaction(transaction_payload)

        if data and data.signedRenewalInfo:
            renewal_payload = verifier.verify_and_decode_renewal_info(
                data.signedRenewalInfo
            )
            renewal_info = _normalize_renewal_info(renewal_payload)
    except VerificationException as exc:
        raise HTTPException(status_code=400, detail=_NOTIFICATION_FAIL_MSG) from exc

    return VerifiedNotification(
        notification_type=(
            _notification_value(notification.notificationType)
            or notification.rawNotificationType
        ),
        subtype=(
            _notification_value(notification.subtype) or notification.rawSubtype
        ),
        notification_uuid=notification.notificationUUID,
        signed_date=_ms_to_datetime(notification.signedDate),
        environment=(
            _notification_value(data.environment) if data else environment_value
        ),
        transaction_info=transaction_info,
        renewal_info=renewal_info,
        signed_transaction_info=(data.signedTransactionInfo if data else None),
        signed_renewal_info=(data.signedRenewalInfo if data else None),
    )


def is_subscription_active(expires_date: datetime | None) -> bool:
    """Check if subscription is currently active based on expiration date."""
    if not expires_date:
        return False
    if expires_date.tzinfo is None:
        expires_date = expires_date.replace(tzinfo=UTC)
    return expires_date > datetime.now(UTC)
