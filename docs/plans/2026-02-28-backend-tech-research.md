# Readless Backend Technology Research

Date: 2026-02-28
Status: Research

---

## 1. Backend Framework: Recommendation = Python (FastAPI)

### Comparison Matrix

| Criteria | FastAPI (Python) | Hono/Bun (TypeScript) | Go (net/http / Gin) |
|---|---|---|---|
| AI library ecosystem | Excellent (native Anthropic SDK, Pydantic) | Good (Anthropic TS SDK) | Fair (community libs) |
| Raw throughput (req/s) | ~5,000-10,000 | ~20,000-40,000 | ~50,000-100,000+ |
| Structured output support | Best (Pydantic models -> Claude structured outputs) | Good (Zod schemas) | Manual JSON marshaling |
| Content extraction libs | Trafilatura, BeautifulSoup, pdfplumber | Readability.js (native), Cheerio | Limited, mostly bindings |
| Type safety | Good (type hints + Pydantic) | Excellent (TypeScript) | Excellent (compiled) |
| Developer velocity | Highest for this use case | High | Medium |
| Async I/O | Native (asyncio + httpx) | Native (Bun/Node event loop) | Native (goroutines) |
| Deployment simplicity | High (uvicorn, Docker) | High (Bun single binary) | Highest (static binary) |

### Why FastAPI Wins for Readless

**The bottleneck is not the framework -- it is the AI API call latency.** Every Readless request spends 2-10 seconds waiting on Claude API responses and 1-5 seconds on content extraction. The difference between 5K and 100K req/s on the framework itself is irrelevant when your actual throughput is gated by external API calls at ~0.1-1 req/s per user request.

FastAPI is the right choice because:

1. **Claude structured outputs use Pydantic natively.** The Anthropic Python SDK provides `client.beta.messages.parse()` which accepts Pydantic models directly -- the exact same models that define your API response schemas. One model definition serves both Claude output parsing and API response serialization.

2. **Trafilatura is Python-native** and is the highest-performing content extractor (F1 0.937). No subprocess calls or FFI needed.

3. **Async-first for I/O-bound orchestration.** FastAPI on asyncio + httpx means you can fire Claude API calls, content extraction, and database queries concurrently with `asyncio.gather()`.

4. **pdfplumber, pytesseract, Pillow** for PDF/image/OCR processing are all Python-native.

5. **SQLAlchemy async + asyncpg** for PostgreSQL -- mature, well-documented.

### Recommended Stack

```
Python 3.12+
FastAPI 0.115+
uvicorn (ASGI server)
Pydantic v2 (data models)
httpx (async HTTP client)
anthropic (official Claude SDK)
sqlalchemy[asyncio] + asyncpg (PostgreSQL)
trafilatura (content extraction)
pdfplumber (PDF extraction)
boto3 (Cloudflare R2 via S3 API)
elevenlabs (official ElevenLabs SDK)
python-jose (JWT tokens)
```

### Project Structure

```
readless-api/
├── app/
│   ├── main.py                  # FastAPI app, lifespan, middleware
│   ├── config.py                # Settings via pydantic-settings
│   ├── models/
│   │   ├── db.py                # SQLAlchemy ORM models
│   │   ├── schemas.py           # Pydantic request/response schemas
│   │   └── claude_schemas.py    # Pydantic models for Claude structured output
│   ├── routers/
│   │   ├── content.py           # POST /content, GET /content/{id}
│   │   ├── summary.py           # GET /content/{id}/summary?level=L1
│   │   ├── podcast.py           # POST /content/{id}/podcast
│   │   ├── search.py            # POST /search
│   │   └── auth.py              # POST /auth/login, /auth/register
│   ├── services/
│   │   ├── extraction.py        # Content extraction orchestrator
│   │   ├── summarizer.py        # Claude API multi-level summarization
│   │   ├── podcast.py           # Podcast script + ElevenLabs audio
│   │   ├── search_agent.py      # Agentic search over knowledge base
│   │   └── storage.py           # R2 upload/download
│   ├── core/
│   │   ├── auth.py              # JWT creation/validation
│   │   ├── database.py          # Async engine, session factory
│   │   └── background.py        # Background task runner
│   └── workers/
│       ├── processor.py         # Content processing pipeline
│       └── rss_poller.py        # RSS/email polling (Phase 2)
├── alembic/                     # Database migrations
├── tests/
├── Dockerfile
├── pyproject.toml
└── .env.example
```

### Core App Skeleton

```python
# app/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.database import engine, Base
from app.routers import content, summary, podcast, search, auth

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: create tables (use Alembic in production)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    # Shutdown: dispose engine
    await engine.dispose()

app = FastAPI(title="Readless API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Lock down in production
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/auth", tags=["auth"])
app.include_router(content.router, prefix="/content", tags=["content"])
app.include_router(summary.router, prefix="/content", tags=["summary"])
app.include_router(podcast.router, prefix="/content", tags=["podcast"])
app.include_router(search.router, prefix="/search", tags=["search"])
```

---

## 2. Content Extraction: Recommendation = Trafilatura (primary) + Jina Reader (fallback)

### Comparison

| Tool | F1 Score | Precision | Recall | Language | Hosting | Cost |
|---|---|---|---|---|---|---|
| Trafilatura | 0.937 | 0.978 | 0.920 | Python | Self-hosted | Free |
| Mozilla Readability | ~0.93 | ~0.95 | 0.929 | JS (Node) | Self-hosted | Free |
| Jina Reader API | ~0.93 | ~0.95 | ~0.92 | API | Cloud | Free 10M tokens, then ~$0.02/M tokens |
| Newspaper3k | ~0.85 | ~0.88 | ~0.83 | Python | Self-hosted | Free (unmaintained) |

