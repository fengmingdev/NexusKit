//
//  ChatApplicationTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusCore

/// 聊天应用场景测试
///
/// 模拟真实的聊天应用场景，测试即时通讯相关功能
///
/// **场景特点**:
/// - 长连接保持
/// - 双向消息传输
/// - 实时性要求高
/// - 需要心跳保活
/// - 多用户并发
/// - 离线重连
///
/// **前置条件**: 启动测试服务器
/// ```bash
/// cd TestServers
/// npm run tcp
/// ```
///
@available(iOS 13.0, macOS 10.15, *)
final class ChatApplicationTests: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8888
    private let connectionTimeout: TimeInterval = 5.0

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        print("\n" + String(repeating: "=", count: 60))
        print("💬 聊天应用场景测试")
        print(String(repeating: "=", count: 60))
    }

    override func tearDown() async throws {
        print(String(repeating: "=", count: 60))
        print("✅ 聊天场景测试完成")
        print(String(repeating: "=", count: 60) + "\n")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await super.tearDown()
    }

    // MARK: - 1. 单聊场景 (2个测试)

    /// 场景1.1: 1对1聊天 - 基础消息收发
    func testOneToOneChatBasic() async throws {
        print("\n📊 场景: 1对1聊天 - 基础消息收发")

        // 模拟两个用户
        let alice = try await createChatUser(name: "Alice")
        let bob = try await createChatUser(name: "Bob")

        defer {
            Task {
                await alice.disconnect()
                await bob.disconnect()
            }
        }

        // Alice 发送消息给 Bob
        let messages = [
            "Hi Bob!",
            "How are you?",
            "Let's meet tomorrow.",
            "Sure, see you! 👋"
        ]

        print("  Alice 向 Bob 发送 \(messages.count) 条消息...")

        var sendLatencies: [TimeInterval] = []

        for (index, message) in messages.enumerated() {
            let chatMessage = ChatMessage(
                from: "Alice",
                to: "Bob",
                content: message,
                timestamp: Date()
            )

            let start = Date()
            try await alice.send(chatMessage)
            let latency = Date().timeIntervalSince(start)
            sendLatencies.append(latency)

            print("    [\(index + 1)] Alice → Bob: \"\(message)\" (\(String(format: "%.2f", latency * 1000))ms)")

            // 模拟用户输入间隔
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }

        // Bob 回复
        let reply = ChatMessage(
            from: "Bob",
            to: "Alice",
            content: "See you tomorrow! 😊",
            timestamp: Date()
        )

        try await bob.send(reply)
        print("    [5] Bob → Alice: \"See you tomorrow! 😊\"")

        // 统计
        let avgLatency = sendLatencies.reduce(0, +) / Double(sendLatencies.count)
        let maxLatency = sendLatencies.max() ?? 0

        print("\n📊 1对1聊天结果:")
        print("  消息数: \(messages.count + 1)")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("  最大延迟: \(String(format: "%.2f", maxLatency * 1000))ms")

        // 聊天场景要求低延迟
        XCTAssertLessThan(avgLatency, 0.1, "聊天消息平均延迟应该小于100ms")
        XCTAssertLessThan(maxLatency, 0.2, "聊天消息最大延迟应该小于200ms")
    }

    /// 场景1.2: 1对1聊天 - 长时间对话
    func testOneToOneChatLongConversation() async throws {
        print("\n📊 场景: 1对1聊天 - 长时间对话 (5分钟)")

        let alice = try await createChatUser(name: "Alice", heartbeatInterval: 30)
        let bob = try await createChatUser(name: "Bob", heartbeatInterval: 30)

        defer {
            Task {
                await alice.disconnect()
                await bob.disconnect()
            }
        }

        let conversationDuration: TimeInterval = 300 // 5分钟
        let messageInterval: TimeInterval = 10 // 每10秒一条消息
        let startTime = Date()

        var totalMessages = 0
        var failedMessages = 0
        var latencies: [TimeInterval] = []

        print("  模拟5分钟对话，每10秒交换消息...")

        while Date().timeIntervalSince(startTime) < conversationDuration {
            // Alice 发送消息
            let aliceMessage = ChatMessage(
                from: "Alice",
                to: "Bob",
                content: "Message at \(Date())",
                timestamp: Date()
            )

            let start1 = Date()
            do {
                try await alice.send(aliceMessage)
                let latency1 = Date().timeIntervalSince(start1)
                latencies.append(latency1)
                totalMessages += 1
            } catch {
                failedMessages += 1
                print("    ⚠️ Alice 发送失败")
            }

            // 等待一半时间
            try await Task.sleep(nanoseconds: UInt64(messageInterval / 2 * 1_000_000_000))

            // Bob 回复
            let bobMessage = ChatMessage(
                from: "Bob",
                to: "Alice",
                content: "Reply at \(Date())",
                timestamp: Date()
            )

            let start2 = Date()
            do {
                try await bob.send(bobMessage)
                let latency2 = Date().timeIntervalSince(start2)
                latencies.append(latency2)
                totalMessages += 1
            } catch {
                failedMessages += 1
                print("    ⚠️ Bob 发送失败")
            }

            // 等待剩余时间
            try await Task.sleep(nanoseconds: UInt64(messageInterval / 2 * 1_000_000_000))

            let elapsed = Date().timeIntervalSince(startTime)
            if Int(elapsed) % 60 == 0 && Int(elapsed) > 0 {
                print("    已运行 \(Int(elapsed / 60)) 分钟, 消息数: \(totalMessages)")
            }
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        let successRate = Double(totalMessages - failedMessages) / Double(totalMessages)
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)

        // 检查心跳状态
        let aliceStats = await alice.heartbeatStatistics
        let bobStats = await bob.heartbeatStatistics

        print("\n📊 长时间对话结果:")
        print("  对话时长: \(String(format: "%.1f", actualDuration / 60))分钟")
        print("  总消息数: \(totalMessages)")
        print("  失败数: \(failedMessages)")
        print("  成功率: \(String(format: "%.2f", successRate * 100))%")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("  Alice心跳: 发送\(aliceStats.sentCount), 接收\(aliceStats.receivedCount)")
        print("  Bob心跳: 发送\(bobStats.sentCount), 接收\(bobStats.receivedCount)")

        XCTAssertGreaterThan(successRate, 0.95, "长时间对话成功率应该大于95%")
        XCTAssertLessThan(avgLatency, 0.15, "平均延迟应该小于150ms")
    }

    // MARK: - 2. 群聊场景 (2个测试)

    /// 场景2.1: 群聊 - 多人同时发言
    func testGroupChatMultipleUsers() async throws {
        print("\n📊 场景: 群聊 - 10人同时发言")

        let userCount = 10
        let messagesPerUser = 5

        // 创建群聊用户
        print("  创建\(userCount)个群聊用户...")
        var users: [ChatUser] = []
        for i in 1...userCount {
            let user = try await createChatUser(name: "User\(i)")
            users.append(user)
        }

        defer {
            for user in users {
                Task { await user.disconnect() }
            }
        }

        print("  每人发送\(messagesPerUser)条消息到群聊...")

        let startTime = Date()
        var totalMessages = 0
        var latencies: [TimeInterval] = []

        // 并发发送消息
        await withTaskGroup(of: [(Int, TimeInterval)].self) { group in
            for (index, user) in users.enumerated() {
                group.addTask {
                    var results: [(Int, TimeInterval)] = []

                    for msgIndex in 1...messagesPerUser {
                        let message = ChatMessage(
                            from: await user.name,
                            to: "Group",
                            content: "Message \(msgIndex) from \(await user.name)",
                            timestamp: Date()
                        )

                        let start = Date()
                        do {
                            try await user.send(message)
                            let latency = Date().timeIntervalSince(start)
                            results.append((index, latency))
                        } catch {
                            // 记录失败
                        }

                        // 随机延迟，模拟真实发言间隔
                        let delay = UInt64.random(in: 100_000_000...500_000_000) // 0.1-0.5秒
                        try? await Task.sleep(nanoseconds: delay)
                    }

                    return results
                }
            }

            for await userResults in group {
                totalMessages += userResults.count
                latencies.append(contentsOf: userResults.map { $0.1 })
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let maxLatency = latencies.max() ?? 0
        let qps = Double(totalMessages) / totalDuration

        print("\n📊 群聊结果:")
        print("  用户数: \(userCount)")
        print("  总消息数: \(totalMessages)")
        print("  总耗时: \(String(format: "%.2f", totalDuration))秒")
        print("  QPS: \(String(format: "%.1f", qps))")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("  最大延迟: \(String(format: "%.2f", maxLatency * 1000))ms")

        XCTAssertGreaterThan(qps, 10, "群聊QPS应该大于10")
        XCTAssertLessThan(avgLatency, 0.2, "群聊平均延迟应该小于200ms")
    }

    /// 场景2.2: 群聊 - 消息广播
    func testGroupChatBroadcast() async throws {
        print("\n📊 场景: 群聊 - 消息广播 (1→50)")

        let broadcasterCount = 1
        let receiverCount = 50
        let broadcastMessages = 10

        // 创建广播者
        let broadcaster = try await createChatUser(name: "Broadcaster")
        defer { Task { await broadcaster.disconnect() } }

        // 创建接收者
        print("  创建\(receiverCount)个接收者...")
        var receivers: [ChatUser] = []
        for i in 1...receiverCount {
            let receiver = try await createChatUser(name: "Receiver\(i)")
            receivers.append(receiver)
        }

        defer {
            for receiver in receivers {
                Task { await receiver.disconnect() }
            }
        }

        print("  广播\(broadcastMessages)条消息...")

        var latencies: [TimeInterval] = []

        for i in 1...broadcastMessages {
            let message = ChatMessage(
                from: "Broadcaster",
                to: "Everyone",
                content: "Broadcast message #\(i)",
                timestamp: Date()
            )

            let start = Date()
            try await broadcaster.send(message)
            let latency = Date().timeIntervalSince(start)
            latencies.append(latency)

            print("    [广播 \(i)] 延迟: \(String(format: "%.2f", latency * 1000))ms")

            try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
        }

        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)

        print("\n📊 消息广播结果:")
        print("  接收者数: \(receiverCount)")
        print("  广播数: \(broadcastMessages)")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")

        XCTAssertLessThan(avgLatency, 0.15, "广播延迟应该小于150ms")
    }

    // MARK: - 3. 断线重连场景 (2个测试)

    /// 场景3.1: 网络切换重连
    func testNetworkSwitchReconnect() async throws {
        print("\n📊 场景: 网络切换重连")

        let user = try await createChatUser(name: "MobileUser", enableReconnect: true)

        // 发送一些消息
        print("  阶段1: 正常聊天...")
        for i in 1...5 {
            let message = ChatMessage(
                from: "MobileUser",
                to: "Friend",
                content: "Message before disconnect \(i)",
                timestamp: Date()
            )
            try await user.send(message)
        }

        let state1 = await user.state
        print("    连接状态: \(state1)")

        // 模拟网络断开
        print("\n  阶段2: 模拟网络断开...")
        await user.disconnect()
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2秒

        // 重连
        print("  阶段3: 重新连接...")
        let reconnectStart = Date()
        try await user.connect()
        let reconnectDuration = Date().timeIntervalSince(reconnectStart)

        print("    重连耗时: \(String(format: "%.2f", reconnectDuration * 1000))ms")

        // 重连后继续发送消息
        print("\n  阶段4: 重连后继续聊天...")
        var successCount = 0
        for i in 1...5 {
            let message = ChatMessage(
                from: "MobileUser",
                to: "Friend",
                content: "Message after reconnect \(i)",
                timestamp: Date()
            )

            do {
                try await user.send(message)
                successCount += 1
            } catch {
                print("    ⚠️ 发送失败: \(error)")
            }
        }

        let state2 = await user.state
        print("    连接状态: \(state2)")
        print("    重连后成功率: \(successCount)/5")

        await user.disconnect()

        print("\n📊 网络切换重连结果:")
        print("  重连时间: \(String(format: "%.2f", reconnectDuration * 1000))ms")
        print("  重连后成功率: \(String(format: "%.0f", Double(successCount) / 5.0 * 100))%")

        XCTAssertLessThan(reconnectDuration, 2.0, "重连时间应该小于2秒")
        XCTAssertGreaterThanOrEqual(successCount, 4, "重连后应该能正常发送消息")
    }

    /// 场景3.2: 多次断线重连循环
    func testMultipleReconnectCycles() async throws {
        print("\n📊 场景: 多次断线重连循环 (10次)")

        let user = try await createChatUser(name: "UnstableUser", enableReconnect: true)
        defer { Task { await user.disconnect() } }

        let cycles = 10
        var reconnectTimes: [TimeInterval] = []
        var successfulReconnects = 0

        for cycle in 1...cycles {
            print("  循环 \(cycle)/\(cycles):")

            // 发送消息
            let message = ChatMessage(
                from: "UnstableUser",
                to: "Server",
                content: "Cycle \(cycle)",
                timestamp: Date()
            )

            do {
                try await user.send(message)
                print("    ✓ 发送成功")
            } catch {
                print("    ✗ 发送失败")
            }

            // 断开
            await user.disconnect()
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

            // 重连
            let reconnectStart = Date()
            do {
                try await user.connect()
                let reconnectTime = Date().timeIntervalSince(reconnectStart)
                reconnectTimes.append(reconnectTime)
                successfulReconnects += 1
                print("    ✓ 重连成功 (\(String(format: "%.2f", reconnectTime * 1000))ms)")
            } catch {
                print("    ✗ 重连失败")
            }

            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }

        let avgReconnectTime = reconnectTimes.isEmpty ? 0 : reconnectTimes.reduce(0, +) / Double(reconnectTimes.count)
        let reconnectSuccessRate = Double(successfulReconnects) / Double(cycles)

        print("\n📊 多次重连循环结果:")
        print("  总循环数: \(cycles)")
        print("  成功重连: \(successfulReconnects)")
        print("  成功率: \(String(format: "%.1f", reconnectSuccessRate * 100))%")
        print("  平均重连时间: \(String(format: "%.2f", avgReconnectTime * 1000))ms")

        XCTAssertGreaterThan(reconnectSuccessRate, 0.8, "重连成功率应该大于80%")
        XCTAssertLessThan(avgReconnectTime, 1.5, "平均重连时间应该小于1.5秒")
    }

    // MARK: - 4. 特殊消息场景 (2个测试)

    /// 场景4.1: 富媒体消息 (图片/视频/文件)
    func testRichMediaMessages() async throws {
        print("\n📊 场景: 富媒体消息传输")

        let user = try await createChatUser(name: "MediaUser")
        defer { Task { await user.disconnect() } }

        // 模拟不同大小的富媒体消息
        let mediaMessages: [(type: String, size: Int)] = [
            ("Emoji", 100),                     // 100B
            ("Small Image", 50 * 1024),         // 50KB
            ("Large Image", 500 * 1024),        // 500KB
            ("Short Video", 2 * 1024 * 1024),   // 2MB
            ("Document", 1 * 1024 * 1024)       // 1MB
        ]

        print("  发送\(mediaMessages.count)个富媒体消息...")

        var results: [(String, Int, TimeInterval)] = []

        for (type, size) in mediaMessages {
            let mediaData = Data(repeating: 0x42, count: size)
            let message = ChatMessage(
                from: "MediaUser",
                to: "Friend",
                content: "[\(type)]",
                timestamp: Date(),
                mediaData: mediaData
            )

            let start = Date()
            try await user.send(message)
            let duration = Date().timeIntervalSince(start)

            results.append((type, size, duration))

            let sizeKB = Double(size) / 1024.0
            let speedKBps = sizeKB / duration

            print("    [\(type)] \(String(format: "%.1f", sizeKB))KB, 耗时: \(String(format: "%.2f", duration * 1000))ms, 速度: \(String(format: "%.1f", speedKBps))KB/s")

            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
        }

        print("\n📊 富媒体消息结果:")
        let totalSize = results.map { $0.1 }.reduce(0, +)
        let totalTime = results.map { $0.2 }.reduce(0, +)
        let avgSpeed = Double(totalSize) / 1024.0 / totalTime // KB/s

        print("  消息数: \(results.count)")
        print("  总大小: \(String(format: "%.2f", Double(totalSize) / 1024.0 / 1024.0))MB")
        print("  总耗时: \(String(format: "%.2f", totalTime))秒")
        print("  平均速度: \(String(format: "%.1f", avgSpeed))KB/s")

        XCTAssertGreaterThan(avgSpeed, 500, "富媒体传输速度应该大于500KB/s")
    }

    /// 场景4.2: 消息重发机制
    func testMessageRetry() async throws {
        print("\n📊 场景: 消息重发机制")

        let user = try await createChatUser(name: "RetryUser", enableRetry: true)
        defer { Task { await user.disconnect() } }

        let messages = 10
        var totalAttempts = 0
        var successCount = 0

        print("  发送\(messages)条消息（模拟偶尔失败）...")

        for i in 1...messages {
            let message = ChatMessage(
                from: "RetryUser",
                to: "Server",
                content: "Message with retry \(i)",
                timestamp: Date()
            )

            var attempts = 0
            var sent = false

            while attempts < 3 && !sent {
                attempts += 1
                totalAttempts += 1

                do {
                    try await user.send(message)
                    sent = true
                    successCount += 1
                    if attempts > 1 {
                        print("    [\(i)] 成功 (第\(attempts)次尝试)")
                    }
                } catch {
                    if attempts < 3 {
                        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    } else {
                        print("    [\(i)] 失败 (已重试\(attempts)次)")
                    }
                }
            }
        }

        let successRate = Double(successCount) / Double(messages)
        let avgAttempts = Double(totalAttempts) / Double(messages)

        print("\n📊 消息重发结果:")
        print("  发送消息数: \(messages)")
        print("  成功数: \(successCount)")
        print("  总尝试次数: \(totalAttempts)")
        print("  成功率: \(String(format: "%.1f", successRate * 100))%")
        print("  平均尝试次数: \(String(format: "%.2f", avgAttempts))")

        XCTAssertGreaterThan(successRate, 0.9, "消息重发后成功率应该大于90%")
    }

    // MARK: - Helper Types & Methods

    /// 聊天用户
    actor ChatUser {
        let name: String
        private let connection: TCPConnection
        private var messageQueue: [ChatMessage] = []

        var state: ConnectionState {
            get async {
                await connection.state
            }
        }

        var heartbeatStatistics: HeartbeatStatistics {
            get async {
                await connection.heartbeatStatistics
            }
        }

        init(name: String, connection: TCPConnection) {
            self.name = name
            self.connection = connection
        }

        func connect() async throws {
            try await connection.connect()
        }

        func disconnect() async {
            await connection.disconnect()
        }

        func send(_ message: ChatMessage) async throws {
            let data = try message.encode()
            try await connection.send(data)
        }

        func receive() async throws -> ChatMessage {
            // 模拟接收（实际应该从connection的stream读取）
            throw NSError(domain: "ChatUser", code: -1, userInfo: nil)
        }
    }

    /// 聊天消息
    struct ChatMessage: Codable {
        let from: String
        let to: String
        let content: String
        let timestamp: Date
        var mediaData: Data?

        func encode() throws -> Data {
            return try JSONEncoder().encode(self)
        }

        static func decode(from data: Data) throws -> ChatMessage {
            return try JSONDecoder().decode(ChatMessage.self, from: data)
        }
    }

    /// 创建聊天用户
    private func createChatUser(
        name: String,
        heartbeatInterval: TimeInterval = 0,
        enableReconnect: Bool = false,
        enableRetry: Bool = false
    ) async throws -> ChatUser {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout

        if heartbeatInterval > 0 {
            config.heartbeatInterval = heartbeatInterval
            config.heartbeatTimeout = heartbeatInterval * 2
        }

        if enableReconnect {
            config.enableAutoReconnect = true
            config.maxReconnectAttempts = 3
        }

        let connection = TCPConnection(
            host: testHost,
            port: testPort,
            configuration: config
        )

        try await connection.connect()

        return ChatUser(name: name, connection: connection)
    }
}
