//
//  WebSocketExample.swift
//  NexusKit Examples
//
//  Created by NexusKit Contributors
//

import Foundation
import NexusCore
import NexusWebSocket

// MARK: - 示例 1：基础 WebSocket 连接

/// 最简单的 WebSocket 连接示例
@available(iOS 13.0, macOS 10.15, *)
func example1_BasicWebSocket() async throws {
    print("=== 示例 1：基础 WebSocket 连接 ===\n")

    // 1. 连接到 WebSocket Echo 服务器
    let connection = try await NexusKit.shared
        .webSocket(url: URL(string: "wss://echo.websocket.org")!)
        .id("echo-ws")
        .timeout(10)
        .connect()

    print("✅ WebSocket 连接成功！")

    // 2. 设置消息处理器
    await connection.on(.message) { data in
        if let text = String(data: data, encoding: .utf8) {
            print("📥 收到回显: \(text)")
        }
    }

    // 3. 发送文本消息
    try await connection.sendText("Hello, WebSocket!")
    print("📤 发送: Hello, WebSocket!")

    // 4. 等待响应
    try await Task.sleep(nanoseconds: 2_000_000_000)

    // 5. 断开连接
    await connection.disconnect(reason: .clientInitiated)
    print("👋 连接已断开\n")
}

// MARK: - 示例 2：聊天应用

/// WebSocket 聊天应用示例
@available(iOS 13.0, macOS 10.15, *)
class WebSocketChatClient {
    private var connection: WebSocketConnection?
    private let username: String

    init(username: String) {
        self.username = username
    }

    func connect(url: URL) async throws {
        print("🔗 \(username) 正在连接...")

        connection = try await NexusKit.shared
            .webSocket(url: url)
            .id("chat-\(username)")
            .pingInterval(30)
            .reconnection(ExponentialBackoffStrategy(maxAttempts: 5))
            .hooks(LifecycleHooks(
                onConnected: { [weak self] in
                    print("✅ \(self?.username ?? "") 已连接")
                },
                onDisconnected: { reason in
                    print("❌ 连接断开: \(reason)")
                },
                onReconnecting: { attempt in
                    print("🔄 正在重连... 第 \(attempt) 次尝试")
                }
            ))
            .connect()

        // 设置消息处理器
        await connection?.on(.message) { [weak self] data in
            await self?.handleMessage(data)
        }
    }

    func sendMessage(_ text: String) async throws {
        guard let connection = connection else {
            throw NexusError.notConnected
        }

        try await connection.sendText(text)
        print("📤 \(username): \(text)")
    }

    private func handleMessage(_ data: Data) async {
        if let text = String(data: data, encoding: .utf8) {
            print("📥 收到消息: \(text)")
        }
    }

    func disconnect() async {
        await connection?.disconnect(reason: .clientInitiated)
        print("👋 \(username) 已断开")
    }
}

@available(iOS 13.0, macOS 10.15, *)
func example2_ChatApp() async throws {
    print("=== 示例 2：WebSocket 聊天应用 ===\n")

    // 使用公共的 WebSocket Echo 服务器进行演示
    let url = URL(string: "wss://echo.websocket.org")!

    // 创建两个客户端
    let alice = WebSocketChatClient(username: "Alice")
    let bob = WebSocketChatClient(username: "Bob")

    // 连接
    try await alice.connect(url: url)
    try await bob.connect(url: url)

    // 发送消息
    try await alice.sendMessage("Hi Bob!")
    try await bob.sendMessage("Hello Alice!")

    // 等待消息处理
    try await Task.sleep(nanoseconds: 2_000_000_000)

    // 断开连接
    await alice.disconnect()
    await bob.disconnect()

    print()
}

// MARK: - 示例 3：JSON 协议

/// JSON 消息定义
struct ChatMessage: Codable {
    let type: String
    let user: String
    let message: String
    let timestamp: Date
}

/// JSON 协议适配器
struct JSONWebSocketAdapter: ProtocolAdapter {
    func encode<T: Encodable>(_ message: T, context: EncodingContext) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(message)
    }

    func decode<T: Decodable>(_ data: Data, as type: T.Type, context: DecodingContext) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    func handleIncoming(_ data: Data) async throws -> [ProtocolEvent] {
        [.response(data)]
    }
}

