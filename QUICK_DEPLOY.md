# Readless 后端快速部署（5分钟上线）

## 🎉 当前生产环境

**已部署服务器**: https://readless.cc
**服务器**: root@172.245.55.158 (SSH端口: 52941)
**部署状态**: ✅ 运行中（2026-03-01部署）
**健康检查**: https://readless.cc/health

### 本地开发使用生产后端（无需部署）

**最简单的方式**: 本地开发直接使用生产服务器

```bash
# 配置 macOS 客户端
cd /Users/wangyixiao/WorkSpace/readless/macos
./configure-backend.sh https://readless.cc

# 运行 App
swift run

# 开始使用
# ⌘K 打开 Command Bar，粘贴内容，按 Enter 导入
```

**优点**:
- ✅ 零配置，立即可用
- ✅ 无需本地 PostgreSQL、Docker 等依赖
- ✅ 与生产环境完全一致
- ✅ 多设备数据同步

**何时需要重新部署**:
- 后端代码有更新
- 需要测试新功能
- 生产服务器维护

---

## 🚀 重新部署到生产服务器

如果你想快速将 Readless 后端部署到服务器进行测试，跟随这个最简化的步骤。

## 方案 A: Railway（最快，推荐新手）

### 1. 准备工作（1分钟）

1. 注册 [Railway.app](https://railway.app) 账号（支持 GitHub 登录）
2. 连接你的 GitHub 账号

### 2. 一键部署（3分钟）

1. **创建新项目**
   - 点击 "New Project" → "Deploy from GitHub"
   - 选择 `readless` 仓库

2. **添加数据库**
   - 在项目页面点击 "New" → "Database" → "Add PostgreSQL"
   - Railway 会自动创建数据库并设置 `DATABASE_URL`

3. **配置环境变量**
   - 点击后端服务 → "Variables"
   - 添加以下变量（从 `backend/.env` 复制）：

```
OPENAI_API_KEY=你的key
OPENAI_BASE_URL=https://api.siliconflow.cn/v1
OPENAI_MODEL=Pro/MiniMaxAI/MiniMax-M2.5
CLERK_SECRET_KEY=你的key
R2_ENDPOINT=你的endpoint
R2_ACCESS_KEY=你的key
R2_SECRET_KEY=你的key
R2_BUCKET=readless
ELEVENLABS_API_KEY=你的key
CORS_ORIGINS=["*"]
```

4. **获取 URL**
   - 点击 "Settings" → "Networking" → "Generate Domain"
   - 复制生成的 URL（例如：`https://readless-production.up.railway.app`）

5. **运行数据库迁移**
   - 在服务页面，点击右上角三个点 → "Shell"
   - 运行：`alembic upgrade head`

### 3. 配置 macOS 客户端（1分钟）

```bash
cd /Users/wangyixiao/WorkSpace/readless/macos

# 配置后端地址
./configure-backend.sh https://你的railway域名.railway.app

# 或者手动设置
defaults write com.readless.app apiBaseURL "https://你的railway域名.railway.app"
```

### 4. 测试

```bash
# 测试后端健康
curl https://你的railway域名.railway.app/health
# 应返回: {"status":"ok"}

# 重启 macOS App
cd macos
swift run

# 测试导入功能
# 1. ⌘K 打开 Command Bar
# 2. 粘贴长文本
# 3. Enter 导入
# 4. 应该成功！
```

---

## 方案 B: VPS + Docker（5-10分钟）

如果你有自己的服务器（Vultr, DigitalOcean, AWS, 阿里云等）。

### 1. 服务器准备

```bash
# SSH 登录服务器
ssh root@你的服务器IP

# 安装 Docker（Ubuntu/Debian）
curl -fsSL https://get.docker.com | sh
sudo systemctl enable docker
sudo systemctl start docker
```

### 2. 上传代码

```bash
# 方法1: Git（推荐）
git clone https://github.com/你的用户名/readless.git
cd readless/backend

# 方法2: 从本地上传
# 在本地运行：
rsync -avz --exclude 'venv' --exclude '__pycache__' \
  /Users/wangyixiao/WorkSpace/readless/backend/ \
  root@你的服务器IP:~/readless/backend/
```

### 3. 配置域名（可选）

如果有域名，修改 `.env`：

```bash
nano .env
# 修改：
DOMAIN=api.yourdomain.com
```

然后将域名 A 记录指向服务器 IP。

### 4. 启动服务

```bash
cd ~/readless/backend

# 启动（包含 PostgreSQL, API, Caddy）
docker compose up -d --build

# 运行迁移
docker compose exec api alembic upgrade head

# 查看日志
docker compose logs -f api
```

### 5. 验证

```bash
# 测试健康端点
curl http://localhost:8000/health

# 如果配置了域名和 Caddy
curl https://api.yourdomain.com/health
```

### 6. 配置 macOS 客户端

```bash
# 使用服务器 IP（无域名）
./configure-backend.sh http://你的服务器IP:8000

# 使用域名（有域名 + Caddy）
./configure-backend.sh https://api.yourdomain.com
```

---

## 方案 C: 本地测试（如果服务器部署失败）

```bash
# 1. 启动本地后端
cd /Users/wangyixiao/WorkSpace/readless
./start-backend.sh

# 2. 确保客户端使用 localhost
defaults delete com.readless.app apiBaseURL  # 删除服务器配置

# 3. 运行 App
cd macos
swift run
```

---

## 常见问题

### Railway 部署失败

**问题**: "Build failed: Python version not found"

**解决**: Railway 会自动检测 `Dockerfile`，无需额外配置。检查 `Dockerfile` 第一行是否为：

```dockerfile
FROM python:3.12-slim
```

### VPS 端口无法访问

**问题**: `curl http://服务器IP:8000/health` 超时

**解决**: 检查防火墙

```bash
# Ubuntu/Debian
sudo ufw allow 8000
sudo ufw allow 80
sudo ufw allow 443

# CentOS/RHEL
sudo firewall-cmd --permanent --add-port=8000/tcp
sudo firewall-cmd --reload
```

### macOS App 仍然报错

**问题**: 配置了服务器地址，但仍然报错

**解决**:

```bash
# 1. 确认配置生效
defaults read com.readless.app apiBaseURL

# 2. 完全退出并重启 App（不是隐藏）
# 在 Xcode 中: 停止运行，然后重新 Run
# 命令行: Ctrl+C 停止，然后重新 swift run

# 3. 查看日志，应显示：
# [Readless] Using configured API base URL: https://...
```

---

## 部署成本参考

| 方案 | 月成本 | 适用场景 |
|------|--------|----------|
| Railway 免费层 | $0 | 个人测试（每月500小时） |
| Railway Pro | $5-10 | 轻度使用 |
| Render 免费层 | $0 | 个人测试（有限制） |
| Vultr 最小VPS | $6 | 完全控制 |
| DigitalOcean Droplet | $6 | 完全控制 |
| 阿里云轻量服务器 | ¥24/月 | 国内访问快 |

---

## 下一步

部署成功后，你可以：

1. ✅ **Command Bar 导入功能**已完全可用
2. 📱 可以在任何地方使用 macOS App（不依赖本地后端）
3. 🔐 配置 Clerk 认证（多用户支持）
4. 🎙️ 测试播客生成功能
5. 📊 查看 API 文档：`https://你的域名/docs`

**问题反馈**: 如遇到部署问题，查看 [DEPLOYMENT.md](DEPLOYMENT.md) 完整指南。
