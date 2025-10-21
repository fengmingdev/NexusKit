//
//  EndToEndTests.swift
//  NexusKit Integration Tests
//
//  Created by NexusKit Contributors
//
//  端到端测试和长期稳定性验证
//

import XCTest
@testable import NexusKit
@testable import NexusKit

/// 端到端集成测试
final class EndToEndTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        let isRunning = await TestUtils.isTCPServerRunning()
        if !isRunning {
            throw XCTSkip("TCP测试服务器未运行")
        }
    }

    // MARK: - 完整生命周期测试

    /// 测试完整连接生命周期
    func testCompleteConnectionLifecycle() async throws {
        TestUtils.printTestSeparator("测试完整连接生命周期")

        // 1. 创建连接
        print("  [1/6] 创建连接...")
        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 2.0, timeout: 5.0)
            .timeout(5.0)
            .connect()

        var stateChanges: [ConnectionState] = [await connection.state]

        // 2. 验证连接状态
        print("  [2/6] 验证连接状态...")
        XCTAssertEqual(await connection.state, .connected)

        // 3. 发送消息
        print("  [3/6] 发送消息...")
        for i in 1...5 {
            let msg = TestFixtures.BinaryProtocolMessage(
                qid: UInt32(i),
                fid: 1,
                body: "Lifecycle Test \(i)".data(using: .utf8)!
            ).encode()

            let response = try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: msg,
                timeout: 5.0
            )
            XCTAssertFalse(response.isEmpty, "消息\(i)应该有响应")
        }

        // 4. 心跳维持
        print("  [4/6] 心跳维持...")
        for i in 1...3 {
            let success = try await TestUtils.sendHeartbeat(
                connection: connection,
                timeout: 5.0
            )
            XCTAssertTrue(success, "心跳\(i)应该成功")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        // 5. 优雅断开
        print("  [5/6] 优雅断开...")
        await connection.disconnect(reason: .clientInitiated)
        stateChanges.append(await connection.state)

        // 6. 验证断开状态
        print("  [6/6] 验证断开状态...")
        XCTAssertEqual(await connection.state, .disconnected)

        print("  状态变化: \(stateChanges)")

        TestUtils.printTestResult("完整连接生命周期", passed: true)
    }

    /// 测试重连机制
    func testReconnectionMechanism() async throws {
        TestUtils.printTestSeparator("测试重连机制")

        var connectCount = 0
        let maxReconnects = 5

        for attempt in 1...maxReconnects {
            print("  尝试连接 \(attempt)/\(maxReconnects)...")

            do {
                let connection = try await TestUtils.createTestConnection()

                // 验证连接
                let success = try await TestUtils.sendHeartbeat(
                    connection: connection,
                    timeout: 3.0
                )

                if success {
                    connectCount += 1
                }

                // 断开
                await connection.disconnect(reason: .clientInitiated)

                // 等待一小段时间再重连
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                print("  连接失败: \(error)")
            }
        }

        let successRate = Double(connectCount) / Double(maxReconnects) * 100
        print("  重连成功率: \(String(format: "%.1f", successRate))%")

        XCTAssertGreaterThan(successRate, 80.0, "重连成功率应该大于80%")

        TestUtils.printTestResult(
            "重连机制(成功率:\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    /// 测试多协议组合
    func testMultiProtocolCombination() async throws {
        TestUtils.printTestSeparator("测试多协议组合")

        // 检查所有服务器是否运行
        let tlsRunning = await TLSTestHelper.isTLSServerRunning()
        let socks5Running = await TestUtils.isSOCKS5ServerRunning()

        guard tlsRunning && socks5Running else {
            throw XCTSkip("需要所有测试服务器运行")
        }

        // 1. TCP连接
        print("  [1/3] TCP连接...")
        let tcpConn = try await TestUtils.createTestConnection()
        let tcpSuccess = try await TestUtils.sendHeartbeat(
            connection: tcpConn,
            timeout: 3.0
        )
        XCTAssertTrue(tcpSuccess, "TCP连接应该成功")
        await tcpConn.disconnect(reason: .clientInitiated)

        // 2. TLS连接
        print("  [2/3] TLS连接...")
        let tlsConn = try await TestUtils.createTLSConnection()
        let tlsSuccess = try await TestUtils.sendHeartbeat(
            connection: tlsConn,
            timeout: 3.0
        )
        XCTAssertTrue(tlsSuccess, "TLS连接应该成功")
        await tlsConn.disconnect(reason: .clientInitiated)

        // 3. SOCKS5代理连接
        print("  [3/3] SOCKS5代理连接...")
        let proxyConn = try await TestUtils.createProxiedConnection()
        let proxySuccess = try await TestUtils.sendHeartbeat(
            connection: proxyConn,
            timeout: 5.0
        )
        XCTAssertTrue(proxySuccess, "SOCKS5代理连接应该成功")
        await proxyConn.disconnect(reason: .clientInitiated)

        TestUtils.printTestResult("多协议组合", passed: true)
    }

    // MARK: - 长期稳定性测试

    /// 测试1小时稳定性（简化为5分钟）
    func testLongTermStability() async throws {
        TestUtils.printTestSeparator("测试长期稳定性(5分钟)")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 5.0, timeout: 15.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let testDuration: TimeInterval = 300.0 // 5分钟
        let checkInterval: TimeInterval = 10.0 // 每10秒检查一次
        let totalChecks = Int(testDuration / checkInterval)

        var successCount = 0
        var failCount = 0
        var latencies: [TimeInterval] = []

        print("  开始长期稳定性测试（\(Int(testDuration))秒，每\(Int(checkInterval))秒检查）...")

        for i in 1...totalChecks {
            let (success, latency) = await TestUtils.measureTime {
                do {
                    _ = try await TestUtils.sendHeartbeat(
                        connection: connection,
                        timeout: 10.0
                    )
                    return true
                } catch {
                    return false
                }
            }

            if success {
                successCount += 1
                latencies.append(latency)
            } else {
                failCount += 1
            }

            if i % 6 == 0 || i == totalChecks {
                let elapsed = Double(i) * checkInterval
                let rate = Double(successCount) / Double(i) * 100
                print("  进度: \(Int(elapsed))s/\(Int(testDuration))s - 成功率: \(String(format: "%.1f", rate))%")
            }

            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
        }

        // 统计分析
        let successRate = Double(successCount) / Double(totalChecks) * 100
        let avgLatency = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)

        print("\n  === 稳定性测试结果 ===")
        print("  总检查次数: \(totalChecks)")
        print("  成功次数: \(successCount)")
        print("  失败次数: \(failCount)")
        print("  成功率: \(String(format: "%.2f", successRate))%")
        print("  平均延迟: \(String(format: "%.3f", avgLatency * 1000)) ms")

        XCTAssertGreaterThan(successRate, 90.0, "长期稳定性应该大于90%")

        TestUtils.printTestResult(
            "长期稳定性(成功率:\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    /// 测试高负载稳定性
    func testHighLoadStability() async throws {
        TestUtils.printTestSeparator("测试高负载稳定性")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let messageCount = 1000
        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "High Load Test".data(using: .utf8)!
        ).encode()

        var successCount = 0
        var failCount = 0
        var totalLatency: TimeInterval = 0

        print("  发送\(messageCount)条消息...")

        let (_, totalDuration) = await TestUtils.measureTime {
            for i in 0..<messageCount {
                let (success, latency) = await TestUtils.measureTime {
                    do {
                        _ = try await TestUtils.sendAndReceiveMessage(
                            connection: connection,
                            message: testMessage,
                            timeout: 5.0
                        )
                        return true
                    } catch {
                        return false
                    }
                }

                if success {
                    successCount += 1
                    totalLatency += latency
                } else {
                    failCount += 1
                }

                if (i + 1) % 100 == 0 {
                    let rate = Double(successCount) / Double(i + 1) * 100
                    print("  进度: \(i + 1)/\(messageCount) - 成功率: \(String(format: "%.1f", rate))%")
                }
            }
        }

        let successRate = Double(successCount) / Double(messageCount) * 100
        let avgLatency = successCount > 0 ? totalLatency / Double(successCount) : 0
        let qps = Double(successCount) / totalDuration

        print("\n  === 高负载测试结果 ===")
        print("  成功: \(successCount)")
        print("  失败: \(failCount)")
        print("  成功率: \(String(format: "%.2f", successRate))%")
        print("  总耗时: \(String(format: "%.3f", totalDuration))s")
        print("  平均延迟: \(String(format: "%.3f", avgLatency * 1000)) ms")
        print("  QPS: \(String(format: "%.0f", qps))")

        XCTAssertGreaterThan(successRate, 95.0, "高负载成功率应该大于95%")
        XCTAssertGreaterThan(qps, 50, "高负载QPS应该大于50")

        TestUtils.printTestResult(
            "高负载稳定性(成功率:\(String(format: "%.1f", successRate))%, QPS:\(String(format: "%.0f", qps)))",
            passed: true
        )
    }

    /// 测试内存稳定性
    func testMemoryStability() async throws {
        TestUtils.printTestSeparator("测试内存稳定性")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 100
        let messageSize = 10 * 1024 // 10KB

        let initialMemory = TestUtils.currentMemoryUsage()
        print("  初始内存: \(String(format: "%.2f", Double(initialMemory) / 1024 / 1024)) MB")

        var memorySnapshots: [UInt64] = [initialMemory]

        for i in 1...iterations {
            // 发送大消息
            let largeBody = TestFixtures.randomData(length: messageSize)
            let largeMessage = TestFixtures.BinaryProtocolMessage(
                qid: UInt32(i),
                fid: 1,
                body: largeBody
            ).encode()

            _ = try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: largeMessage,
                timeout: 5.0
            )

            if i % 20 == 0 {
                let currentMemory = TestUtils.currentMemoryUsage()
                memorySnapshots.append(currentMemory)
                print("  \(i)/\(iterations) - 内存: \(String(format: "%.2f", Double(currentMemory) / 1024 / 1024)) MB")
            }
        }

        let finalMemory = TestUtils.currentMemoryUsage()
        let memoryGrowth = Int64(finalMemory) - Int64(initialMemory)
        let growthMB = Double(memoryGrowth) / 1024 / 1024

        print("  最终内存: \(String(format: "%.2f", Double(finalMemory) / 1024 / 1024)) MB")
        print("  内存增长: \(String(format: "%.2f", growthMB)) MB")

        // 内存增长应该合理（小于100MB）
        XCTAssertLessThan(abs(growthMB), 100.0, "内存增长应该小于100MB")

        TestUtils.printTestResult(
            "内存稳定性(增长:\(String(format: "%.2f", growthMB))MB)",
            passed: true
        )
    }

    // MARK: - 并发场景测试

    /// 测试多连接并发场景
    func testMultiConnectionConcurrency() async throws {
        TestUtils.printTestSeparator("测试多连接并发场景")

        let connectionCount = 20
        var connections: [TCPConnection] = []

        // 创建多个连接
        print("  创建\(connectionCount)个连接...")
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

        // 并发发送消息
        let messagesPerConnection = 10
        var totalSuccess = 0
        let lock = NSLock()

        print("  每个连接发送\(messagesPerConnection)条消息...")

        await withTaskGroup(of: Int.self) { group in
            for (index, conn) in connections.enumerated() {
                group.addTask {
                    var successCount = 0

                    for i in 0..<messagesPerConnection {
                        let msg = TestFixtures.BinaryProtocolMessage(
                            qid: UInt32(i + 1),
                            fid: 1,
                            body: "Conn\(index)-Msg\(i)".data(using: .utf8)!
                        ).encode()

                        do {
                            _ = try await TestUtils.sendAndReceiveMessage(
                                connection: conn,
                                message: msg,
                                timeout: 5.0
                            )
                            successCount += 1
                        } catch {
                            // 忽略个别失败
                        }
                    }

                    return successCount
                }
            }

            for await success in group {
                lock.lock()
                totalSuccess += success
                lock.unlock()
            }
        }

        let totalMessages = connectionCount * messagesPerConnection
        let successRate = Double(totalSuccess) / Double(totalMessages) * 100

        print("  总消息数: \(totalMessages)")
        print("  成功数: \(totalSuccess)")
        print("  成功率: \(String(format: "%.2f", successRate))%")

        XCTAssertGreaterThan(successRate, 80.0, "并发成功率应该大于80%")

        TestUtils.printTestResult(
            "多连接并发(成功率:\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    /// 测试混合负载场景
    func testMixedLoadScenario() async throws {
        TestUtils.printTestSeparator("测试混合负载场景")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var smallMessageSuccess = 0
        var largeMessageSuccess = 0
        var heartbeatSuccess = 0

        let duration: TimeInterval = 30.0
        let startTime = Date()

        print("  运行混合负载测试（\(Int(duration))秒）...")

        await withTaskGroup(of: Void.self) { group in
            // 任务1: 小消息
            group.addTask {
                while Date().timeIntervalSince(startTime) < duration {
                    let msg = TestFixtures.BinaryProtocolMessage(
                        qid: 1,
                        fid: 1,
                        body: "Small".data(using: .utf8)!
                    ).encode()

                    do {
                        _ = try await TestUtils.sendAndReceiveMessage(
                            connection: connection,
                            message: msg,
                            timeout: 3.0
                        )
                        smallMessageSuccess += 1
                    } catch {
                        // 忽略
                    }

                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }

            // 任务2: 大消息
            group.addTask {
                while Date().timeIntervalSince(startTime) < duration {
                    let largeBody = TestFixtures.randomData(length: 64 * 1024)
                    let msg = TestFixtures.BinaryProtocolMessage(
                        qid: 2,
                        fid: 1,
                        body: largeBody
                    ).encode()

                    do {
                        _ = try await TestUtils.sendAndReceiveMessage(
                            connection: connection,
                            message: msg,
                            timeout: 5.0
                        )
                        largeMessageSuccess += 1
                    } catch {
                        // 忽略
                    }

                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }

            // 任务3: 心跳
            group.addTask {
                while Date().timeIntervalSince(startTime) < duration {
                    do {
                        let success = try await TestUtils.sendHeartbeat(
                            connection: connection,
                            timeout: 3.0
                        )
                        if success {
                            heartbeatSuccess += 1
                        }
                    } catch {
                        // 忽略
                    }

                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }

            await group.waitForAll()
        }

        print("\n  === 混合负载结果 ===")
        print("  小消息成功: \(smallMessageSuccess)")
        print("  大消息成功: \(largeMessageSuccess)")
        print("  心跳成功: \(heartbeatSuccess)")

        XCTAssertGreaterThan(smallMessageSuccess, 100, "应该完成大量小消息")
        XCTAssertGreaterThan(largeMessageSuccess, 10, "应该完成一些大消息")
        XCTAssertGreaterThan(heartbeatSuccess, 5, "应该完成多次心跳")

        TestUtils.printTestResult("混合负载场景", passed: true)
    }

    // MARK: - 错误恢复测试

    /// 测试错误恢复能力
    func testErrorRecovery() async throws {
        TestUtils.printTestSeparator("测试错误恢复能力")

        var recoveryCount = 0
        let testIterations = 10

        for i in 1...testIterations {
            print("  迭代 \(i)/\(testIterations)...")

            do {
                let connection = try await TestUtils.createTestConnection()

                // 正常操作
                _ = try await TestUtils.sendHeartbeat(
                    connection: connection,
                    timeout: 3.0
                )

                // 模拟错误：发送无效数据
                let invalidData = Data([0x00, 0x01, 0x02])
                try? await connection.send(invalidData, timeout: 1.0)

                // 尝试恢复：发送正常消息
                let normalSuccess = try await TestUtils.sendHeartbeat(
                    connection: connection,
                    timeout: 3.0
                )

                if normalSuccess {
                    recoveryCount += 1
                    print("    ✓ 恢复成功")
                } else {
                    print("    ✗ 恢复失败")
                }

                await connection.disconnect(reason: .clientInitiated)
            } catch {
                print("    ✗ 连接失败: \(error)")
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let recoveryRate = Double(recoveryCount) / Double(testIterations) * 100
        print("  恢复成功率: \(String(format: "%.1f", recoveryRate))%")

        XCTAssertGreaterThan(recoveryRate, 70.0, "错误恢复率应该大于70%")

        TestUtils.printTestResult(
            "错误恢复(成功率:\(String(format: "%.1f", recoveryRate))%)",
            passed: true
        )
    }

    /// 测试极限场景
    func testExtremeScenarios() async throws {
        TestUtils.printTestSeparator("测试极限场景")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var scenarioResults: [String: Bool] = [:]

        // 场景1: 极小消息
        print("  [1/4] 极小消息...")
        do {
            let tinyMsg = TestFixtures.BinaryProtocolMessage(
                qid: 1,
                fid: 1,
                body: Data([0x00])
            ).encode()
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: tinyMsg,
                timeout: 3.0
            )
            scenarioResults["极小消息"] = true
        } catch {
            scenarioResults["极小消息"] = false
        }

        // 场景2: 极大消息（1MB）
        print("  [2/4] 极大消息...")
        do {
            let hugeBody = TestFixtures.randomData(length: 1024 * 1024)
            let hugeMsg = TestFixtures.BinaryProtocolMessage(
                qid: 2,
                fid: 1,
                body: hugeBody
            ).encode()
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: hugeMsg,
                timeout: 15.0
            )
            scenarioResults["极大消息"] = true
        } catch {
            scenarioResults["极大消息"] = false
        }

        // 场景3: 快速连续消息
        print("  [3/4] 快速连续消息...")
        do {
            var rapidSuccess = 0
            for i in 0..<50 {
                let msg = TestFixtures.BinaryProtocolMessage(
                    qid: UInt32(i + 1),
                    fid: 1,
                    body: "Rapid\(i)".data(using: .utf8)!
                ).encode()

                do {
                    _ = try await TestUtils.sendAndReceiveMessage(
                        connection: connection,
                        message: msg,
                        timeout: 2.0
                    )
                    rapidSuccess += 1
                } catch {
                    // 忽略个别失败
                }
            }
            scenarioResults["快速连续消息"] = rapidSuccess > 40
        } catch {
            scenarioResults["快速连续消息"] = false
        }

        // 场景4: Unicode特殊字符
        print("  [4/4] Unicode特殊字符...")
        do {
            let specialText = "Test™®©℗℠№§¶†‡µ¢£¥€¤"
            let specialMsg = TestFixtures.BinaryProtocolMessage(
                qid: 4,
                fid: 1,
                body: specialText.data(using: .utf8)!
            ).encode()
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: specialMsg,
                timeout: 3.0
            )
            scenarioResults["Unicode特殊字符"] = true
        } catch {
            scenarioResults["Unicode特殊字符"] = false
        }

        // 统计结果
        print("\n  === 极限场景结果 ===")
        for (scenario, passed) in scenarioResults {
            let status = passed ? "✓" : "✗"
            print("  \(status) \(scenario)")
        }

        let passedCount = scenarioResults.values.filter { $0 }.count
        let totalCount = scenarioResults.count
        let passRate = Double(passedCount) / Double(totalCount) * 100

        XCTAssertGreaterThanOrEqual(passedCount, totalCount - 1, "至少通过3/4场景")

        TestUtils.printTestResult(
            "极限场景(\(passedCount)/\(totalCount)通过)",
            passed: passedCount >= totalCount - 1
        )
    }
}
