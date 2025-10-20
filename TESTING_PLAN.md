# NexusKit 单元测试与调试方案

**创建日期**: 2025-10-20  
**状态**: 待执行  
**目标**: 建立完善的测试体系，确保所有功能经过严格测试

---

## 📋 目录

1. [测试环境准备](#1-测试环境准备)
2. [测试服务器搭建](#2-测试服务器搭建)
3. [单元测试架构](#3-单元测试架构)
4. [测试执行方案](#4-测试执行方案)
5. [调试工具配置](#5-调试工具配置)
6. [持续集成配置](#6-持续集成配置)

---

## 1. 测试环境准备

### 1.1 本地环境要求

```bash
# 已安装
✅ Node.js (用于测试服务器)
✅ Swift 5.7+
✅ Xcode 14.0+

# 需要安装
npm install -g socket.io  # Socket.IO 测试服务器
npm install -g ws         # WebSocket 测试服务器
```

### 1.2 Swift Package Manager 配置

确保 `Package.swift` 包含测试依赖：

```swift
// 测试依赖
.package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),

// 测试目标配置
.testTarget(
    name: "NexusCoreTests",
    dependencies: ["NexusCore"],
    resources: [
        .copy("Resources/test_data.json")
    ]
)
```

---

## 2. 测试服务器搭建

### 2.1 Node.js TCP 测试服务器

创建文件 `TestServers/tcp_server.js`:

```javascript
const net = require('net');

// 配置
const PORT = 8888;
const HOST = '127.0.0.1';

// 创建服务器
const server = net.createServer((socket) => {
    console.log(`[TCP] 客户端连接: ${socket.remoteAddress}:${socket.remotePort}`);

    // 心跳计数
    let heartbeatCount = 0;

    // 接收数据
    socket.on('data', (data) => {
        console.log(`[TCP] 收到数据 (${data.length} bytes):`, data.toString('hex'));

        // 解析二进制协议头 (NexusKit BinaryProtocol)
        if (data.length >= 8) {
            const version = data.readUInt8(0);
            const type = data.readUInt8(1);
            const flags = data.readUInt8(2);
            const reserved = data.readUInt8(3);
            const payloadLength = data.readUInt32BE(4);

            console.log(`  版本: ${version}, 类型: ${type}, 标志: ${flags}, 载荷长度: ${payloadLength}`);

            // 心跳响应
            if (type === 0x03) { // Heartbeat
                heartbeatCount++;
                console.log(`  心跳 #${heartbeatCount}`);
                socket.write(data); // 回显
                return;
            }

            // 普通消息回显
            if (type === 0x01) { // Data
                const payload = data.slice(8);
                console.log(`  载荷: ${payload.toString('utf8')}`);
                
                // 构造响应
                const response = Buffer.concat([
                    data.slice(0, 8), // 复用请求头
                    Buffer.from('Server received: '),
                    payload
                ]);
                socket.write(response);
            }
        }
    });

    // 连接关闭
    socket.on('end', () => {
        console.log('[TCP] 客户端断开连接');
    });

    // 错误处理
    socket.on('error', (err) => {
        console.error('[TCP] 错误:', err.message);
    });

    // 发送欢迎消息
    const welcome = createBinaryMessage('Welcome to NexusKit Test Server!');
    socket.write(welcome);
});

// 启动服务器
server.listen(PORT, HOST, () => {
    console.log(`[TCP] 服务器启动在 ${HOST}:${PORT}`);
});

// 构造二进制消息
function createBinaryMessage(text) {
    const payload = Buffer.from(text, 'utf8');
    const header = Buffer.alloc(8);
    header.writeUInt8(1, 0);              // version
    header.writeUInt8(0x01, 1);           // type: Data
    header.writeUInt8(0x00, 2);           // flags
    header.writeUInt8(0x00, 3);           // reserved
    header.writeUInt32BE(payload.length, 4); // payload length
    return Buffer.concat([header, payload]);
}

// 优雅关闭
process.on('SIGINT', () => {
    console.log('\n[TCP] 服务器关闭中...');
    server.close(() => {
        console.log('[TCP] 服务器已关闭');
        process.exit(0);
    });
});
```

### 2.2 WebSocket 测试服务器

创建文件 `TestServers/websocket_server.js`:

```javascript
const WebSocket = require('ws');

const PORT = 8080;
const wss = new WebSocket.Server({ port: PORT });

console.log(`[WebSocket] 服务器启动在 ws://localhost:${PORT}`);

