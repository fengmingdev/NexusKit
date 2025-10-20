//
//  EngineIOPacket.swift
//  NexusIO
//
//  Created by NexusKit Contributors
//

import Foundation

/// Engine.IO 包类型
public enum EngineIOPacketType: Int, Sendable {
    case open = 0       // 打开连接
    case close = 1      // 关闭连接
    case ping = 2       // 心跳请求
    case pong = 3       // 心跳响应
    case message = 4    // 消息
    case upgrade = 5    // 升级传输
    case noop = 6       // 空操作
}

/// Engine.IO 握手数据
public struct EngineIOHandshake: Codable, Sendable {
    /// 会话ID
    public let sid: String
    
    /// 可用的传输升级选项
    public let upgrades: [String]
    
    /// 心跳间隔（毫秒）
    public let pingInterval: Int
    
    /// 心跳超时（毫秒）
    public let pingTimeout: Int
    
    /// 最大HTTP缓冲区大小
    public let maxPayload: Int?
}

/// Engine.IO 协议包
public struct EngineIOPacket: Sendable {
    /// 包类型
    public let type: EngineIOPacketType
    
    /// 数据负载
    public let data: String?
    
    /// 初始化Engine.IO包
    public init(type: EngineIOPacketType, data: String? = nil) {
        self.type = type
        self.data = data
    }
    
    /// 创建PING包
    public static func ping() -> EngineIOPacket {
        return EngineIOPacket(type: .ping)
    }
    
    /// 创建PONG包
    public static func pong() -> EngineIOPacket {
        return EngineIOPacket(type: .pong)
    }
    
    /// 创建MESSAGE包
    public static func message(_ data: String) -> EngineIOPacket {
        return EngineIOPacket(type: .message, data: data)
    }
    
    /// 创建CLOSE包
    public static func close() -> EngineIOPacket {
        return EngineIOPacket(type: .close)
    }
    
    /// 编码为字符串
    public func encode() -> String {
        var encoded = "\(type.rawValue)"
        if let data = data {
            encoded += data
        }
        return encoded
    }
    
    /// 从字符串解码
    public static func decode(_ string: String) throws -> EngineIOPacket {
        guard !string.isEmpty,
              let firstChar = string.first,
              let typeValue = Int(String(firstChar)),
              let type = EngineIOPacketType(rawValue: typeValue) else {
            throw EngineIOError.invalidPacketFormat
        }
        
        let data = string.count > 1 ? String(string.dropFirst()) : nil
        return EngineIOPacket(type: type, data: data)
    }
}

/// Engine.IO 错误
public enum EngineIOError: Error, Sendable {
    case invalidPacketFormat
    case invalidHandshake
    case connectionClosed
    case pingTimeout
    case transportError(String)
}

// MARK: - CustomStringConvertible

extension EngineIOPacket: CustomStringConvertible {
    public var description: String {
        if let data = data {
            return "EngineIO[\(type)] \(data)"
        } else {
            return "EngineIO[\(type)]"
        }
    }
}

extension EngineIOPacketType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .open: return "OPEN"
        case .close: return "CLOSE"
        case .ping: return "PING"
        case .pong: return "PONG"
        case .message: return "MESSAGE"
        case .upgrade: return "UPGRADE"
        case .noop: return "NOOP"
        }
    }
}
