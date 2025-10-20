//
//  TestUtils.swift
//  NexusKit Tests
//
//  Created by NexusKit Contributors
//
//  通用测试工具函数

import Foundation
import XCTest
import NexusCore
import NexusTCP

/// 测试工具类
public enum TestUtils {

    // MARK: - 服务器检查

    /// 检查TCP测试服务器是否运行
    public static func isTCPServerRunning() async -> Bool {
        do {
            let socket = try await NexusKit.shared
                .tcp(host: TestFixtures.tcpHost, port: TestFixtures.tcpPort)
                .timeout(2.0)
                .connect()

            await socket.disconnect(reason: .clientInitiated)
            return true
        } catch {
            return false
        }
    }

    /// 检查SOCKS5代理服务器是否运行
    public static func isSOCKS5ServerRunning() async -> Bool {
        // 简单的端口连接测试
        do {
            let socket = try await NexusKit.shared
                .tcp(host: TestFixtures.socks5Host, port: TestFixtures.socks5Port)
                .timeout(2.0)
                .connect()

            await socket.disconnect(reason: .clientInitiated)
            return true
        } catch {
            return false
        }
    }

    /// 等待所有测试服务器启动
    public static func waitForTestServers(timeout: TimeInterval = 10.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let tcpRunning = await isTCPServerRunning()
            let tlsRunning = await TLSTestHelper.isTLSServerRunning()
            let socks5Running = await isSOCKS5ServerRunning()

            if tcpRunning && tlsRunning && socks5Running {
                print("[TestUtils] 所有测试服务器已就绪")
                return
            }

            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }

