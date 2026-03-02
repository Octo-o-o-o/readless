"""Authentication API endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas.auth import (
    AppleSignInRequest,
    AppleSignInResponse,
    LoginRequest,
    LoginResponse,
    MessageResponse,
    RefreshTokenRequest,
    RefreshTokenResponse,
    RegisterRequest,
    RegisterResponse,
    UserResponse,
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


@router.post("/refresh", response_model=RefreshTokenResponse)
async def refresh_token(
    request: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    """Refresh access token."""
    auth_service = AuthService(db)

    try:
        access_token = await auth_service.refresh_access_token(
            refresh_token=request.refresh_token
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
        user, access_token, refresh_token, is_new_user = await auth_service.apple_signin(
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
    # TODO: Add get_current_user dependency
    db: AsyncSession = Depends(get_db),
):
    """Logout (revoke all refresh tokens)."""
    # TODO: Implement after auth middleware is added
    raise HTTPException(status_code=501, detail="Not implemented yet")
