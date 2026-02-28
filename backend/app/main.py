from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers.content import router as content_router
from app.routers.podcast import router as podcast_router
from app.routers.search import router as search_router

app = FastAPI(
    title="Readless API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(content_router)
app.include_router(podcast_router)
app.include_router(search_router)


@app.get("/health")
async def health() -> dict[str, str]:
    """Health-check endpoint for load balancers and orchestrators."""
    return {"status": "ok"}
