#!/bin/bash
# Nginx配置自动化脚本 - 需要在服务器上以root运行

set -e

DOMAIN="readless.cc"
EMAIL="your-email@example.com"  # 修改为你的邮箱

echo "🔧 Readless Nginx配置脚本"
echo "========================="
echo ""

# 检查是否为root
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用root权限运行: sudo bash setup-nginx.sh"
    exit 1
fi

# 检查nginx是否已安装
if ! command -v nginx &> /dev/null; then
    echo "📦 安装nginx..."
    apt update
    apt install -y nginx
fi

# 检查certbot是否已安装
if ! command -v certbot &> /dev/null; then
    echo "📦 安装certbot..."
    apt install -y certbot python3-certbot-nginx
fi

echo "✅ 依赖检查完成"
echo ""

# 创建nginx配置
echo "📝 创建nginx配置文件..."
cat > /etc/nginx/sites-available/$DOMAIN << 'NGINX_CONFIG'
server {
    listen 80;
    server_name readless.cc www.readless.cc;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name readless.cc www.readless.cc;

    # SSL证书将由certbot自动配置
    ssl_certificate /etc/letsencrypt/live/readless.cc/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/readless.cc/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    access_log /var/log/nginx/readless.access.log;
    error_log /var/log/nginx/readless.error.log;

    client_max_body_size 50M;
    proxy_connect_timeout 75s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;

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
    }

    location /health {
        proxy_pass http://127.0.0.1:8001/health;
        access_log off;
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
echo "📜 申请SSL证书..."
echo "⚠️  确保DNS已正确解析到本服务器IP"
echo "按回车继续申请证书，或按Ctrl+C退出"
read

# 申请证书
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    certbot certonly --nginx \
        -d $DOMAIN \
        -d www.$DOMAIN \
        --email $EMAIL \
        --agree-tos \
        --no-eff-email \
        --non-interactive || {
            echo "⚠️  证书申请失败，可能是DNS未就绪"
            echo "稍后可手动运行: certbot certonly --nginx -d $DOMAIN"
            exit 1
        }

    echo "✅ SSL证书申请成功"

    # 重载nginx应用证书
    systemctl reload nginx
else
    echo "ℹ️  证书已存在，跳过申请"
fi

echo ""
echo "🎉 配置完成！"
echo ""
echo "📋 验证步骤："
echo "  1. 检查nginx状态: systemctl status nginx"
echo "  2. 测试HTTP访问: curl http://$DOMAIN/health"
echo "  3. 测试HTTPS访问: curl https://$DOMAIN/health"
echo "  4. 查看证书信息: certbot certificates"
echo ""
echo "🔧 常用命令："
echo "  重载nginx: systemctl reload nginx"
echo "  查看日志: tail -f /var/log/nginx/readless.error.log"
echo "  续期证书: certbot renew"
echo ""
