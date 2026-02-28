# Readless MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS-native AI-powered read-later + knowledge base app that ingests long content, generates multi-level traceable summaries, produces AI podcasts, and enables semantic recall.

**Architecture:** macOS native client (Swift/SwiftUI) communicates with a Python FastAPI backend over HTTPS. Backend orchestrates AI summarization (Claude API), content extraction (Trafilatura), podcast generation (ElevenLabs), and stores data in PostgreSQL. Client caches locally with SQLite (GRDB). Auth via Clerk. Deployed via Docker on user's cloud server.

**Tech Stack:**
- Client: Swift 5.9+, SwiftUI, macOS 14+, SPM modules (KeyboardShortcuts, GRDB, HotKey)
- Backend: Python 3.12, FastAPI, Anthropic SDK, Trafilatura, PostgreSQL, Cloudflare R2
- Auth: Clerk (standard service)
- Podcast: ElevenLabs Text to Dialogue API
- Deployment: Docker Compose on user's cloud server, Caddy reverse proxy

**Design doc:** `docs/plans/2026-02-28-readless-product-design.md`

---

## Task 1: Project Scaffolding — Backend

**Files:**
- Create: `backend/pyproject.toml`
- Create: `backend/app/__init__.py`
- Create: `backend/app/main.py`
- Create: `backend/app/config.py`
- Create: `backend/app/models/__init__.py`
- Create: `backend/app/routers/__init__.py`
- Create: `backend/Dockerfile`
- Create: `backend/docker-compose.yml`
- Create: `backend/Caddyfile`
- Create: `backend/.env.example`

**Step 1: Create backend directory and pyproject.toml**

```toml
# backend/pyproject.toml
[project]
name = "readless-backend"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.115.0",
    "uvicorn[standard]>=0.32.0",
    "anthropic>=0.43.0",
    "trafilatura>=2.0.0",
    "httpx>=0.28.0",
    "asyncpg>=0.30.0",
    "sqlalchemy[asyncio]>=2.0.36",
    "alembic>=1.14.0",
    "pydantic>=2.10.0",
    "pydantic-settings>=2.6.0",
    "python-multipart>=0.0.18",
    "boto3>=1.35.0",
    "pillow>=11.0.0",
    "pytesseract>=0.3.13",
    "pdfplumber>=0.11.0",
    "clerk-backend-api>=1.0.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.3.0",
    "pytest-asyncio>=0.24.0",
    "httpx>=0.28.0",
    "ruff>=0.8.0",
]

[tool.ruff]
line-length = 100
target-version = "py312"
```

**Step 2: Create app entry point**

```python
# backend/app/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings

app = FastAPI(title="Readless API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health")
async def health():
    return {"status": "ok"}
```

```python
# backend/app/config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str = "postgresql+asyncpg://readless:readless@localhost:5432/readless"
    anthropic_api_key: str = ""
    clerk_secret_key: str = ""
    r2_endpoint: str = ""
    r2_access_key: str = ""
    r2_secret_key: str = ""
    r2_bucket: str = "readless"
    elevenlabs_api_key: str = ""
    cors_origins: list[str] = ["*"]

    model_config = {"env_file": ".env"}

settings = Settings()
```

**Step 3: Create Dockerfile and docker-compose.yml**

```dockerfile
# backend/Dockerfile
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir .
COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

```yaml
# backend/docker-compose.yml
services:
  api:
    build: .
    ports:
      - "8000:8000"
    env_file: .env
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:17
    environment:
      POSTGRES_USER: readless
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-readless}
      POSTGRES_DB: readless
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U readless"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  caddy:
    image: caddy:2
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped

volumes:
  pgdata:
  caddy_data:
  caddy_config:
```

```
# backend/Caddyfile
{$DOMAIN:localhost} {
    reverse_proxy api:8000
}
```

**Step 4: Create .env.example**

```bash
# backend/.env.example
DATABASE_URL=postgresql+asyncpg://readless:readless@db:5432/readless
POSTGRES_PASSWORD=changeme
ANTHROPIC_API_KEY=sk-ant-...
CLERK_SECRET_KEY=sk_live_...
R2_ENDPOINT=https://xxx.r2.cloudflarestorage.com
R2_ACCESS_KEY=
R2_SECRET_KEY=
R2_BUCKET=readless
ELEVENLABS_API_KEY=
DOMAIN=api.readless.app
CORS_ORIGINS=["*"]
```

**Step 5: Verify backend starts**

Run: `cd backend && pip install -e ".[dev]" && uvicorn app.main:app --reload`
Expected: Server starts on port 8000, `GET /health` returns `{"status": "ok"}`

**Step 6: Commit**

```bash
git init
git add backend/
git commit -m "feat: scaffold backend with FastAPI, Docker Compose, Caddy"
```

---

## Task 2: Project Scaffolding — macOS App

**Files:**
- Create: `macos/Package.swift`
- Create: `macos/Sources/App/ReadlessApp.swift`
- Create: `macos/Sources/App/AppDelegate.swift`
- Create: `macos/Sources/Core/Models/Content.swift`
- Create: `macos/Sources/Core/Models/Outline.swift`
- Create: `macos/Sources/Networking/APIClient.swift`
- Create: `macos/Sources/Storage/DatabaseManager.swift`
- Create: `macos/Sources/UI/Theme.swift`

**Step 1: Create Package.swift with modular structure**

```swift
// macos/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Readless",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Readless", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(name: "Core", dependencies: []),
        .target(name: "Networking", dependencies: ["Core"]),
        .target(name: "Storage", dependencies: [
            "Core",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "UI", dependencies: ["Core"]),
        .executableTarget(name: "App", dependencies: [
            "Core", "Networking", "Storage", "UI",
            "KeyboardShortcuts",
        ]),
        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking"]),
        .testTarget(name: "StorageTests", dependencies: ["Storage"]),
    ]
)
```

**Step 2: Create app entry point**

```swift
// macos/Sources/App/ReadlessApp.swift
import SwiftUI

@main
struct ReadlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            Text("Select content to view")
                .foregroundStyle(.secondary)
        }
    }
}

struct SidebarView: View {
    var body: some View {
        List {
            Label("All Items", systemImage: "tray.full")
            Label("Unread", systemImage: "circle")
            Label("Favorites", systemImage: "star")
            Divider()
            Label("Knowledge Base", systemImage: "brain")
        }
        .listStyle(.sidebar)
        .navigationTitle("Readless")
    }
}

struct SettingsView: View {
    var body: some View {
        Text("Settings")
            .frame(width: 400, height: 300)
    }
}
```

```swift
// macos/Sources/App/AppDelegate.swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Global hotkeys and services will be initialized here
    }
}
```

**Step 3: Create Core models**

```swift
// macos/Sources/Core/Models/Content.swift
import Foundation

public struct Content: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var sourceURL: String?
    public var sourceType: SourceType
    public var sourceAppName: String?
    public var sourceAppBundleID: String?
    public var l0Summary: String?
    public var l1Outline: [OutlinePoint]?
    public var tags: [String]
    public var status: ProcessingStatus
    public var createdAt: Date
    public var podcastURL: String?

    public enum SourceType: String, Codable, Sendable {
        case url, pdf, text, image, clipboard, folderWatch, email, rss
    }

    public enum ProcessingStatus: String, Codable, Sendable {
        case pending, processing, ready, failed
    }
}

// macos/Sources/Core/Models/Outline.swift
public struct OutlinePoint: Identifiable, Codable, Sendable {
    public let id: String
    public var point: String
    public var anchors: [String]  // ["¶3", "¶7"]
    public var expanded: Bool = false
    public var detail: String?    // L2 expanded detail (loaded on demand)
}
```

**Step 4: Create Theme**

```swift
// macos/Sources/UI/Theme.swift
import SwiftUI

public enum Theme {
    // Typography
    public static let l0Font: Font = .system(size: 20, weight: .semibold)
    public static let l1Font: Font = .system(size: 16, weight: .medium)
    public static let l2Font: Font = .system(size: 15, weight: .regular)
    public static let citationFont: Font = .system(size: 13, weight: .regular, design: .monospaced)
    public static let lineSpacing: CGFloat = 8

    // Colors
    public static let accent = Color.blue
    public static let citationColor = Color.secondary.opacity(0.7)
    public static let focusBorder = Color.blue.opacity(0.6)
    public static let surfacePrimary = Color(nsColor: .windowBackgroundColor)
    public static let surfaceFloating = Color.black.opacity(0.85)

    // Animation
    public static let snapAnimation: Animation = .snappy(duration: 0.35)
    public static let springAnimation: Animation = .spring(duration: 0.5, bounce: 0.2)
    public static let capsuleAppear: Animation = .spring(duration: 0.3, bounce: 0.15)
    public static let capsuleDismiss: Animation = .smooth(duration: 0.2)

    // Layout
    public static let capsuleWidth: CGFloat = 280
    public static let capsuleHeight: CGFloat = 48
    public static let cornerRadius: CGFloat = 24
}
```

**Step 5: Create placeholder APIClient and DatabaseManager**

```swift
// macos/Sources/Networking/APIClient.swift
import Foundation
import Core

public final class APIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://localhost:8000")!) {
        self.baseURL = baseURL
        self.session = .shared
    }

    public func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        let (_, response) = try await session.data(from: url)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
