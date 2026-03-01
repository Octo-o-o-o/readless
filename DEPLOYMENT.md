# Readless 后端部署指南

## 🚀 生产环境信息

**当前生产服务器**: https://readless.cc
**服务器**: root@172.245.55.158 (SSH端口: 52941)
**部署状态**: ✅ 已部署并运行（2026-03-01）
**健康检查**: https://readless.cc/health

### 本地开发建议

**推荐做法**: 本地开发直接连接生产服务器，无需运行本地后端。

```bash
# 配置 macOS 客户端使用生产服务器
cd macos
./configure-backend.sh https://readless.cc

# 或手动配置
defaults write com.readless.app apiBaseURL "https://readless.cc"

# 运行 App（自动连接到生产服务器）
swift run
```

**优点**:
- ✅ 无需本地安装 PostgreSQL、Redis 等依赖
- ✅ 与生产环境完全一致的API和数据
- ✅ 节省本地资源
- ✅ 多设备开发数据同步

**何时需要本地后端**:
- 后端功能开发和调试
- 无网络环境下的开发
- 需要修改后端代码并测试

---

## 部署方式选择

### 方式 1: Docker Compose（推荐）

适合快速部署到任何支持 Docker 的服务器。

#### 前置要求

- Linux 服务器（Ubuntu 20.04+ / Debian 11+ / CentOS 8+）
- Docker 20.10+
- Docker Compose 2.0+
- 域名已解析到服务器 IP（用于 HTTPS）

#### 部署步骤

1. **在服务器上安装 Docker**

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y docker.io docker-compose-plugin

# 启动 Docker
sudo systemctl enable docker
sudo systemctl start docker

# 将当前用户加入 docker 组（可选）
sudo usermod -aG docker $USER
# 退出并重新登录生效
```

2. **上传代码到服务器**

```bash
# 方法 1: Git Clone（推荐）
ssh your-server
git clone https://github.com/你的用户名/readless.git
cd readless/backend

# 方法 2: 使用 rsync
rsync -avz --exclude 'venv' --exclude '__pycache__' \
  /Users/wangyixiao/WorkSpace/readless/backend/ \
  your-server:/home/user/readless/backend/
```

3. **配置环境变量**

```bash
cd ~/readless/backend

# .env 文件已存在，只需修改域名
nano .env
```

确保 `DOMAIN` 变量设置为你的域名：

```env
DOMAIN=api.readless.cc  # 改成你的实际域名
CORS_ORIGINS=["https://api.readless.cc"]
```

4. **启动服务**

```bash
cd ~/readless/backend

# 构建并启动所有服务
sudo docker compose up -d --build

# 查看日志确认启动成功
sudo docker compose logs -f

# 看到以下日志表示成功：
# api-1   | INFO:     Application startup complete.
# caddy-1 | {"level":"info","ts":1234567890,"msg":"serving initial configuration"}
```

5. **运行数据库迁移**

```bash
# 进入 API 容器执行迁移
sudo docker compose exec api alembic upgrade head
```

6. **验证部署**

```bash
# 检查健康端点
curl http://localhost:8000/health
# 应返回: {"status":"ok"}

# 检查 Caddy HTTPS（需要域名解析成功）
curl https://api.readless.cc/health
```

7. **查看 API 文档**

浏览器访问：`https://api.readless.cc/docs`

---

### 方式 2: 云平台一键部署

#### Railway（推荐新手）

