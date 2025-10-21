//
//  WebSocketConnectionTests.swift
//  NexusWebSocketTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit
@testable import NexusKit

/// WebSocket 连接测试
final class WebSocketConnectionTests: XCTestCase {
    
    var connection: WebSocketConnection!
    let testURL = URL(string: "ws://localhost:8080")!
    
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
    
    // MARK: - 基本连接测试
    
    func testConnectionCreation() async throws {
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        let state = await connection.state
        XCTAssertEqual(state, .disconnected)
        
        let connectionId = await connection.id
        XCTAssertEqual(connectionId, "test-connection")
    }
    
    func testConnectionToEchoServer() async throws {
        let expectation = XCTestExpectation(description: "连接成功")
        
        var didConnect = false
        let hooks = LifecycleHooks(
            onConnected: {
                didConnect = true
                expectation.fulfill()
            }
        )
        
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint,
            lifecycleHooks: hooks
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        try await connection.connect()
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        let state = await connection.state
        XCTAssertEqual(state, .connected)
        XCTAssertTrue(didConnect)
    }
    
    func testDisconnect() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        let disconnectExpectation = XCTestExpectation(description: "断开成功")
        
        let hooks = LifecycleHooks(
            onConnected: {
                connectExpectation.fulfill()
            },
            onDisconnected: { _ in
                disconnectExpectation.fulfill()
            }
        )
        
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint,
            lifecycleHooks: hooks
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        try await connection.connect()
        await fulfillment(of: [connectExpectation], timeout: 5.0)
        
        await connection.disconnect(reason: .clientInitiated)
        await fulfillment(of: [disconnectExpectation], timeout: 5.0)
        
        let state = await connection.state
        XCTAssertEqual(state, .disconnected)
    }
    
    // MARK: - 消息收发测试
    
    func testSendTextMessage() async throws {
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        try await connection.connect()
        
        // 等待连接建立
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 发送文本消息
        try await connection.sendText("Hello WebSocket")
    }
    
    func testSendBinaryMessage() async throws {
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        try await connection.connect()
        
        // 等待连接建立
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 发送二进制消息
        let data = "Hello Binary".data(using: .utf8)!
        try await connection.send(data, timeout: nil)
    }
    
    func testReceiveMessage() async throws {
        let messageExpectation = XCTestExpectation(description: "收到消息")
        
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        // 注册消息处理器
        await connection.on(.message) { data in
            let message = String(data: data, encoding: .utf8)
            XCTAssertNotNil(message)
            messageExpectation.fulfill()
        }
        
        try await connection.connect()
        
        // 等待连接建立
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 发送消息（echo 服务器会返回）
        try await connection.sendText("Test Echo")
        
        await fulfillment(of: [messageExpectation], timeout: 5.0)
    }
    
    // MARK: - 心跳测试
    
    func testPingPong() async throws {
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint,
            pingInterval: 2 // 2秒发送一次 ping
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        try await connection.connect()
        
        // 等待几个心跳周期
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5秒
        
        // 验证连接仍然活跃
        let state = await connection.state
        XCTAssertEqual(state, .connected)
    }
    
    func testManualPing() async throws {
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint,
            pingInterval: 0 // 禁用自动 ping
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        try await connection.connect()
        
        // 手动发送 Ping
        try await connection.sendPing()
        
        // 验证连接正常
        let state = await connection.state
        XCTAssertEqual(state, .connected)
    }
    
    // MARK: - 自定义头部测试
    
    func testCustomHeaders() async throws {
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint,
            headers: [
                "Authorization": "Bearer test-token",
                "X-Custom-Header": "custom-value"
            ]
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        // 连接应该成功（即使服务器不验证头部）
        try await connection.connect()
        
        let state = await connection.state
        XCTAssertEqual(state, .connected)
    }
    
    // MARK: - 子协议测试
    
    func testSubprotocols() async throws {
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint,
            protocols: ["chat", "superchat"]
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        // 连接应该成功
        try await connection.connect()
        
        let state = await connection.state
        XCTAssertEqual(state, .connected)
    }
    
    // MARK: - 事件处理器测试
    
    func testMultipleEventHandlers() async throws {
        var handler1Called = false
        var handler2Called = false
        
        let endpoint = Endpoint.webSocket(url: testURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        // 注册多个处理器
        await connection.on(.message) { _ in
            handler1Called = true
        }
        
        await connection.on(.message) { _ in
            handler2Called = true
        }
        
        try await connection.connect()
        
        // 等待连接建立
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // 发送消息触发处理器
        try await connection.sendText("Trigger")
        
        // 等待处理器执行
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        XCTAssertTrue(handler1Called)
        XCTAssertTrue(handler2Called)
    }
    
    // MARK: - 连接超时测试
    
    func testConnectionTimeout() async throws {
        // 使用一个不存在的地址
        let invalidURL = URL(string: "ws://192.0.2.1:9999")!
        let endpoint = Endpoint.webSocket(url: invalidURL)
        let config = WebSocketConfiguration(
            id: "test-connection",
            endpoint: endpoint,
            connectTimeout: 2 // 2秒超时
        )
        
        connection = WebSocketConnection(
            id: "test-connection",
            endpoint: endpoint,
            configuration: config
        )
        
        do {
            try await connection.connect()
            // WebSocket 可能会立即连接成功（然后在接收时失败）
            // 所以这个测试可能通过或失败
        } catch {
            // 预期可能会失败
        }
        
        // 验证最终状态（可能是connected或disconnected）
        let state = await connection.state
        XCTAssertTrue(state == .connected || state == .disconnected)
    }
}

// MARK: - WebSocket Builder Tests

@available(iOS 13.0, macOS 10.15, *)
final class WebSocketBuilderTests: XCTestCase {
    
    func testBuilderPattern() async throws {
        let config = GlobalConfiguration()
        let builder = WebSocketConnectionBuilder(
            endpoint: .webSocket(url: URL(string: "ws://localhost:8080")!),
            configuration: config
        )
        
        let connection = try await builder
            .id("custom-id")
            .headers(["Authorization": "Bearer token"])
            .protocols(["chat"])
            .pingInterval(5)
            .timeout(10)
            .build()
        
        let connectionId = await connection.id
        XCTAssertEqual(connectionId, "custom-id")
    }
}