```

```swift
// macos/Sources/Storage/DatabaseManager.swift
import Foundation
import GRDB
import Core

public final class DatabaseManager {
    public static let shared = DatabaseManager()
    private let dbQueue: DatabaseQueue

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("Readless", isDirectory: true)
        try! fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("readless.sqlite").path
        dbQueue = try! DatabaseQueue(path: dbPath)
        try! runMigrations()
    }

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "content") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("sourceURL", .text)
                t.column("sourceType", .text).notNull()
                t.column("sourceAppName", .text)
                t.column("sourceAppBundleID", .text)
                t.column("l0Summary", .text)
                t.column("l1OutlineJSON", .text)
                t.column("tagsJSON", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("createdAt", .datetime).notNull()
                t.column("podcastURL", .text)
            }
        }
        try migrator.migrate(dbQueue)
    }
}
```

**Step 6: Build and verify**

Run: `cd macos && swift build`
Expected: Build succeeds with no errors.

**Step 7: Commit**

```bash
git add macos/
git commit -m "feat: scaffold macOS app with SPM modular architecture"
```

---

## Task 3: Backend — Database Schema & Migrations

**Files:**
- Create: `backend/app/database.py`
- Create: `backend/app/models/content.py`
- Create: `backend/app/models/paragraph.py`
- Create: `backend/app/models/channel.py`
- Create: `backend/app/models/podcast.py`
- Create: `backend/alembic.ini`
- Create: `backend/alembic/env.py`
- Create: `backend/alembic/versions/001_initial.py`

**Step 1: Create async database engine**

```python
# backend/app/database.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase
from app.config import settings

engine = create_async_engine(settings.database_url, echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

class Base(DeclarativeBase):
    pass

async def get_db():
    async with async_session() as session:
        yield session
```

**Step 2: Create SQLAlchemy models**

```python
# backend/app/models/content.py
from datetime import datetime
from sqlalchemy import String, Text, DateTime, func, Index
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base

class Content(Base):
    __tablename__ = "contents"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    source_url: Mapped[str | None] = mapped_column(Text)
    source_type: Mapped[str] = mapped_column(String(20), nullable=False)  # url/pdf/text/image
    source_app_name: Mapped[str | None] = mapped_column(String(100))
    source_app_bundle_id: Mapped[str | None] = mapped_column(String(200))
    channel: Mapped[str] = mapped_column(String(20), default="manual")  # manual/email/folder/rss/slack

    l0_summary: Mapped[str | None] = mapped_column(Text)
    l1_outline: Mapped[dict | None] = mapped_column(JSONB)  # [{point, anchors}]
    tags: Mapped[list | None] = mapped_column(ARRAY(String))
    keywords: Mapped[list | None] = mapped_column(ARRAY(String))

    full_text: Mapped[str | None] = mapped_column(Text)
    full_text_tsv: Mapped[str | None] = mapped_column(TSVECTOR)

    status: Mapped[str] = mapped_column(String(20), default="pending")  # pending/processing/ready/failed
    user_id: Mapped[str] = mapped_column(String(100), nullable=False)

    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("ix_contents_full_text_tsv", "full_text_tsv", postgresql_using="gin"),
        Index("ix_contents_tags", "tags", postgresql_using="gin"),
        Index("ix_contents_keywords", "keywords", postgresql_using="gin"),
        Index("ix_contents_l1_outline", "l1_outline", postgresql_using="gin"),
        Index("ix_contents_user_created", "user_id", "created_at"),
    )
```

```python
# backend/app/models/paragraph.py
from sqlalchemy import String, Text, Integer, ForeignKey, Index
from sqlalchemy.dialects.postgresql import TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base

class Paragraph(Base):
    __tablename__ = "paragraphs"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    content_id: Mapped[str] = mapped_column(String(36), ForeignKey("contents.id", ondelete="CASCADE"))
    anchor_id: Mapped[str] = mapped_column(String(20), nullable=False)  # "¶1", "¶2", ...
    text: Mapped[str] = mapped_column(Text, nullable=False)
    position: Mapped[int] = mapped_column(Integer, nullable=False)
    full_text_tsv: Mapped[str | None] = mapped_column(TSVECTOR)

    __table_args__ = (
        Index("ix_paragraphs_content_anchor", "content_id", "anchor_id"),
        Index("ix_paragraphs_tsv", "full_text_tsv", postgresql_using="gin"),
    )
```

```python
# backend/app/models/podcast.py
from datetime import datetime
from sqlalchemy import String, Text, DateTime, ForeignKey, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base

class Podcast(Base):
    __tablename__ = "podcasts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    content_id: Mapped[str] = mapped_column(String(36), ForeignKey("contents.id", ondelete="CASCADE"))
    audio_url: Mapped[str | None] = mapped_column(Text)
    script: Mapped[dict | None] = mapped_column(JSONB)
    chapters: Mapped[dict | None] = mapped_column(JSONB)  # [{title, start_time, outline_point_index}]
    status: Mapped[str] = mapped_column(String(20), default="generating")  # generating/ready/failed
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
```

```python
# backend/app/models/channel.py
from datetime import datetime
from sqlalchemy import String, DateTime, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base

class Channel(Base):
    __tablename__ = "channels"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(100), nullable=False)
    type: Mapped[str] = mapped_column(String(20), nullable=False)  # email/folder/rss/slack/webhook
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    config: Mapped[dict] = mapped_column(JSONB, nullable=False)
    is_active: Mapped[bool] = mapped_column(default=True)
    last_synced_at: Mapped[datetime | None] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
```

```python
# backend/app/models/__init__.py
from app.models.content import Content
from app.models.paragraph import Paragraph
from app.models.podcast import Podcast
from app.models.channel import Channel
```

**Step 3: Set up Alembic and create initial migration**

Run: `cd backend && alembic init alembic`

Update `alembic/env.py` to use async engine and import models. Then:

Run: `alembic revision --autogenerate -m "initial schema"`
Run: `alembic upgrade head`

Expected: Tables created in PostgreSQL.

**Step 4: Write test for model creation**

```python
# backend/tests/test_models.py
import pytest
from app.models import Content

def test_content_model_has_required_fields():
    fields = {c.name for c in Content.__table__.columns}
    assert "id" in fields
    assert "l0_summary" in fields
    assert "l1_outline" in fields
    assert "full_text_tsv" in fields
    assert "source_app_name" in fields
```

Run: `pytest tests/test_models.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add backend/
git commit -m "feat: add database schema with PostgreSQL FTS indexes"
```

---

## Task 4: Backend — Content Extraction Service

**Files:**
- Create: `backend/app/services/extractor.py`
- Create: `backend/tests/test_extractor.py`

**Step 1: Write test for content extraction**

```python
# backend/tests/test_extractor.py
import pytest
from app.services.extractor import ContentExtractor, ExtractedContent

@pytest.mark.asyncio
async def test_extract_from_text():
    extractor = ContentExtractor()
    result = await extractor.extract_text("This is a test paragraph.\n\nThis is another paragraph.")
    assert isinstance(result, ExtractedContent)
    assert len(result.paragraphs) == 2
    assert result.paragraphs[0].anchor_id == "¶1"
    assert result.paragraphs[1].anchor_id == "¶2"

@pytest.mark.asyncio
async def test_extract_from_url():
    extractor = ContentExtractor()
    result = await extractor.extract_url("https://example.com")
    assert result.title is not None
    assert len(result.paragraphs) > 0
```

**Step 2: Implement ContentExtractor**

```python
# backend/app/services/extractor.py
from dataclasses import dataclass
import trafilatura
import httpx
import pdfplumber
import pytesseract
from PIL import Image
from pathlib import Path

@dataclass
class ExtractedParagraph:
    anchor_id: str      # "¶1", "¶2", ...
    text: str
    position: int

@dataclass
class ExtractedContent:
    title: str
    full_text: str
    paragraphs: list[ExtractedParagraph]
    source_url: str | None = None

class ContentExtractor:

    def _segment_paragraphs(self, text: str) -> list[ExtractedParagraph]:
        raw_paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
        # Merge very short paragraphs with their successor
        merged = []
        buffer = ""
        for p in raw_paragraphs:
            if len(p) < 30 and buffer == "":
                buffer = p
            elif buffer:
                merged.append(f"{buffer}\n{p}")
                buffer = ""
            else:
                merged.append(p)
        if buffer:
            merged.append(buffer)

        return [
            ExtractedParagraph(anchor_id=f"¶{i+1}", text=p, position=i)
            for i, p in enumerate(merged)
        ]

    async def extract_url(self, url: str) -> ExtractedContent:
        downloaded = trafilatura.fetch_url(url)
        if not downloaded:
            # Fallback: try Jina Reader
            async with httpx.AsyncClient() as client:
                resp = await client.get(f"https://r.jina.ai/{url}", timeout=30)
                downloaded = resp.text

        result = trafilatura.extract(
            downloaded,
            include_comments=False,
            include_tables=True,
            output_format="txt",
        )
        title = trafilatura.extract(downloaded, output_format="xml")
        # Parse title from XML or use URL as fallback
        import re
        title_match = re.search(r"<title>(.*?)</title>", title or "")
        title_str = title_match.group(1) if title_match else url

        paragraphs = self._segment_paragraphs(result or "")
        return ExtractedContent(
            title=title_str,
            full_text=result or "",
            paragraphs=paragraphs,
            source_url=url,
        )

    async def extract_text(self, text: str) -> ExtractedContent:
        lines = text.strip().split("\n")
        title = lines[0][:100] if lines else "Untitled"
        paragraphs = self._segment_paragraphs(text)
        return ExtractedContent(title=title, full_text=text, paragraphs=paragraphs)

    async def extract_pdf(self, file_path: str) -> ExtractedContent:
        full_text = ""
        with pdfplumber.open(file_path) as pdf:
            for page in pdf.pages:
                page_text = page.extract_text() or ""
                full_text += page_text + "\n\n"
        title = Path(file_path).stem
        paragraphs = self._segment_paragraphs(full_text)
        return ExtractedContent(title=title, full_text=full_text, paragraphs=paragraphs)

    async def extract_image(self, file_path: str) -> ExtractedContent:
        image = Image.open(file_path)
        text = pytesseract.image_to_string(image, lang="chi_sim+eng")
        title = Path(file_path).stem
        paragraphs = self._segment_paragraphs(text)
        return ExtractedContent(title=title, full_text=text, paragraphs=paragraphs)
