//
//  ProtocolHandler.swift
//  NexusCore
//
//  Created by NexusKit on 2025-01-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import Foundation

/// Protocol for custom network protocol handlers
/// Allows implementing custom application-layer protocols on top of TCP/TLS
public protocol ProtocolHandler: Sendable {
    /// Protocol name (e.g., "MQTT", "Redis", "Custom")
    var protocolName: String { get }

    /// Protocol version
    var protocolVersion: String { get }

    /// Called when connection is established
    /// - Parameter context: Protocol context
    func onConnect(context: ProtocolContext) async throws

    /// Called when connection is disconnected
    /// - Parameter context: Protocol context
    func onDisconnect(context: ProtocolContext) async

    /// Called when raw data is received
    /// - Parameters:
    ///   - data: Received data
    ///   - context: Protocol context
    /// - Returns: Processed messages (if any)
    func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage]

    /// Called to send a message
    /// - Parameters:
    ///   - message: Message to send
    ///   - context: Protocol context
    /// - Returns: Encoded data to send
    func encodeMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws -> Data

    /// Called to handle a received message
    /// - Parameters:
    ///   - message: Received message
    ///   - context: Protocol context
    func handleMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws
}

/// Protocol message abstraction
public protocol ProtocolMessage: Sendable {
    /// Message type identifier
    var messageType: String { get }

    /// Message payload
    var payload: Data { get }

    /// Message metadata
    var metadata: [String: String] { get }
}

/// Protocol context for maintaining protocol state
public protocol ProtocolContext: Sendable {
    /// Get connection state
    var isConnected: Bool { get async }

    /// Send raw data
    /// - Parameter data: Data to send
    func send(_ data: Data) async throws

    /// Receive raw data
    /// - Parameter timeout: Timeout in seconds
    /// - Returns: Received data
    func receive(timeout: TimeInterval?) async throws -> Data

    /// Store protocol-specific state
    /// - Parameters:
    ///   - value: Value to store
    ///   - key: Key to store under
    func setState<T: Sendable>(_ value: T, forKey key: String) async

    /// Retrieve protocol-specific state
    /// - Parameter key: Key to retrieve
    /// - Returns: Stored value
    func getState<T: Sendable>(forKey key: String) async -> T?

    /// Remove protocol-specific state
    /// - Parameter key: Key to remove
    func removeState(forKey key: String) async

    /// Close connection
    func close() async
}

// MARK: - Default Protocol Message

/// Default implementation of ProtocolMessage
public struct DefaultProtocolMessage: ProtocolMessage {
    public let messageType: String
    public let payload: Data
    public let metadata: [String: String]

    public init(type: String, payload: Data, metadata: [String: String] = [:]) {
        self.messageType = type
        self.payload = payload
        self.metadata = metadata
    }
}

// MARK: - Protocol Context Implementation

/// Default implementation of ProtocolContext
public actor DefaultProtocolContext: ProtocolContext {
    private weak var connection: (any Connection)?
    private var state: [String: Any] = [:]

    public init(connection: any Connection) {
        self.connection = connection
    }

    public var isConnected: Bool {
        get async {
            guard connection != nil else { return false }
            // Note: Connection protocol needs to be extended with isConnected property
            return true // Placeholder - actual implementation depends on Connection protocol
        }
    }

    public func send(_ data: Data) async throws {
        guard let connection = connection else {
            throw ProtocolError.connectionClosed
        }
        try await connection.send(data, timeout: nil)
    }

    public func receive(timeout: TimeInterval? = nil) async throws -> Data {
        guard connection != nil else {
            throw ProtocolError.connectionClosed
        }
        // Note: Connection protocol may need a receive method
        // For now, throw an error indicating this needs to be implemented
        throw ProtocolError.protocolViolation("Receive not implemented for this connection type")
    }

    public func setState<T: Sendable>(_ value: T, forKey key: String) async {
        state[key] = value
    }

    public func getState<T: Sendable>(forKey key: String) async -> T? {
        return state[key] as? T
    }

    public func removeState(forKey key: String) async {
        state.removeValue(forKey: key)
    }

    public func close() async {
        // Note: Disconnect implementation depends on Connection protocol
        // await connection?.disconnect()
    }
}

// MARK: - Protocol Errors

/// Errors that can occur during protocol operations
public enum ProtocolError: Error, CustomStringConvertible {
    case connectionClosed
    case invalidMessage(String)
    case unsupportedVersion(String)
    case authenticationFailed
    case timeout
    case encodingError(String)
    case decodingError(String)
    case protocolViolation(String)

    public var description: String {
        switch self {
        case .connectionClosed:
            return "Connection is closed"
        case .invalidMessage(let reason):
            return "Invalid message: \(reason)"
        case .unsupportedVersion(let version):
            return "Unsupported protocol version: \(version)"
        case .authenticationFailed:
            return "Authentication failed"
        case .timeout:
            return "Operation timed out"
        case .encodingError(let reason):
            return "Encoding error: \(reason)"
        case .decodingError(let reason):
            return "Decoding error: \(reason)"
        case .protocolViolation(let reason):
            return "Protocol violation: \(reason)"
        }
    }
}

