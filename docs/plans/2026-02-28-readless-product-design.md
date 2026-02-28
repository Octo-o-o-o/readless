# Readless Product Design

> **Read less. Find more. Recall whenever you need.**

Date: 2026-02-28
Status: Approved

---

## 1. Product Overview

### Vision
A cross-platform AI-powered "read-later + knowledge base" for knowledge workers. Readless receives long-form content from any source, generates multi-level traceable summaries, optionally produces AI podcast-style audio, and stores everything in a searchable knowledge base for future recall.

### Target User
Knowledge workers: product managers, researchers, analysts, consultants — anyone processing large volumes of documents, emails, reports, and messages daily.

### Core Value Proposition
- **Read less**: AI distills long content into multi-level outlines you can expand on demand
- **Find more**: Every summary traces back to the original source with anchor links
- **Recall whenever you need**: All processed content is indexed and searchable via natural language

### MVP Platform
macOS desktop-first (Swift/SwiftUI native app).

### Business Model
Freemium subscription.

---

## 2. UI Design Philosophy

### Principles

1. **Buttery smooth, 60fps everywhere** — All transitions use spring animations (SwiftUI `.spring(response:dampingFraction:)`). No jarring cuts. Every element enters and exits with physics-based motion.

2. **Depth through translucency** — Dark translucent materials (NSVisualEffectView) for floating panels, capsules, and overlays. The user's desktop context remains visible, Readless layers on top without taking over.

3. **Minimal chrome, maximum content** — No heavy toolbars or sidebars by default. Content fills the space. Controls appear on hover or via hotkeys. Think: Apple Notes meets Linear.

4. **Micro-interactions matter** — Every action has tactile feedback:
   - Import received: subtle haptic-like bounce on toast
   - Outline point expand: content smoothly unfolds with height animation
   - Source trace: original text panel slides in from the right with parallax
   - Podcast chapters: active chapter glows, transitions crossfade

5. **Typography-first hierarchy** — SF Pro with careful weight/size progression:
   - L0 summary: 20pt semibold
   - L1 outline points: 16pt medium
   - L2 expanded detail: 15pt regular
   - Source citations: 13pt mono, muted color
   - All with generous line-height (1.6) and paragraph spacing

6. **Dark mode native** — Dark mode is the default aesthetic. Light mode supported but dark is the design target. Colors: deep blacks, warm grays, accent color for interactive elements.

7. **Keyboard-visible state** — When navigating via J/K keys, the focused outline point has a subtle left-border highlight that slides smoothly between items. The user always knows where they are.

---

## 3. Core User Flow

```
Content enters Readless (manual or automatic)
    ↓
AI Processing (3-10 seconds)
    → Extract body text → Segment with anchor IDs → Generate multi-level summary → Extract tags/keywords → Index into DB
    ↓
Reading Interface
    → L0: One-line summary (≤30 chars)
    → L1: 3-5 outline points (each traceable to source paragraphs)
    → L2: Expand any point → AI-generated detailed explanation with source citations
    → L3: Follow-up questions → Pinpointed answers with sentence-level citations
    ↓
Optional: Generate AI Podcast
    → NotebookLM-style conversational audio, chapter-linked to outline
    ↓
Auto-indexed into Knowledge Base
    → Semantic search, keyword search, cross-document synthesis
```

---

## 4. Content Ingestion

### 4.1 Manual Inputs (Immediate)

| Method | Description |
|--------|-------------|
| Paste URL | Extract and process web page content |
| Drag/select file | PDF, DOCX, images, etc. |
| Paste text | Raw text from clipboard |
| Screenshot/image | OCR then process |
| Global hotkey import | Select text in any app → hotkey → process (see Section 8) |

### 4.2 Automatic Inputs (Continuous)

