"""Pydantic schemas for authentication endpoints."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


# ============ Request Schemas ============

class RegisterRequest(BaseModel):
    """Registration request."""
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    """Login request."""
    email: EmailStr
    password: str


class SendEmailCodeRequest(BaseModel):
    """Send one-time login code to email."""
    email: EmailStr


class VerifyEmailCodeRequest(BaseModel):
    """Verify one-time login code."""
    email: EmailStr
    code: str = Field(..., pattern=r"^\d{6}$")


class RefreshTokenRequest(BaseModel):
    """Refresh token request."""
    refresh_token: str


class VerifyEmailRequest(BaseModel):
    """Email verification request."""
    token: str


class ResendVerificationRequest(BaseModel):
    """Resend verification email request."""
    email: EmailStr


class ForgotPasswordRequest(BaseModel):
    """Forgot password request."""
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    """Password reset request."""
    token: str
    new_password: str


class AppleSignInRequest(BaseModel):
    """Apple Sign In request."""
    identity_token: str
    authorization_code: str | None = None
    user_info: dict | None = None


class DeleteAccountRequest(BaseModel):
    """Account deletion confirmation."""
    confirmation: str = Field(..., pattern="^DELETE$")


# ============ Response Schemas ============

class UserResponse(BaseModel):
    """User information in responses."""
    id: UUID
    email: str | None
    subscription_tier: str
    trial_expires_at: datetime | None
    subscription_expires_at: datetime | None
    email_verified: bool
    created_at: datetime

    class Config:
        from_attributes = True


class RegisterResponse(BaseModel):
    """Registration response."""
    message: str
    user_id: UUID
    trial_expires_at: datetime


class SendEmailCodeResponse(BaseModel):
    """Send email code response."""
    message: str
    expires_in: int


class LoginResponse(BaseModel):
    """Login response with tokens."""
    access_token: str
    refresh_token: str
    expires_in: int
    user: UserResponse


class EmailCodeLoginResponse(LoginResponse):
    """Email code login response."""
    is_new_user: bool


class RefreshTokenResponse(BaseModel):
    """Refresh token response."""
    access_token: str
    expires_in: int


class AppleSignInResponse(BaseModel):
    """Apple Sign In response."""
    access_token: str
    refresh_token: str
    expires_in: int
    user: UserResponse
    is_new_user: bool


class MessageResponse(BaseModel):
    """Generic message response."""
    message: str