```

**Step 3: Run tests**

Run: `pytest tests/test_extractor.py -v`
Expected: PASS

**Step 4: Commit**

```bash
git add backend/app/services/extractor.py backend/tests/test_extractor.py
git commit -m "feat: add content extraction with Trafilatura, PDF, OCR"
```

---

## Task 5: Backend — AI Summarization Service (Claude)

**Files:**
- Create: `backend/app/services/summarizer.py`
- Create: `backend/app/schemas/summary.py`
- Create: `backend/tests/test_summarizer.py`

**Step 1: Define Pydantic schemas for structured output**

```python
# backend/app/schemas/summary.py
from pydantic import BaseModel

class OutlinePoint(BaseModel):
    point: str           # "纯订阅模式份额从65%降至43%"
    anchors: list[str]   # ["¶3", "¶7"]

class ContentSummary(BaseModel):
    l0_summary: str                # One-line summary, ≤30 chars
    l1_outline: list[OutlinePoint] # 3-5 key points with source anchors
    tags: list[str]                # Auto-extracted tags
    keywords: list[str]            # Auto-extracted keywords
```

**Step 2: Write test**

```python
# backend/tests/test_summarizer.py
import pytest
from app.services.summarizer import SummarizationService
from app.services.extractor import ExtractedContent, ExtractedParagraph

@pytest.fixture
def sample_content():
    text = "Paragraph one about SaaS pricing trends.\n\nParagraph two about subscription models declining.\n\nParagraph three about hybrid pricing growing."
    return ExtractedContent(
        title="SaaS Pricing",
        full_text=text,
        paragraphs=[
            ExtractedParagraph(anchor_id="¶1", text="Paragraph one about SaaS pricing trends.", position=0),
            ExtractedParagraph(anchor_id="¶2", text="Paragraph two about subscription models declining.", position=1),
            ExtractedParagraph(anchor_id="¶3", text="Paragraph three about hybrid pricing growing.", position=2),
        ],
    )

@pytest.mark.asyncio
async def test_summarize_returns_structured_output(sample_content):
    service = SummarizationService()
    result = await service.summarize(sample_content)
    assert result.l0_summary
    assert len(result.l0_summary) <= 60
    assert len(result.l1_outline) >= 1
    assert len(result.tags) >= 1
    for point in result.l1_outline:
        assert point.point
        assert len(point.anchors) >= 1
        assert all(a.startswith("¶") for a in point.anchors)
```

**Step 3: Implement SummarizationService**

```python
# backend/app/services/summarizer.py
import anthropic
from app.config import settings
from app.services.extractor import ExtractedContent
from app.schemas.summary import ContentSummary, OutlinePoint

class SummarizationService:
    def __init__(self):
        self.client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    async def summarize(self, content: ExtractedContent) -> ContentSummary:
        # Build paragraph-annotated text for the prompt
        annotated_text = "\n\n".join(
            f"[{p.anchor_id}] {p.text}" for p in content.paragraphs
        )

        message = self.client.messages.create(
            model="claude-sonnet-4-5-20250514",
            max_tokens=2000,
            messages=[{
                "role": "user",
                "content": f"""Analyze the following content and produce a structured summary.

CONTENT:
{annotated_text}

REQUIREMENTS:
1. l0_summary: A one-line summary in ≤30 Chinese characters (or ≤60 English characters). Capture the core message.
2. l1_outline: 3-5 key points. Each point must:
   - Be a concise statement (15-30 characters)
   - Include "anchors" array citing specific paragraph IDs (e.g., ["¶3", "¶7"]) from the content that support this point
   - Only cite paragraphs that actually contain evidence for the point
3. tags: 3-5 topic tags
4. keywords: 5-10 important keywords

Respond in this exact JSON format:
{{
  "l0_summary": "...",
  "l1_outline": [
    {{"point": "...", "anchors": ["¶N", "¶M"]}},
    ...
  ],
  "tags": ["...", "..."],
  "keywords": ["...", "..."]
}}

JSON only, no other text."""
            }],
        )

        import json
        raw = message.content[0].text
        # Strip markdown code block if present
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
        data = json.loads(raw)
        return ContentSummary(**data)

    async def expand_point(self, content: ExtractedContent, point: OutlinePoint) -> str:
        """L2: Expand a specific outline point with detailed explanation."""
        annotated_text = "\n\n".join(
            f"[{p.anchor_id}] {p.text}" for p in content.paragraphs
        )

        message = self.client.messages.create(
            model="claude-sonnet-4-5-20250514",
            max_tokens=1000,
            messages=[{
                "role": "user",
                "content": f"""Based on the following content, expand on this specific point in detail.

POINT: {point.point}
RELEVANT PARAGRAPHS: {', '.join(point.anchors)}

FULL CONTENT:
{annotated_text}

Write 2-3 paragraphs explaining this point in detail. Cite specific paragraphs using [¶N] notation. Every claim must be traceable to the original text."""
            }],
        )
        return message.content[0].text

    async def ask_followup(self, content: ExtractedContent, question: str) -> str:
        """L3: Answer a follow-up question about the content."""
        annotated_text = "\n\n".join(
            f"[{p.anchor_id}] {p.text}" for p in content.paragraphs
        )

        message = self.client.messages.create(
            model="claude-sonnet-4-5-20250514",
            max_tokens=800,
            messages=[{
                "role": "user",
                "content": f"""Answer this question based ONLY on the following content. Cite specific paragraphs using [¶N] notation. If the answer is not in the content, say so.

QUESTION: {question}

CONTENT:
{annotated_text}"""
            }],
        )
        return message.content[0].text
```

**Step 4: Run tests (requires ANTHROPIC_API_KEY in env)**

Run: `pytest tests/test_summarizer.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add backend/app/services/summarizer.py backend/app/schemas/ backend/tests/test_summarizer.py
git commit -m "feat: add AI summarization with Claude structured output and source tracing"
```

---

## Task 6: Backend — Content Processing Pipeline & API Routes

**Files:**
- Create: `backend/app/services/pipeline.py`
- Create: `backend/app/routers/content.py`
- Create: `backend/app/schemas/content.py`
- Modify: `backend/app/main.py` — register router

**Step 1: Define API schemas**

```python
# backend/app/schemas/content.py
from pydantic import BaseModel
from datetime import datetime

class ContentCreateRequest(BaseModel):
    source_type: str  # url / text / pdf / image
    body: str         # URL string, raw text, or base64-encoded file
    source_app_name: str | None = None
    source_app_bundle_id: str | None = None
    channel: str = "manual"

class ContentResponse(BaseModel):
    id: str
    title: str
    source_url: str | None
    source_type: str
    source_app_name: str | None
    l0_summary: str | None
    l1_outline: list[dict] | None
    tags: list[str] | None
    status: str
    created_at: datetime
    podcast_url: str | None = None

class ExpandRequest(BaseModel):
    point_index: int

class FollowUpRequest(BaseModel):
    question: str

class TextResponse(BaseModel):
    text: str
```

**Step 2: Create processing pipeline**

```python
# backend/app/services/pipeline.py
import uuid
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from app.models.content import Content
from app.models.paragraph import Paragraph
from app.services.extractor import ContentExtractor
from app.services.summarizer import SummarizationService

