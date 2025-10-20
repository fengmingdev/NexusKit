#!/bin/bash

# NexusKit 测试服务器启动脚本

echo "🚀 启动 NexusKit 测试服务器..."

# 切换到脚本目录
cd "$(dirname "$0")"

# 检查 Node.js
if ! command -v node &> /dev/null; then
    echo "❌ Node.js 未安装"
    exit 1
fi

# 安装依赖
if [ ! -d "node_modules" ]; then
    echo "📦 安装依赖..."
    npm install
fi

# 启动所有服务器
echo "▶️  启动服务器..."
echo ""
echo "📡 TCP 服务器: 127.0.0.1:8888"
echo "🌐 WebSocket 服务器: ws://localhost:8080"
echo "⚡ Socket.IO 服务器: http://localhost:3000"
echo ""
echo "按 Ctrl+C 停止所有服务器"
echo ""

npm run all
