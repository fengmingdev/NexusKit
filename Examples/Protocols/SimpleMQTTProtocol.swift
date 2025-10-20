//
//  SimpleMQTTProtocol.swift
//  NexusCore Examples
//
//  Created by NexusKit on 2025-01-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import Foundation
import NexusCore

/// Simplified MQTT-like protocol implementation
/// This is a basic example showing how to implement a custom protocol
public actor SimpleMQTTProtocol: ProtocolHandler {

    // MARK: - MQTT Message Types

    public enum MessageType: UInt8 {
        case connect = 0x10
        case connack = 0x20
        case publish = 0x30
        case puback = 0x40
        case subscribe = 0x80
        case suback = 0x90
        case unsubscribe = 0xA0
        case unsuback = 0xB0
        case pingreq = 0xC0
        case pingresp = 0xD0
        case disconnect = 0xE0
    }

    // MARK: - MQTT Message

    public struct MQTTMessage: ProtocolMessage {
        public let messageType: String
        public let payload: Data
        public let metadata: [String: String]

        public let mqttType: MessageType
        public let topic: String?
        public let qos: UInt8

        public init(type: MessageType, topic: String? = nil, payload: Data = Data(), qos: UInt8 = 0, metadata: [String: String] = [:]) {
            self.mqttType = type
            self.topic = topic
            self.payload = payload
            self.qos = qos
            self.messageType = String(describing: type)
            self.metadata = metadata
        }
    }

    // MARK: - Properties

    public let protocolName: String = "SimpleMQTT"
    public let protocolVersion: String = "1.0"

    private var messageHandler: ((MQTTMessage) async -> Void)?
    private var receiveBuffer: Data = Data()

    // MARK: - Initialization

    public init() {}

    /// Set message handler
    public func setMessageHandler(_ handler: @escaping (MQTTMessage) async -> Void) {
        self.messageHandler = handler
    }

    // MARK: - ProtocolHandler Implementation

    public func onConnect(context: ProtocolContext) async throws {
        // Send CONNECT packet
        let connectMessage = MQTTMessage(type: .connect)
        let data = try await encodeMessage(connectMessage, context: context)
        try await context.send(data)

        // Wait for CONNACK
        let response = try await context.receive(timeout: 5.0)
        let messages = try await onDataReceived(response, context: context)

        guard let connack = messages.first as? MQTTMessage,
              connack.mqttType == .connack else {
            throw ProtocolError.protocolViolation("Expected CONNACK")
        }
    }

    public func onDisconnect(context: ProtocolContext) async {
        // Send DISCONNECT packet
        let disconnectMessage = MQTTMessage(type: .disconnect)
        if let data = try? await encodeMessage(disconnectMessage, context: context) {
            try? await context.send(data)
        }
        receiveBuffer.removeAll()
    }

    public func onDataReceived(_ data: Data, context: ProtocolContext) async throws -> [ProtocolMessage] {
        receiveBuffer.append(data)

        var messages: [ProtocolMessage] = []

        while receiveBuffer.count >= 2 {
            // Read fixed header
            let typeAndFlags = receiveBuffer[0]
            let messageType = typeAndFlags & 0xF0

            // Read remaining length
            var remainingLength = 0
            var multiplier = 1
            var position = 1

            while position < receiveBuffer.count {
                let byte = receiveBuffer[position]
                remainingLength += Int(byte & 0x7F) * multiplier

                if (byte & 0x80) == 0 {
                    break
                }

                multiplier *= 128
                position += 1

                if multiplier > 128 * 128 * 128 {
                    throw ProtocolError.decodingError("Invalid remaining length")
                }
            }

            let headerLength = position + 1
            let totalLength = headerLength + remainingLength

            guard receiveBuffer.count >= totalLength else {
                // Need more data
                break
            }

            // Extract message data
            let messageData = receiveBuffer[headerLength..<totalLength]

            // Parse based on message type
            if let type = MessageType(rawValue: messageType) {
                let message = try parseMessage(type: type, data: Data(messageData))
                messages.append(message)
            }

            // Remove processed data
            receiveBuffer.removeFirst(totalLength)
        }

        return messages
    }

    public func encodeMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws -> Data {
        guard let mqttMessage = message as? MQTTMessage else {
            throw ProtocolError.encodingError("Not an MQTT message")
        }

        var data = Data()

        // Fixed header: type and flags
        let typeAndFlags = mqttMessage.mqttType.rawValue
        data.append(typeAndFlags)

        // Variable header + payload
        var variableHeader = Data()

        switch mqttMessage.mqttType {
        case .connect:
            // Protocol name
            let protocolName = "MQTT"
            variableHeader.append(contentsOf: [0x00, UInt8(protocolName.count)])
            variableHeader.append(contentsOf: protocolName.utf8)

            // Protocol level (4 for MQTT 3.1.1)
            variableHeader.append(0x04)

            // Connect flags
            variableHeader.append(0x02) // Clean session

            // Keep alive (60 seconds)
            variableHeader.append(contentsOf: [0x00, 0x3C])

        case .publish:
            // Topic
            if let topic = mqttMessage.topic {
                variableHeader.append(contentsOf: [0x00, UInt8(topic.count)])
                variableHeader.append(contentsOf: topic.utf8)
            }

            // Payload
            variableHeader.append(mqttMessage.payload)

        case .subscribe:
            // Packet identifier
            variableHeader.append(contentsOf: [0x00, 0x01])

            // Topic filter
            if let topic = mqttMessage.topic {
                variableHeader.append(contentsOf: [0x00, UInt8(topic.count)])
                variableHeader.append(contentsOf: topic.utf8)

                // QoS
                variableHeader.append(mqttMessage.qos)
            }

        case .pingreq, .pingresp, .disconnect:
            // No variable header or payload
            break

        default:
            break
        }

        // Remaining length
        let remainingLength = variableHeader.count
        var length = remainingLength
        repeat {
            var byte = UInt8(length % 128)
            length /= 128
            if length > 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while length > 0

        // Append variable header + payload
        data.append(variableHeader)

        return data
    }

    public func handleMessage(_ message: ProtocolMessage, context: ProtocolContext) async throws {
        guard let mqttMessage = message as? MQTTMessage else {
            throw ProtocolError.invalidMessage("Not an MQTT message")
        }

        // Call custom handler if set
        await messageHandler?(mqttMessage)

        // Handle ping automatically
        if mqttMessage.mqttType == .pingreq {
            let pongMessage = MQTTMessage(type: .pingresp)
            let data = try await encodeMessage(pongMessage, context: context)
            try await context.send(data)
        }
    }

    // MARK: - Public Methods

    /// Publish a message
    public func publish(topic: String, payload: Data, qos: UInt8 = 0, context: ProtocolContext) async throws {
        let message = MQTTMessage(type: .publish, topic: topic, payload: payload, qos: qos)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    /// Subscribe to a topic
    public func subscribe(topic: String, qos: UInt8 = 0, context: ProtocolContext) async throws {
        let message = MQTTMessage(type: .subscribe, topic: topic, qos: qos)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)

        // Wait for SUBACK
        let response = try await context.receive(timeout: 5.0)
        let messages = try await onDataReceived(response, context: context)

        guard let suback = messages.first as? MQTTMessage,
              suback.mqttType == .suback else {
            throw ProtocolError.protocolViolation("Expected SUBACK")
        }
    }

    /// Send ping
    public func ping(context: ProtocolContext) async throws {
        let message = MQTTMessage(type: .pingreq)
        let data = try await encodeMessage(message, context: context)
        try await context.send(data)
    }

    // MARK: - Private Methods

    private func parseMessage(type: MessageType, data: Data) throws -> MQTTMessage {
        switch type {
        case .connack:
            return MQTTMessage(type: .connack)

        case .publish:
            // Parse topic
            guard data.count >= 2 else {
                throw ProtocolError.decodingError("Invalid PUBLISH packet")
            }

            let topicLength = Int(data[0]) << 8 | Int(data[1])
            guard data.count >= 2 + topicLength else {
                throw ProtocolError.decodingError("Invalid topic length")
            }

            let topicData = data[2..<(2 + topicLength)]
            let topic = String(data: topicData, encoding: .utf8) ?? ""

            let payloadStart = 2 + topicLength
            let payload = payloadStart < data.count ? Data(data[payloadStart...]) : Data()

            return MQTTMessage(type: .publish, topic: topic, payload: payload)

        case .suback:
            return MQTTMessage(type: .suback)

        case .pingresp:
            return MQTTMessage(type: .pingresp)

        default:
            return MQTTMessage(type: type)
        }
    }
}

// MARK: - Usage Example

/*
 Example usage:

 // Create connection
 let connection = TCPConnection(host: "mqtt.example.com", port: 1883)
 try await connection.connect()

 // Create protocol handler
 let mqtt = SimpleMQTTProtocol()
 let context = connection.createProtocolContext()

 // Set message handler
 await mqtt.setMessageHandler { message in
     print("Received: \(message.messageType), topic: \(message.topic ?? "none")")
 }

 // Connect
 try await mqtt.onConnect(context: context)

 // Subscribe
 try await mqtt.subscribe(topic: "test/topic", context: context)

 // Publish
 let payload = "Hello MQTT".data(using: .utf8)!
 try await mqtt.publish(topic: "test/topic", payload: payload, context: context)

 // Ping
 try await mqtt.ping(context: context)

 // Disconnect
 await mqtt.onDisconnect(context: context)
 */
