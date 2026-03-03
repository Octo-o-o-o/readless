"""JWT authentication dependency for FastAPI routes."""

from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import InvalidTokenError

from app.auth_utils import verify_access_token
from app.config import settings

security = HTTPBearer(auto_error=False)


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Security(security),
) -> str:
    """Verify local access token and return user ID (sub claim)."""
    if settings.disable_auth:
        return "dev-user"

    if credentials is None:
        raise HTTPException(401, "Missing authorization header")

    token = credentials.credentials
    try:
        payload = verify_access_token(token)
    except InvalidTokenError as e:
        message = str(e).lower()
        if "expired" in message:
            raise HTTPException(401, "Your session has expired. Please log in again.")
        raise HTTPException(401, "Invalid authentication token. Please log in again.")

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(401, "Invalid authentication token. Please log in again.")

    return user_id
