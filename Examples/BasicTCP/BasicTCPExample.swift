//
//  BasicTCPExample.swift
//  NexusKit Examples
//
//  Created by NexusKit Contributors
//

import Foundation
import NexusCore
import NexusTCP

// MARK: - 示例 1：基础 TCP 连接

/// 最简单的 TCP 连接示例
func example1_BasicConnection() async throws {
    print("=== 示例 1：基础 TCP 连接 ===\n")

    // 1. 创建 TCP 连接
    let connection = try await NexusKit.shared
        .tcp(host: "127.0.0.1", port: 8080)
        .id("basic-tcp")
        .timeout(30)
        .connect()

    print("✅ 连接成功！连接 ID: \(connection.id)")

    // 2. 发送原始数据
    let message = "Hello, Server!".data(using: .utf8)!
    try await connection.send(message, timeout: 5)

    print("📤 发送消息: Hello, Server!")

    // 3. 断开连接
    await connection.disconnect(reason: .clientInitiated)

    print("👋 连接已断开\n")
}

// MARK: - 示例 2：使用二进制协议

/// 使用二进制协议适配器
func example2_BinaryProtocol() async throws {
    print("=== 示例 2：二进制协议 ===\n")

    // 1. 创建带协议的连接
    let connection = try await NexusKit.shared
        .tcp(host: "127.0.0.1", port: 8080)
        .id("binary-tcp")
        .binaryProtocol(version: 1, compressionEnabled: true)
        .heartbeat(interval: 30, timeout: 90)
        .connect()

    print("✅ 连接成功（启用二进制协议和心跳）")

    // 2. 定义消息结构
    struct LoginRequest: Codable {
        let username: String
        let password: String
    }

    let loginRequest = LoginRequest(
        username: "admin",
        password: "secret"
    )

    // 3. 发送结构化消息
    try await connection.send(loginRequest, timeout: 5)

    print("📤 发送登录请求: username=\(loginRequest.username)")

    // 4. 等待响应（通过事件处理）
    await connection.on(.message) { data in
        print("📥 收到响应: \(data.count) 字节")
    }

    // 等待一段时间接收消息
    try await Task.sleep(nanoseconds: 2_000_000_000)

    await connection.disconnect(reason: .clientInitiated)

    print("👋 连接已断开\n")
}

// MARK: - 示例 3：自动重连

/// 自动重连示例
func example3_AutoReconnect() async throws {
    print("=== 示例 3：自动重连 ===\n")

    // 1. 创建带自动重连的连接
    let connection = try await NexusKit.shared
        .tcp(host: "127.0.0.1", port: 8080)
        .id("reconnect-tcp")
        .reconnection(ExponentialBackoffStrategy(
            maxAttempts: 5,
            initialInterval: 1.0,
            maxInterval: 30.0,
            multiplier: 2.0
        ))
        .hooks(LifecycleHooks(
            onConnected: {
                print("🟢 已连接")
            },
            onReconnecting: { attempt in
                print("🔄 正在重连... 第 \(attempt) 次尝试")
            },
            onDisconnected: { reason in
                print("🔴 已断开: \(reason)")
            }
        ))
        .connect()

    print("✅ 初始连接成功")

    // 2. 模拟网络中断（实际应用中由网络状态触发）
    // connection 会自动尝试重连

    // 等待
    try await Task.sleep(nanoseconds: 10_000_000_000)

    await connection.disconnect(reason: .clientInitiated)

    print("👋 示例结束\n")
}

// MARK: - 示例 4：中间件使用

/// 日志中间件
struct LoggingMiddleware: Middleware {
    let name = "LoggingMiddleware"
    let priority = 100

    func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        print("📤 [发送] \(data.count) 字节 -> \(context.endpoint)")
        return data
    }

    func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        print("📥 [接收] \(data.count) 字节 <- \(context.endpoint)")
        return data
    }
}

/// 压缩中间件（示例）
struct CompressionMiddleware: Middleware {
    let name = "CompressionMiddleware"
    let priority = 50

    func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        // 如果数据大于 1KB，进行压缩
        guard data.count > 1024 else { return data }

        #if canImport(Compression)
        if let compressed = try? data.gzipped() {
            print("🗜️  压缩: \(data.count) -> \(compressed.count) 字节 (节省 \(100 - compressed.count * 100 / data.count)%)")
            return compressed
        }
        #endif

        return data
    }

    func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        // 尝试解压缩
        #if canImport(Compression)
        if let decompressed = try? data.gunzipped() {
            print("📦 解压缩: \(data.count) -> \(decompressed.count) 字节")
            return decompressed
        }
        #endif

        return data
    }
}

/// 中间件示例
func example4_Middleware() async throws {
    print("=== 示例 4：中间件 ===\n")

    // 1. 创建带中间件的连接
    let connection = try await NexusKit.shared
        .tcp(host: "127.0.0.1", port: 8080)
        .id("middleware-tcp")
        .middlewares([
            LoggingMiddleware(),
            CompressionMiddleware()
        ])
        .connect()

    print("✅ 连接成功（启用日志和压缩中间件）\n")

    // 2. 发送大数据（触发压缩）
    let largeData = Data(repeating: 0xFF, count: 2048)
    try await connection.send(largeData, timeout: 5)

    // 3. 发送小数据（不压缩）
    let smallData = "Small message".data(using: .utf8)!
    try await connection.send(smallData, timeout: 5)

    try await Task.sleep(nanoseconds: 1_000_000_000)

    await connection.disconnect(reason: .clientInitiated)

    print("\n👋 示例结束\n")
}