### Recommended Strategy: Tiered Extraction

```python
# app/services/extraction.py
import trafilatura
import httpx
from dataclasses import dataclass

@dataclass
class ExtractedContent:
    title: str
    text: str
    author: str | None
    date: str | None
    source_url: str
    extraction_method: str

async def extract_from_url(url: str) -> ExtractedContent:
    """
    Tiered extraction strategy:
    1. Trafilatura (fast, free, high quality)
    2. Jina Reader API (fallback for JS-heavy pages)
    """
    # Tier 1: Trafilatura
    downloaded = trafilatura.fetch_url(url)
    if downloaded:
        result = trafilatura.extract(
            downloaded,
            include_comments=False,
            include_tables=True,
            output_format="txt",
            with_metadata=True,
        )
        if result and len(result) > 100:  # Minimum viable extraction
            metadata = trafilatura.extract(
                downloaded, output_format="xmltei", with_metadata=True
            )
            return ExtractedContent(
                title=_parse_title(metadata) or url,
                text=result,
                author=_parse_author(metadata),
                date=_parse_date(metadata),
                source_url=url,
                extraction_method="trafilatura",
            )

    # Tier 2: Jina Reader API (handles JS-rendered pages)
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"https://r.jina.ai/{url}",
            headers={
                "Accept": "application/json",
                "X-Return-Format": "text",
            },
            timeout=30.0,
        )
        if resp.status_code == 200:
            data = resp.json()
            return ExtractedContent(
                title=data.get("title", url),
                text=data.get("content", ""),
                author=data.get("author"),
                date=data.get("publishedTime"),
                source_url=url,
                extraction_method="jina_reader",
            )

    raise ExtractionError(f"Failed to extract content from {url}")
```

### Why This Strategy

- **Trafilatura first**: Free, no API dependency, fastest (local processing), highest precision (0.978). Works for 90%+ of standard web pages.
- **Jina Reader fallback**: Handles JavaScript-heavy SPAs that Trafilatura cannot render. Uses Puppeteer under the hood. Free tier gives 10M tokens/month -- more than enough for a startup.
- **No Readability.js**: Would require a Node.js subprocess or separate service. Trafilatura matches or exceeds its quality in Python natively.

### PDF and Image Extraction

```python
import pdfplumber
from PIL import Image
import pytesseract

def extract_from_pdf(file_path: str) -> str:
    """Extract text from PDF, falling back to OCR for scanned pages."""
    texts = []
    with pdfplumber.open(file_path) as pdf:
        for page in pdf.pages:
            text = page.extract_text()
            if text and len(text.strip()) > 50:
                texts.append(text)
            else:
                # Scanned page -- OCR fallback
                img = page.to_image(resolution=300).original
                texts.append(pytesseract.image_to_string(img))
    return "\n\n".join(texts)

def extract_from_image(file_path: str) -> str:
    """OCR an image file."""
    img = Image.open(file_path)
    return pytesseract.image_to_string(img)
```

---

## 3. Claude API for Multi-Level Summarization

### Structured Output with Pydantic (November 2025 Feature)

Claude now supports **guaranteed JSON schema compliance** via structured outputs. This is ideal for Readless's multi-level summary format.

**Required header**: `anthropic-beta: structured-outputs-2025-11-13`
**Supported models**: Claude Sonnet 4.5, Claude Opus 4.1

### Pydantic Models for Readless Summaries

```python
# app/models/claude_schemas.py
from pydantic import BaseModel, Field

class L1Point(BaseModel):
    """A single outline point in the L1 summary."""
    index: int = Field(description="Point number, starting from 1")
    text: str = Field(
        description="The outline point text, 15-30 characters",
        max_length=60,
    )
    anchor_ids: list[int] = Field(
        description="List of paragraph anchor IDs this point references, e.g. [3, 7]"
    )

class ContentSummary(BaseModel):
    """Multi-level summary of a content item."""
    l0_summary: str = Field(
        description="One-line summary, max 30 characters",
        max_length=60,
    )
    l1_outline: list[L1Point] = Field(
        description="3-5 structured outline points, each with source citations",
        min_length=2,
        max_length=7,
    )
    tags: list[str] = Field(
        description="3-8 topic tags extracted from the content",
        min_length=1,
        max_length=10,
    )
    keywords: list[str] = Field(
        description="5-15 important keywords for search indexing",
        min_length=3,
        max_length=20,
    )
    language: str = Field(
        description="ISO 639-1 language code of the content, e.g. 'en', 'zh'"
    )

class L2Expansion(BaseModel):
    """Detailed expansion of a single L1 point."""
    point_index: int
    detail_paragraphs: list[str] = Field(
        description="2-3 paragraphs of detailed explanation"
    )
    cited_anchors: list[int] = Field(
        description="All paragraph anchor IDs cited in the expansion"
    )

class L3Answer(BaseModel):
    """Answer to a follow-up question with sentence-level citations."""
    answer: str = Field(description="Direct answer to the question")
    cited_anchors: list[int] = Field(
        description="Paragraph anchor IDs supporting this answer"
    )
    cited_sentences: list[str] = Field(
        description="Exact sentences from the original text that support the answer"
    )
    confidence: float = Field(
        description="Confidence score 0-1 that the answer is supported by the source",
        ge=0.0,
        le=1.0,
    )
```

### Summarization Service

