# NexusKit

<p align="center">
  <img src="Documentation/Assets/logo.png" width="200" alt="NexusKit Logo">
</p>

<p align="center">
  <a href="https://github.com/yourorg/NexusKit/actions">
    <img src="https://github.com/yourorg/NexusKit/workflows/CI/badge.svg" alt="CI Status">
  </a>
  <a href="https://codecov.io/gh/yourorg/NexusKit">
    <img src="https://codecov.io/gh/yourorg/NexusKit/branch/main/graph/badge.svg" alt="Coverage">
  </a>
  <a href="https://swift.org">
    <img src="https://img.shields.io/badge/Swift-5.5+-orange.svg" alt="Swift 5.5+">
  </a>
  <a href="https://cocoapods.org/pods/NexusKit">
    <img src="https://img.shields.io/cocoapods/v/NexusKit.svg" alt="CocoaPods">
  </a>
  <a href="https://github.com/yourorg/NexusKit/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License">
  </a>
</p>

**The Modern Socket Framework for Swift**

NexusKit is a powerful, type-safe socket framework that brings modern Swift concurrency to network programming. Built with Swift 5.5+ features like async/await and AsyncStream, it provides a clean, intuitive API for TCP, WebSocket, and Socket.IO connections.

---

## ✨ Features

- 🚀 **Modern Swift** - Built with async/await, actors, and structured concurrency
- 🔒 **Type-Safe** - Leverages Swift generics and Codable for compile-time safety
- 🔌 **Multi-Protocol** - TCP, WebSocket, Socket.IO support out of the box
- 🛠 **Middleware System** - Extensible pipeline for compression, encryption, logging
- ♻️ **Auto-Reconnect** - Smart reconnection strategies with exponential backoff
- 🏊 **Connection Pooling** - Efficient resource management for multiple connections
- 📊 **Built-in Metrics** - Monitor performance and connection health
- 🔐 **TLS/SSL** - Secure connections with certificate validation
- 🌐 **Proxy Support** - SOCKS5 and HTTP CONNECT proxy support
- 📦 **Modular** - Use only what you need
- ⚡️ **High Performance** - Zero-copy buffers, os_unfair_lock, optimized for speed

---

## 📋 Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Xcode 14.0+
- Swift 5.5+

---

## 📦 Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/NexusKit.git", from: "1.0.0")
]

targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "NexusTCP", package: "NexusKit")
        ]
    )
]
```

### CocoaPods

Add to your `Podfile`:

```ruby
# TCP support
pod 'NexusKit/TCP'

# WebSocket support
pod 'NexusKit/WebSocket'

# Socket.IO support
pod 'NexusKit/IO'

# Everything
pod 'NexusKit/All'
```

Then run:

```bash
pod install
```

---

## 🚀 Quick Start

### Basic TCP Connection

```swift
import NexusTCP

// Create and connect
let connection = try await NexusKit.shared
    .connection(to: .tcp(host: "192.168.1.100", port: 8888))
    .heartbeat(interval: 30, timeout: 60)
    .reconnection(.exponentialBackoff(maxAttempts: 5))
    .connect()

// Send message with type safety
struct Message: Codable {
    let text: String
    let timestamp: Date
}

try await connection.send(Message(text: "Hello!", timestamp: Date()))

// Receive events
for await message: Message in connection.on("chat") {
    print("收到消息: \(message.text)")
}
```

### WebSocket

```swift
import NexusWebSocket

let ws = try await NexusKit.shared
    .connection(to: .webSocket(url: URL(string: "wss://example.com")!))
    .middleware(LoggingMiddleware(level: .debug))
    .connect()

// Subscribe to events
for await message: ChatMessage in ws.on("chat") {
    print("[\(message.from)]: \(message.content)")
}
```

### Socket.IO

```swift
import NexusIO

let io = try await NexusKit.shared
    .connection(to: .socketIO(url: URL(string: "https://chat.example.com")!))
    .connect()

// Request-Response pattern
let response: LoginResponse = try await io.request(
    LoginRequest(username: "user", password: "pass"),
    timeout: 10
)

print("登录成功，token: \(response.token)")
```

### Advanced Features

```swift
// Connection pooling
let pool = ConnectionPool(configuration: .init(
    maxConnections: 10,
    minIdleConnections: 2
))

let connection = try await pool.acquire()
try await connection.send(message)
pool.release(connection)

// Custom middleware
class AuthMiddleware: Middleware {
    func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        var mutableData = data
        mutableData.insert(contentsOf: authToken.utf8, at: 0)
        return mutableData
    }
}

