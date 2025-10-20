//
//  SocketIOPacket.swift
//  NexusIO
//
//  Created by NexusKit Contributors
//

import Foundation

/// Socket.IO 协议包类型
public enum SocketIOPacketType: Int, Sendable {
    case connect = 0        // 连接
    case disconnect = 1     // 断开
    case event = 2          // 事件
    case ack = 3            // 确认
    case connectError = 4   // 连接错误
    case binaryEvent = 5    // 二进制事件
    case binaryAck = 6      // 二进制确认
}

/// Socket.IO 协议包
public struct SocketIOPacket: Sendable {
    /// 包类型
    public let type: SocketIOPacketType
    
    /// 命名空间（默认为 "/"）
    public let namespace: String
    
    /// 数据负载
    public let data: [Any]?
    
    /// 确认ID（用于request-response模式）
    public let id: Int?
    
    /// 二进制附件数量
    public let attachments: Int?
    
    /// 初始化Socket.IO包
    public init(
        type: SocketIOPacketType,
        namespace: String = "/",
        data: [Any]? = nil,
        id: Int? = nil,
        attachments: Int? = nil
    ) {
        self.type = type
        self.namespace = namespace
        self.data = data
        self.id = id
        self.attachments = attachments
    }
    
    /// 创建连接包
    public static func connect(namespace: String = "/", auth: [String: Any]? = nil) -> SocketIOPacket {
        var data: [Any]?
        if let auth = auth {
            data = [auth]
        }
        return SocketIOPacket(type: .connect, namespace: namespace, data: data)
    }
    
    /// 创建断开包
    public static func disconnect(namespace: String = "/") -> SocketIOPacket {
        return SocketIOPacket(type: .disconnect, namespace: namespace)
    }
    
    /// 创建事件包
    public static func event(
        _ eventName: String,
        items: [Any] = [],
        namespace: String = "/",
        id: Int? = nil
    ) -> SocketIOPacket {
        var data: [Any] = [eventName]
        data.append(contentsOf: items)
        return SocketIOPacket(type: .event, namespace: namespace, data: data, id: id)
    }
    
    /// 创建确认包
    public static func ack(data: [Any], id: Int, namespace: String = "/") -> SocketIOPacket {
        return SocketIOPacket(type: .ack, namespace: namespace, data: data, id: id)
    }
    
    /// 创建连接错误包
    public static func connectError(message: String, namespace: String = "/") -> SocketIOPacket {
        return SocketIOPacket(type: .connectError, namespace: namespace, data: [["message": message]])
    }
}

// MARK: - CustomStringConvertible

extension SocketIOPacket: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        parts.append("type=\(type)")
        if namespace != "/" {
            parts.append("namespace=\(namespace)")
        }
        if let id = id {
            parts.append("id=\(id)")
        }
        if let attachments = attachments {
            parts.append("attachments=\(attachments)")
        }
        if let data = data {
            parts.append("data=\(data)")
        }
        return "SocketIOPacket(\(parts.joined(separator: ", ")))"
    }
}

extension SocketIOPacketType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connect: return "CONNECT"
        case .disconnect: return "DISCONNECT"
        case .event: return "EVENT"
        case .ack: return "ACK"
        case .connectError: return "CONNECT_ERROR"
        case .binaryEvent: return "BINARY_EVENT"
        case .binaryAck: return "BINARY_ACK"
        }
    }
}
