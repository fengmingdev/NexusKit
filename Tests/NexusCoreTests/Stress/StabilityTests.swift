//
//  StabilityTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusKit

/// 稳定性测试套件
///
/// 测试系统长时间运行的稳定性，包括内存泄漏、连接稳定性、性能衰减等
///
/// **前置条件**: 启动测试服务器
/// ```bash
/// cd TestServers
/// npm run integration
/// ```
///
/// **测试覆盖**:
/// - 1小时长连接稳定性测试
/// - 1小时循环重连测试
/// - 内存稳定性测试（检测泄漏）
/// - 性能衰减测试
/// - 资源释放测试
///
/// **注意**: 这些测试耗时较长，建议单独运行
///
@available(iOS 13.0, macOS 10.15, *)
final class StabilityTests: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8888
    private let connectionTimeout: TimeInterval = 10.0

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        try await Task.sleep(nanoseconds: 500_000_000)
        print("\n" + String(repeating: "=", count: 60))
        print("⏱️  开始稳定性测试")
        print(String(repeating: "=", count: 60))
    }

    override func tearDown() async throws {
        print(String(repeating: "=", count: 60))
        print("✅ 稳定性测试完成")
        print(String(repeating: "=", count: 60) + "\n")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await super.tearDown()
    }

    // MARK: - 1. 长连接稳定性测试

    /// 测试1.1: 1小时单连接稳定性
    func testOneHourSingleConnectionStability() async throws {
        let testDuration: TimeInterval = 3600 // 1小时
        let checkInterval: TimeInterval = 60 // 每分钟检查一次
        let heartbeatInterval: TimeInterval = 30

        print("\n📊 测试: 1小时单连接稳定性")
        print("  测试时长: \(Int(testDuration / 60))分钟")
        print("  检查间隔: \(Int(checkInterval))秒")
        print("  心跳间隔: \(Int(heartbeatInterval))秒")

        // 创建连接
        let connection = try await createConnection(heartbeatInterval: heartbeatInterval)
        let startTime = Date()
        let memoryAtStart = getMemoryUsage()

        var checkResults: [(minute: Int, state: Bool, memory: Double, latency: TimeInterval)] = []
        var totalMessages = 0
        var failedMessages = 0

        let iterations = Int(testDuration / checkInterval)

        for iteration in 1...iterations {
            // 等待到下一个检查点
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))

            let currentMinute = iteration
            let elapsedTime = Date().timeIntervalSince(startTime)
            let currentMemory = getMemoryUsage()

            // 检查连接状态
            let state = await connection.state
            let isConnected = (state == .connected)

            // 发送测试消息并测量延迟
            let testData = "Stability check \(iteration)".data(using: .utf8)!
            let sendStart = Date()
            var latency: TimeInterval = 0

            do {
                try await connection.send(testData)
                totalMessages += 1
                latency = Date().timeIntervalSince(sendStart)
            } catch {
                failedMessages += 1
                print("  ⚠️ 第\(currentMinute)分钟: 发送失败 - \(error)")
            }

            checkResults.append((
                minute: currentMinute,
                state: isConnected,
                memory: currentMemory,
                latency: latency
            ))

            // 每10分钟输出一次详细报告
            if currentMinute % 10 == 0 {
                let memoryIncrease = currentMemory - memoryAtStart
                let successRate = Double(totalMessages - failedMessages) / Double(totalMessages)

                print("\n  📊 第\(currentMinute)分钟检查点:")
                print("    运行时间: \(String(format: "%.1f", elapsedTime / 60))分钟")
                print("    连接状态: \(isConnected ? "✅ 连接" : "❌ 断开")")
                print("    内存: \(String(format: "%.2f", currentMemory))MB (增长: \(String(format: "%.2f", memoryIncrease))MB)")
                print("    消息成功率: \(String(format: "%.2f", successRate * 100))%")
                print("    当前延迟: \(String(format: "%.2f", latency * 1000))ms")
            } else {
                print("  ✓ 第\(currentMinute)分钟: 状态OK, 内存=\(String(format: "%.1f", currentMemory))MB")
            }
        }

        await connection.disconnect()

        let finalMemory = getMemoryUsage()
        let totalMemoryIncrease = finalMemory - memoryAtStart

        // 分析结果
        let connectedCount = checkResults.filter { $0.state }.count
        let stabilityRate = Double(connectedCount) / Double(checkResults.count)

        let memoryValues = checkResults.map { $0.memory }
        let avgMemory = memoryValues.reduce(0, +) / Double(memoryValues.count)
        let maxMemory = memoryValues.max() ?? 0

        let latencies = checkResults.filter { $0.latency > 0 }.map { $0.latency }
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        let maxLatency = latencies.max() ?? 0

        let messageSuccessRate = Double(totalMessages - failedMessages) / Double(totalMessages)

        print("\n📊 1小时稳定性测试结果:")
        print("  测试时长: \(String(format: "%.1f", testDuration / 60))分钟")
        print("  检查次数: \(checkResults.count)")
        print("  连接稳定率: \(String(format: "%.2f", stabilityRate * 100))%")
        print("  消息成功率: \(String(format: "%.2f", messageSuccessRate * 100))%")
        print("  总消息数: \(totalMessages)")
        print("  失败消息数: \(failedMessages)")
        print("\n  内存统计:")
        print("    起始内存: \(String(format: "%.2f", memoryAtStart))MB")
        print("    平均内存: \(String(format: "%.2f", avgMemory))MB")
        print("    峰值内存: \(String(format: "%.2f", maxMemory))MB")
        print("    最终内存: \(String(format: "%.2f", finalMemory))MB")
        print("    总增长: \(String(format: "%.2f", totalMemoryIncrease))MB")
        print("\n  性能统计:")
        print("    平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("    最大延迟: \(String(format: "%.2f", maxLatency * 1000))ms")

        // 稳定性要求
        XCTAssertGreaterThan(stabilityRate, 0.95, "1小时连接稳定率应该大于95%")
        XCTAssertGreaterThan(messageSuccessRate, 0.98, "消息成功率应该大于98%")
        XCTAssertLessThan(totalMemoryIncrease, 100.0, "1小时内存增长应该小于100MB")
        XCTAssertLessThan(avgLatency, 0.1, "平均延迟应该小于100ms")
    }

    /// 测试1.2: 1小时多连接稳定性
    func testOneHourMultipleConnectionsStability() async throws {
        let testDuration: TimeInterval = 3600 // 1小时
        let checkInterval: TimeInterval = 120 // 每2分钟检查一次
        let connectionCount = 10

        print("\n📊 测试: 1小时多连接(\(connectionCount)个)稳定性")

        // 创建多个连接
        print("  创建\(connectionCount)个连接...")
        let connections = try await withThrowingTaskGroup(of: TCPConnection.self) { group in
            for _ in 1...connectionCount {
                group.addTask {
                    try await self.createConnection(heartbeatInterval: 30)
                }
            }

            var results: [TCPConnection] = []
            for try await connection in group {
                results.append(connection)
            }
            return results
        }
        print("  ✓ 连接创建完成")

        let startTime = Date()
        let memoryAtStart = getMemoryUsage()

        var checkResults: [(minute: Int, activeConnections: Int, memory: Double)] = []

        let iterations = Int(testDuration / checkInterval)

        for iteration in 1...iterations {
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))

            let currentMinute = Int(Date().timeIntervalSince(startTime) / 60)
            let currentMemory = getMemoryUsage()

            // 检查所有连接状态
            var activeCount = 0
            for connection in connections {
                let state = await connection.state
                if state == .connected {
                    activeCount += 1
                }
            }

            checkResults.append((
                minute: currentMinute,
                activeConnections: activeCount,
                memory: currentMemory
            ))

            print("  ✓ 第\(currentMinute)分钟: 活跃连接 \(activeCount)/\(connectionCount), 内存=\(String(format: "%.1f", currentMemory))MB")

            // 每个连接发送测试消息
            if iteration % 3 == 0 { // 每6分钟发送一次
                for (index, connection) in connections.enumerated() {
                    let testData = "Multi check \(iteration)-\(index)".data(using: .utf8)!
                    do {
                        try await connection.send(testData)
                    } catch {
                        print("    ⚠️ 连接\(index)发送失败")
                    }
                }
            }
        }

        // 清理
        for connection in connections {
            await connection.disconnect()
        }

        let finalMemory = getMemoryUsage()
        let totalMemoryIncrease = finalMemory - memoryAtStart

        // 分析结果
        let avgActiveConnections = Double(checkResults.map { $0.activeConnections }.reduce(0, +)) / Double(checkResults.count)
        let minActiveConnections = checkResults.map { $0.activeConnections }.min() ?? 0
        let connectionStabilityRate = avgActiveConnections / Double(connectionCount)

        let memoryValues = checkResults.map { $0.memory }
        let avgMemory = memoryValues.reduce(0, +) / Double(memoryValues.count)

        print("\n📊 1小时多连接稳定性测试结果:")
        print("  连接数: \(connectionCount)")
        print("  检查次数: \(checkResults.count)")
        print("  平均活跃连接: \(String(format: "%.1f", avgActiveConnections))")
        print("  最少活跃连接: \(minActiveConnections)")
        print("  连接稳定率: \(String(format: "%.2f", connectionStabilityRate * 100))%")
        print("  平均内存: \(String(format: "%.2f", avgMemory))MB")
        print("  总内存增长: \(String(format: "%.2f", totalMemoryIncrease))MB")
        print("  平均每连接内存: \(String(format: "%.2f", totalMemoryIncrease / Double(connectionCount)))MB")

        XCTAssertGreaterThan(connectionStabilityRate, 0.95, "多连接稳定率应该大于95%")
        XCTAssertLessThan(totalMemoryIncrease, 150.0, "总内存增长应该小于150MB")
    }

    // MARK: - 2. 循环重连稳定性测试

    /// 测试2.1: 1小时循环重连测试
    func testOneHourReconnectStability() async throws {
        let testDuration: TimeInterval = 3600 // 1小时
        let reconnectInterval: TimeInterval = 10 // 每10秒重连一次

        print("\n📊 测试: 1小时循环重连稳定性")
        print("  预计重连次数: ~\(Int(testDuration / reconnectInterval))")

        let startTime = Date()
        let memoryAtStart = getMemoryUsage()

        var reconnectCount = 0
        var successfulReconnects = 0
        var failedReconnects = 0
        var reconnectTimes: [TimeInterval] = []

        while Date().timeIntervalSince(startTime) < testDuration {
            reconnectCount += 1

            // 创建连接
            let connectStart = Date()
            do {
                let connection = try await createConnection()
                let connectDuration = Date().timeIntervalSince(connectStart)
                reconnectTimes.append(connectDuration)

                // 发送测试消息
                let testData = "Reconnect test \(reconnectCount)".data(using: .utf8)!
                try await connection.send(testData)

                successfulReconnects += 1

                // 断开连接
                await connection.disconnect()

                if reconnectCount % 30 == 0 {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let currentMemory = getMemoryUsage()
                    let successRate = Double(successfulReconnects) / Double(reconnectCount)
                    print("  ✓ 第\(reconnectCount)次重连: 成功率=\(String(format: "%.1f", successRate * 100))%, 内存=\(String(format: "%.1f", currentMemory))MB, 耗时=\(String(format: "%.0f", elapsed))秒")
                }

            } catch {
                failedReconnects += 1
                if failedReconnects % 10 == 0 {
                    print("  ⚠️ 重连失败次数: \(failedReconnects)")
                }
            }

            // 等待下一次重连
            try await Task.sleep(nanoseconds: UInt64(reconnectInterval * 1_000_000_000))
        }

        let finalMemory = getMemoryUsage()
        let totalMemoryIncrease = finalMemory - memoryAtStart

        // 统计
        let successRate = Double(successfulReconnects) / Double(reconnectCount)
        let avgReconnectTime = reconnectTimes.isEmpty ? 0 : reconnectTimes.reduce(0, +) / Double(reconnectTimes.count)
        let maxReconnectTime = reconnectTimes.max() ?? 0

        print("\n📊 1小时循环重连测试结果:")
        print("  总重连次数: \(reconnectCount)")
        print("  成功次数: \(successfulReconnects)")
        print("  失败次数: \(failedReconnects)")
        print("  成功率: \(String(format: "%.2f", successRate * 100))%")
        print("  平均重连时间: \(String(format: "%.2f", avgReconnectTime * 1000))ms")
        print("  最慢重连时间: \(String(format: "%.2f", maxReconnectTime * 1000))ms")
        print("  起始内存: \(String(format: "%.2f", memoryAtStart))MB")
        print("  最终内存: \(String(format: "%.2f", finalMemory))MB")
        print("  总内存增长: \(String(format: "%.2f", totalMemoryIncrease))MB")

        XCTAssertGreaterThan(successRate, 0.95, "循环重连成功率应该大于95%")
        XCTAssertLessThan(avgReconnectTime, 1.0, "平均重连时间应该小于1秒")
        XCTAssertLessThan(abs(totalMemoryIncrease), 50.0, "内存增长应该小于50MB（检测内存泄漏）")
    }

    // MARK: - 3. 性能衰减测试

    /// 测试3.1: 性能衰减检测
    func testPerformanceDegradation() async throws {
        let testDuration: TimeInterval = 1800 // 30分钟
        let measureInterval: TimeInterval = 300 // 每5分钟测量一次
        let messagesPerMeasure = 100

        print("\n📊 测试: 性能衰减检测 (\(Int(testDuration / 60))分钟)")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let testData = "Performance test".data(using: .utf8)!
        var measurements: [(minute: Int, qps: Double, avgLatency: TimeInterval)] = []

        let startTime = Date()
        let iterations = Int(testDuration / measureInterval)

        for iteration in 0...iterations {
            if iteration > 0 {
                try await Task.sleep(nanoseconds: UInt64(measureInterval * 1_000_000_000))
            }

            let currentMinute = Int(Date().timeIntervalSince(startTime) / 60)

            // 测量当前性能
            let measureStart = Date()
            var latencies: [TimeInterval] = []

            for _ in 1...messagesPerMeasure {
                let sendStart = Date()
                try await connection.send(testData)
                let latency = Date().timeIntervalSince(sendStart)
                latencies.append(latency)
            }

            let measureDuration = Date().timeIntervalSince(measureStart)
            let qps = Double(messagesPerMeasure) / measureDuration
            let avgLatency = latencies.reduce(0, +) / Double(latencies.count)

            measurements.append((
                minute: currentMinute,
                qps: qps,
                avgLatency: avgLatency
            ))

            print("  ✓ 第\(currentMinute)分钟: QPS=\(String(format: "%.1f", qps)), 延迟=\(String(format: "%.2f", avgLatency * 1000))ms")
        }

        // 分析性能衰减
        let firstQPS = measurements[0].qps
        let lastQPS = measurements[measurements.count - 1].qps
        let qpsDegradation = (firstQPS - lastQPS) / firstQPS * 100

        let firstLatency = measurements[0].avgLatency
        let lastLatency = measurements[measurements.count - 1].avgLatency
        let latencyIncrease = (lastLatency - firstLatency) / firstLatency * 100

        let avgQPS = measurements.map { $0.qps }.reduce(0, +) / Double(measurements.count)
        let avgLatency = measurements.map { $0.avgLatency }.reduce(0, +) / Double(measurements.count)

        print("\n📊 性能衰减测试结果:")
        print("  测量次数: \(measurements.count)")
        print("  初始QPS: \(String(format: "%.1f", firstQPS))")
        print("  最终QPS: \(String(format: "%.1f", lastQPS))")
        print("  平均QPS: \(String(format: "%.1f", avgQPS))")
        print("  QPS衰减: \(String(format: "%.1f", qpsDegradation))%")
        print("  初始延迟: \(String(format: "%.2f", firstLatency * 1000))ms")
        print("  最终延迟: \(String(format: "%.2f", lastLatency * 1000))ms")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("  延迟增长: \(String(format: "%.1f", latencyIncrease))%")

        // 性能要求
        XCTAssertLessThan(abs(qpsDegradation), 20.0, "QPS衰减应该小于20%")
        XCTAssertLessThan(latencyIncrease, 50.0, "延迟增长应该小于50%")
    }

    // MARK: - Helper Methods

    /// 创建TCP连接
    private func createConnection(heartbeatInterval: TimeInterval = 0) async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout

        if heartbeatInterval > 0 {
            config.heartbeatInterval = heartbeatInterval
            config.heartbeatTimeout = heartbeatInterval * 2
        }

        let connection = TCPConnection(
            host: testHost,
            port: testPort,
            configuration: config
        )

        try await connection.connect()
        return connection
    }

    /// 获取当前内存使用量（MB）
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        } else {
            return 0.0
        }
    }
}
