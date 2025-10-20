# 编解码器开发指南

## 目录

1. [概述](#概述)
2. [编解码器架构](#编解码器架构)
3. [内置编解码器](#内置编解码器)
4. [编解码器链](#编解码器链)
5. [自定义编解码器](#自定义编解码器)
6. [性能优化](#性能优化)
7. [最佳实践](#最佳实践)

---

## 概述

NexusKit 提供了强大的编解码器系统，用于在网络传输前对数据进行编码，以及在接收后进行解码。支持多种编码格式和编解码器链。

### 核心特性

- ✅ **多格式支持**: JSON、Protobuf、MessagePack、CBOR等
- ✅ **编解码器链**: 支持多个编解码器组合（如：JSON → Gzip → AES）
- ✅ **类型安全**: 基于Swift Codable的类型安全编解码
- ✅ **高性能**: 零拷贝优化、缓冲区池
- ✅ **可扩展**: 易于添加自定义编解码器

---

## 编解码器架构

### Codec 协议

```swift
public protocol Codec: Sendable {
    /// 编解码器名称
    var name: String { get }

    /// 内容类型（如 "application/json"）
    var contentType: String? { get }

    /// 编码数据
    func encode<T: Encodable>(_ value: T) async throws -> Data

    /// 解码数据
    func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T

    /// 估计编码后的大小
    func estimatedSize<T: Encodable>(_ value: T) -> Int
}
```

### 数据编解码器

用于原始数据的转换（如压缩、加密）:

```swift
public protocol DataCodec: Sendable {
    /// 编解码器名称
    var name: String { get }

    /// 转换数据
    func transform(_ data: Data) async throws -> Data

    /// 逆转换数据
    func reverseTransform(_ data: Data) async throws -> Data
}
```

---

## 内置编解码器

### 1. JSON Codec

**特性**:
- 基于 `JSONEncoder`/`JSONDecoder`
- 支持 pretty printing
- 支持自定义日期/数据策略
- 支持浮点数非数字处理

**使用示例**:
```swift
struct User: Codable {
    let id: Int
    let name: String
    let createdAt: Date
}

let codec = JSONCodec()
let user = User(id: 1, name: "Alice", createdAt: Date())

// 编码
let data = try await codec.encode(user)

// 解码
let decoded = try await codec.decode(User.self, from: data)
```

**配置选项**:
```swift
let codec = JSONCodec(
    prettyPrint: true,
    dateEncodingStrategy: .iso8601,
    keyEncodingStrategy: .convertToSnakeCase
)
```

### 2. Protobuf Codec

**特性**:
- 基于 SwiftProtobuf
- 高性能二进制格式
- 向后兼容
- 跨语言支持

**使用示例**:
```swift
// 假设已定义 User.proto
import SwiftProtobuf

let codec = ProtobufCodec()
let user = User(id: 1, name: "Alice")

let data = try await codec.encode(user)
let decoded = try await codec.decode(User.self, from: data)
```

### 3. MessagePack Codec

**特性**:
- 高效二进制格式
- 比JSON更紧凑
- 支持多种数据类型

**使用示例**:
```swift
let codec = MessagePackCodec()
let data = try await codec.encode(myData)
let decoded = try await codec.decode(MyType.self, from: data)
```

### 4. CBOR Codec

**特性**:
- RFC 7049标准
- 紧凑二进制格式
- 支持流式编码

**使用示例**:
```swift
let codec = CBORCodec()
let data = try await codec.encode(myData)
let decoded = try await codec.decode(MyType.self, from: data)
```

### 5. Compression Codecs

#### Gzip Codec
```swift
let gzip = GzipCodec(compressionLevel: 6)
let compressed = try await gzip.transform(data)
let decompressed = try await gzip.reverseTransform(compressed)
```

#### Zlib Codec
```swift
let zlib = ZlibCodec()
let compressed = try await zlib.transform(data)
```

#### LZ4 Codec
```swift
let lz4 = LZ4Codec() // 极速压缩
let compressed = try await lz4.transform(data)
```

### 6. Encryption Codecs

#### AES Codec
```swift
let key = Data(/* 256-bit key */)
let aes = AESCodec(key: key, mode: .GCM)
let encrypted = try await aes.transform(data)
let decrypted = try await aes.reverseTransform(encrypted)
```

---

## 编解码器链

### CodecChain

编解码器链允许组合多个编解码器，按顺序执行转换：

```swift
public actor CodecChain: Codec {
    private let codecs: [any Codec]

    public init(codecs: [any Codec]) {
        self.codecs = codecs
    }

    public func encode<T: Encodable>(_ value: T) async throws -> Data {
        // 依次执行每个编解码器
        var data = try await codecs[0].encode(value)

        for codec in codecs.dropFirst() {
            if let dataCodec = codec as? DataCodec {
                data = try await dataCodec.transform(data)
            }
        }

        return data
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        // 反向执行
        var currentData = data

        for codec in codecs.reversed().dropLast() {
            if let dataCodec = codec as? DataCodec {
                currentData = try await dataCodec.reverseTransform(currentData)
            }
        }

        return try await codecs.first!.decode(type, from: currentData)
    }
}
```

### 使用示例

**场景1: JSON + Gzip**
```swift
let chain = CodecChain(codecs: [
    JSONCodec(),
    GzipCodec(compressionLevel: 6)
])

let data = try await chain.encode(user)
// 数据流: User → JSON → Gzip → 网络

let decoded = try await chain.decode(User.self, from: data)
// 数据流: 网络 → Ungzip → JSON → User
```

**场景2: JSON + Gzip + AES**
```swift
let chain = CodecChain(codecs: [
    JSONCodec(),
    GzipCodec(),
    AESCodec(key: encryptionKey)
])

let data = try await chain.encode(sensitiveData)
// 数据流: Data → JSON → Gzip → AES → 网络
```

**场景3: Protobuf + LZ4**
```swift
let chain = CodecChain(codecs: [
    ProtobufCodec(),
    LZ4Codec()
])

let data = try await chain.encode(message)
// 高性能场景：Protobuf紧凑 + LZ4极速压缩
```

---

## 自定义编解码器

### 步骤 1: 实现 Codec 协议

```swift
public actor CustomCodec: Codec {
    public let name = "custom"
    public let contentType: String? = "application/x-custom"

    public init() {}

    public func encode<T: Encodable>(_ value: T) async throws -> Data {
        // 1. 使用 JSONEncoder 作为中间步骤
        let jsonData = try JSONEncoder().encode(value)

        // 2. 添加自定义头部
        var data = Data()

        // 魔数 (4 bytes)
        data.append(contentsOf: [0x43, 0x55, 0x53, 0x54]) // "CUST"

        // 版本 (2 bytes)
        data.append(contentsOf: [0x01, 0x00]) // v1.0

        // 长度 (4 bytes)
        let length = UInt32(jsonData.count)
        withUnsafeBytes(of: length.bigEndian) {
            data.append(contentsOf: $0)
        }

        // 负载
        data.append(jsonData)

        return data
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        // 验证魔数
        guard data.count >= 10,
              data[0] == 0x43, data[1] == 0x55,
              data[2] == 0x53, data[3] == 0x54 else {
            throw CodecError.invalidFormat
        }

        // 读取长度
        let length = data[6..<10].withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        // 提取负载
        let payload = data[10...]

        guard payload.count == length else {
            throw CodecError.invalidLength
        }

        // 解码
        return try JSONDecoder().decode(type, from: payload)
    }

    public func estimatedSize<T: Encodable>(_ value: T) -> Int {
        // 头部 (10 bytes) + JSON估计大小
        return 10 + 1024 // 简化估计
    }
}
```

### 步骤 2: 实现 DataCodec（数据转换）

```swift
public actor Base64Codec: DataCodec {
    public let name = "base64"

    public func transform(_ data: Data) async throws -> Data {
        let base64String = data.base64EncodedString()
        return Data(base64String.utf8)
    }

    public func reverseTransform(_ data: Data) async throws -> Data {
        guard let base64String = String(data: data, encoding: .utf8),
              let decoded = Data(base64Encoded: base64String) else {
            throw CodecError.decodingFailed
        }
        return decoded
    }
}
```

### 步骤 3: 使用自定义编解码器

```swift
let customCodec = CustomCodec()

// 单独使用
let encoded = try await customCodec.encode(myData)
let decoded = try await customCodec.decode(MyType.self, from: encoded)

// 在链中使用
let chain = CodecChain(codecs: [
    customCodec,
    GzipCodec(),
    Base64Codec()
])
```

---

## 性能优化

### 1. 零拷贝集成

```swift
public actor OptimizedCodec: Codec {
    private let bufferPool = BufferPool.shared
    private let zeroCopy = ZeroCopyTransfer.shared

    public func encode<T: Encodable>(_ value: T) async throws -> Data {
        // 估计大小并从池获取缓冲区
        let estimatedSize = estimatedSize(value)
        let buffer = await bufferPool.acquire(size: estimatedSize)
        defer { buffer.release() }

        // 编码到缓冲区
        var data = buffer.mutableBuffer()
        // ... 编码逻辑 ...

        return data
    }
}
```

### 2. 流式编码/解码

对于大数据：

```swift
public actor StreamingCodec: Codec {
    public func encodeStream<T: Encodable>(_ value: T, chunkSize: Int = 8192) async throws -> AsyncStream<Data> {
        AsyncStream { continuation in
            Task {
                // 分块编码
                let encoder = JSONEncoder()
                // 实现流式编码逻辑
                continuation.finish()
            }
        }
    }

    public func decodeStream<T: Decodable>(_ type: T.Type, from stream: AsyncStream<Data>) async throws -> T {
        // 流式解码
        var accumulated = Data()
        for await chunk in stream {
            accumulated.append(chunk)
        }
        return try JSONDecoder().decode(type, from: accumulated)
    }
}
```

### 3. 批量操作

```swift
public actor BatchCodec {
    public func encodeBatch<T: Encodable>(_ values: [T]) async throws -> [Data] {
        // 并发编码
        return try await withThrowingTaskGroup(of: Data.self) { group in
            for value in values {
                group.addTask {
                    try await self.codec.encode(value)
                }
            }

            var results: [Data] = []
            for try await data in group {
                results.append(data)
            }
            return results
        }
    }
}
```

### 4. 缓存

```swift
public actor CachingCodec: Codec {
    private var encodeCache: [String: Data] = [:]

    public func encode<T: Encodable>(_ value: T) async throws -> Data {
        let key = String(describing: value)

        if let cached = encodeCache[key] {
            return cached
        }

        let data = try await baseCodec.encode(value)
        encodeCache[key] = data
        return data
    }
}
```

---

## 最佳实践

### 1. 选择合适的编解码器

**JSON**: 人类可读、调试友好、兼容性好
```swift
// 适用场景：API通信、配置文件、日志
let codec = JSONCodec()
```

**Protobuf**: 高性能、紧凑、跨语言
```swift
// 适用场景：微服务、高性能RPC
let codec = ProtobufCodec()
```

**MessagePack**: 比JSON紧凑、比Protobuf简单
```swift
// 适用场景：游戏、实时通信
let codec = MessagePackCodec()
```

### 2. 合理使用压缩

```swift
// 小数据(<1KB)：不压缩
if data.count < 1024 {
    return data
}

// 中等数据(1-100KB)：LZ4（速度优先）
if data.count < 100 * 1024 {
    return try await LZ4Codec().transform(data)
}

// 大数据(>100KB)：Gzip（压缩率优先）
return try await GzipCodec(compressionLevel: 9).transform(data)
```

### 3. 错误处理

```swift
do {
    let data = try await codec.encode(value)
} catch let error as CodecError {
    switch error {
    case .encodingFailed(let reason):
        print("Encoding failed: \(reason)")
    case .invalidFormat:
        print("Invalid format")
    default:
        print("Unknown codec error")
    }
} catch {
    print("Other error: \(error)")
}
```

### 4. 版本兼容性

```swift
public struct VersionedMessage: Codable {
    let version: Int
    let data: Data

    init<T: Encodable>(version: Int, value: T) throws {
        self.version = version
        self.data = try JSONEncoder().encode(value)
    }

    func decode<T: Decodable>(as type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: data)
    }
}
```

### 5. 监控和统计

```swift
public actor CodecWithMetrics: Codec {
    private var encodeCalls: Int = 0
    private var decodeCalls: Int = 0
    private var totalBytesEncoded: Int = 0
    private var totalBytesDecoded: Int = 0

    public func encode<T: Encodable>(_ value: T) async throws -> Data {
        encodeCalls += 1
        let data = try await baseCodec.encode(value)
        totalBytesEncoded += data.count
        return data
    }

    public func getStats() -> CodecStats {
        CodecStats(
            encodeCalls: encodeCalls,
            decodeCalls: decodeCalls,
            totalBytesEncoded: totalBytesEncoded,
            totalBytesDecoded: totalBytesDecoded
        )
    }
}
```

---

## 总结

NexusKit 的编解码器系统提供了：

1. **灵活性**: 支持多种编码格式
2. **可组合性**: 编解码器链支持复杂转换
3. **性能**: 零拷贝、缓冲池、流式处理
4. **安全性**: 类型安全、错误处理
5. **可扩展性**: 易于添加自定义编解码器

通过合理选择和组合编解码器，可以满足各种场景的性能和功能需求。

---

## 参考资料

- [Codec Protocol](../Sources/NexusCore/Codec/Codec.swift)
- [Codec Chain](../Sources/NexusCore/Codec/CodecChain.swift)
- [Zero-Copy Guide](ZeroCopyGuide.md)
- [Performance Guide](PerformanceGuide.md)
- [Protocol Development Guide](ProtocolDevelopmentGuide.md)