@available(iOS 13.0, macOS 10.15, *)
func example3_JSONProtocol() async throws {
    print("=== 示例 3：JSON 协议 ===\n")

    let connection = try await NexusKit.shared
        .webSocket(url: URL(string: "wss://echo.websocket.org")!)
        .protocol(JSONWebSocketAdapter())
        .connect()

    print("✅ 连接成功（启用 JSON 协议）")

    // 发送 JSON 消息
    let message = ChatMessage(
        type: "chat",
        user: "Alice",
        message: "Hello with JSON!",
        timestamp: Date()
    )

    try await connection.send(message, timeout: 5)
    print("📤 发送 JSON: \(message.message)")

    // 接收 JSON 消息
    await connection.on(.message) { data in
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let receivedMessage = try decoder.decode(ChatMessage.self, from: data)
            print("📥 收到 JSON: \(receivedMessage.message) from \(receivedMessage.user)")
        } catch {
            print("⚠️ JSON 解析失败: \(error)")
        }
    }

    try await Task.sleep(nanoseconds: 2_000_000_000)

    await connection.disconnect(reason: .clientInitiated)
    print("👋 连接已断开\n")
}

// MARK: - 示例 4：自定义头部和子协议

@available(iOS 13.0, macOS 10.15, *)
func example4_CustomHeaders() async throws {
    print("=== 示例 4：自定义头部和子协议 ===\n")

    let connection = try await NexusKit.shared
        .webSocket(url: URL(string: "wss://echo.websocket.org")!)
        .headers([
            "Authorization": "Bearer your-token-here",
            "X-Client-Version": "1.0.0"
        ])
        .protocols(["chat", "superchat"])
        .connect()

    print("✅ 连接成功（自定义头部和子协议）")

    try await connection.sendText("Hello with custom headers!")

    try await Task.sleep(nanoseconds: 1_000_000_000)

    await connection.disconnect(reason: .clientInitiated)
    print("👋 连接已断开\n")
}

// MARK: - 示例 5：实时数据流

@available(iOS 13.0, macOS 10.15, *)
func example5_RealTimeData() async throws {
    print("=== 示例 5：实时数据流 ===\n")

    let connection = try await NexusKit.shared
        .webSocket(url: URL(string: "wss://echo.websocket.org")!)
        .middleware(PrintLoggingMiddleware(showTimestamp: true, showData: false))
        .middleware(MetricsMiddleware(reportInterval: 5))
        .connect()

    print("✅ 连接成功（启用日志和监控）\n")

    // 模拟实时数据流
    for i in 1...10 {
        let data = "Message \(i): \(Date())".data(using: .utf8)!
        try await connection.send(data, timeout: 1)

        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
    }

    print("\n📊 实时数据发送完成")

    try await Task.sleep(nanoseconds: 2_000_000_000)

    await connection.disconnect(reason: .clientInitiated)
    print()
}

// MARK: - 示例 6：错误处理和重连

@available(iOS 13.0, macOS 10.15, *)
func example6_ErrorHandling() async throws {
    print("=== 示例 6：错误处理和重连 ===\n")

    let connection = try await NexusKit.shared
        .webSocket(url: URL(string: "wss://echo.websocket.org")!)
        .reconnection(ExponentialBackoffStrategy(
            maxAttempts: 3,
            initialInterval: 1.0,
            maxInterval: 10.0,
            multiplier: 2.0
        ))
        .hooks(LifecycleHooks(
            onConnected: {
                print("🟢 连接成功")
            },
            onReconnecting: { attempt in
                print("🔄 正在重连... 第 \(attempt) 次尝试")
            },
            onDisconnected: { reason in
                print("🔴 连接断开: \(reason)")
            },
            onError: { error in
                print("⚠️ 错误: \(error.localizedDescription)")
            }
        ))
        .connect()

    print("✅ 初始连接成功\n")

    // 模拟网络中断（实际应用中由网络状态触发）
    // connection 会自动尝试重连

    try await Task.sleep(nanoseconds: 5_000_000_000)

    await connection.disconnect(reason: .clientInitiated)
    print("\n👋 示例结束\n")
}

// MARK: - 主函数

@available(iOS 13.0, macOS 10.15, *)
@main
struct WebSocketExample {
    static func main() async {
        print("🚀 NexusKit WebSocket 示例程序\n")
        print("=" + String(repeating: "=", count: 50) + "\n")

        do {
            // 运行所有示例
            try await example1_BasicWebSocket()
            try await example2_ChatApp()
            try await example3_JSONProtocol()
            try await example4_CustomHeaders()
            try await example5_RealTimeData()
            try await example6_ErrorHandling()

            print("=" + String(repeating: "=", count: 50))
            print("\n✅ 所有示例运行完成！")

        } catch {
            print("\n❌ 错误: \(error.localizedDescription)")
        }
    }
}
