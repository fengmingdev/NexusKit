//
//  PerformanceBenchmarks.swift
//  NexusKit Benchmark Tests
//
//  Created by NexusKit Contributors
//
//  性能基准测试 - 对比和验证性能指标
//

import XCTest
@testable import NexusCore
@testable import NexusTCP

/// 性能基准测试
final class PerformanceBenchmarks: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        let isRunning = await TestUtils.isTCPServerRunning()
        if !isRunning {
            throw XCTSkip("TCP测试服务器未运行")
        }
    }

    // MARK: - 连接性能基准

    /// 基准测试：连接建立时间
    func testConnectionEstablishmentBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：连接建立时间")

        let iterations = 100
        var durations: [TimeInterval] = []

        print("  测试\(iterations)次连接建立...")

        for i in 1...iterations {
            let (_, duration) = await TestUtils.measureTime {
                let conn = try await TestUtils.createTestConnection()
                await conn.disconnect(reason: .clientInitiated)
            }
            durations.append(duration)

            if i % 20 == 0 {
                print("  进度: \(i)/\(iterations)")
            }
        }

        // 统计分析
        durations.sort()
        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let minDuration = durations.first ?? 0
        let maxDuration = durations.last ?? 0
        let p50 = durations[iterations / 2]
        let p90 = durations[Int(Double(iterations) * 0.9)]
        let p95 = durations[Int(Double(iterations) * 0.95)]
        let p99 = durations[Int(Double(iterations) * 0.99)]

        print("\n  === 连接建立性能 ===")
        print("  平均: \(String(format: "%.3f", avgDuration * 1000)) ms")
        print("  最小: \(String(format: "%.3f", minDuration * 1000)) ms")
        print("  最大: \(String(format: "%.3f", maxDuration * 1000)) ms")
        print("  P50:  \(String(format: "%.3f", p50 * 1000)) ms")
        print("  P90:  \(String(format: "%.3f", p90 * 1000)) ms")
        print("  P95:  \(String(format: "%.3f", p95 * 1000)) ms")
        print("  P99:  \(String(format: "%.3f", p99 * 1000)) ms")

        // 性能断言
        XCTAssertLessThan(avgDuration, 0.5, "平均连接时间应该<500ms")
        XCTAssertLessThan(p95, 1.0, "P95连接时间应该<1s")

        TestUtils.printTestResult("连接建立基准", passed: true)
    }

    /// 基准测试：TLS握手时间
    func testTLSHandshakeBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：TLS握手时间")

        let tlsRunning = await TLSTestHelper.isTLSServerRunning()
        guard tlsRunning else {
            throw XCTSkip("TLS服务器未运行")
        }

        let iterations = 50
        var durations: [TimeInterval] = []

        print("  测试\(iterations)次TLS握手...")

        for i in 1...iterations {
            let (_, duration) = await TestUtils.measureTime {
                let conn = try await TestUtils.createTLSConnection()
                await conn.disconnect(reason: .clientInitiated)
            }
            durations.append(duration)

            if i % 10 == 0 {
                print("  进度: \(i)/\(iterations)")
            }
        }

        durations.sort()
        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let p95 = durations[Int(Double(iterations) * 0.95)]

        print("\n  === TLS握手性能 ===")
        print("  平均: \(String(format: "%.3f", avgDuration * 1000)) ms")
        print("  P95:  \(String(format: "%.3f", p95 * 1000)) ms")

        XCTAssertLessThan(avgDuration, 1.0, "平均TLS握手应该<1s")
        XCTAssertLessThan(p95, 2.0, "P95 TLS握手应该<2s")

        TestUtils.printTestResult("TLS握手基准", passed: true)
    }

    // MARK: - 消息吞吐量基准

    /// 基准测试：小消息吞吐量
    func testSmallMessageThroughputBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：小消息吞吐量")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 500
        let smallMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Small".data(using: .utf8)!
        ).encode()

        print("  发送\(iterations)条小消息...")

        let (qps, avgLatency) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: smallMessage,
                timeout: 5.0
            )
        }

        print("\n  === 小消息吞吐量 ===")
        print("  QPS: \(String(format: "%.0f", qps))")
        print("  平均延迟: \(String(format: "%.3f", avgLatency * 1000)) ms")

        XCTAssertGreaterThan(qps, 50, "小消息QPS应该>50")
        XCTAssertLessThan(avgLatency, 0.1, "小消息延迟应该<100ms")

        TestUtils.printTestResult(
            "小消息吞吐量(\(String(format: "%.0f", qps)) QPS)",
            passed: true
        )
    }

    /// 基准测试：大消息吞吐量
    func testLargeMessageThroughputBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：大消息吞吐量")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 50
        let largeBody = TestFixtures.randomData(length: 64 * 1024) // 64KB
        let largeMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: largeBody
        ).encode()

        print("  发送\(iterations)条大消息(64KB)...")

        let (qps, avgLatency) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: connection,
                message: largeMessage,
                timeout: 10.0
            )
        }

        let throughputMBps = Double(largeMessage.count) * qps / 1024 / 1024

        print("\n  === 大消息吞吐量 ===")
        print("  QPS: \(String(format: "%.0f", qps))")
        print("  吞吐量: \(String(format: "%.2f", throughputMBps)) MB/s")
        print("  平均延迟: \(String(format: "%.3f", avgLatency * 1000)) ms")

        XCTAssertGreaterThan(qps, 5, "大消息QPS应该>5")

        TestUtils.printTestResult(
            "大消息吞吐量(\(String(format: "%.0f", qps)) QPS)",
            passed: true
        )
    }

    /// 基准测试：混合消息吞吐量
    func testMixedMessageThroughputBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：混合消息吞吐量")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 100
        var successCount = 0

        let startTime = Date()

        for i in 0..<iterations {
            // 交替发送小消息和大消息
            let isSmall = i % 2 == 0
            let body = isSmall ?
                "Small\(i)".data(using: .utf8)! :
                TestFixtures.randomData(length: 32 * 1024)

            let message = TestFixtures.BinaryProtocolMessage(
                qid: UInt32(i + 1),
                fid: 1,
                body: body
            ).encode()

            do {
                _ = try await TestUtils.sendAndReceiveMessage(
                    connection: connection,
                    message: message,
                    timeout: 5.0
                )
                successCount += 1
            } catch {
                // 忽略个别失败
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        let qps = Double(successCount) / duration

        print("\n  === 混合消息吞吐量 ===")
        print("  成功: \(successCount)/\(iterations)")
        print("  QPS: \(String(format: "%.0f", qps))")
        print("  耗时: \(String(format: "%.3f", duration))s")

        XCTAssertGreaterThan(qps, 10, "混合消息QPS应该>10")

        TestUtils.printTestResult(
            "混合消息吞吐量(\(String(format: "%.0f", qps)) QPS)",
            passed: true
        )
    }

    // MARK: - 心跳性能基准

    /// 基准测试：心跳延迟
    func testHeartbeatLatencyBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：心跳延迟")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 200
        var latencies: [TimeInterval] = []

        print("  测试\(iterations)次心跳...")

        for _ in 0..<iterations {
            let (_, latency) = await TestUtils.measureTime {
                _ = try await TestUtils.sendHeartbeat(
                    connection: connection,
                    timeout: 3.0
                )
            }
            latencies.append(latency)
        }

        latencies.sort()
        let avgLatency = latencies.reduce(0, +) / Double(latencies.count)
        let p50 = latencies[iterations / 2]
        let p95 = latencies[Int(Double(iterations) * 0.95)]

        print("\n  === 心跳延迟 ===")
        print("  平均: \(String(format: "%.3f", avgLatency * 1000)) ms")
        print("  P50:  \(String(format: "%.3f", p50 * 1000)) ms")
        print("  P95:  \(String(format: "%.3f", p95 * 1000)) ms")

        XCTAssertLessThan(avgLatency, 0.05, "平均心跳延迟应该<50ms")
        XCTAssertLessThan(p95, 0.1, "P95心跳延迟应该<100ms")

        TestUtils.printTestResult("心跳延迟基准", passed: true)
    }

    /// 基准测试：心跳性能开销
    func testHeartbeatOverheadBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：心跳性能开销")

        // 测试无心跳
        let withoutHeartbeat = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .disableHeartbeat()
            .connect()

        // 测试有心跳
        let withHeartbeat = try await NexusKit.shared
            .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
            .heartbeat(interval: 1.0, timeout: 3.0)
            .connect()

        defer {
            Task {
                await withoutHeartbeat.disconnect(reason: .clientInitiated)
                await withHeartbeat.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 100
        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Overhead Test".data(using: .utf8)!
        ).encode()

        // 测试无心跳性能
        let (qpsWithout, _) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: withoutHeartbeat,
                message: testMessage,
                timeout: 3.0
            )
        }

        // 测试有心跳性能
        let (qpsWith, _) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: withHeartbeat,
                message: testMessage,
                timeout: 3.0
            )
        }

        let overhead = (qpsWithout - qpsWith) / qpsWithout * 100

        print("\n  === 心跳性能开销 ===")
        print("  无心跳QPS: \(String(format: "%.0f", qpsWithout))")
        print("  有心跳QPS: \(String(format: "%.0f", qpsWith))")
        print("  性能开销: \(String(format: "%.1f", overhead))%")

        XCTAssertLessThan(overhead, 20.0, "心跳性能开销应该<20%")

        TestUtils.printTestResult(
            "心跳开销(\(String(format: "%.1f", overhead))%)",
            passed: true
        )
    }

    // MARK: - 并发性能基准

    /// 基准测试：并发连接性能
    func testConcurrentConnectionsBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：并发连接性能")

        let concurrencyLevels = [1, 5, 10, 20, 50]

        print("\n  === 并发连接性能 ===")

        for concurrency in concurrencyLevels {
            let (_, duration) = await TestUtils.measureTime {
                try await TestUtils.runConcurrently(count: concurrency) {
                    let conn = try await TestUtils.createTestConnection()
                    await conn.disconnect(reason: .clientInitiated)
                }
            }

            let connectionsPerSecond = Double(concurrency) / duration
            print("  \(concurrency)并发: \(String(format: "%.2f", duration))s (\(String(format: "%.0f", connectionsPerSecond)) conn/s)")
        }

        TestUtils.printTestResult("并发连接基准", passed: true)
    }

    /// 基准测试：并发消息性能
    func testConcurrentMessagesBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：并发消息性能")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let concurrencyLevels = [1, 10, 50, 100]
        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Concurrent Test".data(using: .utf8)!
        ).encode()

        print("\n  === 并发消息性能 ===")

        for concurrency in concurrencyLevels {
            var successCount = 0
            let lock = NSLock()

            let (_, duration) = await TestUtils.measureTime {
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<concurrency {
                        group.addTask {
                            do {
                                _ = try await TestUtils.sendAndReceiveMessage(
                                    connection: connection,
                                    message: testMessage,
                                    timeout: 5.0
                                )
                                lock.lock()
                                successCount += 1
                                lock.unlock()
                            } catch {
                                // 忽略
                            }
                        }
                    }
                    await group.waitForAll()
                }
            }

            let qps = Double(successCount) / duration
            print("  \(concurrency)并发: \(successCount)成功, \(String(format: "%.0f", qps)) QPS")
        }

        TestUtils.printTestResult("并发消息基准", passed: true)
    }

    // MARK: - 内存性能基准

    /// 基准测试：内存占用
    func testMemoryUsageBenchmark() async throws {
        TestUtils.printTestSeparator("基准测试：内存占用")

        let initialMemory = TestUtils.currentMemoryUsage()
        print("  初始内存: \(String(format: "%.2f", Double(initialMemory) / 1024 / 1024)) MB")

        var connections: [TCPConnection] = []
        var memorySnapshots: [(connections: Int, memory: UInt64)] = []

        // 逐步创建连接并测量内存
        let connectionCounts = [1, 5, 10, 20, 50]

        for count in connectionCounts {
            // 创建更多连接达到目标数量
            let toCreate = count - connections.count
            for _ in 0..<toCreate {
                let conn = try await TestUtils.createTestConnection()
                connections.append(conn)
            }

            let currentMemory = TestUtils.currentMemoryUsage()
            memorySnapshots.append((connections: count, memory: currentMemory))

            let growth = Int64(currentMemory) - Int64(initialMemory)
            let perConnection = count > 0 ? Double(growth) / Double(count) / 1024 : 0

            print("  \(count)连接: \(String(format: "%.2f", Double(currentMemory) / 1024 / 1024)) MB (每连接: \(String(format: "%.2f", perConnection)) KB)")
        }

        // 清理
        for conn in connections {
            await conn.disconnect(reason: .clientInitiated)
        }

        let finalMemory = TestUtils.currentMemoryUsage()
        print("  清理后: \(String(format: "%.2f", Double(finalMemory) / 1024 / 1024)) MB")

        TestUtils.printTestResult("内存占用基准", passed: true)
    }

    /// 基准测试：内存泄漏检测
    func testMemoryLeakDetection() async throws {
        TestUtils.printTestSeparator("基准测试：内存泄漏检测")

        let iterations = 50
        var memorySnapshots: [UInt64] = []

        print("  创建和销毁\(iterations)次连接...")

        for i in 1...iterations {
            let conn = try await TestUtils.createTestConnection()

            // 发送一些消息
            for _ in 0..<5 {
                _ = try? await TestUtils.sendHeartbeat(
                    connection: conn,
                    timeout: 2.0
                )
            }

            await conn.disconnect(reason: .clientInitiated)

            if i % 10 == 0 {
                let memory = TestUtils.currentMemoryUsage()
                memorySnapshots.append(memory)
                print("  \(i)/\(iterations) - 内存: \(String(format: "%.2f", Double(memory) / 1024 / 1024)) MB")
            }
        }

        // 检查内存增长趋势
        if memorySnapshots.count >= 2 {
            let initialMem = memorySnapshots.first!
            let finalMem = memorySnapshots.last!
            let growth = Int64(finalMem) - Int64(initialMem)
            let growthMB = Double(growth) / 1024 / 1024

            print("\n  内存增长: \(String(format: "%.2f", growthMB)) MB")

            // 内存增长应该很小（<50MB）
            XCTAssertLessThan(abs(growthMB), 50.0, "内存增长应该<50MB")
        }

        TestUtils.printTestResult("内存泄漏检测", passed: true)
    }

    // MARK: - 协议性能基准

    /// 基准测试：TLS vs 非TLS性能
    func testTLSPerformanceComparison() async throws {
        TestUtils.printTestSeparator("基准测试：TLS vs 非TLS性能")

        let tlsRunning = await TLSTestHelper.isTLSServerRunning()
        guard tlsRunning else {
            throw XCTSkip("TLS服务器未运行")
        }

        let plainConn = try await TestUtils.createTestConnection()
        let tlsConn = try await TestUtils.createTLSConnection()

        defer {
            Task {
                await plainConn.disconnect(reason: .clientInitiated)
                await tlsConn.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 100
        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Performance Test".data(using: .utf8)!
        ).encode()

        // 非TLS性能
        let (qpsPlain, latencyPlain) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: plainConn,
                message: testMessage,
                timeout: 3.0
            )
        }

        // TLS性能
        let (qpsTLS, latencyTLS) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: tlsConn,
                message: testMessage,
                timeout: 3.0
            )
        }

        let overhead = (qpsPlain - qpsTLS) / qpsPlain * 100

        print("\n  === TLS vs 非TLS ===")
        print("  非TLS QPS: \(String(format: "%.0f", qpsPlain))")
        print("  TLS QPS:   \(String(format: "%.0f", qpsTLS))")
        print("  非TLS延迟: \(String(format: "%.3f", latencyPlain * 1000)) ms")
        print("  TLS延迟:   \(String(format: "%.3f", latencyTLS * 1000)) ms")
        print("  TLS开销:   \(String(format: "%.1f", overhead))%")

        XCTAssertLessThan(overhead, 50.0, "TLS性能开销应该<50%")

        TestUtils.printTestResult(
            "TLS性能对比(开销:\(String(format: "%.1f", overhead))%)",
            passed: true
        )
    }

    /// 基准测试：SOCKS5 vs 直连性能
    func testSOCKS5PerformanceComparison() async throws {
        TestUtils.printTestSeparator("基准测试：SOCKS5 vs 直连性能")

        let socks5Running = await TestUtils.isSOCKS5ServerRunning()
        guard socks5Running else {
            throw XCTSkip("SOCKS5服务器未运行")
        }

        let directConn = try await TestUtils.createTestConnection()
        let proxyConn = try await TestUtils.createProxiedConnection(timeout: 10.0)

        defer {
            Task {
                await directConn.disconnect(reason: .clientInitiated)
                await proxyConn.disconnect(reason: .clientInitiated)
            }
        }

        let iterations = 50
        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Proxy Test".data(using: .utf8)!
        ).encode()

        // 直连性能
        let (qpsDirect, latencyDirect) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: directConn,
                message: testMessage,
                timeout: 3.0
            )
        }

        // SOCKS5性能
        let (qpsProxy, latencyProxy) = try await TestUtils.measureThroughput(iterations: iterations) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: proxyConn,
                message: testMessage,
                timeout: 5.0
            )
        }

        let overhead = (qpsDirect - qpsProxy) / qpsDirect * 100

        print("\n  === SOCKS5 vs 直连 ===")
        print("  直连QPS:   \(String(format: "%.0f", qpsDirect))")
        print("  SOCKS5 QPS: \(String(format: "%.0f", qpsProxy))")
        print("  直连延迟:  \(String(format: "%.3f", latencyDirect * 1000)) ms")
        print("  SOCKS5延迟: \(String(format: "%.3f", latencyProxy * 1000)) ms")
        print("  SOCKS5开销: \(String(format: "%.1f", overhead))%")

        XCTAssertLessThan(overhead, 60.0, "SOCKS5性能开销应该<60%")

        TestUtils.printTestResult(
            "SOCKS5性能对比(开销:\(String(format: "%.1f", overhead))%)",
            passed: true
        )
    }

    // MARK: - 综合性能报告

    /// 综合性能基准报告
    func testComprehensivePerformanceReport() async throws {
        TestUtils.printTestSeparator("综合性能基准报告")

        var report: [String: String] = [:]

        // 1. 连接性能
        print("  [1/6] 测试连接性能...")
        let (_, connDuration) = await TestUtils.measureTime {
            let conn = try await TestUtils.createTestConnection()
            await conn.disconnect(reason: .clientInitiated)
        }
        report["连接建立"] = "\(String(format: "%.3f", connDuration * 1000)) ms"

        // 2. 消息吞吐量
        print("  [2/6] 测试消息吞吐量...")
        let conn = try await TestUtils.createTestConnection()
        defer {
            Task {
                await conn.disconnect(reason: .clientInitiated)
            }
        }

        let testMsg = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Test".data(using: .utf8)!
        ).encode()

        let (qps, _) = try await TestUtils.measureThroughput(iterations: 100) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: conn,
                message: testMsg,
                timeout: 3.0
            )
        }
        report["消息QPS"] = "\(String(format: "%.0f", qps))"

        // 3. 心跳延迟
        print("  [3/6] 测试心跳延迟...")
        let (_, hbLatency) = await TestUtils.measureTime {
            _ = try await TestUtils.sendHeartbeat(
                connection: conn,
                timeout: 3.0
            )
        }
        report["心跳延迟"] = "\(String(format: "%.3f", hbLatency * 1000)) ms"

        // 4. 内存占用
        print("  [4/6] 测试内存占用...")
        let memory = TestUtils.currentMemoryUsage()
        report["当前内存"] = "\(String(format: "%.2f", Double(memory) / 1024 / 1024)) MB"

        // 5. 并发性能
        print("  [5/6] 测试并发性能...")
        var concurrentSuccess = 0
        let lock = NSLock()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    do {
                        _ = try await TestUtils.sendHeartbeat(
                            connection: conn,
                            timeout: 3.0
                        )
                        lock.lock()
                        concurrentSuccess += 1
                        lock.unlock()
                    } catch {
                        // 忽略
                    }
                }
            }
            await group.waitForAll()
        }
        report["并发成功率"] = "\(concurrentSuccess * 10)%"

        // 6. 稳定性
        print("  [6/6] 测试稳定性...")
        var stabilitySuccess = 0
        for _ in 0..<10 {
            if (try? await TestUtils.sendHeartbeat(connection: conn, timeout: 2.0)) == true {
                stabilitySuccess += 1
            }
        }
        report["稳定性"] = "\(stabilitySuccess * 10)%"

        // 打印报告
        print("\n")
        print("  ╔══════════════════════════════════════════╗")
        print("  ║       NexusKit 性能基准报告              ║")
        print("  ╠══════════════════════════════════════════╣")
        for (key, value) in report.sorted(by: { $0.key < $1.key }) {
            let padding = String(repeating: " ", count: 20 - key.count)
            print("  ║  \(key):\(padding)\(value.padding(toLength: 15, withPad: " ", startingAt: 0))║")
        }
        print("  ╚══════════════════════════════════════════╝")

        TestUtils.printTestResult("综合性能报告", passed: true)
    }
}