wss.on('connection', (ws, req) => {
    console.log(`[WebSocket] 新连接来自: ${req.socket.remoteAddress}`);

    // 发送欢迎消息
    ws.send(JSON.stringify({
        type: 'welcome',
        message: 'Connected to NexusKit WebSocket Test Server',
        timestamp: Date.now()
    }));

    // 接收消息
    ws.on('message', (data) => {
        console.log('[WebSocket] 收到消息:', data.toString());

        try {
            const message = JSON.parse(data.toString());

            // 心跳响应
            if (message.type === 'ping') {
                ws.send(JSON.stringify({
                    type: 'pong',
                    timestamp: Date.now()
                }));
                return;
            }

            // 回显消息
            ws.send(JSON.stringify({
                type: 'echo',
                originalMessage: message,
                timestamp: Date.now()
            }));
        } catch (e) {
            console.error('[WebSocket] 解析错误:', e.message);
        }
    });

    // 连接关闭
    ws.on('close', () => {
        console.log('[WebSocket] 连接关闭');
    });

    // 错误处理
    ws.on('error', (err) => {
        console.error('[WebSocket] 错误:', err.message);
    });

    // 定期心跳
    const heartbeat = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({
                type: 'server_heartbeat',
                timestamp: Date.now()
            }));
        }
    }, 30000); // 30秒

    ws.on('close', () => clearInterval(heartbeat));
});
```

### 2.3 Socket.IO 测试服务器

创建文件 `TestServers/socketio_server.js`:

```javascript
const { Server } = require('socket.io');

