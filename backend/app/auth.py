"""Clerk JWT authentication middleware for FastAPI.

Verifies Clerk-issued JWTs locally using JWKS (JSON Web Key Sets) fetched
from Clerk's well-known endpoint, instead of making a remote API call on
every request.
"""

import asyncio
import time

import httpx
import jwt as pyjwt
from fastapi import HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from app.config import settings

security = HTTPBearer()

# Cached JWKS to avoid fetching on every request.
_jwks_cache: dict | None = None
_jwks_fetched_at: float = 0
_jwks_lock = asyncio.Lock()
_JWKS_TTL = 3600  # Re-fetch JWKS every hour


async def _get_jwks() -> dict:
    """Fetch and cache Clerk's JWKS (public keys for JWT verification)."""
    global _jwks_cache, _jwks_fetched_at
    now = time.time()
    if _jwks_cache and (now - _jwks_fetched_at) < _JWKS_TTL:
        return _jwks_cache
    async with _jwks_lock:
        # Re-check after acquiring lock (another coroutine may have refreshed)
        now = time.time()
        if _jwks_cache and (now - _jwks_fetched_at) < _JWKS_TTL:
            return _jwks_cache
        try:
            async with httpx.AsyncClient() as client:
                resp = await client.get(
                    f"https://{settings.clerk_domain}/.well-known/jwks.json",
                    timeout=10,
                )
                resp.raise_for_status()
                _jwks_cache = resp.json()
                _jwks_fetched_at = now
                return _jwks_cache
        except httpx.HTTPError as e:
            if _jwks_cache:
                return _jwks_cache  # Use stale cache on fetch failure
            raise HTTPException(503, f"Failed to fetch Clerk JWKS: {e}")


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Security(security),
) -> str:
    """Verify Clerk JWT locally and return user ID (sub claim)."""
    token = credentials.credentials
    try:
        jwks = await _get_jwks()
        # Decode the JWT header to find the key ID (kid)
        unverified = pyjwt.get_unverified_header(token)
        kid = unverified.get("kid")
        if not kid:
            raise HTTPException(401, "Token missing key ID")

        # Find the matching public key in JWKS
        public_key = None
        for key_data in jwks.get("keys", []):
            if key_data.get("kid") == kid:
                public_key = pyjwt.algorithms.RSAAlgorithm.from_jwk(key_data)
                break

        if not public_key:
            # Invalidate cache and retry once in case keys rotated
            global _jwks_fetched_at
            _jwks_fetched_at = 0
            jwks = await _get_jwks()
            for key_data in jwks.get("keys", []):
                if key_data.get("kid") == kid:
                    public_key = pyjwt.algorithms.RSAAlgorithm.from_jwk(key_data)
                    break

        if not public_key:
            raise HTTPException(401, "No matching key found")

        payload = pyjwt.decode(
            token,
            public_key,
            algorithms=["RS256"],
            options={"verify_aud": False},
        )
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(401, "Token missing user ID")
        return user_id

    except pyjwt.ExpiredSignatureError:
        raise HTTPException(401, "Token expired")
    except pyjwt.InvalidTokenError as e:
        raise HTTPException(401, f"Invalid token: {e}")
