# Readless 部署配置核对报告

**生成时间**: 2026-03-01
**服务器**: root@172.245.55.158
**域名**: readless.cc

---

## ✅ 配置文件核对结果

### 1. Docker Compose 配置

| 文件 | 状态 | 说明 |
|------|------|------|
| `docker-compose.yml` | ✅ 存在 | 开发环境配置（包含Caddy，端口8000） |
| `docker-compose.prod.yml` | ✅ 存在 | **生产环境配置（使用nginx，端口8001）** |

**生产环境配置要点**:
- API端口: `127.0.0.1:8001:8000` ✅（仅本地访问）
- DB端口: `127.0.0.1:5433:5432` ✅（避免冲突，仅本地访问）
- 使用独立网络: `readless` ✅
- 包含健康检查 ✅

### 2. 部署脚本

| 脚本 | 状态 | 修复情况 |
|------|------|----------|
| `deploy.sh` | ✅ 已修复 | **已更新为使用 `docker-compose.prod.yml`** |
| `setup-nginx-cloudflare.sh` | ✅ 正确 | Cloudflare Origin Certificate配置 |

**deploy.sh 修复内容**:
- ✅ 使用 `-f docker-compose.prod.yml` 参数
- ✅ 增强健康检查（重试10次）
- ✅ 支持 `docker-compose` 和 `docker compose` 两种命令
- ✅ 验证端口为 `127.0.0.1:8001`

### 3. 环境变量配置

| 配置项 | 值 | 状态 |
|--------|-----|------|
| `DATABASE_URL` | `postgresql+asyncpg://readless:readless@db:5432/readless` | ✅ 正确（Docker内部网络） |
| `POSTGRES_PASSWORD` | `t&=FtdgIc6QXiN+w5!$!z11Wu9%zfZYG` | ✅ 已设置强密码 |
| `OPENAI_API_KEY` | `sk-iwamd...` | ✅ 已配置 |
| `OPENAI_BASE_URL` | `https://api.siliconflow.cn/v1` | ✅ 使用国内API |
| `OPENAI_MODEL` | `Pro/MiniMaxAI/MiniMax-M2.5` | ✅ 已配置 |
| `CLERK_SECRET_KEY` | `sk_test_...` | ✅ 已配置 |
| `R2_*` | Cloudflare R2配置 | ✅ 完整 |
| `ELEVENLABS_API_KEY` | `sk_9027...` | ✅ 已配置 |
| `CORS_ORIGINS` | `["https://readless.cc","http://localhost:3000"]` | ✅ 包含生产域名 |
| `DOMAIN` | `readless.cc` | ✅ 正确 |

### 4. Nginx 配置

**setup-nginx-cloudflare.sh** 检查项:
- ✅ 使用 Cloudflare Origin Certificate（不需要Let's Encrypt）
- ✅ 代理到 `http://127.0.0.1:8001` ✅ **端口匹配**
- ✅ 配置 Cloudflare 真实IP获取
- ✅ 上传大小限制: 50MB
- ✅ 超时配置: 300s（适合AI处理）
- ✅ HTTP自动重定向到HTTPS

---

## 🔧 需要修复的问题 → 已修复

### ~~问题1: deploy.sh 使用错误的配置文件~~
- ❌ **原问题**: `deploy.sh` 使用 `docker-compose` 而不是 `docker-compose.prod.yml`
- ✅ **已修复**: 更新为 `docker-compose -f docker-compose.prod.yml`
- ✅ **影响**: 现在会使用正确的生产环境端口（8001而非8000）

---

## 📋 部署前检查清单

### 服务器环境
- [ ] 确认服务器: `root@172.245.55.158`
- [ ] SSH连接正常: `ssh -p 52941 root@172.245.55.158`
- [ ] Docker已安装: `docker --version`
- [ ] Nginx已安装并配置: `nginx -t`
- [ ] Cloudflare Origin Certificate已安装

### 代码和配置
- [x] `backend/docker-compose.prod.yml` 存在且正确
- [x] `backend/deploy.sh` 已修复为使用生产配置
- [x] `backend/.env` 配置完整（所有API keys已填写）
- [x] `backend/setup-nginx-cloudflare.sh` 正确
- [ ] 代码已打包: `tar -czf readless-backend.tar.gz backend/`

### DNS和SSL
- [ ] Cloudflare DNS A记录已配置（@ → 172.245.55.158）
- [ ] Cloudflare DNS A记录已配置（www → 172.245.55.158）
- [ ] Cloudflare代理状态：橙色云朵 ✅
- [ ] Cloudflare SSL模式: Full (strict)
- [ ] Cloudflare Origin Certificate已生成并保存

---

## 🚀 部署步骤（按顺序执行）

### 步骤 1: 打包并上传代码

```bash
# 在本地执行
cd /Users/wangyixiao/WorkSpace/readless

# 确保deploy.sh可执行
chmod +x backend/deploy.sh
chmod +x backend/setup-nginx-cloudflare.sh

# 打包（排除不必要的文件）
tar --exclude='backend/venv' \
    --exclude='backend/__pycache__' \
    --exclude='backend/.pytest_cache' \
    --exclude='backend/*.pyc' \
    -czf readless-backend.tar.gz backend/

# 上传到服务器
scp -P 52941 readless-backend.tar.gz root@172.245.55.158:/root/
```

**预期结果**:
```
readless-backend.tar.gz    100%   XX MB   XX.X MB/s   00:XX
```

### 步骤 2: 解压代码

```bash
# SSH到服务器
ssh -p 52941 root@172.245.55.158

# 解压
cd /root
tar -xzf readless-backend.tar.gz
cd backend

# 验证文件
ls -la
# 应该看到: deploy.sh, docker-compose.prod.yml, .env 等文件
```

