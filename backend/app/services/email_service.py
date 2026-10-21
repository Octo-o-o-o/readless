"""Email delivery helpers."""

from urllib.parse import urlencode

import httpx

from app.config import settings


class ResendEmailService:
    """Send transactional emails using Resend."""

    API_URL = "https://api.resend.com/emails"

    async def _send_email(
        self,
        *,
        to_email: str,
        subject: str,
        text_body: str,
        html_body: str,
        failure_message: str,
    ) -> None:
        api_key = settings.resend_api_key.strip()
        from_email = settings.resend_from_email.strip()

        if not api_key or not from_email:
            raise ValueError(
                "Email service is not configured."
                " Set RESEND_API_KEY and RESEND_FROM_EMAIL."
            )

        payload = {
            "from": from_email,
            "to": [to_email],
            "subject": subject,
            "text": text_body,
            "html": html_body,
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=10) as client:
            try:
                response = await client.post(
                    self.API_URL,
                    json=payload,
                    headers=headers,
                )
            except httpx.HTTPError as exc:
                raise ValueError(failure_message) from exc

        if response.status_code >= 400:
            raise ValueError(failure_message)

    async def send_login_code(self, to_email: str, code: str) -> None:
        """Send one-time login code email."""
        subject = "Your Readless verification code"
        text_body = (
            f"Your Readless verification code is: {code}\n\n"
            f"It expires in {settings.email_login_code_expire_minutes} minutes."
        )
        html_body = (
            "<p>Your Readless verification code is:</p>"
            f"<p style='font-size:24px;font-weight:700;letter-spacing:4px;'>{code}</p>"
            f"<p>It expires in {settings.email_login_code_expire_minutes} minutes.</p>"
        )

        await self._send_email(
            to_email=to_email,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
            failure_message=(
                "Failed to send verification code email."
                " Please try again."
            ),
        )

    async def send_verification_email(self, to_email: str, token: str) -> None:
        """Send account verification email."""
        verify_query = urlencode({"token": token})
        verification_url = (
            f"{settings.public_app_url.rstrip('/')}"
            f"/api/v1/auth/email/verify?{verify_query}"
        )
        subject = "Verify your Readless email"
        text_body = (
            "Welcome to Readless.\n\n"
            "Verify your email by opening this link:\n"
            f"{verification_url}\n\n"
            "If you did not create this account, you can ignore this email."
        )
        html_body = (
            "<p>Welcome to Readless.</p>"
            "<p>Verify your email by opening this link:</p>"
            f"<p><a href='{verification_url}'>{verification_url}</a></p>"
            "<p>If you did not create this account, you can ignore this email.</p>"
        )

        await self._send_email(
            to_email=to_email,
            subject=subject,
            text_body=text_body,
            html_body=html_body,
            failure_message=(
                "Failed to send verification email."
                " Please try again."
            ),
        )
