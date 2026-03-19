# Readless

AI-powered macOS desktop app that ingests long-form content and generates multi-level traceable summaries and AI podcasts.

## 🚀 Quick Start

### Prerequisites
- macOS 14.0+
- Xcode 15+ or Swift 5.9+

### Running the App (Recommended)

The app is configured to use the production backend by default. **No local backend setup required.**

```bash
# 1. Clone the repository
git clone https://github.com/your-username/readless.git
cd readless

# 2. Configure to use production backend
cd macos
./configure-backend.sh https://readless.cc

# 3. Run the app
swift run

# You should see:
# [Readless] Using configured API base URL: https://readless.cc
```

### Usage

1. **Open Command Bar**: Press `⌘K`
2. **Import Content**: Paste text or URL, press Enter
3. **View Summary**: See AI-generated outline and summary
4. **Expand Details**: Click outline points to expand

**Keyboard Shortcuts**:
- `⌘K` — Open/Close Command Bar
- `⌥⇧R` — Quick import from clipboard (silent)
- `⌥⇧D` — Quick import from clipboard (show UI)
- `⌥⇧V` — Summon panel
- `⌥⇧S` — Search

---

## 🏗 Architecture

### Two-Part System

- **Backend**: Python FastAPI server (deployed at https://readless.cc)
- **macOS Client**: Native SwiftUI app

### macOS Client Structure

```
macos/Sources/
├── Core/          # Domain models, zero dependencies
├── Networking/    # APIClient with configurable backend URL
├── Storage/       # GRDB SQLite local cache
├── UI/            # Reusable SwiftUI components
└── App/           # Main executable
    ├── Services/  # ContentManager, CommandBar, Hotkeys
    └── Views/     # ReaderView, CommandBarView
```

**Backend Configuration**: The app reads backend URL from UserDefaults:
- Default: `https://readless.cc` (production)
- Override: `defaults write com.readless.app apiBaseURL "http://localhost:8000"`

---

## 🌐 Production Backend

**URL**: https://readless.cc
**Server**: Deployed on VPS with Docker Compose
**Status**: [Check Health](https://readless.cc/health)
**API Docs**: https://readless.cc/docs

### Backend Features
- Content extraction (URLs, PDFs, images with OCR)
- Multi-level AI summarization (L0/L1/L2/L3)
- Full-text search with AI ranking
- Podcast script generation + TTS
- Cloudflare R2 object storage

---

## 💻 Development

### macOS Client Development

```bash
cd macos

# Build
swift build

# Run
swift run

# Run tests
swift test

# Release build
swift build -c release
```

The app will connect to the configured backend (production or localhost).

### Backend Development (Optional)

Only needed if you're developing backend features.

#### Local Setup

```bash
cd backend

# Create virtual environment
python3.12 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -e ".[dev]"

# Run API server
uvicorn app.main:app --reload

# Run content worker in a second terminal
python -m app.worker

# Run tests
pytest tests/
```

#### Configure macOS app to use local backend

```bash
# Use localhost
defaults delete com.readless.app apiBaseURL

# Or explicitly set
defaults write com.readless.app apiBaseURL "http://localhost:8000"
```

#### Docker Setup

```bash
cd backend

# Start services (PostgreSQL + API + worker)
docker compose up -d --build

# View logs
docker compose logs -f

# Stop services
docker compose down
```

### Backend Structure

```
backend/app/
├── main.py           # FastAPI entry point
├── config.py         # Settings from .env
├── auth.py           # Clerk JWT verification
├── routers/          # API endpoints
│   ├── content.py    # Content CRUD
│   ├── podcast.py    # Podcast generation
│   └── search.py     # AI-powered search
├── services/         # Business logic
│   ├── pipeline.py   # Extract → Summarize → Store
│   ├── extractor.py  # URL/PDF/Image extraction
│   ├── summarizer.py # Multi-level AI summaries
│   └── podcast.py    # TTS generation
└── models/           # SQLAlchemy ORM
```

---

## 📚 Documentation

### User Documentation
- [Command Bar Usage Guide](COMMAND_BAR_USAGE.md) — How to use Command Bar
- [Troubleshooting Guide](TROUBLESHOOTING.md) — Common issues and fixes

### Deployment Documentation
- [Production Deployment Result](DEPLOYMENT-RESULT.md) — Current deployment status
- [Deployment Verification](DEPLOYMENT-VERIFICATION.md) — Pre-deployment checklist
- [Quick Deploy Guide](QUICK_DEPLOY.md) — 5-minute deployment
- [Full Deployment Guide](DEPLOYMENT.md) — Comprehensive deployment options
- [Deployment Checklist](DEPLOYMENT-CHECKLIST.md) — Step-by-step checklist

### Development Documentation
- [CLAUDE.md](CLAUDE.md) — Project overview for AI assistants
- [Backend README](backend/README.md) — Backend-specific documentation

---

## 🔧 Configuration

### Backend URL Configuration

The macOS app reads the backend URL from UserDefaults:

```bash
# Use production (recommended)
defaults write com.readless.app apiBaseURL "https://readless.cc"

# Use localhost (for backend development)
defaults write com.readless.app apiBaseURL "http://localhost:8000"

# Reset to default
defaults delete com.readless.app apiBaseURL

# Check current setting
defaults read com.readless.app apiBaseURL
```

Or use the configuration script:

```bash
cd macos
./configure-backend.sh https://readless.cc
```

---

## 🌟 Features

### Content Import
- 📝 Plain text
- 🔗 URLs (automatic content extraction)
- 📄 PDF files (with OCR)
- 🖼️ Images (OCR support)
- 📋 Clipboard monitoring

### AI Processing
- **L0 Summary**: One-line summary (≤30 Chinese chars or ≤60 English chars)
- **L1 Outline**: Structured outline with 3-7 points
- **L2 Expansion**: Detailed expansion of outline points
- **L3 Q&A**: Follow-up questions and answers

### Search
- Full-text search with PostgreSQL FTS
- AI-powered semantic ranking
- Natural language queries

### Podcasts
- AI-generated podcast scripts
- Text-to-speech with ElevenLabs
- Upload to Cloudflare R2

---

## 🔐 External Services

The backend integrates with:

- **OpenAI**: AI summarization and search (via SiliconFlow)
- **ElevenLabs**: Text-to-speech for podcasts
- **Clerk**: User authentication (JWT)
- **Cloudflare R2**: Object storage for podcast audio
- **PostgreSQL 17**: Primary database

---

## 📊 Tech Stack

### macOS Client
- **Language**: Swift 5.9+
- **UI**: SwiftUI
- **Architecture**: MVVM with @Observable
- **Database**: GRDB (SQLite)
- **Dependencies**: SPM (Swift Package Manager)

### Backend
- **Language**: Python 3.12+
- **Framework**: FastAPI
- **Database**: PostgreSQL 17 with async SQLAlchemy
- **Deployment**: Docker Compose + Nginx
- **SSL**: Cloudflare Origin Certificate

---

## 🚀 Production Deployment

The production backend is deployed on a VPS with:

- **Docker Compose** for container orchestration
- **Nginx** as reverse proxy
- **Cloudflare** for SSL/TLS and CDN
- **PostgreSQL 17** for data storage
- **Automated backups** (daily)

See [DEPLOYMENT-RESULT.md](DEPLOYMENT-RESULT.md) for the latest deployment report.

---

## 📝 License

[Your License Here]

---

## 🙏 Acknowledgments

Built with:
- [FastAPI](https://fastapi.tiangolo.com/)
- [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- [GRDB](https://github.com/groue/GRDB.swift)
- [OpenAI](https://openai.com/)
- [ElevenLabs](https://elevenlabs.io/)
- [Cloudflare](https://www.cloudflare.com/)

---

**Questions?** Check the [Troubleshooting Guide](TROUBLESHOOTING.md) or [CLAUDE.md](CLAUDE.md) for detailed documentation.