```python
# app/services/summarizer.py
import anthropic
from app.models.claude_schemas import ContentSummary, L2Expansion, L3Answer

client = anthropic.Anthropic()

def _segment_text(text: str) -> list[dict]:
    """Split text into paragraphs with anchor IDs."""
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    return [
        {"anchor_id": i + 1, "text": para}
        for i, para in enumerate(paragraphs)
    ]

async def generate_summary(
    title: str,
    text: str,
    source_url: str,
) -> tuple[list[dict], ContentSummary]:
    """Generate L0+L1 summary with source tracing."""
    segments = _segment_text(text)
    numbered_text = "\n\n".join(
        f"[paragraph {s['anchor_id']}] {s['text']}" for s in segments
    )

    response = client.beta.messages.parse(
        model="claude-sonnet-4-5-20250514",
        max_tokens=2048,
        betas=["structured-outputs-2025-11-13"],
        system=(
            "You are a precise content summarizer. You MUST cite source "
            "paragraphs using their [paragraph N] numbers. Every claim in "
            "your outline must reference at least one source paragraph. "
            "Match the language of the original content."
        ),
        messages=[
            {
                "role": "user",
                "content": (
                    f"Title: {title}\n"
                    f"Source: {source_url}\n\n"
                    f"--- CONTENT WITH PARAGRAPH NUMBERS ---\n\n"
                    f"{numbered_text}\n\n"
                    f"--- INSTRUCTIONS ---\n"
                    f"Generate a multi-level summary of this content. "
                    f"The l0_summary must be <= 30 characters. "
                    f"The l1_outline must have 3-5 points, each 15-30 characters, "
                    f"each citing specific paragraph numbers via anchor_ids. "
                    f"Extract relevant tags and keywords for search indexing."
                ),
            }
        ],
        response_model=ContentSummary,
    )

    return segments, response.parsed_output

async def expand_point(
    segments: list[dict],
    l1_point: dict,
    full_summary: dict,
) -> L2Expansion:
    """Generate L2 detailed expansion for a specific L1 point."""
    # Build context with the relevant source paragraphs
    relevant_ids = l1_point["anchor_ids"]
    relevant_text = "\n\n".join(
        f"[paragraph {s['anchor_id']}] {s['text']}"
        for s in segments
        if s["anchor_id"] in relevant_ids
    )

    response = client.beta.messages.parse(
        model="claude-sonnet-4-5-20250514",
        max_tokens=1024,
        betas=["structured-outputs-2025-11-13"],
        system=(
            "You are expanding a summary point with detailed explanation. "
            "Cite specific paragraph numbers. Match the source language."
        ),
        messages=[
            {
                "role": "user",
                "content": (
                    f"Original outline:\n{full_summary}\n\n"
                    f"Point to expand: {l1_point['text']}\n\n"
                    f"Relevant source paragraphs:\n{relevant_text}\n\n"
                    f"Write 2-3 paragraphs expanding this point with citations."
                ),
            }
        ],
        response_model=L2Expansion,
    )
    return response.parsed_output

async def answer_followup(
    segments: list[dict],
    question: str,
    context_point: dict | None = None,
) -> L3Answer:
    """Answer a follow-up question with sentence-level citations."""
    all_text = "\n\n".join(
        f"[paragraph {s['anchor_id']}] {s['text']}" for s in segments
    )

    response = client.beta.messages.parse(
        model="claude-sonnet-4-5-20250514",
        max_tokens=1024,
        betas=["structured-outputs-2025-11-13"],
        system=(
            "Answer the user's question based ONLY on the provided source text. "
            "Cite specific paragraphs and quote exact sentences. "
            "If the answer is not in the source, say so and set confidence to 0. "
            "Match the source language."
        ),
        messages=[
            {
                "role": "user",
                "content": (
                    f"Source text:\n{all_text}\n\n"
                    f"{'Context: ' + str(context_point) if context_point else ''}\n\n"
                    f"Question: {question}"
                ),
            }
        ],
        response_model=L3Answer,
    )
    return response.parsed_output
```

### Cost Estimation

Using Claude Sonnet 4.5 ($3/M input, $15/M output tokens):
- Average article: ~3,000 words -> ~4,000 input tokens
- L0+L1 summary output: ~500 tokens
- **Per-article L1 summary cost: ~$0.02**
- L2 expansion: ~$0.01 per point
- L3 Q&A: ~$0.01 per question
- **Total per article (L0+L1+L2 for all points): ~$0.06-0.08**

At $9.99/mo Pro tier with ~100 articles/month: ~$6-8 in Claude API costs. Viable margin.

### Performance Note

First request with a new schema incurs 100-300ms compilation overhead. The grammar is then cached by Anthropic for 24 hours. For production, consider warming the cache on deployment by sending a dummy request.

---

## 4. PostgreSQL Full-Text Search

### Why PostgreSQL FTS Is Sufficient (No Vector DB Needed)

Readless content is **already richly structured at ingestion time**:
- L0 summary (short text, highly searchable)
- L1 outline points (structured, keyword-dense)
- Tags and keywords (extracted by Claude)
- Full text (indexed via tsvector)

This is a **structured retrieval** problem, not a semantic similarity problem. PostgreSQL FTS with the Search Agent (which uses Claude for intent parsing and re-ranking) provides everything needed.

### Schema Setup

