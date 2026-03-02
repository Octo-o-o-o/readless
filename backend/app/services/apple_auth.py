"""Apple Sign In authentication utilities."""

import jwt
from fastapi import HTTPException
from jwt import PyJWKClient

from app.config import settings

# Apple's JWKS endpoint for public keys
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"


async def verify_apple_identity_token(identity_token: str) -> dict:
    """
    Verify Apple identity token (JWT) and extract user information.

    Args:
        identity_token: JWT token from Apple Sign In

    Returns:
        dict with:
            - apple_id: User's Apple ID (sub claim)
            - email: User's email (if provided)
            - email_verified: Whether email is verified by Apple

    Raises:
        HTTPException: If token is invalid or verification fails
    """
    try:
        # Fetch Apple's public keys
        jwks_client = PyJWKClient(APPLE_JWKS_URL, cache_keys=True)
        signing_key = jwks_client.get_signing_key_from_jwt(identity_token)

        # Decode and verify the token
        payload = jwt.decode(
            identity_token,
            signing_key.key,
            algorithms=["RS256"],
            audience=settings.apple_bundle_id,  # Your app's bundle ID
            issuer="https://appleid.apple.com",  # Apple's issuer
            options={
                "verify_signature": True,
                "verify_exp": True,
                "verify_aud": True,
                "verify_iss": True,
            }
        )

        # Extract user information
        apple_id = payload.get("sub")
        email = payload.get("email")
        email_verified = payload.get("email_verified", "false") == "true"

        if not apple_id:
            raise HTTPException(
                status_code=400,
                detail="Invalid identity token: missing subject claim"
            )

        return {
            "apple_id": apple_id,
            "email": email,
            "email_verified": email_verified,
        }

    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=401,
            detail="Apple identity token has expired"
        )
    except jwt.InvalidAudienceError:
        raise HTTPException(
            status_code=401,
            detail="Invalid identity token: audience mismatch"
        )
    except jwt.InvalidIssuerError:
        raise HTTPException(
            status_code=401,
            detail="Invalid identity token: issuer mismatch"
        )
    except jwt.PyJWTError as e:
        raise HTTPException(
            status_code=401,
            detail=f"Invalid Apple identity token: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to verify Apple identity token: {str(e)}"
        )