class ProcessingPipeline:
    def __init__(self):
        self.extractor = ContentExtractor()
        self.summarizer = SummarizationService()

    async def process(self, source_type: str, body: str, user_id: str,
                      source_app_name: str | None = None,
                      source_app_bundle_id: str | None = None,
                      channel: str = "manual",
                      db: AsyncSession = None) -> Content:
        content_id = str(uuid.uuid4())

        # Step 1: Extract content
        if source_type == "url":
            extracted = await self.extractor.extract_url(body)
        elif source_type == "text":
            extracted = await self.extractor.extract_text(body)
        elif source_type == "pdf":
            extracted = await self.extractor.extract_pdf(body)
        elif source_type == "image":
            extracted = await self.extractor.extract_image(body)
        else:
            raise ValueError(f"Unsupported source_type: {source_type}")

        # Step 2: AI Summarize
        summary = await self.summarizer.summarize(extracted)

        # Step 3: Store in DB
        content = Content(
            id=content_id,
            title=extracted.title,
            source_url=extracted.source_url,
            source_type=source_type,
            source_app_name=source_app_name,
            source_app_bundle_id=source_app_bundle_id,
            channel=channel,
            l0_summary=summary.l0_summary,
            l1_outline=[p.model_dump() for p in summary.l1_outline],
            tags=summary.tags,
            keywords=summary.keywords,
            full_text=extracted.full_text,
            status="ready",
            user_id=user_id,
        )
        db.add(content)

        # Step 4: Store paragraphs
        for para in extracted.paragraphs:
            db.add(Paragraph(
                content_id=content_id,
                anchor_id=para.anchor_id,
                text=para.text,
                position=para.position,
            ))

        await db.commit()

        # Step 5: Update full-text search vectors
        await db.execute(text("""
            UPDATE contents SET full_text_tsv =
                setweight(to_tsvector('simple', coalesce(title,'')), 'A') ||
                setweight(to_tsvector('simple', coalesce(l0_summary,'')), 'A') ||
                setweight(to_tsvector('simple', coalesce(full_text,'')), 'C')
            WHERE id = :id
        """), {"id": content_id})

        await db.execute(text("""
            UPDATE paragraphs SET full_text_tsv = to_tsvector('simple', text)
            WHERE content_id = :id
        """), {"id": content_id})

        await db.commit()
        return content
```

**Step 3: Create API router**

```python
# backend/app/routers/content.py
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc
from app.database import get_db
from app.models.content import Content
from app.models.paragraph import Paragraph
from app.schemas.content import (
    ContentCreateRequest, ContentResponse, ExpandRequest, FollowUpRequest, TextResponse,
)
from app.services.pipeline import ProcessingPipeline
from app.services.summarizer import SummarizationService
from app.services.extractor import ExtractedContent, ExtractedParagraph
from app.schemas.summary import OutlinePoint

router = APIRouter(prefix="/api/v1/content", tags=["content"])
pipeline = ProcessingPipeline()
summarizer = SummarizationService()

# TODO: Replace with Clerk auth middleware
def get_current_user_id() -> str:
    return "dev-user"

@router.post("/", response_model=ContentResponse)
async def create_content(
    req: ContentCreateRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    content = await pipeline.process(
        source_type=req.source_type,
        body=req.body,
        user_id=user_id,
        source_app_name=req.source_app_name,
        source_app_bundle_id=req.source_app_bundle_id,
        channel=req.channel,
        db=db,
    )
    return _to_response(content)

@router.get("/", response_model=list[ContentResponse])
async def list_contents(
    skip: int = 0,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    result = await db.execute(
        select(Content)
        .where(Content.user_id == user_id)
        .order_by(desc(Content.created_at))
        .offset(skip).limit(limit)
    )
    return [_to_response(c) for c in result.scalars()]

@router.get("/{content_id}", response_model=ContentResponse)
async def get_content(content_id: str, db: AsyncSession = Depends(get_db)):
    content = await db.get(Content, content_id)
    if not content:
        raise HTTPException(404, "Content not found")
    return _to_response(content)

@router.get("/{content_id}/paragraphs")
async def get_paragraphs(content_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Paragraph)
        .where(Paragraph.content_id == content_id)
        .order_by(Paragraph.position)
    )
    return [{"anchor_id": p.anchor_id, "text": p.text, "position": p.position}
            for p in result.scalars()]

@router.post("/{content_id}/expand", response_model=TextResponse)
async def expand_point(content_id: str, req: ExpandRequest, db: AsyncSession = Depends(get_db)):
    content = await db.get(Content, content_id)
    if not content:
        raise HTTPException(404)
    paras_result = await db.execute(
        select(Paragraph).where(Paragraph.content_id == content_id).order_by(Paragraph.position)
    )
    paras = list(paras_result.scalars())
    extracted = ExtractedContent(
        title=content.title,
        full_text=content.full_text or "",
        paragraphs=[ExtractedParagraph(anchor_id=p.anchor_id, text=p.text, position=p.position) for p in paras],
    )
    outline = content.l1_outline or []
    if req.point_index >= len(outline):
        raise HTTPException(400, "Invalid point index")
    point = OutlinePoint(**outline[req.point_index])
    detail = await summarizer.expand_point(extracted, point)
    return TextResponse(text=detail)

@router.post("/{content_id}/ask", response_model=TextResponse)
async def ask_followup(content_id: str, req: FollowUpRequest, db: AsyncSession = Depends(get_db)):
    content = await db.get(Content, content_id)
    if not content:
        raise HTTPException(404)
    paras_result = await db.execute(
        select(Paragraph).where(Paragraph.content_id == content_id).order_by(Paragraph.position)
    )
    paras = list(paras_result.scalars())
    extracted = ExtractedContent(
        title=content.title,
        full_text=content.full_text or "",
        paragraphs=[ExtractedParagraph(anchor_id=p.anchor_id, text=p.text, position=p.position) for p in paras],
    )
    answer = await summarizer.ask_followup(extracted, req.question)
    return TextResponse(text=answer)

def _to_response(c: Content) -> ContentResponse:
    return ContentResponse(
        id=c.id, title=c.title, source_url=c.source_url,
        source_type=c.source_type, source_app_name=c.source_app_name,
        l0_summary=c.l0_summary, l1_outline=c.l1_outline,
        tags=c.tags, status=c.status, created_at=c.created_at,
    )
```

**Step 4: Register router in main.py**

```python
# Add to backend/app/main.py
from app.routers.content import router as content_router
app.include_router(content_router)
```

**Step 5: Test API manually**

Run: `uvicorn app.main:app --reload`
Run: `curl -X POST http://localhost:8000/api/v1/content/ -H 'Content-Type: application/json' -d '{"source_type":"text","body":"This is a long test article about AI pricing..."}'`
Expected: Returns JSON with id, l0_summary, l1_outline with anchors

**Step 6: Commit**

```bash
git add backend/
git commit -m "feat: add content processing pipeline with extract → summarize → store"
```

---

## Task 7: Backend — Search Agent

**Files:**
- Create: `backend/app/services/search_agent.py`
- Create: `backend/app/routers/search.py`
- Create: `backend/tests/test_search.py`

**Step 1: Implement Search Agent**

```python
# backend/app/services/search_agent.py
import json
import anthropic
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text, desc
from app.config import settings
from app.models.content import Content

class SearchAgent:
    def __init__(self):
        self.client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    async def search(self, query: str, user_id: str, db: AsyncSession) -> dict:
        # Step 1: Parse intent with AI
        intent = await self._parse_intent(query)

        # Step 2: Build and execute SQL query
        candidates = await self._search_index(intent, user_id, db)

        if not candidates:
            return {"answer": "No matching content found.", "sources": []}

        # Step 3: Rank candidates with AI
        ranked = await self._rank_candidates(query, candidates)

        # Step 4: Generate answer
        answer = await self._generate_answer(query, ranked)

        return answer

    async def _parse_intent(self, query: str) -> dict:
        message = self.client.messages.create(
            model="claude-haiku-3-5-20241022",
            max_tokens=300,
            messages=[{"role": "user", "content": f"""Parse this search query into structured intent.
Query: "{query}"

Return JSON:
{{"search_terms": ["keyword1", "keyword2"], "time_filter": "7d" or "30d" or null, "source_type": "url" or "pdf" or null}}

JSON only."""}],
        )
        raw = message.content[0].text
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
        return json.loads(raw)

    async def _search_index(self, intent: dict, user_id: str, db: AsyncSession) -> list[Content]:
        terms = intent.get("search_terms", [])
        ts_query = " | ".join(terms) if terms else ""

        sql = """
            SELECT *, ts_rank_cd(full_text_tsv, to_tsquery('simple', :query)) AS rank
            FROM contents
            WHERE user_id = :user_id
              AND full_text_tsv @@ to_tsquery('simple', :query)
        """
        params = {"user_id": user_id, "query": ts_query}

        time_filter = intent.get("time_filter")
        if time_filter == "7d":
            sql += " AND created_at > NOW() - INTERVAL '7 days'"
        elif time_filter == "30d":
            sql += " AND created_at > NOW() - INTERVAL '30 days'"

        sql += " ORDER BY rank DESC LIMIT 10"

        result = await db.execute(text(sql), params)
        rows = result.fetchall()

        # Fallback: if FTS returns nothing, try tag/keyword match
        if not rows and terms:
            tag_sql = """
                SELECT * FROM contents
                WHERE user_id = :user_id AND (tags && :terms OR keywords && :terms)
                ORDER BY created_at DESC LIMIT 10
            """
            result = await db.execute(text(tag_sql), {"user_id": user_id, "terms": terms})
            rows = result.fetchall()

        return rows

    async def _rank_candidates(self, query: str, candidates: list) -> list:
        if len(candidates) <= 3:
            return candidates

        summaries = "\n".join(
            f"[{i}] {c.title} — {c.l0_summary} (tags: {c.tags})"
            for i, c in enumerate(candidates)
        )
        message = self.client.messages.create(
            model="claude-haiku-3-5-20241022",
            max_tokens=100,
            messages=[{"role": "user", "content": f"""Rank these by relevance to: "{query}"
{summaries}
Return JSON array of indices, most relevant first. JSON only."""}],
        )
        raw = message.content[0].text
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
        indices = json.loads(raw)
        return [candidates[i] for i in indices if i < len(candidates)]

    async def _generate_answer(self, query: str, sources: list) -> dict:
        context = "\n\n".join(
            f"Source: {s.title}\nSummary: {s.l0_summary}\nOutline: {json.dumps(s.l1_outline, ensure_ascii=False)}"
            for s in sources[:5]
        )
        message = self.client.messages.create(
            model="claude-sonnet-4-5-20250514",
            max_tokens=500,
            messages=[{"role": "user", "content": f"""Answer this question using ONLY the provided sources. Cite each source by title.

Question: {query}

Sources:
{context}

If the answer spans multiple sources, synthesize them. If no source answers the question, say so."""}],
        )
        return {
            "answer": message.content[0].text,
            "sources": [
                {"id": s.id, "title": s.title, "l0_summary": s.l0_summary, "source_url": s.source_url}
                for s in sources[:5]
            ],
        }
```

**Step 2: Create search router**

```python
# backend/app/routers/search.py
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.services.search_agent import SearchAgent

router = APIRouter(prefix="/api/v1/search", tags=["search"])
agent = SearchAgent()

def get_current_user_id() -> str:
    return "dev-user"

class SearchRequest(BaseModel):
    query: str

@router.post("/")
async def search(
    req: SearchRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_current_user_id),
):
    return await agent.search(req.query, user_id, db)
```

**Step 3: Register router**

Add to `backend/app/main.py`:
```python
from app.routers.search import router as search_router
app.include_router(search_router)
```

**Step 4: Commit**

```bash
git add backend/
git commit -m "feat: add agentic search with intent parsing, FTS, and AI ranking"
```

---

## Task 8: Backend — Podcast Generation Service

**Files:**
- Create: `backend/app/services/podcast.py`
- Create: `backend/app/services/storage.py`
- Create: `backend/app/routers/podcast.py`

**Step 1: Create R2 storage service**

```python
# backend/app/services/storage.py
import boto3
from app.config import settings

class StorageService:
    def __init__(self):
        self.s3 = boto3.client(
            "s3",
            endpoint_url=settings.r2_endpoint,
            aws_access_key_id=settings.r2_access_key,
            aws_secret_access_key=settings.r2_secret_key,
        )
        self.bucket = settings.r2_bucket

    def upload_audio(self, key: str, data: bytes) -> str:
        self.s3.put_object(Bucket=self.bucket, Key=key, Body=data, ContentType="audio/mpeg")
        return f"{settings.r2_endpoint}/{self.bucket}/{key}"

    def get_presigned_url(self, key: str, expires_in: int = 3600) -> str:
        return self.s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=expires_in,
        )
```

**Step 2: Create podcast generation service**

```python
# backend/app/services/podcast.py
import uuid
import json
import httpx
import anthropic
from sqlalchemy.ext.asyncio import AsyncSession
from app.config import settings
from app.models.content import Content
from app.models.podcast import Podcast
from app.services.storage import StorageService

class PodcastService:
    def __init__(self):
        self.ai = anthropic.Anthropic(api_key=settings.anthropic_api_key)
        self.storage = StorageService()

    async def generate(self, content: Content, db: AsyncSession) -> Podcast:
        podcast_id = str(uuid.uuid4())
        podcast = Podcast(id=podcast_id, content_id=content.id, status="generating")
        db.add(podcast)
        await db.commit()

        try:
            # Step 1: Generate podcast script from outline
            script = await self._generate_script(content)

            # Step 2: Generate audio via ElevenLabs Text to Dialogue
            audio_bytes = await self._generate_audio(script["dialogue"])

            # Step 3: Upload to R2
            key = f"podcasts/{content.user_id}/{podcast_id}.mp3"
            audio_url = self.storage.upload_audio(key, audio_bytes)

            # Step 4: Update podcast record
            podcast.audio_url = audio_url
            podcast.script = script
            podcast.chapters = script.get("chapters", [])
            podcast.status = "ready"

        except Exception as e:
            podcast.status = "failed"
            podcast.script = {"error": str(e)}

        await db.commit()
        return podcast

    async def _generate_script(self, content: Content) -> dict:
        outline_text = json.dumps(content.l1_outline, ensure_ascii=False)
        message = self.ai.messages.create(
            model="claude-sonnet-4-5-20250514",
            max_tokens=3000,
            messages=[{"role": "user", "content": f"""Create a podcast dialogue script for two hosts discussing this content.

TITLE: {content.title}
SUMMARY: {content.l0_summary}
OUTLINE:
{outline_text}

Requirements:
1. Two speakers: Host A (introduces topics) and Host B (provides analysis)
2. Natural conversational tone, NOT a dry reading
3. Cover each outline point as a separate chapter
4. Include an intro and outro
5. Total length: ~3-5 minutes when spoken

Return JSON:
{{
  "dialogue": "Host A: Welcome to... Host B: Thanks...",
  "chapters": [
    {{"title": "Introduction", "outline_point_index": null}},
    {{"title": "Chapter title matching outline point", "outline_point_index": 0}},
    ...
  ]
}}
JSON only."""}],
        )
        raw = message.content[0].text
        if raw.startswith("```"):
            raw = raw.split("\n", 1)[1].rsplit("```", 1)[0]
        return json.loads(raw)

    async def _generate_audio(self, dialogue_text: str) -> bytes:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                "https://api.elevenlabs.io/v1/text-to-dialogue",
                headers={
                    "xi-api-key": settings.elevenlabs_api_key,
                    "Content-Type": "application/json",
                },
                json={"text": dialogue_text},
                timeout=120,
            )
            resp.raise_for_status()
            return resp.content
