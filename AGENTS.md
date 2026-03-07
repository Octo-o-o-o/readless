# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Readless is an AI-powered macOS desktop app that ingests long-form content (articles, PDFs, text, images) and generates multi-level traceable summaries and AI podcasts. It consists of a native Swift/SwiftUI macOS client and a Python FastAPI backend.

## Production Environment

**Backend Server**: https://readless.cc
**Server**: root@172.245.55.158 (SSH port: 52941)
**Status**: ✅ Running in production (deployed 2026-03-01)

### Server Architecture
- Docker Compose with PostgreSQL 17 + FastAPI
- Nginx reverse proxy with Cloudflare Origin Certificate
- API: `127.0.0.1:8001` (internal) → `https://readless.cc` (public)
- Database: `127.0.0.1:5433` (internal PostgreSQL)

### Quick Health Check
```bash
curl https://readless.cc/health     # Should return {"status":"ok"}
curl https://readless.cc/docs       # API documentation
```

## Build & Run Commands

### Backend (Python/FastAPI)

#### Option 1: Use Production Server (Recommended)
Both development and production builds of the macOS app can connect to the production server. **No local backend needed**.

```bash
# Configure macOS app to use production
cd macos
./configure-backend.sh https://readless.cc

# Or manually
defaults write com.readless.app apiBaseURL "https://readless.cc"

# Verify configuration
defaults read com.readless.app apiBaseURL
```

#### Option 2: Run Local Backend (Optional)
Only needed for backend development or offline testing.

```bash
cd backend
pip install -e ".[dev]"               # Install dependencies
uvicorn app.main:app --reload          # Run dev server (http://localhost:8000)
docker-compose up -d --build           # Run with Docker (includes PostgreSQL)
docker-compose exec api alembic upgrade head  # Run DB migrations

# Configure macOS app to use localhost
defaults delete com.readless.app apiBaseURL  # Use default localhost:8000
```

### Backend Tests & Linting

```bash
cd backend
pytest tests/                          # Run all tests
pytest tests/test_pipeline.py -v       # Run single test file
ruff check .                           # Lint
ruff format .                          # Format
```

### macOS App (Swift/SwiftUI)

```bash
cd macos
swift build                            # Build
swift build -c release                 # Release build
swift run App                          # Run
swift test                             # Run tests

# The app will automatically use the configured backend:
# - If apiBaseURL is set: uses that URL (e.g., https://readless.cc)
# - If not set: defaults to http://localhost:8000
```

### Production Deployment

```bash
# Deploy to production server
cd /Users/wangyixiao/WorkSpace/readless

# 1. Package backend
tar --exclude='backend/venv' --exclude='backend/__pycache__' \
    -czf readless-backend.tar.gz backend/

# 2. Upload to server
scp -P 52941 readless-backend.tar.gz root@172.245.55.158:/root/

# 3. SSH and deploy
ssh -p 52941 root@172.245.55.158
cd /root && tar -xzf readless-backend.tar.gz
cd backend && bash deploy.sh

# 4. Verify deployment
curl https://readless.cc/health
```

See [DEPLOYMENT-RESULT.md](DEPLOYMENT-RESULT.md) for complete deployment documentation.

## Architecture

### Two-Part System

- **`backend/`** — Python FastAPI server with PostgreSQL, deployed via Docker
- **`macos/`** — Native SwiftUI macOS app, built with Swift Package Manager

The macOS client communicates with the backend over HTTPS using Bearer token auth (Clerk JWT).

### Backend Structure (`backend/app/`)

- **`main.py`** — FastAPI entry point with CORS and startup hooks
- **`config.py`** — Pydantic Settings loading from `.env`
- **`auth.py`** — Clerk JWT verification via `get_current_user_id()` dependency
- **`database.py`** — Async SQLAlchemy with `AsyncSession`
- **`routers/`** — API endpoints: content (`/api/v1/content`), podcast (`/api/v1/podcast`), search (`/api/v1/search`)
- **`services/`** — Business logic:
  - `pipeline.py` — Orchestrates extract → summarize → store
  - `extractor.py` — Extracts text from URLs (Trafilatura + Jina fallback), PDFs (pdfplumber), images (Tesseract OCR)
  - `summarizer.py` — Multi-level summaries via OpenAI (L0: one-liner, L1: outline, L2: expanded detail, L3: Q&A)
  - `podcast.py` — Script generation (OpenAI) + audio (ElevenLabs) + upload (Cloudflare R2)
  - `search_agent.py` — Agentic search: intent parsing → FTS → AI ranking → answer synthesis
  - `storage.py` — Cloudflare R2 object storage
