//
//  BinaryProtocolAdapterTests.swift
//  NexusTCPTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore
@testable import NexusTCP

/// 二进制协议适配器测试
final class BinaryProtocolAdapterTests: XCTestCase {

    // MARK: - Properties

    var adapter: BinaryProtocolAdapter!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        adapter = BinaryProtocolAdapter()
    }

    override func tearDown() {
        adapter = nil
        super.tearDown()
    }

    // MARK: - Encoding Tests

    func testBasicEncoding() throws {
        struct TestMessage: Codable {
            let text: String
            let number: Int
        }

        let message = TestMessage(text: "Hello", number: 42)
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test")

        let data = try adapter.encode(message, context: context)

        // Verify structure: [4 bytes length prefix][20 bytes header][body]
        XCTAssertGreaterThanOrEqual(data.count, 24) // At least 4 + 20

        // Verify length prefix
        let totalLength = data.readBigEndianUInt32(at: 0)
        XCTAssertNotNil(totalLength)
        XCTAssertEqual(UInt32(data.count), totalLength! + 4) // Total = length field + totalLength value
    }

    func testEncodingWithFunctionId() throws {
        struct TestMessage: Codable {
            let value: String
        }

        let message = TestMessage(value: "test")
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test", metadata: ["functionId": "12345"])

        let data = try adapter.encode(message, context: context)

        // Verify header contains function ID
        XCTAssertGreaterThanOrEqual(data.count, 24)

        // Function ID is at offset 14-17 in the header (after 4-byte length prefix)
        let functionId = data.readBigEndianUInt32(at: 14) // offset 14-17
        XCTAssertEqual(functionId, 12345)
    }

    func testEncodingProtocolTag() throws {
        struct TestMessage: Codable {
            let data: String
        }

        let message = TestMessage(data: "test")
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test")

        let data = try adapter.encode(message, context: context)

        // Protocol tag is at offset 4-5 (after length prefix)
        let tag = data.readBigEndianUInt16(at: 4)
        XCTAssertNotNil(tag)
        XCTAssertEqual(tag, 0x7A5A) // Expected protocol tag
    }

    func testEncodingProtocolVersion() throws {
        struct TestMessage: Codable {
            let data: String
        }

        let message = TestMessage(data: "test")
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test")

        let data = try adapter.encode(message, context: context)

        // Version is at offset 6-7
        let version = data.readBigEndianUInt16(at: 6)
        XCTAssertNotNil(version)
        XCTAssertEqual(version, 1) // Default version
    }

    func testEncodingCustomVersion() throws {
        adapter = BinaryProtocolAdapter(version: 2)

        struct TestMessage: Codable {
            let data: String
        }

        let message = TestMessage(data: "test")
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test")

        let data = try adapter.encode(message, context: context)

        let version = data.readBigEndianUInt16(at: 6)
        XCTAssertEqual(version, 2)
    }

    func testEncodingRequestFlag() throws {
        struct TestMessage: Codable {
            let data: String
        }

        let message = TestMessage(data: "test")
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test")

        let data = try adapter.encode(message, context: context)

        // Response flag is at offset 9 (should be 0 for requests)
        let responseFlag = data.readBigEndianUInt8(at: 9)
        XCTAssertEqual(responseFlag, 0)
    }

    // MARK: - Decoding Tests

    func testBasicDecoding() throws {
        struct TestMessage: Codable, Equatable {
            let text: String
            let number: Int
        }

        let original = TestMessage(text: "Hello", number: 42)

        // Encode first
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let encContext = EncodingContext(connectionId: "test")
        let encoded = try adapter.encode(original, context: encContext)

        // Decode (使用完整数据，包括长度前缀)
        let decContext = DecodingContext(connectionId: "test", dataSize: encoded.count)
        let decoded: TestMessage = try adapter.decode(encoded, as: TestMessage.self, context: decContext)

        XCTAssertEqual(decoded, original)
    }

    func testDecodingInvalidData() {
        let invalidData = Data([0x00, 0x01, 0x02]) // Too short

        struct TestMessage: Codable {
            let text: String
        }

        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = DecodingContext(connectionId: "test", dataSize: invalidData.count)

        XCTAssertThrowsError(try adapter.decode(invalidData, as: TestMessage.self, context: context)) { error in
            guard let nexusError = error as? NexusError else {
                XCTFail("Wrong error type")
                return
            }

            if case .invalidMessageFormat(let reason) = nexusError {
                XCTAssertTrue(reason.contains("Header too short"))
            } else {
                XCTFail("Expected invalidMessageFormat error")
            }
        }
    }

    func testDecodingInvalidProtocolTag() throws {
        // Create data with invalid protocol tag
        // 格式: [4字节Len] + [Tag(2) + Ver(2) + Tp(1) + Res(1) + Qid(4) + Fid(4) + Code(4) + Dh(2)]
        var data = Data()
        data.appendBigEndian(UInt32(20)) // Length
        data.appendBigEndian(UInt16(0xFFFF)) // Invalid tag
        data.appendBigEndian(UInt16(1)) // Version
        data.appendBigEndian(UInt8(0)) // Type flags
        data.appendBigEndian(UInt8(0)) // Response flag
        data.appendBigEndian(UInt32(1)) // Request ID
        data.appendBigEndian(UInt32(0)) // Function ID
        data.appendBigEndian(UInt32(0)) // Response code
        data.appendBigEndian(UInt16(0)) // Dh (保留字段)

        struct TestMessage: Codable {
            let text: String
        }

        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = DecodingContext(connectionId: "test", dataSize: data.count)

        XCTAssertThrowsError(try adapter.decode(data, as: TestMessage.self, context: context)) { error in
            guard let nexusError = error as? NexusError else {
                XCTFail("Wrong error type")
                return
            }

            if case .invalidMessageFormat(let reason) = nexusError {
                XCTAssertTrue(reason.contains("Invalid protocol tag"))
            } else {
                XCTFail("Expected invalidMessageFormat error")
            }
        }
    }

    // MARK: - Heartbeat Tests

    func testHeartbeatCreation() async throws {
        let heartbeat = try await adapter.createHeartbeat()

        // Heartbeat should be 24 bytes: 4-byte length + 20-byte header
        XCTAssertEqual(heartbeat.count, 24)

        // Verify length field
        let totalLength = heartbeat.readBigEndianUInt32(at: 0)
        XCTAssertEqual(totalLength, 20) // Only header, no body

        // Verify protocol tag
        let tag = heartbeat.readBigEndianUInt16(at: 4)
        XCTAssertEqual(tag, 0x7A5A)

        // Verify idle flag (bit 0 of type flags)
        let typeFlags = heartbeat.readBigEndianUInt8(at: 8)
        XCTAssertEqual(typeFlags! & 0x01, 0x01) // Idle flag set

        // Verify function ID is 0xFFFF (heartbeat marker)
        let functionId = heartbeat.readBigEndianUInt32(at: 14)
        XCTAssertEqual(functionId, 0xFFFF)
    }

    // MARK: - Compression Tests

    #if canImport(Compression)
    func testCompressionEnabled() throws {
        adapter = BinaryProtocolAdapter(compressionEnabled: true)

        struct TestMessage: Codable {
            let text: String
        }

        // Large message that should trigger compression
        let message = TestMessage(text: String(repeating: "A", count: 2000))
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test")

        let data = try adapter.encode(message, context: context)

        // Check compression flag (bit 5 of type flags at offset 8)
        let typeFlags = data.readBigEndianUInt8(at: 8)
        let isCompressed = (typeFlags! & 0x20) != 0

        // For a message of 2000 'A's, compression should be triggered
        XCTAssertTrue(isCompressed, "Compression should be enabled for large messages")
    }

    func testCompressionDisabled() throws {
        adapter = BinaryProtocolAdapter(compressionEnabled: false)

        struct TestMessage: Codable {
            let text: String
        }

        let message = TestMessage(text: String(repeating: "A", count: 2000))
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test")

        let data = try adapter.encode(message, context: context)

        // Check compression flag
        let typeFlags = data.readBigEndianUInt8(at: 8)
        let isCompressed = (typeFlags! & 0x20) != 0

        XCTAssertFalse(isCompressed, "Compression should be disabled")
    }

    func testCompressionRoundTrip() throws {
        adapter = BinaryProtocolAdapter(compressionEnabled: true)

        struct TestMessage: Codable, Equatable {
            let text: String
        }

        // Large message
        let original = TestMessage(text: String(repeating: "Hello World! ", count: 200))

        // Encode
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let encContext = EncodingContext(connectionId: "test")
        let encoded = try adapter.encode(original, context: encContext)

        // Decode (使用完整数据)
        let decContext = DecodingContext(connectionId: "test", dataSize: encoded.count)
        let decoded: TestMessage = try adapter.decode(encoded, as: TestMessage.self, context: decContext)

        XCTAssertEqual(decoded, original)
    }
    #endif

    // MARK: - Message Encoder/Decoder Tests

    func testCustomJSONEncoder() throws {
        let jsonEncoder = JSONMessageEncoder()
        let jsonDecoder = JSONMessageDecoder()

        adapter = BinaryProtocolAdapter(
            version: 1,
            compressionEnabled: false,
            encoder: jsonEncoder,
            decoder: jsonDecoder
        )

        struct TestMessage: Codable, Equatable {
            let name: String
            let age: Int
        }

        let original = TestMessage(name: "Alice", age: 30)

        // Encode
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let encContext = EncodingContext(connectionId: "test")
        let encoded = try adapter.encode(original, context: encContext)

        // Decode (使用完整数据)
        let decContext = DecodingContext(connectionId: "test", dataSize: encoded.count)
        let decoded: TestMessage = try adapter.decode(encoded, as: TestMessage.self, context: decContext)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Protocol Event Handling Tests

    func testHandleIncomingResponseEvent() async throws {
        // Create a response message (responseFlag = 1)
        // 格式: [4字节Len] + [Tag(2) + Ver(2) + Tp(1) + Res(1) + Qid(4) + Fid(4) + Code(4) + Dh(2)]
        var data = Data()
        data.appendBigEndian(UInt32(20)) // Length (header only)
        data.appendBigEndian(UInt16(0x7A5A)) // Protocol tag
        data.appendBigEndian(UInt16(1)) // Version
        data.appendBigEndian(UInt8(0)) // Type flags
        data.appendBigEndian(UInt8(1)) // Response flag = 1
        data.appendBigEndian(UInt32(123)) // Request ID
        data.appendBigEndian(UInt32(0)) // Function ID
        data.appendBigEndian(UInt32(0)) // Response code
        data.appendBigEndian(UInt16(0)) // Dh

        let events = try await adapter.handleIncoming(data)

        XCTAssertEqual(events.count, 1)
        if case .response = events[0] {
            // Expected
        } else {
            XCTFail("Expected response event")
        }
    }

    func testHandleIncomingHeartbeatEvent() async throws {
        // Create a heartbeat message (functionId = 0xFFFF)
        var data = Data()
        data.appendBigEndian(UInt32(20)) // Length
        data.appendBigEndian(UInt16(0x7A5A)) // Protocol tag
        data.appendBigEndian(UInt16(1)) // Version
        data.appendBigEndian(UInt8(0x01)) // Type flags (idle)
        data.appendBigEndian(UInt8(0)) // Response flag = 0 (request)
        data.appendBigEndian(UInt32(0)) // Request ID
        data.appendBigEndian(UInt32(0xFFFF)) // Function ID = heartbeat
        data.appendBigEndian(UInt32(0)) // Response code
        data.appendBigEndian(UInt16(0)) // Dh

        let events = try await adapter.handleIncoming(data)

        XCTAssertEqual(events.count, 1)
        if case .control(let type, _) = events[0] {
            if case .heartbeat = type {
                // Expected
            } else {
                XCTFail("Expected heartbeat type")
            }
        } else {
            XCTFail("Expected control event with heartbeat type")
        }
    }

    func testHandleIncomingNotificationEvent() async throws {
        // Create a notification message (not response, not heartbeat)
        var data = Data()
        data.appendBigEndian(UInt32(20)) // Length
        data.appendBigEndian(UInt16(0x7A5A)) // Protocol tag
        data.appendBigEndian(UInt16(1)) // Version
        data.appendBigEndian(UInt8(0)) // Type flags
        data.appendBigEndian(UInt8(0)) // Response flag = 0 (not a response)
        data.appendBigEndian(UInt32(0)) // Request ID
        data.appendBigEndian(UInt32(100)) // Function ID (not 0xFFFF)
        data.appendBigEndian(UInt32(0)) // Response code
        data.appendBigEndian(UInt16(0)) // Dh

        let events = try await adapter.handleIncoming(data)

        XCTAssertEqual(events.count, 1)
        if case .notification = events[0] {
            // Expected
        } else {
            XCTFail("Expected notification event")
        }
    }

    func testHandleIncomingIncompleteMessage() async {
        // Create incomplete message (header says body length but it's missing)
        var data = Data()
        data.appendBigEndian(UInt32(100)) // Length claims 100 bytes (20 header + 80 body)
        data.appendBigEndian(UInt16(0x7A5A)) // Protocol tag
        data.appendBigEndian(UInt16(1)) // Version
        data.appendBigEndian(UInt8(0)) // Type flags
        data.appendBigEndian(UInt8(0)) // Response flag
        data.appendBigEndian(UInt32(0)) // Request ID
        data.appendBigEndian(UInt32(0)) // Function ID
        data.appendBigEndian(UInt32(0)) // Response code
        data.appendBigEndian(UInt16(0)) // Dh
        // Body is missing (should be 80 more bytes)

        do {
            _ = try await adapter.handleIncoming(data)
            XCTFail("Should throw incomplete body error")
        } catch let error as NexusError {
            if case .invalidMessageFormat(let reason) = error {
                XCTAssertTrue(reason.contains("Incomplete body"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Request ID Generation Tests

    func testRequestIdGeneration() throws {
        struct TestMessage: Codable {
            let data: String
        }

        let message = TestMessage(data: "test")
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let context = EncodingContext(connectionId: "test")

        // Generate multiple requests
        let data1 = try adapter.encode(message, context: context)
        let data2 = try adapter.encode(message, context: context)
        let data3 = try adapter.encode(message, context: context)

        // Extract request IDs (at offset 10-13 in header)
        let reqId1 = data1.readBigEndianUInt32(at: 10)
        let reqId2 = data2.readBigEndianUInt32(at: 10)
        let reqId3 = data3.readBigEndianUInt32(at: 10)

        // Request IDs should be unique and incrementing
        XCTAssertNotEqual(reqId1, reqId2)
        XCTAssertNotEqual(reqId2, reqId3)
        XCTAssertNotEqual(reqId1, reqId3)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentEncoding() async throws {
        struct TestMessage: Codable {
            let value: Int
        }

        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let message = TestMessage(value: i)
                    let context = EncodingContext(connectionId: "test-\(i)")
                    _ = try? self.adapter.encode(message, context: context)
                }
            }
        }

        // Should complete without crashes or data races
    }

    func testConcurrentHeartbeatCreation() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    _ = try? await self.adapter.createHeartbeat()
                }
            }
        }

        // Should complete without crashes
    }

    // MARK: - Edge Cases

    func testEmptyMessageBody() throws {
        struct EmptyMessage: Codable, Equatable {}

        let message = EmptyMessage()
        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let encContext = EncodingContext(connectionId: "test")

        let encoded = try adapter.encode(message, context: encContext)

        // Should still have header
        XCTAssertGreaterThanOrEqual(encoded.count, 24)

        // Decode (使用完整数据)
        let decContext = DecodingContext(connectionId: "test", dataSize: encoded.count)
        let decoded: EmptyMessage = try adapter.decode(encoded, as: EmptyMessage.self, context: decContext)

        XCTAssertEqual(decoded, message)
    }

    func testLargeMessage() throws {
        struct LargeMessage: Codable, Equatable {
            let data: [UInt8]
        }

        // 1MB of data
        let largeData = [UInt8](repeating: 0x42, count: 1_000_000)
        let message = LargeMessage(data: largeData)

        let endpoint = Endpoint.tcp(host: "localhost", port: 8080)
        let encContext = EncodingContext(connectionId: "test")

        let encoded = try adapter.encode(message, context: encContext)

        // Verify length field is correct
        let totalLength = encoded.readBigEndianUInt32(at: 0)
        XCTAssertNotNil(totalLength)

        // Decode (使用完整数据)
        let decContext = DecodingContext(connectionId: "test", dataSize: encoded.count)
        let decoded: LargeMessage = try adapter.decode(encoded, as: LargeMessage.self, context: decContext)

        XCTAssertEqual(decoded.data.count, largeData.count)
    }
}