```

**Step 3: Create podcast router**

```python
# backend/app/routers/podcast.py
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.ext.asyncio import AsyncSession
from app.database import get_db
from app.models.content import Content
from app.models.podcast import Podcast
from app.services.podcast import PodcastService
from sqlalchemy import select

router = APIRouter(prefix="/api/v1/podcast", tags=["podcast"])
podcast_service = PodcastService()

@router.post("/{content_id}/generate")
async def generate_podcast(
    content_id: str,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
):
    content = await db.get(Content, content_id)
    if not content:
        raise HTTPException(404)
    # Check for existing podcast
    existing = await db.execute(
        select(Podcast).where(Podcast.content_id == content_id, Podcast.status == "ready")
    )
    if existing.scalar_one_or_none():
        raise HTTPException(409, "Podcast already exists")

    podcast = await podcast_service.generate(content, db)
    return {"id": podcast.id, "status": podcast.status}

@router.get("/{content_id}")
async def get_podcast(content_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Podcast).where(Podcast.content_id == content_id).order_by(Podcast.created_at.desc())
    )
    podcast = result.scalar_one_or_none()
    if not podcast:
        raise HTTPException(404)
    return {
        "id": podcast.id, "status": podcast.status,
        "audio_url": podcast.audio_url, "chapters": podcast.chapters,
    }
```

**Step 4: Register router and commit**

Add to `main.py`:
```python
from app.routers.podcast import router as podcast_router
app.include_router(podcast_router)
```

```bash
git add backend/
git commit -m "feat: add podcast generation with ElevenLabs and R2 storage"
```

---

## Task 9: macOS — Global Hotkeys + Source App Capture + Text Capture

**Files:**
- Create: `macos/Sources/App/Services/HotkeyService.swift`
- Create: `macos/Sources/App/Services/TextCaptureService.swift`
- Modify: `macos/Sources/App/AppDelegate.swift`

**Step 1: Define hotkey names**

```swift
// macos/Sources/App/Services/HotkeyService.swift
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    // Global hotkeys
    static let silentImport = Self("silentImport", default: .init(.r, modifiers: [.option, .shift]))
    static let importAndDisplay = Self("importAndDisplay", default: .init(.d, modifiers: [.option, .shift]))
    static let importClipboard = Self("importClipboard", default: .init(.v, modifiers: [.option, .shift]))
    static let summonReadless = Self("summonReadless", default: .init(.s, modifiers: [.option, .shift]))
}

@MainActor
final class HotkeyService {
    private let textCapture = TextCaptureService()
    private let onSilentImport: (String, String?, String?) -> Void     // text, appName, bundleID
    private let onImportAndDisplay: (String, String?, String?) -> Void
    private let onSummon: () -> Void

    init(
        onSilentImport: @escaping (String, String?, String?) -> Void,
        onImportAndDisplay: @escaping (String, String?, String?) -> Void,
        onSummon: @escaping () -> Void
    ) {
        self.onSilentImport = onSilentImport
        self.onImportAndDisplay = onImportAndDisplay
        self.onSummon = onSummon

        KeyboardShortcuts.onKeyUp(for: .silentImport) { [weak self] in
            self?.handleImport(display: false)
        }
        KeyboardShortcuts.onKeyUp(for: .importAndDisplay) { [weak self] in
            self?.handleImport(display: true)
        }
        KeyboardShortcuts.onKeyUp(for: .importClipboard) { [weak self] in
            self?.handleClipboardImport()
        }
        KeyboardShortcuts.onKeyUp(for: .summonReadless) { [weak self] in
            self?.onSummon()
        }
    }