- **`models/`** — SQLAlchemy ORM: Content, Paragraph, Podcast, Channel
- **`schemas/`** — Pydantic request/response models

### macOS App Structure (`macos/Sources/`)

SPM multi-target layout with explicit dependency graph:

- **`Core/`** — Domain models (`Content`, `OutlinePoint`), enums — zero dependencies
- **`Networking/`** — `APIClient` for backend HTTP calls — depends on Core
  - `APIClient.swift` — Configurable backend URL via UserDefaults (`apiBaseURL`)
  - Reads from `defaults read com.readless.app apiBaseURL`
  - Falls back to `http://localhost:8000` if not configured
- **`Storage/`** — GRDB SQLite local cache — depends on Core
- **`UI/`** — Reusable SwiftUI components (Theme, FloatingPanel) — depends on Core
- **`App/`** — Main executable — depends on all above
  - `Services/ContentManager.swift` — Central `@Observable` state coordinator bridging UI ↔ API
  - `Services/TextCaptureService.swift` — Captures text from foreground macOS apps
  - `Services/HotkeyService.swift` — Global keyboard shortcuts (KeyboardShortcuts package)
  - `Services/FolderWatchService.swift` — FSEvents folder monitoring
  - `Services/CommandBarService.swift` — Command Bar input processing and content import
  - `Views/ReaderView.swift` — Main summary display with keyboard navigation (j/k, Enter)
  - `ViewModels/` — MVVM view models using `@Observable`

### macOS Client Backend Configuration

The macOS app uses UserDefaults to determine which backend to connect to:

```swift
// APIClient automatically reads from UserDefaults
private static func getConfiguredBaseURL() -> URL {
    if let urlString = UserDefaults.standard.string(forKey: "apiBaseURL"),
       let url = URL(string: urlString) {
        print("[Readless] Using configured API base URL: \(urlString)")
        return url
    }
    // Fallback to localhost for development
    return URL(string: "http://localhost:8000")!
}
```

**Configuration Commands:**
```bash
# Use production server (recommended)
defaults write com.readless.app apiBaseURL "https://readless.cc"

# Use local server
defaults delete com.readless.app apiBaseURL

# Check current configuration
defaults read com.readless.app apiBaseURL
```

### Key Data Flow

```
User action (hotkey/paste) → TextCaptureService → ContentManager → APIClient
  → POST /api/v1/content → ProcessingPipeline (extract → summarize → store)
  → ContentResponse → ContentManager updates UI → ReaderView (L0 + L1)
  → User expands point → POST /expand → SummarizationService.expand_point (L2)
```

## Key Patterns

- **Backend services** use a lazy singleton pattern: module-level `_service` variable with `_get_service()` factory
- **OpenAI calls** enforce JSON-only responses (no markdown fences) via system prompts
- **Paragraph anchors** (¶1, ¶2, etc.) link outline points to source paragraphs for traceability
- **PostgreSQL FTS** uses TSVECTOR columns with GIN indexes for full-text search
- **macOS state** flows through `ContentManager` (@Observable) as the single source of truth
- **All DB operations** are async (`AsyncSession`) — never use sync SQLAlchemy calls
- **All backend tests** are designed to run without database, API keys, or network access

## User Tag System

The User Tag System allows users to organize and filter content using custom tags. Tags are AI-selected during summarization and can be managed manually.

### Architecture

**Database Schema:**
- `user_tags` - User's tag library (id, user_id, tag_name, content_count, created_at, updated_at, deleted_at)
- `content_tags` - Many-to-many relationships between content and tags (content_id, tag_id, user_id)
- Soft deletion: Tags are marked deleted (deleted_at) rather than hard-deleted
- Composite primary key: (content_id, tag_id) for content_tags

