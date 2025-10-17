//
//  Connection.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Connection Protocol

/// 连接协议 - 所有连接类型的基础协议
public protocol Connection: AnyObject, Sendable {
    /// 连接的唯一标识符
    var id: String { get }

    /// 当前连接状态
    var state: ConnectionState { get async }

    /// 连接到服务器
    /// - Throws: 连接失败时抛出 NexusError
    func connect() async throws

    /// 断开连接
    /// - Parameter reason: 断开原因
    func disconnect(reason: DisconnectReason) async

    /// 发送数据
    /// - Parameters:
    ///   - data: 要发送的数据
    ///   - timeout: 发送超时时间
    /// - Throws: 发送失败时抛出 NexusError
    func send(_ data: Data, timeout: TimeInterval?) async throws

    /// 状态变化流
    var stateStream: AsyncStream<ConnectionState> { get }
}

// MARK: - TypedConnection Protocol

/// 类型化连接协议 - 支持 Codable 消息的连接
public protocol TypedConnection: Connection {
    /// 发送类型化消息
    /// - Parameters:
    ///   - message: 符合 Encodable 的消息
    ///   - options: 发送选项
    /// - Returns: 发送结果
    /// - Throws: 编码或发送失败时抛出错误
    @discardableResult
    func send<T: Encodable>(_ message: T, options: SendOptions) async throws -> SendResult

    /// 请求-响应模式
    /// - Parameters:
    ///   - request: 请求消息
    ///   - timeout: 超时时间
    /// - Returns: 响应消息
    /// - Throws: 超时或错误
    func request<Request: Encodable, Response: Decodable>(
        _ request: Request,
        timeout: TimeInterval
    ) async throws -> Response

    /// 单向发送事件
    /// - Parameters:
    ///   - event: 事件名称
    ///   - data: 事件数据
    /// - Throws: 发送失败
    func emit<T: Encodable>(_ event: String, data: T) async throws

    /// 订阅事件流
    /// - Parameter eventName: 事件名称
    /// - Returns: 事件数据流
    func events<T: Decodable>(for eventName: String) -> AsyncStream<T>
}

// MARK: - Send Options

/// 发送选项
public struct SendOptions: Sendable {
    /// 超时时间
    public var timeout: TimeInterval?

    /// 是否需要确认
    public var requiresAck: Bool

    /// 优先级
    public var priority: Priority

    /// 是否压缩
    public var compress: Bool

    /// 自定义元数据
    public var metadata: [String: String]

    public enum Priority: Sendable {
        case low
        case normal
        case high
    }

    public init(
        timeout: TimeInterval? = nil,
        requiresAck: Bool = false,
        priority: Priority = .normal,
        compress: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.timeout = timeout
        self.requiresAck = requiresAck
        self.priority = priority
        self.compress = compress
        self.metadata = metadata
    }

    /// 默认选项
    public static let `default` = SendOptions()
}

// MARK: - Send Result

/// 发送结果
public struct SendResult: Sendable {
    /// 是否成功
    public let success: Bool

    /// 发送的字节数
    public let bytesSent: Int

    /// 耗时（秒）
    public let duration: TimeInterval

    /// 错误信息
    public let error: Error?

    public init(
        success: Bool,
        bytesSent: Int = 0,
        duration: TimeInterval = 0,
        error: Error? = nil
    ) {
        self.success = success
        self.bytesSent = bytesSent
        self.duration = duration
        self.error = error
    }
}

// MARK: - Lifecycle Hooks

/// 生命周期钩子
public struct LifecycleHooks: Sendable {
    public var onConnecting: (@Sendable () async -> Void)?
    public var onConnected: (@Sendable () async -> Void)?
    public var onDisconnected: (@Sendable (DisconnectReason) async -> Void)?
    public var onReconnecting: (@Sendable (Int) async -> Void)?
    public var onError: (@Sendable (Error) async -> Void)?

    public init(
        onConnecting: (@Sendable () async -> Void)? = nil,
        onConnected: (@Sendable () async -> Void)? = nil,
        onDisconnected: (@Sendable (DisconnectReason) async -> Void)? = nil,
        onReconnecting: (@Sendable (Int) async -> Void)? = nil,
        onError: (@Sendable (Error) async -> Void)? = nil
    ) {
        self.onConnecting = onConnecting
        self.onConnected = onConnected
        self.onDisconnected = onDisconnected
        self.onReconnecting = onReconnecting
        self.onError = onError
    }
}

// MARK: - Endpoint

/// 连接端点
public enum Endpoint: Sendable, Equatable {
    /// TCP 端点
    case tcp(host: String, port: UInt16)

    /// WebSocket 端点
    case webSocket(url: URL)

    /// Socket.IO 端点
    case socketIO(url: URL, namespace: String = "/")

    /// 自定义端点
    case custom(host: String, port: UInt16, scheme: String)

    // MARK: - Computed Properties

    /// 主机地址
    public var host: String {
        switch self {
        case .tcp(let host, _), .custom(let host, _, _):
            return host
        case .webSocket(let url), .socketIO(let url, _):
            return url.host ?? ""
        }
    }

    /// 端口号
    public var port: UInt16? {
        switch self {
        case .tcp(_, let port), .custom(_, let port, _):
            return port
        case .webSocket(let url), .socketIO(let url, _):
            return url.port.map(UInt16.init) ?? defaultPort
        }
    }

    /// 默认端口
    private var defaultPort: UInt16? {
        switch self {
        case .webSocket(let url), .socketIO(let url, _):
            return url.scheme == "wss" ? 443 : 80
        default:
            return nil
        }
    }

    /// 是否使用安全连接
    public var isSecure: Bool {
        switch self {
        case .webSocket(let url), .socketIO(let url, _):
            return url.scheme == "wss" || url.scheme == "https"
        case .custom(_, _, let scheme):
            return scheme.hasSuffix("s")
        default:
            return false
        }
    }
}