```sql
-- Content table with full-text search
CREATE TABLE content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),

    -- Source metadata
    title TEXT NOT NULL,
    source_url TEXT,
    source_type TEXT NOT NULL,  -- 'url', 'pdf', 'text', 'image'
    source_channel TEXT,        -- 'manual', 'folder_watch', 'email', 'rss'
    source_app_name TEXT,       -- e.g. 'Google Chrome'
    source_app_bundle_id TEXT,  -- e.g. 'com.google.Chrome'

    -- AI-generated content
    l0_summary TEXT NOT NULL,
    l1_outline JSONB NOT NULL,  -- [{index, text, anchor_ids}]
    tags TEXT[] NOT NULL DEFAULT '{}',
    keywords TEXT[] NOT NULL DEFAULT '{}',
    language TEXT NOT NULL DEFAULT 'en',

    -- Full text (segmented paragraphs stored as JSONB)
    segments JSONB NOT NULL,  -- [{anchor_id, text}]

    -- Full-text search vector (auto-generated)
    full_text_tsv TSVECTOR GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(l0_summary, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(
            (SELECT string_agg(elem->>'text', ' ')
             FROM jsonb_array_elements(l1_outline) AS elem), ''
        )), 'B') ||
        setweight(to_tsvector('english', coalesce(
            array_to_string(tags, ' '), ''
        )), 'B') ||
        setweight(to_tsvector('english', coalesce(
            (SELECT string_agg(elem->>'text', ' ')
             FROM jsonb_array_elements(segments) AS elem), ''
        )), 'C')
    ) STORED,

    -- Storage references
    original_snapshot_key TEXT,  -- R2 key for original content
    podcast_audio_key TEXT,     -- R2 key for podcast audio

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- GIN indexes for fast search
CREATE INDEX idx_content_fts ON content USING GIN(full_text_tsv);
CREATE INDEX idx_content_tags ON content USING GIN(tags);
CREATE INDEX idx_content_keywords ON content USING GIN(keywords);
CREATE INDEX idx_content_l1_outline ON content USING GIN(l1_outline jsonb_path_ops);

-- B-tree indexes for filtering
CREATE INDEX idx_content_user_created ON content(user_id, created_at DESC);
CREATE INDEX idx_content_source_type ON content(user_id, source_type);
CREATE INDEX idx_content_source_app ON content(user_id, source_app_bundle_id);
```

### Important: Multi-Language tsvector

Readless supports Chinese and English content. PostgreSQL's built-in `english` config works for English but not Chinese. For Chinese full-text search, use the `pg_jieba` or `zhparser` extension.

```sql
-- For Chinese content, create a separate tsvector or use a custom config
-- Option 1: Install zhparser extension (available on most managed Postgres)
CREATE EXTENSION IF NOT EXISTS zhparser;
CREATE TEXT SEARCH CONFIGURATION chinese (PARSER = zhparser);
ALTER TEXT SEARCH CONFIGURATION chinese
    ADD MAPPING FOR n,v,a,i,e,l WITH simple;

-- Option 2: Use the 'simple' config as fallback (tokenizes on whitespace)
-- Less ideal but works without extensions

-- In practice, detect language and use the appropriate config:
-- to_tsvector('english', ...) for English
-- to_tsvector('chinese', ...) for Chinese
```

### Ranked Search Query

```sql
-- Ranked full-text search with filters
SELECT
    id,
    title,
    l0_summary,
    l1_outline,
    tags,
    source_app_name,
    created_at,
    ts_rank_cd(full_text_tsv, query, 32) AS rank,
    ts_headline('english', l0_summary, query,
        'MaxWords=50, MinWords=20, StartSel=<mark>, StopSel=</mark>'
    ) AS headline
FROM content, plainto_tsquery('english', 'AI product gross margin') AS query
WHERE user_id = $1
    AND full_text_tsv @@ query
    AND created_at > now() - interval '7 days'  -- time filter
ORDER BY rank DESC
LIMIT 20;
```

### Search Agent Integration (Python)

```python
# app/services/search_agent.py
from sqlalchemy import text
from app.core.database import async_session

async def keyword_search(
    user_id: str,
    query_text: str,
    time_filter: str | None = None,
    source_type: str | None = None,
    tags_filter: list[str] | None = None,
    limit: int = 20,
) -> list[dict]:
    """PostgreSQL full-text search with filters."""
    conditions = ["user_id = :user_id", "full_text_tsv @@ plainto_tsquery('english', :query)"]
    params = {"user_id": user_id, "query": query_text, "limit": limit}

    if time_filter:
        conditions.append("created_at > now() - :interval::interval")
        params["interval"] = time_filter

    if source_type:
        conditions.append("source_type = :source_type")
        params["source_type"] = source_type

    if tags_filter:
        conditions.append("tags @> :tags")
        params["tags"] = tags_filter

    where_clause = " AND ".join(conditions)

    sql = text(f"""
        SELECT id, title, l0_summary, l1_outline, tags, source_app_name,
               created_at,
               ts_rank_cd(full_text_tsv, plainto_tsquery('english', :query), 32) AS rank
        FROM content
        WHERE {where_clause}
        ORDER BY rank DESC
        LIMIT :limit
    """)

    async with async_session() as session:
        result = await session.execute(sql, params)
        return [dict(row._mapping) for row in result]
```

---

## 5. Cloudflare R2 Object Storage

### Why R2

- **Zero egress fees** -- Readless serves podcast audio files which can be large (5-20MB each). S3 egress would be expensive; R2 egress is free.
- **S3-compatible API** -- Use existing boto3 SDK with a custom endpoint.
- **Generous free tier** -- 10 GB storage, 1M Class A ops, 10M Class B ops/month.

### Pricing (2025-2026)

| Component | Price | Notes |
|---|---|---|
| Storage | $0.015/GB/month | 10 GB free |
| Class A operations (PUT, POST, LIST) | $4.50/million | 1M free/month |
| Class B operations (GET, HEAD) | $0.36/million | 10M free/month |
| Egress | **Free** | This is R2's killer feature |
| Infrequent Access tier | $0.01/GB/month | 30-day minimum, higher op costs |

### Cost Projection for Readless

Per content item stored:
- Original text snapshot: ~50 KB
- Podcast audio: ~10 MB (MP3, ~5 min)
- At 1,000 active users x 50 items/month = 50K items/month

