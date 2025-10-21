//
//  CustomProtocolTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

final class CustomProtocolTests: XCTestCase {
    
    // MARK: - JSON Protocol Tests
    
    func testJSONProtocolEncode() throws {
        // Given
        let proto = JSONProtocol()
        let context = EncodingContext(connectionId: "test")
        
        struct TestMessage: Codable {
            let text: String
            let value: Int
        }
        
        let message = TestMessage(text: "Hello", value: 42)
        
        // When
        let data = try proto.encode(message, context: context)
        
        // Then
        XCTAssertGreaterThan(data.count, 0)
        
        // 验证可以解码回来
        let decoded = try JSONDecoder().decode(TestMessage.self, from: data)
        XCTAssertEqual(decoded.text, "Hello")
        XCTAssertEqual(decoded.value, 42)
    }
    
    func testJSONProtocolDecode() throws {
        // Given
        let proto = JSONProtocol()
        let context = DecodingContext(connectionId: "test", dataSize: 100)
        
        struct TestMessage: Codable {
            let text: String
        }
        
        let jsonData = "{\"text\":\"Hello\"}".data(using: .utf8)!
        
        // When
        let decoded = try proto.decode(jsonData, as: TestMessage.self, context: context)
        
        // Then
        XCTAssertEqual(decoded.text, "Hello")
    }
    
    func testJSONProtocolHandleIncomingEvent() async throws {
        // Given
        let proto = JSONProtocol()
        let eventData = """
        {"event": "message", "data": {"text": "Hello"}}
        """.data(using: .utf8)!
        
        // When
        let events = try await proto.handleIncoming(eventData)
        
        // Then
        XCTAssertEqual(events.count, 1)
        if case .notification(let event, _) = events[0] {
            XCTAssertEqual(event, "message")
        } else {
            XCTFail("Expected notification event")
        }
    }
    
    func testJSONProtocolHandleIncomingHeartbeat() async throws {
        // Given
        let proto = JSONProtocol()
        let heartbeatData = """
        {"type": "heartbeat"}
        """.data(using: .utf8)!
        
        // When
        let events = try await proto.handleIncoming(heartbeatData)
        
        // Then
        XCTAssertEqual(events.count, 1)
        if case .control(let type, _) = events[0] {
            if case .heartbeat = type {
                // Success
            } else {
                XCTFail("Expected heartbeat control event")
            }
        } else {
            XCTFail("Expected control event")
        }
    }
    
    func testJSONProtocolCapabilities() {
        // Given
        let proto = JSONProtocol()
        
        // When
        let capabilities = proto.capabilities
        
        // Then
        XCTAssertTrue(capabilities.contains(.compression))
        XCTAssertTrue(capabilities.contains(.heartbeat))
        XCTAssertTrue(capabilities.contains(.bidirectional))
    }
    
    func testJSONProtocolMetadata() {
        // Given
        let proto = JSONProtocol()
        
        // When
        let metadata = proto.metadata
        
        // Then
        XCTAssertEqual(metadata.author, "NexusKit")
        XCTAssertTrue(metadata.tags.contains("json"))
        XCTAssertEqual(metadata.customProperties["content-type"], "application/json")
    }
    
    func testJSONProtocolConfigure() async throws {
        // Given
        let proto = JSONProtocol()
        
        // When
        try await proto.configure(with: ["prettyPrint": true, "sortedKeys": true])
        
        // Then - 配置应该成功（无异常）
    }
    
    // MARK: - MessagePack Protocol Tests
    
    func testMessagePackProtocolEncode() throws {
        // Given
        let proto = MessagePackProtocol()
        let context = EncodingContext(connectionId: "test")
        
        struct TestMessage: Codable {
            let text: String
        }
        
        let message = TestMessage(text: "Hello")
        
        // When
        let data = try proto.encode(message, context: context)
        
        // Then
        XCTAssertGreaterThan(data.count, 0)
        // 第一个字节应该是版本标记
        XCTAssertEqual(data[0], 0x01)
    }
    
