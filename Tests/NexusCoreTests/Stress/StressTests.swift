//
//  StressTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusKit

/// 压力测试套件
///
/// 测试系统在高负载下的表现，包括并发连接、内存使用、性能衰减等
///
/// **前置条件**: 启动测试服务器
/// ```bash
/// cd TestServers
/// npm run integration
/// ```
///
/// **测试覆盖**:
/// - 高并发连接测试 (100+/500+/1000+连接)
/// - 高频消息测试 (1000+消息/秒)
/// - 持续负载测试 (持续发送10分钟)
/// - 连接池压力测试
/// - 内存压力测试
/// - CPU压力测试
/// - 峰值负载测试
/// - 恢复能力测试
///
@available(iOS 13.0, macOS 10.15, *)
final class StressTests: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8888
    private let connectionTimeout: TimeInterval = 10.0

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        print("\n" + String(repeating: "=", count: 60))
        print("🔥 开始压力测试")
        print(String(repeating: "=", count: 60))
    }

    override func tearDown() async throws {
        print(String(repeating: "=", count: 60))
        print("✅ 压力测试完成")
        print(String(repeating: "=", count: 60) + "\n")
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒，让连接充分释放
        try await super.tearDown()
    }

    // MARK: - 1. 高并发连接测试 (3个测试)

    /// 测试1.1: 100并发连接
    func testConcurrent100Connections() async throws {
        let connectionCount = 100
        print("\n📊 测试: \(connectionCount)个并发连接")

        let startTime = Date()
        let memoryBefore = getMemoryUsage()

        // 并发创建连接
        let connections = try await withThrowingTaskGroup(of: (TCPConnection, TimeInterval).self) { group in
            for i in 1...connectionCount {
                group.addTask {
                    let connectStart = Date()
                    let connection = try await self.createConnection()
                    let connectDuration = Date().timeIntervalSince(connectStart)

                    if i % 20 == 0 {
                        print("  ✓ 已建立 \(i) 个连接")
                    }

                    return (connection, connectDuration)
                }
            }

            var results: [(TCPConnection, TimeInterval)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let memoryAfter = getMemoryUsage()
        let memoryIncrease = memoryAfter - memoryBefore

        // 验证所有连接成功
        XCTAssertEqual(connections.count, connectionCount, "应该成功建立所有连接")

        // 计算统计数据
        let connectionTimes = connections.map { $0.1 }
        let avgConnectionTime = connectionTimes.reduce(0, +) / Double(connectionTimes.count)
        let maxConnectionTime = connectionTimes.max() ?? 0
        let minConnectionTime = connectionTimes.min() ?? 0

        print("\n📊 \(connectionCount)并发连接测试结果:")
        print("  总耗时: \(String(format: "%.2f", totalDuration))秒")
        print("  平均连接时间: \(String(format: "%.2f", avgConnectionTime * 1000))ms")
        print("  最快连接: \(String(format: "%.2f", minConnectionTime * 1000))ms")
        print("  最慢连接: \(String(format: "%.2f", maxConnectionTime * 1000))ms")
        print("  内存增长: \(String(format: "%.2f", memoryIncrease))MB")
        print("  平均每连接内存: \(String(format: "%.2f", memoryIncrease / Double(connectionCount) * 1024))KB")

        // 性能要求
        XCTAssertLessThan(avgConnectionTime, 1.0, "平均连接时间应该小于1秒")
        XCTAssertLessThan(memoryIncrease / Double(connectionCount), 1.0, "每连接内存应该小于1MB")

        // 测试所有连接都可用
        let testData = "Stress test".data(using: .utf8)!
        var successCount = 0

        for (connection, _) in connections {
            do {
                try await connection.send(testData)
                successCount += 1
            } catch {
                print("  ⚠️ 发送失败: \(error)")
            }
        }

        print("  发送成功率: \(String(format: "%.1f", Double(successCount) / Double(connectionCount) * 100))%")
        XCTAssertGreaterThan(Double(successCount) / Double(connectionCount), 0.95, "发送成功率应该>95%")

        // 清理
        for (connection, _) in connections {
            await connection.disconnect()
        }
    }

    /// 测试1.2: 500并发连接
    func testConcurrent500Connections() async throws {
        let connectionCount = 500
        print("\n📊 测试: \(connectionCount)个并发连接")

        let startTime = Date()
        let memoryBefore = getMemoryUsage()

        // 分批创建连接（每批100个）
        let batchSize = 100
        var allConnections: [TCPConnection] = []

        for batchIndex in 0..<(connectionCount / batchSize) {
            let batchStart = Date()

            let batch = try await withThrowingTaskGroup(of: TCPConnection.self) { group in
                for _ in 1...batchSize {
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

            allConnections.append(contentsOf: batch)
            let batchDuration = Date().timeIntervalSince(batchStart)
            print("  ✓ 批次\(batchIndex + 1): 已建立 \((batchIndex + 1) * batchSize) 个连接 (耗时: \(String(format: "%.2f", batchDuration))秒)")
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let memoryAfter = getMemoryUsage()
        let memoryIncrease = memoryAfter - memoryBefore

        XCTAssertEqual(allConnections.count, connectionCount)

        print("\n📊 \(connectionCount)并发连接测试结果:")
        print("  总耗时: \(String(format: "%.2f", totalDuration))秒")
        print("  吞吐量: \(String(format: "%.1f", Double(connectionCount) / totalDuration)) 连接/秒")
        print("  内存增长: \(String(format: "%.2f", memoryIncrease))MB")
        print("  平均每连接内存: \(String(format: "%.2f", memoryIncrease / Double(connectionCount) * 1024))KB")

        // 性能要求
        XCTAssertLessThan(totalDuration, 30.0, "500并发连接应该在30秒内完成")
        XCTAssertLessThan(memoryIncrease, 500.0, "总内存增长应该小于500MB")

        // 清理
        for connection in allConnections {
            await connection.disconnect()
        }

        // 等待资源释放
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
    }

    /// 测试1.3: 1000并发连接（极限测试）
    func testConcurrent1000Connections() async throws {
        let connectionCount = 1000
        print("\n📊 测试: \(connectionCount)个并发连接 (极限测试)")

        let startTime = Date()
        let memoryBefore = getMemoryUsage()

        // 分批创建（每批100个，分10批）
        let batchSize = 100
        var allConnections: [TCPConnection] = []
        var failedCount = 0

        for batchIndex in 0..<(connectionCount / batchSize) {
            let batch = try await withThrowingTaskGroup(of: Result<TCPConnection, Error>.self) { group in
                for _ in 1...batchSize {
                    group.addTask {
                        do {
                            let connection = try await self.createConnection()
                            return .success(connection)
                        } catch {
                            return .failure(error)
                        }
                    }
                }

                var results: [TCPConnection] = []
                for try await result in group {
                    switch result {
                    case .success(let connection):
                        results.append(connection)
                    case .failure:
                        failedCount += 1
                    }
                }
                return results
            }

            allConnections.append(contentsOf: batch)
            print("  ✓ 批次\(batchIndex + 1): 成功 \(batch.count)/\(batchSize) 个连接 (总计: \(allConnections.count))")

            // 短暂延迟，避免过载
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let memoryAfter = getMemoryUsage()
        let memoryIncrease = memoryAfter - memoryBefore
        let successRate = Double(allConnections.count) / Double(connectionCount)

        print("\n📊 \(connectionCount)并发连接测试结果:")
        print("  成功连接: \(allConnections.count)/\(connectionCount)")
        print("  成功率: \(String(format: "%.1f", successRate * 100))%")
        print("  失败连接: \(failedCount)")
        print("  总耗时: \(String(format: "%.2f", totalDuration))秒")
        print("  吞吐量: \(String(format: "%.1f", Double(allConnections.count) / totalDuration)) 连接/秒")
        print("  内存增长: \(String(format: "%.2f", memoryIncrease))MB")
        print("  平均每连接内存: \(String(format: "%.2f", memoryIncrease / Double(allConnections.count) * 1024))KB")

        // 在极限测试中，允许一定的失败率
        XCTAssertGreaterThan(successRate, 0.90, "成功率应该大于90%")

        // 清理
        for connection in allConnections {
            await connection.disconnect()
        }
    }

    // MARK: - 2. 高频消息测试 (2个测试)

    /// 测试2.1: 单连接高频消息 (1000条消息)
    func testHighFrequencyMessages() async throws {
        let messageCount = 1000
        print("\n📊 测试: 单连接发送\(messageCount)条消息")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let testData = "High frequency test message".data(using: .utf8)!
        let startTime = Date()

        var successCount = 0
        var failedCount = 0

        for i in 1...messageCount {
            do {
                try await connection.send(testData)
                successCount += 1

                if i % 200 == 0 {
                    print("  ✓ 已发送 \(i) 条消息")
                }
            } catch {
                failedCount += 1
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let qps = Double(successCount) / totalDuration
        let successRate = Double(successCount) / Double(messageCount)

        print("\n📊 高频消息测试结果:")
        print("  成功发送: \(successCount)/\(messageCount)")
        print("  成功率: \(String(format: "%.1f", successRate * 100))%")
        print("  失败数: \(failedCount)")
        print("  总耗时: \(String(format: "%.2f", totalDuration))秒")
        print("  QPS: \(String(format: "%.1f", qps))")
        print("  平均延迟: \(String(format: "%.2f", totalDuration / Double(successCount) * 1000))ms")

        // 性能要求
        XCTAssertGreaterThan(qps, 50, "QPS应该大于50")
        XCTAssertGreaterThan(successRate, 0.98, "成功率应该大于98%")
    }

    /// 测试2.2: 多连接并发消息 (10连接 × 500消息)
    func testConcurrentHighFrequencyMessages() async throws {
        let connectionCount = 10
        let messagesPerConnection = 500
        let totalMessages = connectionCount * messagesPerConnection

        print("\n📊 测试: \(connectionCount)连接并发发送，每连接\(messagesPerConnection)条消息")

        let startTime = Date()

        // 创建连接并并发发送消息
        let results = try await withThrowingTaskGroup(of: (Int, Int, TimeInterval).self) { group in
            for connIndex in 1...connectionCount {
                group.addTask {
                    let connection = try await self.createConnection()
                    let testData = "Concurrent message".data(using: .utf8)!

                    let sendStart = Date()
                    var successCount = 0

                    for _ in 1...messagesPerConnection {
                        do {
                            try await connection.send(testData)
                            successCount += 1
                        } catch {
                            // 记录失败
                        }
                    }

                    let sendDuration = Date().timeIntervalSince(sendStart)
                    await connection.disconnect()

                    return (connIndex, successCount, sendDuration)
                }
            }

            var allResults: [(Int, Int, TimeInterval)] = []
            for try await result in group {
                allResults.append(result)
            }
            return allResults
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let totalSuccess = results.map { $0.1 }.reduce(0, +)
        let overallQPS = Double(totalSuccess) / totalDuration
        let successRate = Double(totalSuccess) / Double(totalMessages)

        print("\n📊 并发高频消息测试结果:")
        print("  连接数: \(connectionCount)")
        print("  总消息数: \(totalMessages)")
        print("  成功发送: \(totalSuccess)")
        print("  成功率: \(String(format: "%.1f", successRate * 100))%")
        print("  总耗时: \(String(format: "%.2f", totalDuration))秒")
        print("  总体QPS: \(String(format: "%.1f", overallQPS))")

        // 每连接详情
        for (index, success, duration) in results {
            let connQPS = Double(success) / duration
            print("  连接\(index): \(success)条消息, QPS=\(String(format: "%.1f", connQPS))")
        }

        // 性能要求
        XCTAssertGreaterThan(overallQPS, 200, "总体QPS应该大于200")
        XCTAssertGreaterThan(successRate, 0.95, "成功率应该大于95%")
    }

    // MARK: - 3. 持续负载测试 (1个测试)

    /// 测试3.1: 10分钟持续负载测试
    func testSustainedLoad() async throws {
        let duration: TimeInterval = 600 // 10分钟
        let connectionCount = 20
        let messagesPerSecond = 10

        print("\n📊 测试: \(connectionCount)连接持续\(Int(duration))秒，每秒\(messagesPerSecond)条消息")
        print("  预计总消息数: \(connectionCount * messagesPerSecond * Int(duration))")

        // 创建连接
        print("\n  创建\(connectionCount)个连接...")
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

        print("  ✓ 连接创建完成")

        let startTime = Date()
        let memoryBefore = getMemoryUsage()

        // 并发持续发送
        let results = try await withThrowingTaskGroup(of: (Int, Int, [TimeInterval]).self) { group in
            for (index, connection) in connections.enumerated() {
                group.addTask {
                    var successCount = 0
                    var failedCount = 0
                    var samples: [TimeInterval] = []
                    let testData = "Sustained load".data(using: .utf8)!

                    let taskStart = Date()
                    while Date().timeIntervalSince(taskStart) < duration {
                        let sendStart = Date()

                        do {
                            try await connection.send(testData)
                            successCount += 1

                            let sendDuration = Date().timeIntervalSince(sendStart)
                            samples.append(sendDuration)
                        } catch {
                            failedCount += 1
                        }

                        // 控制发送频率
                        let interval = 1.0 / Double(messagesPerSecond)
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }

                    if index % 5 == 0 {
                        print("  ✓ 连接\(index + 1): 成功\(successCount), 失败\(failedCount)")
                    }

                    return (successCount, failedCount, samples)
                }
            }

            var allResults: [(Int, Int, [TimeInterval])] = []
            for try await result in group {
                allResults.append(result)
            }
            return allResults
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let memoryAfter = getMemoryUsage()
        let memoryIncrease = memoryAfter - memoryBefore

        // 统计
        let totalSuccess = results.map { $0.0 }.reduce(0, +)
        let totalFailed = results.map { $0.1 }.reduce(0, +)
        let allSamples = results.flatMap { $0.2 }

        let avgLatency = allSamples.reduce(0, +) / Double(allSamples.count)
        let maxLatency = allSamples.max() ?? 0
        let minLatency = allSamples.min() ?? 0

        let successRate = Double(totalSuccess) / Double(totalSuccess + totalFailed)
        let overallQPS = Double(totalSuccess) / totalDuration

        print("\n📊 持续负载测试结果:")
        print("  测试时长: \(String(format: "%.1f", totalDuration))秒")
        print("  连接数: \(connectionCount)")
        print("  成功消息: \(totalSuccess)")
        print("  失败消息: \(totalFailed)")
        print("  成功率: \(String(format: "%.2f", successRate * 100))%")
        print("  总体QPS: \(String(format: "%.1f", overallQPS))")
        print("  平均延迟: \(String(format: "%.2f", avgLatency * 1000))ms")
        print("  最小延迟: \(String(format: "%.2f", minLatency * 1000))ms")
        print("  最大延迟: \(String(format: "%.2f", maxLatency * 1000))ms")
        print("  内存增长: \(String(format: "%.2f", memoryIncrease))MB")

        // 性能要求
        XCTAssertGreaterThan(successRate, 0.95, "持续负载下成功率应该大于95%")
        XCTAssertLessThan(avgLatency, 0.1, "平均延迟应该小于100ms")
        XCTAssertLessThan(abs(memoryIncrease), 50.0, "内存增长应该小于50MB（允许GC波动）")

        // 清理
        for connection in connections {
            await connection.disconnect()
        }
    }

    // MARK: - 4. 峰值负载测试 (1个测试)

    /// 测试4.1: 峰值负载突发测试
    func testBurstLoad() async throws {
        print("\n📊 测试: 峰值突发负载 (正常→峰值→正常)")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        let testData = "Burst test".data(using: .utf8)!

        // 阶段1: 正常负载 (10秒，10 QPS)
        print("\n  阶段1: 正常负载 (10秒，10 QPS)")
        let phase1Start = Date()
        var phase1Success = 0

        for _ in 1...100 {
            try await connection.send(testData)
            phase1Success += 1
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let phase1Duration = Date().timeIntervalSince(phase1Start)
        let phase1QPS = Double(phase1Success) / phase1Duration

        // 阶段2: 峰值负载 (5秒，尽可能快)
        print("  阶段2: 峰值负载 (5秒，尽可能快)")
        let phase2Start = Date()
        var phase2Success = 0

        while Date().timeIntervalSince(phase2Start) < 5.0 {
            do {
                try await connection.send(testData)
                phase2Success += 1
            } catch {
                break
            }
        }

        let phase2Duration = Date().timeIntervalSince(phase2Start)
        let phase2QPS = Double(phase2Success) / phase2Duration

        // 阶段3: 恢复到正常负载 (10秒，10 QPS)
        print("  阶段3: 恢复正常负载 (10秒，10 QPS)")
        let phase3Start = Date()
        var phase3Success = 0

        for _ in 1...100 {
            try await connection.send(testData)
            phase3Success += 1
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        let phase3Duration = Date().timeIntervalSince(phase3Start)
        let phase3QPS = Double(phase3Success) / phase3Duration

        print("\n📊 峰值突发负载测试结果:")
        print("  阶段1 (正常): \(phase1Success)条消息, QPS=\(String(format: "%.1f", phase1QPS))")
        print("  阶段2 (峰值): \(phase2Success)条消息, QPS=\(String(format: "%.1f", phase2QPS))")
        print("  阶段3 (恢复): \(phase3Success)条消息, QPS=\(String(format: "%.1f", phase3QPS))")
        print("  峰值倍率: \(String(format: "%.1f", phase2QPS / phase1QPS))x")

        // 验证恢复能力（阶段3应该接近阶段1）
        let recoveryRate = phase3QPS / phase1QPS
        print("  恢复率: \(String(format: "%.1f", recoveryRate * 100))%")

        XCTAssertGreaterThan(phase2QPS, phase1QPS * 2, "峰值QPS应该至少是正常的2倍")
        XCTAssertGreaterThan(recoveryRate, 0.9, "应该能恢复到正常负载的90%以上")
    }

    // MARK: - Helper Methods

    /// 创建TCP连接
    private func createConnection() async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout

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
            return Double(info.resident_size) / 1024.0 / 1024.0 // 转换为MB
        } else {
            return 0.0
        }
    }
}