**Backend Flow:**
1. **Summarization** (`backend/app/services/summarizer.py`):
   - Fetches user's tag library from database
   - Includes available tags in AI prompt
   - AI selects 0-3 relevant tags from library
   - Validates AI-selected tags are from user's library

2. **Pipeline** (`backend/app/services/pipeline.py`):
   - Saves AI-selected tags to `content_tags` table
   - Batch-optimized tag lookup (no N+1 queries)
   - Logs when AI-selected tags aren't in library

3. **API Endpoints** (`backend/app/routers/tags.py`):
   - `GET /api/v1/tags` - List user's tags
   - `POST /api/v1/tags` - Create tag
   - `DELETE /api/v1/tags/{id}` - Soft-delete tag
   - `GET /api/v1/tags/content/{id}/tags` - Get content's tags
   - `PUT /api/v1/tags/content/{id}/tags` - Update content's tags
   - `GET /api/v1/tags/{id}/contents` - Filter content by tag

4. **Content Router** (`backend/app/routers/content.py`):
   - Returns tags via JOIN query (excludes soft-deleted)
   - Batch-fetches all tags in single query (optimized)

**macOS Frontend:**
- `Core/Models/Tag.swift` - UserTag model (Identifiable, Codable, Sendable)
- `Networking/APIClient.swift` - Tag API methods (fetchUserTags, createTag, deleteTag, updateContentTags, fetchContentsByTag)
- `App/Services/TagManager.swift` - @Observable service managing tag library and selection
- `App/Services/ContentManager.swift` - Tag filtering methods (filterByTag, clearTagFilter)
- `App/ReadlessApp.swift` - TagManager injected into SwiftUI environment

### Key Features

- **AI Tag Selection**: During summarization, AI automatically selects 0-3 relevant tags from user's library
- **Tag Validation**: Invalid AI-selected tags are filtered out
- **Soft Deletion**: Deleted tags remain in database but are excluded from queries
- **Performance**: Batch queries eliminate N+1 issues
- **User Isolation**: All tag operations respect user_id
- **Auto-Creation**: Tags are automatically created when assigned to content if they don't exist

### Testing

**Backend Tests (189 passing):**
- `tests/models/test_content_tag.py` - Model relationships
- `tests/routers/test_tags.py` - All 6 tag endpoints (37 tests)
- `tests/routers/test_content.py` - Tag fetching via JOIN (3 tests)
- `tests/test_summarizer.py` - AI tag selection (4 tests)
- `tests/test_pipeline.py` - Tag saving (2 tests)

**Test Coverage:**
- Tag CRUD operations
- Soft deletion
- User isolation
- AI tag selection with/without user tags
- Invalid tag filtering
- Database error handling
- N+1 query prevention

## External Services

| Service | Purpose | Config Key |
|---------|---------|------------|
| OpenAI | Summarization, search, podcast scripts | `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL` |
| ElevenLabs | Text-to-speech for podcasts | `ELEVENLABS_API_KEY` |
| Clerk | JWT authentication | `CLERK_SECRET_KEY` |
| Cloudflare R2 | Object storage (podcast audio) | `R2_ENDPOINT`, `R2_ACCESS_KEY`, `R2_SECRET_KEY`, `R2_BUCKET` |
| PostgreSQL 17 | Primary database | `DATABASE_URL` |

## Language Notes

- Content may be in Chinese or English. Summaries respect source language.
- L0 summary limit: ≤30 Chinese characters or ≤60 English characters.
- OCR supports Chinese + English via Tesseract (`chi_sim+eng`).

## Production Server Management

### Server Access
```bash
# SSH to production server
ssh -p 52941 root@172.245.55.158

# Navigate to backend directory
cd /root/backend
```

### Common Operations

**View Logs:**
```bash
# Real-time logs
docker compose -f docker-compose.prod.yml logs -f

# Last 50 lines of API logs
docker compose -f docker-compose.prod.yml logs --tail=50 api

# Last 50 lines of DB logs
docker compose -f docker-compose.prod.yml logs --tail=50 db
```

