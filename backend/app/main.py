import logging
from time import perf_counter
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.sessions import SessionMiddleware

from app.admin import create_admin
from app.config import settings
from app.database import get_engine
from app.routers.auth import router as auth_router
from app.routers.content import router as content_router
from app.routers.podcast import router as podcast_router
from app.routers.search import router as search_router
from app.routers.subscription import router as subscription_router
from app.routers.tags import router as tags_router

logger = logging.getLogger(__name__)


# Middleware to fix HTTPS protocol in redirects
class HTTPSRedirectMiddleware(BaseHTTPMiddleware):
    """Ensure redirects use HTTPS when behind a reverse proxy."""

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)

        # Fix redirect location to use HTTPS if forwarded from HTTPS
        if response.status_code in (307, 308) and "location" in response.headers:
            forwarded_proto = request.headers.get("x-forwarded-proto", "http")
            location = response.headers["location"]

            # Replace http:// with https:// if originally HTTPS
            if forwarded_proto == "https" and location.startswith("http://"):
                location = location.replace("http://", "https://", 1)
                response.headers["location"] = location

        return response


class OperationalHeadersMiddleware(BaseHTTPMiddleware):
    """Attach request tracing and baseline hardening headers."""

    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("x-request-id") or str(uuid4())
        request.state.request_id = request_id
        started_at = perf_counter()

        response = await call_next(request)
        response.headers.setdefault("X-Request-ID", request_id)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "same-origin")
        response.headers.setdefault(
            "X-Process-Time-Ms",
            f"{(perf_counter() - started_at) * 1000:.2f}",
        )
        return response


async def check_database_readiness() -> None:
    """Raise when the database cannot satisfy a basic readiness probe."""
    engine = get_engine()
    async with engine.connect() as connection:
        await connection.execute(text("SELECT 1"))


app = FastAPI(
    title="Readless API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Add session middleware for admin authentication
app.add_middleware(
    SessionMiddleware,
    secret_key=settings.jwt_secret_key,
    https_only=settings.admin_session_https_only,
    same_site=settings.admin_session_same_site,
    max_age=settings.admin_session_max_age_seconds,
)

# Add HTTPS redirect middleware first
app.add_middleware(HTTPSRedirectMiddleware)
app.add_middleware(OperationalHeadersMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(auth_router, prefix="/api/v1")
app.include_router(content_router)
app.include_router(podcast_router)
app.include_router(search_router)
app.include_router(subscription_router, prefix="/api/v1")
app.include_router(tags_router)

# Mount SQLAdmin
admin = create_admin(app)


@app.get("/health")
async def health() -> dict[str, str]:
    """Health-check endpoint for load balancers and orchestrators."""
    return {"status": "ok"}


@app.get("/health/ready")
async def health_ready() -> JSONResponse:
    """Readiness probe that confirms the API can reach its database."""
    try:
        await check_database_readiness()
    except Exception:
        logger.exception("Database readiness probe failed")
        return JSONResponse(
            status_code=503,
            content={
                "status": "degraded",
                "checks": {"database": "error"},
            },
        )

    return JSONResponse(
        content={
            "status": "ok",
            "checks": {"database": "ok"},
        }
    )
