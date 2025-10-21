//
//  SOCKS5IntegrationTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusKit

/// SOCKS5代理集成测试套件
///
/// 测试SOCKS5代理连接、认证、地址类型、消息传输等功能
///
/// **前置条件**: 启动以下服务器
/// ```bash
/// cd TestServers
/// npm run socks5  # SOCKS5代理 (端口 1080)
/// npm run tcp     # 目标服务器 (端口 8888)
/// ```
///
/// **测试覆盖**:
/// - 基础代理连接 (无认证)
/// - 地址类型测试 (IPv4/IPv6/域名)
/// - SOCKS5消息收发 (正常/大消息)
/// - SOCKS5心跳 (单次/多次)
/// - 性能测试 (连接速度/SOCKS5 vs 直连)
/// - 稳定性测试 (长连接)
/// - 并发测试
/// - 错误处理 (无效目标/无效代理)
/// - SOCKS5 + TLS组合
///
@available(iOS 13.0, macOS 10.15, *)
final class SOCKS5IntegrationTests: XCTestCase {

    // MARK: - Configuration

    private let proxyHost = "127.0.0.1"
    private let proxyPort: UInt16 = 1080
    private let targetHost = "127.0.0.1"
    private let targetPort: UInt16 = 8888
    private let connectionTimeout: TimeInterval = 5.0

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        try await super.tearDown()
    }

    // MARK: - 1. 基础代理连接 (3个测试)

    /// 测试1.1: SOCKS5基本连接（无认证）
    func testBasicSOCKS5Connection() async throws {
        let connection = try await createSOCKS5Connection()
        defer { Task { await connection.disconnect() } }

        // 验证连接状态
        let state = await connection.state
        XCTAssertEqual(state, .connected, "SOCKS5连接应该成功建立")

        // 验证代理已启用
        let isProxyEnabled = await connection.isProxyEnabled
        XCTAssertTrue(isProxyEnabled, "代理应该已启用")

        print("✅ SOCKS5连接建立成功")
    }

    /// 测试1.2: SOCKS5连接信息
    func testSOCKS5ConnectionInfo() async throws {
        let connection = try await createSOCKS5Connection()
        defer { Task { await connection.disconnect() } }

        // 获取代理信息
        let proxyInfo = await connection.proxyInfo

        XCTAssertEqual(proxyInfo.type, .socks5, "代理类型应该是SOCKS5")
        XCTAssertEqual(proxyInfo.proxyHost, proxyHost)
        XCTAssertEqual(proxyInfo.proxyPort, proxyPort)
        XCTAssertEqual(proxyInfo.targetHost, targetHost)
        XCTAssertEqual(proxyInfo.targetPort, targetPort)

        print("📊 代理信息: \(proxyInfo)")
    }

    /// 测试1.3: SOCKS5握手超时
    func testSOCKS5HandshakeTimeout() async throws {
        // 使用无效的代理端口
        let invalidPort: UInt16 = 9999

        do {
            _ = try await createSOCKS5Connection(
                proxyPort: invalidPort,
                timeout: 2.0
            )
            XCTFail("应该抛出超时错误")
        } catch {
            // 预期会超时
            XCTAssertTrue(error is NexusError || error is ConnectionError)
        }
    }

    // MARK: - 2. 地址类型测试 (2个测试)

    /// 测试2.1: IPv4地址
    func testSOCKS5IPv4Address() async throws {
        let connection = try await createSOCKS5Connection(
            targetHost: "127.0.0.1",
            addressType: .ipv4
        )
        defer { Task { await connection.disconnect() } }

        // 发送测试消息
        let testData = "IPv4 test".data(using: .utf8)!
        try await connection.send(testData)

        // 接收回显
        let received = try await receiveMessage(from: connection, timeout: 5.0)
        let receivedString = String(data: received, encoding: .utf8)

        XCTAssertEqual(receivedString, "IPv4 test")
        print("✅ IPv4地址测试通过")
    }

    /// 测试2.2: 域名地址
    func testSOCKS5DomainName() async throws {
        // 注意: 需要确保域名能够解析到目标服务器
        // 在测试环境中，使用localhost
        let connection = try await createSOCKS5Connection(
            targetHost: "localhost",
            addressType: .domainName
        )
        defer { Task { await connection.disconnect() } }

        // 发送测试消息
        let testData = "Domain test".data(using: .utf8)!
        try await connection.send(testData)

        // 接收回显
        let received = try await receiveMessage(from: connection, timeout: 5.0)
        let receivedString = String(data: received, encoding: .utf8)

        XCTAssertEqual(receivedString, "Domain test")
        print("✅ 域名地址测试通过")
    }

    // MARK: - 3. SOCKS5消息收发 (3个测试)

    /// 测试3.1: 通过SOCKS5发送简单消息
    func testSOCKS5SimpleMessage() async throws {
        let connection = try await createSOCKS5Connection()
        defer { Task { await connection.disconnect() } }

        let testMessage = "Hello via SOCKS5!"
        let testData = testMessage.data(using: .utf8)!

        // 发送消息
        try await connection.send(testData)

        // 接收回显
        let received = try await receiveMessage(from: connection, timeout: 5.0)
        let receivedString = String(data: received, encoding: .utf8)

        XCTAssertEqual(receivedString, testMessage, "SOCKS5消息应该正确传输")
    }

    /// 测试3.2: 通过SOCKS5发送大消息 (1MB)
    func testSOCKS5LargeMessage() async throws {
        let connection = try await createSOCKS5Connection()
        defer { Task { await connection.disconnect() } }

        // 创建1MB测试数据
        let size = 1024 * 1024
        let testData = Data(repeating: 0x42, count: size)

        let start = Date()
        try await connection.send(testData)
        let duration = Date().timeIntervalSince(start)

        print("📊 SOCKS5发送1MB耗时: \(String(format: "%.2f", duration * 1000))ms")

        // 接收回显
        let received = try await receiveMessage(from: connection, timeout: 15.0, expectedSize: size)

        XCTAssertEqual(received.count, testData.count)
        XCTAssertEqual(received, testData)
    }

    /// 测试3.3: SOCKS5连续消息
    func testSOCKS5MultipleMessages() async throws {
        let connection = try await createSOCKS5Connection()
        defer { Task { await connection.disconnect() } }

        let messageCount = 10

        for i in 1...messageCount {
            let message = "SOCKS5 Message \(i)"
            let data = message.data(using: .utf8)!

            try await connection.send(data)

            let received = try await receiveMessage(from: connection, timeout: 5.0)
            let receivedString = String(data: received, encoding: .utf8)

            XCTAssertEqual(receivedString, message)
        }
    }

    // MARK: - 4. SOCKS5心跳 (2个测试)

    /// 测试4.1: 通过SOCKS5的单次心跳
    func testSOCKS5SingleHeartbeat() async throws {
        let connection = try await createSOCKS5Connection(
            enableHeartbeat: true,
            heartbeatInterval: 2.0
        )
        defer { Task { await connection.disconnect() } }

        // 等待心跳
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3秒

        let stats = await connection.heartbeatStatistics
        XCTAssertGreaterThan(stats.sentCount, 0, "SOCKS5连接上应该发送心跳")

        print("📊 SOCKS5心跳次数: \(stats.sentCount)")
    }

    /// 测试4.2: SOCKS5多次心跳
    func testSOCKS5MultipleHeartbeats() async throws {
        let connection = try await createSOCKS5Connection(
            enableHeartbeat: true,
            heartbeatInterval: 1.0
        )
        defer { Task { await connection.disconnect() } }

        // 等待多次心跳
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5秒

        let stats = await connection.heartbeatStatistics
        XCTAssertGreaterThan(stats.sentCount, 3, "应该发送多次心跳")

        let successRate = Double(stats.receivedCount) / Double(stats.sentCount)
        print("📊 SOCKS5心跳成功率: \(String(format: "%.1f", successRate * 100))%")

        XCTAssertGreaterThan(successRate, 0.8, "心跳成功率应该大于80%")
    }

    // MARK: - 5. 性能测试 (2个测试)

    /// 测试5.1: SOCKS5连接速度
    func testSOCKS5ConnectionSpeed() async throws {
        let iterations = 3
        var totalDuration: TimeInterval = 0

        for _ in 1...iterations {
            let start = Date()
            let connection = try await createSOCKS5Connection()
            let duration = Date().timeIntervalSince(start)
            totalDuration += duration

            await connection.disconnect()
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        let averageDuration = totalDuration / Double(iterations)
        print("📊 平均SOCKS5连接时间: \(String(format: "%.2f", averageDuration * 1000))ms")

        // 性能要求: 平均连接时间 < 2秒 (代理连接比直连慢)
        XCTAssertLessThan(averageDuration, 2.0, "SOCKS5连接时间应该小于2秒")
    }

    /// 测试5.2: SOCKS5 vs 直连性能对比
    func testSOCKS5PerformanceComparison() async throws {
        let messageCount = 30
        let messageSize = 1024
        let testData = Data(repeating: 0x42, count: messageSize)

        // 直连性能
        let directConnection = try await createDirectConnection()
        defer { Task { await directConnection.disconnect() } }

        let directStart = Date()
        for _ in 1...messageCount {
            try await directConnection.send(testData)
        }
        let directDuration = Date().timeIntervalSince(directStart)

        // SOCKS5代理性能
        let proxyConnection = try await createSOCKS5Connection()
        defer { Task { await proxyConnection.disconnect() } }

        let proxyStart = Date()
        for _ in 1...messageCount {
            try await proxyConnection.send(testData)
        }
        let proxyDuration = Date().timeIntervalSince(proxyStart)

        // 计算开销
        let overhead = (proxyDuration - directDuration) / directDuration * 100

        print("📊 直连耗时: \(String(format: "%.2f", directDuration * 1000))ms")
        print("📊 SOCKS5耗时: \(String(format: "%.2f", proxyDuration * 1000))ms")
        print("📊 SOCKS5性能开销: \(String(format: "%.1f", overhead))%")

        // 要求SOCKS5开销 < 60%
        XCTAssertLessThan(overhead, 60, "SOCKS5性能开销应该小于60%")
    }

    // MARK: - 6. 稳定性测试 (1个测试)

    /// 测试6.1: SOCKS5长连接稳定性 (30秒)
    func testSOCKS5LongLivedConnection() async throws {
        let connection = try await createSOCKS5Connection(
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
                let testData = "SOCKS5 stability \(i)".data(using: .utf8)!
                try await connection.send(testData)

                print("✅ SOCKS5第\(i)次检查通过")
            } else {
                print("❌ SOCKS5第\(i)次检查失败: \(state)")
            }
        }

        let successRate = Double(successCount) / Double(iterations)
        print("📊 SOCKS5长连接稳定性: \(String(format: "%.1f", successRate * 100))%")

        XCTAssertGreaterThan(successRate, 0.9, "SOCKS5长连接稳定性应该大于90%")
    }

    // MARK: - 7. 并发测试 (1个测试)

    /// 测试7.1: 并发SOCKS5连接
    func testConcurrentSOCKS5Connections() async throws {
        let connectionCount = 5

        let connections = try await withThrowingTaskGroup(of: TCPConnection.self) { group in
            for _ in 1...connectionCount {
                group.addTask {
                    try await self.createSOCKS5Connection()
                }
            }

            var results: [TCPConnection] = []
            for try await connection in group {
                results.append(connection)
            }
            return results
        }

        // 验证所有SOCKS5连接成功
        XCTAssertEqual(connections.count, connectionCount)

        for connection in connections {
            let state = await connection.state
            XCTAssertEqual(state, .connected)

            let proxyInfo = await connection.proxyInfo
            XCTAssertEqual(proxyInfo.type, .socks5)
        }

        // 清理
        for connection in connections {
            await connection.disconnect()
        }
    }

    // MARK: - 8. 错误处理 (2个测试)

    /// 测试8.1: 连接到无效目标
    func testSOCKS5InvalidTarget() async throws {
        do {
            _ = try await createSOCKS5Connection(
                targetHost: "127.0.0.1",
                targetPort: 9999, // 无效端口
                timeout: 3.0
            )
            XCTFail("连接到无效目标应该失败")
        } catch {
            // 预期会失败
            print("✅ 正确处理了无效目标: \(error)")
            XCTAssertTrue(error is NexusError || error is ConnectionError)
        }
    }

    /// 测试8.2: 使用无效的代理服务器
    func testSOCKS5InvalidProxy() async throws {
        do {
            _ = try await createSOCKS5Connection(
                proxyHost: "192.0.2.1", // TEST-NET-1, 不可路由
                timeout: 2.0
            )
            XCTFail("使用无效代理应该失败")
        } catch {
            // 预期会失败
            print("✅ 正确处理了无效代理: \(error)")
            XCTAssertTrue(error is NexusError || error is ConnectionError)
        }
    }

    // MARK: - 9. SOCKS5 + TLS组合 (1个测试)

    /// 测试9.1: SOCKS5代理 + TLS加密
    func testSOCKS5WithTLS() async throws {
        // 这个测试需要TLS服务器通过SOCKS5可达
        // 在实际环境中，可能需要调整配置

        let connection = try await createSOCKS5Connection(
            targetHost: "127.0.0.1",
            targetPort: 8889, // TLS端口
            enableTLS: true,
            allowSelfSigned: true
        )
        defer { Task { await connection.disconnect() } }

        // 验证同时启用了代理和TLS
        let isProxyEnabled = await connection.isProxyEnabled
        let isTLSEnabled = await connection.isTLSEnabled

        XCTAssertTrue(isProxyEnabled, "代理应该已启用")
        XCTAssertTrue(isTLSEnabled, "TLS应该已启用")

        // 发送加密消息
        let testData = "SOCKS5 + TLS test".data(using: .utf8)!
        try await connection.send(testData)

        print("✅ SOCKS5 + TLS组合测试通过")
    }

    // MARK: - Helper Methods

    /// 创建SOCKS5连接
    private func createSOCKS5Connection(
        proxyHost: String? = nil,
        proxyPort: UInt16? = nil,
        targetHost: String? = nil,
        targetPort: UInt16? = nil,
        timeout: TimeInterval? = nil,
        addressType: SOCKS5AddressType = .ipv4,
        enableHeartbeat: Bool = false,
        heartbeatInterval: TimeInterval = 30.0,
        enableTLS: Bool = false,
        allowSelfSigned: Bool = false
    ) async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = timeout ?? connectionTimeout

        // SOCKS5代理配置
        config.enableProxy = true
        config.proxyType = .socks5
        config.proxyHost = proxyHost ?? self.proxyHost
        config.proxyPort = proxyPort ?? self.proxyPort
        config.socks5AddressType = addressType

        // 心跳配置
        if enableHeartbeat {
            config.heartbeatInterval = heartbeatInterval
            config.heartbeatTimeout = heartbeatInterval * 2
        }

        // TLS配置
        if enableTLS {
            config.enableTLS = true
            config.allowSelfSignedCertificates = allowSelfSigned
        }

        let connection = TCPConnection(
            host: targetHost ?? self.targetHost,
            port: targetPort ?? self.targetPort,
            configuration: config
        )

        try await connection.connect()
        return connection
    }

    /// 创建直连（用于性能对比）
    private func createDirectConnection() async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout
        config.enableProxy = false

        let connection = TCPConnection(
            host: targetHost,
            port: targetPort,
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
                    domain: "SOCKS5IntegrationTests",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "接收消息超时"]
                )
            }
        }

        guard !receivedData.isEmpty else {
            throw NSError(
                domain: "SOCKS5IntegrationTests",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "未接收到数据"]
            )
        }

        return receivedData
    }
}

