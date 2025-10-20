//
//  CustomBinaryProtocol.swift
//  NexusCore Examples
//
//  Created by NexusKit on 2025-01-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import Foundation
import NexusCore

/// Custom binary protocol with fixed header and variable payload
/// This demonstrates a high-performance binary protocol design
///
/// Protocol Format:
/// ┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
/// │  Magic   │ Version  │  OpCode  │  Flags   │  Length  │ Payload  │
/// │ (4 bytes)│ (2 bytes)│ (1 byte) │ (1 byte) │ (4 bytes)│(Variable)│
/// └──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
public actor CustomBinaryProtocol: ProtocolHandler {

    // MARK: - Protocol Constants

    public static let magic: UInt32 = 0x4E455855 // "NEXU" in hex
    public static let currentVersion: UInt16 = 0x0100 // Version 1.0
    public static let headerSize = 12 // 4 + 2 + 1 + 1 + 4

    // MARK: - Operation Codes

    public enum OpCode: UInt8 {
        case handshake = 0x01
        case handshakeAck = 0x02
        case ping = 0x10
        case pong = 0x11
        case request = 0x20
        case response = 0x21
        case notification = 0x30
        case error = 0xFF
    }

    // MARK: - Message Flags

    public struct Flags: OptionSet {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let compressed = Flags(rawValue: 1 << 0)
        public static let encrypted = Flags(rawValue: 1 << 1)
        public static let requiresAck = Flags(rawValue: 1 << 2)
        public static let isFragment = Flags(rawValue: 1 << 3)
    }

    // MARK: - Binary Message

    public struct BinaryMessage: ProtocolMessage {
        public let messageType: String
        public let payload: Data
        public let metadata: [String: String]

        public let opCode: OpCode
        public let flags: Flags
        public let version: UInt16

        public init(opCode: OpCode, payload: Data = Data(), flags: Flags = [], version: UInt16 = CustomBinaryProtocol.currentVersion) {
            self.opCode = opCode
            self.payload = payload
            self.flags = flags
            self.version = version
            self.messageType = String(describing: opCode)
            self.metadata = [:]
        }
    }

    // MARK: - Properties

    public let protocolName: String = "CustomBinary"
    public let protocolVersion: String = "1.0"

    private var receiveBuffer: Data = Data()
    private var messageHandler: ((BinaryMessage) async throws -> BinaryMessage?)?
    private var isHandshakeComplete = false

    // MARK: - Initialization

    public init() {}

    /// Set message handler (returns optional response message)
    public func setMessageHandler(_ handler: @escaping (BinaryMessage) async throws -> BinaryMessage?) {
        self.messageHandler = handler
    }

    // MARK: - ProtocolHandler Implementation

    public func onConnect(context: ProtocolContext) async throws {
        // Send handshake
        let handshake = BinaryMessage(opCode: .handshake)
        let data = try await encodeMessage(handshake, context: context)
        try await context.send(data)

        // Wait for handshake ack
        let response = try await context.receive(timeout: 5.0)
        let messages = try await onDataReceived(response, context: context)

        guard let ack = messages.first as? BinaryMessage,
              ack.opCode == .handshakeAck else {
            throw ProtocolError.protocolViolation("Expected handshake ack")
        }

        isHandshakeComplete = true
    }

    public func onDisconnect(context: ProtocolContext) async {
        receiveBuffer.removeAll()
        isHandshakeComplete = false
    }

    public func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage] {
        receiveBuffer.append(data)

        var messages: [ProtocolMessage] = []

        while receiveBuffer.count >= Self.headerSize {
            // Read magic number
            let magic = receiveBuffer.withUnsafeBytes { $0.load(as: UInt32.self) }
            guard magic == Self.magic else {
                throw ProtocolError.decodingError("Invalid magic number: 0x\(String(magic, radix: 16))")
            }

            // Read version
            let version = receiveBuffer.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self) }

            // Read opcode
            let opCodeRaw = receiveBuffer[6]
            guard let opCode = OpCode(rawValue: opCodeRaw) else {
                throw ProtocolError.decodingError("Invalid opcode: 0x\(String(opCodeRaw, radix: 16))")
            }

            // Read flags
            let flagsRaw = receiveBuffer[7]
            let flags = Flags(rawValue: flagsRaw)

            // Read length
            let length = receiveBuffer.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }

            let totalLength = Self.headerSize + Int(length)
            guard receiveBuffer.count >= totalLength else {
                // Need more data
                break
            }

            // Extract payload
            let payloadStart = Self.headerSize
            let payloadEnd = payloadStart + Int(length)
            let payload = Data(receiveBuffer[payloadStart..<payloadEnd])

            let message = BinaryMessage(opCode: opCode, payload: payload, flags: flags, version: version)
            messages.append(message)

            // Remove processed data
            receiveBuffer.removeFirst(totalLength)
        }

        return messages
    }

    public func encodeMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws -> Data {
        guard let binaryMessage = message as? BinaryMessage else {
            throw ProtocolError.encodingError("Not a binary message")
        }

        var data = Data(capacity: Self.headerSize + binaryMessage.payload.count)

        // Magic number (4 bytes)
        withUnsafeBytes(of: Self.magic) { data.append(contentsOf: $0) }

        // Version (2 bytes)
        withUnsafeBytes(of: binaryMessage.version) { data.append(contentsOf: $0) }

        // OpCode (1 byte)
        data.append(binaryMessage.opCode.rawValue)

        // Flags (1 byte)
        data.append(binaryMessage.flags.rawValue)

        // Length (4 bytes)
        let length = UInt32(binaryMessage.payload.count)
        withUnsafeBytes(of: length) { data.append(contentsOf: $0) }

        // Payload
        data.append(binaryMessage.payload)

        return data
    }

    public func handleMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws {
        guard let binaryMessage = message as? BinaryMessage else {
            throw ProtocolError.invalidMessage("Not a binary message")
        }

        // Auto-handle ping/pong
        if binaryMessage.opCode == .ping {
            let pong = BinaryMessage(opCode: .pong)
            let data = try await encodeMessage(pong, context: context)
            try await context.send(data)
            return
        }

        // Auto-handle handshake (server side)
        if binaryMessage.opCode == .handshake {
            let ack = BinaryMessage(opCode: .handshakeAck)
            let data = try await encodeMessage(ack, context: context)
            try await context.send(data)
            isHandshakeComplete = true
            return
        }

        // Call custom handler
        if let handler = messageHandler {
            if let response = try await handler(binaryMessage) {
                let data = try await encodeMessage(response, context: context)
                try await context.send(data)
            }
        }
    }

    // MARK: - Public Methods

    /// Send a request and optionally wait for response
    public func request(_ payload: Data, context: ProtocolContext, waitForResponse: Bool = false) async throws -> BinaryMessage? {
        let message = BinaryMessage(opCode: .request, payload: payload, flags: waitForResponse ? [.requiresAck] : [])
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)

        if waitForResponse {
            let responseData = try await context.receive(timeout: 5.0)
            let messages = try await onDataReceived(responseData, context: context)
            return messages.first as? BinaryMessage
        }

        return nil
    }

    /// Send a response
    public func respond(_ payload: Data, context: ProtocolContext) async throws {
        let message = BinaryMessage(opCode: .response, payload: payload)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    /// Send a notification (fire and forget)
    public func notify(_ payload: Data, context: ProtocolContext) async throws {
        let message = BinaryMessage(opCode: .notification, payload: payload)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    /// Send ping
    public func ping(context: ProtocolContext) async throws {
        let message = BinaryMessage(opCode: .ping)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    /// Send error
    public func sendError(_ errorMessage: String, context: ProtocolContext) async throws {
        let payload = errorMessage.data(using: .utf8) ?? Data()
        let message = BinaryMessage(opCode: .error, payload: payload)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    // MARK: - Helper Methods

    /// Parse payload as UTF-8 string
    public func parseString(from message: BinaryMessage) -> String? {
        return String(data: message.payload, encoding: .utf8)
    }

    /// Parse payload as JSON
    public func parseJSON<T: Decodable>(from message: BinaryMessage, as type: T.Type) throws -> T {
        return try JSONDecoder().decode(type, from: message.payload)
    }

    /// Create JSON payload
    public func createJSONPayload<T: Encodable>(_ value: T) throws -> Data {
        return try JSONEncoder().encode(value)
    }
}

// MARK: - Usage Example

/*
 Example usage:

 // Create connection
 let connection = TCPConnection(host: "example.com", port: 9000)
 try await connection.connect()

 // Create protocol handler
 let proto = CustomBinaryProtocol()
 let context = connection.createProtocolContext()

 // Set message handler
 await proto.setMessageHandler { message in
     print("Received: \(message.opCode)")

     if message.opCode == .request {
         // Handle request and return response
         let responsePayload = "Response data".data(using: .utf8)!
         return BinaryMessage(opCode: .response, payload: responsePayload)
     }

     return nil
 }

 // Connect (handshake)
 try await proto.onConnect(context: context)

 // Send request
 let requestData = "Request data".data(using: .utf8)!
 if let response = try await proto.request(requestData, context: context, waitForResponse: true) {
     print("Got response: \(proto.parseString(from: response) ?? "")")
 }

 // Send notification
 let notificationData = "Event occurred".data(using: .utf8)!
 try await proto.notify(notificationData, context: context)

 // Send ping
 try await proto.ping(context: context)

 // JSON example
 struct MyData: Codable {
     let id: Int
     let name: String
 }

 let myData = MyData(id: 123, name: "Test")
 let jsonPayload = try proto.createJSONPayload(myData)
 try await proto.request(jsonPayload, context: context)
 */
