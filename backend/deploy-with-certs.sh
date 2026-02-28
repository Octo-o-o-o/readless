#!/bin/bash
# 使用已有证书文件部署nginx配置

set -e

DOMAIN="readless.cc"
CERT_FILE="readless.cc.pem"
KEY_FILE="readless.cc.key"

echo "🔧 Readless Nginx配置脚本 (使用已有证书)"
echo "============================================"
echo ""

# 检查证书文件是否存在
if [ ! -f "$CERT_FILE" ]; then
    echo "❌ 证书文件不存在: $CERT_FILE"
    echo "请确保证书文件在当前目录"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "❌ 私钥文件不存在: $KEY_FILE"
    echo "请确保私钥文件在当前目录"
    exit 1
fi

echo "✅ 找到证书文件: $CERT_FILE"
echo "✅ 找到私钥文件: $KEY_FILE"
echo ""

# 检查是否为root
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用root权限运行: sudo bash deploy-with-certs.sh"
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

# 复制证书文件
echo "📋 复制证书文件..."
cp "$CERT_FILE" /etc/nginx/ssl/$DOMAIN/cert.pem
cp "$KEY_FILE" /etc/nginx/ssl/$DOMAIN/key.pem

# 设置证书权限
chmod 644 /etc/nginx/ssl/$DOMAIN/cert.pem
chmod 600 /etc/nginx/ssl/$DOMAIN/key.pem

echo "✅ 证书文件已复制到 /etc/nginx/ssl/$DOMAIN/"
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

    # 重定向到HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name readless.cc www.readless.cc;

    # Cloudflare Origin Certificate
    ssl_certificate /etc/nginx/ssl/readless.cc/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/readless.cc/key.pem;

    # SSL优化配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # 日志
    access_log /var/log/nginx/readless.access.log;
    error_log /var/log/nginx/readless.error.log;

    # 文件上传大小限制
    client_max_body_size 50M;
    client_body_buffer_size 128k;

    # 超时配置
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

        # 标准代理头
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # Cloudflare特定头
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
echo "🎉 Nginx配置完成！"
echo ""
echo "📋 接下来的步骤："
echo ""
echo "   1. 确保Cloudflare SSL模式设置为: Full (strict)"
echo "      路径: SSL/TLS → Overview → Full (strict)"
echo ""
echo "   2. 确保DNS记录代理状态为: 已代理（橙色云朵）"
echo ""
echo "   3. 启动后端服务:"
echo "      cd /root/backend"
echo "      bash deploy.sh"
echo ""
echo "   4. 验证部署:"
echo "      curl http://127.0.0.1:8001/health"
echo "      curl https://readless.cc/health"
echo ""
echo "🔧 常用命令："
echo "   重载nginx: systemctl reload nginx"
echo "   查看日志: tail -f /var/log/nginx/readless.error.log"
echo "   验证证书: openssl x509 -in /etc/nginx/ssl/$DOMAIN/cert.pem -text -noout"
echo ""