| Channel | Mechanism | MVP Priority | Complexity |
|---------|-----------|-------------|------------|
| Local folder watch | macOS FSEvents listener | **P0** | Low |
| Email inbox | IMAP polling/push | **P1** | Medium |
| RSS/Newsletter | Scheduled pull | **P1** | Low |
| Slack Channel | Slack API subscription | **P2** | Medium |
| Browser extension | Right-click "Send to Readless" | **P2** | Medium |
| Custom crawler rules | Scheduled crawl + keyword filter | **P3** | High |
| Webhook API | External systems push content | **P3** | Low |

---

## 5. Multi-Level Summary with Source Tracing

### 5.1 Content Processing Pipeline

```
Original content
    → Segment into paragraphs, assign anchor_id to each
    → Store segmented full text in DB
    → AI generates summaries at each level with [¶N] citations
```

### 5.2 Summary Levels

**L0 — One-Line Summary (≤30 characters)**
- Example: "2025年SaaS定价趋势转向混合计费"

**L1 — Structured Outline (3-5 points)**
- Each point is 15-30 characters
- Each point has `[¶N]` citations linking to source paragraphs
- Example: `1. 纯订阅模式份额从65%降至43% [¶3,¶7]`

**L2 — Expanded Detail**
- User clicks to expand any L1 point
- AI generates 2-3 paragraphs of detailed explanation
- Every claim cites specific source paragraphs `[¶N]`
- Includes a "View Original ¶X-Y" link

**L3 — Follow-up Q&A**
- User asks a specific question about any point
- AI answers with sentence-level citations from the original
- Example: Q: "21%增长率的样本量多大？" → A: "根据原文¶8，Bessemer调研了1,200家SaaS公司..."

### 5.3 Source Tracing Mechanism

- Every paragraph in the original gets an `anchor_id`
- AI-generated summaries include `[¶N]` markers referencing these anchors
- Clicking a `[¶N]` marker opens a side panel showing the original paragraph with relevant sentences highlighted
- At any level, user can "jump to original" and land at the precise location

---

## 6. AI Podcast Generation

### Overview
Optional feature, triggered after outline is generated. Produces NotebookLM-style conversational audio (two AI voices discussing the content), not simple TTS readout.

### Flow
```
User clicks "Generate Podcast" (or presses P hotkey)
    ↓
AI composes podcast script from L1 outline + L2 details
    ↓
TTS API generates conversational audio (30-60s generation time)
    ↓
Podcast player with chapter navigation
```

### Player Interface
- Chapters correspond 1:1 to L1 outline points
- Pausing shows the corresponding text summary for current chapter
- Chapter skip via `[` / `]` keys
- On iPhone: Action Button controls playback (see Section 8)

### Constraints
- Generation takes 30-60 seconds (async, notification when ready)
- Free tier: 3 podcasts/month; Pro: unlimited

---

## 7. Knowledge Base & Retrieval

### 7.1 Architecture: Agentic Page Index (No Vector DB)

Content is already richly structured at ingestion time — no need for a separate vector database.

**Per-content index stored in PostgreSQL:**
```
├── title, source_url, source_type, channel
├── source_app_name        -- e.g. "Google Chrome", "Mail"
├── source_app_bundle_id   -- e.g. "com.google.Chrome"
├── l0_summary             -- one-line summary
├── l1_outline JSONB       -- [{point, anchors}]
├── tags TEXT[]             -- auto-extracted tags
├── keywords TEXT[]         -- auto-extracted keywords
├── full_text_tsv           -- PostgreSQL full-text search vector
├── created_at, updated_at
└── GIN indexes on tags, keywords, l1_outline, full_text_tsv
```

### 7.2 Search Agent Flow

```
User query: "上周看过一篇关于AI产品毛利率的文章"
    ↓
Step 1: Intent parsing
    → Time: last week
    → Topic: AI product gross margin
    → Type: article
    ↓
Step 2: Index search (SQL)
    → WHERE created_at > 7 days ago
    → AND (l0_summary/tags/keywords match)
    → Full-text search fallback
    ↓
Step 3: Candidate ranking
    → Top 5 candidates → read L1 outlines → AI ranks by relevance
    ↓
Step 4: Generate answer
    → Cite specific articles + paragraph anchors
```

