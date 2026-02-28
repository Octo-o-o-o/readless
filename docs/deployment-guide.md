# Readless 后端部署指南

## 服务器信息
- 域名: `readless.cc`
- 服务器: 172.245.55.158:52941
- 现有服务: nginx (80/443), PostgreSQL (5432), OctoReport

## 部署策略

由于80/443/5432端口已被占用，我们将：
1. **复用现有nginx**作为反向代理
2. **修改PostgreSQL端口**为5433
3. **FastAPI服务**暴露在8001端口
4. **移除Caddy服务**（使用nginx替代）

---

## 第一步：准备配置文件

### 1. 修改 `backend/docker-compose.yml`

```yaml
services:
  api:
    build: .
    ports:
      - "127.0.0.1:8001:8000"  # 仅本地访问，通过nginx代理
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
    ports:
      - "127.0.0.1:5433:5432"  # 改用5433避免冲突
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U readless"]
      interval: 5s
      timeout: 5s
      retries: 5
    restart: unless-stopped

volumes:
  pgdata:
```

### 2. 创建 `backend/.env`

```bash
# Database (注意端口改为5433)
DATABASE_URL=postgresql+asyncpg://readless:readless@db:5432/readless
POSTGRES_PASSWORD=你的安全密码

# Anthropic API
ANTHROPIC_API_KEY=sk-ant-你的密钥

# Clerk Auth
CLERK_SECRET_KEY=sk_live_你的密钥

# Cloudflare R2
R2_ENDPOINT=https://你的账户ID.r2.cloudflarestorage.com
R2_ACCESS_KEY=你的AccessKey
R2_SECRET_KEY=你的SecretKey
R2_BUCKET=readless

# ElevenLabs
ELEVENLABS_API_KEY=你的密钥

# Domain
DOMAIN=readless.cc

# CORS (生产环境建议限制具体域名)
CORS_ORIGINS=["https://readless.cc","http://localhost:3000"]
```

---

## 第二步：配置Nginx反向代理

### 1. 创建nginx站点配置

SSH到服务器创建配置文件：

```bash
ssh -p 52941 root@172.245.55.158

# 创建配置文件
cat > /etc/nginx/sites-available/readless.cc << 'EOF'
server {
    listen 80;
    server_name readless.cc www.readless.cc;

    # 重定向到HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name readless.cc www.readless.cc;

    # SSL证书配置 (Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/readless.cc/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/readless.cc/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 日志
    access_log /var/log/nginx/readless.access.log;
    error_log /var/log/nginx/readless.error.log;

    # API代理
    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        # 超时设置（AI处理可能较长）
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }

    # 健康检查端点
    location /health {
        proxy_pass http://127.0.0.1:8001/health;
        access_log off;
    }

    # 文件上传大小限制
    client_max_body_size 50M;
}
EOF
```

### 2. 申请SSL证书

```bash
# 安装certbot（如果未安装）
apt update && apt install -y certbot python3-certbot-nginx

# 申请证书
certbot certonly --nginx -d readless.cc -d www.readless.cc

# 验证证书自动续期
certbot renew --dry-run
```

### 3. 启用站点配置

```bash
# 创建软链接
ln -s /etc/nginx/sites-available/readless.cc /etc/nginx/sites-enabled/

# 测试配置
nginx -t

# 重载nginx
systemctl reload nginx
```

---

## 第三步：配置DNS

在你的域名DNS管理面板（如Cloudflare）添加A记录：

```
类型: A
名称: @
内容: 172.245.55.158
TTL: Auto
代理状态: 仅DNS（如果使用Cloudflare）
```

```
类型: A
名称: www
内容: 172.245.55.158
TTL: Auto
```

---

## 第四步：部署后端

### 1. 上传代码到服务器

```bash
# 在本地打包
cd /Users/wangyixiao/WorkSpace/readless
tar -czf readless-backend.tar.gz backend/

# 上传到服务器
scp -P 52941 readless-backend.tar.gz root@172.245.55.158:/root/

# SSH到服务器
ssh -p 52941 root@172.245.55.158

# 解压
cd /root
tar -xzf readless-backend.tar.gz
cd backend
```

### 2. 启动服务

```bash
# 构建并启动容器
docker-compose up -d --build

# 查看日志
docker-compose logs -f

# 检查容器状态
docker-compose ps
```

