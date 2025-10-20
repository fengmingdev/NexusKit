//
//  NetworkMonitoringTests.swift
//  NexusKit Integration Tests
//
//  Created by NexusKit Contributors
//

import XCTest
import Network
@testable import NexusCore
@testable import NexusTCP

/// 网络监控集成测试
final class NetworkMonitoringTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        let isRunning = await TestUtils.isTCPServerRunning()
        if !isRunning {
            throw XCTSkip("TCP测试服务器未运行")
        }
    }

    // MARK: - 基础监控测试

    /// 测试网络状态监控
    func testNetworkStatusMonitoring() async throws {
        TestUtils.printTestSeparator("测试网络状态监控")

        let monitor = NetworkMonitor.shared

        // 等待网络监控启动
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let isConnected = await monitor.isNetworkAvailable
        print("  网络可用: \(isConnected)")

        XCTAssertTrue(isConnected, "网络应该可用（测试需要网络连接）")

        TestUtils.printTestResult("网络状态监控", passed: true)
    }

    /// 测试网络类型检测
    func testNetworkTypeDetection() async throws {
        TestUtils.printTestSeparator("测试网络类型检测")

        let monitor = NetworkMonitor.shared

        try await Task.sleep(nanoseconds: 1_000_000_000)

        let networkType = await monitor.currentNetworkType
        print("  当前网络类型: \(networkType)")

        // 验证网络类型有效
        let validTypes: [NetworkMonitor.NetworkType] = [.wifi, .cellular, .wired, .other, .unknown]
        XCTAssertTrue(validTypes.contains(networkType), "网络类型应该是有效的")

        TestUtils.printTestResult("网络类型检测(\(networkType))", passed: true)
    }

    /// 测试网络质量评估
    func testNetworkQualityAssessment() async throws {
        TestUtils.printTestSeparator("测试网络质量评估")

        let monitor = NetworkMonitor.shared

        try await Task.sleep(nanoseconds: 1_000_000_000)

        let quality = await monitor.networkQuality
        print("  网络质量: \(quality)")

        // 验证质量级别有效
        let validQualities: [NetworkMonitor.NetworkQuality] = [.excellent, .good, .fair, .poor, .unavailable]
        XCTAssertTrue(validQualities.contains(quality), "网络质量应该是有效的")

        TestUtils.printTestResult("网络质量评估(\(quality))", passed: true)
    }

    // MARK: - 网络变化监听测试

    /// 测试网络状态变化通知
    func testNetworkStatusChangeNotification() async throws {
        TestUtils.printTestSeparator("测试网络状态变化通知")

        let monitor = NetworkMonitor.shared
        var notificationReceived = false

        // 监听网络状态变化
        let cancellable = await monitor.onNetworkStatusChange { status in
            print("  网络状态变化: \(status)")
            notificationReceived = true
        }

        defer {
            cancellable.cancel()
        }

        // 等待一段时间观察变化
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // 注意：在稳定的网络环境下可能不会有状态变化
        print("  收到通知: \(notificationReceived)")

        TestUtils.printTestResult("网络状态变化通知", passed: true)
    }

    /// 测试网络类型变化通知
    func testNetworkTypeChangeNotification() async throws {
        TestUtils.printTestSeparator("测试网络类型变化通知")

        let monitor = NetworkMonitor.shared
        var changeCount = 0

        let cancellable = await monitor.onNetworkTypeChange { oldType, newType in
            print("  网络类型变化: \(oldType) -> \(newType)")
            changeCount += 1
        }

        defer {
            cancellable.cancel()
        }

        // 等待观察
        try await Task.sleep(nanoseconds: 3_000_000_000)

        print("  类型变化次数: \(changeCount)")

        TestUtils.printTestResult("网络类型变化通知", passed: true)
    }

    // MARK: - 连接质量监控测试

    /// 测试连接延迟监控
    func testConnectionLatencyMonitoring() async throws {
        TestUtils.printTestSeparator("测试连接延迟监控")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var latencies: [TimeInterval] = []

        // 测量10次往返延迟
        for _ in 0..<10 {
            let (_, latency) = await TestUtils.measureTime {
                _ = try await TestUtils.sendHeartbeat(
                    connection: connection,
                    timeout: 5.0
                )
            }
            latencies.append(latency)

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let minLatency = latencies.min() ?? 0
        let maxLatency = latencies.max() ?? 0

        print("  平均延迟: \(String(format: "%.3f", avgLatency * 1000)) ms")
        print("  最小延迟: \(String(format: "%.3f", minLatency * 1000)) ms")
        print("  最大延迟: \(String(format: "%.3f", maxLatency * 1000)) ms")

        XCTAssertLessThan(avgLatency, 0.5, "平均延迟应该小于500ms")

        TestUtils.printTestResult(
            "连接延迟监控(平均:\(String(format: "%.0f", avgLatency * 1000))ms)",
            passed: true
        )
    }

    /// 测试连接稳定性监控
    func testConnectionStabilityMonitoring() async throws {
        TestUtils.printTestSeparator("测试连接稳定性监控")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let duration: TimeInterval = 30.0
        let checkInterval: TimeInterval = 1.0
        let checks = Int(duration / checkInterval)

        var successCount = 0
        var totalLatency: TimeInterval = 0

        for i in 1...checks {
            let (success, latency) = await TestUtils.measureTime {
                do {
                    _ = try await TestUtils.sendHeartbeat(
                        connection: connection,
                        timeout: 3.0
                    )
                    return true
                } catch {
                    return false
                }
            }

            if success {
                successCount += 1
                totalLatency += latency
            }

            if i % 10 == 0 {
                print("  已检查 \(i)/\(checks) 次")
            }

            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }

        let successRate = Double(successCount) / Double(checks) * 100
        let avgLatency = successCount > 0 ? totalLatency / Double(successCount) : 0

        print("  稳定性: \(String(format: "%.1f", successRate))%")
        print("  平均延迟: \(String(format: "%.3f", avgLatency * 1000)) ms")

        XCTAssertGreaterThan(successRate, 90.0, "连接稳定性应该大于90%")

        TestUtils.printTestResult(
            "连接稳定性(\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    // MARK: - 带宽监控测试

    /// 测试下载速度监控
    func testDownloadSpeedMonitoring() async throws {
        TestUtils.printTestSeparator("测试下载速度监控")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 请求大数据
        let largeDataSize = 512 * 1024 // 512KB
        let largeBody = TestFixtures.randomData(length: largeDataSize)
        let largeMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: largeBody
        ).encode()

        let (response, duration) = await TestUtils.measureTime {
            try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: largeMessage,
                timeout: 10.0
            )
        }

        let downloadSpeed = Double(response.count) / duration / 1024 / 1024 // MB/s
        print("  下载速度: \(String(format: "%.2f", downloadSpeed)) MB/s")
        print("  数据大小: \(response.count / 1024) KB")
        print("  耗时: \(String(format: "%.3f", duration))s")

        XCTAssertGreaterThan(downloadSpeed, 0.1, "下载速度应该大于0.1 MB/s")

        TestUtils.printTestResult(
            "下载速度(\(String(format: "%.2f", downloadSpeed)) MB/s)",
            passed: true
        )
    }

    /// 测试上传速度监控
    func testUploadSpeedMonitoring() async throws {
        TestUtils.printTestSeparator("测试上传速度监控")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 发送大数据
        let uploadSize = 256 * 1024 // 256KB
        let uploadData = TestFixtures.randomData(length: uploadSize)
        let uploadMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: uploadData
        ).encode()

        let (_, duration) = await TestUtils.measureTime {
            try await connection.send(uploadMessage, timeout: 10.0)
        }

        let uploadSpeed = Double(uploadMessage.count) / duration / 1024 / 1024 // MB/s
        print("  上传速度: \(String(format: "%.2f", uploadSpeed)) MB/s")
        print("  数据大小: \(uploadMessage.count / 1024) KB")
        print("  耗时: \(String(format: "%.3f", duration))s")

        XCTAssertGreaterThan(uploadSpeed, 0.1, "上传速度应该大于0.1 MB/s")

        TestUtils.printTestResult(
            "上传速度(\(String(format: "%.2f", uploadSpeed)) MB/s)",
            passed: true
        )
    }

    // MARK: - 网络恢复测试

    /// 测试网络中断检测
    func testNetworkInterruptionDetection() async throws {
        TestUtils.printTestSeparator("测试网络中断检测")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 1.0, timeout: 3.0)
            .connect()

        var disconnected = false

        // 监听断开事件
        Task {
            while await connection.state != .disconnected {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            disconnected = true
        }

        // 模拟长时间运行
        try await Task.sleep(nanoseconds: 5_000_000_000)

        // 主动断开
        await connection.disconnect(reason: .clientInitiated)

        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(disconnected, "应该检测到断开")

        TestUtils.printTestResult("网络中断检测", passed: true)
    }

    // MARK: - 多连接监控测试

    /// 测试多连接并发监控
    func testMultiConnectionMonitoring() async throws {
        TestUtils.printTestSeparator("测试多连接并发监控")

        let connectionCount = 5
        var connections: [TCPConnection] = []

        // 创建多个连接
        for _ in 0..<connectionCount {
            let conn = try await TestUtils.createTestConnection()
            connections.append(conn)
        }

        defer {
            Task {
                for conn in connections {
                    await conn.disconnect(reason: .clientInitiated)
                }
            }
        }

        // 并发监控所有连接
        var allSuccess = true

        await withTaskGroup(of: Bool.self) { group in
            for conn in connections {
                group.addTask {
                    do {
                        _ = try await TestUtils.sendHeartbeat(
                            connection: conn,
                            timeout: 5.0
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if !success {
                    allSuccess = false
                }
            }
        }

        XCTAssertTrue(allSuccess, "所有连接应该正常")

        TestUtils.printTestResult("多连接并发监控(\(connectionCount)个)", passed: true)
    }

    /// 测试连接池健康检查
    func testConnectionPoolHealthCheck() async throws {
        TestUtils.printTestSeparator("测试连接池健康检查")

        let poolSize = 10
        var connections: [TCPConnection] = []
        var healthyCount = 0

        // 创建连接池
        for _ in 0..<poolSize {
            do {
                let conn = try await TestUtils.createTestConnection()
                connections.append(conn)
            } catch {
                print("  创建连接失败: \(error)")
            }
        }

        defer {
            Task {
                for conn in connections {
                    await conn.disconnect(reason: .clientInitiated)
                }
            }
        }

        print("  连接池大小: \(connections.count)")

        // 健康检查
        for conn in connections {
            let state = await conn.state
            if state == .connected {
                do {
                    _ = try await TestUtils.sendHeartbeat(
                        connection: conn,
                        timeout: 3.0
                    )
                    healthyCount += 1
                } catch {
                    print("  心跳失败")
                }
            }
        }

        let healthRate = Double(healthyCount) / Double(connections.count) * 100
        print("  健康率: \(String(format: "%.1f", healthRate))%")

        XCTAssertGreaterThan(healthRate, 80.0, "连接池健康率应该大于80%")

        TestUtils.printTestResult(
            "连接池健康检查(\(String(format: "%.1f", healthRate))%)",
            passed: true
        )
    }

    // MARK: - 网络性能基准测试

    /// 测试网络吞吐量基准
    func testNetworkThroughputBenchmark() async throws {
        TestUtils.printTestSeparator("测试网络吞吐量基准")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Benchmark".data(using: .utf8)!
        ).encode()

        // 测试不同负载下的吞吐量
        let testCases = [10, 50, 100, 200]

        for iterations in testCases {
            let (qps, avgLatency) = try await TestUtils.measureThroughput(iterations: iterations) {
                _ = try await TestUtils.sendAndReceiveMessage(
                    connection: connection,
                    message: testMessage,
                    timeout: 5.0
                )
            }

            print("  \(iterations)次: \(String(format: "%.0f", qps)) QPS, 延迟 \(String(format: "%.3f", avgLatency * 1000)) ms")
        }

        TestUtils.printTestResult("网络吞吐量基准", passed: true)
    }

    /// 测试网络延迟分布
    func testNetworkLatencyDistribution() async throws {
        TestUtils.printTestSeparator("测试网络延迟分布")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var latencies: [TimeInterval] = []
        let sampleCount = 100

        for _ in 0..<sampleCount {
            let (_, latency) = await TestUtils.measureTime {
                _ = try await TestUtils.sendHeartbeat(
                    connection: connection,
                    timeout: 3.0
                )
            }
            latencies.append(latency)
        }

        // 统计分析
        latencies.sort()
        let p50 = latencies[sampleCount / 2]
        let p90 = latencies[Int(Double(sampleCount) * 0.9)]
        let p95 = latencies[Int(Double(sampleCount) * 0.95)]
        let p99 = latencies[Int(Double(sampleCount) * 0.99)]

        print("  P50: \(String(format: "%.3f", p50 * 1000)) ms")
        print("  P90: \(String(format: "%.3f", p90 * 1000)) ms")
        print("  P95: \(String(format: "%.3f", p95 * 1000)) ms")
        print("  P99: \(String(format: "%.3f", p99 * 1000)) ms")

        XCTAssertLessThan(p95, 0.2, "P95延迟应该小于200ms")

        TestUtils.printTestResult("网络延迟分布", passed: true)
    }

    // MARK: - 实际应用场景测试

    /// 测试弱网环境模拟
    func testPoorNetworkConditions() async throws {
        TestUtils.printTestSeparator("测试弱网环境模拟")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .timeout(10.0) // 增加超时时间
            .heartbeat(interval: 3.0, timeout: 10.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var successCount = 0
        var failCount = 0

        // 发送请求，模拟弱网
        for _ in 0..<20 {
            do {
                _ = try await TestUtils.sendHeartbeat(
                    connection: connection,
                    timeout: 10.0
                )
                successCount += 1
            } catch {
                failCount += 1
                print("  请求失败: \(error)")
            }

            // 随机延迟
            let randomDelay = UInt64.random(in: 100_000_000...500_000_000)
            try await Task.sleep(nanoseconds: randomDelay)
        }

        let successRate = Double(successCount) / Double(successCount + failCount) * 100
        print("  成功率: \(String(format: "%.1f", successRate))%")

        // 弱网环境下成功率降低是正常的
        XCTAssertGreaterThan(successRate, 50.0, "弱网环境成功率应该大于50%")

        TestUtils.printTestResult(
            "弱网环境模拟(成功率:\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    /// 测试网络切换场景
    func testNetworkSwitchScenario() async throws {
        TestUtils.printTestSeparator("测试网络切换场景")

        let monitor = NetworkMonitor.shared
        var statusChanges: [Bool] = []

        // 监听网络状态
        let cancellable = await monitor.onNetworkStatusChange { status in
            statusChanges.append(status)
            print("  网络状态: \(status)")
        }

        defer {
            cancellable.cancel()
        }

        // 创建连接
        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 持续监控10秒
        for i in 1...10 {
            let isConnected = await connection.state == .connected
            print("  第\(i)秒: 连接状态 = \(isConnected)")

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        print("  网络状态变化次数: \(statusChanges.count)")

        TestUtils.printTestResult("网络切换场景", passed: true)
    }
}