**Restart Services:**
```bash
# Restart API only
docker compose -f docker-compose.prod.yml restart api

# Restart all services
docker compose -f docker-compose.prod.yml restart

# Stop all services
docker compose -f docker-compose.prod.yml down

# Start all services
docker compose -f docker-compose.prod.yml up -d
```

**Check Status:**
```bash
# Container status
docker compose -f docker-compose.prod.yml ps

# Health check
curl http://127.0.0.1:8001/health

# Public health check
curl https://readless.cc/health
```

**Database Backup:**
```bash
# Create backup
docker compose -f docker-compose.prod.yml exec -T db \
  pg_dump -U readless readless | gzip > backup_$(date +%Y%m%d).sql.gz

# Restore backup
gunzip < backup_20260301.sql.gz | \
  docker compose -f docker-compose.prod.yml exec -T db \
  psql -U readless readless
```

**Update Deployment:**
```bash
# 1. On local machine: package and upload
cd /Users/wangyixiao/WorkSpace/readless
tar --exclude='backend/venv' --exclude='backend/__pycache__' \
    -czf readless-backend.tar.gz backend/
scp -P 52941 readless-backend.tar.gz root@172.245.55.158:/root/

# 2. On server: extract and redeploy
ssh -p 52941 root@172.245.55.158
cd /root && tar -xzf readless-backend.tar.gz
cd backend
docker compose -f docker-compose.prod.yml down
docker compose -f docker-compose.prod.yml up -d --build

# 3. Verify
curl https://readless.cc/health
```

### Deployment Files

- **`backend/docker-compose.prod.yml`** — Production Docker Compose configuration
  - API port: `127.0.0.1:8001:8000` (localhost only)
  - DB port: `127.0.0.1:5433:5432` (localhost only, avoids port conflicts)
  - Uses separate `readless` network
  - Includes health checks

- **`backend/deploy.sh`** — Automated deployment script
  - Builds Docker images
  - Starts database and waits for health
  - Runs migrations (if Alembic configured)
  - Starts API service
  - Verifies health endpoint

- **`backend/setup-nginx-cloudflare.sh`** — Nginx + Cloudflare SSL setup
  - Configures Cloudflare Origin Certificate
  - Sets up nginx reverse proxy
  - Configures real IP from Cloudflare
  - Enables HTTPS with HTTP redirect

### Environment Variables

Production environment variables are in `/root/backend/.env`:

```env
# Database (Docker internal network)
DATABASE_URL=postgresql+asyncpg://readless:readless@db:5432/readless
POSTGRES_PASSWORD=<strong-password>

# OpenAI API (using SiliconFlow)
OPENAI_API_KEY=sk-...
OPENAI_BASE_URL=https://api.siliconflow.cn/v1
OPENAI_MODEL=Pro/MiniMaxAI/MiniMax-M2.5

# Clerk Authentication
CLERK_SECRET_KEY=sk_test_...

# Cloudflare R2 Storage
R2_ENDPOINT=https://....r2.cloudflarestorage.com
R2_ACCESS_KEY=...
R2_SECRET_KEY=...
R2_BUCKET=readless

# ElevenLabs TTS
ELEVENLABS_API_KEY=sk_...

# CORS Configuration
CORS_ORIGINS=["https://readless.cc","http://localhost:3000"]

# Domain
DOMAIN=readless.cc
```

### Deployment Documentation

- **[DEPLOYMENT-RESULT.md](DEPLOYMENT-RESULT.md)** — Latest deployment report (2026-03-01)
- **[DEPLOYMENT-VERIFICATION.md](DEPLOYMENT-VERIFICATION.md)** — Configuration verification guide
- **[DEPLOYMENT.md](DEPLOYMENT.md)** — General deployment guide (Railway, VPS, etc.)
- **[QUICK_DEPLOY.md](QUICK_DEPLOY.md)** — 5-minute quick deployment guide
- **[DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)** — Step-by-step deployment checklist
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — Common issues and solutions
