"""Authentication API endpoints."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_id
from app.config import settings
from app.database import get_db
from app.models.user import User
from app.schemas.auth import (
    AppleSignInRequest,
    AppleSignInResponse,
    EmailCodeLoginResponse,
    LoginRequest,
    LoginResponse,
    MessageResponse,
    RefreshTokenRequest,
    RefreshTokenResponse,
    RegisterRequest,
    RegisterResponse,
    SendEmailCodeRequest,
    SendEmailCodeResponse,
    UserResponse,
    VerifyEmailCodeRequest,
)
from app.services.auth_service import AuthService

router = APIRouter(prefix="/auth", tags=["authentication"])


@router.post("/register", response_model=RegisterResponse, status_code=201)
async def register(
    request: RegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    """Register new user with email and password."""
    auth_service = AuthService(db)

    try:
        user, verification_token = await auth_service.register_user(
            email=request.email,
            password=request.password
        )

        # TODO: Send verification email with token (using Resend)
        # For now, just return success

        return RegisterResponse(
            message="Registration successful. Please verify your email.",
            user_id=user.id,
            trial_expires_at=user.trial_expires_at,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/login", response_model=LoginResponse)
async def login(
    request: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """Login with email and password."""
    auth_service = AuthService(db)

    try:
        user, access_token, refresh_token = await auth_service.login_user(
            email=request.email,
            password=request.password,
            device_name=None,  # TODO: Get from request header
            device_id=None,
        )

        return LoginResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=900,  # 15 minutes
            user=UserResponse.model_validate(user),
        )
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))


@router.post("/email/send-code", response_model=SendEmailCodeResponse)
async def send_email_login_code(
    request: SendEmailCodeRequest,
    db: AsyncSession = Depends(get_db),
):
    """Send one-time login code to email."""
    auth_service = AuthService(db)

    try:
        await auth_service.send_email_login_code(email=request.email)
        return SendEmailCodeResponse(
            message="Verification code sent.",
            expires_in=settings.email_login_code_expire_minutes * 60,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/email/verify-code", response_model=EmailCodeLoginResponse)
async def verify_email_login_code(
    request: VerifyEmailCodeRequest,
    db: AsyncSession = Depends(get_db),
):
    """Verify one-time login code and create session."""
    auth_service = AuthService(db)

    try:
        (
            user, access_token, refresh_token, is_new_user,
        ) = await auth_service.verify_email_login_code(
            email=request.email,
            code=request.code,
            device_name=None,
            device_id=None,
        )

        return EmailCodeLoginResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=900,
            user=UserResponse.model_validate(user),
            is_new_user=is_new_user,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/refresh", response_model=RefreshTokenResponse)
async def refresh_token(
    request: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    """Refresh access token."""
    auth_service = AuthService(db)

    try:
        access_token = await auth_service.refresh_access_token(
            refresh_token_str=request.refresh_token
        )

        return RefreshTokenResponse(
            access_token=access_token,
            expires_in=900,
        )
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))


@router.post("/apple-signin", response_model=AppleSignInResponse)
async def apple_signin(
    request: AppleSignInRequest,
    db: AsyncSession = Depends(get_db),
):
    """Apple Sign In."""
    auth_service = AuthService(db)

    try:
        (
            user, access_token, refresh_token, is_new_user,
        ) = await auth_service.apple_signin(
            identity_token=request.identity_token,
            device_name=None,  # TODO: Get from request header
            device_id=None,
        )

        return AppleSignInResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=900,
            user=UserResponse.model_validate(user),
            is_new_user=is_new_user,
        )
    except HTTPException:
        raise  # Pass through HTTP exceptions from apple_auth
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/logout", response_model=MessageResponse)
async def logout(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Logout (revoke all refresh tokens)."""
    auth_service = AuthService(db)
    try:
        await auth_service.logout_user(UUID(user_id))
        return MessageResponse(message="Logged out successfully.")
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))


@router.get("/me", response_model=UserResponse)
async def get_current_user(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
):
    """Get current authenticated user profile."""
    try:
        user_uuid = UUID(user_id)
    except ValueError:
        raise HTTPException(
            status_code=401,
            detail="Invalid session. Please log in again.",
        )

    result = await db.execute(
        select(User).where(User.id == user_uuid, User.deleted_at.is_(None))
    )
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(
            status_code=401,
            detail="User not found. Please log in again.",
        )

    return UserResponse.model_validate(user)