    private func handleImport(display: Bool) {
        // Capture source app BEFORE our window activates
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let appName = sourceApp?.localizedName
        let bundleID = sourceApp?.bundleIdentifier

        // Get selected text
        if let text = textCapture.getSelectedText(), !text.isEmpty {
            if display {
                onImportAndDisplay(text, appName, bundleID)
            } else {
                onSilentImport(text, appName, bundleID)
            }
        } else {
            // Fallback: copy to clipboard then read
            textCapture.simulateCopyAndRead { [weak self] text in
                guard let self, let text, !text.isEmpty else { return }
                if display {
                    self.onImportAndDisplay(text, appName, bundleID)
                } else {
                    self.onSilentImport(text, appName, bundleID)
                }
            }
        }
    }

    private func handleClipboardImport() {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onSilentImport(text, sourceApp?.localizedName, sourceApp?.bundleIdentifier)
    }
}
```

**Step 2: Create text capture service**

```swift
// macos/Sources/App/Services/TextCaptureService.swift
import AppKit
import ApplicationServices

final class TextCaptureService {

    func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement
        ) == .success else { return nil }

        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText
        ) == .success else { return nil }

        return selectedText as? String
    }

    func simulateCopyAndRead(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Simulate Cmd+C
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let newContent = pasteboard.string(forType: .string)
            if newContent != previousContent {
                completion(newContent)
            } else {
                completion(nil)
            }
        }
    }
}
```

**Step 3: Initialize in AppDelegate**

```swift
// macos/Sources/App/AppDelegate.swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var hotkeyService: HotkeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeyService = HotkeyService(
            onSilentImport: { text, appName, bundleID in
                Task { await ContentManager.shared.importSilently(text: text, appName: appName, bundleID: bundleID) }
            },
            onImportAndDisplay: { text, appName, bundleID in
                Task { await ContentManager.shared.importAndDisplay(text: text, appName: appName, bundleID: bundleID) }
            },
            onSummon: {
                // Show floating search panel
                NotificationCenter.default.post(name: .showSummonPanel, object: nil)
            }
        )
    }
}

extension Notification.Name {
    static let showSummonPanel = Notification.Name("showSummonPanel")
}
```

**Step 4: Commit**

```bash
git add macos/Sources/App/Services/ macos/Sources/App/AppDelegate.swift
git commit -m "feat: add global hotkeys with source app capture and text extraction"
```

---

## Task 10: macOS — Floating Capsule Progress Indicator

**Files:**
- Create: `macos/Sources/UI/CapsuleProgressView.swift`
- Create: `macos/Sources/UI/FloatingPanel.swift`
- Create: `macos/Sources/UI/WaveAnimation.swift`

**Step 1: Create wave animation**

```swift
// macos/Sources/UI/WaveAnimation.swift
import SwiftUI

public struct WaveAnimation: View {
    @State private var phase: CGFloat = 0
    let isActive: Bool

    public init(isActive: Bool = true) {
        self.isActive = isActive
    }

    public var body: some View {
        Canvas { context, size in
            let dotCount = 12
            let dotSize: CGFloat = 4
            let spacing = size.width / CGFloat(dotCount + 1)

            for i in 0..<dotCount {
                let x = spacing * CGFloat(i + 1)
                let wave = sin(phase + CGFloat(i) * 0.5) * 0.5 + 0.5
                let opacity = isActive ? (0.3 + wave * 0.7) : 0.3
                let scale = isActive ? (0.6 + wave * 0.4) : 0.6
                let y = size.height / 2

                context.opacity = opacity
                let rect = CGRect(
                    x: x - dotSize * scale / 2,
                    y: y - dotSize * scale / 2,
                    width: dotSize * scale,
                    height: dotSize * scale
                )
                context.fill(Circle().path(in: rect), with: .color(.white))
            }
        }
        .frame(height: 20)
        .onAppear {
            guard isActive else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}
```

**Step 2: Create floating panel wrapper**

```swift
// macos/Sources/UI/FloatingPanel.swift
import SwiftUI
import AppKit

public class FloatingPanelWindow: NSPanel {
    public override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView],
        backing: NSWindow.BackingStoreType = .buffered,
        defer flag: Bool = false
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }
}
```

**Step 3: Create capsule progress view**

```swift
// macos/Sources/UI/CapsuleProgressView.swift
import SwiftUI
import AppKit

public enum CapsuleState {
    case processing
    case completed
    case dismissed
}

public struct CapsuleProgressView: View {
    @Binding var state: CapsuleState
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var appear = false

    public init(state: Binding<CapsuleState>, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self._state = state
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)

            // Wave animation
            WaveAnimation(isActive: state == .processing)
                .frame(width: 140)

            // Confirm button
            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(state == .completed ? .white : .white.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(state == .completed ? Color.green.opacity(0.6) : .white.opacity(0.1))
                    )
                    .scaleEffect(state == .completed ? 1.1 : 1.0)
                    .animation(.spring(duration: 0.3, bounce: 0.4), value: state)
            }
            .buttonStyle(.plain)
            .disabled(state != .completed)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
        .scaleEffect(appear ? 1 : 0.8)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
        .onAppear {
            withAnimation(.spring(duration: 0.3, bounce: 0.15)) {
                appear = true
            }
        }
    }

    public func dismiss() {
        withAnimation(.smooth(duration: 0.2)) {
            appear = false
        }
    }
}
```

**Step 4: Build and verify**

Run: `cd macos && swift build`
Expected: Build succeeds.

**Step 5: Commit**

```bash
git add macos/Sources/UI/
git commit -m "feat: add floating capsule progress indicator with wave animation"
```

---

## Task 11: macOS — Reader View (Multi-Level Summary + Source Tracing)

**Files:**
- Create: `macos/Sources/App/Views/ReaderView.swift`
- Create: `macos/Sources/App/Views/OutlineView.swift`
- Create: `macos/Sources/App/Views/SourceTracePanel.swift`
- Create: `macos/Sources/App/ViewModels/ReaderViewModel.swift`

**Step 1: Create ReaderViewModel**

```swift
// macos/Sources/App/ViewModels/ReaderViewModel.swift
import Foundation
import Core
import Networking

@MainActor
@Observable
final class ReaderViewModel {
    var content: Content?
    var paragraphs: [(anchorID: String, text: String)] = []
    var expandedDetails: [Int: String] = [:]  // point_index -> detail text
    var focusedIndex: Int = 0
    var showSourcePanel: Bool = false
    var sourceAnchorID: String?
    var followUpAnswer: String?
    var isLoadingExpand: Bool = false

    private let api = APIClient()

    func loadParagraphs(contentID: String) async {
        // Fetch from API
    }

    func expandPoint(at index: Int) async {
        guard expandedDetails[index] == nil else { return }
        isLoadingExpand = true
        // Call API /content/{id}/expand
        isLoadingExpand = false
    }

    func traceSource(anchors: [String]) {
        sourceAnchorID = anchors.first
        showSourcePanel = true
    }

    func askFollowUp(question: String) async {
        // Call API /content/{id}/ask
    }

    // Keyboard navigation
    func moveDown() {
        guard let outline = content?.l1Outline else { return }
        if focusedIndex < outline.count - 1 { focusedIndex += 1 }
    }

    func moveUp() {
        if focusedIndex > 0 { focusedIndex -= 1 }
    }
}
```

**Step 2: Create OutlineView**

```swift
// macos/Sources/App/Views/OutlineView.swift
import SwiftUI
import Core
import UI

