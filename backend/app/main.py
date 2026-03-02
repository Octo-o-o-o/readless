from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import settings
from app.routers.auth import router as auth_router
from app.routers.content import router as content_router
from app.routers.podcast import router as podcast_router
from app.routers.search import router as search_router
from app.routers.subscription import router as subscription_router
from app.routers.tags import router as tags_router


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


app = FastAPI(
    title="Readless API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Add HTTPS redirect middleware first
app.add_middleware(HTTPSRedirectMiddleware)

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


@app.get("/health")
async def health() -> dict[str, str]:
    """Health-check endpoint for load balancers and orchestrators."""
    return {"status": "ok"}
