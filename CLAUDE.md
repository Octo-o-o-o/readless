# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Readless is an AI-powered macOS desktop app that ingests long-form content (articles, PDFs, text, images) and generates multi-level traceable summaries and AI podcasts. It consists of a native Swift/SwiftUI macOS client and a Python FastAPI backend.

## Build & Run Commands

### Backend (Python/FastAPI)

```bash
cd backend
pip install -e ".[dev]"               # Install dependencies
uvicorn app.main:app --reload          # Run dev server (http://localhost:8000)
docker-compose up -d --build           # Run with Docker (includes PostgreSQL)
docker-compose exec api alembic upgrade head  # Run DB migrations
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
```

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
- **`Storage/`** — GRDB SQLite local cache — depends on Core
- **`UI/`** — Reusable SwiftUI components (Theme, FloatingPanel) — depends on Core
- **`App/`** — Main executable — depends on all above
  - `Services/ContentManager.swift` — Central `@Observable` state coordinator bridging UI ↔ API
  - `Services/TextCaptureService.swift` — Captures text from foreground macOS apps
  - `Services/HotkeyService.swift` — Global keyboard shortcuts (KeyboardShortcuts package)
  - `Services/FolderWatchService.swift` — FSEvents folder monitoring
  - `Views/ReaderView.swift` — Main summary display with keyboard navigation (j/k, Enter)
  - `ViewModels/` — MVVM view models using `@Observable`

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