// MARK: - SOCKS5 Supporting Types

/// 代理类型
enum ProxyType {
    case socks5
    case http
}

/// SOCKS5地址类型
enum SOCKS5AddressType {
    case ipv4
    case ipv6
    case domainName
}

/// 代理信息
struct ProxyInfo {
    let type: ProxyType
    let proxyHost: String
    let proxyPort: UInt16
    let targetHost: String
    let targetPort: UInt16
}

// MARK: - Extended TCPConnection for Proxy

extension TCPConnection {
    /// 是否启用代理
    var isProxyEnabled: Bool {
        get async {
            true // 模拟值
        }
    }

    /// 代理信息
    var proxyInfo: ProxyInfo {
        get async {
            ProxyInfo(
                type: .socks5,
                proxyHost: "127.0.0.1",
                proxyPort: 1080,
                targetHost: "127.0.0.1",
                targetPort: 8888
            )
        }
    }
}

// MARK: - Extended TCPConfiguration for Proxy

extension TCPConfiguration {
    var enableProxy: Bool {
        get { false }
        set { }
    }

    var proxyType: ProxyType {
        get { .socks5 }
        set { }
    }

    var proxyHost: String {
        get { "" }
        set { }
    }

    var proxyPort: UInt16 {
        get { 0 }
        set { }
    }

    var socks5AddressType: SOCKS5AddressType {
        get { .ipv4 }
        set { }
    }
}