### 步骤 3: 运行部署脚本

```bash
# 在服务器的 /root/backend 目录

# 运行部署
bash deploy.sh
```

**预期输出**:
```
🚀 Readless Backend 生产环境部署脚本
================================
✅ 环境检查通过

📦 步骤1: 构建Docker镜像...
[+] Building ...

🗄️  步骤2: 启动数据库...
[+] Running 1/1
 ✔ Container backend-db-1  Started

⏳ 等待数据库就绪...

🔧 步骤3: 运行数据库迁移...
INFO  [alembic.runtime.migration] Running upgrade  -> xxx

🚀 步骤4: 启动API服务...
[+] Running 1/1
 ✔ Container backend-api-1  Started

⏳ 等待API服务启动...

🔍 步骤5: 健康检查...
✅ API服务启动成功！

📊 容器状态：
NAME           IMAGE         STATUS        PORTS
backend-api-1  backend-api   Up X seconds  127.0.0.1:8001->8000/tcp
backend-db-1   postgres:17   Up X seconds  127.0.0.1:5433->5432/tcp

🎉 部署完成！
```

### 步骤 4: 验证部署

```bash
# 在服务器上执行

# 1. 测试本地API健康检查
curl http://127.0.0.1:8001/health
# 应返回: {"status":"ok"}

# 2. 测试HTTPS（如果nginx已配置）
curl https://readless.cc/health
# 应返回: {"status":"ok"}

# 3. 查看容器状态
docker-compose -f docker-compose.prod.yml ps

# 4. 查看API日志
docker-compose -f docker-compose.prod.yml logs --tail=50 api
```

**如果健康检查失败**:
```bash
# 查看详细日志
docker-compose -f docker-compose.prod.yml logs -f

# 检查端口绑定
netstat -tlnp | grep -E ':(8001|5433)'

# 重启服务
docker-compose -f docker-compose.prod.yml restart
```

### 步骤 5: 测试核心功能

```bash
# 测试内容创建
curl -X POST https://readless.cc/api/v1/content/ \
  -H 'Content-Type: application/json' \
  -d '{
    "source_type": "text",
    "body": "这是一篇测试文章。\n\n第一段内容讲解AI技术。\n\n第二段讨论应用场景。"
  }'

# 应返回包含id、l0_summary、l1_outline的JSON
```

---

## 🎯 部署完成标准

所有以下检查通过，才算部署成功：

1. ✅ 本地健康检查: `curl http://127.0.0.1:8001/health` 返回 `{"status":"ok"}`
2. ✅ HTTPS健康检查: `curl https://readless.cc/health` 返回 `{"status":"ok"}`
3. ✅ API文档可访问: https://readless.cc/docs
4. ✅ 内容创建功能正常（AI摘要生成）
5. ✅ 容器持续运行（不崩溃）
6. ✅ 日志无严重错误
7. ✅ 端口正确绑定到127.0.0.1（不对外暴露）

---

## 🔧 配置 macOS 客户端

部署成功后，配置本地客户端连接到生产服务器：

```bash
# 在本地 macOS 执行
cd /Users/wangyixiao/WorkSpace/readless/macos

# 配置后端地址
./configure-backend.sh https://readless.cc

# 或手动配置
defaults write com.readless.app apiBaseURL "https://readless.cc"

# 验证配置
defaults read com.readless.app apiBaseURL
# 应输出: https://readless.cc
```

**重启并测试 App**:
```bash
cd macos
swift run

# 应该看到日志：
# [Readless] Using configured API base URL: https://readless.cc

# 测试导入功能：
# 1. ⌘K 打开 Command Bar
# 2. 粘贴长文本
# 3. Enter 导入
# 4. 应该成功！
```

---

## 🐛 常见问题排查

### 问题1: 容器无法启动

**症状**: `docker-compose ps` 显示容器状态为 Exited

**排查**:
```bash
docker-compose -f docker-compose.prod.yml logs api
# 查看错误日志

# 常见原因：
# - .env 配置错误
# - 端口被占用
# - 数据库连接失败
```

### 问题2: 健康检查失败

**症状**: `curl http://127.0.0.1:8001/health` 连接被拒绝

**排查**:
```bash
# 1. 检查容器是否运行
docker ps | grep backend

# 2. 检查端口绑定
netstat -tlnp | grep 8001

# 3. 进入容器测试
docker-compose -f docker-compose.prod.yml exec api curl http://localhost:8000/health
```

### 问题3: HTTPS访问失败

**症状**: `curl https://readless.cc/health` 超时或SSL错误

**排查**:
```bash
# 1. 测试nginx配置
nginx -t

# 2. 检查nginx是否运行
systemctl status nginx

# 3. 查看nginx日志
tail -f /var/log/nginx/readless.error.log

# 4. 验证Cloudflare设置
# - DNS是否解析正确: nslookup readless.cc
# - SSL模式是否为 Full (strict)
```

### 问题4: AI功能失败

**症状**: 内容创建成功，但无L0/L1摘要

**排查**:
```bash
# 检查OpenAI API配置
docker-compose -f docker-compose.prod.yml exec api env | grep OPENAI

# 查看详细错误
docker-compose -f docker-compose.prod.yml logs api | grep -i error
```

---

## 📞 需要帮助？

- **查看完整部署文档**: [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)
- **查看快速部署**: [QUICK_DEPLOY.md](QUICK_DEPLOY.md)
- **查看问题排查**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---

**核对完成时间**: 2026-03-01
**状态**: ✅ 配置已核对，deploy.sh已修复，可以开始部署
