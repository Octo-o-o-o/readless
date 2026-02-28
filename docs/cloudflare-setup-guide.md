# Cloudflare配置指南 - Readless

## 概述

使用Cloudflare托管域名时，SSL配置更简单且功能更强大：

✅ **优势**：
- 免费SSL证书（15年有效期）
- 自动DDoS防护
- 全球CDN加速
- 流量分析
- 页面规则和缓存优化

⚠️ **与传统Let's Encrypt的区别**：
- **不需要**certbot
- **不需要**定期续期
- 使用Cloudflare Origin Certificate

---

## 第一步：DNS配置

### 1. 登录Cloudflare

访问 https://dash.cloudflare.com → 选择 `readless.cc`

### 2. 添加DNS记录

进入 **DNS → Records**

#### A记录（必需）
```
类型: A
名称: @
内容: 172.245.55.158
代理状态: 已代理（橙色云朵） ← 重要！
TTL: Auto
```

#### A记录 - www（可选）
```
类型: A
名称: www
内容: 172.245.55.158
代理状态: 已代理（橙色云朵）
TTL: Auto
```

⚠️ **代理状态说明**：
- 🟠 **已代理（橙色云朵）**：流量经过Cloudflare，启用CDN和安全功能（推荐）
- ⚫ **仅DNS（灰色云朵）**：直连源服务器，需要Let's Encrypt证书

**推荐选择：橙色云朵（已代理）**

---

## 第二步：SSL/TLS配置

### 1. 生成Origin Certificate

进入 **SSL/TLS → Origin Server**

点击 **Create Certificate**

配置选项：
```
证书格式: PEM
私钥类型: RSA (2048)
主机名:
  ✓ readless.cc
  ✓ *.readless.cc
有效期: 15 years（推荐）
```

点击 **Create**

### 2. 保存证书

会显示两个文本框：

#### Origin Certificate
```
-----BEGIN CERTIFICATE-----
MIIEpDCCAoygAwIBAgIUdO...
（一大段文字）
-----END CERTIFICATE-----
```
**复制整个内容**，稍后会用到。

#### Private Key
```
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w...
（一大段文字）
-----END PRIVATE KEY-----
```
**复制整个内容**，稍后会用到。

⚠️ **重要**：私钥只会显示一次，请立即保存！

### 3. 设置加密模式

进入 **SSL/TLS → Overview**

选择加密模式：**Full (strict)** ← 必须选这个！

```
❌ Off - 不加密
❌ Flexible - Cloudflare到源服务器不加密（不安全）
❌ Full - Cloudflare到源服务器加密，但不验证证书
✅ Full (strict) - 完全加密且验证证书（推荐）
❌ Strict (SSL-Only Origin Pull) - 企业功能
```

---

## 第三步：服务器配置

### 1. 上传并运行配置脚本

```bash
# SSH到服务器
ssh -p 52941 root@172.245.55.158

cd /root/backend

# 运行Cloudflare版本的配置脚本
chmod +x setup-nginx-cloudflare.sh
bash setup-nginx-cloudflare.sh
```

### 2. 脚本会提示粘贴证书

#### 粘贴Origin Certificate
当看到提示 `"请粘贴 Origin Certificate 内容"`：
1. 粘贴之前复制的完整证书内容（包括BEGIN和END行）
2. 按 `Ctrl+D` 完成输入

#### 粘贴Private Key
当看到提示 `"请粘贴 Private Key 内容"`：
1. 粘贴之前复制的完整私钥内容（包括BEGIN和END行）
2. 按 `Ctrl+D` 完成输入

脚本会自动：
- ✅ 保存证书到 `/etc/nginx/ssl/readless.cc/`
- ✅ 配置nginx
- ✅ 设置Cloudflare真实IP获取
- ✅ 重载nginx

---

## 第四步：Cloudflare优化配置

### 1. SSL/TLS优化

进入 **SSL/TLS → Edge Certificates**

