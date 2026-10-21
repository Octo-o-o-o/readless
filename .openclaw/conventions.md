# Project Conventions — Readless

> 生成方式: Eve 在 intake-20260323-1458-2def 首次接触项目时从代码观察生成。
> 与已有文档: CLAUDE.md 定义构建/测试/部署命令，本文件定义架构级规范。
> 最近更新: 2026-03-23 — intake-20260323-1458-2def — 首次创建

---

## 1. 项目概况

- **类型**: 双端应用（macOS 客户端 + Python 后端）
- **技术栈**: 
  - 后端: Python 3.x, FastAPI, SQLAlchemy (async), PostgreSQL 17, Alembic
  - 前端: Swift/SwiftUI (macOS 原生), SPM
  - Landing Page: 纯 HTML/CSS/JS（无框架）
- **关键目录**:
  - `backend/` → FastAPI 后端服务
  - `macos/` → SwiftUI macOS 客户端
  - `landing/` → 官网 landing page（新增）
  - `docs/` → 项目文档
- **已有规范文档**: CLAUDE.md（全面的项目指南）

## 2. 代码规范

### 2.1 命名约定

| 对象 | 风格 | 示例 |
|------|------|------|
| Python 函数/变量 | snake_case | `get_current_user_id` |
| Python 类 | PascalCase | `ContentManager` |
| Swift 类/结构体 | PascalCase | `ReaderViewModel` |
| Swift 变量/函数 | camelCase | `contentManager` |
| API 路径 | kebab-case with prefix | `/api/v1/content` |
| 数据库表 | snake_case 复数 | `user_tags`, `content_tags` |
| CSS 类 | kebab-case | `hero-section`, `feature-card` |
| 环境变量 | SCREAMING_SNAKE_CASE | `OPENAI_API_KEY` |

### 2.2 架构模式

**后端 (FastAPI)**:
- 分层: router → service → model (SQLAlchemy ORM)
- 服务使用 lazy singleton: 模块级 `_service` + `_get_service()` 工厂
- 所有 DB 操作异步 (`AsyncSession`)
- API 风格: REST, `/api/v1/` 前缀

**macOS 客户端 (SwiftUI)**:
- SPM 多 target: Core → Networking → Storage → UI → App
- 状态管理: `@Observable` (ContentManager 单一数据源)
- MVVM: ViewModels 使用 `@Observable`

**Landing Page (HTML/CSS/JS)**:
- 纯静态，无构建步骤
- 资源路径: `/landing-assets/` 前缀
- 内联 SVG 图标，无外部图标库
- 系统字体栈，无外部字体加载

### 2.3 错误处理

- 后端: FastAPI HTTPException + 自定义 error handler
- OpenAI 调用: JSON-only 响应（system prompt 禁止 markdown fence）
- 测试: 设计为无需数据库/API key/网络即可运行

## 3. 测试约定

- **框架**: pytest (backend), Swift Testing (macOS)
- **目录**: `backend/tests/`
- **策略**: 单元测试为主，无需真实外部服务
- **当前状态**: 189 tests passing (backend)

## 4. 部署约定

- **平台**: VPS (172.245.55.158:52941), Docker Compose
- **域名**: readless.cc (Cloudflare DNS + Origin Certificate)
- **Nginx**: 反向代理，API → 127.0.0.1:8001
- **Landing Page**: 静态文件由 nginx 直接提供 (/var/www/readless-landing/)
- **关键注意**: nginx 配置变更需备份 + `nginx -t` 验证

## 前端约定 (Landing Page)

### Design Tokens — Dark (Default)

| Token | 值 | 用途 |
|-------|-----|------|
| background | #000000 | 页面背景 |
| surface | #0a0a0a | 卡片/区块背景 |
| text-primary | #FFFFFF | 正文/标题 |
| text-secondary | #888888 | 辅助文字 |
| text-muted | #555555 | 极淡辅助 |
| border | #222222 | 边框/分割线 |
| nav-bg | rgba(0,0,0,0.8) | 导航栏背景 |
| btn-bg / btn-text | #FFFFFF / #000000 | 按钮背景/文字 |

### Design Tokens — Light

| Token | 值 | 用途 |
|-------|-----|------|
| background | #FFFFFF | 页面背景 |
| surface | #F5F5F5 | 卡片/区块背景 |
| text-primary | #111111 | 正文/标题 |
| text-secondary | #555555 | 辅助文字 |
| text-muted | #999999 | 极淡辅助 |
| border | #E0E0E0 | 边框/分割线 |
| nav-bg | rgba(255,255,255,0.8) | 导航栏背景 |
| btn-bg / btn-text | #111111 / #FFFFFF | 按钮背景/文字 |

### 主题切换约定
- 通过 `[data-theme="light"]` CSS 选择器覆盖 `:root` 变量
- 所有颜色必须通过 CSS 变量引用，禁止硬编码 rgba/hex（变量定义处除外）
- FOUC 防护: `<head>` 内联脚本同步初始化

### Typography

| 级别 | 字号 | 行高 | 字重 |
|------|------|------|------|
| Hero title | 4rem (64px) | 1.1 | 700 |
| Section title | 2rem (32px) | 1.3 | 600 |
| Body | 1.125rem (18px) | 1.6 | 400 |
| Caption/small | 0.875rem (14px) | 1.5 | 400 |

字体族: `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif`

### Spacing
- Base unit: 8px
- Section padding: 120px (top/bottom)
- Content max-width: 1080px
- Responsive breakpoint: 768px (mobile)

### 样式规则
- 方案: 纯 CSS（CSS Custom Properties）
- 禁止: !important, inline style, 外部 CSS 框架
- 动效: CSS transition + IntersectionObserver，无第三方库