        throw TestError.serverNotRunning
    }

    // MARK: - 测试辅助

    /// 创建测试用TCP连接
    public static func createTestConnection(
        host: String = TestFixtures.tcpHost,
        port: UInt16 = TestFixtures.tcpPort,
        timeout: TimeInterval = TestFixtures.shortTimeout
    ) async throws -> TCPConnection {
        try await NexusKit.shared
            .tcp(host: host, port: port)
            .timeout(timeout)
            .connect()
    }

    /// 创建测试用TLS连接
    public static func createTLSConnection(
        host: String = TestFixtures.tlsHost,
        port: UInt16 = TestFixtures.tlsPort,
        tlsConfig: TLSConfiguration? = nil,
        timeout: TimeInterval = TestFixtures.shortTimeout
    ) async throws -> TCPConnection {
        let config = tlsConfig ?? TLSTestHelper.createInsecureConfiguration()

        return try await NexusKit.shared
            .tcp(host: host, port: port)
            .tls(config)
            .timeout(timeout)
            .connect()
    }

    /// 创建通过SOCKS5代理的连接
    public static func createProxiedConnection(
        targetHost: String = TestFixtures.tcpHost,
        targetPort: UInt16 = TestFixtures.tcpPort,
        proxyHost: String = TestFixtures.socks5Host,
        proxyPort: UInt16 = TestFixtures.socks5Port,
        timeout: TimeInterval = TestFixtures.mediumTimeout
    ) async throws -> TCPConnection {
        let proxyConfig = ProxyConfiguration.socks5(
            host: proxyHost,
            port: proxyPort,
            username: nil,
            password: nil
        )

        return try await NexusKit.shared
            .tcp(host: targetHost, port: targetPort)
            .proxy(proxyConfig)
            .timeout(timeout)
            .connect()
    }

    // MARK: - 消息发送和验证

    /// 发送消息并等待响应
    public static func sendAndReceiveMessage(
        connection: TCPConnection,
        message: Data,
        timeout: TimeInterval = TestFixtures.shortTimeout
    ) async throws -> Data {
        var receivedData: Data?

        connection.on(.message) { data in
            receivedData = data
        }

        try await connection.send(message, timeout: timeout)

        // 等待响应
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && receivedData == nil {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        guard let data = receivedData else {
            throw TestError.timeout
        }

        return data
    }

    /// 发送心跳并验证响应
    public static func sendHeartbeat(
        connection: TCPConnection,
        timeout: TimeInterval = TestFixtures.shortTimeout
    ) async throws -> Bool {
        do {
            let response = try await sendAndReceiveMessage(
                connection: connection,
                message: TestFixtures.heartbeatMessage,
                timeout: timeout
            )

            // 验证是否是心跳响应
            if let message = TestFixtures.BinaryProtocolMessage.decode(response) {
                return message.fid == 0xFFFF
            }

            return false
        } catch {
            return false
        }
    }

    // MARK: - 性能测量

    /// 测量操作执行时间
    public static func measureTime<T>(
        _ operation: () async throws -> T
    ) async rethrows -> (result: T, duration: TimeInterval) {
        let startTime = Date()
        let result = try await operation()
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        return (result, duration)
    }

    /// 测量吞吐量
    public static func measureThroughput(
        iterations: Int,
        operation: () async throws -> Void
    ) async throws -> (qps: Double, avgLatency: TimeInterval) {
        let startTime = Date()

        for _ in 0..<iterations {
            try await operation()
        }

        let endTime = Date()
        let totalDuration = endTime.timeIntervalSince(startTime)
        let qps = Double(iterations) / totalDuration
        let avgLatency = totalDuration / Double(iterations)

        return (qps, avgLatency)
    }

    // MARK: - 并发测试

    /// 并发执行多个操作
    public static func runConcurrently<T>(
        count: Int,
        operation: @escaping () async throws -> T
    ) async throws -> [T] {
        try await withThrowingTaskGroup(of: T.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try await operation()
                }
            }

            var results: [T] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }

    // MARK: - 内存测试

    /// 测量内存使用
    public static func measureMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if kerr == KERN_SUCCESS {
            return info.resident_size
        }

        return 0
    }

    /// 测量操作的内存影响
    public static func measureMemoryImpact<T>(
        _ operation: () async throws -> T
    ) async rethrows -> (result: T, memoryDelta: Int64) {
        let beforeMemory = Int64(measureMemoryUsage())
        let result = try await operation()
        let afterMemory = Int64(measureMemoryUsage())
        let delta = afterMemory - beforeMemory

        return (result, delta)
    }

    // MARK: - 日志辅助

    /// 打印测试分隔线
    public static func printTestSeparator(_ title: String) {
        print("\n" + String(repeating: "=", count: 60))
        print("  \(title)")
        print(String(repeating: "=", count: 60) + "\n")
    }

    /// 打印测试结果
    public static func printTestResult(
        _ name: String,
        passed: Bool,
        duration: TimeInterval? = nil
    ) {
        let status = passed ? "✅ PASS" : "❌ FAIL"
        let durationStr = duration.map { String(format: " (%.3fs)", $0) } ?? ""
        print("[\(status)] \(name)\(durationStr)")
    }
}

// MARK: - XCTest Extensions

extension XCTestCase {

    /// 异步断言
    public func XCTAsyncAssertTrue(
        _ condition: @autoclosure () async throws -> Bool,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let result = try await condition()
        XCTAssertTrue(result, message, file: file, line: line)
    }

    /// 异步断言相等
    public func XCTAsyncAssertEqual<T: Equatable>(
        _ expression1: @autoclosure () async throws -> T,
        _ expression2: @autoclosure () async throws -> T,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let value1 = try await expression1()
        let value2 = try await expression2()
        XCTAssertEqual(value1, value2, message, file: file, line: line)
    }

    /// 异步断言不抛出异常
    public func XCTAsyncAssertNoThrow<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail("\(message) - Unexpected error: \(error)", file: file, line: line)
        }
    }

    /// 异步断言抛出异常
    public func XCTAsyncAssertThrowsError<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("\(message) - Expected error but succeeded", file: file, line: line)
        } catch {
            // Expected
        }
    }
}
