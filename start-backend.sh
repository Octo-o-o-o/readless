#!/bin/bash

# Readless Backend 启动脚本

set -e

cd "$(dirname "$0")/backend"

echo "🚀 Starting Readless Backend..."
echo "📍 Location: $(pwd)"
echo ""

# 检查虚拟环境
if [ ! -d "venv" ]; then
    echo "⚙️  Creating virtual environment..."
    python3 -m venv venv
fi

# 激活虚拟环境
source venv/bin/activate

# 检查依赖
if [ ! -f "venv/.deps_installed" ]; then
    echo "📦 Installing dependencies..."
    pip install --upgrade pip
    pip install -e ".[dev]"
    touch venv/.deps_installed
fi

# 检查.env文件
if [ ! -f ".env" ]; then
    echo "⚠️  Warning: .env file not found!"
    echo "Please create .env file with your configuration."
    echo "See .env.example for reference."
    exit 1
fi

# 启动服务器
echo "✅ Starting FastAPI server on http://localhost:8000"
echo "Press Ctrl+C to stop"
echo ""

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