const PORT = 3000;
const io = new Server(PORT, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

console.log(`[Socket.IO] 服务器启动在 http://localhost:${PORT}`);

io.on('connection', (socket) => {
    console.log(`[Socket.IO] 客户端连接: ${socket.id}`);

    // 欢迎消息
    socket.emit('welcome', {
        message: 'Connected to Socket.IO Test Server',
        clientId: socket.id,
        timestamp: Date.now()
    });

    // 聊天消息
    socket.on('chat', (data) => {
        console.log('[Socket.IO] 聊天消息:', data);
        io.emit('chat', {
            from: socket.id,
            message: data.message,
            timestamp: Date.now()
        });
    });

    // 请求-响应模式
    socket.on('request', (data, callback) => {
        console.log('[Socket.IO] 收到请求:', data);
        callback({
            success: true,
            data: { echo: data },
            timestamp: Date.now()
        });
    });

    // 命名空间
    socket.on('join_room', (room) => {
        socket.join(room);
        console.log(`[Socket.IO] ${socket.id} 加入房间: ${room}`);
        socket.to(room).emit('user_joined', {
            userId: socket.id,
            room: room
        });
    });

    // 断开连接
    socket.on('disconnect', (reason) => {
        console.log(`[Socket.IO] 客户端断开: ${socket.id}, 原因: ${reason}`);
    });

    // 自定义事件
    socket.on('custom_event', (data) => {
        console.log('[Socket.IO] 自定义事件:', data);
        socket.emit('custom_response', { received: true, data });
    });
});
```

### 2.4 测试服务器管理脚本

创建 `TestServers/package.json`:

```json
{
  "name": "nexuskit-test-servers",
  "version": "1.0.0",
  "description": "Test servers for NexusKit",
  "scripts": {
    "tcp": "node tcp_server.js",
    "ws": "node websocket_server.js",
    "io": "node socketio_server.js",
    "all": "concurrently \"npm run tcp\" \"npm run ws\" \"npm run io\"",
    "test": "npm run all"
  },
  "dependencies": {
    "socket.io": "^4.5.0",
    "ws": "^8.13.0"
  },
  "devDependencies": {
    "concurrently": "^8.0.0"
  }
}
```

创建启动脚本 `TestServers/start_all.sh`:

```bash
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
npm run all
```

---

## 3. 单元测试架构

### 3.1 测试分类

```
Tests/
├── NexusCoreTests/              # 核心功能测试
│   ├── ConnectionStateTests     ✅ 已完成
│   ├── DataExtensionsTests      ⚠️  待修复
│   ├── LockTests                ✅ 已完成
│   ├── MiddlewareTests          ✅ 已完成
│   ├── NexusErrorTests          ✅ 已完成
│   └── ReconnectionStrategyTests ✅ 已完成
│
├── NexusTCPTests/               # TCP 模块测试
│   ├── BinaryProtocolAdapterTests ⚠️ 待修复 (3/23)
│   └── TCPConnectionTests        ✅ 基本完成 (18/22)
│
├── NexusWebSocketTests/         # WebSocket 测试 (待实现)
│   ├── WebSocketConnectionTests
│   ├── WebSocketFrameTests
│   └── WebSocketProtocolTests
│
├── NexusIOTests/                # Socket.IO 测试 (待实现)
│   ├── SocketIOConnectionTests
│   ├── SocketIOEventsTests
│   └── SocketIONamespaceTests
│
├── MiddlewareTests/             # 中间件测试 (待扩展)
│   ├── CompressionMiddlewareTests
│   ├── EncryptionMiddlewareTests
│   ├── LoggingMiddlewareTests
│   └── MetricsMiddlewareTests
│
└── IntegrationTests/            # 集成测试 (待实现)
    ├── TCPIntegrationTests
    ├── WebSocketIntegrationTests
    ├── SocketIOIntegrationTests
    └── EndToEndTests
```

### 3.2 测试优先级

#### P0 - 立即处理 (本周)

1. **修复 BinaryProtocolAdapterTests** (20/23 失败)
   - 调试协议编解码逻辑
   - 修复压缩标志位
   - 验证协议头格式

2. **修复 DataExtensionsTests** (压缩功能)
   - GZIP 压缩/解压缩
   - 边界情况测试

3. **完善 TCPConnectionTests** (4/22 失败)
   - 修复生命周期钩子测试
   - 修复错误处理测试

#### P1 - 高优先级 (本月)

4. **WebSocket 单元测试** (0%)
   ```swift
   // Tests/NexusWebSocketTests/WebSocketConnectionTests.swift
   - testBasicConnection
   - testPingPong
   - testTextMessages
   - testBinaryMessages
   - testFragmentation
   - testCloseHandshake
   ```

5. **Socket.IO 单元测试** (0%)
   ```swift
   // Tests/NexusIOTests/SocketIOConnectionTests.swift
   - testConnection
   - testEventEmit
   - testEventOn
   - testAcknowledgement
   - testNamespaces
   - testRooms
   ```

6. **中间件单元测试** (0%)
   ```swift
   // Tests/MiddlewareTests/
   - CompressionMiddlewareTests
   - EncryptionMiddlewareTests
   - LoggingMiddlewareTests
   - MetricsMiddlewareTests
   ```

#### P2 - 中优先级 (下月)

7. **集成测试** (0%)
   - TCP 端到端测试
   - WebSocket 端到端测试
   - Socket.IO 端到端测试
   - 多连接并发测试

8. **性能测试** (0%)
   - 吞吐量测试
   - 延迟测试
   - 内存占用测试
   - CPU 使用测试

### 3.3 测试辅助工具

创建 `Tests/TestUtilities/`:

```swift
// Tests/TestUtilities/MockConnection.swift
import NexusCore

final class MockConnection: Connection {
    var state: ConnectionState = .disconnected(.userInitiated)
    var isConnected: Bool { state.isConnected }
    
    private(set) var sentMessages: [Data] = []
    var shouldFailOnSend = false
    
    func connect() async throws {
        state = .connecting
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        state = .connected
    }
    
    func disconnect(reason: DisconnectReason) async {
        state = .disconnected(reason)
    }
    
    func send(_ data: Data) async throws {
        guard isConnected else {
            throw NexusError.connectionError(.notConnected)
        }
        if shouldFailOnSend {
            throw NexusError.sendError(.encodingFailed)
        }
        sentMessages.append(data)
    }
    
    func on<T: Decodable>(_ event: String) -> AsyncStream<T> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
```

```swift
// Tests/TestUtilities/TestServer.swift
import Foundation
import Network

/// 测试用 TCP 服务器
actor TestTCPServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    
    let port: UInt16
    private(set) var isRunning = false
    
    init(port: UInt16 = 0) {
        self.port = port
    }
    
    func start() async throws {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
        
        listener?.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleStateChange(state) }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleNewConnection(connection) }
        }
        
        listener?.start(queue: .global())
        isRunning = true
    }
    
    func stop() async {
        listener?.cancel()
        for conn in connections {
            conn.cancel()
        }
        connections.removeAll()
        isRunning = false
    }
    
    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("测试服务器就绪")
        case .failed(let error):
            print("测试服务器失败: \(error)")
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .global())
        receiveData(on: connection)
    }
    
    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            if let data = data, !data.isEmpty {
                // 回显数据
                connection.send(content: data, completion: .idempotent)
                self?.receiveData(on: connection)
            }
        }
    }
}
```

---

## 4. 测试执行方案

### 4.1 命令行测试

```bash
# 运行所有测试
swift test

# 运行特定模块测试
swift test --filter NexusCoreTests
swift test --filter NexusTCPTests

