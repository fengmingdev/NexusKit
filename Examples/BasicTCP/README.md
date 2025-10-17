# NexusKit TCP 基础示例

这个示例展示了如何使用 NexusKit 的 TCP 功能。

## 📋 示例列表

### 1. 基础 TCP 连接
最简单的 TCP 连接示例，演示如何创建连接、发送数据和断开连接。

```swift
let connection = try await NexusKit.shared
    .tcp(host: "127.0.0.1", port: 8080)
    .id("basic-tcp")
    .timeout(30)
    .connect()
```

### 2. 二进制协议
使用二进制协议适配器，支持结构化消息和压缩。

```swift
let connection = try await NexusKit.shared
    .tcp(host: "127.0.0.1", port: 8080)
    .binaryProtocol(version: 1, compressionEnabled: true)
    .heartbeat(interval: 30, timeout: 90)
    .connect()
```

### 3. 自动重连
演示自动重连机制，支持多种重连策略。

```swift
.reconnection(ExponentialBackoffStrategy(
    maxAttempts: 5,
    initialInterval: 1.0,
    maxInterval: 30.0,
    multiplier: 2.0
))
```

### 4. 中间件
展示如何使用中间件进行日志记录和数据压缩。

```swift
.middlewares([
    LoggingMiddleware(),
    CompressionMiddleware()
])
```

### 5. TLS 加密
演示如何建立 TLS 加密连接。

```swift
.enableTLS() // 使用系统默认证书
```

### 6. 连接池管理
展示如何管理多个连接和查看统计信息。

```swift
let stats = await NexusKit.shared.statistics()
```

### 7. 聊天客户端
完整的聊天客户端实现，展示实际应用场景。

## 🚀 运行示例

### 方式 1: Swift Package Manager

```bash
# 1. 克隆仓库
git clone https://github.com/fengmingdev/NexusKit.git
cd NexusKit

# 2. 运行示例
swift run BasicTCPExample
```

### 方式 2: Xcode

1. 打开 `Package.swift` 文件
2. 在 Xcode 中选择 `BasicTCPExample` scheme
3. 点击运行

## 🧪 测试服务器

示例需要一个 TCP 测试服务器。你可以使用以下方式之一：

### 使用 netcat (简单测试)

```bash
# 启动一个简单的 TCP 服务器
nc -l 8080
```

### 使用 Node.js (完整功能)

```javascript
// server.js
const net = require('net');

const server = net.createServer((socket) => {
    console.log('客户端已连接');

    socket.on('data', (data) => {
        console.log('收到数据:', data.toString());
        // 回显数据
        socket.write(data);
    });

    socket.on('end', () => {
        console.log('客户端已断开');
    });
});

server.listen(8080, '127.0.0.1', () => {
    console.log('TCP 服务器运行在 127.0.0.1:8080');
});
```

运行服务器:
```bash
node server.js
```

## 📝 示例输出

运行示例程序后，你会看到类似以下输出：

```
🚀 NexusKit TCP 示例程序

==================================================

=== 示例 1：基础 TCP 连接 ===

✅ 连接成功！连接 ID: basic-tcp
📤 发送消息: Hello, Server!
👋 连接已断开

=== 示例 2：二进制协议 ===

✅ 连接成功（启用二进制协议和心跳）
📤 发送登录请求: username=admin
📥 收到响应: 128 字节
👋 连接已断开

...

✅ 所有示例运行完成！
```

## 🛠️ 自定义配置

### 修改服务器地址

编辑示例代码中的主机和端口：

```swift
.tcp(host: "your-server.com", port: 9000)
```

### 调整超时设置

```swift
.timeout(60) // 连接超时 60 秒
.readWriteTimeout(30) // 读写超时 30 秒
```

### 自定义协议

```swift
class MyProtocolAdapter: ProtocolAdapter {
    // 实现你的自定义协议
}

.protocol(MyProtocolAdapter())
```

## 📚 更多示例

- [WebSocket 示例](../WebSocket/)
- [Socket.IO 示例](../SocketIO/)
- [高级用法](../Advanced/)

## 🐛 故障排除

### 连接超时

如果遇到连接超时错误，检查：
1. 服务器是否正在运行
2. 主机地址和端口是否正确
3. 防火墙设置

### 编译错误

确保你的项目：
1. 使用 Swift 5.9+
2. 目标平台为 iOS 13+ 或 macOS 10.15+
3. 已正确导入 NexusKit 模块

## 💡 最佳实践

1. **错误处理**: 总是使用 `try-catch` 处理连接错误
2. **生命周期管理**: 使用 `LifecycleHooks` 监听连接状态
3. **资源释放**: 及时断开不需要的连接
4. **重连策略**: 根据场景选择合适的重连策略
5. **性能优化**: 大数据传输时启用压缩中间件

## 📄 许可证

MIT License - 详见 [LICENSE](../../LICENSE)
