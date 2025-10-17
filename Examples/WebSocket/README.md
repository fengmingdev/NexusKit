# NexusKit WebSocket 示例

这个示例展示了如何使用 NexusKit 的 WebSocket 功能。

## 📋 示例列表

### 1. 基础 WebSocket 连接
最简单的 WebSocket 连接示例，演示连接、发送文本消息和断开。

```swift
let connection = try await NexusKit.shared
    .webSocket(url: URL(string: "wss://echo.websocket.org")!)
    .connect()

try await connection.sendText("Hello, WebSocket!")
```

### 2. 聊天应用
完整的 WebSocket 聊天客户端实现。

```swift
class WebSocketChatClient {
    func connect(url: URL) async throws {
        connection = try await NexusKit.shared
            .webSocket(url: url)
            .pingInterval(30)
            .reconnection(ExponentialBackoffStrategy())
            .connect()
    }
}
```

### 3. JSON 协议
使用 JSON 协议适配器发送和接收结构化消息。

```swift
struct ChatMessage: Codable {
    let type: String
    let user: String
    let message: String
}

let connection = try await NexusKit.shared
    .webSocket(url: url)
    .protocol(JSONWebSocketAdapter())
    .connect()
```

### 4. 自定义头部和子协议
演示如何添加自定义 HTTP 头和 WebSocket 子协议。

```swift
.headers([
    "Authorization": "Bearer token",
    "X-Client-Version": "1.0.0"
])
.protocols(["chat", "superchat"])
```

### 5. 实时数据流
展示如何处理实时数据流，带日志和性能监控。

```swift
.middleware(PrintLoggingMiddleware())
.middleware(MetricsMiddleware(reportInterval: 5))
```

### 6. 错误处理和重连
完整的错误处理和自动重连示例。

```swift
.reconnection(ExponentialBackoffStrategy(
    maxAttempts: 3,
    initialInterval: 1.0,
    maxInterval: 10.0
))
.hooks(LifecycleHooks(
    onReconnecting: { attempt in
        print("正在重连... 第 \(attempt) 次")
    }
))
```

## 🚀 运行示例

### 方式 1: Swift Package Manager

```bash
# 1. 克隆仓库
git clone https://github.com/fengmingdev/NexusKit.git
cd NexusKit

# 2. 运行示例
swift run WebSocketExample
```

### 方式 2: Xcode

1. 打开 `Package.swift` 文件
2. 在 Xcode 中选择 `WebSocketExample` scheme
3. 点击运行

## 🧪 测试服务器

示例使用以下 WebSocket 测试服务器：

### 1. WebSocket Echo Server
```
wss://echo.websocket.org
```
- 功能：回显所有发送的消息
- 适合：基础测试

### 2. 自建服务器（Node.js）

```javascript
// server.js
const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8080 });

wss.on('connection', (ws) => {
    console.log('客户端已连接');

    ws.on('message', (message) => {
        console.log('收到:', message);
        // 回显消息
        ws.send(message);
    });

    ws.on('close', () => {
        console.log('客户端已断开');
    });
});

console.log('WebSocket 服务器运行在 ws://localhost:8080');
```

运行:
```bash
npm install ws
node server.js
```

### 3. Python 服务器

```python
# server.py
import asyncio
import websockets

async def echo(websocket, path):
    async for message in websocket:
        print(f"收到: {message}")
        await websocket.send(message)

start_server = websockets.serve(echo, "localhost", 8080)

asyncio.get_event_loop().run_until_complete(start_server)
print("WebSocket 服务器运行在 ws://localhost:8080")
asyncio.get_event_loop().run_forever()
```

运行:
```bash
pip install websockets
python server.py
```

## 📝 示例输出

运行示例程序后，你会看到类似以下输出：

```
🚀 NexusKit WebSocket 示例程序

==================================================

=== 示例 1：基础 WebSocket 连接 ===

✅ WebSocket 连接成功！
📤 发送: Hello, WebSocket!
📥 收到回显: Hello, WebSocket!
👋 连接已断开

=== 示例 2：WebSocket 聊天应用 ===

🔗 Alice 正在连接...
✅ Alice 已连接
🔗 Bob 正在连接...
✅ Bob 已连接
📤 Alice: Hi Bob!
📤 Bob: Hello Alice!
📥 收到消息: Hi Bob!
📥 收到消息: Hello Alice!
👋 Alice 已断开
👋 Bob 已断开

...

✅ 所有示例运行完成！
```

## 🛠️ 自定义配置

### 修改服务器 URL

编辑示例代码中的 URL：

```swift
.webSocket(url: URL(string: "wss://your-server.com/ws")!)
```

### 调整 Ping 间隔

```swift
.pingInterval(60) // 60 秒
```

### 自定义协议适配器

```swift
struct MyProtocolAdapter: ProtocolAdapter {
    // 实现你的自定义协议
}

.protocol(MyProtocolAdapter())
```

## 🌟 高级用法

### 1. 多连接管理

```swift
let connection1 = try await NexusKit.shared
    .webSocket(url: url1)
    .id("ws-1")
    .connect()

let connection2 = try await NexusKit.shared
    .webSocket(url: url2)
    .id("ws-2")
    .connect()

// 获取所有连接
let active = await NexusKit.shared.activeConnections()
```

### 2. 二进制数据

```swift
// 发送二进制
let binaryData = Data([0x01, 0x02, 0x03, 0x04])
try await connection.send(binaryData, timeout: 5)

// 接收二进制
await connection.on(.message) { data in
    print("收到二进制: \(data.hexString)")
}
```

### 3. 子协议协商

```swift
.protocols(["v1.chat", "v2.chat"])
// 服务器会选择一个支持的协议
```

## 📚 更多示例

- [TCP 示例](../BasicTCP/)
- [Socket.IO 示例](../SocketIO/)
- [高级用法](../Advanced/)

## 🐛 故障排除

### 连接超时

如果遇到连接超时：
1. 检查服务器是否运行
2. 验证 URL 是否正确
3. 检查防火墙设置
4. 增加超时时间: `.timeout(60)`

### SSL/TLS 错误

对于 wss:// 连接：
1. 确保服务器证书有效
2. 开发环境可以临时禁用证书验证（不推荐生产环境）

### 消息丢失

1. 检查网络连接
2. 启用日志中间件查看详情
3. 使用性能监控中间件检查吞吐量

## 💡 最佳实践

1. **错误处理**: 总是使用 `try-catch` 处理连接错误
2. **生命周期管理**: 使用 `LifecycleHooks` 监听连接状态
3. **资源释放**: 及时断开不需要的连接
4. **重连策略**: 根据场景选择合适的重连策略
5. **Ping/Pong**: 保持合理的 Ping 间隔（30-60秒）

## 📄 许可证

MIT License - 详见 [LICENSE](../../LICENSE)