    func testMessagePackProtocolDecode() throws {
        // Given
        let proto = MessagePackProtocol()
        let context = DecodingContext(connectionId: "test", dataSize: 100)
        
        struct TestMessage: Codable {
            let text: String
        }
        
        // 创建带版本标记的数据
        let jsonData = "{\"text\":\"Hello\"}".data(using: .utf8)!
        var msgpackData = Data()
        msgpackData.append(0x01) // 版本标记
        msgpackData.append(contentsOf: jsonData)
        
        // When
        let decoded = try proto.decode(msgpackData, as: TestMessage.self, context: context)
        
        // Then
        XCTAssertEqual(decoded.text, "Hello")
    }
    
    func testMessagePackProtocolHandleIncomingHeartbeat() async throws {
        // Given
        let proto = MessagePackProtocol()
        let heartbeatData = proto.heartbeatData!
        
        // When
        let events = try await proto.handleIncoming(heartbeatData)
        
        // Then
        XCTAssertEqual(events.count, 1)
        if case .control(let type, _) = events[0] {
            if case .heartbeat = type {
                // Success
            } else {
                XCTFail("Expected heartbeat control event")
            }
        } else {
            XCTFail("Expected control event")
        }
    }
    
    func testMessagePackProtocolCapabilities() {
        // Given
        let proto = MessagePackProtocol()
        
        // When
        let capabilities = proto.capabilities
        
        // Then
        XCTAssertTrue(capabilities.contains(.compression))
        XCTAssertTrue(capabilities.contains(.heartbeat))
        XCTAssertTrue(capabilities.contains(.bidirectional))
        XCTAssertTrue(capabilities.contains(.fragmentation))
    }
    
    func testMessagePackProtocolMetadata() {
        // Given
        let proto = MessagePackProtocol()
        
        // When
        let metadata = proto.metadata
        
        // Then
        XCTAssertEqual(metadata.author, "NexusKit")
        XCTAssertTrue(metadata.tags.contains("messagepack"))
        XCTAssertEqual(metadata.customProperties["content-type"], "application/msgpack")
    }
    
    func testMessagePackProtocolPriority() {
        // Given
        let jsonProtocol = JSONProtocol()
        let msgpackProtocol = MessagePackProtocol()
        
        // Then - MessagePack 应该有更高的默认优先级
        XCTAssertGreaterThan(msgpackProtocol.priority, jsonProtocol.priority)
    }
    
    // MARK: - Protocol Info Tests
    
    func testProtocolInfoFromCustomProtocol() {
        // Given
        let jsonProtocol = JSONProtocol(version: "2.0", priority: 15)
        
        // When
        let info = ProtocolInfo(from: jsonProtocol, supportedVersions: ["1.0", "2.0"])
        
        // Then
        XCTAssertEqual(info.name, "JSON")
        XCTAssertEqual(info.version, "2.0")
        XCTAssertEqual(info.supportedVersions, ["1.0", "2.0"])
        XCTAssertEqual(info.priority, 15)
        XCTAssertEqual(info.capabilities, jsonProtocol.capabilities.rawValue)
    }
    
    func testProtocolInfoCodable() throws {
        // Given
        let info = ProtocolInfo(
            identifier: "json",
            name: "JSON",
            version: "1.0",
            supportedVersions: ["1.0", "2.0"],
            capabilities: 0x07,
            priority: 10,
            metadata: ["author": "NexusKit"]
        )
        
        // When
        let encoded = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(ProtocolInfo.self, from: encoded)
        
        // Then
        XCTAssertEqual(decoded.identifier, "json")
        XCTAssertEqual(decoded.name, "JSON")
        XCTAssertEqual(decoded.version, "1.0")
        XCTAssertEqual(decoded.supportedVersions, ["1.0", "2.0"])
        XCTAssertEqual(decoded.capabilities, 0x07)
        XCTAssertEqual(decoded.priority, 10)
        XCTAssertEqual(decoded.metadata["author"], "NexusKit")
    }
}