struct OutlineView: View {
    let points: [OutlinePoint]
    @Binding var focusedIndex: Int
    let expandedDetails: [Int: String]
    let onExpand: (Int) -> Void
    let onTrace: ([String]) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        OutlinePointRow(
                            point: point,
                            index: index,
                            isFocused: index == focusedIndex,
                            expandedDetail: expandedDetails[index],
                            onExpand: { onExpand(index) },
                            onTrace: { onTrace(point.anchors) }
                        )
                        .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: focusedIndex) { _, newIndex in
                withAnimation(Theme.snapAnimation) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

struct OutlinePointRow: View {
    let point: OutlinePoint
    let index: Int
    let isFocused: Bool
    let expandedDetail: String?
    let onExpand: () -> Void
    let onTrace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Focus indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(isFocused ? Theme.focusBorder : .clear)
                    .frame(width: 3)
                    .animation(Theme.snapAnimation, value: isFocused)

                VStack(alignment: .leading, spacing: 4) {
                    // Point text
                    Text("\(index + 1). \(point.point)")
                        .font(Theme.l1Font)
                        .foregroundStyle(isFocused ? .primary : .secondary)

                    // Anchor citations
                    HStack(spacing: 4) {
                        ForEach(point.anchors, id: \.self) { anchor in
                            Button(anchor) { onTrace() }
                                .font(Theme.citationFont)
                                .foregroundStyle(Theme.citationColor)
                                .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                // Expand chevron
                Image(systemName: expandedDetail != nil ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expandedDetail != nil ? 0 : 0))
            }

            // L2 Expanded detail
            if let detail = expandedDetail {
                Text(detail)
                    .font(Theme.l2Font)
                    .foregroundStyle(.secondary)
                    .lineSpacing(Theme.lineSpacing)
                    .padding(.leading, 16)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onExpand() }
    }
}
```

**Step 3: Create SourceTracePanel**

```swift
// macos/Sources/App/Views/SourceTracePanel.swift
import SwiftUI
import UI

struct SourceTracePanel: View {
    let paragraphs: [(anchorID: String, text: String)]
    let highlightAnchor: String?
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Original Text")
                    .font(.headline)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Paragraphs
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(paragraphs, id: \.anchorID) { para in
                            HStack(alignment: .top, spacing: 8) {
                                Text(para.anchorID)
                                    .font(Theme.citationFont)
                                    .foregroundStyle(Theme.citationColor)
                                    .frame(width: 30, alignment: .trailing)

                                Text(para.text)
                                    .font(Theme.l2Font)
                                    .lineSpacing(Theme.lineSpacing)
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(para.anchorID == highlightAnchor
                                                  ? Color.yellow.opacity(0.15)
                                                  : .clear)
                                    )
                            }
                            .id(para.anchorID)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    if let anchor = highlightAnchor {
                        withAnimation {
                            proxy.scrollTo(anchor, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 350, maxWidth: 450)
        .background(.ultraThinMaterial)
    }
}
```

**Step 4: Create ReaderView with keyboard support**

```swift
// macos/Sources/App/Views/ReaderView.swift
import SwiftUI
import Core
import UI

struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()
    let content: Content

    var body: some View {
        HSplitView {
            // Main reader
            VStack(alignment: .leading, spacing: 16) {
                // L0 Summary
                Text(content.l0Summary ?? "Processing...")
                    .font(Theme.l0Font)
                    .padding(.horizontal)
                    .padding(.top)

                // Source info
                if let appName = content.sourceAppName {
                    Text("from \(appName)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal)
                }

                Divider()

                // L1 Outline
                if let points = content.l1Outline {
                    OutlineView(
                        points: points,
                        focusedIndex: $viewModel.focusedIndex,
                        expandedDetails: viewModel.expandedDetails,
                        onExpand: { index in
                            Task { await viewModel.expandPoint(at: index) }
                        },
                        onTrace: { anchors in
                            viewModel.traceSource(anchors: anchors)
                        }
                    )
                }
            }
            .frame(minWidth: 400)

            // Source trace panel (right side)
            if viewModel.showSourcePanel {
                SourceTracePanel(
                    paragraphs: viewModel.paragraphs,
                    highlightAnchor: viewModel.sourceAnchorID,
                    isPresented: $viewModel.showSourcePanel
                )
                .transition(.move(edge: .trailing))
            }
        }
        .focusable()
        .onKeyPress(.downArrow) { viewModel.moveDown(); return .handled }
        .onKeyPress(.upArrow) { viewModel.moveUp(); return .handled }
        .onKeyPress(characters: "j") { viewModel.moveDown(); return .handled }
        .onKeyPress(characters: "k") { viewModel.moveUp(); return .handled }
        .onKeyPress(.return) {
            Task { await viewModel.expandPoint(at: viewModel.focusedIndex) }
            return .handled
        }
        .onKeyPress(characters: "s") {
            if let points = content.l1Outline, viewModel.focusedIndex < points.count {
                viewModel.traceSource(anchors: points[viewModel.focusedIndex].anchors)
            }
            return .handled
        }
        .onKeyPress(characters: "p") {
            // Trigger podcast generation
            return .handled
        }
        .onKeyPress(.escape) {
            viewModel.showSourcePanel = false
            return .handled
        }
    }
}
```

**Step 5: Build and commit**

Run: `cd macos && swift build`

```bash
git add macos/Sources/App/Views/ macos/Sources/App/ViewModels/
git commit -m "feat: add reader view with multi-level outline, source tracing, and vim-style navigation"
```

---

## Task 12: macOS — Settings + Hotkey Customization

**Files:**
- Modify: `macos/Sources/App/ReadlessApp.swift` — update SettingsView
- Create: `macos/Sources/App/Views/HotkeySettingsView.swift`

**Step 1: Create hotkey settings view**

```swift
// macos/Sources/App/Views/HotkeySettingsView.swift
import SwiftUI
import KeyboardShortcuts

struct HotkeySettingsView: View {
    var body: some View {
        Form {
            Section("Global Hotkeys") {
                KeyboardShortcuts.Recorder("Silent Import:", name: .silentImport)
                    .help("Import selected text silently into knowledge base")
                KeyboardShortcuts.Recorder("Import & Display:", name: .importAndDisplay)
                    .help("Import and show processing capsule + result")
                KeyboardShortcuts.Recorder("Import Clipboard:", name: .importClipboard)
                    .help("Import current clipboard content silently")
                KeyboardShortcuts.Recorder("Summon Readless:", name: .summonReadless)
                    .help("Open floating search/import panel")
            }

            Section("In-App Navigation") {
                Text("J / K — Navigate outline points")
                Text("Enter — Expand focused point (L2)")
                Text("S — Trace to original source")
                Text("P — Generate podcast")
                Text("Q — Ask follow-up question")
                Text("H / L — Collapse / Expand")
                Text("1 / 2 / 3 — Switch summary level")
                Text("Space — Play/Pause podcast")
                Text("[ / ] — Previous/Next podcast chapter")
                Text("/ or ⌘F — Search knowledge base")
                Text("Esc — Dismiss / Go back")
            }
            .foregroundStyle(.secondary)
            .font(.system(.body, design: .monospaced))
        }
        .formStyle(.grouped)
        .frame(width: 500)
    }
}
```

**Step 2: Update SettingsView**

```swift
// Update in ReadlessApp.swift
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            HotkeySettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            ChannelsSettingsView()
                .tabItem { Label("Channels", systemImage: "antenna.radiowaves.left.and.right") }
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .frame(width: 550, height: 400)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("General settings placeholder")
        }
    }
}

struct ChannelsSettingsView: View {
    var body: some View {
        Form {
            Text("Folder watch, email, RSS settings placeholder")
        }
    }
}

struct AccountSettingsView: View {
    var body: some View {
        Form {
            Text("Account & subscription placeholder")
        }
    }
}
```

**Step 3: Build and commit**

```bash
git add macos/
git commit -m "feat: add settings with hotkey customization panel"
```

---

## Task 13: macOS — Folder Watch Service

**Files:**
- Create: `macos/Sources/App/Services/FolderWatchService.swift`

**Step 1: Implement folder watcher**

```swift
// macos/Sources/App/Services/FolderWatchService.swift
import Foundation
import CoreServices

final class FolderWatchService {
    private var stream: FSEventStreamRef?
    private let callback: ([String]) -> Void
    private var watchedPaths: [String] = []
    private var knownFiles: Set<String> = []

    init(callback: @escaping ([String]) -> Void) {
        self.callback = callback
    }

    func watch(paths: [String]) {
        stop()
        watchedPaths = paths

        // Snapshot existing files
        for path in paths {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
                for file in files {
                    knownFiles.insert("\(path)/\(file)")
                }
            }
        }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, clientInfo, numEvents, eventPaths, _, _ in
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let service = Unmanaged<FolderWatchService>.fromOpaque(clientInfo!).takeUnretainedValue()
                service.handleEvents(paths: paths)
            },
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func handleEvents(paths: [String]) {
        let supportedExtensions = Set(["pdf", "txt", "md", "docx", "png", "jpg", "jpeg", "html"])
        var newFiles: [String] = []

        for path in paths {
            guard !knownFiles.contains(path) else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            knownFiles.insert(path)
            newFiles.append(path)
        }

        if !newFiles.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.callback(newFiles)
            }
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
```

**Step 2: Commit**

```bash
git add macos/Sources/App/Services/FolderWatchService.swift
git commit -m "feat: add folder watch service with FSEvents"
```

---

## Task 14: Backend — Auth with Clerk

**Files:**
- Create: `backend/app/auth.py`
- Modify: `backend/app/routers/content.py` — replace stub auth
- Modify: `backend/app/routers/search.py` — replace stub auth

**Step 1: Create Clerk auth dependency**

```python
# backend/app/auth.py
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
```

**Step 2: Replace stub auth in routers**

Replace `get_current_user_id` import in `content.py` and `search.py`:
```python
from app.auth import get_current_user_id
```

Remove the local `def get_current_user_id() -> str: return "dev-user"` stubs.

**Step 3: Commit**

```bash
git add backend/app/auth.py backend/app/routers/
git commit -m "feat: add Clerk JWT auth middleware"
```

---

## Task 15: Integration — Content Manager (macOS Client ↔ Backend)

**Files:**
- Create: `macos/Sources/App/Services/ContentManager.swift`
- Modify: `macos/Sources/Networking/APIClient.swift` — add content endpoints

**Step 1: Extend APIClient with content endpoints**

```swift
// macos/Sources/Networking/APIClient.swift — add methods
import Foundation
import Core

