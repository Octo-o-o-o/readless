# Readless Backend

AI驱动的读后整理与知识库系统 - 后端服务

## 快速开始

### 本地开发

```bash
# 安装依赖
pip install -e ".[dev]"

# 启动服务
uvicorn app.main:app --reload

# 访问API文档
open http://localhost:8000/docs
```

### 生产部署到服务器 (readless.cc)

#### 前置条件

- 服务器: Ubuntu 20.04+
- 域名DNS已解析到服务器IP
- 已安装Docker和Docker Compose
- SSH访问权限

#### 部署步骤

**1️⃣ 准备配置文件**

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑.env文件，填入必要的API密钥
nano .env
```

必须配置的环境变量：
- `ANTHROPIC_API_KEY` - Claude API密钥
- `POSTGRES_PASSWORD` - 数据库密码
- `CLERK_SECRET_KEY` - 认证密钥
- `R2_*` - Cloudflare R2存储配置
- `ELEVENLABS_API_KEY` - 语音合成密钥

**2️⃣ 上传代码到服务器**

```bash
# 在本地打包
tar -czf readless-backend.tar.gz backend/

# 上传到服务器
scp -P 52941 readless-backend.tar.gz root@172.245.55.158:/root/

# SSH连接服务器
ssh -p 52941 root@172.245.55.158

# 解压
cd /root
tar -xzf readless-backend.tar.gz
cd backend
```

**3️⃣ 配置Nginx反向代理**

```bash
# 在服务器上运行nginx配置脚本
chmod +x setup-nginx.sh
sudo bash setup-nginx.sh
```

这个脚本会：
- 创建nginx配置文件
- 申请Let's Encrypt SSL证书
- 配置HTTPS重定向

**4️⃣ 启动后端服务**

```bash
# 使用生产配置启动
docker-compose -f docker-compose.prod.yml up -d --build

# 或使用一键部署脚本
chmod +x deploy.sh
bash deploy.sh

# 查看日志
docker-compose logs -f
```

**5️⃣ 运行数据库迁移**

```bash
docker-compose exec api alembic upgrade head
```

**6️⃣ 验证部署**

```bash
# 健康检查
curl https://readless.cc/health

# 应返回: {"status": "ok"}

# 测试API
curl -X POST https://readless.cc/api/v1/content/ \
  -H 'Content-Type: application/json' \
  -d '{"source_type":"text","body":"测试文章内容"}'
```

## 架构说明

### 服务端口配置

由于服务器已有服务占用标准端口，采用以下配置：

- **API服务**: `127.0.0.1:8001` (仅本地访问)
- **PostgreSQL**: `127.0.0.1:5433` (避免与现有5432冲突)
- **Nginx**: `80/443` (复用现有nginx)

```
Internet → Nginx (443) → FastAPI (8001) → PostgreSQL (5433)
```

### 目录结构

```
backend/
├── app/
│   ├── main.py              # FastAPI应用入口
│   ├── config.py            # 配置管理
│   ├── database.py          # 数据库连接
│   ├── models/              # SQLAlchemy模型
│   ├── routers/             # API路由
│   ├── schemas/             # Pydantic模式
│   └── services/            # 业务逻辑
│       ├── extractor.py     # 内容提取
│       ├── summarizer.py    # AI摘要
│       ├── pipeline.py      # 处理流程
│       ├── search_agent.py  # 搜索Agent
│       └── podcast.py       # 播客生成
├── tests/                   # 测试
├── alembic/                 # 数据库迁移
├── Dockerfile
├── docker-compose.prod.yml  # 生产环境配置
├── pyproject.toml
├── deploy.sh                # 一键部署脚本
├── setup-nginx.sh           # Nginx配置脚本
└── nginx.conf.template      # Nginx配置模板
```

## API文档

启动服务后访问：
- Swagger UI: https://readless.cc/docs
- ReDoc: https://readless.cc/redoc

### 核心端点

#### 内容管理
- `POST /api/v1/content/` - 创建内容（自动提取+摘要）
- `GET /api/v1/content/` - 列出内容
- `GET /api/v1/content/{id}` - 获取内容详情
- `GET /api/v1/content/{id}/paragraphs` - 获取段落

#### AI交互
- `POST /api/v1/content/{id}/expand` - 展开outline要点(L2)
- `POST /api/v1/content/{id}/ask` - 追问(L3)

#### 搜索
- `POST /api/v1/search/` - 智能搜索

#### 播客
- `POST /api/v1/podcast/{content_id}/generate` - 生成播客
- `GET /api/v1/podcast/{content_id}` - 获取播客

## 运维命令

### 日志管理

```bash
# 查看所有日志
docker-compose logs -f

