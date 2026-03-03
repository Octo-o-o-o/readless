"""Email delivery helpers."""

import httpx

from app.config import settings


class ResendEmailService:
    """Send transactional emails using Resend."""

    API_URL = "https://api.resend.com/emails"

    async def send_login_code(self, to_email: str, code: str) -> None:
        """Send one-time login code email."""
        api_key = settings.resend_api_key.strip()
        from_email = settings.resend_from_email.strip()

        if not api_key or not from_email:
            raise ValueError(
                "Email service is not configured. Set RESEND_API_KEY and RESEND_FROM_EMAIL."
            )

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
            response = await client.post(self.API_URL, json=payload, headers=headers)

        if response.status_code >= 400:
            raise ValueError("Failed to send verification code email. Please try again.")
