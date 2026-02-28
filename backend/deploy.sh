#!/bin/bash
set -e

echo "🚀 Readless Backend 一键部署脚本"
echo "================================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否在服务器上运行
if [ ! -f "/etc/nginx/nginx.conf" ]; then
    echo -e "${RED}❌ 此脚本需要在服务器上运行${NC}"
    exit 1
fi

# 检查docker是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker未安装，请先安装Docker${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose未安装，请先安装Docker Compose${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 环境检查通过${NC}"
echo ""

# 检查.env文件
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠️  .env文件不存在，从.env.example创建${NC}"
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo -e "${YELLOW}请编辑 .env 文件填入必要的API密钥${NC}"
        echo -e "${YELLOW}按回车继续，或按Ctrl+C退出去编辑.env文件${NC}"
        read
    else
        echo -e "${RED}❌ .env.example文件不存在${NC}"
        exit 1
    fi
fi

echo "📦 步骤1: 构建Docker镜像..."
docker-compose build

echo ""
echo "🗄️  步骤2: 启动数据库..."
docker-compose up -d db

echo ""
echo "⏳ 等待数据库就绪..."
sleep 10

echo ""
echo "🔧 步骤3: 运行数据库迁移..."
if [ -d "alembic" ]; then
    docker-compose run --rm api alembic upgrade head
else
    echo -e "${YELLOW}⚠️  Alembic未初始化，跳过迁移${NC}"
fi

echo ""
echo "🚀 步骤4: 启动API服务..."
docker-compose up -d api

echo ""
echo "⏳ 等待API服务启动..."
sleep 5

echo ""
echo "🔍 步骤5: 健康检查..."
if curl -s http://127.0.0.1:8001/health | grep -q "ok"; then
    echo -e "${GREEN}✅ API服务启动成功！${NC}"
else
    echo -e "${RED}❌ API服务启动失败，查看日志：docker-compose logs api${NC}"
    exit 1
fi

echo ""
echo "📊 容器状态："
docker-compose ps

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🎉 部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📝 下一步："
echo "  1. 配置nginx反向代理（参考 docs/deployment-guide.md）"
echo "  2. 申请SSL证书: certbot certonly --nginx -d readless.cc"
echo "  3. 测试API: curl https://readless.cc/health"
echo ""
echo "🔧 常用命令："
echo "  查看日志: docker-compose logs -f"
echo "  重启服务: docker-compose restart"
echo "  停止服务: docker-compose down"
echo "  备份数据: docker-compose exec db pg_dump -U readless readless > backup.sql"
echo ""
