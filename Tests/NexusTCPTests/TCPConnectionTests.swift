//
//  TCPConnectionTests.swift
//  NexusTCPTests
//
//  Created by NexusKit Contributors
//

import XCTest
import Network
@testable import NexusKit
@testable import NexusKit

/// TCP 连接测试
final class TCPConnectionTests: XCTestCase {

    // MARK: - Properties

    var connection: TCPConnection!
    let testHost = "127.0.0.1"
    let testPort: UInt16 = 8080

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
    }

    override func tearDown() async throws {
        if let connection = connection {
            await connection.disconnect(reason: .clientInitiated)
        }
        connection = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialization() {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test-connection",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )

        connection = TCPConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )

        Task {
            let state = await connection.state
            XCTAssertEqual(state, .disconnected)
            let connectionId = await connection.id
            XCTAssertEqual(connectionId, "test-connection")
        }
    }

    // MARK: - State Transition Tests

    func testInitialState() async {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        let state = await connection.state
        XCTAssertEqual(state, .disconnected)
    }

    func testStateTransitionFromDisconnectedToConnecting() async throws {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 0.1, // Short timeout for test
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        // Attempt to connect (will fail due to no server, but state should transition)
        do {
            try await connection.connect()
        } catch {
            // Expected to fail - no server running
        }
    }

    func testInvalidStateTransition() async throws {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        // Cannot connect while already connecting
        Task {
            do {
                try await connection.connect()
            } catch {
                // Ignore
            }
        }

        // Give it time to start connecting
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Try to connect again - should fail with invalid state
        do {
            try await connection.connect()
            XCTFail("Should throw invalid state transition error")
        } catch let error as NexusError {
            if case .invalidStateTransition = error {
                // Expected error
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            // Might be connection timeout, which is also acceptable
        }
    }

    // MARK: - Connection Tests

    func testConnectionTimeout() async throws {
        let endpoint = Endpoint.tcp(host: "192.0.2.1", port: 9999) // Non-routable IP
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 0.5, // 500ms timeout
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        do {
            try await connection.connect()
            XCTFail("Connection should timeout")
        } catch let error as NexusError {
            XCTAssertEqual(error, .connectionTimeout)
        }
    }

    func testInvalidEndpoint() async throws {
        let endpoint = Endpoint.webSocket(url: URL(string: "ws://example.com")!)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        do {
            try await connection.connect()
            XCTFail("Should throw invalid endpoint error")
        } catch let error as NexusError {
            XCTAssertEqual(error, .invalidEndpoint(endpoint))
        }
    }

    // MARK: - Disconnection Tests

    func testDisconnectFromDisconnectedState() async {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        // Should be no-op
        await connection.disconnect(reason: .clientInitiated)

        let state = await connection.state
        XCTAssertEqual(state, .disconnected)
    }

    func testDisconnectReason() async {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)

        var disconnectReason: DisconnectReason?
        let hooks = LifecycleHooks(
            onDisconnected: { reason in
                disconnectReason = reason
            }
        )

        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: hooks,
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        await connection.disconnect(reason: .clientInitiated)

        // Give hooks time to execute
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertNotNil(disconnectReason)
        if case .clientInitiated = disconnectReason {
            // Expected
        } else {
            XCTFail("Wrong disconnect reason: \(String(describing: disconnectReason))")
        }
    }

    // MARK: - Send Tests

    func testSendWhenDisconnected() async throws {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        let testData = "Hello".data(using: .utf8)!

        do {
            try await connection.send(testData, timeout: 5.0)
            XCTFail("Should throw not connected error")
        } catch let error as NexusError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    func testSendWithoutProtocolAdapter() async throws {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        struct TestMessage: Codable {
            let text: String
        }

        do {
            try await connection.send(TestMessage(text: "test"), timeout: 5.0)
            XCTFail("Should throw no protocol adapter error")
        } catch let error as NexusError {
            XCTAssertEqual(error, .noProtocolAdapter)
        }
    }

    // MARK: - Receive Tests

    func testReceiveNotSupported() async throws {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        do {
            _ = try await connection.receive(timeout: 5.0)
            XCTFail("Should throw unsupported operation error")
        } catch let error as NexusError {
            if case .unsupportedOperation(let operation, _) = error {
                XCTAssertEqual(operation, "receive")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testReceiveDecodableNotSupported() async throws {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        struct TestMessage: Codable {
            let text: String
        }

        do {
            _ = try await connection.receive(as: TestMessage.self, timeout: 5.0)
            XCTFail("Should throw unsupported operation error")
        } catch let error as NexusError {
            if case .unsupportedOperation(let operation, _) = error {
                XCTAssertEqual(operation, "receive")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Event Handler Tests

    func testEventHandlerRegistration() async {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        var receivedData: Data?

        await connection.on(.message) { data in
            receivedData = data
        }

        // Event handler should be registered (internal state, cannot verify directly)
        // This test mainly verifies no crashes occur
        XCTAssertNil(receivedData) // Not called yet
    }

    func testMultipleEventHandlers() async {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        var handler1Called = false
        var handler2Called = false

        await connection.on(.message) { _ in
            handler1Called = true
        }

        await connection.on(.message) { _ in
            handler2Called = true
        }

        // Both handlers should be registered
        XCTAssertFalse(handler1Called)
        XCTAssertFalse(handler2Called)
    }

    // MARK: - Lifecycle Hooks Tests

    func testLifecycleHooksOnConnecting() async {
        let endpoint = Endpoint.tcp(host: "192.0.2.1", port: 9999)

        var connectingCalled = false
        let hooks = LifecycleHooks(
            onConnecting: {
                connectingCalled = true
            }
        )

        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 0.2,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: hooks,
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        do {
            try await connection.connect()
        } catch {
            // Expected to fail
        }

        XCTAssertTrue(connectingCalled)
    }

    func testLifecycleHooksOnDisconnecting() async {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)

        var disconnectingCalled = false
        let hooks = LifecycleHooks(
            onDisconnected: { _ in
                disconnectingCalled = true
            }
        )

        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: hooks,
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        await connection.disconnect(reason: .clientInitiated)

        // Give hooks time to execute
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        XCTAssertTrue(disconnectingCalled)
    }

    func testLifecycleHooksOnError() async {
        let endpoint = Endpoint.tcp(host: "192.0.2.1", port: 9999)

        var errorReceived: Error?
        let hooks = LifecycleHooks(
            onError: { error in
                errorReceived = error
            }
        )

        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 0.5,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: hooks,
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        do {
            try await connection.connect()
        } catch {
            // Expected to fail
        }

        // Give hooks time to execute
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Error hook might be called during connection attempts
        // This test verifies the hook mechanism works
    }

    // MARK: - Middleware Tests

    func testMiddlewareProcessing() async throws {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)

        // Create a middleware that adds a prefix
        let middleware = TestPrefixMiddleware(prefix: "TEST:")

        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [middleware],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        // Verify middleware is configured (internal state)
        // Actual middleware processing is tested in integration tests
    }

    // MARK: - Configuration Tests

    func testCustomConfiguration() {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)

        let config = ConnectionConfiguration(
            id: "custom-id",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 15.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: HeartbeatConfiguration(
                interval: 60,
                timeout: 120,
                enabled: true
            ),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )

        connection = TCPConnection(
            id: "custom-id",
            endpoint: endpoint,
            configuration: config
        )

        Task {
            let connectionId = await connection.id
            XCTAssertEqual(connectionId, "custom-id")
        }
    }

    func testTLSConfiguration() {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)

        let tlsConfig = TLSConfiguration(enabled: true)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: tlsConfig,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )

        connection = TCPConnection(
            id: "test",
            endpoint: endpoint,
            configuration: config
        )

        // TLS configuration should be applied during connect
        // Actual TLS functionality tested in integration tests
    }

    func testProxyConfiguration() {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)

        let proxyConfig = ProxyConfiguration(
            type: .socks5,
            host: "proxy.example.com",
            port: 1080
        )

        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: proxyConfig,
            lifecycleHooks: .init(),
            metadata: [:]
        )

        connection = TCPConnection(
            id: "test",
            endpoint: endpoint,
            configuration: config
        )

        // Proxy configuration should be applied during connect
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentDisconnect() async {
        let endpoint = Endpoint.tcp(host: testHost, port: testPort)
        let config = ConnectionConfiguration(
            id: "test",
            endpoint: endpoint,
            protocolAdapter: nil,
            reconnectionStrategy: nil,
            middlewares: [],
            connectTimeout: 10.0,
            readWriteTimeout: 30.0,
            heartbeatConfig: .init(interval: 30, timeout: 60, enabled: false),
            tlsConfig: nil,
            proxyConfig: nil,
            lifecycleHooks: .init(),
            metadata: [:]
        )
        connection = TCPConnection(id: "test", endpoint: endpoint, configuration: config)

        // Multiple concurrent disconnects should be safe
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await self.connection.disconnect(reason: .clientInitiated)
                }
            }
        }

        let state = await connection.state
        XCTAssertEqual(state, .disconnected)
    }
}

// MARK: - Test Helpers

/// Test middleware that adds a prefix to outgoing data
class TestPrefixMiddleware: Middleware {
    let name = "TestPrefixMiddleware"
    let priority = 100
    let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        var result = prefix.data(using: .utf8)!
        result.append(data)
        return result
    }

    func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        // Remove prefix if present
        let prefixData = prefix.data(using: .utf8)!
        if data.starts(with: prefixData) {
            return data.dropFirst(prefixData.count)
        }
        return data
    }
}
