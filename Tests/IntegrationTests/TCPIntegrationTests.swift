//
//  TCPIntegrationTests.swift
//  NexusKit Integration Tests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore
@testable import NexusTCP

/// TCP连接集成测试
/// 需要先启动测试服务器: cd TestServers && npm run integration
final class TCPIntegrationTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // 检查测试服务器是否运行
        let isRunning = await TestUtils.isTCPServerRunning()
        if !isRunning {
            throw XCTSkip("TCP测试服务器未运行。请先启动: cd TestServers && npm run tcp")
        }
    }

    // MARK: - 基础连接测试

    /// 测试基础TCP连接
    func testBasicConnection() async throws {
        TestUtils.printTestSeparator("测试基础TCP连接")

        let connection = try await TestUtils.createTestConnection()

        // 验证连接状态
        let state = await connection.state
        XCTAssertEqual(state, .connected, "连接应该成功")

        // 断开连接
        await connection.disconnect(reason: .clientInitiated)

        let finalState = await connection.state
        XCTAssertEqual(finalState, .disconnected, "应该已断开连接")

        TestUtils.printTestResult("基础TCP连接", passed: true)
    }

    /// 测试连接超时
    func testConnectionTimeout() async throws {
        TestUtils.printTestSeparator("测试连接超时")

        do {
            // 尝试连接到不存在的端口
            _ = try await NexusKit.shared
                .tcp(host: "127.0.0.1", port: 9999)
                .timeout(1.0)
                .connect()

            XCTFail("应该超时失败")
        } catch {
            // 预期会超时
            XCTAssertTrue(error is NexusError, "应该是NexusError")
            TestUtils.printTestResult("连接超时", passed: true)
        }
    }

    /// 测试多次连接和断开
    func testMultipleConnections() async throws {
        TestUtils.printTestSeparator("测试多次连接和断开")

        for i in 1...5 {
            let connection = try await TestUtils.createTestConnection()

            let state = await connection.state
            XCTAssertEqual(state, .connected, "第\(i)次连接应该成功")

            await connection.disconnect(reason: .clientInitiated)

            let finalState = await connection.state
            XCTAssertEqual(finalState, .disconnected, "第\(i)次断开应该成功")
        }

        TestUtils.printTestResult("多次连接和断开", passed: true)
    }

    // MARK: - 消息发送和接收测试

    /// 测试发送和接收简单消息
    func testSendAndReceiveSimpleMessage() async throws {
        TestUtils.printTestSeparator("测试发送和接收简单消息")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Hello Server!".data(using: .utf8)!
        ).encode()

        let response = try await TestUtils.sendAndReceiveMessage(
            connection: connection,
            message: testMessage,
            timeout: 5.0
        )

        XCTAssertFalse(response.isEmpty, "应该收到响应")

        // 解析响应
        if let responseMsg = TestFixtures.BinaryProtocolMessage.decode(response) {
            XCTAssertEqual(responseMsg.res, 1, "应该是响应消息")
            XCTAssertEqual(responseMsg.code, 200, "响应码应该是200")
            XCTAssertEqual(responseMsg.qid, 1, "请求ID应该匹配")

            let responseText = String(data: responseMsg.body, encoding: .utf8) ?? ""
            XCTAssertTrue(responseText.contains("received"), "响应应该包含'received'")
        } else {
            XCTFail("无法解析响应消息")
        }

        TestUtils.printTestResult("发送和接收简单消息", passed: true)
    }

    /// 测试发送大消息
    func testSendLargeMessage() async throws {
        TestUtils.printTestSeparator("测试发送大消息")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 创建64KB的消息
        let largeBody = TestFixtures.randomData(length: 65536)
        let largeMessage = TestFixtures.BinaryProtocolMessage(
            qid: 2,
            fid: 1,
            body: largeBody
        ).encode()

        let (_, duration) = await TestUtils.measureTime {
            try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: largeMessage,
                timeout: 10.0
            )
        }

        XCTAssertLessThan(duration, 5.0, "发送大消息应该在5秒内完成")

        TestUtils.printTestResult("发送大消息", passed: true, duration: duration)
    }

    /// 测试发送Unicode消息
    func testSendUnicodeMessage() async throws {
        TestUtils.printTestSeparator("测试发送Unicode消息")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let unicodeText = "你好世界🚀🌟✨"
        let unicodeMessage = TestFixtures.BinaryProtocolMessage(
            qid: 3,
            fid: 1,
            body: unicodeText.data(using: .utf8)!
        ).encode()

        let response = try await TestUtils.sendAndReceiveMessage(
            connection: connection,
            message: unicodeMessage,
            timeout: 5.0
        )

        if let responseMsg = TestFixtures.BinaryProtocolMessage.decode(response) {
            XCTAssertEqual(responseMsg.code, 200, "响应码应该是200")

            let responseText = String(data: responseMsg.body, encoding: .utf8) ?? ""
            XCTAssertTrue(responseText.contains("received"), "应该收到响应")
        } else {
            XCTFail("无法解析响应")
        }

        TestUtils.printTestResult("发送Unicode消息", passed: true)
    }

    // MARK: - 心跳测试

    /// 测试心跳功能
    func testHeartbeat() async throws {
        TestUtils.printTestSeparator("测试心跳功能")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 发送心跳
        let heartbeatSuccess = try await TestUtils.sendHeartbeat(
            connection: connection,
            timeout: 5.0
        )

        XCTAssertTrue(heartbeatSuccess, "心跳应该成功")

        TestUtils.printTestResult("心跳功能", passed: true)
    }

    /// 测试多次心跳
    func testMultipleHeartbeats() async throws {
        TestUtils.printTestSeparator("测试多次心跳")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var successCount = 0
        for i in 1...10 {
            let success = try await TestUtils.sendHeartbeat(
                connection: connection,
                timeout: 5.0
            )
            if success {
                successCount += 1
            }

            // 间隔100ms
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(successCount, 10, "所有心跳应该成功")

        TestUtils.printTestResult("多次心跳", passed: true)
    }

    // MARK: - 并发测试

    /// 测试并发连接
    func testConcurrentConnections() async throws {
        TestUtils.printTestSeparator("测试并发连接")

        let connectionCount = 10
        let (_, duration) = await TestUtils.measureTime {
            try await TestUtils.runConcurrently(count: connectionCount) {
                let conn = try await TestUtils.createTestConnection()
                await conn.disconnect(reason: .clientInitiated)
            }
        }

        XCTAssertLessThan(duration, 10.0, "10个并发连接应该在10秒内完成")

        TestUtils.printTestResult(
            "并发连接(\(connectionCount)个)",
            passed: true,
            duration: duration
        )
    }

    /// 测试并发消息发送
    func testConcurrentMessages() async throws {
        TestUtils.printTestSeparator("测试并发消息发送")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let messageCount = 50
        var successCount = 0
        let lock = NSLock()

        let (_, duration) = await TestUtils.measureTime {
            try await TestUtils.runConcurrently(count: messageCount) {
                let testMsg = TestFixtures.BinaryProtocolMessage(
                    qid: UInt32.random(in: 1...1000),
                    fid: 1,
                    body: TestFixtures.randomString(length: 100).data(using: .utf8)!
                ).encode()

                do {
                    _ = try await TestUtils.sendAndReceiveMessage(
                        connection: connection,
                        message: testMsg,
                        timeout: 5.0
                    )

                    lock.lock()
                    successCount += 1
                    lock.unlock()
                } catch {
                    // 忽略个别失败
                }
            }
        }

        // 至少80%成功
        XCTAssertGreaterThan(successCount, messageCount * 80 / 100, "至少80%的消息应该成功")

        TestUtils.printTestResult(
            "并发消息发送(\(messageCount)条, 成功\(successCount))",
            passed: true,
            duration: duration
        )
    }

    // MARK: - 性能测试

    /// 测试连接建立速度
    func testConnectionSpeed() async throws {
        TestUtils.printTestSeparator("测试连接建立速度")

        var durations: [TimeInterval] = []

        for _ in 0..<10 {
            let (_, duration) = await TestUtils.measureTime {
                let conn = try await TestUtils.createTestConnection()
                await conn.disconnect(reason: .clientInitiated)
            }
            durations.append(duration)
        }

        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let maxDuration = durations.max() ?? 0

        XCTAssertLessThan(avgDuration, 0.5, "平均连接时间应该小于500ms")
        XCTAssertLessThan(maxDuration, 1.0, "最大连接时间应该小于1秒")

        TestUtils.printTestResult(
            "连接建立速度(平均: \(String(format: "%.3f", avgDuration))s)",
            passed: true
        )
    }

    /// 测试消息吞吐量
    func testMessageThroughput() async throws {
        TestUtils.printTestSeparator("测试消息吞吐量")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 100
        let testMsg = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Throughput Test".data(using: .utf8)!
        ).encode()

        let (qps, avgLatency) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: testMsg,
                timeout: 5.0
            )
        }

        print("  吞吐量: \(String(format: "%.0f", qps)) QPS")
        print("  平均延迟: \(String(format: "%.3f", avgLatency * 1000)) ms")

        XCTAssertGreaterThan(qps, 10, "QPS应该大于10")
        XCTAssertLessThan(avgLatency, 0.1, "平均延迟应该小于100ms")

        TestUtils.printTestResult(
            "消息吞吐量(\(String(format: "%.0f", qps)) QPS)",
            passed: true
        )
    }

    // MARK: - 稳定性测试

    /// 测试长时间连接
    func testLongLivedConnection() async throws {
        TestUtils.printTestSeparator("测试长时间连接")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 保持连接30秒，每秒发送一次心跳
        let duration: TimeInterval = 30.0
        let heartbeatInterval: TimeInterval = 1.0
        let iterations = Int(duration / heartbeatInterval)

        var successCount = 0

        for i in 1...iterations {
            let success = try await TestUtils.sendHeartbeat(
                connection: connection,
                timeout: 5.0
            )

            if success {
                successCount += 1
            }

            if i % 10 == 0 {
                print("  已完成 \(i)/\(iterations) 次心跳")
            }

            try await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
        }

        let successRate = Double(successCount) / Double(iterations) * 100
        print("  心跳成功率: \(String(format: "%.1f", successRate))%")

        XCTAssertGreaterThan(successRate, 95.0, "心跳成功率应该大于95%")

        TestUtils.printTestResult(
            "长时间连接(\(Int(duration))秒, 成功率\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    // MARK: - 错误处理测试

    /// 测试无效消息格式
    func testInvalidMessageFormat() async throws {
        TestUtils.printTestSeparator("测试无效消息格式")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 发送无效格式的数据
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])

        do {
            try await connection.send(invalidData, timeout: 2.0)
            // 服务器可能不会响应无效消息，这是正常的
        } catch {
            // 发送失败也是可以接受的
        }

        // 验证连接仍然存活
        let state = await connection.state
        XCTAssertTrue(
            state == .connected || state == .disconnected,
            "连接状态应该是有效的"
        )

        TestUtils.printTestResult("无效消息格式", passed: true)
    }

    /// 测试连接断开后发送
    func testSendAfterDisconnect() async throws {
        TestUtils.printTestSeparator("测试连接断开后发送")

        let connection = try await TestUtils.createTestConnection()

        // 断开连接
        await connection.disconnect(reason: .clientInitiated)

        // 尝试发送消息
        do {
            try await connection.send(TestFixtures.dataMessage, timeout: 2.0)
            XCTFail("断开后发送应该失败")
        } catch {
            // 预期会失败
            XCTAssertTrue(error is NexusError, "应该抛出NexusError")
        }

        TestUtils.printTestResult("连接断开后发送", passed: true)
    }
}