# 运行特定测试
swift test --filter testBasicConnection

# 并行测试
swift test --parallel

# 生成代码覆盖率
swift test --enable-code-coverage

# 查看覆盖率报告
xcrun llvm-cov report \
    .build/debug/NexusKitPackageTests.xctest/Contents/MacOS/NexusKitPackageTests \
    -instr-profile .build/debug/codecov/default.profdata
```

### 4.2 Xcode 测试

```bash
# 生成 Xcode 项目
swift package generate-xcodeproj

# 或者直接在 Xcode 中打开
open Package.swift
```

在 Xcode 中：
1. `Cmd + U` - 运行所有测试
2. `Cmd + Ctrl + U` - 运行单个测试
3. 点击行号左侧的菱形图标运行特定测试

### 4.3 自动化测试脚本

创建 `Scripts/run_tests.sh`:

```bash
#!/bin/bash

# NexusKit 自动化测试脚本

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🧪 NexusKit 测试套件"
echo "===================="

# 1. 启动测试服务器
echo -e "${YELLOW}📡 启动测试服务器...${NC}"
cd TestServers
npm install > /dev/null 2>&1
npm run all &
SERVER_PID=$!
cd ..

# 等待服务器启动
sleep 3

# 2. 清理构建
echo -e "${YELLOW}🧹 清理构建...${NC}"
swift package clean

# 3. 运行测试
echo -e "${YELLOW}🧪 运行单元测试...${NC}"
if swift test --enable-code-coverage; then
    echo -e "${GREEN}✅ 所有测试通过${NC}"
else
    echo -e "${RED}❌ 测试失败${NC}"
    kill $SERVER_PID
    exit 1
fi

# 4. 生成覆盖率报告
echo -e "${YELLOW}📊 生成覆盖率报告...${NC}"
swift test --enable-code-coverage > /dev/null 2>&1

# 5. 关闭测试服务器
echo -e "${YELLOW}🛑 关闭测试服务器...${NC}"
kill $SERVER_PID

echo -e "${GREEN}🎉 测试完成！${NC}"
```

### 4.4 测试计划

创建 `.xctestplan` 文件以配置测试：

```json
{
  "configurations": [
    {
      "id": "Debug",
      "name": "Debug Configuration",
      "options": {
        "codeCoverage": {
          "targets": [
            { "containerPath": "container:NexusKit", "identifier": "NexusCore" },
            { "containerPath": "container:NexusKit", "identifier": "NexusTCP" },
            { "containerPath": "container:NexusKit", "identifier": "NexusWebSocket" }
          ]
        },
        "environmentVariableEntries": [
          {
            "key": "TEST_SERVER_HOST",
            "value": "127.0.0.1"
          },
          {
            "key": "TEST_SERVER_TCP_PORT",
            "value": "8888"
          },
          {
            "key": "TEST_SERVER_WS_PORT",
            "value": "8080"
          }
        ]
      }
    }
  ],
  "defaultOptions": {
    "codeCoverage": true,
    "testTimeoutsEnabled": true
  },
  "testTargets": [
    {
      "target": {
        "containerPath": "container:NexusKit",
        "identifier": "NexusCoreTests"
      }
    },
    {
      "target": {
        "containerPath": "container:NexusKit",
        "identifier": "NexusTCPTests"
      }
    }
  ],
  "version": 1
}
```

---

## 5. 调试工具配置

### 5.1 日志配置

在测试中启用详细日志：

```swift
// Tests/TestUtilities/TestLogger.swift
import Logging

func setupTestLogger(level: Logger.Level = .debug) {
    LoggingSystem.bootstrap { label in
        var handler = StreamLogHandler.standardOutput(label: label)
        handler.logLevel = level
        return handler
    }
}
```

在测试中使用：

```swift
class MyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setupTestLogger(level: .trace)
    }
}
```

### 5.2 网络抓包

使用 Wireshark 或 tcpdump 抓包分析：

```bash
# 抓取本地回环接口的流量
sudo tcpdump -i lo0 -w nexuskit_traffic.pcap port 8888

# 或使用 Wireshark GUI
# 过滤器: tcp.port == 8888 || tcp.port == 8080
```

### 5.3 性能分析

使用 Instruments 进行性能分析：

```bash
# 生成 Instruments 可用的 trace 文件
xcodebuild test \
    -scheme NexusKit \
    -enableCodeCoverage YES \
    -enablePerformanceTestsDiagnostics YES \
    -resultBundlePath TestResults
