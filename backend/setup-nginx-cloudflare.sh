#!/bin/bash
# Nginx配置脚本 - Cloudflare版本
# 使用Cloudflare Origin Certificate，不需要Let's Encrypt

set -e

DOMAIN="readless.cc"

echo "🔧 Readless Nginx配置脚本 (Cloudflare版)"
echo "========================================="
echo ""

# 检查是否为root
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用root权限运行: sudo bash setup-nginx-cloudflare.sh"
    exit 1
fi

# 检查nginx是否已安装
if ! command -v nginx &> /dev/null; then
    echo "📦 安装nginx..."
    apt update
    apt install -y nginx
fi

echo "✅ 依赖检查完成"
echo ""

# 创建SSL证书目录
echo "📁 创建SSL证书目录..."
mkdir -p /etc/nginx/ssl/$DOMAIN

echo ""
echo "🔐 请先在Cloudflare控制台生成Origin Certificate："
echo ""
echo "   1. 登录 https://dash.cloudflare.com"
echo "   2. 选择域名 $DOMAIN"
echo "   3. 进入 SSL/TLS → Origin Server"
echo "   4. 点击 'Create Certificate'"
echo "   5. 配置："
echo "      - 私钥类型: RSA (2048)"
echo "      - 主机名: $DOMAIN, *.$DOMAIN"
echo "      - 有效期: 15 years"
echo "   6. 点击 'Create'"
echo ""
echo "   会得到两个文件内容："
echo "   - Origin Certificate (证书)"
echo "   - Private Key (私钥)"
echo ""
echo "按回车继续..."
read

# 创建证书文件
echo "📝 请粘贴 Origin Certificate 内容（包括 BEGIN 和 END 行）"
echo "粘贴完成后按 Ctrl+D："
cat > /etc/nginx/ssl/$DOMAIN/cert.pem

echo ""
echo "📝 请粘贴 Private Key 内容（包括 BEGIN 和 END 行）"
echo "粘贴完成后按 Ctrl+D："
cat > /etc/nginx/ssl/$DOMAIN/key.pem

# 设置证书权限
chmod 644 /etc/nginx/ssl/$DOMAIN/cert.pem
chmod 600 /etc/nginx/ssl/$DOMAIN/key.pem

echo ""
echo "✅ SSL证书保存完成"
echo ""

# 创建nginx配置
echo "📝 创建nginx配置文件..."
cat > /etc/nginx/sites-available/$DOMAIN << 'NGINX_CONFIG'
# Cloudflare优化配置
# 真实IP获取
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 131.0.72.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2c0f:f248::/32;
set_real_ip_from 2a06:98c0::/29;
real_ip_header CF-Connecting-IP;

server {
    listen 80;
    listen [::]:80;
    server_name readless.cc www.readless.cc;

    # Cloudflare会处理HTTPS重定向，这里可以直接代理
    # 或者仍然重定向到HTTPS（推荐，双重保险）
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name readless.cc www.readless.cc;

    # Cloudflare Origin Certificate
    ssl_certificate /etc/nginx/ssl/readless.cc/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/readless.cc/key.pem;

    # SSL优化配置（针对Cloudflare）
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    # 安全头（部分由Cloudflare处理，但本地也配置）
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    # HSTS由Cloudflare处理，这里不设置避免冲突

    # 日志（会看到Cloudflare的IP）
    access_log /var/log/nginx/readless.access.log;
    error_log /var/log/nginx/readless.error.log;

    # 文件上传大小限制
    client_max_body_size 50M;
    client_body_buffer_size 128k;

    # 超时配置（AI处理可能较长）
    proxy_connect_timeout 75s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;

    # API代理到本地FastAPI服务
    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_http_version 1.1;

        # WebSocket支持
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';

        # 标准代理头（使用Cloudflare的真实IP）
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # Cloudflare特定头传递
        proxy_set_header CF-Connecting-IP $http_cf_connecting_ip;
        proxy_set_header CF-Ray $http_cf_ray;
        proxy_set_header CF-Visitor $http_cf_visitor;

        # 禁用缓存
        proxy_cache_bypass $http_upgrade;
        proxy_no_cache 1;
        proxy_buffering off;
    }

    # 健康检查端点
    location /health {
        proxy_pass http://127.0.0.1:8001/health;
        access_log off;
    }

    # API文档
    location /docs {
        proxy_pass http://127.0.0.1:8001/docs;
    }

    location /redoc {
        proxy_pass http://127.0.0.1:8001/redoc;
    }

    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://127.0.0.1:8001;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # 防止访问敏感文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
NGINX_CONFIG

echo "✅ nginx配置创建完成"
echo ""

# 启用站点
echo "🔗 启用站点配置..."
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# 测试配置
echo "🧪 测试nginx配置..."
if nginx -t; then
    echo "✅ nginx配置测试通过"
else
    echo "❌ nginx配置有误，请检查"
    exit 1
fi

# 重载nginx
echo "🔄 重载nginx..."
systemctl reload nginx

echo ""
echo "🎉 配置完成！"
echo ""
echo "📋 接下来需要在Cloudflare设置："
echo ""
echo "   1. 进入 SSL/TLS → Overview"
echo "   2. 设置加密模式为: Full (strict)"
echo "      ⚠️ 必须选择 'Full (strict)'，不要选 'Flexible' 或 'Full'"
echo ""
echo "   3. （可选）进入 SSL/TLS → Edge Certificates"
echo "      - 启用 'Always Use HTTPS'"
echo "      - 启用 'Automatic HTTPS Rewrites'"
echo "      - 启用 'Minimum TLS Version: 1.2'"
echo ""
echo "   4. 进入 Speed → Optimization"
echo "      - 启用 'Auto Minify' (CSS, JS, HTML)"
echo "      - 启用 'Brotli'"
echo ""
echo "   5. 进入 Network"
echo "      - 启用 'HTTP/2'"
echo "      - 启用 'HTTP/3 (with QUIC)'"
echo ""
echo "📊 验证步骤："
echo "   1. 测试HTTP访问: curl -I http://readless.cc"
echo "   2. 测试HTTPS访问: curl https://readless.cc/health"
echo "   3. 检查SSL: https://www.ssllabs.com/ssltest/analyze.html?d=readless.cc"
echo ""
echo "🔧 常用命令："
echo "   重载nginx: systemctl reload nginx"
echo "   查看日志: tail -f /var/log/nginx/readless.error.log"
echo "   验证证书: openssl s_client -connect readless.cc:443 -servername readless.cc"
echo ""