### 3. 运行数据库迁移

```bash
# 进入API容器
docker-compose exec api bash

# 运行Alembic迁移
alembic upgrade head

# 退出容器
exit
```

---

## 第五步：验证部署

### 1. 健康检查

```bash
# 本地检查
curl http://127.0.0.1:8001/health

# 通过域名检查
curl https://readless.cc/health
```

预期返回：
```json
{"status": "ok"}
```

### 2. 测试API

```bash
# 创建测试内容
curl -X POST https://readless.cc/api/v1/content/ \
  -H 'Content-Type: application/json' \
  -d '{
    "source_type": "text",
    "body": "这是一篇关于AI的测试文章。\n\n人工智能正在改变世界。\n\n未来充满可能性。"
  }'
```

### 3. 监控资源使用

```bash
# 查看容器资源
docker stats

# 查看内存使用
free -h

# 查看磁盘使用
df -h

# 查看nginx访问日志
tail -f /var/log/nginx/readless.access.log
```

---

## 日常运维命令

### 查看日志
```bash
cd /root/backend

# API日志
docker-compose logs -f api

# 数据库日志
docker-compose logs -f db

# 所有服务日志
docker-compose logs -f
```

### 重启服务
```bash
# 重启所有服务
docker-compose restart

# 仅重启API
docker-compose restart api

# 重新构建并启动
docker-compose up -d --build
```

### 备份数据库
```bash
# 导出数据库
docker-compose exec db pg_dump -U readless readless > backup_$(date +%Y%m%d).sql

# 恢复数据库
cat backup_20260228.sql | docker-compose exec -T db psql -U readless readless
```

### 更新代码
```bash
cd /root/backend

# 拉取最新代码（或上传新版本）
git pull  # 如果使用git

# 重新构建
docker-compose up -d --build

# 运行迁移
docker-compose exec api alembic upgrade head
```

---

## 故障排查

### API无法访问
```bash
# 检查容器状态
docker-compose ps

# 检查容器日志
docker-compose logs api

# 检查nginx日志
tail -n 100 /var/log/nginx/readless.error.log

# 检查端口监听
netstat -tlnp | grep 8001
```

### 数据库连接失败
```bash
# 检查数据库容器
docker-compose logs db

# 进入数据库容器测试连接
docker-compose exec db psql -U readless -d readless

# 检查数据库端口
netstat -tlnp | grep 5433
```

### SSL证书问题
```bash
# 检查证书有效期
certbot certificates

# 手动续期
certbot renew

# 重新申请
certbot certonly --nginx -d readless.cc --force-renewal
```

---

## 安全建议

1. **防火墙配置**
```bash
# 只允许必要端口
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 52941/tcp  # SSH
ufw enable
```

2. **定期更新**
```bash
# 更新系统
apt update && apt upgrade -y

# 更新Docker镜像
docker-compose pull
docker-compose up -d
```

3. **启用fail2ban保护nginx**
```bash
# 创建nginx jail配置
cat > /etc/fail2ban/jail.d/nginx.conf << 'EOF'
[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/readless.error.log
EOF

systemctl restart fail2ban
```

---

## 性能优化

### 1. PostgreSQL调优
```bash
# 编辑 docker-compose.yml，添加环境变量
services:
  db:
    environment:
      - POSTGRES_SHARED_BUFFERS=256MB
      - POSTGRES_EFFECTIVE_CACHE_SIZE=1GB
      - POSTGRES_MAX_CONNECTIONS=50
```

### 2. Nginx缓存
```nginx
# 在nginx配置中添加
proxy_cache_path /var/cache/nginx/readless levels=1:2 keys_zone=readless_cache:10m max_size=100m inactive=60m;

location /api/v1/content/ {
    proxy_cache readless_cache;
    proxy_cache_valid 200 10m;
    proxy_cache_key "$request_uri";
    # ... 其他proxy配置
}
```

### 3. 监控告警
```bash
# 安装netdata实时监控（可选）
bash <(curl -Ss https://my-netdata.io/kickstart.sh)
```

---

## 下一步

部署完成后：
1. ✅ 测试所有API端点
2. ✅ 配置监控和告警
3. ✅ 设置自动备份计划
4. ✅ 对接macOS客户端
5. ✅ 配置Clerk认证
