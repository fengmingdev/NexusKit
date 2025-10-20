//
//  MessagePackProtocol.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - MessagePack Protocol

/// MessagePack 协议适配器 - 使用 MessagePack 二进制格式
public final class MessagePackProtocol: CustomProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    public let name = "MessagePack"
    public let version: String
    public let priority: Int
    
    public var capabilities: ProtocolCapabilities {
        [.compression, .heartbeat, .bidirectional, .fragmentation]
    }
    
    public var metadata: ProtocolMetadata {
        ProtocolMetadata(
            description: "Binary MessagePack protocol for efficient data exchange",
            author: "NexusKit",
            tags: ["messagepack", "binary", "efficient"],
            customProperties: [
                "content-type": "application/msgpack",
                "encoding": "binary"
            ]
        )
    }
    
    public var supportsCompression: Bool { true }
    
    public var heartbeatData: Data? {
        // 简单的 MessagePack 心跳包：{"type": "heartbeat"}
        // 格式: 0x81 (map with 1 entry) + 0xa4 (str with 4 bytes) + "type" + 0xa9 (str with 9 bytes) + "heartbeat"
        var data = Data()
        data.append(0x81) // map with 1 entry
        data.append(0xa4) // str with 4 bytes
        data.append(contentsOf: "type".utf8)
        data.append(0xa9) // str with 9 bytes
        data.append(contentsOf: "heartbeat".utf8)
        return data
    }
    
    // MARK: - Initialization
    
    public init(version: String = "1.0", priority: Int = 20) {
        self.version = version
        self.priority = priority
    }
    
    // MARK: - ProtocolAdapter
    
    public func encode<T: Encodable>(
        _ message: T,
        context: EncodingContext
    ) throws -> Data {
        // 简化实现：使用 JSON 作为中间格式
        // 实际生产环境应使用专门的 MessagePack 编码器
        let jsonData = try JSONEncoder().encode(message)
        
        // 添加 MessagePack 头部（简化版）
        var msgpackData = Data()
        msgpackData.append(0x01) // 版本标记
        msgpackData.append(contentsOf: jsonData)
        
        return msgpackData
    }
    
    public func decode<T: Decodable>(
        _ data: Data,
        as type: T.Type,
        context: DecodingContext
    ) throws -> T {
        // 简化实现：去除 MessagePack 头部后使用 JSON 解码
        guard data.count > 1 else {
            throw MessagePackError.invalidData
        }
        
        let jsonData = data.dropFirst() // 跳过版本标记
        return try JSONDecoder().decode(type, from: jsonData)
    }
    
    public func handleIncoming(_ data: Data) async throws -> [ProtocolEvent] {
        guard data.count > 0 else {
            throw MessagePackError.invalidData
        }
        
        // 检查第一个字节
        let firstByte = data[0]
        
        // 检查是否是心跳包（0x81开头的map）
        if firstByte == 0x81 && data.count >= 15 {
            // 检查是否包含完整的心跳数据结构
            // 0x81 (map with 1 entry) + 0xa4 (str 4) + "type" + 0xa9 (str 9) + "heartbeat"
            let expectedHeartbeat = heartbeatData!
            if data.prefix(expectedHeartbeat.count) == expectedHeartbeat {
                return [.control(type: .heartbeat, data: nil)]
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
        // MessagePack 特定配置（如果需要）
    }
}

// MARK: - MessagePack Error

/// MessagePack 错误
public enum MessagePackError: Error, Sendable {
    /// 无效数据
    case invalidData
    
    /// 不支持的类型
    case unsupportedType
    
    /// 编码失败
    case encodingFailed(String)
    
    /// 解码失败
    case decodingFailed(String)
}

extension MessagePackError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidData:
            return "Invalid MessagePack data"
        case .unsupportedType:
            return "Unsupported MessagePack type"
        case .encodingFailed(let reason):
            return "MessagePack encoding failed: \(reason)"
        case .decodingFailed(let reason):
            return "MessagePack decoding failed: \(reason)"
        }
    }
}

// MARK: - MessagePack Value

/// MessagePack 值类型（用于表示 MessagePack 数据结构）
public enum MessagePackValue: Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case float(Float)
    case double(Double)
    case string(String)
    case binary(Data)
    case array([MessagePackValue])
    case map([MessagePackValue: MessagePackValue])
    case ext(type: Int8, data: Data)
}

// MARK: - Hashable

extension MessagePackValue: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .null:
            hasher.combine(0)
        case .bool(let value):
            hasher.combine(value)
        case .int(let value):
            hasher.combine(value)
        case .uint(let value):
            hasher.combine(value)
        case .float(let value):
            hasher.combine(value)
        case .double(let value):
            hasher.combine(value)
        case .string(let value):
            hasher.combine(value)
        case .binary(let value):
            hasher.combine(value)
        case .array(let value):
            hasher.combine(value)
        case .map:
            hasher.combine(1) // 简化处理
        case .ext(let type, let data):
            hasher.combine(type)
            hasher.combine(data)
        }
    }
}
