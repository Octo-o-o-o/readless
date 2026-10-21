"""Authentication API endpoints."""

import html
import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse
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
    ResendVerificationRequest,
    SendEmailCodeRequest,
    SendEmailCodeResponse,
    UserResponse,
    VerifyEmailCodeRequest,
    VerifyEmailRequest,
)
from app.services.auth_service import AuthService

router = APIRouter(prefix="/auth", tags=["authentication"])
logger = logging.getLogger(__name__)


def _verification_page(*, title: str, message: str, success: bool) -> HTMLResponse:
    """Render a small browser-friendly email verification status page."""
    accent = "#15803d" if success else "#b91c1c"
    title_text = html.escape(title)
    message_text = html.escape(message)
    homepage = html.escape(settings.public_app_url.rstrip("/"))

    page = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title_text}</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #09090b;
      --surface: #111827;
      --text: #f8fafc;
      --muted: #cbd5e1;
      --border: rgba(255, 255, 255, 0.12);
      --accent: {accent};
    }}
    @media (prefers-color-scheme: light) {{
      :root {{
        --bg: #f8fafc;
        --surface: #ffffff;
        --text: #0f172a;
        --muted: #475569;
        --border: rgba(15, 23, 42, 0.12);
      }}
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 24px;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background:
        radial-gradient(circle at top, rgba(21, 128, 61, 0.12), transparent 32%),
        var(--bg);
      color: var(--text);
    }}
    main {{
      width: min(100%, 520px);
      padding: 32px;
      border-radius: 24px;
      border: 1px solid var(--border);
      background: var(--surface);
      box-shadow: 0 24px 80px rgba(0, 0, 0, 0.28);
    }}
    .eyebrow {{
      display: inline-flex;
      align-items: center;
      gap: 10px;
      font-size: 13px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--muted);
    }}
    .dot {{
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: var(--accent);
      box-shadow: 0 0 0 6px color-mix(in srgb, var(--accent) 18%, transparent);
    }}
    h1 {{
      margin: 18px 0 12px;
      font-size: clamp(32px, 6vw, 42px);
      line-height: 1.05;
      letter-spacing: -0.04em;
    }}
    p {{
      margin: 0;
      font-size: 16px;
      line-height: 1.7;
      color: var(--muted);
    }}
    a {{
      display: inline-flex;
      margin-top: 24px;
      padding: 12px 18px;
      border-radius: 999px;
      background: var(--text);
      color: var(--bg);
      text-decoration: none;
      font-weight: 600;
    }}
  </style>
</head>
<body>
  <main>
    <div class="eyebrow"><span class="dot"></span>Readless</div>
    <h1>{title_text}</h1>
    <p>{message_text}</p>
    <a href="{homepage}">Open Readless</a>
  </main>
</body>
</html>
"""
    return HTMLResponse(
        content=page,
        status_code=200 if success else 400,
    )


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

        if settings.resend_api_key.strip() and settings.resend_from_email.strip():
            try:
                await auth_service.email_service.send_verification_email(
                    to_email=user.email,
                    token=verification_token,
                )
            except ValueError:
                logger.warning(
                    "Registration verification email delivery failed for %s",
                    user.email,
                )

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


@router.post("/email/verify", response_model=MessageResponse)
async def verify_email(
    request: VerifyEmailRequest,
    db: AsyncSession = Depends(get_db),
):
    """Verify a user's email address using a verification token."""
    auth_service = AuthService(db)

    try:
        await auth_service.verify_email(request.token)
        return MessageResponse(message="Email verified successfully.")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/email/verify", response_class=HTMLResponse, include_in_schema=False)
async def verify_email_browser(
    token: str = Query(..., min_length=1),
    db: AsyncSession = Depends(get_db),
):
    """Verify email from a browser-friendly link."""
    auth_service = AuthService(db)

    try:
        await auth_service.verify_email(token)
        return _verification_page(
            title="Email verified",
            message=(
                "Your Readless account is now verified."
                " You can close this tab and continue in the app."
            ),
            success=True,
        )
    except ValueError:
        return _verification_page(
            title="Verification failed",
            message=(
                "This verification link is invalid or has already been used."
                " Request a new verification email and try again."
            ),
            success=False,
        )


@router.post("/email/resend-verification", response_model=MessageResponse)
async def resend_verification_email(
    request: ResendVerificationRequest,
    db: AsyncSession = Depends(get_db),
):
    """Resend the email verification link for an existing account."""
    auth_service = AuthService(db)

    try:
        await auth_service.resend_verification_email(str(request.email))
        return MessageResponse(message="Verification email sent.")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


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
        access_token, refresh_token = await auth_service.refresh_access_token(
            refresh_token_str=request.refresh_token,
            rotate_refresh_token=request.rotate_refresh_token,
        )

        return RefreshTokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
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
