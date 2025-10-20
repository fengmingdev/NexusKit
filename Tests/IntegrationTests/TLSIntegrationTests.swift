//
//  TLSIntegrationTests.swift
//  NexusKit Integration Tests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore
@testable import NexusTCP

/// TLS/SSL集成测试
final class TLSIntegrationTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        let isRunning = await TLSTestHelper.isTLSServerRunning()
        if !isRunning {
            throw XCTSkip("TLS测试服务器未运行。请先启动: cd TestServers && npm run tls")
        }
    }

    // MARK: - 基础TLS连接测试

    /// 测试基础TLS连接（允许自签名）
    func testBasicTLSConnection() async throws {
        TestUtils.printTestSeparator("测试基础TLS连接")

        let tlsConfig = TLSTestHelper.createInsecureConfiguration()

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
            .tls(tlsConfig)
            .timeout(5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .connected, "TLS连接应该成功")

        TestUtils.printTestResult("基础TLS连接", passed: true)
    }

    /// 测试TLS版本协商
    func testTLSVersionNegotiation() async throws {
        TestUtils.printTestSeparator("测试TLS版本协商")

        let versions: [TLSConfiguration.TLSVersion] = [.tls12, .tls13, .automatic]

        for version in versions {
            let tlsConfig = TLSConfiguration(
                enabled: true,
                version: version,
                p12Certificate: nil,
                validationPolicy: .disabled,
                cipherSuites: .default,
                serverName: nil,
                alpnProtocols: nil,
                allowSelfSigned: true
            )

            do {
                let connection = try await NexusKit.shared
                    .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
                    .tls(tlsConfig)
                    .timeout(5.0)
                    .connect()

                let state = await connection.state
                XCTAssertEqual(state, .connected, "TLS \(version)连接应该成功")

                await connection.disconnect(reason: .clientInitiated)

                print("  TLS \(version): ✓")
            } catch {
                XCTFail("TLS \(version)连接失败: \(error)")
            }
        }

        TestUtils.printTestResult("TLS版本协商", passed: true)
    }

    // MARK: - 证书固定测试

    /// 测试证书固定
    func testCertificatePinning() async throws {
        TestUtils.printTestSeparator("测试证书固定")

        // 加载测试证书
        let tlsConfig = try TLSTestHelper.createPinningConfiguration()

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
            .tls(tlsConfig)
            .timeout(5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .connected, "证书固定连接应该成功")

        TestUtils.printTestResult("证书固定", passed: true)
    }

    /// 测试错误的证书固定
    func testInvalidCertificatePinning() async throws {
        TestUtils.printTestSeparator("测试错误的证书固定")

        // 使用错误的证书数据
        let invalidCertData = Data([0x00, 0x01, 0x02, 0x03])
        let pinnedCert = TLSConfiguration.ValidationPolicy.CertificateData(data: invalidCertData)

        let tlsConfig = TLSConfiguration(
            enabled: true,
            version: .automatic,
            p12Certificate: nil,
            validationPolicy: .pinning([pinnedCert]),
            cipherSuites: .default,
            serverName: nil,
            alpnProtocols: nil,
            allowSelfSigned: false
        )

        do {
            _ = try await NexusKit.shared
                .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
                .tls(tlsConfig)
                .timeout(5.0)
                .connect()

            XCTFail("错误的证书固定应该失败")
        } catch {
            // 预期会失败
            TestUtils.printTestResult("错误的证书固定", passed: true)
        }
    }

    // MARK: - 密码套件测试

    /// 测试现代密码套件
    func testModernCipherSuites() async throws {
        TestUtils.printTestSeparator("测试现代密码套件")

        let tlsConfig = TLSConfiguration(
            enabled: true,
            version: .automatic,
            p12Certificate: nil,
            validationPolicy: .disabled,
            cipherSuites: .modern,
            serverName: nil,
            alpnProtocols: nil,
            allowSelfSigned: true
        )

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
            .tls(tlsConfig)
            .timeout(5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .connected, "现代密码套件连接应该成功")

        TestUtils.printTestResult("现代密码套件", passed: true)
    }

    /// 测试兼容密码套件
    func testCompatibleCipherSuites() async throws {
        TestUtils.printTestSeparator("测试兼容密码套件")

        let tlsConfig = TLSConfiguration(
            enabled: true,
            version: .automatic,
            p12Certificate: nil,
            validationPolicy: .disabled,
            cipherSuites: .compatible,
            serverName: nil,
            alpnProtocols: nil,
            allowSelfSigned: true
        )

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
            .tls(tlsConfig)
            .timeout(5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .connected, "兼容密码套件连接应该成功")

        TestUtils.printTestResult("兼容密码套件", passed: true)
    }

    // MARK: - TLS消息收发测试

    /// 测试TLS加密消息发送
    func testTLSMessageSendReceive() async throws {
        TestUtils.printTestSeparator("测试TLS加密消息发送")

        let connection = try await TestUtils.createTLSConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Encrypted Message".data(using: .utf8)!
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

            let responseText = String(data: responseMsg.body, encoding: .utf8) ?? ""
            XCTAssertTrue(responseText.contains("received"), "响应应该包含'received'")
        } else {
            XCTFail("无法解析响应")
        }

        TestUtils.printTestResult("TLS加密消息发送", passed: true)
    }

    /// 测试TLS大消息传输
    func testTLSLargeMessageTransfer() async throws {
        TestUtils.printTestSeparator("测试TLS大消息传输")

        let connection = try await TestUtils.createTLSConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 128KB消息
        let largeBody = TestFixtures.randomData(length: 131072)
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

        XCTAssertLessThan(duration, 10.0, "128KB消息传输应该在10秒内完成")

        TestUtils.printTestResult(
            "TLS大消息传输(\(String(format: "%.3f", duration))s)",
            passed: true
        )
    }

    // MARK: - TLS心跳测试

    /// 测试TLS连接心跳
    func testTLSHeartbeat() async throws {
        TestUtils.printTestSeparator("测试TLS连接心跳")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
            .tls(TLSTestHelper.createInsecureConfiguration())
            .heartbeat(interval: 2.0, timeout: 5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 发送手动心跳
        let success = try await TestUtils.sendHeartbeat(
            connection: connection,
            timeout: 5.0
        )

        XCTAssertTrue(success, "TLS心跳应该成功")

        TestUtils.printTestResult("TLS连接心跳", passed: true)
    }

    // MARK: - TLS性能测试

    /// 测试TLS握手性能
    func testTLSHandshakePerformance() async throws {
        TestUtils.printTestSeparator("测试TLS握手性能")

        var durations: [TimeInterval] = []

        for _ in 0..<5 {
            let (_, duration) = await TestUtils.measureTime {
                let conn = try await TestUtils.createTLSConnection()
                await conn.disconnect(reason: .clientInitiated)
            }
            durations.append(duration)
        }

        let avgDuration = durations.reduce(0, +) / Double(durations.count)
        let maxDuration = durations.max() ?? 0

        print("  平均握手时间: \(String(format: "%.3f", avgDuration))s")
        print("  最大握手时间: \(String(format: "%.3f", maxDuration))s")

        XCTAssertLessThan(avgDuration, 1.0, "平均TLS握手应该小于1秒")
        XCTAssertLessThan(maxDuration, 2.0, "最大TLS握手应该小于2秒")

        TestUtils.printTestResult(
            "TLS握手性能(平均\(String(format: "%.3f", avgDuration))s)",
            passed: true
        )
    }

    /// 测试TLS vs 非TLS性能对比
    func testTLSVsPlainPerformance() async throws {
        TestUtils.printTestSeparator("测试TLS vs 非TLS性能")

        let tlsConn = try await TestUtils.createTLSConnection()
        let plainConn = try await TestUtils.createTestConnection()

        defer {
            Task {
                await tlsConn.disconnect(reason: .clientInitiated)
                await plainConn.disconnect(reason: .clientInitiated)
            }
        }

        let testMessage = TestFixtures.BinaryProtocolMessage(
            qid: 1,
            fid: 1,
            body: "Performance Test".data(using: .utf8)!
        ).encode()

        // TLS性能
        let (qpsTLS, latencyTLS) = try await TestUtils.measureThroughput(iterations: 30) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: tlsConn,
                message: testMessage,
                timeout: 3.0
            )
        }

        // 非TLS性能
        let (qpsPlain, latencyPlain) = try await TestUtils.measureThroughput(iterations: 30) {
            _ = try await TestUtils.sendAndReceiveMessage(
                connection: plainConn,
                message: testMessage,
                timeout: 3.0
            )
        }

        print("  TLS QPS: \(String(format: "%.0f", qpsTLS))")
        print("  非TLS QPS: \(String(format: "%.0f", qpsPlain))")

        let overhead = (qpsPlain - qpsTLS) / qpsPlain * 100
        print("  TLS性能开销: \(String(format: "%.1f", overhead))%")

        // TLS开销应该小于50%
        XCTAssertLessThan(overhead, 50.0, "TLS性能开销应该小于50%")

        TestUtils.printTestResult(
            "TLS vs 非TLS(开销\(String(format: "%.1f", overhead))%)",
            passed: true
        )
    }

    // MARK: - TLS稳定性测试

    /// 测试TLS长连接稳定性
    func testTLSLongLivedConnection() async throws {
        TestUtils.printTestSeparator("测试TLS长连接稳定性")

        let connection = try await NexusKit.shared
            .tcp(host: TestFixtures.tlsHost, port: TestFixtures.tlsPort)
            .tls(TLSTestHelper.createInsecureConfiguration())
            .heartbeat(interval: 2.0, timeout: 5.0)
            .connect()

        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        let duration: TimeInterval = 30.0
        let iterations = 15

        var successCount = 0

        for i in 1...iterations {
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
        XCTAssertGreaterThan(successRate, 90.0, "TLS长连接成功率应该大于90%")

        TestUtils.printTestResult(
            "TLS长连接稳定性(\(String(format: "%.1f", successRate))%)",
            passed: true
        )
    }

    // MARK: - TLS并发测试

    /// 测试TLS并发连接
    func testTLSConcurrentConnections() async throws {
        TestUtils.printTestSeparator("测试TLS并发连接")

        let connectionCount = 10

        let (_, duration) = await TestUtils.measureTime {
            try await TestUtils.runConcurrently(count: connectionCount) {
                let conn = try await TestUtils.createTLSConnection()
                await conn.disconnect(reason: .clientInitiated)
            }
        }

        XCTAssertLessThan(duration, 15.0, "10个TLS并发连接应该在15秒内完成")

        TestUtils.printTestResult(
            "TLS并发连接(\(connectionCount)个, \(String(format: "%.3f", duration))s)",
            passed: true
        )
    }
}
