//
//  SocketIOPacketTests.swift
//  NexusIOTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusIO

final class SocketIOPacketTests: XCTestCase {
    
    // MARK: - 包创建测试
    
    func testConnectPacket() {
        let packet = SocketIOPacket.connect()
        
        XCTAssertEqual(packet.type, .connect)
        XCTAssertEqual(packet.namespace, "/")
        XCTAssertNil(packet.data)
        XCTAssertNil(packet.id)
    }
    
    func testConnectPacketWithAuth() {
        let auth = ["token": "abc123"]
        let packet = SocketIOPacket.connect(auth: auth)
        
        XCTAssertEqual(packet.type, .connect)
        XCTAssertEqual(packet.data?.count, 1)
    }
    
    func testDisconnectPacket() {
        let packet = SocketIOPacket.disconnect()
        
        XCTAssertEqual(packet.type, .disconnect)
        XCTAssertEqual(packet.namespace, "/")
    }
    
    func testEventPacket() {
        let packet = SocketIOPacket.event("message", items: ["Hello", "World"])
        
        XCTAssertEqual(packet.type, .event)
        XCTAssertEqual(packet.data?.count, 3) // eventName + 2 items
        XCTAssertEqual(packet.data?[0] as? String, "message")
    }
    
    func testAckPacket() {
        let packet = SocketIOPacket.ack(data: ["OK"], id: 42)
        
        XCTAssertEqual(packet.type, .ack)
        XCTAssertEqual(packet.id, 42)
        XCTAssertEqual(packet.data?.count, 1)
    }
    
    func testConnectErrorPacket() {
        let packet = SocketIOPacket.connectError(message: "Auth failed")
        
        XCTAssertEqual(packet.type, .connectError)
        XCTAssertEqual(packet.data?.count, 1)
    }
    
    // MARK: - 命名空间测试
    
    func testCustomNamespace() {
        let packet = SocketIOPacket.connect(namespace: "/chat")
        
        XCTAssertEqual(packet.namespace, "/chat")
    }
    
    // MARK: - 描述测试
    
    func testDescription() {
        let packet = SocketIOPacket.event("test", items: ["data"])
        let description = packet.description
        
        XCTAssertTrue(description.contains("EVENT"))
        XCTAssertTrue(description.contains("type"))
    }
    
    func testPacketTypeDescription() {
        XCTAssertEqual(SocketIOPacketType.connect.description, "CONNECT")
        XCTAssertEqual(SocketIOPacketType.disconnect.description, "DISCONNECT")
        XCTAssertEqual(SocketIOPacketType.event.description, "EVENT")
        XCTAssertEqual(SocketIOPacketType.ack.description, "ACK")
        XCTAssertEqual(SocketIOPacketType.connectError.description, "CONNECT_ERROR")
    }
}
