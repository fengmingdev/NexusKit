//
//  SocketIOIntegrationTests.swift
//  NexusIOTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

/// Socket.IO 集成测试
/// - Note: 需要启动 TestServers/socketio_server.js
final class SocketIOIntegrationTests: XCTestCase {
    
    var client: SocketIOClient!
    let testURL = URL(string: "http://localhost:3000")!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // 创建客户端
        var config = SocketIOConfiguration()
        config.reconnect = true
        config.timeout = 10.0
        
        client = SocketIOClient(url: testURL, configuration: config)
    }
    
    override func tearDown() async throws {
        // 断开连接
        await client?.disconnect()
        client = nil
        
        try await super.tearDown()
    }
    
    // MARK: - 基本连接测试
    
    func testConnection() async throws {
        let expectation = XCTestExpectation(description: "连接成功")
        
        // 设置代理
        let delegate = TestDelegate()
        delegate.onConnect = { _ in
            expectation.fulfill()
        }
        await client.setDelegate(delegate)
        
        // 连接
        try await client.connect()
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testDisconnect() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        let disconnectExpectation = XCTestExpectation(description: "断开成功")
        
        let delegate = TestDelegate()
        delegate.onConnect = { _ in
            connectExpectation.fulfill()
        }
        delegate.onDisconnect = { _, _ in
            disconnectExpectation.fulfill()
        }
        await client.setDelegate(delegate)
        
        try await client.connect()
        await fulfillment(of: [connectExpectation], timeout: 5.0)
        
        await client.disconnect()
        await fulfillment(of: [disconnectExpectation], timeout: 5.0)
    }
    
    // MARK: - 事件测试
    
    func testEmitAndReceiveEvent() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        let eventExpectation = XCTestExpectation(description: "收到事件")
        
        let delegate = TestDelegate()
        delegate.onConnect = { _ in
            connectExpectation.fulfill()
        }
        delegate.onEvent = { _, event, data in
            if event == "welcome" {
                XCTAssertFalse(data.isEmpty)
                eventExpectation.fulfill()
            }
        }
        await client.setDelegate(delegate)
        
        try await client.connect()
        
        await fulfillment(of: [connectExpectation, eventExpectation], timeout: 5.0)
    }
    
    func testCustomEvent() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        let responseExpectation = XCTestExpectation(description: "收到自定义响应")
        
        let delegate = TestDelegate()
        delegate.onConnect = { client in
            connectExpectation.fulfill()
            
            // 发送自定义事件
            Task {
                try? await client.emit("custom_event", ["test": "data"])
            }
        }
        delegate.onEvent = { _, event, data in
            if event == "custom_response" {
                responseExpectation.fulfill()
            }
        }
        await client.setDelegate(delegate)
        
        try await client.connect()
        
        await fulfillment(of: [connectExpectation, responseExpectation], timeout: 5.0)
    }
    
    // MARK: - Acknowledgment 测试
    
    func testAcknowledgment() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        let ackExpectation = XCTestExpectation(description: "收到确认")
        
        let delegate = TestDelegate()
        delegate.onConnect = { client in
            connectExpectation.fulfill()
            
            // 发送带回调的事件
            Task {
                try? await client.emit("request", ["data": "test"]) { ackData in
                    XCTAssertFalse(ackData.isEmpty)
                    ackExpectation.fulfill()
                }
            }
        }
        await client.setDelegate(delegate)
        
        try await client.connect()
        
        await fulfillment(of: [connectExpectation, ackExpectation], timeout: 5.0)
    }
    
    // MARK: - 事件监听器测试
    
    func testOnEventHandler() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        let handlerExpectation = XCTestExpectation(description: "处理器被调用")
        
        let delegate = TestDelegate()
        delegate.onConnect = { client in
            connectExpectation.fulfill()
        }
        await client.setDelegate(delegate)
        
        // 添加事件监听器
        await client.on("welcome") { data in
            XCTAssertFalse(data.isEmpty)
            handlerExpectation.fulfill()
        }
        
        try await client.connect()
        
        await fulfillment(of: [connectExpectation, handlerExpectation], timeout: 5.0)
    }
    
    func testOnceEventHandler() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        let onceExpectation = XCTestExpectation(description: "Once处理器被调用")
        onceExpectation.expectedFulfillmentCount = 1 // 只应被调用一次
        
        let delegate = TestDelegate()
        delegate.onConnect = { _ in
            connectExpectation.fulfill()
        }
        await client.setDelegate(delegate)
        
        // 添加一次性事件监听器
        await client.once("welcome") { data in
            onceExpectation.fulfill()
        }
        
        try await client.connect()
        
        await fulfillment(of: [connectExpectation, onceExpectation], timeout: 5.0)
    }
    
    // MARK: - 房间功能测试
    
    func testJoinRoom() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        
        let delegate = TestDelegate()
        delegate.onConnect = { client in
            connectExpectation.fulfill()
            
            // 加入房间
            Task {
                let rooms = await client.rooms()
                try? await rooms.join("test_room")
                
                // 验证房间状态
                let joinedRooms = await rooms.getRooms()
                XCTAssertTrue(joinedRooms.contains("test_room"))
            }
        }
        await client.setDelegate(delegate)
        
        try await client.connect()
        
        await fulfillment(of: [connectExpectation], timeout: 5.0)
    }
    
    func testLeaveRoom() async throws {
        let connectExpectation = XCTestExpectation(description: "连接成功")
        
        let delegate = TestDelegate()
        delegate.onConnect = { client in
            connectExpectation.fulfill()
            
            Task {
                let rooms = await client.rooms()
                
                // 加入房间
                try? await rooms.join("test_room")
                let isInRoom1 = await rooms.isInRoom("test_room")
                XCTAssertTrue(isInRoom1)
                
                // 离开房间
                try? await rooms.leave("test_room")
                let isInRoom2 = await rooms.isInRoom("test_room")
                XCTAssertFalse(isInRoom2)
            }
        }
        await client.setDelegate(delegate)
        
        try await client.connect()
        
        await fulfillment(of: [connectExpectation], timeout: 5.0)
    }
}

// MARK: - Test Delegate

/// 测试代理，使用 @unchecked Sendable 因为回调在测试中不会并发访问
final class TestDelegate: SocketIOClientDelegate, @unchecked Sendable {
    var onConnect: ((SocketIOClient) -> Void)?
    var onDisconnect: ((SocketIOClient, String) -> Void)?
    var onError: ((SocketIOClient, Error) -> Void)?
    var onEvent: ((SocketIOClient, String, [Any]) -> Void)?
    
    func socketIOClientDidConnect(_ client: SocketIOClient) async {
        onConnect?(client)
    }
    
    func socketIOClientDidDisconnect(_ client: SocketIOClient, reason: String) async {
        onDisconnect?(client, reason)
    }
    
    func socketIOClient(_ client: SocketIOClient, didFailWithError error: Error) async {
        onError?(client, error)
    }
    
    func socketIOClient(_ client: SocketIOClient, didReceiveEvent event: String, data: [Any]) async {
        onEvent?(client, event, data)
    }
}
