//
//  ProtocolAdapter.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Protocol Adapter

/// 协议适配器 - 处理不同协议的编解码和消息解析
public protocol ProtocolAdapter: Sendable {
    /// 协议名称
    var name: String { get }

    /// 协议版本
    var version: String { get }

    /// 编码消息
    /// - Parameters:
    ///   - message: 要编码的消息
    ///   - context: 编码上下文
    /// - Returns: 编码后的数据
    /// - Throws: 编码失败时抛出错误
    func encode<T: Encodable>(_ message: T, context: EncodingContext) throws -> Data

    /// 解码消息
    /// - Parameters:
    ///   - data: 要解码的数据
    ///   - type: 目标类型
    ///   - context: 解码上下文
    /// - Returns: 解码后的消息
    /// - Throws: 解码失败时抛出错误
    func decode<T: Decodable>(_ data: Data, as type: T.Type, context: DecodingContext) throws -> T

    /// 处理接收到的原始数据
    /// - Parameter data: 原始数据
    /// - Returns: 解析出的协议事件数组
    /// - Throws: 解析失败时抛出错误
    func handleIncoming(_ data: Data) async throws -> [ProtocolEvent]

    /// 心跳包数据
    var heartbeatData: Data? { get }

    /// 是否支持压缩
    var supportsCompression: Bool { get }
}

// MARK: - Encoding Context

/// 编码上下文
public struct EncodingContext: Sendable {
    /// 连接标识符
    public let connectionId: String

    /// 消息 ID（用于请求-响应匹配）
    public let messageId: String?

    /// 事件名称
    public let eventName: String?

    /// 是否需要压缩
    public let shouldCompress: Bool

    /// 自定义元数据
    public let metadata: [String: String]

    public init(
        connectionId: String,
        messageId: String? = nil,
        eventName: String? = nil,
        shouldCompress: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.connectionId = connectionId
        self.messageId = messageId
        self.eventName = eventName
        self.shouldCompress = shouldCompress
        self.metadata = metadata
    }
}

// MARK: - Decoding Context

/// 解码上下文
public struct DecodingContext: Sendable {
    /// 连接标识符
    public let connectionId: String

    /// 原始数据大小
    public let dataSize: Int

    /// 是否已压缩
    public let isCompressed: Bool

    /// 时间戳
    public let timestamp: Date

    /// 自定义元数据
    public let metadata: [String: String]

    public init(
        connectionId: String,
        dataSize: Int,
        isCompressed: Bool = false,
        timestamp: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.connectionId = connectionId
        self.dataSize = dataSize
        self.isCompressed = isCompressed
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - Protocol Event

/// 协议事件
public enum ProtocolEvent: Sendable {
    /// 响应事件（用于请求-响应模式）
    case response(id: String, data: Data)

    /// 通知事件（服务器推送）
    case notification(event: String, data: Data)

    /// 控制事件（心跳、确认等）
    case control(type: ControlEventType, data: Data?)

    /// 错误事件
    case error(Error)

    /// 控制事件类型
    public enum ControlEventType: Sendable {
        case heartbeat
        case acknowledgement
        case ping
        case pong
        case custom(String)
    }
}

// MARK: - Frame Parser

/// 帧解析器协议
public protocol FrameParser: Sendable {
    /// 解析数据帧
    /// - Parameter buffer: 数据缓冲区
    /// - Returns: 解析出的帧和剩余数据
    /// - Throws: 解析失败时抛出错误
    func parseFrame(from buffer: Data) throws -> (frame: Frame?, remaining: Data)

    /// 构建数据帧
    /// - Parameter payload: 有效载荷
    /// - Returns: 完整的数据帧
    /// - Throws: 构建失败时抛出错误
    func buildFrame(payload: Data) throws -> Data
}

// MARK: - Frame

/// 数据帧
public struct Frame: Sendable {
    /// 帧类型
    public let type: FrameType

    /// 有效载荷
    public let payload: Data

    /// 帧标志
    public let flags: FrameFlags

    /// 帧元数据
    public let metadata: FrameMetadata?

    public init(
        type: FrameType,
        payload: Data,
        flags: FrameFlags = .init(),
        metadata: FrameMetadata? = nil
    ) {
        self.type = type
        self.payload = payload
        self.flags = flags
        self.metadata = metadata
    }

    /// 帧类型
    public enum FrameType: UInt8, Sendable {
        case data = 0x00
        case control = 0x01
        case heartbeat = 0x02
        case acknowledgement = 0x03
        case error = 0x04
    }

    /// 帧标志
    public struct FrameFlags: Sendable, OptionSet {
        public let rawValue: UInt8

        public init(rawValue: UInt8 = 0) {
            self.rawValue = rawValue
        }

        /// 是否压缩
        public static let compressed = FrameFlags(rawValue: 1 << 0)

        /// 是否加密
        public static let encrypted = FrameFlags(rawValue: 1 << 1)

        /// 是否是最后一个分片
        public static let finalFragment = FrameFlags(rawValue: 1 << 2)

        /// 是否需要确认
        public static let requiresAck = FrameFlags(rawValue: 1 << 3)
    }

    /// 帧元数据
    public struct FrameMetadata: Sendable {
        /// 序列号
        public let sequenceNumber: UInt32?

        /// 时间戳
        public let timestamp: Date?

        /// 优先级
        public let priority: UInt8?

        /// 自定义字段
        public let customFields: [String: String]

        public init(
            sequenceNumber: UInt32? = nil,
            timestamp: Date? = nil,
            priority: UInt8? = nil,
            customFields: [String: String] = [:]
        ) {
            self.sequenceNumber = sequenceNumber
            self.timestamp = timestamp
            self.priority = priority
            self.customFields = customFields
        }
    }
}

// MARK: - Default Implementations

public extension ProtocolAdapter {
    var version: String { "1.0" }
    var supportsCompression: Bool { false }
    var heartbeatData: Data? { nil }
}