Storage: 50K x 10 MB = ~500 GB = **$7.50/month**
Operations: ~100K writes + 500K reads = **~$0.63/month**
**Total: ~$8/month for 1,000 users. Scales linearly.**

### Setup Code

```python
# app/services/storage.py
import boto3
from botocore.config import Config
from app.config import settings

def get_r2_client():
    return boto3.client(
        "s3",
        endpoint_url=f"https://{settings.r2_account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=settings.r2_access_key_id,
        aws_secret_access_key=settings.r2_secret_access_key,
        config=Config(signature_version="s3v4"),
        region_name="auto",
    )

BUCKET = "readless-storage"

async def upload_content_snapshot(content_id: str, text: str) -> str:
    """Upload original text snapshot to R2."""
    key = f"snapshots/{content_id}.txt"
    client = get_r2_client()
    client.put_object(
        Bucket=BUCKET,
        Key=key,
        Body=text.encode("utf-8"),
        ContentType="text/plain; charset=utf-8",
    )
    return key

async def upload_podcast_audio(content_id: str, audio_bytes: bytes) -> str:
    """Upload podcast MP3 to R2."""
    key = f"podcasts/{content_id}.mp3"
    client = get_r2_client()
    client.put_object(
        Bucket=BUCKET,
        Key=key,
        Body=audio_bytes,
        ContentType="audio/mpeg",
    )
    return key

async def get_presigned_url(key: str, expires_in: int = 3600) -> str:
    """Generate a presigned URL for the macOS client to download."""
    client = get_r2_client()
    return client.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET, "Key": key},
        ExpiresIn=expires_in,
    )
```

### R2 Dashboard Setup Steps

1. Log into Cloudflare Dashboard
2. Go to **Storage & Databases > R2 > Overview**
3. Click **Create Bucket**, name it `readless-storage`
4. Go to **Manage R2 API Tokens**
5. Create a token with **Object Read & Write** permission for the bucket
6. Copy the **Account ID**, **Access Key ID**, and **Secret Access Key**
7. Set these as environment variables in your backend

---

## 6. ElevenLabs API for Podcast Audio

### Text to Dialogue API

ElevenLabs launched **Text to Dialogue** which is exactly what Readless needs: multi-speaker conversational audio from text input, using the Eleven v3 model. No limit on number of speakers (Readless uses 2: host + guest).

### Pricing

| Plan | Monthly Cost | Credits | Minutes (TTS) | Minutes (Dialogue) |
|---|---|---|---|---|
| Free | $0 | 10,000 | ~10 min | Limited |
| Starter | $5 | 30,000 | ~30 min | ~30 min |
| Creator | $22 | 100,000 | ~100 min | 250 min |
| Pro | $99 | 500,000 | ~500 min | 1,100 min |
| Scale | $330 | 2,000,000 | ~2,000 min | 3,600 min |

**For Readless:** Each podcast is ~3-5 minutes. At 1,000 users x 5 podcasts/month = 5,000 podcasts = ~20,000 minutes/month. This requires the **Scale plan ($330/month)** or above. At scale, consider negotiating enterprise pricing.

**Cost per podcast (~4 min):** ~$0.07-0.10 on Scale plan.

### Implementation

```python
# app/services/podcast.py
import anthropic
from elevenlabs.client import ElevenLabs
from pydantic import BaseModel, Field
from app.config import settings
from app.services.storage import upload_podcast_audio

claude_client = anthropic.Anthropic()
eleven_client = ElevenLabs(api_key=settings.elevenlabs_api_key)

# --- Step 1: Generate podcast script with Claude ---

class DialogueLine(BaseModel):
    speaker: str = Field(description="Either 'host' or 'guest'")
    text: str = Field(description="The spoken line")
    chapter_index: int | None = Field(
        description="Which L1 outline point this line relates to (1-indexed), or null for intro/outro"
    )

class PodcastScript(BaseModel):
    title: str
    lines: list[DialogueLine]

async def generate_podcast_script(
    title: str,
    l0_summary: str,
    l1_outline: list[dict],
    l2_details: list[str] | None = None,
) -> PodcastScript:
    """Use Claude to write a conversational podcast script."""
    outline_text = "\n".join(
        f"  {p['index']}. {p['text']}" for p in l1_outline
    )

    response = claude_client.beta.messages.parse(
        model="claude-sonnet-4-5-20250514",
        max_tokens=4096,
        betas=["structured-outputs-2025-11-13"],
        system=(
            "You are a podcast script writer. Write a natural, engaging "
            "conversation between a Host and a Guest discussing the content. "
            "The Host asks questions and guides the discussion. "
            "The Guest provides insights and explanations. "
            "Keep it conversational -- use filler words, reactions, etc. "
            "Each chapter_index corresponds to an L1 outline point. "
            "Include a brief intro (chapter_index=null) and outro. "
            "Total script should be 3-5 minutes when spoken (~500-800 words). "
            "Match the language of the source content."
        ),
        messages=[
            {
                "role": "user",
                "content": (
                    f"Title: {title}\n"
                    f"Summary: {l0_summary}\n\n"
                    f"Outline:\n{outline_text}\n\n"
                    f"{'Details: ' + str(l2_details) if l2_details else ''}\n\n"
                    f"Write a podcast script discussing this content."
                ),
            }
        ],
        response_model=PodcastScript,
    )
    return response.parsed_output

# --- Step 2: Generate audio with ElevenLabs Text to Dialogue ---

# Voice IDs (choose from ElevenLabs voice library)
HOST_VOICE_ID = "JBFqnCBsd6RMkjVDRZzb"   # Example: George
GUEST_VOICE_ID = "EXAVITQu4vr4xnSDxMaL"  # Example: Sarah

async def generate_podcast_audio(
    content_id: str,
    script: PodcastScript,
) -> str:
    """Generate multi-voice audio and upload to R2."""
    # Option A: Use Text to Dialogue API (preferred, single API call)
    # Construct dialogue format expected by the API
    dialogue_text = "\n".join(
        f"{'Host' if line.speaker == 'host' else 'Guest'}: {line.text}"
        for line in script.lines
    )

    audio = eleven_client.text_to_dialogue.convert(
        text=dialogue_text,
        voices=[
            {"name": "Host", "voice_id": HOST_VOICE_ID},
            {"name": "Guest", "voice_id": GUEST_VOICE_ID},
        ],
        model_id="eleven_v3",
        output_format="mp3_44100_128",
    )

    # Collect audio bytes
    audio_bytes = b"".join(chunk for chunk in audio)

    # Upload to R2
    key = await upload_podcast_audio(content_id, audio_bytes)
    return key
```