# 查看API日志
docker-compose logs -f api

# 查看数据库日志
docker-compose logs -f db

# 查看nginx日志
tail -f /var/log/nginx/readless.access.log
tail -f /var/log/nginx/readless.error.log
```

### 服务管理

```bash
# 重启服务
docker-compose restart

# 停止服务
docker-compose down

# 重新构建
docker-compose up -d --build

# 查看容器状态
docker-compose ps

# 查看资源使用
docker stats
```

### 数据库管理

```bash
# 进入数据库
docker-compose exec db psql -U readless -d readless

# 备份数据库
docker-compose exec db pg_dump -U readless readless > backup_$(date +%Y%m%d).sql

# 恢复数据库
cat backup.sql | docker-compose exec -T db psql -U readless readless

# 数据库迁移
docker-compose exec api alembic upgrade head
docker-compose exec api alembic downgrade -1
```

### 更新部署

```bash
# 拉取最新代码
git pull  # 或上传新版本

# 重新构建并启动
docker-compose -f docker-compose.prod.yml up -d --build

# 运行迁移
docker-compose exec api alembic upgrade head

# 查看日志确认
docker-compose logs -f api
```

## 性能监控

### 查看资源使用

```bash
# 容器资源
docker stats

# 系统资源
htop
free -h
df -h
```

### 数据库性能

```bash
# 进入数据库
docker-compose exec db psql -U readless

# 查看慢查询
SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;

# 查看连接数
SELECT count(*) FROM pg_stat_activity;
```

### 设置告警（可选）

可集成Prometheus + Grafana监控，或使用简单的脚本定期检查：

```bash
# 创建健康检查cron任务
(crontab -l 2>/dev/null; echo "*/5 * * * * curl -f https://readless.cc/health || echo 'Readless down' | mail -s 'Alert' your@email.com") | crontab -
```

## 故障排查

### API无法访问

1. 检查容器状态: `docker-compose ps`
2. 检查API日志: `docker-compose logs api`
3. 检查nginx日志: `tail -f /var/log/nginx/readless.error.log`
4. 测试本地端口: `curl http://127.0.0.1:8001/health`

### 数据库连接失败

1. 检查数据库容器: `docker-compose logs db`
2. 检查连接: `docker-compose exec db psql -U readless`
3. 验证DATABASE_URL配置

### SSL证书问题

```bash
# 查看证书状态
certbot certificates

# 手动续期
certbot renew

# 重新申请
certbot certonly --nginx -d readless.cc --force-renewal
```

### 性能问题

1. 检查资源使用: `docker stats`
2. 查看慢查询日志
3. 检查PostgreSQL连接池配置
4. 考虑增加缓存层（Redis）

## 安全建议

1. **防火墙配置**
```bash
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 52941/tcp  # SSH
ufw enable
```

2. **定期更新**
```bash
apt update && apt upgrade -y
docker-compose pull
```

3. **API速率限制**
   在nginx配置中启用（见nginx.conf.template注释）

4. **备份策略**
   - 每日自动备份数据库
   - 定期备份R2存储数据
   - 保留至少7天的备份

## 技术栈

- **Web框架**: FastAPI 0.115+
- **数据库**: PostgreSQL 17 (带全文搜索)
- **AI**: Anthropic Claude API (Sonnet 4.5)
- **内容提取**: Trafilatura, PDFPlumber, Tesseract OCR
- **对象存储**: Cloudflare R2
- **语音合成**: ElevenLabs Text to Dialogue
- **认证**: Clerk
- **反向代理**: Nginx
- **容器化**: Docker + Docker Compose

## 文档

- 📖 [部署指南](../docs/deployment-guide.md) - 完整部署文档
- 📋 [产品设计](../docs/plans/2026-02-28-readless-product-design.md)
- 🗺️ [实现计划](../docs/plans/2026-02-28-readless-implementation-plan.md)

## License

MIT
