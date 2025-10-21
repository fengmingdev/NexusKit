//
//  TCPIntegrationTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusKit

/// TCP集成测试套件
///
/// 测试TCP连接、消息收发、心跳、并发、性能等功能
///
/// **前置条件**: 启动 TestServers/tcp_server.js (端口 8888)
/// ```bash
/// cd TestServers
/// npm run tcp
/// ```
///
/// **测试覆盖**:
/// - 基础连接测试 (连接/断开/超时/多次连接)
/// - 消息收发测试 (简单/大消息/Unicode)
/// - 心跳测试 (单次/多次)
/// - 并发测试 (并发连接/并发消息)
/// - 性能测试 (连接速度/消息吞吐量)
/// - 稳定性测试 (长时间连接)
/// - 错误处理测试 (无效消息/断开后发送)
///
@available(iOS 13.0, macOS 10.15, *)
final class TCPIntegrationTests: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8888
    private let connectionTimeout: TimeInterval = 5.0

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        // 等待服务器准备就绪
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }

    override func tearDown() async throws {
        // 清理所有连接
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        try await super.tearDown()
    }

    // MARK: - 1. 基础连接测试 (4个测试)

    /// 测试1.1: 基本TCP连接建立和断开
    func testBasicConnection() async throws {
        let connection = try await createConnection()

        // 验证连接状态
        let state = await connection.state
        XCTAssertEqual(state, .connected, "连接应该处于connected状态")

        // 断开连接
        await connection.disconnect()

        // 验证断开状态
        let disconnectedState = await connection.state
        XCTAssertEqual(disconnectedState, .disconnected, "连接应该处于disconnected状态")
    }

    /// 测试1.2: 连接超时处理
    func testConnectionTimeout() async throws {
        // 使用无效端口测试超时
        let invalidPort: UInt16 = 9999

        do {
            _ = try await createConnection(port: invalidPort, timeout: 2.0)
            XCTFail("应该抛出超时错误")
        } catch {
            // 预期会超时或连接失败
            XCTAssertTrue(error is NexusError || error is ConnectionError,
                         "应该是连接错误: \(error)")
        }
    }

    /// 测试1.3: 多次连接同一服务器
    func testMultipleConnections() async throws {
        let connection1 = try await createConnection()
        let connection2 = try await createConnection()
        let connection3 = try await createConnection()

        // 验证所有连接都成功
        let state1 = await connection1.state
        let state2 = await connection2.state
        let state3 = await connection3.state

        XCTAssertEqual(state1, .connected)
        XCTAssertEqual(state2, .connected)
        XCTAssertEqual(state3, .connected)

        // 清理
        await connection1.disconnect()
        await connection2.disconnect()
        await connection3.disconnect()
    }

    /// 测试1.4: 连接后立即断开
    func testImmediateDisconnect() async throws {
        let connection = try await createConnection()

        // 立即断开
        await connection.disconnect()

        let state = await connection.state
        XCTAssertEqual(state, .disconnected)
    }

    // MARK: - 2. 消息收发测试 (4个测试)

    /// 测试2.1: 发送和接收简单消息
    func testSimpleMessageSendReceive() async throws {
        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let testMessage = "Hello from NexusKit!"
        let testData = testMessage.data(using: .utf8)!

        // 发送消息
        try await connection.send(testData)

        // 接收回显消息
        let received = try await receiveMessage(from: connection, timeout: 5.0)

        // 验证回显
        let receivedString = String(data: received, encoding: .utf8)
        XCTAssertEqual(receivedString, testMessage, "应该接收到回显消息")
    }

    /// 测试2.2: 发送大消息 (1MB)
    func testLargeMessageSendReceive() async throws {
        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        // 创建1MB测试数据
        let size = 1024 * 1024 // 1MB
        let testData = Data(repeating: 0x42, count: size)

        // 发送大消息
        let sendStart = Date()
        try await connection.send(testData)
        let sendDuration = Date().timeIntervalSince(sendStart)

        print("📊 发送1MB数据耗时: \(String(format: "%.2f", sendDuration * 1000))ms")

        // 接收回显 (可能需要拼接多个数据包)
        let received = try await receiveMessage(from: connection, timeout: 10.0, expectedSize: size)

        // 验证数据
        XCTAssertEqual(received.count, testData.count, "接收数据大小应该匹配")
        XCTAssertEqual(received, testData, "接收数据内容应该匹配")
    }

    /// 测试2.3: 发送Unicode消息
    func testUnicodeMessageSendReceive() async throws {
        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let unicodeMessage = "你好世界! 🚀 Hello World! こんにちは世界!"
        let testData = unicodeMessage.data(using: .utf8)!

        // 发送消息
        try await connection.send(testData)

        // 接收回显
        let received = try await receiveMessage(from: connection, timeout: 5.0)
        let receivedString = String(data: received, encoding: .utf8)

        XCTAssertEqual(receivedString, unicodeMessage, "Unicode消息应该正确传输")
    }

    /// 测试2.4: 连续发送多条消息
    func testMultipleMessages() async throws {
        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let messageCount = 10
        var receivedCount = 0

        for i in 1...messageCount {
            let message = "Message \(i)"
            let data = message.data(using: .utf8)!

            // 发送消息
            try await connection.send(data)

            // 接收回显
            let received = try await receiveMessage(from: connection, timeout: 5.0)
            let receivedString = String(data: received, encoding: .utf8)

            XCTAssertEqual(receivedString, message, "第\(i)条消息应该正确接收")
            receivedCount += 1
        }

        XCTAssertEqual(receivedCount, messageCount, "应该接收到所有消息")
    }

    // MARK: - 3. 心跳测试 (2个测试)

    /// 测试3.1: 单次心跳发送和响应
    func testSingleHeartbeat() async throws {
        let connection = try await createConnection(enableHeartbeat: true)
        defer { Task { await connection.disconnect() } }

        // 等待心跳发送
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2秒

        // 验证连接仍然活跃
        let state = await connection.state
        XCTAssertEqual(state, .connected, "心跳后连接应该保持连接")
    }

    /// 测试3.2: 多次心跳测试
    func testMultipleHeartbeats() async throws {
        let connection = try await createConnection(enableHeartbeat: true, heartbeatInterval: 1.0)
        defer { Task { await connection.disconnect() } }

        // 等待多次心跳
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5秒，应该发送约5次心跳

        // 验证连接稳定
        let state = await connection.state
        XCTAssertEqual(state, .connected, "多次心跳后连接应该保持稳定")
    }

    // MARK: - 4. 并发测试 (2个测试)

    /// 测试4.1: 并发建立多个连接
    func testConcurrentConnections() async throws {
        let connectionCount = 10

        let connections = try await withThrowingTaskGroup(of: TCPConnection.self) { group in
            for _ in 1...connectionCount {
                group.addTask {
                    try await self.createConnection()
                }
            }

            var results: [TCPConnection] = []
            for try await connection in group {
                results.append(connection)
            }
            return results
        }

        // 验证所有连接成功
        XCTAssertEqual(connections.count, connectionCount, "应该成功建立所有连接")

        for connection in connections {
            let state = await connection.state
            XCTAssertEqual(state, .connected, "每个连接都应该处于连接状态")
        }

        // 清理
        for connection in connections {
            await connection.disconnect()
        }
    }

    /// 测试4.2: 并发发送消息
    func testConcurrentMessages() async throws {
        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let messageCount = 20

        // 并发发送消息
        try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 1...messageCount {
                group.addTask {
                    let message = "Concurrent message \(i)"
                    let data = message.data(using: .utf8)!
                    try await connection.send(data)
                    return i
                }
            }

            var sentCount = 0
            for try await _ in group {
                sentCount += 1
            }

            XCTAssertEqual(sentCount, messageCount, "应该成功发送所有消息")
        }

        // 等待所有回显
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
    }

    // MARK: - 5. 性能测试 (2个测试)

    /// 测试5.1: 连接建立速度
    func testConnectionSpeed() async throws {
        let iterations = 5
        var totalDuration: TimeInterval = 0

        for _ in 1...iterations {
            let start = Date()
            let connection = try await createConnection()
            let duration = Date().timeIntervalSince(start)
            totalDuration += duration

            await connection.disconnect()

            // 等待端口释放
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let averageDuration = totalDuration / Double(iterations)
        print("📊 平均连接建立时间: \(String(format: "%.2f", averageDuration * 1000))ms")

        // 性能要求: 平均连接时间 < 500ms
        XCTAssertLessThan(averageDuration, 0.5, "平均连接建立时间应该小于500ms")
    }

    /// 测试5.2: 消息吞吐量测试
    func testMessageThroughput() async throws {
        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let messageCount = 50
        let messageSize = 1024 // 1KB per message
        let testData = Data(repeating: 0x41, count: messageSize)

        let start = Date()

        // 发送消息
        for _ in 1...messageCount {
            try await connection.send(testData)
        }

        let duration = Date().timeIntervalSince(start)
        let throughput = Double(messageCount) / duration // messages/second
        let dataRate = Double(messageCount * messageSize) / duration / 1024 // KB/s

        print("📊 消息吞吐量: \(String(format: "%.2f", throughput)) QPS")
        print("📊 数据速率: \(String(format: "%.2f", dataRate)) KB/s")

        // 性能要求: QPS > 10
        XCTAssertGreaterThan(throughput, 10, "消息吞吐量应该大于10 QPS")
    }

    // MARK: - 6. 稳定性测试 (1个测试)

    /// 测试6.1: 长时间连接稳定性 (30秒)
    func testLongLivedConnection() async throws {
        let connection = try await createConnection(enableHeartbeat: true, heartbeatInterval: 5.0)
        defer { Task { await connection.disconnect() } }

        let duration: TimeInterval = 30.0 // 30秒
        let checkInterval: TimeInterval = 5.0 // 每5秒检查一次
        let iterations = Int(duration / checkInterval)

        var successCount = 0

        for i in 1...iterations {
            // 等待
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))

            // 检查连接状态
            let state = await connection.state
            if state == .connected {
                successCount += 1

                // 发送测试消息
                let testMessage = "Stability check \(i)"
                let data = testMessage.data(using: .utf8)!
                try await connection.send(data)

                print("✅ 第\(i)次稳定性检查通过 (\(i * Int(checkInterval))秒)")
            } else {
                print("❌ 第\(i)次稳定性检查失败: 连接状态为 \(state)")
            }
        }

        let successRate = Double(successCount) / Double(iterations)
        print("📊 长连接稳定性: \(String(format: "%.1f", successRate * 100))%")

        // 要求: 稳定性 > 90%
        XCTAssertGreaterThan(successRate, 0.9, "长连接稳定性应该大于90%")
    }

    // MARK: - 7. 错误处理测试 (2个测试)

    /// 测试7.1: 发送无效数据
    func testSendInvalidData() async throws {
        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        // 发送空数据
        let emptyData = Data()

        do {
            try await connection.send(emptyData)
            // 某些实现可能允许发送空数据，所以不一定会抛出错误
        } catch {
            // 如果抛出错误，应该是合理的错误类型
            XCTAssertTrue(error is NexusError || error is ConnectionError)
        }
    }

    /// 测试7.2: 断开后尝试发送
    func testSendAfterDisconnect() async throws {
        let connection = try await createConnection()

        // 断开连接
        await connection.disconnect()

        // 尝试发送数据
        let testData = "Test".data(using: .utf8)!

        do {
            try await connection.send(testData)
            XCTFail("断开连接后发送应该失败")
        } catch {
            // 应该抛出连接错误
            XCTAssertTrue(error is NexusError || error is ConnectionError,
                         "应该是连接错误")
        }
    }

    // MARK: - Helper Methods

    /// 创建TCP连接
    private func createConnection(
        host: String? = nil,
        port: UInt16? = nil,
        timeout: TimeInterval? = nil,
        enableHeartbeat: Bool = false,
        heartbeatInterval: TimeInterval = 30.0
    ) async throws -> TCPConnection {
        let actualHost = host ?? testHost
        let actualPort = port ?? testPort
        let actualTimeout = timeout ?? connectionTimeout

        var config = TCPConfiguration()
        config.timeout = actualTimeout

        if enableHeartbeat {
            config.heartbeatInterval = heartbeatInterval
            config.heartbeatTimeout = heartbeatInterval * 2
        }

        let connection = TCPConnection(
            host: actualHost,
            port: actualPort,
            configuration: config
        )

        try await connection.connect()
        return connection
    }

    /// 接收消息（带超时）
    private func receiveMessage(
        from connection: TCPConnection,
        timeout: TimeInterval,
        expectedSize: Int? = nil
    ) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var receivedData = Data()

        // 使用AsyncStream接收数据
        let stream = await connection.dataStream

        for await data in stream {
            receivedData.append(data)

            // 如果指定了期望大小，检查是否已接收完整
            if let expectedSize = expectedSize, receivedData.count >= expectedSize {
                break
            }

            // 对于普通消息，假设一次接收完整（根据服务器实现）
            if expectedSize == nil {
                break
            }

            // 检查超时
            if Date() > deadline {
                throw NSError(
                    domain: "TCPIntegrationTests",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "接收消息超时"]
                )
            }
        }

        guard !receivedData.isEmpty else {
            throw NSError(
                domain: "TCPIntegrationTests",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "未接收到数据"]
            )
        }

        return receivedData
    }

    /// 生成测试数据
    private func generateTestData(size: Int, pattern: String = "Test") -> Data {
        let patternData = pattern.data(using: .utf8)!
        var result = Data()

        while result.count < size {
            result.append(patternData)
        }

        return result.prefix(size)
    }
}