### Alternatives to ElevenLabs

| Alternative | Pros | Cons | Cost |
|---|---|---|---|
| **Podcastfy** (open source) | Free, self-hosted, uses any TTS backend | Requires your own TTS, more setup | Free + TTS costs |
| **OpenAI TTS** | Simple API, good quality | Single voice only, no dialogue mode | $15/M chars |
| **Google Cloud TTS** | Multi-voice, SSML support | More complex API, lower naturalness | $4-16/M chars |
| **Azure Speech** | Multi-voice, SSML, neural voices | Complex setup | $15/M chars |
| **Fish Audio** | Cheaper, fast | Less natural than ElevenLabs | ~$0.005/M chars |
| **Tongyi TTS (Alibaba)** | Good Chinese support | Limited English quality | ~$0.01/M chars |

**Recommendation:** Start with ElevenLabs for quality. If costs become prohibitive at scale, evaluate Podcastfy (open source) with a cheaper TTS backend like Fish Audio or Google Cloud TTS.

---

## 7. Authentication

### Recommendation: JWT with Email Magic Link (+ Apple Sign-In later)

For a macOS-first app with a cloud backend, the simplest effective auth is:

1. **Magic Link (email-based)** for signup/login -- no passwords to manage
2. **JWT access tokens** (short-lived, 15 min) for API authentication
3. **Refresh tokens** (long-lived, 30 days) stored in macOS Keychain
4. **Apple Sign-In** as Phase 2 addition (required for App Store)

### Why This Stack

- **Magic Link**: Users enter email, receive a link, click it, done. No password to forget. Excellent UX for a productivity tool. Simple to implement server-side.
- **JWT**: Stateless validation on every API request. The macOS app stores tokens in Keychain (secure). No session state on the server.
- **No OAuth provider dependency**: Magic links work with any email. No Google/GitHub/etc. dependency for MVP.

### Implementation

```python
# app/core/auth.py
import secrets
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
from pydantic import BaseModel
from app.config import settings

ALGORITHM = "HS256"

class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds

def create_access_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=15)
    return jwt.encode(
        {"sub": user_id, "exp": expire, "type": "access"},
        settings.jwt_secret,
        algorithm=ALGORITHM,
    )

def create_refresh_token(user_id: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=30)
    return jwt.encode(
        {"sub": user_id, "exp": expire, "type": "refresh"},
        settings.jwt_secret,
        algorithm=ALGORITHM,
    )

def create_token_pair(user_id: str) -> TokenPair:
    return TokenPair(
        access_token=create_access_token(user_id),
        refresh_token=create_refresh_token(user_id),
        expires_in=900,  # 15 minutes
    )

def verify_token(token: str, expected_type: str = "access") -> str | None:
    """Returns user_id if valid, None otherwise."""
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
        if payload.get("type") != expected_type:
            return None
        return payload.get("sub")
    except JWTError:
        return None

def generate_magic_link_token() -> str:
    """Generate a cryptographically secure token for magic links."""
    return secrets.token_urlsafe(32)
```

```python
# app/routers/auth.py
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr
from app.core.auth import (
    create_token_pair, verify_token, generate_magic_link_token
)
from app.core.database import async_session

router = APIRouter()

class MagicLinkRequest(BaseModel):
    email: EmailStr

class MagicLinkVerify(BaseModel):
    token: str

class RefreshRequest(BaseModel):
    refresh_token: str

@router.post("/magic-link")
async def request_magic_link(req: MagicLinkRequest):
    """Send a magic link to the user's email."""
    token = generate_magic_link_token()

    # Store token in DB with expiry (15 minutes)
    async with async_session() as session:
        await session.execute(
            text("""
                INSERT INTO magic_links (email, token, expires_at)
                VALUES (:email, :token, now() + interval '15 minutes')
            """),
            {"email": req.email, "token": token},
        )
        await session.commit()

    # Send email (use Resend, Postmark, or SES)
    magic_url = f"https://app.readless.ai/auth/verify?token={token}"
    await send_email(
        to=req.email,
        subject="Sign in to Readless",
        body=f"Click to sign in: {magic_url}\n\nThis link expires in 15 minutes.",
    )

    return {"message": "Magic link sent"}

@router.post("/verify")
async def verify_magic_link(req: MagicLinkVerify):
    """Verify a magic link token and return JWT tokens."""
    async with async_session() as session:
        result = await session.execute(
            text("""
                DELETE FROM magic_links
                WHERE token = :token AND expires_at > now()
                RETURNING email
            """),
            {"token": req.token},
        )
        row = result.first()

    if not row:
        raise HTTPException(401, "Invalid or expired magic link")

    email = row.email

    # Find or create user
    user = await get_or_create_user(email)
    tokens = create_token_pair(str(user.id))

    return tokens

@router.post("/refresh")
async def refresh_tokens(req: RefreshRequest):
    """Exchange a refresh token for a new token pair."""
    user_id = verify_token(req.refresh_token, expected_type="refresh")
    if not user_id:
        raise HTTPException(401, "Invalid refresh token")

    return create_token_pair(user_id)
```

