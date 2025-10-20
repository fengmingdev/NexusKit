//
//  SimpleRedisProtocol.swift
//  NexusCore Examples
//
//  Created by NexusKit on 2025-01-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import Foundation
import NexusCore

/// Simplified Redis RESP (Redis Serialization Protocol) implementation
/// This demonstrates a text-based protocol with line-delimited messages
public actor SimpleRedisProtocol: ProtocolHandler {

    // MARK: - RESP Types

    public enum RESPType: String {
        case simpleString = "+"  // +OK\r\n
        case error = "-"         // -Error message\r\n
        case integer = ":"       // :1000\r\n
        case bulkString = "$"    // $6\r\nfoobar\r\n
        case array = "*"         // *2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n
    }

    // MARK: - RESP Message

    public struct RedisMessage: ProtocolMessage {
        public let messageType: String
        public let payload: Data
        public let metadata: [String: String]

        public let respType: RESPType
        public let value: RESPValue

        public init(value: RESPValue, metadata: [String: String] = [:]) {
            self.value = value
            self.respType = value.type
            self.messageType = String(describing: value.type)
            self.payload = Data()
            self.metadata = metadata
        }
    }

    // MARK: - RESP Value

    public enum RESPValue {
        case simpleString(String)
        case error(String)
        case integer(Int)
        case bulkString(Data?)
        case array([RESPValue])

        var type: RESPType {
            switch self {
            case .simpleString: return .simpleString
            case .error: return .error
            case .integer: return .integer
            case .bulkString: return .bulkString
            case .array: return .array
            }
        }
    }

    // MARK: - Properties

    public let protocolName: String = "SimpleRedis"
    public let protocolVersion: String = "RESP2"

    private var receiveBuffer: Data = Data()
    private var responseHandler: ((RedisMessage) async -> Void)?

    // MARK: - Initialization

    public init() {}

    /// Set response handler
    public func setResponseHandler(_ handler: @escaping (RedisMessage) async -> Void) {
        self.responseHandler = handler
    }

    // MARK: - ProtocolHandler Implementation

    public func onConnect(context: ProtocolContext) async throws {
        // Redis doesn't require explicit connection handshake
        // Optionally send PING to verify connection
        try await ping(context: context)
    }

    public func onDisconnect(context: ProtocolContext) async {
        receiveBuffer.removeAll()
    }

    public func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage] {
        receiveBuffer.append(data)

        var messages: [ProtocolMessage] = []

        while !receiveBuffer.isEmpty {
            guard let (value, bytesConsumed) = try? parseRESP(from: receiveBuffer) else {
                // Need more data
                break
            }

            let message = RedisMessage(value: value)
            messages.append(message)

            receiveBuffer.removeFirst(bytesConsumed)
        }

        return messages
    }

    public func encodeMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws -> Data {
        guard let redisMessage = message as? RedisMessage else {
            throw ProtocolError.encodingError("Not a Redis message")
        }

        return encodeRESP(redisMessage.value)
    }

    public func handleMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws {
        guard let redisMessage = message as? RedisMessage else {
            throw ProtocolError.invalidMessage("Not a Redis message")
        }

        await responseHandler?(redisMessage)
    }

    // MARK: - Public Commands

    /// Send PING command
    public func ping(context: ProtocolContext) async throws {
        let command = RESPValue.array([
            .bulkString("PING".data(using: .utf8))
        ])
        let message = RedisMessage(value: command)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    /// Send GET command
    public func get(key: String, context: ProtocolContext) async throws -> String? {
        let command = RESPValue.array([
            .bulkString("GET".data(using: .utf8)),
            .bulkString(key.data(using: .utf8))
        ])
        let message = RedisMessage(value: command)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)

        // Wait for response
        let response = try await context.receive(timeout: 5.0)
        let messages = try await onDataReceived(response, context: context)

        guard let redisMessage = messages.first as? RedisMessage else {
            return nil
        }

        if case .bulkString(let data) = redisMessage.value,
           let data = data {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    /// Send SET command
    public func set(key: String, value: String, context: ProtocolContext) async throws {
        let command = RESPValue.array([
            .bulkString("SET".data(using: .utf8)),
            .bulkString(key.data(using: .utf8)),
            .bulkString(value.data(using: .utf8))
        ])
        let message = RedisMessage(value: command)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    /// Send DEL command
    public func del(keys: [String], context: ProtocolContext) async throws {
        var command: [RESPValue] = [.bulkString("DEL".data(using: .utf8))]
        command.append(contentsOf: keys.map { .bulkString($0.data(using: .utf8)) })

        let message = RedisMessage(value: .array(command))
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    /// Send custom command
    public func command(_ parts: [String], context: ProtocolContext) async throws {
        let command = RESPValue.array(parts.map { .bulkString($0.data(using: .utf8)) })
        let message = RedisMessage(value: command)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    // MARK: - RESP Encoding

    private func encodeRESP(_ value: RESPValue) -> Data {
        var data = Data()

        switch value {
        case .simpleString(let string):
            data.append("+".data(using: .utf8)!)
            data.append(string.data(using: .utf8)!)
            data.append("\r\n".data(using: .utf8)!)

        case .error(let error):
            data.append("-".data(using: .utf8)!)
            data.append(error.data(using: .utf8)!)
            data.append("\r\n".data(using: .utf8)!)

        case .integer(let int):
            data.append(":".data(using: .utf8)!)
            data.append("\(int)".data(using: .utf8)!)
            data.append("\r\n".data(using: .utf8)!)

        case .bulkString(let bulkData):
            data.append("$".data(using: .utf8)!)
            if let bulkData = bulkData {
                data.append("\(bulkData.count)".data(using: .utf8)!)
                data.append("\r\n".data(using: .utf8)!)
                data.append(bulkData)
            } else {
                data.append("-1".data(using: .utf8)!)
            }
            data.append("\r\n".data(using: .utf8)!)

        case .array(let elements):
            data.append("*".data(using: .utf8)!)
            data.append("\(elements.count)".data(using: .utf8)!)
            data.append("\r\n".data(using: .utf8)!)
            for element in elements {
                data.append(encodeRESP(element))
            }
        }

        return data
    }

    // MARK: - RESP Parsing

    private func parseRESP(from data: Data) throws -> (RESPValue, Int)? {
        guard !data.isEmpty else { return nil }

        let typeChar = String(data: data[0...0], encoding: .utf8) ?? ""

        guard let type = RESPType(rawValue: typeChar) else {
            throw ProtocolError.decodingError("Invalid RESP type: \(typeChar)")
        }

        switch type {
        case .simpleString, .error, .integer:
            return try parseSimpleLine(type: type, from: data)

        case .bulkString:
            return try parseBulkString(from: data)

        case .array:
            return try parseArray(from: data)
        }
    }

    private func parseSimpleLine(type: RESPType, from data: Data) throws -> (RESPValue, Int)? {
        guard let crlfRange = data.range(of: "\r\n".data(using: .utf8)!) else {
            return nil // Need more data
        }

        let lineData = data[1..<crlfRange.lowerBound]
        let line = String(data: lineData, encoding: .utf8) ?? ""

        let value: RESPValue
        switch type {
        case .simpleString:
            value = .simpleString(line)
        case .error:
            value = .error(line)
        case .integer:
            value = .integer(Int(line) ?? 0)
        default:
            throw ProtocolError.decodingError("Unexpected type")
        }

        return (value, crlfRange.upperBound)
    }

    private func parseBulkString(from data: Data) throws -> (RESPValue, Int)? {
        guard let crlfRange = data.range(of: "\r\n".data(using: .utf8)!) else {
            return nil
        }

        let lengthData = data[1..<crlfRange.lowerBound]
        let lengthStr = String(data: lengthData, encoding: .utf8) ?? ""
        guard let length = Int(lengthStr) else {
            throw ProtocolError.decodingError("Invalid bulk string length")
        }

        if length == -1 {
            return (.bulkString(nil), crlfRange.upperBound)
        }

        let contentStart = crlfRange.upperBound
        let contentEnd = contentStart + length

        guard data.count >= contentEnd + 2 else {
            return nil // Need more data
        }

        let content = data[contentStart..<contentEnd]
        return (.bulkString(Data(content)), contentEnd + 2) // +2 for \r\n
    }

    private func parseArray(from data: Data) throws -> (RESPValue, Int)? {
        guard let crlfRange = data.range(of: "\r\n".data(using: .utf8)!) else {
            return nil
        }

        let countData = data[1..<crlfRange.lowerBound]
        let countStr = String(data: countData, encoding: .utf8) ?? ""
        guard let count = Int(countStr) else {
            throw ProtocolError.decodingError("Invalid array count")
        }

        var elements: [RESPValue] = []
        var position = crlfRange.upperBound

        for _ in 0..<count {
            guard let (element, bytesConsumed) = try parseRESP(from: data[position...]) else {
                return nil // Need more data
            }
            elements.append(element)
            position += bytesConsumed
        }

        return (.array(elements), position)
    }
}

// MARK: - Usage Example

/*
 Example usage:

 // Create connection
 let connection = TCPConnection(host: "localhost", port: 6379)
 try await connection.connect()

 // Create protocol handler
 let redis = SimpleRedisProtocol()
 let context = connection.createProtocolContext()

 // Set response handler
 await redis.setResponseHandler { message in
     print("Response: \(message.value)")
 }

 // Connect (ping)
 try await redis.onConnect(context: context)

 // SET command
 try await redis.set(key: "mykey", value: "myvalue", context: context)

 // GET command
 if let value = try await redis.get(key: "mykey", context: context) {
     print("Value: \(value)")
 }

 // Custom command
 try await redis.command(["INCR", "counter"], context: context)

 // DEL command
 try await redis.del(keys: ["mykey"], context: context)
 */