推荐配置：
```
✓ Always Use HTTPS - 自动重定向HTTP到HTTPS
✓ HTTP Strict Transport Security (HSTS)
  - Max Age: 6 months
  - Include subdomains: ✓
  - Preload: ✗（可选）
✓ Minimum TLS Version: TLS 1.2
✓ Opportunistic Encryption: ✓
✓ TLS 1.3: ✓
✓ Automatic HTTPS Rewrites: ✓
```

### 2. 速度优化

进入 **Speed → Optimization**

```
Auto Minify:
  ✓ JavaScript
  ✓ CSS
  ✓ HTML

✓ Brotli
✓ Early Hints
✓ Rocket Loader（API项目可不启用）
```

### 3. 缓存配置

进入 **Caching → Configuration**

```
Caching Level: Standard
Browser Cache TTL: Respect Existing Headers
```

创建缓存规则（**Rules → Page Rules**）：

#### 规则1：API不缓存
```
URL: readless.cc/api/*
设置:
  - Cache Level: Bypass
```

#### 规则2：健康检查不缓存
```
URL: readless.cc/health
设置:
  - Cache Level: Bypass
```

#### 规则3：静态资源缓存（如果有）
```
URL: readless.cc/*.{jpg,jpeg,png,gif,css,js}
设置:
  - Cache Level: Cache Everything
  - Edge Cache TTL: 1 month
```

### 4. 网络优化

进入 **Network**

```
✓ HTTP/2
✓ HTTP/3 (with QUIC)
✓ 0-RTT Connection Resumption
✓ IPv6 Compatibility
✓ WebSockets
✓ Onion Routing
✓ Pseudo IPv4
```

### 5. 安全设置

进入 **Security → Settings**

```
Security Level: Medium（默认）
Challenge Passage: 30 minutes
Browser Integrity Check: ✓
Privacy Pass Support: ✓
```

进入 **Security → Bots**

```
Bot Fight Mode: ✓（免费计划可用）
```

### 6. 防火墙规则（可选）

进入 **Security → WAF**

创建防火墙规则保护API：

```
规则名称: Rate Limit API
表达式:
  (http.request.uri.path matches "/api/.*")
动作: Managed Challenge
速率限制: 100 requests per 10 minutes
```

---

## 第五步：验证配置

### 1. DNS传播检查

```bash
# 检查DNS解析
nslookup readless.cc

# 应该看到Cloudflare的IP（不是源服务器IP）
```

### 2. 本地测试

```bash
# SSH到服务器
ssh -p 52941 root@172.245.55.158

# 测试本地端口
curl http://127.0.0.1:8001/health
# 应返回: {"status":"ok"}

# 测试nginx配置
curl -k https://127.0.0.1/health
# 应返回: {"status":"ok"}
```

### 3. 通过Cloudflare测试

```bash
# 在任何机器上执行
curl https://readless.cc/health
# 应返回: {"status":"ok"}

# 检查响应头（查看Cloudflare标识）
curl -I https://readless.cc/health
# 应该看到: cf-ray, cf-cache-status 等头
```

### 4. SSL质量测试

访问 SSL Labs 测试：
```
https://www.ssllabs.com/ssltest/analyze.html?d=readless.cc
```

期望结果：**A或A+评级**

### 5. 查看Cloudflare日志

在Cloudflare控制台：
- **Analytics → Traffic** - 查看流量统计
- **Analytics → Security** - 查看安全事件
- **Analytics → Performance** - 查看性能指标

---

## 对比：Cloudflare vs Let's Encrypt

| 特性 | Cloudflare Origin Certificate | Let's Encrypt |
|------|------------------------------|---------------|
| 证书有效期 | 15年 | 90天 |
| 自动续期 | 不需要 | 需要（certbot） |
| 配置难度 | ⭐⭐ 简单 | ⭐⭐⭐ 中等 |
| CDN加速 | ✅ 包含 | ❌ 需额外配置 |
| DDoS防护 | ✅ 包含 | ❌ 无 |
| WAF防火墙 | ✅ 包含 | ❌ 无 |
| 成本 | 免费 | 免费 |
| 浏览器信任 | ✅ 是 | ✅ 是 |
| 适用场景 | 已用Cloudflare DNS | 直连服务器 |

