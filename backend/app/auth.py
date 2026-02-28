"""Clerk JWT authentication middleware for FastAPI."""

from fastapi import HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import httpx

from app.config import settings

security = HTTPBearer()


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Security(security),
) -> str:
    """Verify Clerk JWT and return user ID."""
    token = credentials.credentials
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(
                "https://api.clerk.com/v1/sessions/verify",
                headers={
                    "Authorization": f"Bearer {settings.clerk_secret_key}",
                    "Content-Type": "application/json",
                },
                params={"token": token},
            )
            if resp.status_code != 200:
                raise HTTPException(401, "Invalid token")
            data = resp.json()
            return data["user_id"]
    except httpx.HTTPError:
        raise HTTPException(401, "Authentication failed")