### 7.3 Cross-Document Synthesis (Pro)

When a question spans multiple articles:
- User: "最近看的几篇文章里，关于AI产品定价有什么共识？"
- Agent retrieves relevant articles, reads L1/L2 summaries, synthesizes with citations to each source

### 7.4 Search Modes

- **Semantic search**: Natural language questions → Search Agent
- **Keyword search**: Direct text matching via PostgreSQL FTS
- **Filter**: By tag, source type, channel, time range, source app
- **Browse**: Chronological feed of all processed content

---

## 8. Hotkey System — "The Soul of Readless"

### Design Principle

> Any high-frequency action completes in 1-2 keystrokes, hands never leave the keyboard.
> Hotkeys are the primary interaction layer, not a settings afterthought.

### 8.1 macOS Global Hotkeys (Work Even When App Is Not Focused)

Two distinct import modes:

| Hotkey | Action | Behavior |
|--------|--------|----------|
| `⌥⇧R` | **Silent import** | Select text in any app → hotkey → brief toast "Received from Chrome" → processes and indexes silently in background. User is not interrupted. |
| `⌥⇧D` | **Import & display** | Select text in any app → hotkey → floating capsule progress indicator appears at bottom center of screen (see 8.1.1). Processing completes → result slides up for immediate reading. |
| `⌥⇧V` | **Import clipboard (silent)** | Send current clipboard content (text/URL/image) to Readless silently |
| `⌥⇧S` | **Summon Readless** | Spotlight-like floating window for paste/search/ask |

#### 8.1.1 Floating Capsule Progress Indicator (Import & Display Mode)

When `⌥⇧D` is triggered, a floating capsule appears at the bottom center of the screen, above all windows:

```
                ┌─────────────────────────────────┐
                │  ✕   ·····•••○○○•••·····   ✓   │
                └─────────────────────────────────┘
                         ↑ wave animation

Design specs:
- Pill/capsule shape, ~280pt wide × 48pt tall
- Dark translucent background with vibrancy (NSVisualEffectView, .hudWindow material)
- Left: Cancel button (✕) — click to abort processing, capsule dismisses
- Center: Animated progress wave (fluid dot animation, not a linear progress bar)
- Right: Checkmark (✓) — appears when processing completes, click to open result
- Floats above all windows (NSWindow.Level.floating)
- Appears with spring animation (slide up + fade in from bottom)
- On completion: wave animation settles, checkmark pulses once
  → Auto-transitions to result view after 0.5s, OR user clicks ✓ immediately
  → If user clicks ✕ during processing: capsule slides down + fades out, task cancelled
- On cancel: capsule dismisses with slide-down animation
```

State transitions:
```
⌥⇧D pressed
    ↓
Capsule slides up from bottom (spring animation, 0.3s)
    ↓
Processing state: wave animation loops, ✕ active, ✓ dimmed
    ↓
    ├── User clicks ✕ → cancel task, capsule slides down (0.2s)
    │
    └── Processing complete → wave settles, ✓ pulses
            ↓
            ├── User clicks ✓ → open result immediately
            └── Auto (0.5s) → capsule morphs into result panel
                    ↓
                Result panel slides up: shows L1 outline
                Full Readless interaction available (J/K/Enter/S/P...)
```

### 8.2 Source App Capture

When importing via global hotkey, Readless captures the frontmost application's identity:

- **macOS**: `NSWorkspace.shared.frontmostApplication` provides `bundleIdentifier` (e.g. `com.google.Chrome`) and `localizedName` (e.g. "Google Chrome")
- Stored as `source_app_name` and `source_app_bundle_id` on the content record
- Displayed in the content card: "Imported from Safari · 2 hours ago"
- Searchable: user can filter by source app ("show me everything I imported from Slack")
- If content is a URL from a browser, additionally extract the page URL via Accessibility API or AppleScript

### 8.3 In-App Hotkeys

