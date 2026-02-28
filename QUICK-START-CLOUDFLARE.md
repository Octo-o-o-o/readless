# Readless 快速部署指南（Cloudflare版）

## 🎯 5步完成部署

### 前置条件
- ✅ 域名 `readless.cc` 托管在Cloudflare
- ✅ 服务器: 172.245.55.158（SSH端口52941）
- ✅ 已准备好各种API密钥

---

## 📋 Step 1: Cloudflare配置（10分钟）

### 1.1 配置DNS

登录 https://dash.cloudflare.com → 选择 `readless.cc` → DNS

添加两条A记录：

```
记录1:
类型: A
名称: @
内容: 172.245.55.158
代理: 🟠 已代理（橙色云朵）← 必须！
TTL: Auto

记录2:
类型: A
名称: www
内容: 172.245.55.158
代理: 🟠 已代理（橙色云朵）
TTL: Auto
```

### 1.2 生成SSL证书

**SSL/TLS → Origin Server → Create Certificate**

配置：
```
私钥类型: RSA (2048)
主机名: readless.cc, *.readless.cc
有效期: 15 years
```

点击 **Create** 后会显示：
1. **Origin Certificate** - 复制保存
2. **Private Key** - 复制保存（只显示一次！）

### 1.3 设置加密模式

**SSL/TLS → Overview**

选择：**Full (strict)** ✅ ← 必须选这个！

✅ **Cloudflare配置完成**

---

## 📋 Step 2: 准备.env配置（5分钟）

在本地编辑 `backend/.env`：

```bash
cd /Users/wangyixiao/WorkSpace/readless/backend

# 复制模板
cp .env.example .env

# 编辑配置
nano .env
```

必须填写的配置：
```bash
# 数据库密码（自己设置一个强密码）
POSTGRES_PASSWORD=你的强密码

# Claude API
ANTHROPIC_API_KEY=sk-ant-api03-xxx

# Clerk认证
CLERK_SECRET_KEY=sk_live_xxx

# Cloudflare R2存储
R2_ENDPOINT=https://你的账户ID.r2.cloudflarestorage.com
R2_ACCESS_KEY=xxx
R2_SECRET_KEY=xxx
R2_BUCKET=readless

# ElevenLabs语音
ELEVENLABS_API_KEY=xxx

# 域名（已改为readless.cc）
DOMAIN=readless.cc
```

✅ **.env配置完成**

---

## 📋 Step 3: 上传代码（2分钟）

```bash
# 在本地执行
cd /Users/wangyixiao/WorkSpace/readless

# 打包
tar -czf readless-backend.tar.gz backend/

# 上传到服务器
scp -P 52941 readless-backend.tar.gz root@172.245.55.158:/root/
```

✅ **代码上传完成**

---

## 📋 Step 4: 服务器配置（10分钟）

```bash
# SSH连接服务器
ssh -p 52941 root@172.245.55.158

# 解压代码
cd /root
tar -xzf readless-backend.tar.gz
cd backend

# 运行nginx配置脚本（Cloudflare版）
chmod +x setup-nginx-cloudflare.sh
bash setup-nginx-cloudflare.sh
```

**脚本会提示你粘贴证书**：

#### 提示1: 粘贴Origin Certificate
```
📝 请粘贴 Origin Certificate 内容（包括 BEGIN 和 END 行）
粘贴完成后按 Ctrl+D：
```
→ 粘贴之前从Cloudflare复制的 **Origin Certificate** 完整内容
→ 按 `Ctrl+D` 完成

#### 提示2: 粘贴Private Key
```
📝 请粘贴 Private Key 内容（包括 BEGIN 和 END 行）
粘贴完成后按 Ctrl+D：
```
→ 粘贴之前从Cloudflare复制的 **Private Key** 完整内容
→ 按 `Ctrl+D` 完成

