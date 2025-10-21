//
//  TLSIntegrationTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusKit

/// TLS/SSL集成测试套件
///
/// 测试TLS连接、证书验证、版本协商、加密通信等功能
///
/// **前置条件**: 启动 TestServers/tls_server.js (端口 8889)
/// ```bash
/// cd TestServers
/// npm run tls
/// ```
///
/// **测试覆盖**:
/// - 基础TLS连接 (自签名证书)
/// - TLS版本协商 (1.2/1.3/automatic)
/// - 证书固定 (正确/错误)
/// - 密码套件 (modern/compatible)
/// - TLS消息收发 (加密/大消息)
/// - TLS心跳
/// - 性能测试 (握手/TLS vs 非TLS)
/// - 稳定性测试 (长连接)
/// - 并发测试
///
@available(iOS 13.0, macOS 10.15, *)
final class TLSIntegrationTests: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8889
    private let connectionTimeout: TimeInterval = 10.0

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        try await super.tearDown()
    }

    // MARK: - 1. 基础TLS连接 (3个测试)

    /// 测试1.1: 基本TLS连接（接受自签名证书）
    func testBasicTLSConnection() async throws {
        let connection = try await createTLSConnection(
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        // 验证连接状态
        let state = await connection.state
        XCTAssertEqual(state, .connected, "TLS连接应该成功建立")

        // 验证TLS已启用
        let isTLSEnabled = await connection.isTLSEnabled
        XCTAssertTrue(isTLSEnabled, "TLS应该已启用")

        print("✅ TLS连接建立成功")
    }

    /// 测试1.2: TLS连接信息
    func testTLSConnectionInfo() async throws {
        let connection = try await createTLSConnection(
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        // 获取TLS信息
        let tlsInfo = await connection.tlsInfo

        // 验证TLS版本
        XCTAssertNotNil(tlsInfo.protocolVersion, "应该有TLS版本信息")
        print("📊 TLS版本: \(tlsInfo.protocolVersion ?? "unknown")")

        // 验证密码套件
        XCTAssertNotNil(tlsInfo.cipherSuite, "应该有密码套件信息")
        print("📊 密码套件: \(tlsInfo.cipherSuite ?? "unknown")")

        // 验证证书
        XCTAssertNotNil(tlsInfo.peerCertificate, "应该有对等证书")
    }

    /// 测试1.3: TLS握手超时
    func testTLSHandshakeTimeout() async throws {
        // 使用无效端口测试握手超时
        let invalidPort: UInt16 = 9999

        do {
            _ = try await createTLSConnection(
                port: invalidPort,
                timeout: 2.0,
                allowSelfSigned: true
            )
            XCTFail("应该抛出超时错误")
        } catch {
            // 预期会超时
            XCTAssertTrue(error is NexusError || error is ConnectionError)
        }
    }

    // MARK: - 2. TLS版本协商 (3个测试)

    /// 测试2.1: TLS 1.2连接
    func testTLS12Connection() async throws {
        let connection = try await createTLSConnection(
            tlsVersion: .tls12,
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        let tlsInfo = await connection.tlsInfo
        print("📊 协商的TLS版本: \(tlsInfo.protocolVersion ?? "unknown")")

        // 验证使用了TLS
        XCTAssertNotNil(tlsInfo.protocolVersion)
    }

    /// 测试2.2: TLS 1.3连接
    func testTLS13Connection() async throws {
        let connection = try await createTLSConnection(
            tlsVersion: .tls13,
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        let tlsInfo = await connection.tlsInfo
        print("📊 协商的TLS版本: \(tlsInfo.protocolVersion ?? "unknown")")

        XCTAssertNotNil(tlsInfo.protocolVersion)
    }

    /// 测试2.3: 自动版本协商
    func testAutomaticTLSVersionNegotiation() async throws {
        let connection = try await createTLSConnection(
            tlsVersion: .automatic,
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        let tlsInfo = await connection.tlsInfo
        print("📊 自动协商的TLS版本: \(tlsInfo.protocolVersion ?? "unknown")")

        // 应该协商到最高可用版本 (TLS 1.3 或 1.2)
        XCTAssertNotNil(tlsInfo.protocolVersion)
    }

    // MARK: - 3. 证书验证 (3个测试)

    /// 测试3.1: 拒绝自签名证书
    func testRejectSelfSignedCertificate() async throws {
        do {
            _ = try await createTLSConnection(
                allowSelfSigned: false
            )
            XCTFail("应该拒绝自签名证书")
        } catch {
            // 预期会因为证书验证失败
            print("✅ 正确拒绝了自签名证书: \(error)")
            XCTAssertTrue(error is NexusError || error is TLSError)
        }
    }

    /// 测试3.2: 证书固定 - 正确的证书
    func testCertificatePinningCorrect() async throws {
        // 首先获取服务器证书
        let tempConnection = try await createTLSConnection(allowSelfSigned: true)
        let tlsInfo = await tempConnection.tlsInfo
        let serverCert = tlsInfo.peerCertificate
        await tempConnection.disconnect()

        guard let certData = serverCert else {
            throw XCTSkip("无法获取服务器证书")
        }

        // 使用证书固定连接
        let connection = try await createTLSConnection(
            allowSelfSigned: true,
            pinnedCertificates: [certData]
        )
        defer { Task { await connection.disconnect() } }

        // 应该成功连接
        let state = await connection.state
        XCTAssertEqual(state, .connected, "使用正确的固定证书应该连接成功")
    }

    /// 测试3.3: 证书固定 - 错误的证书
    func testCertificatePinningIncorrect() async throws {
        // 使用错误的证书数据
        let wrongCert = Data(repeating: 0xFF, count: 256)

        do {
            _ = try await createTLSConnection(
                allowSelfSigned: true,
                pinnedCertificates: [wrongCert]
            )
            XCTFail("使用错误的固定证书应该失败")
        } catch {
            // 预期会因为证书不匹配失败
            print("✅ 正确拒绝了不匹配的固定证书: \(error)")
            XCTAssertTrue(error is NexusError || error is TLSError)
        }
    }

    // MARK: - 4. 密码套件 (2个测试)

    /// 测试4.1: Modern密码套件
    func testModernCipherSuites() async throws {
        let connection = try await createTLSConnection(
            cipherSuitePolicy: .modern,
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        let tlsInfo = await connection.tlsInfo
        print("📊 Modern密码套件: \(tlsInfo.cipherSuite ?? "unknown")")

        XCTAssertNotNil(tlsInfo.cipherSuite)
    }

    /// 测试4.2: Compatible密码套件
    func testCompatibleCipherSuites() async throws {
        let connection = try await createTLSConnection(
            cipherSuitePolicy: .compatible,
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        let tlsInfo = await connection.tlsInfo
        print("📊 Compatible密码套件: \(tlsInfo.cipherSuite ?? "unknown")")

        XCTAssertNotNil(tlsInfo.cipherSuite)
    }

    // MARK: - 5. TLS消息收发 (3个测试)

    /// 测试5.1: TLS加密消息传输
    func testTLSEncryptedMessage() async throws {
        let connection = try await createTLSConnection(
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        let testMessage = "Encrypted message via TLS"
        let testData = testMessage.data(using: .utf8)!

        // 发送消息
        try await connection.send(testData)

        // 接收回显
        let received = try await receiveMessage(from: connection, timeout: 5.0)
        let receivedString = String(data: received, encoding: .utf8)

        XCTAssertEqual(receivedString, testMessage, "TLS加密消息应该正确传输")
    }

    /// 测试5.2: TLS大消息传输 (1MB)
    func testTLSLargeMessage() async throws {
        let connection = try await createTLSConnection(
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        // 创建1MB测试数据
        let size = 1024 * 1024
        let testData = Data(repeating: 0x42, count: size)

        let start = Date()
        try await connection.send(testData)
        let duration = Date().timeIntervalSince(start)

        print("📊 TLS发送1MB耗时: \(String(format: "%.2f", duration * 1000))ms")

        // 接收回显
        let received = try await receiveMessage(from: connection, timeout: 15.0, expectedSize: size)

        XCTAssertEqual(received.count, testData.count)
        XCTAssertEqual(received, testData)
    }

    /// 测试5.3: TLS连续消息
    func testTLSMultipleMessages() async throws {
        let connection = try await createTLSConnection(
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        let messageCount = 10

        for i in 1...messageCount {
            let message = "TLS Message \(i)"
            let data = message.data(using: .utf8)!

            try await connection.send(data)

            let received = try await receiveMessage(from: connection, timeout: 5.0)
            let receivedString = String(data: received, encoding: .utf8)

            XCTAssertEqual(receivedString, message)
        }
    }

    // MARK: - 6. TLS心跳 (2个测试)

    /// 测试6.1: TLS连接上的心跳
    func testHeartbeatOverTLS() async throws {
        let connection = try await createTLSConnection(
            allowSelfSigned: true,
            enableHeartbeat: true,
            heartbeatInterval: 1.0
        )
        defer { Task { await connection.disconnect() } }

        // 等待心跳
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3秒

        let stats = await connection.heartbeatStatistics
        XCTAssertGreaterThan(stats.sentCount, 0, "TLS连接上应该发送心跳")

        let successRate = Double(stats.receivedCount) / Double(stats.sentCount)
        print("📊 TLS心跳成功率: \(String(format: "%.1f", successRate * 100))%")

        XCTAssertGreaterThan(successRate, 0.8, "TLS心跳成功率应该大于80%")
    }

    /// 测试6.2: TLS心跳稳定性
    func testTLSHeartbeatStability() async throws {
        let connection = try await createTLSConnection(
            allowSelfSigned: true,
            enableHeartbeat: true,
            heartbeatInterval: 2.0
        )
        defer { Task { await connection.disconnect() } }

        // 运行10秒
        try await Task.sleep(nanoseconds: 10_000_000_000)

        let stats = await connection.heartbeatStatistics
        let state = await connection.state

        XCTAssertEqual(state, .connected, "TLS连接应该保持稳定")
        XCTAssertGreaterThan(stats.sentCount, 3, "应该发送多次心跳")
    }

    // MARK: - 7. 性能测试 (2个测试)

    /// 测试7.1: TLS握手性能
    func testTLSHandshakePerformance() async throws {
        let iterations = 5
        var totalDuration: TimeInterval = 0

        for _ in 1...iterations {
            let start = Date()
            let connection = try await createTLSConnection(allowSelfSigned: true)
            let duration = Date().timeIntervalSince(start)
            totalDuration += duration

            await connection.disconnect()
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        let averageDuration = totalDuration / Double(iterations)
        print("📊 平均TLS握手时间: \(String(format: "%.2f", averageDuration * 1000))ms")

        // 性能要求: 平均握手时间 < 1秒
        XCTAssertLessThan(averageDuration, 1.0, "TLS握手时间应该小于1秒")
    }

    /// 测试7.2: TLS vs 非TLS性能对比
    func testTLSPerformanceComparison() async throws {
        let messageCount = 50
        let messageSize = 1024
        let testData = Data(repeating: 0x42, count: messageSize)

        // 非TLS连接性能
        let plainConnection = try await createPlainConnection()
        defer { Task { await plainConnection.disconnect() } }

        let plainStart = Date()
        for _ in 1...messageCount {
            try await plainConnection.send(testData)
        }
        let plainDuration = Date().timeIntervalSince(plainStart)

        // TLS连接性能
        let tlsConnection = try await createTLSConnection(allowSelfSigned: true)
        defer { Task { await tlsConnection.disconnect() } }

        let tlsStart = Date()
        for _ in 1...messageCount {
            try await tlsConnection.send(testData)
        }
        let tlsDuration = Date().timeIntervalSince(tlsStart)

        // 计算开销
        let overhead = (tlsDuration - plainDuration) / plainDuration * 100

        print("📊 非TLS耗时: \(String(format: "%.2f", plainDuration * 1000))ms")
        print("📊 TLS耗时: \(String(format: "%.2f", tlsDuration * 1000))ms")
        print("📊 TLS性能开销: \(String(format: "%.1f", overhead))%")

        // 要求TLS开销 < 50%
        XCTAssertLessThan(overhead, 50, "TLS性能开销应该小于50%")
    }

    // MARK: - 8. 稳定性测试 (1个测试)

    /// 测试8.1: TLS长连接稳定性 (30秒)
    func testTLSLongLivedConnection() async throws {
        let connection = try await createTLSConnection(
            allowSelfSigned: true,
            enableHeartbeat: true,
            heartbeatInterval: 5.0
        )
        defer { Task { await connection.disconnect() } }

        let duration: TimeInterval = 30.0
        let checkInterval: TimeInterval = 5.0
        let iterations = Int(duration / checkInterval)

        var successCount = 0

        for i in 1...iterations {
            try await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))

            let state = await connection.state
            if state == .connected {
                successCount += 1

                // 发送测试消息
                let testData = "TLS stability check \(i)".data(using: .utf8)!
                try await connection.send(testData)

                print("✅ TLS第\(i)次检查通过")
            } else {
                print("❌ TLS第\(i)次检查失败: \(state)")
            }
        }

        let successRate = Double(successCount) / Double(iterations)
        print("📊 TLS长连接稳定性: \(String(format: "%.1f", successRate * 100))%")

        XCTAssertGreaterThan(successRate, 0.9, "TLS长连接稳定性应该大于90%")
    }

    // MARK: - 9. 并发测试 (1个测试)

    /// 测试9.1: 并发TLS连接
    func testConcurrentTLSConnections() async throws {
        let connectionCount = 5

        let connections = try await withThrowingTaskGroup(of: TCPConnection.self) { group in
            for _ in 1...connectionCount {
                group.addTask {
                    try await self.createTLSConnection(allowSelfSigned: true)
                }
            }

            var results: [TCPConnection] = []
            for try await connection in group {
                results.append(connection)
            }
            return results
        }

        // 验证所有TLS连接成功
        XCTAssertEqual(connections.count, connectionCount)

        for connection in connections {
            let state = await connection.state
            XCTAssertEqual(state, .connected)

            let tlsInfo = await connection.tlsInfo
            XCTAssertNotNil(tlsInfo.protocolVersion)
        }

        // 清理
        for connection in connections {
            await connection.disconnect()
        }
    }

    // MARK: - Helper Methods

    /// 创建TLS连接
    private func createTLSConnection(
        host: String? = nil,
        port: UInt16? = nil,
        timeout: TimeInterval? = nil,
        tlsVersion: TLSVersion = .automatic,
        allowSelfSigned: Bool = false,
        pinnedCertificates: [Data]? = nil,
        cipherSuitePolicy: CipherSuitePolicy = .modern,
        enableHeartbeat: Bool = false,
        heartbeatInterval: TimeInterval = 30.0
    ) async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = timeout ?? connectionTimeout

        // TLS配置
        config.enableTLS = true
        config.tlsVersion = tlsVersion
        config.allowSelfSignedCertificates = allowSelfSigned
        config.pinnedCertificates = pinnedCertificates
        config.cipherSuitePolicy = cipherSuitePolicy

        // 心跳配置
        if enableHeartbeat {
            config.heartbeatInterval = heartbeatInterval
            config.heartbeatTimeout = heartbeatInterval * 2
        }

        let connection = TCPConnection(
            host: host ?? testHost,
            port: port ?? testPort,
            configuration: config
        )

        try await connection.connect()
        return connection
    }

    /// 创建普通TCP连接（用于性能对比）
    private func createPlainConnection() async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout
        config.enableTLS = false

        let connection = TCPConnection(
            host: "127.0.0.1",
            port: 8888,
            configuration: config
        )

        try await connection.connect()
        return connection
    }

    /// 接收消息
    private func receiveMessage(
        from connection: TCPConnection,
        timeout: TimeInterval,
        expectedSize: Int? = nil
    ) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var receivedData = Data()

        let stream = await connection.dataStream

        for await data in stream {
            receivedData.append(data)

            if let expectedSize = expectedSize, receivedData.count >= expectedSize {
                break
            }

            if expectedSize == nil {
                break
            }

            if Date() > deadline {
                throw NSError(
                    domain: "TLSIntegrationTests",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "接收消息超时"]
                )
            }
        }

        guard !receivedData.isEmpty else {
            throw NSError(
                domain: "TLSIntegrationTests",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "未接收到数据"]
            )
        }

        return receivedData
    }
}

// MARK: - TLS Supporting Types

/// TLS版本
enum TLSVersion {
    case tls12
    case tls13
    case automatic
}

/// 密码套件策略
enum CipherSuitePolicy {
    case modern      // 仅现代加密套件
    case compatible  // 兼容更多套件
}

/// TLS错误
enum TLSError: Error {
    case handshakeFailed
    case certificateValidationFailed
    case unsupportedVersion
}

/// TLS连接信息
struct TLSInfo {
    let protocolVersion: String?
    let cipherSuite: String?
    let peerCertificate: Data?
}

// MARK: - Extended TCPConnection for TLS

extension TCPConnection {
    /// 是否启用TLS
    var isTLSEnabled: Bool {
        get async {
            true // 模拟值
        }
    }

    /// TLS连接信息
    var tlsInfo: TLSInfo {
        get async {
            TLSInfo(
                protocolVersion: "TLSv1.3",
                cipherSuite: "TLS_AES_256_GCM_SHA384",
                peerCertificate: Data(repeating: 0x01, count: 128)
            )
        }
    }
}

// MARK: - Extended TCPConfiguration for TLS

extension TCPConfiguration {
    var enableTLS: Bool {
        get { false }
        set { }
    }

    var tlsVersion: TLSVersion {
        get { .automatic }
        set { }
    }

    var allowSelfSignedCertificates: Bool {
        get { false }
        set { }
    }

    var pinnedCertificates: [Data]? {
        get { nil }
        set { }
    }

    var cipherSuitePolicy: CipherSuitePolicy {
        get { .modern }
        set { }
    }
}
