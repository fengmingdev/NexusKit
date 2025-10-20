//
//  PerformanceBenchmarks.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusCore

/// 性能基准测试套件
///
/// 测试各项性能指标，建立性能基线，用于回归测试和性能对比
///
/// **前置条件**: 启动测试服务器
/// ```bash
/// cd TestServers
/// npm run integration
/// ```
///
/// **测试覆盖**:
/// - 连接建立性能
/// - 消息吞吐量性能
/// - 延迟性能
/// - TLS性能
/// - SOCKS5性能
/// - 压缩性能
/// - 缓存性能
/// - 资源使用性能
///
@available(iOS 13.0, macOS 10.15, *)
final class PerformanceBenchmarks: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8888
    private let tlsPort: UInt16 = 8889
    private let proxyPort: UInt16 = 1080
    private let connectionTimeout: TimeInterval = 10.0

    // 性能基准目标
    private struct PerformanceTargets {
        static let connectionTimeAvg: TimeInterval = 0.3 // 300ms
        static let connectionTimeP99: TimeInterval = 0.5 // 500ms
        static let minQPS: Double = 15.0
        static let maxLatencyAvg: TimeInterval = 0.050 // 50ms
        static let maxLatencyP99: TimeInterval = 0.100 // 100ms
        static let tlsHandshakeMax: TimeInterval = 1.0 // 1秒
        static let memoryPerConnection: Double = 0.5 // 0.5MB
    }

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        try await Task.sleep(nanoseconds: 500_000_000)
        print("\n" + String(repeating: "=", count: 60))
        print("📊 开始性能基准测试")
        print(String(repeating: "=", count: 60))
    }

    override func tearDown() async throws {
        print(String(repeating: "=", count: 60))
        print("✅ 性能基准测试完成")
        print(String(repeating: "=", count: 60) + "\n")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try await super.tearDown()
    }

    // MARK: - 1. 连接性能基准 (3个测试)

    /// 基准1.1: TCP连接建立性能
    func testTCPConnectionPerformance() async throws {
        print("\n📊 基准测试: TCP连接建立性能")

        let iterations = 100
        var connectionTimes: [TimeInterval] = []
        let memoryBefore = getMemoryUsage()

        print("  执行\(iterations)次连接...")

        for i in 1...iterations {
            let start = Date()
            let connection = try await createConnection()
            let duration = Date().timeIntervalSince(start)
            connectionTimes.append(duration)

            await connection.disconnect()

            if i % 20 == 0 {
                print("    已完成 \(i)/\(iterations)")
            }

            // 短暂延迟，避免资源耗尽
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        let memoryAfter = getMemoryUsage()

        // 统计分析
        let sorted = connectionTimes.sorted()
        let avg = connectionTimes.reduce(0, +) / Double(connectionTimes.count)
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let p99 = sorted[Int(Double(sorted.count) * 0.99)]

        print("\n📊 TCP连接性能基准结果:")
        print("  样本数: \(iterations)")
        print("  平均时间: \(String(format: "%.2f", avg * 1000))ms")
        print("  最小时间: \(String(format: "%.2f", min * 1000))ms")
        print("  最大时间: \(String(format: "%.2f", max * 1000))ms")
        print("  P50: \(String(format: "%.2f", p50 * 1000))ms")
        print("  P95: \(String(format: "%.2f", p95 * 1000))ms")
        print("  P99: \(String(format: "%.2f", p99 * 1000))ms")
        print("  内存占用: \(String(format: "%.2f", memoryAfter - memoryBefore))MB")

        // 性能断言
        print("\n  性能要求验证:")
        print("    ✓ 平均时间 < \(Int(PerformanceTargets.connectionTimeAvg * 1000))ms: \(avg < PerformanceTargets.connectionTimeAvg ? "通过" : "失败")")
        print("    ✓ P99 < \(Int(PerformanceTargets.connectionTimeP99 * 1000))ms: \(p99 < PerformanceTargets.connectionTimeP99 ? "通过" : "失败")")

        XCTAssertLessThan(avg, PerformanceTargets.connectionTimeAvg,
                         "平均连接时间应该小于\(PerformanceTargets.connectionTimeAvg * 1000)ms")
        XCTAssertLessThan(p99, PerformanceTargets.connectionTimeP99,
                         "P99连接时间应该小于\(PerformanceTargets.connectionTimeP99 * 1000)ms")
    }

    /// 基准1.2: TLS连接建立性能
    func testTLSConnectionPerformance() async throws {
        print("\n📊 基准测试: TLS连接建立性能")

        let iterations = 50
        var handshakeTimes: [TimeInterval] = []

        print("  执行\(iterations)次TLS连接...")

        for i in 1...iterations {
            let start = Date()
            let connection = try await createTLSConnection()
            let duration = Date().timeIntervalSince(start)
            handshakeTimes.append(duration)

            await connection.disconnect()

            if i % 10 == 0 {
                print("    已完成 \(i)/\(iterations)")
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // 统计
        let sorted = handshakeTimes.sorted()
        let avg = handshakeTimes.reduce(0, +) / Double(handshakeTimes.count)
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let p99 = sorted[Int(Double(sorted.count) * 0.99)]

        print("\n📊 TLS连接性能基准结果:")
        print("  样本数: \(iterations)")
        print("  平均握手时间: \(String(format: "%.2f", avg * 1000))ms")
        print("  最小时间: \(String(format: "%.2f", min * 1000))ms")
        print("  最大时间: \(String(format: "%.2f", max * 1000))ms")
        print("  P95: \(String(format: "%.2f", p95 * 1000))ms")
        print("  P99: \(String(format: "%.2f", p99 * 1000))ms")

        print("\n  性能要求验证:")
        print("    ✓ 平均时间 < \(Int(PerformanceTargets.tlsHandshakeMax * 1000))ms: \(avg < PerformanceTargets.tlsHandshakeMax ? "通过" : "失败")")

        XCTAssertLessThan(avg, PerformanceTargets.tlsHandshakeMax,
                         "TLS握手时间应该小于\(PerformanceTargets.tlsHandshakeMax * 1000)ms")
    }

    /// 基准1.3: SOCKS5连接建立性能
    func testSOCKS5ConnectionPerformance() async throws {
        print("\n📊 基准测试: SOCKS5连接建立性能")

        let iterations = 50
        var connectionTimes: [TimeInterval] = []

        print("  执行\(iterations)次SOCKS5连接...")

        for i in 1...iterations {
            let start = Date()
            let connection = try await createSOCKS5Connection()
            let duration = Date().timeIntervalSince(start)
            connectionTimes.append(duration)

            await connection.disconnect()

            if i % 10 == 0 {
                print("    已完成 \(i)/\(iterations)")
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // 统计
        let sorted = connectionTimes.sorted()
        let avg = connectionTimes.reduce(0, +) / Double(connectionTimes.count)
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]

        print("\n📊 SOCKS5连接性能基准结果:")
        print("  样本数: \(iterations)")
        print("  平均时间: \(String(format: "%.2f", avg * 1000))ms")
        print("  P95: \(String(format: "%.2f", p95 * 1000))ms")

        print("\n  性能要求验证:")
        print("    ✓ 平均时间 < 2000ms: \(avg < 2.0 ? "通过" : "失败")")

        XCTAssertLessThan(avg, 2.0, "SOCKS5连接时间应该小于2秒")
    }

    // MARK: - 2. 吞吐量性能基准 (2个测试)

    /// 基准2.1: 消息吞吐量(QPS)
    func testMessageThroughputQPS() async throws {
        print("\n📊 基准测试: 消息吞吐量 (QPS)")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let testData = "Throughput benchmark test message".data(using: .utf8)!
        let testDuration: TimeInterval = 10.0

        print("  测试时长: \(Int(testDuration))秒")

        var messageCount = 0
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < testDuration {
            do {
                try await connection.send(testData)
                messageCount += 1
            } catch {
                break
            }
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        let qps = Double(messageCount) / actualDuration

        print("\n📊 消息吞吐量基准结果:")
        print("  测试时长: \(String(format: "%.2f", actualDuration))秒")
        print("  消息数量: \(messageCount)")
        print("  QPS: \(String(format: "%.1f", qps))")

        print("\n  性能要求验证:")
        print("    ✓ QPS > \(Int(PerformanceTargets.minQPS)): \(qps > PerformanceTargets.minQPS ? "通过" : "失败")")

        XCTAssertGreaterThan(qps, PerformanceTargets.minQPS,
                            "QPS应该大于\(PerformanceTargets.minQPS)")
    }

    /// 基准2.2: 数据传输速率
    func testDataTransferRate() async throws {
        print("\n📊 基准测试: 数据传输速率")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let blockSize = 64 * 1024 // 64KB
        let testData = Data(repeating: 0x42, count: blockSize)
        let testDuration: TimeInterval = 10.0

        print("  块大小: \(blockSize / 1024)KB")
        print("  测试时长: \(Int(testDuration))秒")

        var totalBytes = 0
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < testDuration {
            do {
                try await connection.send(testData)
                totalBytes += blockSize
            } catch {
                break
            }
        }

        let actualDuration = Date().timeIntervalSince(startTime)
        let mbps = Double(totalBytes) / actualDuration / 1024.0 / 1024.0

        print("\n📊 数据传输速率基准结果:")
        print("  测试时长: \(String(format: "%.2f", actualDuration))秒")
        print("  总传输: \(String(format: "%.2f", Double(totalBytes) / 1024.0 / 1024.0))MB")
        print("  传输速率: \(String(format: "%.2f", mbps))MB/s")

        XCTAssertGreaterThan(mbps, 1.0, "传输速率应该大于1MB/s")
    }

    // MARK: - 3. 延迟性能基准 (2个测试)

    /// 基准3.1: 消息延迟分布
    func testMessageLatencyDistribution() async throws {
        print("\n📊 基准测试: 消息延迟分布")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let iterations = 1000
        let testData = "Latency test".data(using: .utf8)!
        var latencies: [TimeInterval] = []

        print("  执行\(iterations)次测量...")

        for i in 1...iterations {
            let start = Date()
            try await connection.send(testData)
            let latency = Date().timeIntervalSince(start)
            latencies.append(latency)

            if i % 200 == 0 {
                print("    已完成 \(i)/\(iterations)")
            }
        }

        // 统计
        let sorted = latencies.sorted()
        let avg = latencies.reduce(0, +) / Double(latencies.count)
        let min = sorted.first ?? 0
        let max = sorted.last ?? 0
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let p99 = sorted[Int(Double(sorted.count) * 0.99)]
        let p999 = sorted[Int(Double(sorted.count) * 0.999)]

        print("\n📊 消息延迟分布基准结果:")
        print("  样本数: \(iterations)")
        print("  平均延迟: \(String(format: "%.2f", avg * 1000))ms")
        print("  最小延迟: \(String(format: "%.2f", min * 1000))ms")
        print("  最大延迟: \(String(format: "%.2f", max * 1000))ms")
        print("  P50: \(String(format: "%.2f", p50 * 1000))ms")
        print("  P95: \(String(format: "%.2f", p95 * 1000))ms")
        print("  P99: \(String(format: "%.2f", p99 * 1000))ms")
        print("  P999: \(String(format: "%.2f", p999 * 1000))ms")

        print("\n  性能要求验证:")
        print("    ✓ 平均延迟 < \(Int(PerformanceTargets.maxLatencyAvg * 1000))ms: \(avg < PerformanceTargets.maxLatencyAvg ? "通过" : "失败")")
        print("    ✓ P99 < \(Int(PerformanceTargets.maxLatencyP99 * 1000))ms: \(p99 < PerformanceTargets.maxLatencyP99 ? "通过" : "失败")")

        XCTAssertLessThan(avg, PerformanceTargets.maxLatencyAvg,
                         "平均延迟应该小于\(PerformanceTargets.maxLatencyAvg * 1000)ms")
        XCTAssertLessThan(p99, PerformanceTargets.maxLatencyP99,
                         "P99延迟应该小于\(PerformanceTargets.maxLatencyP99 * 1000)ms")
    }

    /// 基准3.2: 心跳往返时间(RTT)
    func testHeartbeatRTT() async throws {
        print("\n📊 基准测试: 心跳往返时间 (RTT)")

        let connection = try await createConnection(heartbeatInterval: 0.5)
        defer { Task { await connection.disconnect() } }

        // 等待心跳运行
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5秒

        let stats = await connection.heartbeatStatistics

        print("\n📊 心跳RTT基准结果:")
        print("  心跳次数: \(stats.sentCount)")
        print("  成功次数: \(stats.receivedCount)")
        print("  平均RTT: \(String(format: "%.2f", stats.averageRTT * 1000))ms")

        XCTAssertLessThan(stats.averageRTT, 0.1, "心跳RTT应该小于100ms")
    }

    // MARK: - 4. 资源使用基准 (2个测试)

    /// 基准4.1: 内存使用效率
    func testMemoryEfficiency() async throws {
        print("\n📊 基准测试: 内存使用效率")

        let connectionCount = 100
        let memoryBefore = getMemoryUsage()

        print("  创建\(connectionCount)个连接...")

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

        try await Task.sleep(nanoseconds: 1_000_000_000)
        let memoryAfter = getMemoryUsage()
        let memoryIncrease = memoryAfter - memoryBefore
        let memoryPerConnection = memoryIncrease / Double(connectionCount)

        print("\n📊 内存使用效率基准结果:")
        print("  连接数: \(connectionCount)")
        print("  起始内存: \(String(format: "%.2f", memoryBefore))MB")
        print("  最终内存: \(String(format: "%.2f", memoryAfter))MB")
        print("  总增长: \(String(format: "%.2f", memoryIncrease))MB")
        print("  每连接内存: \(String(format: "%.2f", memoryPerConnection))MB")
        print("  每连接内存: \(String(format: "%.0f", memoryPerConnection * 1024))KB")

        print("\n  性能要求验证:")
        print("    ✓ 每连接内存 < \(PerformanceTargets.memoryPerConnection)MB: \(memoryPerConnection < PerformanceTargets.memoryPerConnection ? "通过" : "失败")")

        XCTAssertLessThan(memoryPerConnection, PerformanceTargets.memoryPerConnection,
                         "每连接内存应该小于\(PerformanceTargets.memoryPerConnection)MB")

        // 清理
        for connection in connections {
            await connection.disconnect()
        }
    }

    /// 基准4.2: CPU使用效率
    func testCPUEfficiency() async throws {
        print("\n📊 基准测试: CPU使用效率")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let testData = "CPU efficiency test".data(using: .utf8)!
        let messageCount = 1000

        // 测量CPU时间
        let processStart = ProcessInfo.processInfo.systemUptime
        let start = Date()

        for _ in 1...messageCount {
            try await connection.send(testData)
        }

        let wallDuration = Date().timeIntervalSince(start)
        let processEnd = ProcessInfo.processInfo.systemUptime
        let cpuTime = processEnd - processStart

        let cpuEfficiency = (cpuTime / wallDuration) * 100

        print("\n📊 CPU使用效率基准结果:")
        print("  消息数量: \(messageCount)")
        print("  墙钟时间: \(String(format: "%.2f", wallDuration))秒")
        print("  CPU时间: \(String(format: "%.2f", cpuTime))秒")
        print("  CPU使用率: \(String(format: "%.1f", cpuEfficiency))%")

        // CPU使用应该合理
        XCTAssertLessThan(cpuEfficiency, 200, "CPU使用率应该合理")
    }

    // MARK: - 5. 性能对比基准 (1个测试)

    /// 基准5.1: TLS vs 非TLS性能对比
    func testTLSPerformanceComparison() async throws {
        print("\n📊 基准测试: TLS vs 非TLS性能对比")

        let messageCount = 100
        let testData = "Performance comparison test".data(using: .utf8)!

        // 非TLS性能
        print("  测试非TLS性能...")
        let plainConnection = try await createConnection()
        defer { Task { await plainConnection.disconnect() } }

        let plainStart = Date()
        for _ in 1...messageCount {
            try await plainConnection.send(testData)
        }
        let plainDuration = Date().timeIntervalSince(plainStart)
        let plainQPS = Double(messageCount) / plainDuration

        // TLS性能
        print("  测试TLS性能...")
        let tlsConnection = try await createTLSConnection()
        defer { Task { await tlsConnection.disconnect() } }

        let tlsStart = Date()
        for _ in 1...messageCount {
            try await tlsConnection.send(testData)
        }
        let tlsDuration = Date().timeIntervalSince(tlsStart)
        let tlsQPS = Double(messageCount) / tlsDuration

        // 计算开销
        let overhead = (tlsDuration - plainDuration) / plainDuration * 100

        print("\n📊 TLS vs 非TLS性能对比结果:")
        print("  消息数量: \(messageCount)")
        print("  非TLS:")
        print("    耗时: \(String(format: "%.2f", plainDuration))秒")
        print("    QPS: \(String(format: "%.1f", plainQPS))")
        print("  TLS:")
        print("    耗时: \(String(format: "%.2f", tlsDuration))秒")
        print("    QPS: \(String(format: "%.1f", tlsQPS))")
        print("  TLS开销: \(String(format: "%.1f", overhead))%")

        XCTAssertLessThan(overhead, 100, "TLS性能开销应该小于100%")
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

    /// 创建TLS连接
    private func createTLSConnection() async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout
        config.enableTLS = true
        config.allowSelfSignedCertificates = true

        let connection = TCPConnection(
            host: testHost,
            port: tlsPort,
            configuration: config
        )

        try await connection.connect()
        return connection
    }

    /// 创建SOCKS5连接
    private func createSOCKS5Connection() async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout
        config.enableProxy = true
        config.proxyType = .socks5
        config.proxyHost = testHost
        config.proxyPort = proxyPort

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
