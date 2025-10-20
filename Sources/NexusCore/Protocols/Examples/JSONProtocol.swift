//
//  JSONProtocol.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - JSON Protocol

/// JSON 协议适配器 - 使用 JSON 编解码消息
public final class JSONProtocol: CustomProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    public let name = "JSON"
    public let version: String
    public let priority: Int
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public var capabilities: ProtocolCapabilities {
        [.compression, .heartbeat, .bidirectional]
    }
    
    public var metadata: ProtocolMetadata {
        ProtocolMetadata(
            description: "JSON-based protocol for human-readable data exchange",
            author: "NexusKit",
            tags: ["json", "text", "human-readable"],
            customProperties: [
                "content-type": "application/json",
                "encoding": "utf-8"
            ]
        )
    }
    
    public var supportsCompression: Bool { true }
    
    public var heartbeatData: Data? {
        let payload: [String: Any] = ["type": "heartbeat", "timestamp": Date().timeIntervalSince1970]
        return try? JSONSerialization.data(withJSONObject: payload)
    }
    
    // MARK: - Initialization
    
    public init(version: String = "1.0", priority: Int = 10) {
        self.version = version
        self.priority = priority
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - ProtocolAdapter
    
    public func encode<T: Encodable>(
        _ message: T,
        context: EncodingContext
    ) throws -> Data {
        try encoder.encode(message)
    }
    
    public func decode<T: Decodable>(
        _ data: Data,
        as type: T.Type,
        context: DecodingContext
    ) throws -> T {
        try decoder.decode(type, from: data)
    }
    
    public func handleIncoming(_ data: Data) async throws -> [ProtocolEvent] {
        // 尝试解析为 JSON 对象
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [.notification(event: "data", data: data)]
        }
        
        // 检查是否是响应
        if let responseId = json["responseId"] as? String,
           let responseData = try? JSONSerialization.data(withJSONObject: json["data"] ?? [:]) {
            return [.response(id: responseId, data: responseData)]
        }
        
        // 检查是否是事件
        if let eventName = json["event"] as? String,
           let eventData = try? JSONSerialization.data(withJSONObject: json["data"] ?? [:]) {
            return [.notification(event: eventName, data: eventData)]
        }
        
        // 检查是否是控制消息
        if let controlType = json["type"] as? String {
            switch controlType {
            case "heartbeat":
                return [.control(type: .heartbeat, data: nil)]
            case "ping":
                return [.control(type: .ping, data: nil)]
            case "pong":
                return [.control(type: .pong, data: nil)]
            default:
                return [.control(type: .custom(controlType), data: data)]
            }
        }
        
        // 默认作为通知事件
        return [.notification(event: "message", data: data)]
    }
    
    // MARK: - CustomProtocol
    
    public func negotiateVersion(with versions: [String]) async -> String? {
        // 支持的版本列表
        let supportedVersions = ["1.0", "2.0"]
        
        // 找到最高的公共版本
        let commonVersions = Set(versions).intersection(Set(supportedVersions))
        return commonVersions.sorted().last ?? version
    }
    
    public func configure(with options: [String: Any]) async throws {
        // 配置 JSON 编码器选项
        if let prettyPrint = options["prettyPrint"] as? Bool, prettyPrint {
            encoder.outputFormatting = .prettyPrinted
        }
        
        if let sortedKeys = options["sortedKeys"] as? Bool, sortedKeys {
            encoder.outputFormatting.insert(.sortedKeys)
        }
    }
}

// MARK: - JSON Message

/// JSON 消息结构
public struct JSONMessage: Codable, Sendable {
    /// 消息类型
    public let type: MessageType
    
    /// 消息 ID
    public let id: String?
    
    /// 事件名称
    public let event: String?
    
    /// 数据负载（编码为 String）
    public let data: String?
    
    /// 时间戳
    public let timestamp: Date
    
    /// 元数据
    public let metadata: [String: String]?
    
    public enum MessageType: String, Codable, Sendable {
        case request
        case response
        case event
        case control
    }
    
    public init(
        type: MessageType,
        id: String? = nil,
        event: String? = nil,
        data: String? = nil,
        timestamp: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.type = type
        self.id = id
        self.event = event
        self.data = data
        self.timestamp = timestamp
        self.metadata = metadata
    }
}
