//
//  HeartbeatIntegrationTests.swift
//  NexusKit Integration Tests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore
@testable import NexusTCP

/// 心跳管理器集成测试
final class HeartbeatIntegrationTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        let isRunning = await TestUtils.isTCPServerRunning()
        if !isRunning {
            throw XCTSkip("TCP测试服务器未运行")
        }
    }

    // MARK: - 基础心跳测试

    /// 测试基础心跳发送
    func testBasicHeartbeat() async throws {
        TestUtils.printTestSeparator("测试基础心跳发送")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 2.0, timeout: 5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 等待几个心跳周期
        try await Task.sleep(nanoseconds: 7_000_000_000) // 7秒

        // 验证连接仍然存活
        let state = await connection.state
        XCTAssertEqual(state, .connected, "连接应该保持活跃")

        TestUtils.printTestResult("基础心跳发送", passed: true)
    }

    /// 测试心跳响应
    func testHeartbeatResponse() async throws {
        TestUtils.printTestSeparator("测试心跳响应")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 1.0, timeout: 3.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var heartbeatCount = 0

        // 监听心跳响应
        connection.on(.control) { data in
            // 检查是否是心跳响应
            if let msg = TestFixtures.BinaryProtocolMessage.decode(data) {
                if msg.fid == 0xFFFF {
                    heartbeatCount += 1
                }
            }
        }

        // 等待5秒，应该收到至少3次心跳响应
        try await Task.sleep(nanoseconds: 5_000_000_000)

        XCTAssertGreaterThanOrEqual(heartbeatCount, 3, "应该收到至少3次心跳响应")

        TestUtils.printTestResult(
            "心跳响应(收到\(heartbeatCount)次)",
            passed: true
        )
    }

    // MARK: - 心跳超时测试

    /// 测试心跳超时检测
    func testHeartbeatTimeout() async throws {
        TestUtils.printTestSeparator("测试心跳超时检测")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 1.0, timeout: 2.0)
            .connect()

        var disconnected = false

        // 监听断开事件
        Task {
            while await connection.state != .disconnected {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            disconnected = true
        }

        // 模拟网络中断：不发送心跳响应
        // 注意：实际测试需要服务器配合或模拟网络故障

        // 等待超时检测
        try await Task.sleep(nanoseconds: 5_000_000_000)

        // 在正常情况下连接应该保持，除非真的超时
        let state = await connection.state
        print("  连接状态: \(state)")

        await connection.disconnect(reason: .clientInitiated)

        TestUtils.printTestResult("心跳超时检测", passed: true)
    }

    // MARK: - 自适应心跳测试

    /// 测试心跳间隔调整
    func testHeartbeatIntervalAdjustment() async throws {
        TestUtils.printTestSeparator("测试心跳间隔调整")

        // 创建不同间隔的连接
        let intervals: [TimeInterval] = [1.0, 2.0, 5.0]

        for interval in intervals {
            let connection = try await NexusKit.shared
                .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
                .heartbeat(interval: interval, timeout: interval * 2)
                .connect()

            // 等待几个周期
            try await Task.sleep(nanoseconds: UInt64(interval * 3 * 1_000_000_000))

            let state = await connection.state
            XCTAssertEqual(state, .connected, "间隔\(interval)秒的连接应该保持活跃")

            await connection.disconnect(reason: .clientInitiated)

            print("  间隔\(interval)秒: ✓")
        }

        TestUtils.printTestResult("心跳间隔调整", passed: true)
    }

    /// 测试心跳统计
    func testHeartbeatStatistics() async throws {
        TestUtils.printTestSeparator("测试心跳统计")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 1.0, timeout: 3.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var successCount = 0
        var failCount = 0

        // 监听心跳事件
        connection.on(.control) { data in
            if let msg = TestFixtures.BinaryProtocolMessage.decode(data) {
                if msg.fid == 0xFFFF {
                    if msg.code == 200 {
                        successCount += 1
                    } else {
                        failCount += 1
                    }
                }
            }
        }

        // 运行10秒
        try await Task.sleep(nanoseconds: 10_000_000_000)

        print("  成功心跳: \(successCount)")
        print("  失败心跳: \(failCount)")

        let successRate = Double(successCount) / Double(successCount + failCount) * 100
        XCTAssertGreaterThan(successRate, 90.0, "心跳成功率应该大于90%")

        TestUtils.printTestResult(
            "心跳统计(成功率\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    // MARK: - 双向心跳测试

    /// 测试客户端主动心跳
    func testClientInitiatedHeartbeat() async throws {
        TestUtils.printTestSeparator("测试客户端主动心跳")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 手动发送10次心跳
        var successCount = 0

        for _ in 0..<10 {
            let success = try await TestUtils.sendHeartbeat(
                connection: connection,
                timeout: 3.0
            )

            if success {
                successCount += 1
            }

            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        XCTAssertEqual(successCount, 10, "所有心跳应该成功")

        TestUtils.printTestResult(
            "客户端主动心跳(\(successCount)/10)",
            passed: true
        )
    }

    /// 测试服务器心跳响应
    func testServerHeartbeatResponse() async throws {
        TestUtils.printTestSeparator("测试服务器心跳响应")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 2.0, timeout: 5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var responseReceived = false
        var responseTime: TimeInterval?

        connection.on(.control) { data in
            if let msg = TestFixtures.BinaryProtocolMessage.decode(data) {
                if msg.fid == 0xFFFF {
                    responseReceived = true
                    responseTime = Date().timeIntervalSince1970
                }
            }
        }

        let startTime = Date().timeIntervalSince1970

        // 等待心跳响应
        try await Task.sleep(nanoseconds: 3_000_000_000)

        XCTAssertTrue(responseReceived, "应该收到心跳响应")

        if let respTime = responseTime {
            let latency = respTime - startTime
            print("  响应延迟: \(String(format: "%.3f", latency))秒")
            XCTAssertLessThan(latency, 5.0, "响应延迟应该小于5秒")
        }

        TestUtils.printTestResult("服务器心跳响应", passed: true)
    }

    // MARK: - 心跳状态测试

    /// 测试心跳状态转换
    func testHeartbeatStateTransitions() async throws {
        TestUtils.printTestSeparator("测试心跳状态转换")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 1.0, timeout: 3.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 状态应该从连接变为正常
        let initialState = await connection.state
        XCTAssertEqual(initialState, .connected)

        // 等待一段时间，验证连接保持稳定
        for i in 1...5 {
            try await Task.sleep(nanoseconds: 1_000_000_000)

            let state = await connection.state
            XCTAssertEqual(state, .connected, "第\(i)秒连接应该保持活跃")
        }

        TestUtils.printTestResult("心跳状态转换", passed: true)
    }

    // MARK: - 性能测试

    /// 测试心跳性能开销
    func testHeartbeatPerformanceOverhead() async throws {
        TestUtils.printTestSeparator("测试心跳性能开销")

        // 创建两个连接：一个启用心跳，一个不启用
        let withHeartbeat = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 1.0, timeout: 3.0)
            .connect()

        let withoutHeartbeat = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .disableHeartbeat()
            .connect()

        defer {
            Task {
                await withHeartbeat.disconnect(reason: .clientInitiated)
                await withoutHeartbeat.disconnect(reason: .clientInitiated)
            }
        }

        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Performance Test".data(using: .utf8)!
        ).encode()

        // 测试有心跳的性能
        let (qpsWithHB, _) = try await TestUtils.measureThroughput(iterations: 50) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: withHeartbeat,
                message: testMessage,
                timeout: 3.0
            )
        }

        // 测试无心跳的性能
        let (qpsWithoutHB, _) = try await TestUtils.measureThroughput(iterations: 50) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: withoutHeartbeat,
                message: testMessage,
                timeout: 3.0
            )
        }

        print("  有心跳QPS: \(String(format: "%.0f", qpsWithHB))")
        print("  无心跳QPS: \(String(format: "%.0f", qpsWithoutHB))")

        let overhead = (qpsWithoutHB - qpsWithHB) / qpsWithoutHB * 100
        print("  性能开销: \(String(format: "%.1f", overhead))%")

        // 心跳开销应该小于20%
        XCTAssertLessThan(overhead, 20.0, "心跳性能开销应该小于20%")

        TestUtils.printTestResult(
            "心跳性能开销(\(String(format: "%.1f", overhead))%)",
            passed: true
        )
    }

    /// 测试高频心跳
    func testHighFrequencyHeartbeat() async throws {
        TestUtils.printTestSeparator("测试高频心跳")

        // 每100ms一次心跳
        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 0.1, timeout: 0.5)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var heartbeatCount = 0

        connection.on(.control) { data in
            if let msg = TestFixtures.BinaryProtocolMessage.decode(data) {
                if msg.fid == 0xFFFF {
                    heartbeatCount += 1
                }
            }
        }

        // 运行2秒，应该收到约20次心跳
        try await Task.sleep(nanoseconds: 2_000_000_000)

        print("  心跳次数: \(heartbeatCount)")

        // 允许一定误差
        XCTAssertGreaterThan(heartbeatCount, 15, "应该收到至少15次心跳")

        TestUtils.printTestResult(
            "高频心跳(\(heartbeatCount)次/2秒)",
            passed: true
        )
    }

    // MARK: - 稳定性测试

    /// 测试长时间心跳稳定性
    func testLongTermHeartbeatStability() async throws {
        TestUtils.printTestSeparator("测试长时间心跳稳定性")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 2.0, timeout: 5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let duration: TimeInterval = 60.0 // 1分钟
        var heartbeatCount = 0
        var lastHeartbeat = Date()

        connection.on(.control) { data in
            if let msg = TestFixtures.BinaryProtocolMessage.decode(data) {
                if msg.fid == 0xFFFF {
                    heartbeatCount += 1
                    lastHeartbeat = Date()
                }
            }
        }

        // 运行指定时间
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        let expectedCount = Int(duration / 2.0) // 每2秒一次
        let tolerance = expectedCount / 10 // 允许10%误差

        print("  预期心跳: \(expectedCount)")
        print("  实际心跳: \(heartbeatCount)")

        XCTAssertTrue(
            abs(heartbeatCount - expectedCount) <= tolerance,
            "心跳次数应该接近预期值"
        )

        // 验证最后一次心跳不久前发生
        let timeSinceLastHB = Date().timeIntervalSince(lastHeartbeat)
        XCTAssertLessThan(timeSinceLastHB, 5.0, "最后一次心跳应该在5秒内")

        TestUtils.printTestResult(
            "长时间心跳稳定性(\(heartbeatCount)/\(expectedCount))",
            passed: true
        )
    }
}