**推荐**：如果域名在Cloudflare，强烈建议使用Cloudflare Origin Certificate。

---

## 常见问题

### Q1: 为什么要选择"Full (strict)"模式？

**A**:
- ❌ **Flexible**: Cloudflare到源服务器是HTTP（不安全）
- ⚠️ **Full**: Cloudflare到源服务器是HTTPS，但不验证证书（中间人攻击风险）
- ✅ **Full (strict)**: 完全加密且验证Origin Certificate（最安全）

### Q2: 如果证书过期了怎么办？

**A**: Origin Certificate有效期15年，到期前Cloudflare会提醒。到时重新生成一个即可。

### Q3: 可以同时用Let's Encrypt吗？

**A**: 可以，但没必要。Cloudflare Origin Certificate已经足够，且更简单。

### Q4: 如何获取真实访问者IP？

**A**: 已在nginx配置中设置，使用：
- `$http_cf_connecting_ip` - Cloudflare传递的真实IP
- `$remote_addr` - 会显示Cloudflare的IP

FastAPI中获取：
```python
real_ip = request.headers.get("CF-Connecting-IP") or request.client.host
```

### Q5: Cloudflare缓存会影响API吗？

**A**: 不会，已配置Page Rule绕过API路径缓存。

### Q6: 如何临时禁用Cloudflare代理？

**A**: DNS记录中将橙色云朵改为灰色即可（需几分钟生效）。

### Q7: 流量很大会收费吗？

**A**: Cloudflare免费计划**无流量限制**，但有请求速率限制（约1000 req/s）。

---

## 故障排查

### 问题1: 502 Bad Gateway

**原因**：
- 源服务器未启动
- nginx配置错误
- 防火墙阻止

**解决**：
```bash
# 检查后端服务
docker-compose ps

# 检查nginx状态
systemctl status nginx

# 查看nginx日志
tail -f /var/log/nginx/readless.error.log

# 测试本地连接
curl http://127.0.0.1:8001/health
```

### 问题2: 526 Invalid SSL Certificate

**原因**：
- SSL模式设置错误（应为Full strict）
- Origin Certificate未正确配置

**解决**：
```bash
# 检查证书文件
ls -la /etc/nginx/ssl/readless.cc/

# 验证nginx配置
nginx -t

# 检查SSL模式
# 在Cloudflare控制台确认是 Full (strict)
```

### 问题3: 看不到真实IP

**原因**：
- nginx未配置Cloudflare IP段
- 未读取CF-Connecting-IP头

**解决**：
已在 `setup-nginx-cloudflare.sh` 中配置，检查：
```bash
grep "set_real_ip_from" /etc/nginx/sites-available/readless.cc
```

### 问题4: HTTPS重定向循环

**原因**：
- SSL模式设置为Flexible
- nginx配置冲突

**解决**：
1. 确保SSL模式是 **Full (strict)**
2. 检查nginx配置中的重定向逻辑

---

## 下一步

完成Cloudflare配置后：

1. ✅ 部署后端服务（参考 [backend/README.md](../backend/README.md)）
2. ✅ 测试API端点
3. ✅ 监控Cloudflare Analytics
4. ✅ 配置告警（可选）

---

## 额外优化（可选）

### 1. Argo Smart Routing（收费）

加速全球访问，$5/月起。

### 2. Workers

可在边缘处理简单逻辑，如：
- 速率限制
- 请求转换
- A/B测试

### 3. Load Balancing（收费）

多源服务器负载均衡，$5/月起。

### 4. 图片优化（收费）

Polish、Image Resizing等功能。

---

## 总结

使用Cloudflare托管域名的优势：

✅ **更简单**：无需certbot，证书15年有效
✅ **更安全**：内置DDoS、WAF、Bot防护
✅ **更快速**：全球CDN、HTTP/3、Brotli压缩
✅ **更智能**：流量分析、缓存优化、页面规则
✅ **零成本**：免费计划已满足大部分需求

按照本指南配置后，你的API将获得企业级的安全性和性能！🚀