### macOS Client Side (Swift)

```swift
// Store tokens in Keychain
import Security

class AuthManager {
    static let shared = AuthManager()

    func storeTokens(_ pair: TokenPair) {
        KeychainHelper.save(key: "access_token", value: pair.accessToken)
        KeychainHelper.save(key: "refresh_token", value: pair.refreshToken)
    }

    func getAccessToken() -> String? {
        return KeychainHelper.load(key: "access_token")
    }

    // Handle magic link callback via custom URL scheme
    // readless://auth/verify?token=xxx
    func handleMagicLink(url: URL) async throws {
        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "token" })?.value else {
            throw AuthError.invalidLink
        }

        let pair = try await API.verifyMagicLink(token: token)
        storeTokens(pair)
    }
}
```

### Database Tables for Auth

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    plan TEXT NOT NULL DEFAULT 'free',  -- 'free' or 'pro'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE magic_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    token TEXT UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_magic_links_token ON magic_links(token);
CREATE INDEX idx_magic_links_expires ON magic_links(expires_at);
```

---

## 8. Deployment: Recommendation = Railway (MVP) -> Hetzner (Scale)

### Comparison Matrix

| Criteria | Railway | Fly.io | Render | Hetzner |
|---|---|---|---|---|
| **Ease of deploy** | Excellent (git push) | Good (flyctl) | Excellent (git push) | Manual (Docker + ssh) |
| **Managed PostgreSQL** | Yes ($5+ usage-based) | Yes (~$3.15/mo min) | Yes ($7/mo starter) | No (self-managed) |
| **Pricing model** | Usage-based (RAM/CPU hours) | Usage-based | Fixed tiers | Fixed VPS price |
| **Smallest useful config** | ~$5-10/mo | ~$5-10/mo | $7/mo (Starter) | ~$4-5/mo (CX22) |
| **Auto-scaling** | Yes | Yes (per-region) | Yes (paid plans) | No (manual) |
| **Global edge** | No | Yes (35+ regions) | No | No (EU or US) |
| **DX quality** | Best | Good | Good | Bare metal |
| **Free tier** | $5 trial credit | Hobby plan (limited) | 750 hours/mo | None |
| **Best for** | Fast iteration, MVPs | Global low-latency | Simple web services | Cost at scale |

### Pricing Estimates for Readless Backend (1,000 users)

| Platform | Compute | PostgreSQL | Total/month |
|---|---|---|---|
| Railway | ~$10-20 | ~$10-15 | **~$20-35** |
| Fly.io | ~$10-15 | ~$7-10 | **~$17-25** |
| Render | $7 (Starter) | $7 (Starter) | **~$14** (limited) |
| Hetzner | ~$5 (CX22) | $0 (self-managed) | **~$5** |

### Recommended Path

**Phase 1 (MVP, 0-1,000 users): Railway**
- Zero-config deployment: connect GitHub repo, Railway detects Dockerfile, deploys
- Managed PostgreSQL included
- Usage-based billing means you pay nothing when idle during development
- Best developer experience for rapid iteration
- Estimated cost: **$10-30/month**

**Phase 2 (Scale, 1,000-10,000 users): Hetzner**
- Move to a Hetzner CX32 or CCX13 VPS (~$5-15/month)
- Run PostgreSQL on the same box or use a separate Hetzner instance
- Use Docker Compose for orchestration
- 10x cheaper than managed platforms at this scale
- Estimated cost: **$10-30/month for 10x the users**

### Railway Deployment

```dockerfile
# Dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies for PDF/OCR processing
RUN apt-get update && apt-get install -y \
    tesseract-ocr \
    tesseract-ocr-chi-sim \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
RUN pip install --no-cache-dir .

COPY app/ ./app/
COPY alembic/ ./alembic/
COPY alembic.ini ./

# Run migrations then start server
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
```

```toml
# railway.toml (optional, Railway auto-detects Dockerfile)
[build]
builder = "DOCKERFILE"
dockerfilePath = "Dockerfile"

[deploy]
healthcheckPath = "/health"
healthcheckTimeout = 300
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 3
```

Railway setup steps:
1. Create a new project at railway.app
2. Add a **PostgreSQL** service (click "+ New" -> "Database" -> "PostgreSQL")
3. Add a **service** from your GitHub repo
4. Railway auto-injects `DATABASE_URL` environment variable
5. Add other env vars: `ANTHROPIC_API_KEY`, `ELEVENLABS_API_KEY`, `R2_*`, `JWT_SECRET`
6. Deploy triggers automatically on git push

### Hetzner Migration (Phase 2)

```yaml
# docker-compose.yml (for Hetzner VPS)
services:
  api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql+asyncpg://readless:${DB_PASSWORD}@db:5432/readless
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      - ELEVENLABS_API_KEY=${ELEVENLABS_API_KEY}
      - R2_ACCOUNT_ID=${R2_ACCOUNT_ID}
      - R2_ACCESS_KEY_ID=${R2_ACCESS_KEY_ID}
      - R2_SECRET_ACCESS_KEY=${R2_SECRET_ACCESS_KEY}
      - JWT_SECRET=${JWT_SECRET}
    depends_on:
      - db
    restart: unless-stopped

  db:
    image: postgres:17
    volumes:
      - pgdata:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=readless
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=readless
    restart: unless-stopped

  caddy:
    image: caddy:2
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
    depends_on:
      - api
    restart: unless-stopped