let connection = try await NexusKit.shared
    .connection(to: endpoint)
    .middleware(AuthMiddleware())
    .middleware(CompressionMiddleware())
    .middleware(EncryptionMiddleware(key: encryptionKey))
    .connect()

// Monitor metrics
let metricsMiddleware = MetricsMiddleware()

let connection = try await NexusKit.shared
    .connection(to: endpoint)
    .middleware(metricsMiddleware)
    .connect()

print("发送: \(metricsMiddleware.metrics.totalBytesSent) bytes")
print("接收: \(metricsMiddleware.metrics.totalBytesReceived) bytes")
```

---

## 📚 Documentation

- **[Getting Started Guide](Documentation/Guides/GettingStarted.md)** - 快速开始
- **[API Reference](https://yourorg.github.io/NexusKit)** - 完整 API 文档
- **[Custom Protocols](Documentation/Protocols/CustomProtocol.md)** - 自定义协议开发
- **[Middleware Guide](Documentation/Middleware/MiddlewareDevelopment.md)** - 中间件开发指南
- **[Architecture Overview](Documentation/Architecture/Overview.md)** - 架构概览
- **[Migration Guide](Documentation/Guides/Migration.md)** - 从其他库迁移

---

## 🏗 Architecture

NexusKit 采用分层、模块化架构：

```
┌─────────────────────────────────────────────┐
│              Application Layer               │
│           (Your Swift Code)                 │
└──────────────────┬──────────────────────────┘
                   │
    ┌──────────────┼──────────────┬──────────┐
    ▼              ▼              ▼          ▼
┌─────────┐  ┌──────────┐  ┌────────┐  ┌────────┐
│ TCP     │  │WebSocket │  │Socket.IO│  │ Secure │
└────┬────┘  └─────┬────┘  └────┬───┘  └───┬────┘
     │             │             │          │
     └─────────────┴─────────────┴──────────┘
                   │
                   ▼
          ┌────────────────┐
          │   NexusCore    │ ◄─── Middlewares
          │ (Core Layer)   │
          └────────────────┘
```

核心特性：

- **协议导向设计** - 易于扩展和测试
- **中间件管道** - 灵活的数据处理链
- **零拷贝优化** - 高性能缓冲区处理
- **Actor 隔离** - 线程安全保证
- **结构化并发** - 现代 Swift 并发模型

---

## 🎯 Roadmap

### v0.1.0 (已完成 ✅)
- ✅ Core architecture
- ✅ TCP protocol support (基于 Network framework)
- ✅ 完整的中间件系统
- ✅ 4 个生产级中间件（日志、压缩、加密、监控）
- ✅ Auto-reconnection (4种策略)
- ✅ 高性能工具（UnfairLock、Atomic）

### v0.2.0 (当前版本 ✅)
- ✅ WebSocket support (完成)
- ✅ NexusCore 单元测试 (6个测试文件，1800+ 行)
- ✅ GitHub Actions CI/CD
- ✅ 贡献指南 (CONTRIBUTING.md)
- 🔲 Socket.IO full support
- 🔲 集成测试

### v0.3.0 (计划中 📅)
- 🔲 Connection pooling
- 🔲 Advanced security module
- 🔲 Performance benchmarks
- 🔲 更多协议支持（MQTT、gRPC）

### v1.0.0 (目标 🎯)
- 🔲 生产级稳定性
- 🔲 完整文档
- 🔲 CI/CD
- 🔲 正式发布

详细路线图请查看 [ROADMAP.md](ROADMAP.md)

---

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/yourorg/NexusKit.git
cd NexusKit

# Run tests
swift test

# Generate documentation
./Scripts/generate-docs.sh

# Run linter
./Scripts/lint.sh
```

---

## 📄 License

NexusKit is released under the MIT license. See [LICENSE](LICENSE) for details.

---

## 🙏 Credits

NexusKit is inspired by excellent projects in the Swift community:

- [Socket.IO](https://socket.io) - Real-time communication
- [Starscream](https://github.com/daltoniam/Starscream) - WebSocket implementation
- [Alamofire](https://github.com/Alamofire/Alamofire) - API design patterns
- [Moya](https://github.com/Moya/Moya) - Network abstraction

Special thanks to all [contributors](https://github.com/yourorg/NexusKit/graphs/contributors)!

---

## 📞 Contact

- **Issues**: [GitHub Issues](https://github.com/yourorg/NexusKit/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourorg/NexusKit/discussions)
- **Twitter**: [@NexusKit](https://twitter.com/nexuskit)

---

<p align="center">Made with ❤️ by the Swift Community</p>
