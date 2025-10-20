//
//  SOCKS5IntegrationTests.swift
//  NexusKit Integration Tests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore
@testable import NexusTCP

/// SOCKS5代理集成测试
final class SOCKS5IntegrationTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        let isRunning = await TestUtils.isSOCKS5ServerRunning()
        if !isRunning {
            throw XCTSkip("SOCKS5测试服务器未运行。请先启动: cd TestServers && npm run socks5")
        }

        // 确保TCP目标服务器也在运行
        let isTCPRunning = await TestUtils.isTCPServerRunning()
        if !isTCPRunning {
            throw XCTSkip("TCP目标服务器未运行。请先启动: cd TestServers && npm run tcp")
        }
    }

    // MARK: - 基础代理连接测试

    /// 测试无认证SOCKS5连接
    func testBasicSOCKS5Connection() async throws {
        TestUtils.printTestSeparator("测试无认证SOCKS5连接")

        let connection = try await TestUtils.createProxiedConnection()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .connected, "SOCKS5代理连接应该成功")

        TestUtils.printTestResult("无认证SOCKS5连接", passed: true)
    }

    /// 测试SOCKS5 IPv4地址
    func testSOCKS5IPv4Address() async throws {
        TestUtils.printTestSeparator("测试SOCKS5 IPv4地址")

        let proxyConfig = ProxyConfiguration.socks5(
            host: TestFixtures.socks5Host,
            port: TestFixtures.socks5Port,
            username: nil,
            password: nil
        )

        let connection = try await NexusKit.shared
            .tcp(host: "127.0.0.1", port: TestFixtures.tcpPort) // IPv4
            .proxy(proxyConfig)
            .timeout(5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .connected, "IPv4地址应该成功")

        TestUtils.printTestResult("SOCKS5 IPv4地址", passed: true)
    }

    /// 测试SOCKS5域名
    func testSOCKS5DomainName() async throws {
        TestUtils.printTestSeparator("测试SOCKS5域名")

        let proxyConfig = ProxyConfiguration.socks5(
            host: TestFixtures.socks5Host,
            port: TestFixtures.socks5Port,
            username: nil,
            password: nil
        )

        let connection = try await NexusKit.shared
            .tcp(host: "localhost", port: TestFixtures.tcpPort) // 域名
            .proxy(proxyConfig)
            .timeout(5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .connected, "域名应该成功")

        TestUtils.printTestResult("SOCKS5域名", passed: true)
    }

    // MARK: - SOCKS5消息收发测试

    /// 测试通过SOCKS5发送消息
    func testSOCKS5MessageSendReceive() async throws {
        TestUtils.printTestSeparator("测试通过SOCKS5发送消息")

        let connection = try await TestUtils.createProxiedConnection()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Proxied Message".data(using: .utf8)!
        ).encode()

        let response = try await TestUtils.sendAndReceiveMessage(
            connection: connection,
            message: testMessage,
            timeout: 5.0
        )

        XCTAssertFalse(response.isEmpty, "应该收到响应")

        if let responseMsg = TestFixtures.BinaryProtocolMessage.decode(response) {
            XCTAssertEqual(responseMsg.res, 1, "应该是响应消息")
            XCTAssertEqual(responseMsg.code, 200, "响应码应该是200")
        } else {
            XCTFail("无法解析响应")
        }

        TestUtils.printTestResult("SOCKS5消息收发", passed: true)
    }

    /// 测试SOCKS5大消息传输
    func testSOCKS5LargeMessage() async throws {
        TestUtils.printTestSeparator("测试SOCKS5大消息传输")

        let connection = try await TestUtils.createProxiedConnection(timeout: 10.0)

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 64KB消息
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

        XCTAssertLessThan(duration, 10.0, "大消息传输应该在10秒内完成")

        TestUtils.printTestResult(
            "SOCKS5大消息传输(\(String(format: "%.3f", duration))s)",
            passed: true
        )
    }

    // MARK: - SOCKS5心跳测试

    /// 测试SOCKS5连接心跳
    func testSOCKS5Heartbeat() async throws {
        TestUtils.printTestSeparator("测试SOCKS5连接心跳")

        let connection = try await TestUtils.createProxiedConnection()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let success = try await TestUtils.sendHeartbeat(
            connection: connection,
            timeout: 5.0
        )

        XCTAssertTrue(success, "通过SOCKS5的心跳应该成功")

        TestUtils.printTestResult("SOCKS5连接心跳", passed: true)
    }

    /// 测试SOCKS5多次心跳
    func testSOCKS5MultipleHeartbeats() async throws {
        TestUtils.printTestSeparator("测试SOCKS5多次心跳")

        let connection = try await TestUtils.createProxiedConnection()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        var successCount = 0

        for _ in 0..<10 {
            let success = try await TestUtils.sendHeartbeat(
                connection: connection,
                timeout: 5.0
            )

            if success {
                successCount += 1
            }

            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        XCTAssertGreaterThanOrEqual(successCount, 8, "至少80%的心跳应该成功")

        TestUtils.printTestResult(
            "SOCKS5多次心跳(\(successCount)/10)",
            passed: true
        )
    }

    // MARK: - SOCKS5性能测试

    /// 测试SOCKS5连接建立时间
    func testSOCKS5ConnectionSpeed() async throws {
        TestUtils.printTestSeparator("测试SOCKS5连接建立时间")

        var durations: [TimeInterval] = []

        for _ in 0..<5 {
            let (_, duration) = await TestUtils.measureTime {
                let conn = try await TestUtils.createProxiedConnection()
                await conn.disconnect(reason: .clientInitiated)
            }
            durations.append(duration)
        }

        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let maxDuration = durations.max() ?? 0

        print("  平均连接时间: \(String(format: "%.3f", avgDuration))s")
        print("  最大连接时间: \(String(format: "%.3f", maxDuration))s")

        XCTAssertLessThan(avgDuration, 2.0, "平均SOCKS5连接应该小于2秒")

        TestUtils.printTestResult(
            "SOCKS5连接速度(平均\(String(format: "%.3f", avgDuration))s)",
            passed: true
        )
    }

    /// 测试SOCKS5 vs 直连性能对比
    func testSOCKS5VsDirectPerformance() async throws {
        TestUtils.printTestSeparator("测试SOCKS5 vs 直连性能")

        let proxiedConn = try await TestUtils.createProxiedConnection(timeout: 10.0)
        let directConn = try await TestUtils.createTestConnection()

        defer {
            Task {
                await proxiedConn.disconnect(reason: .clientInitiated)
                await directConn.disconnect(reason: .clientInitiated)
            }
        }

        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Performance Test".data(using: .utf8)!
        ).encode()

        // SOCKS5性能
        let (qpsProxied, _) = try await TestUtils.measureThroughput(iterations: 30) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: proxiedConn,
                message: testMessage,
                timeout: 5.0
            )
        }

        // 直连性能
        let (qpsDirect, _) = try await TestUtils.measureThroughput(iterations: 30) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: directConn,
                message: testMessage,
                timeout: 3.0
            )
        }

        print("  SOCKS5 QPS: \(String(format: "%.0f", qpsProxied))")
        print("  直连 QPS: \(String(format: "%.0f", qpsDirect))")

        let overhead = (qpsDirect - qpsProxied) / qpsDirect * 100
        print("  SOCKS5性能开销: \(String(format: "%.1f", overhead))%")

        // SOCKS5开销应该小于60%（代理有额外跳转）
        XCTAssertLessThan(overhead, 60.0, "SOCKS5性能开销应该小于60%")

        TestUtils.printTestResult(
            "SOCKS5 vs 直连(开销\(String(format: "%.1f", overhead))%)",
            passed: true
        )
    }

    // MARK: - SOCKS5稳定性测试

    /// 测试SOCKS5长连接稳定性
    func testSOCKS5LongLivedConnection() async throws {
        TestUtils.printTestSeparator("测试SOCKS5长连接稳定性")

        let connection = try await TestUtils.createProxiedConnection(timeout: 10.0)

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let duration: TimeInterval = 30.0
        let iterations = 15

        var successCount = 0

        for _ in 1...iterations {
            let success = try await TestUtils.sendHeartbeat(
                connection: connection,
                timeout: 5.0
            )

            if success {
                successCount += 1
            }

            try await Task.sleep(nanoseconds: UInt64(duration / Double(iterations) * 1_000_000_000))
        }

        let successRate = Double(successCount) / Double(iterations) * 100
        XCTAssertGreaterThan(successRate, 80.0, "SOCKS5长连接成功率应该大于80%")

        TestUtils.printTestResult(
            "SOCKS5长连接稳定性(\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    // MARK: - SOCKS5并发测试

    /// 测试SOCKS5并发连接
    func testSOCKS5ConcurrentConnections() async throws {
        TestUtils.printTestSeparator("测试SOCKS5并发连接")

        let connectionCount = 5 // SOCKS5代理较慢，减少并发数

        let (_, duration) = await TestUtils.measureTime {
            try await TestUtils.runConcurrently(count: connectionCount) {
                let conn = try await TestUtils.createProxiedConnection(timeout: 10.0)
                await conn.disconnect(reason: .clientInitiated)
            }
        }

        XCTAssertLessThan(duration, 30.0, "\(connectionCount)个SOCKS5并发连接应该在30秒内完成")

        TestUtils.printTestResult(
            "SOCKS5并发连接(\(connectionCount)个, \(String(format: "%.3f", duration))s)",
            passed: true
        )
    }

    // MARK: - SOCKS5错误处理测试

    /// 测试连接到不存在的目标
    func testSOCKS5InvalidTarget() async throws {
        TestUtils.printTestSeparator("测试SOCKS5连接到无效目标")

        let proxyConfig = ProxyConfiguration.socks5(
            host: TestFixtures.socks5Host,
            port: TestFixtures.socks5Port,
            username: nil,
            password: nil
        )

        do {
            _ = try await NexusKit.shared
                .tcp(host: "127.0.0.1", port: 9999) // 不存在的端口
                .proxy(proxyConfig)
                .timeout(5.0)
                .connect()

            XCTFail("连接到无效目标应该失败")
        } catch {
            // 预期会失败
            TestUtils.printTestResult("SOCKS5连接到无效目标", passed: true)
        }
    }

    /// 测试无效的代理地址
    func testSOCKS5InvalidProxy() async throws {
        TestUtils.printTestSeparator("测试无效的SOCKS5代理")

        let proxyConfig = ProxyConfiguration.socks5(
            host: "127.0.0.1",
            port: 9999, // 不存在的代理端口
            username: nil,
            password: nil
        )

        do {
            _ = try await NexusKit.shared
                .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
                .proxy(proxyConfig)
                .timeout(5.0)
                .connect()

            XCTFail("连接到无效代理应该失败")
        } catch {
            // 预期会失败
            TestUtils.printTestResult("无效的SOCKS5代理", passed: true)
        }
    }

    // MARK: - SOCKS5 + TLS测试

    /// 测试SOCKS5 + TLS组合
    func testSOCKS5WithTLS() async throws {
        TestUtils.printTestSeparator("测试SOCKS5 + TLS组合")

        // 检查TLS服务器是否运行
        let isTLSRunning = await TLSTestHelper.isTLSServerRunning()
        if !isTLSRunning {
            throw XCTSkip("TLS服务器未运行")
        }

        let proxyConfig = ProxyConfiguration.socks5(
            host: TestFixtures.socks5Host,
            port: TestFixtures.socks5Port,
            username: nil,
            password: nil
        )

        let tlsConfig = TLSTestHelper.createInsecureConfiguration()

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
            .proxy(proxyConfig)
            .tls(tlsConfig)
            .timeout(10.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .connected, "SOCKS5 + TLS应该成功")

        // 发送消息验证
        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Proxied TLS Message".data(using: .utf8)!
        ).encode()

        let response = try await TestUtils.sendAndReceiveMessage(
            connection: connection,
            message: testMessage,
            timeout: 5.0
        )

        XCTAssertFalse(response.isEmpty, "应该收到响应")

        TestUtils.printTestResult("SOCKS5 + TLS组合", passed: true)
    }
}