```

---

## 6. 持续集成配置

### 6.1 GitHub Actions

已有配置：`.github/workflows/ci.yml`

增强版本：

```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    name: Test on ${{ matrix.os }}
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [macos-13, macos-14]
        swift: [5.7, 5.8, 5.9]
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Swift
      uses: swift-actions/setup-swift@v1
      with:
        swift-version: ${{ matrix.swift }}
    
    - name: Setup Node.js
      uses: actions/setup-node@v3
      with:
        node-version: '18'
    
    - name: Install test server dependencies
      run: |
        cd TestServers
        npm install
    
    - name: Start test servers
      run: |
        cd TestServers
        npm run all &
        sleep 5
    
    - name: Run tests
      run: swift test --enable-code-coverage
    
    - name: Generate coverage report
      run: |
        xcrun llvm-cov export -format="lcov" \
          .build/debug/NexusKitPackageTests.xctest/Contents/MacOS/NexusKitPackageTests \
          -instr-profile .build/debug/codecov/default.profdata > coverage.lcov
    
    - name: Upload coverage to Codecov
      uses: codecov/codecov-action@v3
      with:
        files: ./coverage.lcov
        fail_ci_if_error: true
```

### 6.2 本地 Pre-commit Hook

创建 `.git/hooks/pre-commit`:

```bash
#!/bin/bash

echo "运行测试..."
swift test --filter NexusCoreTests

if [ $? -ne 0 ]; then
    echo "❌ 测试失败，提交已取消"
    exit 1
fi

echo "✅ 测试通过"
exit 0
```

---

## 7. 测试覆盖率目标

### 7.1 当前覆盖率

| 模块 | 覆盖率 | 目标 | 状态 |
|------|--------|------|------|
| NexusCore | ~60% | 80% | 🟡 |
| NexusTCP | ~40% | 80% | 🔴 |
| NexusWebSocket | 0% | 80% | 🔴 |
| NexusIO | 0% | 80% | 🔴 |

### 7.2 提升计划

1. **Week 1**: 修复现有测试，NexusCore 达到 80%
2. **Week 2**: NexusTCP 测试完善，达到 80%
3. **Week 3**: WebSocket 测试实现，达到 60%
4. **Week 4**: Socket.IO 测试实现，达到 60%

---

## 8. 下一步行动计划

### 立即执行 (今日)

- [ ] 创建 `TestServers/` 目录
- [ ] 实现 3 个测试服务器（TCP, WebSocket, Socket.IO）
- [ ] 创建 `start_all.sh` 脚本
- [ ] 测试服务器是否正常运行

### 本周任务

- [ ] 修复 `BinaryProtocolAdapterTests` (P0)
- [ ] 修复 `DataExtensionsTests` 压缩功能 (P0)
- [ ] 完善 `TCPConnectionTests` 生命周期测试 (P0)
- [ ] 创建 `TestUtilities` 模块
- [ ] 实现 Mock 对象和测试服务器

### 下周任务

- [ ] 实现 `WebSocketConnectionTests`
- [ ] 实现 `SocketIOConnectionTests`
- [ ] 创建集成测试框架
- [ ] 设置 CI/CD 自动化

---

## 附录

### A. 测试命名规范

```swift
// ✅ 好的测试名称
func testConnectionSucceedsWithValidEndpoint()
func testSendFailsWhenDisconnected()
func testHeartbeatTriggersAfterInterval()

// ❌ 不好的测试名称
func test1()
func testConnection()
func testStuff()
```

### B. 断言最佳实践

```swift
// ✅ 使用具体断言
XCTAssertEqual(connection.state, .connected)
XCTAssertTrue(connection.isConnected)
XCTAssertNotNil(receivedData)

// ✅ 提供失败消息
XCTAssertEqual(
    connection.state, 
    .connected,
    "连接应该在成功建立后进入 connected 状态"
)

// ✅ 异步测试
let expectation = expectation(description: "receive message")
Task {
    let message = await connection.receive()
    XCTAssertNotNil(message)
    expectation.fulfill()
}
await fulfillment(of: [expectation], timeout: 5.0)
```

### C. 常见问题排查

1. **测试服务器连接失败**
   - 检查端口是否被占用：`lsof -i :8888`
   - 检查防火墙设置
   - 确认服务器已启动：`ps aux | grep node`

2. **测试超时**
   - 增加超时时间
   - 检查异步任务是否正确 await
   - 使用 `Task.sleep` 增加等待时间

3. **内存泄漏**
   - 使用 Xcode Memory Graph 检测
   - 确保 async 闭包使用 `[weak self]`
   - 检查 actor 循环引用

---

**维护者**: NexusKit Team  
**最后更新**: 2025-10-20