// MARK: - Mock Types (如果实际类型不存在)

#if DEBUG
// 如果TCPConnection还未实现，提供模拟实现用于编译

/// TCP连接状态
enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

/// TCP配置
struct TCPConfiguration {
    var timeout: TimeInterval = 10.0
    var heartbeatInterval: TimeInterval = 30.0
    var heartbeatTimeout: TimeInterval = 60.0
}

/// TCP连接错误
enum ConnectionError: Error {
    case timeout
    case connectionFailed
    case disconnected
}

/// 模拟TCP连接（如果实际实现不存在）
actor TCPConnection {
    private let host: String
    private let port: UInt16
    private let configuration: TCPConfiguration
    private var _state: ConnectionState = .disconnected
    private var dataStreamContinuation: AsyncStream<Data>.Continuation?

    var state: ConnectionState {
        _state
    }

    var dataStream: AsyncStream<Data> {
        AsyncStream { continuation in
            self.dataStreamContinuation = continuation
        }
    }

    init(host: String, port: UInt16, configuration: TCPConfiguration) {
        self.host = host
        self.port = port
        self.configuration = configuration
    }

    func connect() async throws {
        // 模拟实现
        _state = .connecting
        try await Task.sleep(nanoseconds: 100_000_000)
        _state = .connected
    }

    func disconnect() {
        _state = .disconnected
        dataStreamContinuation?.finish()
    }

    func send(_ data: Data) async throws {
        guard _state == .connected else {
            throw ConnectionError.disconnected
        }
        // 模拟发送
    }
}
#endif
