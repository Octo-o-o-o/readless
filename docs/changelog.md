# Changelog

## 2026-03-24 — Theme & i18n (intake-20260324-1226-cf6b)

**Added**: 亮暗主题切换 + 中英文切换

- 亮色/暗色主题切换 — Switch 控件，默认跟随系统 `prefers-color-scheme`，localStorage 持久化
- 中英文切换 — Switch 控件，默认跟随浏览器语言，localStorage 持久化
- FOUC 防护 — `<head>` 内联脚本同步初始化 theme/lang，避免闪烁
- 完整亮色主题 CSS 变量集（白色背景、深色文字、极简风格）
- 53 个双语文案条目覆盖全部页面文案
- 双标记 i18n: `data-i18n` (textContent) + `data-i18n-html` (innerHTML)
- 所有硬编码 rgba/颜色替换为 CSS 变量驱动
- 响应式适配：480px 断点缩小 switch、768px 调整间距
- `<meta name="theme-color">` 随主题动态更新

**决策**:
- 选择 CSS Custom Properties + `data-theme` 而非 media query 驱动，支持用户手动覆盖系统偏好
- i18n 用 JS 对象而非 JSON 文件，避免额外网络请求（纯静态页）
- innerHTML 仅用于含 HTML 子元素的 2 个元素（badge、tagline），其余全用 textContent

## 2026-03-23 — Landing Page (intake-20260323-1458-2def)

**Added**: 官网 landing page (`landing/` 目录)

- 纯 HTML/CSS/JS 单页面，黑白高对比度极简设计
- 6 个 section: Navigation, Hero, How It Works, Features, Keyboard-First, Footer CTA
- 多层摘要 L0-L3 可视化 + AI Podcast + ⌘K 命令栏展示
- CSS Custom Properties 驱动 design tokens，全响应式 (375px → 1440px)
- IntersectionObserver 滚动动画 + CSS keycap press 动画
- SEO: Open Graph, Twitter Card, robots.txt
- nginx 配置片段 (`nginx-landing.conf`) 使用 `^~` 修饰符避免与 API 路由冲突
- 一键部署脚本 (`deploy-landing.sh`) 含备份、上传、回归测试
- 项目规范文件 (`.openclaw/conventions.md`)

**待办**:
- 服务器部署 (运行 deploy-landing.sh)
- 制作 og:image 分享图
- 替换 Download CTA 为真实下载链接