1. **在 [Railway.app](https://railway.app) 注册账号**

2. **创建新项目**
   - New Project → Deploy from GitHub
   - 选择 `readless` 仓库
   - Railway 会自动检测 `Dockerfile`

3. **添加 PostgreSQL 数据库**
   - Add Service → Database → PostgreSQL

4. **配置环境变量**
   - Settings → Variables
   - 复制 `.env` 中的所有变量
   - `DATABASE_URL` 使用 Railway 提供的 PostgreSQL 连接串

5. **部署**
   - Railway 会自动部署
   - 获取公开 URL：Settings → Domains → Generate Domain

#### Render

1. **在 [Render.com](https://render.com) 注册**
2. **创建 Web Service**
   - New → Web Service
   - Connect Repository: `readless`
   - Root Directory: `backend`
   - Build Command: `pip install --no-cache-dir .`
   - Start Command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`

3. **添加 PostgreSQL**
   - New → PostgreSQL
   - 复制 External Database URL

4. **配置环境变量**
   - Environment → Environment Variables
   - 添加 `.env` 中的所有变量
   - `DATABASE_URL` 使用 Render 提供的连接串

#### Fly.io

```bash
# 安装 flyctl
curl -L https://fly.io/install.sh | sh

# 登录
flyctl auth login

# 在 backend 目录下初始化
cd backend
flyctl launch
# 选择区域、配置等

# 添加 PostgreSQL
flyctl postgres create

# 部署
flyctl deploy
```

---

### 方式 3: VPS 手动部署（不使用 Docker）

适合轻量服务器或特殊需求。

#### 步骤

1. **安装依赖**

```bash
# Python 3.12+
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3-pip

# Tesseract OCR（用于图片文字识别）
sudo apt install -y tesseract-ocr tesseract-ocr-chi-sim

# PostgreSQL 17
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null
sudo apt update
sudo apt install -y postgresql-17
```

2. **创建数据库**

```bash
sudo -u postgres psql
```

```sql
CREATE USER readless WITH PASSWORD 'your_strong_password';
CREATE DATABASE readless OWNER readless;
GRANT ALL PRIVILEGES ON DATABASE readless TO readless;
\q
```

3. **部署应用**

```bash
cd ~/readless/backend

# 创建虚拟环境
python3.12 -m venv venv
source venv/bin/activate

# 安装依赖
pip install --upgrade pip
pip install -e ".[dev]"
```

4. **修改 .env**

```env
DATABASE_URL=postgresql+asyncpg://readless:your_strong_password@localhost:5432/readless
```

5. **运行迁移**

```bash
alembic upgrade head
```

6. **使用 systemd 托管服务**

创建 `/etc/systemd/system/readless.service`：

```ini
[Unit]
Description=Readless API Server
After=network.target postgresql.service

[Service]
Type=simple
User=your-user
WorkingDirectory=/home/your-user/readless/backend
Environment="PATH=/home/your-user/readless/backend/venv/bin"
ExecStart=/home/your-user/readless/backend/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable readless
sudo systemctl start readless
```

7. **配置 Nginx 反向代理**

创建 `/etc/nginx/sites-available/readless`：

```nginx
server {
    listen 80;
    server_name api.readless.cc;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/readless /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

8. **配置 HTTPS（Let's Encrypt）**

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d api.readless.cc
```

---

## macOS 客户端配置

### 方式 1: 使用命令行参数（临时测试）

```bash
# 方法已在代码中实现，见下文
```

### 方式 2: 在 UserDefaults 中设置（推荐）

```bash
# 设置后端 URL
defaults write com.readless.app apiBaseURL "https://api.readless.cc"

# 恢复默认（localhost）
defaults delete com.readless.app apiBaseURL
```

### 方式 3: 在代码中硬编码（开发阶段）

修改 `macos/Sources/Networking/APIClient.swift`：

```swift
public init(
    baseURL: URL = URL(string: "https://api.readless.cc")!, // 改成你的服务器 URL
    authToken: String? = nil,
    session: URLSession = .shared
) {
```

---

## 部署检查清单

### 部署前

- [ ] `.env` 文件已配置所有必需的 API keys
- [ ] 域名已解析到服务器 IP
- [ ] 服务器防火墙开放 80 和 443 端口
- [ ] PostgreSQL 密码已更改为强密码

### 部署后

- [ ] 健康检查成功：`curl https://api.readless.cc/health`
- [ ] API 文档可访问：`https://api.readless.cc/docs`
- [ ] 数据库迁移已执行：`alembic current` 显示最新版本
- [ ] CORS 配置正确：`CORS_ORIGINS` 包含前端域名
- [ ] HTTPS 证书有效（绿锁）

### macOS 客户端

- [ ] 客户端 `apiBaseURL` 已设置为服务器地址
- [ ] 可以成功导入内容
- [ ] 可以查看生成的大纲

---

## 故障排查

### 问题 1: Docker 容器无法启动

```bash
# 查看详细日志
sudo docker compose logs api

# 常见原因：
# - 端口 8000 被占用 → 修改 docker-compose.yml 中的端口映射
# - .env 文件缺失 → 确保 .env 存在
```

### 问题 2: 数据库连接失败

```bash
# 检查数据库是否启动
sudo docker compose ps

# 进入数据库容器测试
sudo docker compose exec db psql -U readless -d readless
```

### 问题 3: HTTPS 证书问题

```bash
# Caddy 会自动获取证书，但需要：
# 1. 域名正确解析到服务器 IP
# 2. 80 和 443 端口可访问
# 3. DOMAIN 环境变量设置正确

# 查看 Caddy 日志
sudo docker compose logs caddy
```

### 问题 4: CORS 错误

修改 `.env`：

```env
CORS_ORIGINS=["https://你的域名.com","http://localhost:3000"]
```

重启服务：

```bash
sudo docker compose restart api
```

---

## 推荐部署方案对比

| 方案 | 难度 | 成本 | 适用场景 |
|------|------|------|----------|
| Railway | ⭐ | $5-20/月 | 快速原型、个人项目 |
| Render | ⭐⭐ | 免费/$7起 | 小型项目 |
| Fly.io | ⭐⭐ | 免费/$5起 | 全球部署 |
| Docker Compose | ⭐⭐⭐ | VPS成本 | 完全控制、生产环境 |
| 手动部署 | ⭐⭐⭐⭐ | VPS成本 | 特殊需求、学习 |

**新手推荐**：Railway（最简单）
**生产推荐**：Docker Compose on VPS（最稳定）
**免费方案**：Render 免费层 或 Fly.io 免费额度

---

## 快速启动命令

### 本地测试（Docker）

```bash
cd backend
sudo docker compose up -d --build
sudo docker compose exec api alembic upgrade head
```

### 服务器部署（Docker）

```bash
# 1. 上传代码
rsync -avz backend/ your-server:~/readless/backend/

# 2. SSH 到服务器
ssh your-server

# 3. 启动
cd ~/readless/backend
sudo docker compose up -d --build
sudo docker compose exec api alembic upgrade head

# 4. 验证
curl http://localhost:8000/health
```

### macOS 客户端配置

```bash
# 设置服务器地址
defaults write com.readless.app apiBaseURL "https://api.readless.cc"

# 重启 App 生效
```

---

**需要帮助？**

- 查看日志：`sudo docker compose logs -f`
- API 文档：`https://你的域名/docs`
- 健康检查：`https://你的域名/health`
