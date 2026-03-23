# Changelog

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