脚本会自动：
- ✅ 安装nginx
- ✅ 配置SSL证书
- ✅ 设置Cloudflare真实IP获取
- ✅ 重载nginx

✅ **Nginx配置完成**

---

## 📋 Step 5: 启动后端服务（5分钟）

```bash
# 仍在服务器的 /root/backend 目录

# 方式1: 一键部署脚本（推荐）
chmod +x deploy.sh
bash deploy.sh

# 方式2: 手动部署
docker-compose -f docker-compose.prod.yml up -d --build
docker-compose exec api alembic upgrade head
```

等待容器启动（约1-2分钟）

✅ **后端服务启动完成**

---

## ✅ Step 6: 验证部署（2分钟）

### 6.1 健康检查

```bash
# 本地端口测试
curl http://127.0.0.1:8001/health
# 应返回: {"status":"ok"}

# 通过域名测试（HTTPS）
curl https://readless.cc/health
# 应返回: {"status":"ok"}
```

### 6.2 查看服务状态

```bash
# 查看容器
docker-compose ps
# api和db都应该是Up状态

# 查看日志
docker-compose logs -f api
# 按Ctrl+C退出
```

### 6.3 测试API

在浏览器访问：
- API文档: https://readless.cc/docs
- 健康检查: https://readless.cc/health

或用curl测试创建内容：
```bash
curl -X POST https://readless.cc/api/v1/content/ \
  -H 'Content-Type: application/json' \
  -d '{
    "source_type": "text",
    "body": "这是测试文章。\n\n第一段内容。\n\n第二段内容。"
  }'
```

应返回包含 `id`, `l0_summary`, `l1_outline` 的JSON。

✅ **部署验证完成**

---

## 🎉 完成！

你的Readless后端已成功部署！

### 访问地址
- 🌐 API基础URL: `https://readless.cc`
- 📖 API文档: `https://readless.cc/docs`
- ❤️ 健康检查: `https://readless.cc/health`

### 下一步

1. **配置Cloudflare优化**（可选，10分钟）
   - 参考: [docs/cloudflare-setup-guide.md](docs/cloudflare-setup-guide.md)
   - 启用缓存规则、速率限制等

2. **配置监控和备份**
   - 参考: [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)
   - 设置自动备份、健康检查告警

3. **连接macOS客户端**
   - 修改客户端API URL为 `https://readless.cc`
   - 配置Clerk认证

---

## 🔧 常用运维命令

```bash
# 查看日志
docker-compose logs -f

# 重启服务
docker-compose restart

# 停止服务
docker-compose down

# 备份数据库
docker-compose exec db pg_dump -U readless readless > backup.sql

# 查看资源使用
docker stats

# 更新代码
git pull  # 或重新上传
docker-compose up -d --build
docker-compose exec api alembic upgrade head
```

---

## 🆘 遇到问题？

### 问题1: 502 Bad Gateway

```bash
# 检查容器状态
docker-compose ps

# 查看API日志
docker-compose logs api

# 重启服务
docker-compose restart
```

### 问题2: SSL错误

确认Cloudflare配置：
- ✅ SSL模式: **Full (strict)**
- ✅ DNS代理: 橙色云朵（已代理）
- ✅ Origin Certificate已正确安装

### 问题3: 数据库连接失败

```bash
# 检查数据库容器
docker-compose logs db

# 进入数据库测试
docker-compose exec db psql -U readless
```

### 更多帮助

- [完整部署文档](docs/deployment-guide.md)
- [Cloudflare配置指南](docs/cloudflare-setup-guide.md)
- [后端README](backend/README.md)
- [故障排查清单](DEPLOYMENT-CHECKLIST.md)

---

## ⏱️ 总耗时估算

- Cloudflare配置: 10分钟
- 准备.env: 5分钟
- 上传代码: 2分钟
- 服务器配置: 10分钟
- 启动服务: 5分钟
- 验证测试: 2分钟

**总计: ~35分钟**

---

祝部署顺利！🚀