// MARK: - 示例 5：TLS 加密连接

/// TLS 加密连接示例
func example5_TLS() async throws {
    print("=== 示例 5：TLS 加密连接 ===\n")

    // 1. 创建 TLS 连接
    let connection = try await NexusKit.shared
        .tcp(host: "secure.example.com", port: 443)
        .id("tls-tcp")
        .enableTLS() // 使用系统默认证书
        .connect()

    print("✅ TLS 连接成功！")
    print("🔒 连接已加密")

    // 2. 发送加密数据
    let message = "Secure message".data(using: .utf8)!
    try await connection.send(message, timeout: 5)

    print("📤 发送加密消息")

    await connection.disconnect(reason: .clientInitiated)

    print("👋 TLS 连接已断开\n")
}

// MARK: - 示例 6：连接池管理

/// 连接池示例
func example6_ConnectionPool() async throws {
    print("=== 示例 6：连接池管理 ===\n")

    // 1. 创建多个连接
    let connection1 = try await NexusKit.shared
        .tcp(host: "127.0.0.1", port: 8080)
        .id("pool-1")
        .connect()

    let connection2 = try await NexusKit.shared
        .tcp(host: "127.0.0.1", port: 8080)
        .id("pool-2")
        .connect()

    print("✅ 创建了 2 个连接")

    // 2. 获取活跃连接
    let activeConnections = await NexusKit.shared.activeConnections()
    print("📊 当前活跃连接数: \(activeConnections.count)")

    // 3. 查看统计信息
    let stats = await NexusKit.shared.statistics()
    print("📈 统计信息:")
    print("   - 总连接数: \(stats.totalConnections)")
    print("   - 活跃连接数: \(stats.activeConnections)")
    print("   - 发送字节数: \(stats.totalBytesSent)")
    print("   - 接收字节数: \(stats.totalBytesReceived)")

    // 4. 断开所有连接
    await NexusKit.shared.disconnectAll()

    print("\n👋 所有连接已断开\n")
}

// MARK: - 示例 7：完整的聊天客户端

/// 聊天消息
struct ChatMessage: Codable {
    let from: String
    let to: String
    let content: String
    let timestamp: Date
}

/// 完整的聊天客户端示例
class ChatClient {
    private var connection: TCPConnection?
    private let username: String

    init(username: String) {
        self.username = username
    }

    func connect(host: String, port: UInt16) async throws {
        print("🔗 正在连接到聊天服务器...")

        connection = try await NexusKit.shared
            .tcp(host: host, port: port)
            .id("chat-\(username)")
            .binaryProtocol(version: 1, compressionEnabled: true)
            .heartbeat(interval: 30, timeout: 90)
            .reconnection(ExponentialBackoffStrategy())
            .hooks(LifecycleHooks(
                onConnected: { [weak self] in
                    print("✅ \(self?.username ?? "") 已连接到服务器")
                },
                onDisconnected: { reason in
                    print("❌ 连接断开: \(reason)")
                },
                onError: { error in
                    print("⚠️ 错误: \(error.localizedDescription)")
                }
            ))
            .middleware(LoggingMiddleware())
            .connect()

        // 设置消息处理器
        await connection?.on(.message) { [weak self] data in
            await self?.handleMessage(data)
        }
    }

    func sendMessage(to: String, content: String) async throws {
        guard let connection = connection else {
            throw NexusError.notConnected
        }

        let message = ChatMessage(
            from: username,
            to: to,
            content: content,
            timestamp: Date()
        )

        try await connection.send(message, timeout: 5)

        print("📤 \(username) -> \(to): \(content)")
    }

    private func handleMessage(_ data: Data) async {
        // 解析消息
        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(ChatMessage.self, from: data)

            print("📥 \(message.from) -> \(username): \(message.content)")

        } catch {
            print("⚠️ 无法解析消息: \(error)")
        }
    }

    func disconnect() async {
        await connection?.disconnect(reason: .clientInitiated)
        print("👋 \(username) 已断开连接")
    }
}

/// 聊天客户端示例
func example7_ChatClient() async throws {
    print("=== 示例 7：聊天客户端 ===\n")

    // 1. 创建两个聊天客户端
    let alice = ChatClient(username: "Alice")
    let bob = ChatClient(username: "Bob")

    // 2. 连接到服务器
    try await alice.connect(host: "127.0.0.1", port: 8080)
    try await bob.connect(host: "127.0.0.1", port: 8080)

    // 3. 发送消息
    try await alice.sendMessage(to: "Bob", content: "Hi Bob!")
    try await bob.sendMessage(to: "Alice", content: "Hello Alice!")

    // 4. 等待一段时间
    try await Task.sleep(nanoseconds: 3_000_000_000)

    // 5. 断开连接
    await alice.disconnect()
    await bob.disconnect()

    print("\n👋 聊天示例结束\n")
}

// MARK: - 主函数

@main
struct BasicTCPExample {
    static func main() async {
        print("🚀 NexusKit TCP 示例程序\n")
        print("=" + String(repeating: "=", count: 50) + "\n")

        do {
            // 运行所有示例
            try await example1_BasicConnection()
            try await example2_BinaryProtocol()
            try await example3_AutoReconnect()
            try await example4_Middleware()
            try await example5_TLS()
            try await example6_ConnectionPool()
            try await example7_ChatClient()

            print("=" + String(repeating: "=", count: 50))
            print("\n✅ 所有示例运行完成！")

        } catch {
            print("\n❌ 错误: \(error.localizedDescription)")
        }
    }
}
