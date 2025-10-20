# NexusKit 快速开始指南

## 🎯 立即开始测试

### 步骤 1: 安装测试服务器依赖

```bash
cd TestServers
npm install
```

预计时间: 1-2 分钟

### 步骤 2: 启动测试服务器

```bash
./start_all.sh
```

或者分别启动：

```bash
# 终端 1 - TCP 服务器
npm run tcp

# 终端 2 - WebSocket 服务器
npm run ws

# 终端 3 - Socket.IO 服务器
npm run io
```

服务器地址：
- **TCP**: 127.0.0.1:8888
- **WebSocket**: ws://localhost:8080
- **Socket.IO**: http://localhost:3000

### 步骤 3: 运行测试

在新终端中：

```bash
cd ..  # 回到 NexusKit 根目录
swift test
```

### 步骤 4: 查看测试报告

```bash
# 运行特定模块测试
swift test --filter NexusCoreTests

# 查看详细输出
swift test --verbose

# 生成代码覆盖率
swift test --enable-code-coverage
```

---

## 🔧 手动测试

### 测试 TCP 服务器

```bash
# 使用 telnet
telnet 127.0.0.1 8888

# 或使用 nc
nc 127.0.0.1 8888
```

### 测试 WebSocket 服务器

浏览器控制台：

```javascript
const ws = new WebSocket('ws://localhost:8080');

ws.onopen = () => {
    console.log('连接成功');
    ws.send(JSON.stringify({ type: 'ping' }));
};

ws.onmessage = (event) => {
    console.log('收到消息:', event.data);
};
```

### 测试 Socket.IO 服务器

创建测试文件 `test_socketio.html`:

```html
<!DOCTYPE html>
<html>
<head>
    <title>Socket.IO Test</title>
    <script src="https://cdn.socket.io/4.5.0/socket.io.min.js"></script>
</head>
<body>
    <h1>Socket.IO Test</h1>
    <div id="output"></div>
    
    <script>
        const socket = io('http://localhost:3000');
        const output = document.getElementById('output');
        
        socket.on('welcome', (data) => {
            output.innerHTML += '<p>欢迎: ' + JSON.stringify(data) + '</p>';
        });
        
        socket.on('chat', (data) => {
            output.innerHTML += '<p>聊天: ' + JSON.stringify(data) + '</p>';
        });
        
        // 发送测试消息
        socket.emit('chat', { message: 'Hello from browser!' });
    </script>
</body>
</html>
```

在浏览器打开此文件。

---

## 📊 测试状态检查

### 当前测试通过情况

```bash
# 预期结果
✅ NexusCoreTests/ConnectionStateTests: 11/11
✅ NexusCoreTests/MiddlewareTests: 全部通过
✅ NexusCoreTests/LockTests: 全部通过
✅ NexusCoreTests/ReconnectionStrategyTests: 全部通过
✅ NexusCoreTests/NexusErrorTests: 全部通过
⚠️  NexusCoreTests/DataExtensionsTests: 部分通过
⚠️  NexusTCPTests/TCPConnectionTests: 18/22
⚠️  NexusTCPTests/BinaryProtocolAdapterTests: 3/23
```

### 需要修复的测试

1. **BinaryProtocolAdapterTests** (优先级: P0)
   - 20/23 失败
   - 问题: 协议编解码逻辑

2. **DataExtensionsTests** (优先级: P0)
   - 部分失败
   - 问题: GZIP 压缩/解压缩

3. **TCPConnectionTests** (优先级: P1)
   - 4/22 失败
   - 问题: 生命周期钩子

---

## 🐛 故障排查

### 测试服务器无法启动

**问题**: 端口被占用

```bash
# 查看端口占用
lsof -i :8888
lsof -i :8080
lsof -i :3000

# 杀死占用进程
kill -9 <PID>
```

**问题**: Node.js 未安装

```bash
# 检查 Node.js
node --version

# macOS 安装
brew install node

# 或从官网下载
# https://nodejs.org/
```

**问题**: npm 依赖安装失败

```bash
# 清除缓存
npm cache clean --force

# 重新安装
rm -rf node_modules
npm install
```

### Swift 测试失败

**问题**: 无法连接测试服务器

- 确保测试服务器已启动
- 检查防火墙设置
- 确认端口配置正确

**问题**: 编译错误

```bash
# 清理构建
swift package clean

# 重新构建
swift build
```

**问题**: 测试超时

- 增加测试超时时间
- 检查网络连接
- 查看服务器日志

---

## 📖 文档导航

### 核心文档

- **README.md** - 项目介绍和快速开始
- **TESTING_PLAN.md** - 完整的测试方案 ⭐ 重要
- **ACTION_PLAN.md** - 下一步行动计划 ⭐ 重要
- **NEXT_STEPS.md** - 任务追踪

### 技术文档

- **SWIFT6_MIGRATION.md** - Swift 6 迁移指南
- **SWIFT6_MIGRATION_COMPLETE.md** - 迁移完成总结
- **UNIT_TESTS_FIX_SUMMARY.md** - 测试修复总结

### 示例代码

- **Examples/BasicTCP/** - TCP 基础示例
- **Examples/WebSocket/** - WebSocket 示例
- **TestServers/** - 测试服务器

---

## 🎯 下一步建议

### 立即执行 (今日)

1. ✅ 启动测试服务器
2. ✅ 运行现有测试
3. [ ] 手动测试服务器连接
4. [ ] 开始修复失败的测试

### 本周任务

1. [ ] 修复 BinaryProtocolAdapterTests
2. [ ] 修复 DataExtensionsTests
3. [ ] 完善 TCPConnectionTests
4. [ ] 实现 WebSocketTests

### 本月目标

1. [ ] 所有测试 100% 通过
2. [ ] 实现 Socket.IO 模块
3. [ ] 测试覆盖率 > 80%
4. [ ] 完成基础文档

---

## 🚀 运行示例

### 运行 TCP 示例

```bash
# 确保测试服务器运行中
swift run BasicTCPExample
```

### 运行 WebSocket 示例

```bash
swift run WebSocketExample
```

---

## 📞 获取帮助

### 查看日志

```bash
# 测试服务器日志
# 直接在启动终端查看

# Swift 测试日志
swift test 2>&1 | tee test.log
```

### 调试模式

```swift
// 在测试中启用详细日志
import Logging

LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardOutput(label: label)
    handler.logLevel = .trace
    return handler
}
```

### 报告问题

- 创建 GitHub Issue
- 提供完整的错误日志
- 说明重现步骤

---

**快速开始完成！🎉**

接下来查看 **TESTING_PLAN.md** 了解详细的测试架构。