volumes:
  pgdata:
  caddy_data:
```

```
# Caddyfile (automatic HTTPS via Let's Encrypt)
api.readless.ai {
    reverse_proxy api:8000
}
```

---

## Summary of Recommendations

| Component | Recommendation | Why |
|---|---|---|
| **Framework** | Python + FastAPI | Native Claude/Pydantic integration, Trafilatura, async I/O |
| **Content Extraction** | Trafilatura (primary) + Jina Reader (fallback) | Best F1 score, free, Python-native; Jina handles JS pages |
| **AI Summarization** | Claude Sonnet 4.5 + structured outputs | Guaranteed JSON, Pydantic models, ~$0.06/article |
| **Database** | PostgreSQL with tsvector + GIN indexes | Sufficient for structured search, no vector DB needed |
| **Object Storage** | Cloudflare R2 | Zero egress fees, S3-compatible, ~$8/mo at 1K users |
| **Podcast Audio** | ElevenLabs Text to Dialogue API | Best quality multi-voice, ~$0.07-0.10/podcast |
| **Authentication** | Magic Link + JWT | No passwords, great UX, simple implementation |
| **Deployment** | Railway (MVP) -> Hetzner (scale) | Fast iteration first, cost optimization later |

### Total Estimated Monthly Cost at 1,000 Users

| Component | Cost |
|---|---|
| Railway (compute + Postgres) | $25 |
| Claude API (100 articles/user avg = impossible, realistic: 5K total) | $300 |
| ElevenLabs (2K podcasts) | $66 |
| Cloudflare R2 | $8 |
| Email sending (Resend) | $0 (free tier) |
| **Total** | **~$400/month** |

Revenue at 1,000 users (10% conversion): 100 x $9.99 = **$999/month**. Positive margin from day one.

---

## Sources

### Backend Framework
- [Go vs Node.js vs FastAPI: Backend Technology Comparison 2026](https://www.index.dev/skill-vs-skill/backend-go-vs-nodejs-vs-python-fastapi)
- [FastAPI-Fastify-Hono Benchmark](https://github.com/malkiii/fastapi-fastify-hono-benchmark)
- [FastAPI for Microservices: High-Performance Python API Design Patterns](https://talent500.com/blog/fastapi-microservices-python-api-design-patterns-2025/)

### Content Extraction
- [Comparing algorithms for extracting content from web pages](https://chuniversiteit.nl/papers/comparison-of-web-content-extraction-algorithms)
- [Jina Reader API](https://jina.ai/reader/)
- [Best Web Scraping Tools for AI Applications](https://www.thetoolnerd.com/p/best-web-scraping-tools-for-ai-applications)

### Claude API
- [Claude Structured Outputs Documentation](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [Claude API Structured Output: Complete Guide](https://thomas-wiegold.com/blog/claude-api-structured-output/)
- [Anthropic Launches Structured Outputs](https://techbytes.app/posts/claude-structured-outputs-json-schema-api/)
- [Hands-On with Anthropic's Structured Output](https://towardsdatascience.com/hands-on-with-anthropics-new-structured-output-capabilities/)

### PostgreSQL FTS
- [Full-Text Search with GIN Indexes in PostgreSQL](https://oneuptime.com/blog/post/2026-01-25-full-text-search-gin-postgresql/view)
- [PostgreSQL Full-Text Search: Alternative to Elasticsearch](https://iniakunhuda.medium.com/postgresql-full-text-search-a-powerful-alternative-to-elasticsearch-for-small-to-medium-d9524e001fe0)
- [PostgreSQL Documentation: Text Search Indexes](https://www.postgresql.org/docs/current/textsearch-indexes.html)

### Cloudflare R2
- [R2 Pricing Documentation](https://developers.cloudflare.com/r2/pricing/)
- [Cloudflare R2 vs AWS S3: 2025 Comparison](https://www.digitalapplied.com/blog/cloudflare-r2-vs-aws-s3-comparison)
- [R2 boto3 Examples](https://developers.cloudflare.com/r2/examples/aws/boto3/)

### ElevenLabs
- [ElevenLabs API Pricing](https://elevenlabs.io/pricing/api)
- [Text to Dialogue Quickstart](https://elevenlabs.io/docs/developers/guides/cookbooks/text-to-dialogue)
- [ElevenLabs Python SDK](https://github.com/elevenlabs/elevenlabs-python)

### Podcast Alternatives
- [Podcastfy: Open Source NotebookLM Alternative](https://github.com/souzatharsis/podcastfy)
- [Open Notebook](https://github.com/lfnovo/open-notebook)

### Authentication
- [Ultimate Guide to Authentication 2025: JWT, OAuth2, Passwordless](https://www.meerako.com/blogs/ultimate-guide-authentication-jwt-oauth2-passwordless-2025)
- [AppAuth-iOS: OAuth 2.0 SDK for iOS/macOS](https://github.com/openid/AppAuth-iOS)
- [Mobile Login with JWTs and Refresh Tokens](https://fusionauth.io/articles/login-authentication-workflows/mobile/native-login-form-to-application-backend-jwts-refresh-tokens)

### Deployment
- [Railway vs Fly.io](https://docs.railway.com/platform/compare-to-fly)
- [Railway vs Render](https://northflank.com/blog/railway-vs-render)
- [Railway vs Fly.io vs Render ROI Comparison](https://medium.com/ai-disruption/railway-vs-fly-io-vs-render-which-cloud-gives-you-the-best-roi-2e3305399e5b)
- [Hetzner Cloud Pricing](https://www.hetzner.com/cloud)