| Hotkey | Action | Context |
|--------|--------|---------|
| `P` | **Generate podcast** | On any content's summary page |
| `1` `2` `3` | **Switch summary level** | L1 outline / L2 expanded / L3 Q&A |
| `Enter` | **Expand current point** | On focused outline point |
| `S` | **Trace to source** | Jump to original text for current content |
| `⌘F` / `/` | **Search knowledge base** | Global, enters semantic search |
| `J` / `K` | **Navigate down/up** | Move between outline points (vim-style) |
| `H` / `L` | **Collapse/Expand** | Toggle current point's detail level |
| `Q` | **Ask follow-up** | Opens Q&A input for current point |
| `⌘N` | **New import** | Opens import window |
| `Space` | **Play/Pause** | Podcast playback control |
| `[` / `]` | **Prev/Next chapter** | Podcast chapter navigation |
| `Esc` | **Dismiss/Back** | Close floating window or go back |
| `⌘,` | **Preferences** | Includes hotkey customization panel |

### 8.4 Hotkey Customization

- Full customization panel in Preferences
- Preset schemes: "Readless Default", "Vim-style", "Custom"
- Conflict detection: warns if a hotkey conflicts with system or other apps, suggests alternatives
- Record-new-hotkey UI for each action

### 8.5 iPhone Action Button

| Trigger | Action |
|---------|--------|
| Press Action Button | Import clipboard content (default) |
| Configurable alternatives | Voice input → AI process / Open quick search |
| During podcast playback | Pause/Resume |
| Double-press | Next chapter |
| Triple-press | Show source text for current chapter |

Also integrates with iOS Shortcuts:
- Share Sheet → "Send to Readless"
- Siri: "Readless帮我总结这个"

### 8.6 Workflow Examples

**Workflow A: Silent import (⌥⇧R) — "I'll read this later"**
```
  ① Select text or copy URL in any app
  ② ⌥⇧R → subtle toast: "Received from Chrome" (fades in 1.5s)
  ③ Continue working. Content processes in background.
  ④ Later: ⌥⇧S → search knowledge base → find it fully summarized
```

**Workflow B: Import & display (⌥⇧D) — "Summarize this NOW"**
```
  ① Select text or copy URL in any app
  ② ⌥⇧D → floating capsule slides up at bottom center:

         ┌──────────────────────────────────┐
         │  ✕   ·····•••○○○•••·····    ✓   │
         └──────────────────────────────────┘

  ③ 3-8 seconds: wave animation plays, user can ✕ to cancel
  ④ Processing complete: ✓ pulses, capsule morphs into result panel

         ┌──────────────────────────────────────────┐
         │ 📄 SaaS Pricing Trends 2025              │
         │ from Chrome · bessemer.com                │
         │                                          │
         │ "SaaS定价从纯订阅转向混合计费"              │
         │                                          │
         │ ▸ 1. 纯订阅份额降至43%          [¶3,¶7]  │
         │ ▸ 2. 混合模式增长率达21%          [¶12]   │
         │ ▸ 3. AI产品毛利率仅50-60%       [¶18]    │
         │ ▸ 4. 30%+企业将采用成果定价      [¶24]    │
         │                                          │
         │  [P]odcast  [S]ource  [Q]uestion   Esc   │
         └──────────────────────────────────────────┘

  ⑤ J/K navigate → Enter expand → S trace source
  ⑥ P to generate podcast
  ⑦ Esc → panel slides down, back to work

  All spring-animated. All 60fps. Zero mouse clicks.
```

---

## 9. Technical Architecture

