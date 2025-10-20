# 自定义协议开发指南

## 目录

1. [概述](#概述)
2. [协议抽象层](#协议抽象层)
3. [实现自定义协议](#实现自定义协议)
4. [示例协议](#示例协议)
5. [最佳实践](#最佳实践)
6. [性能优化](#性能优化)
7. [常见问题](#常见问题)

---

## 概述

NexusKit 提供了强大的协议抽象层，允许开发者在 TCP/TLS 基础上实现自定义应用层协议。无论是实现标准协议（如 MQTT、Redis、gRPC）还是自定义二进制/文本协议，都可以使用统一的 API。

### 核心优势

- ✅ **统一抽象**: 标准化的协议接口
- ✅ **状态管理**: 内置协议状态和上下文
- ✅ **消息处理**: 自动消息解析和分发
- ✅ **零拷贝**: 支持高性能零拷贝传输
- ✅ **Actor安全**: 完全并发安全
- ✅ **可扩展**: 易于添加新协议

---

## 协议抽象层

### 核心协议 (Protocols)

#### 1. ProtocolHandler

```swift
public protocol ProtocolHandler: Sendable {
    /// 协议名称
    var protocolName: String { get }

    /// 协议版本
    var protocolVersion: String { get }

    /// 连接建立时调用
    func onConnect(context: ProtocolContext) async throws

    /// 连接断开时调用
    func onDisconnect(context: ProtocolContext) async

    /// 接收到原始数据时调用
    func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage]

    /// 编码消息为原始数据
    func encodeMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws -> Data

    /// 处理接收到的消息
    func handleMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws
}
```

#### 2. ProtocolMessage

```swift
public protocol ProtocolMessage: Sendable {
    /// 消息类型标识
    var messageType: String { get }

    /// 消息负载
    var payload: Data { get }

    /// 消息元数据
    var metadata: [String: String] { get }
}
```

#### 3. ProtocolContext

```swift
public protocol ProtocolContext: Sendable {
    /// 连接状态
    var isConnected: Bool { get async }

    /// 发送原始数据
    func send(_ data: Data) async throws

    /// 接收原始数据
    func receive(timeout: TimeInterval?) async throws -> Data

    /// 存储协议特定状态
    func setState<T: Sendable>(_ value: T, forKey key: String) async

    /// 获取协议特定状态
    func getState<T: Sendable>(forKey key: String) async -> T?

    /// 关闭连接
    func close() async
}
```

---

## 实现自定义协议

### 步骤 1: 定义消息类型

```swift
public enum MyProtocolMessageType: UInt8 {
    case handshake = 0x01
    case data = 0x02
    case ack = 0x03
    case ping = 0x10
    case pong = 0x11
}
```

### 步骤 2: 实现 ProtocolMessage

```swift
public struct MyProtocolMessage: ProtocolMessage {
    public let messageType: String
    public let payload: Data
    public let metadata: [String: String]

    public let type: MyProtocolMessageType

    public init(type: MyProtocolMessageType, payload: Data = Data(), metadata: [String: String] = [:]) {
        self.type = type
        self.messageType = String(describing: type)
        self.payload = payload
        self.metadata = metadata
    }
}
```

### 步骤 3: 实现 ProtocolHandler

```swift
public actor MyProtocolHandler: ProtocolHandler {
    public let protocolName = "MyProtocol"
    public let protocolVersion = "1.0"

    private var receiveBuffer = Data()

    public func onConnect(context: ProtocolContext) async throws {
        // 发送握手消息
        let handshake = MyProtocolMessage(type: .handshake)
        let data = try await encodeMessage(handshake, context: context)
        try await context.send(data)
    }

    public func onDisconnect(context: ProtocolContext) async {
        receiveBuffer.removeAll()
    }

    public func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage] {
        receiveBuffer.append(data)

        // 解析消息（根据协议格式）
        var messages: [ProtocolMessage] = []

        while receiveBuffer.count >= minMessageSize {
            if let (message, bytesConsumed) = try parseMessage(from: receiveBuffer) {
                messages.append(message)
                receiveBuffer.removeFirst(bytesConsumed)
            } else {
                break // 需要更多数据
            }
        }

        return messages
    }

    public func encodeMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws -> Data {
        guard let msg = message as? MyProtocolMessage else {
            throw ProtocolError.encodingError("Invalid message type")
        }

        // 编码消息（根据协议格式）
        var data = Data()
        data.append(msg.type.rawValue)
        // ... 添加其他字段
        data.append(msg.payload)

        return data
    }

    public func handleMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws {
        guard let msg = message as? MyProtocolMessage else {
            throw ProtocolError.invalidMessage("Invalid message type")
        }

        // 处理消息
        switch msg.type {
        case .ping:
            // 自动回复 pong
            let pong = MyProtocolMessage(type: .pong)
            let data = try await encodeMessage(pong, context: context)
            try await context.send(data)

        case .data:
            // 处理数据消息
            // ...

        default:
            break
        }
    }

    private func parseMessage(from data: Data) throws -> (MyProtocolMessage, Int)? {
        // 实现消息解析逻辑
        // 返回 (消息, 消耗的字节数) 或 nil（需要更多数据）
        return nil
    }
}
```

### 步骤 4: 使用协议

```swift
// 创建连接
let connection = TCPConnection(host: "example.com", port: 9000)
try await connection.connect()

// 创建协议处理器
let protocol = MyProtocolHandler()
let context = connection.createProtocolContext()

// 连接
try await protocol.onConnect(context: context)

// 发送消息
let message = MyProtocolMessage(type: .data, payload: myData)
let data = try await protocol.encodeMessage(message, context: context)
try await context.send(data)

// 接收和处理消息
let receivedData = try await context.receive(timeout: 5.0)
let messages = try await protocol.onDataReceived(receivedData, context: context)

for message in messages {
    try await protocol.handleMessage(message, context: context)
}
```

---

## 示例协议

NexusKit 提供了三个完整的协议实现示例：

### 1. SimpleMQTTProtocol

**类型**: 二进制协议（MQTT-like）
**特性**:
- 发布/订阅模式
- QoS 支持
- 心跳机制
- 变长编码

**适用场景**: IoT设备通信、消息队列

```swift
// 使用示例
let mqtt = SimpleMQTTProtocol()
try await mqtt.onConnect(context: context)
try await mqtt.subscribe(topic: "sensors/temperature", context: context)
try await mqtt.publish(topic: "sensors/temperature", payload: data, context: context)
```

**文件位置**: `Examples/Protocols/SimpleMQTTProtocol.swift`

### 2. SimpleRedisProtocol

**类型**: 文本协议（RESP）
**特性**:
- 简单字符串、批量字符串、数组、整数、错误
- 行分隔符 (\r\n)
- 命令-响应模式

**适用场景**: 键值存储、缓存系统

```swift
// 使用示例
let redis = SimpleRedisProtocol()
try await redis.onConnect(context: context)
try await redis.set(key: "user:123", value: "John", context: context)
let value = try await redis.get(key: "user:123", context: context)
```

**文件位置**: `Examples/Protocols/SimpleRedisProtocol.swift`

### 3. CustomBinaryProtocol

**类型**: 自定义二进制协议
**特性**:
- 固定头部 (12字节)
- 魔数校验 (0x4E455855 - "NEXU")
- 版本协商
- 操作码
- 标志位（压缩/加密/分片）

**适用场景**: 高性能RPC、游戏协议、自定义业务协议

```swift
// 使用示例
let proto = CustomBinaryProtocol()
try await proto.onConnect(context: context)
let response = try await proto.request(requestData, context: context, waitForResponse: true)
try await proto.notify(notificationData, context: context)
```

**文件位置**: `Examples/Protocols/CustomBinaryProtocol.swift`

---

## 最佳实践

### 1. 消息边界处理

**问题**: TCP是流协议，消息可能被分片或合并

**解决方案**:
```swift
private var receiveBuffer = Data()

public func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage] {
    receiveBuffer.append(data)

    var messages: [ProtocolMessage] = []

    while canParseMessage(from: receiveBuffer) {
        let (message, bytesConsumed) = try parseNextMessage(from: receiveBuffer)
        messages.append(message)
        receiveBuffer.removeFirst(bytesConsumed)
    }

    return messages
}
```

### 2. 协议状态管理

使用 `ProtocolContext` 存储状态：

```swift
// 存储序列号
await context.setState(sequenceNumber, forKey: "sequenceNumber")

// 获取序列号
if let seq: Int = await context.getState(forKey: "sequenceNumber") {
    // 使用序列号
}
```

### 3. 错误处理

```swift
public func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage] {
    do {
        return try parseMessages(from: data)
    } catch let error as ProtocolError {
        // 协议错误 - 发送错误响应
        try await sendError(error.description, context: context)
        throw error
    } catch {
        // 其他错误
        throw ProtocolError.decodingError(error.localizedDescription)
    }
}
```

### 4. 心跳/保活

```swift
public func onConnect(context: ProtocolContext) async throws {
    // 启动心跳任务
    Task {
        while await context.isConnected {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30秒
            try? await ping(context: context)
        }
    }
}
```

### 5. 版本协商

```swift
public func onConnect(context: ProtocolContext) async throws {
    let handshake = createHandshake(version: protocolVersion)
    try await context.send(handshake)

    let response = try await context.receive(timeout: 5.0)
    let serverVersion = parseVersion(from: response)

    if !isCompatibleVersion(serverVersion) {
        throw ProtocolError.unsupportedVersion(serverVersion)
    }
}
```

---

## 性能优化

### 1. 零拷贝传输

结合 `ZeroCopyTransfer` 减少内存拷贝：

```swift
let transfer = ZeroCopyTransfer.shared

public func send(largeData: Data, context: ProtocolContext) async throws {
    try await transfer.write(largeData) { chunk in
        try await context.send(chunk)
    }
}
```

### 2. 缓冲区池

使用 `BufferPool` 复用缓冲区：

```swift
let pool = BufferPool.shared

public func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage] {
    let buffer = await pool.acquire(size: data.count)
    defer { buffer.release() }

    // 使用缓冲区处理数据
    // ...
}
```

### 3. 批量处理

```swift
private var pendingMessages: [ProtocolMessage] = []

public func send(_ message: ProtocolMessage, context: ProtocolContext) async throws {
    pendingMessages.append(message)

    if pendingMessages.count >= batchSize {
        try await flushMessages(context: context)
    }
}

private func flushMessages(context: ProtocolContext) async throws {
    let batch = pendingMessages
    pendingMessages.removeAll()

    for message in batch {
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }
}
```

### 4. 预分配缓冲区

```swift
public func encodeMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws -> Data {
    // 预分配足够大小的缓冲区
    var data = Data(capacity: estimatedSize(message))

    // 编码消息
    // ...

    return data
}
```

---

## 常见问题

### Q1: 如何处理粘包/半包？

**A**: 使用接收缓冲区累积数据，只有当完整消息可用时才解析：

```swift
while receiveBuffer.count >= minMessageSize {
    guard let messageLength = getMessageLength(from: receiveBuffer) else {
        break // 头部不完整
    }

    guard receiveBuffer.count >= messageLength else {
        break // 消息不完整
    }

    // 解析完整消息
    let message = try parseMessage(from: receiveBuffer)
    messages.append(message)
    receiveBuffer.removeFirst(messageLength)
}
```

### Q2: 如何实现请求-响应模式？

**A**: 使用请求ID关联请求和响应：

```swift
private var pendingRequests: [UInt32: CheckedContinuation<ProtocolMessage, Error>] = [:]
private var nextRequestID: UInt32 = 0

public func request(_ payload: Data, context: ProtocolContext) async throws -> ProtocolMessage {
    let requestID = nextRequestID
    nextRequestID += 1

    return try await withCheckedThrowingContinuation { continuation in
        pendingRequests[requestID] = continuation

        Task {
            let request = createRequest(id: requestID, payload: payload)
            let data = try await encodeMessage(request, context: context)
            try await context.send(data)
        }
    }
}

public func handleMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws {
    if let requestID = getRequestID(from: message),
       let continuation = pendingRequests.removeValue(forKey: requestID) {
        continuation.resume(returning: message)
    }
}
```

### Q3: 如何处理大文件传输？

**A**: 使用分片传输和零拷贝：

```swift
public func sendFile(_ fileURL: URL, context: ProtocolContext) async throws {
    let fileHandle = try FileHandle(forReadingFrom: fileURL)
    defer { try? fileHandle.close() }

    let chunkSize = 64 * 1024 // 64KB
    var offset: UInt64 = 0

    while true {
        let chunk = fileHandle.readData(ofLength: chunkSize)
        if chunk.isEmpty { break }

        let message = createDataMessage(offset: offset, data: chunk, isLast: chunk.count < chunkSize)
        let encoded = try await encodeMessage(message, context: context)
        try await context.send(encoded)

        offset += UInt64(chunk.count)
    }
}
```

### Q4: 如何实现协议升级/降级？

**A**: 在握手阶段协商版本：

```swift
public func onConnect(context: ProtocolContext) async throws {
    // 发送支持的版本列表
    let handshake = createHandshake(supportedVersions: ["2.0", "1.5", "1.0"])
    try await context.send(handshake)

    // 接收服务器选择的版本
    let response = try await context.receive(timeout: 5.0)
    let selectedVersion = parseSelectedVersion(from: response)

    // 存储协议版本
    await context.setState(selectedVersion, forKey: "protocolVersion")

    // 根据版本调整行为
    configureForVersion(selectedVersion)
}
```

### Q5: 如何调试协议实现？

**A**: 添加详细日志和统计：

```swift
public func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage] {
    print("[Protocol] Received \(data.count) bytes: \(data.hexString)")

    let messages = try parseMessages(from: data)

    for message in messages {
        print("[Protocol] Parsed message: type=\(message.messageType), size=\(message.payload.count)")
    }

    return messages
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
```

---

## 总结

NexusKit 的协议抽象层提供了：

1. **灵活性**: 支持任意文本/二进制协议
2. **性能**: 零拷贝、缓冲区池、Actor并发
3. **易用性**: 清晰的API和丰富的示例
4. **可靠性**: 完善的错误处理和状态管理

通过遵循本指南，您可以快速实现高性能、生产级的自定义网络协议。

---

## 参考资料

- [ProtocolHandler API](../Sources/NexusCore/Protocol/ProtocolHandler.swift)
- [SimpleMQTTProtocol 示例](../Examples/Protocols/SimpleMQTTProtocol.swift)
- [SimpleRedisProtocol 示例](../Examples/Protocols/SimpleRedisProtocol.swift)
- [CustomBinaryProtocol 示例](../Examples/Protocols/CustomBinaryProtocol.swift)
- [Zero-Copy Guide](ZeroCopyGuide.md)
- [Performance Guide](PerformanceGuide.md)
