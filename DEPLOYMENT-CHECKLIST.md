# Readless 部署清单

## ✅ 部署前准备

### 1. Cloudflare DNS配置
- [ ] 登录Cloudflare控制台 (https://dash.cloudflare.com)
- [ ] 选择域名 readless.cc
- [ ] 添加A记录（主域名）
  - 类型: A
  - 名称: @
  - 内容: 172.245.55.158
  - 代理状态: ✅ 已代理（橙色云朵）← 重要！
  - TTL: Auto
- [ ] 添加A记录（www子域名）
  - 类型: A
  - 名称: www
  - 内容: 172.245.55.158
  - 代理状态: ✅ 已代理（橙色云朵）
  - TTL: Auto
- [ ] 等待DNS传播（约2-5分钟）

### 1.1 Cloudflare SSL证书准备
- [ ] 进入 SSL/TLS → Origin Server
- [ ] 点击 "Create Certificate"
- [ ] 配置证书参数
  - 私钥类型: RSA (2048)
  - 主机名: readless.cc, *.readless.cc
  - 有效期: 15 years
- [ ] 点击 "Create"
- [ ] 复制并保存 "Origin Certificate" 内容
- [ ] 复制并保存 "Private Key" 内容（只显示一次！）
- [ ] 设置加密模式: SSL/TLS → Overview → Full (strict)

### 2. API密钥准备
- [ ] OpenAI API Key (https://platform.openai.com/)
- [ ] Clerk Secret Key (https://clerk.com/)
- [ ] Cloudflare R2配置
  - [ ] Account ID
  - [ ] Access Key ID
  - [ ] Secret Access Key
  - [ ] 创建bucket: readless
- [ ] ElevenLabs API Key (https://elevenlabs.io/)

### 3. 本地准备
- [ ] 克隆代码到本地
- [ ] 配置 `backend/.env` 文件

---

## 🚀 部署流程

### 步骤1: 上传代码

```bash
# 在本地执行
cd /Users/wangyixiao/WorkSpace/readless
tar -czf readless-backend.tar.gz backend/
scp -P 52941 readless-backend.tar.gz root@172.245.55.158:/root/
```

- [ ] 代码上传完成

### 步骤2: 配置Nginx

```bash
# SSH到服务器
ssh -p 52941 root@172.245.55.158

# 解压代码
cd /root
tar -xzf readless-backend.tar.gz
cd backend

# 运行Cloudflare版nginx配置脚本
chmod +x setup-nginx-cloudflare.sh
sudo bash setup-nginx-cloudflare.sh

# 脚本会提示粘贴证书，准备好之前从Cloudflare复制的：
# 1. Origin Certificate（包括BEGIN/END行）→ 粘贴后按Ctrl+D
# 2. Private Key（包括BEGIN/END行）→ 粘贴后按Ctrl+D
```

- [ ] Nginx配置完成
- [ ] Cloudflare Origin Certificate已安装
- [ ] Nginx配置测试通过

### 步骤3: 启动后端服务

```bash
# 在服务器的 /root/backend 目录

# 确保.env文件已配置
nano .env

# 运行部署脚本
chmod +x deploy.sh
bash deploy.sh
```

- [ ] 容器构建成功
- [ ] 数据库启动成功
- [ ] API服务启动成功

### 步骤4: 验证部署

```bash
# 健康检查
curl https://readless.cc/health
# 应返回: {"status":"ok"}

# 测试API（本地测试）
curl http://127.0.0.1:8001/health

# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f api
```

- [ ] 本地健康检查通过
- [ ] HTTPS健康检查通过
- [ ] API文档可访问 (https://readless.cc/docs)

### 步骤5: 测试核心功能

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

- [ ] 内容创建成功
- [ ] AI摘要生成正常
- [ ] 数据存储正常

---

## 📊 部署后检查

### 资源监控
```bash
# 查看容器资源使用
docker stats

# 查看系统资源
free -h
df -h
```

- [ ] 内存使用正常 (< 80%)
- [ ] 磁盘空间充足 (> 10GB)
- [ ] CPU负载正常 (< 2.0)

### 日志检查
```bash
# API日志
docker-compose logs api | tail -50

# 数据库日志
docker-compose logs db | tail -50

# Nginx日志
tail -50 /var/log/nginx/readless.error.log
```

- [ ] 无严重错误
- [ ] API正常响应请求

### 安全检查
```bash
# 检查防火墙
ufw status

# 检查SSL证书
certbot certificates

# 检查敏感端口（不应对外暴露）
netstat -tlnp | grep -E ':(8001|5433)'
```

- [ ] 8001端口仅绑定127.0.0.1
- [ ] 5433端口仅绑定127.0.0.1
- [ ] SSL证书有效期 > 30天
- [ ] 防火墙规则正确

---

## 🔧 配置macOS客户端

### 修改客户端配置

```swift
// macos/Sources/Networking/APIClient.swift
public init(baseURL: URL = URL(string: "https://readless.cc")!) {
    self.baseURL = baseURL
    self.session = .shared
}
```

- [ ] 客户端指向生产环境URL
- [ ] 客户端可以连接API
- [ ] 认证流程正常

---

## 📝 运维设置

### 自动备份
```bash
# 创建备份脚本
cat > /root/backup-readless.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/root/backups/readless"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
docker-compose -f /root/backend/docker-compose.prod.yml exec -T db \
  pg_dump -U readless readless | gzip > $BACKUP_DIR/backup_$DATE.sql.gz
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete
EOF

chmod +x /root/backup-readless.sh

# 添加到crontab（每天凌晨3点备份）
(crontab -l 2>/dev/null; echo "0 3 * * * /root/backup-readless.sh") | crontab -
```

- [ ] 备份脚本创建
- [ ] Cron任务添加
- [ ] 测试备份执行

### 监控告警
```bash
# 健康检查告警
cat > /root/health-check.sh << 'EOF'
#!/bin/bash
if ! curl -sf https://readless.cc/health > /dev/null; then
    echo "Readless API is down!" | mail -s "Readless Alert" your-email@example.com
fi
EOF

chmod +x /root/health-check.sh

# 每5分钟检查一次
(crontab -l 2>/dev/null; echo "*/5 * * * * /root/health-check.sh") | crontab -
```

- [ ] 健康检查脚本创建
- [ ] 邮件告警配置

### SSL证书自动续期
```bash
# 测试自动续期
certbot renew --dry-run

# certbot会自动添加续期任务，验证
systemctl list-timers | grep certbot
```

- [ ] 自动续期测试通过

---

## 🎯 完成标准

所有以下条件满足时，部署完成：

1. ✅ HTTPS访问正常 (https://readless.cc/health)
2. ✅ API文档可访问 (https://readless.cc/docs)
3. ✅ 内容创建功能正常
4. ✅ AI摘要生成正常
5. ✅ 搜索功能正常
6. ✅ SSL证书有效
7. ✅ 自动备份已配置
8. ✅ 监控告警已设置
9. ✅ macOS客户端可连接

---

## 📞 问题排查

遇到问题时：

1. **查看日志**
   ```bash
   docker-compose logs -f
   tail -f /var/log/nginx/readless.error.log
   ```

2. **重启服务**
   ```bash
   docker-compose restart
   systemctl reload nginx
   ```

3. **检查配置**
   ```bash
   docker-compose config
   nginx -t
   ```

4. **查看资源**
   ```bash
   docker stats
   free -h
   df -h
   ```

5. **参考文档**
   - [backend/README.md](backend/README.md)
   - [docs/deployment-guide.md](docs/deployment-guide.md)

---

## 📅 定期维护

### 每周
- [ ] 检查磁盘空间
- [ ] 查看错误日志
- [ ] 验证备份完整性

### 每月
- [ ] 更新系统包: `apt update && apt upgrade`
- [ ] 更新Docker镜像: `docker-compose pull`
- [ ] 检查SSL证书有效期
- [ ] 审查资源使用趋势

### 每季度
- [ ] 审查安全配置
- [ ] 优化数据库性能
- [ ] 清理旧备份和日志
