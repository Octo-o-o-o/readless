"""Pydantic schemas for API requests and responses."""

from app.schemas.auth import (
    AppleSignInRequest,
    AppleSignInResponse,
    DeleteAccountRequest,
    ForgotPasswordRequest,
    LoginRequest,
    LoginResponse,
    MessageResponse,
    RefreshTokenRequest,
    RefreshTokenResponse,
    RegisterRequest,
    RegisterResponse,
    ResendVerificationRequest,
    ResetPasswordRequest,
    UserResponse,
    VerifyEmailRequest,
)
from app.schemas.content import (
    ContentCreateRequest,
    ContentResponse,
    ExpandRequest,
    FollowUpRequest,
    TextResponse,
)
from app.schemas.summary import (
    ContentSummary,
    OutlinePoint,
)
from app.schemas.tag import (
    ContentTagsUpdateRequest,
    TagCreateRequest,
    UserTagResponse,
)
from app.schemas.subscription import (
    SubscriptionStatusResponse,
    VerifyReceiptRequest,
    VerifyReceiptResponse,
)

__all__ = [
    # Auth schemas
    "RegisterRequest",
    "RegisterResponse",
    "LoginRequest",
    "LoginResponse",
    "RefreshTokenRequest",
    "RefreshTokenResponse",
    "AppleSignInRequest",
    "AppleSignInResponse",
    "UserResponse",
    "MessageResponse",
    "VerifyEmailRequest",
    "ResendVerificationRequest",
    "ForgotPasswordRequest",
    "ResetPasswordRequest",
    "DeleteAccountRequest",
    # Content schemas
    "ContentCreateRequest",
    "ContentResponse",
    "ExpandRequest",
    "FollowUpRequest",
    "TextResponse",
    # Summary schemas
    "ContentSummary",
    "OutlinePoint",
    # Tag schemas
    "TagCreateRequest",
    "UserTagResponse",
    "ContentTagsUpdateRequest",
    # Subscription schemas
    "VerifyReceiptRequest",
    "VerifyReceiptResponse",
    "SubscriptionStatusResponse",
]