```
┌───────────────────────────────────────────────────────┐
│  macOS Native App (Swift / SwiftUI)                   │
│  ├── Main UI (content list, reader, knowledge base)   │
│  ├── Global hotkey listener (Carbon/CGEvent)          │
│  ├── Source app capture (NSWorkspace)                  │
│  ├── Floating capsule progress indicator (NSPanel)    │
│  ├── Local folder watcher (FSEvents)                  │
│  ├── Clipboard monitor (optional)                     │
│  ├── Audio player (AVFoundation)                      │
│  ├── Local cache (SQLite — offline reading of summaries│
│  └── Hotkey customization engine                      │
└───────────────────────┬───────────────────────────────┘
                        │ HTTPS API
                        ▼
┌───────────────────────────────────────────────────────┐
│  Cloud Services                                       │
│  ├── API Gateway (auth, rate limiting, billing)       │
│  ├── Content Extraction (Jina Reader / Readability)   │
│  ├── AI Summary Service (Claude API)                  │
│  ├── Podcast Generation (ElevenLabs / Tongyi TTS)     │
│  ├── Search Agent (agentic retrieval over page index) │
│  ├── PostgreSQL (content, index, users — single DB)   │
│  ├── Object Storage (R2 — original snapshots, audio)  │
│  └── Background Jobs (email polling, RSS pull, sync)  │
│                                                       │
│  ❌ No vector database                                │
└───────────────────────────────────────────────────────┘
```

---

## 10. Freemium Pricing

| | Free | Pro ($9.99/mo) |
|---|---|---|
| Daily content processing | 5 items | Unlimited |
| Summary levels | L0 + L1 | L0 through L3 |
| Podcast generation | 3/month | Unlimited |
| Knowledge base storage | 100 items | Unlimited |
| Cross-document synthesis | No | Yes |
| Auto-input channels | 1 channel | Unlimited |
| Semantic search | Yes | Yes |
| Source app tracking | Yes | Yes |

---

## 11. Competitive Positioning

### Market Context
- Read-later space in crisis: Pocket (dead Jul 2025), Omnivore (dead Nov 2024), Summari (dead)
- No single tool does the full pipeline: ingest → summarize → trace → podcast → store → recall
- Existing tools are siloed: Otter.ai (meetings only), Readwise (articles only), Notion AI (within Notion only)

### Readless Differentiators

| vs Competitor | Readless Advantage |
|---|---|
| vs Readwise Reader | Multi-level traceable summaries (not just highlights), AI podcast, free tier, hotkey-first UX |
| vs Getrecall.ai | Native desktop app, source app tracking, auto-ingestion channels, podcast |
| vs Otter.ai | Not limited to meetings — handles articles, docs, images, email |
| vs Notion AI | Standalone tool, content comes to you (auto-channels), no vendor lock-in |
| vs Kimi/Monica | Persistent knowledge base with recall, not ephemeral chat sessions |
| vs 通义听悟/飞书妙记 | Not limited to audio/video, not locked to any ecosystem |

### Key Risks
1. **AI hallucination in summaries** — mitigated by mandatory source tracing at every level
2. **Cost of AI API calls** — mitigated by caching, smart processing tiers
3. **User acquisition** — mitigated by free tier + viral "share summary" feature
4. **Cross-platform expansion** — Phase 2+ concern, macOS first validates the concept

---

## 12. MVP Scope (Phase 1, ~6-8 weeks)

### In Scope
- macOS native app (Swift/SwiftUI)
- Manual import: paste URL, drag file (PDF/text), paste text, image (OCR)
- Local folder watching (FSEvents)
- Global hotkeys: silent import (⌥⇧R) and import & display (⌥⇧D) with source app capture
- Floating capsule progress indicator with cancel/confirm (import & display mode)
- In-app hotkey navigation (vim-style)
- Hotkey customization panel
- Multi-level summary (L0-L3) with source tracing
- AI podcast generation (optional per content)
- Knowledge base with Search Agent (PostgreSQL + agentic retrieval)
- Cloud backend: API gateway, content extraction, AI summary, podcast gen, PostgreSQL, R2
- Freemium with user accounts

### Out of Scope (Phase 2+)
- Email inbox integration (P1)
- RSS/Newsletter pull (P1)
- Browser extension (P2)
- Slack/Teams integration (P2)
- iOS app with Action Button (P2)
- Custom crawler rules (P3)
- Webhook API (P3)
- Windows/Android (P3+)
- Team collaboration features (P3+)
- Knowledge graph visualization (P3+)
