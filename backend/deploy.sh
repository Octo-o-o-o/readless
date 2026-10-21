#!/bin/bash
set -e

echo "🚀 Readless Backend 生产环境部署脚本"
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

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo -e "${RED}❌ Docker Compose未安装，请先安装Docker Compose${NC}"
    exit 1
fi

# 使用docker compose或docker-compose
DOCKER_COMPOSE="docker-compose"
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
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

# 检查生产环境配置文件
if [ ! -f "docker-compose.prod.yml" ]; then
    echo -e "${RED}❌ docker-compose.prod.yml 不存在${NC}"
    exit 1
fi

echo "📦 步骤1: 构建Docker镜像..."
$DOCKER_COMPOSE -f docker-compose.prod.yml build --no-cache

echo ""
echo "🗄️  步骤2: 启动数据库..."
$DOCKER_COMPOSE -f docker-compose.prod.yml up -d db

echo ""
echo "⏳ 等待数据库就绪..."
sleep 15

echo ""
echo "🔧 步骤3: 运行数据库迁移..."
if [ -d "alembic" ]; then
    $DOCKER_COMPOSE -f docker-compose.prod.yml exec -T api alembic upgrade head || \
    $DOCKER_COMPOSE -f docker-compose.prod.yml run --rm api alembic upgrade head
else
    echo -e "${YELLOW}⚠️  Alembic未初始化，跳过迁移${NC}"
fi

echo ""
echo "🚀 步骤4: 启动API和Worker服务..."
$DOCKER_COMPOSE -f docker-compose.prod.yml up -d api worker

echo ""
echo "⏳ 等待API服务启动..."
sleep 10

echo ""
echo "🔍 步骤5: 健康检查..."
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -sf http://127.0.0.1:8001/health | grep -q "ok"; then
        echo -e "${GREEN}✅ API服务启动成功！${NC}"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            echo -e "${RED}❌ API服务启动失败，查看日志：$DOCKER_COMPOSE -f docker-compose.prod.yml logs api worker${NC}"
            $DOCKER_COMPOSE -f docker-compose.prod.yml logs --tail=50 api
            $DOCKER_COMPOSE -f docker-compose.prod.yml logs --tail=50 worker
            exit 1
        fi
        echo "等待API启动... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 3
    fi
done

echo ""
echo "📊 容器状态："
$DOCKER_COMPOSE -f docker-compose.prod.yml ps

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🎉 部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "📝 下一步："
echo "  1. 测试本地API: curl http://127.0.0.1:8001/health"
echo "  2. 测试HTTPS: curl https://readless.cc/health"
echo "  3. 查看API文档: https://readless.cc/docs"
echo ""
echo "🔧 常用命令："
echo "  查看日志: $DOCKER_COMPOSE -f docker-compose.prod.yml logs -f"
echo "  Worker日志: $DOCKER_COMPOSE -f docker-compose.prod.yml logs -f worker"
echo "  重启服务: $DOCKER_COMPOSE -f docker-compose.prod.yml restart"
echo "  停止服务: $DOCKER_COMPOSE -f docker-compose.prod.yml down"
echo "  备份数据: $DOCKER_COMPOSE -f docker-compose.prod.yml exec db pg_dump -U readless readless > backup.sql"
echo ""