public final class APIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    // Token will be set after auth
    public var authToken: String?

    public init(baseURL: URL = URL(string: "http://localhost:8000")!) {
        self.baseURL = baseURL
        self.session = .shared
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    public func createContent(sourceType: String, body: String, appName: String?, bundleID: String?) async throws -> Content {
        struct Req: Encodable {
            let source_type: String
            let body: String
            let source_app_name: String?
            let source_app_bundle_id: String?
        }
        let payload = try JSONEncoder().encode(Req(
            source_type: sourceType, body: body,
            source_app_name: appName, source_app_bundle_id: bundleID
        ))
        let data = try await request("/api/v1/content/", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(Content.self, from: data)
    }

    public func listContents(skip: Int = 0, limit: Int = 50) async throws -> [Content] {
        let data = try await request("/api/v1/content/?skip=\(skip)&limit=\(limit)")
        return try JSONDecoder.apiDecoder.decode([Content].self, from: data)
    }

    public func expandPoint(contentID: String, pointIndex: Int) async throws -> String {
        struct Req: Encodable { let point_index: Int }
        struct Resp: Decodable { let text: String }
        let payload = try JSONEncoder().encode(Req(point_index: pointIndex))
        let data = try await request("/api/v1/content/\(contentID)/expand", method: "POST", body: payload)
        return try JSONDecoder().decode(Resp.self, from: data).text
    }

    public func search(query: String) async throws -> SearchResult {
        struct Req: Encodable { let query: String }
        let payload = try JSONEncoder().encode(Req(query: query))
        let data = try await request("/api/v1/search/", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(SearchResult.self, from: data)
    }

    public func healthCheck() async throws -> Bool {
        let data = try await request("/health")
        return true
    }

    public enum APIError: Error {
        case serverError(Int)
    }
}

public struct SearchResult: Codable, Sendable {
    public let answer: String
    public let sources: [SearchSource]
}

public struct SearchSource: Codable, Sendable {
    public let id: String
    public let title: String
    public let l0Summary: String?
    public let sourceURL: String?
}

extension JSONDecoder {
    static let apiDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
```

**Step 2: Create ContentManager**

```swift
// macos/Sources/App/Services/ContentManager.swift
import Foundation
import AppKit
import Core
import Networking

@MainActor
@Observable
final class ContentManager {
    static let shared = ContentManager()

    var contents: [Content] = []
    var processingContent: Content?
    var capsuleState: CapsuleState = .dismissed
    var showResultPanel: Bool = false

    private let api = APIClient()

    func importSilently(text: String, appName: String?, bundleID: String?) async {
        // Show brief toast
        showToast("Received from \(appName ?? "clipboard")")
        do {
            let sourceType = text.hasPrefix("http") ? "url" : "text"
            let content = try await api.createContent(
                sourceType: sourceType, body: text,
                appName: appName, bundleID: bundleID
            )
            contents.insert(content, at: 0)
        } catch {
            showToast("Import failed: \(error.localizedDescription)")
        }
    }

    func importAndDisplay(text: String, appName: String?, bundleID: String?) async {
        // Show capsule
        capsuleState = .processing
        do {
            let sourceType = text.hasPrefix("http") ? "url" : "text"
            let content = try await api.createContent(
                sourceType: sourceType, body: text,
                appName: appName, bundleID: bundleID
            )
            contents.insert(content, at: 0)
            processingContent = content
            capsuleState = .completed

            // Auto-show result after 0.5s
            try? await Task.sleep(for: .milliseconds(500))
            if capsuleState == .completed {
                showResultPanel = true
                capsuleState = .dismissed
            }
        } catch {
            capsuleState = .dismissed
            showToast("Import failed: \(error.localizedDescription)")
        }
    }

    func cancelProcessing() {
        capsuleState = .dismissed
        processingContent = nil
    }

    func loadContents() async {
        do {
            contents = try await api.listContents()
        } catch {
            // Handle error
        }
    }

    private func showToast(_ message: String) {
        // Post notification for toast display
        NotificationCenter.default.post(name: .showToast, object: message)
    }
}

extension Notification.Name {
    static let showToast = Notification.Name("showToast")
}
```

**Step 3: Build and commit**

```bash
git add macos/
git commit -m "feat: add ContentManager bridging macOS client with backend API"
```

---

## Task 16: macOS — Audio Player for Podcasts

**Files:**
- Create: `macos/Sources/App/Views/PodcastPlayerView.swift`
- Create: `macos/Sources/App/ViewModels/PodcastPlayerViewModel.swift`

**Step 1: Create audio player ViewModel**

```swift
// macos/Sources/App/ViewModels/PodcastPlayerViewModel.swift
import AVFoundation
import Foundation

@MainActor
@Observable
final class PodcastPlayerViewModel: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: Double = 0
    var currentChapterIndex: Int = 0
    var chapters: [(title: String, outlinePointIndex: Int?)] = []

    private var player: AVPlayer?
    private var timeObserver: Any?

    func load(url: URL, chapters: [(title: String, outlinePointIndex: Int?)]) {
        self.chapters = chapters
        player = AVPlayer(url: url)
        // Observe time
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 10),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.currentTime = CMTimeGetSeconds(time)
            if self.duration > 0 {
                self.progress = self.currentTime / self.duration
            }
        }
        // Get duration
        Task {
            if let dur = try? await player?.currentItem?.asset.load(.duration) {
                duration = CMTimeGetSeconds(dur)
            }
        }
    }

    func togglePlayPause() {
        if isPlaying { player?.pause() } else { player?.play() }
        isPlaying.toggle()
    }

    func nextChapter() {
        if currentChapterIndex < chapters.count - 1 { currentChapterIndex += 1 }
    }

    func previousChapter() {
        if currentChapterIndex > 0 { currentChapterIndex -= 1 }
    }

    static func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
```

**Step 2: Create PodcastPlayerView**

```swift
// macos/Sources/App/Views/PodcastPlayerView.swift
import SwiftUI
import UI

struct PodcastPlayerView: View {
    @State private var viewModel = PodcastPlayerViewModel()

    var body: some View {
        VStack(spacing: 16) {
            // Progress
            Slider(value: $viewModel.progress, in: 0...1)
                .tint(Theme.accent)

            HStack {
                Text(PodcastPlayerViewModel.formatTime(viewModel.currentTime))
                Spacer()
                Text(PodcastPlayerViewModel.formatTime(viewModel.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)

            // Controls
            HStack(spacing: 32) {
                Button { viewModel.previousChapter() } label: {
                    Image(systemName: "backward.end.fill")
                }
                Button { viewModel.togglePlayPause() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button { viewModel.nextChapter() } label: {
                    Image(systemName: "forward.end.fill")
                }
            }
            .buttonStyle(.plain)

            // Chapters
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.chapters.enumerated()), id: \.offset) { index, chapter in
                        HStack {
                            Circle()
                                .fill(index == viewModel.currentChapterIndex ? Theme.accent : .tertiary)
                                .frame(width: 6, height: 6)
                            Text(chapter.title)
                                .font(index == viewModel.currentChapterIndex ? Theme.l1Font : Theme.l2Font)
                                .foregroundStyle(index == viewModel.currentChapterIndex ? .primary : .secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .focusable()
        .onKeyPress(.space) { viewModel.togglePlayPause(); return .handled }
        .onKeyPress(characters: "[") { viewModel.previousChapter(); return .handled }
        .onKeyPress(characters: "]") { viewModel.nextChapter(); return .handled }
    }
}
```

**Step 3: Commit**

```bash
git add macos/Sources/App/Views/PodcastPlayerView.swift macos/Sources/App/ViewModels/
git commit -m "feat: add podcast player with chapter navigation and keyboard controls"
```

---

## Task 17: End-to-End Integration & Polish

**Step 1: Wire up main ContentView with all components**
- Connect sidebar navigation to content list, reader, knowledge base
- Wire capsule overlay to ContentManager state
- Connect folder watch to import pipeline

**Step 2: Add toast notification system**
- Lightweight toast that appears for 1.5s on silent import

**Step 3: Test full flow**
- Start backend: `docker compose up`
- Build and run macOS app
- Test: ⌥⇧R (silent import) → ⌥⇧D (import & display) → J/K navigation → Enter expand → S trace → P podcast → ⌥⇧S search
- Verify source app capture shows correctly

**Step 4: Final commit**

```bash
git add .
git commit -m "feat: wire up end-to-end integration, toast notifications, capsule overlay"
```

---

## Summary

| Task | Component | Description |
|------|-----------|-------------|
| 1 | Backend | Project scaffolding (FastAPI, Docker, Caddy) |
| 2 | macOS | Project scaffolding (SPM, SwiftUI, modules) |
| 3 | Backend | Database schema + migrations (PostgreSQL FTS) |
| 4 | Backend | Content extraction (Trafilatura, PDF, OCR) |
| 5 | Backend | AI summarization (Claude structured output) |
| 6 | Backend | Processing pipeline + API routes |
| 7 | Backend | Search agent (agentic page index) |
| 8 | Backend | Podcast generation (ElevenLabs + R2) |
| 9 | macOS | Global hotkeys + source app capture |
| 10 | macOS | Floating capsule progress indicator |
| 11 | macOS | Reader view (outline + source tracing) |
| 12 | macOS | Settings + hotkey customization |
| 13 | macOS | Folder watch service |
| 14 | Backend | Auth with Clerk |
| 15 | macOS | ContentManager (client ↔ backend bridge) |
| 16 | macOS | Podcast player |
| 17 | Both | End-to-end integration & polish |

**Estimated total: ~6-8 weeks for solo developer, or ~3-4 weeks with parallel frontend/backend work.**
