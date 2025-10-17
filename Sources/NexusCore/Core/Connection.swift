//
//  Connection.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Connection Protocol

/// 连接协议 - 定义所有连接类型的通用接口
///
/// `Connection` 协议是 NexusKit 的核心抽象，定义了所有网络连接的基本操作。
/// 所有具体的连接实现（TCP、WebSocket、Socket.IO 等）都必须遵循此协议。
///
/// ## 设计理念
///
/// - **协议优先**: 通过协议定义接口，实现松耦合
/// - **异步优先**: 所有 I/O 操作都是异步的，使用 async/await
/// - **类型安全**: 支持泛型消息编解码，在编译时保证类型安全
/// - **并发安全**: 遵循 Sendable 协议，确保跨并发域安全
///
/// ## 使用示例
///
/// ```swift
/// // 创建连接
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .connect()
///
/// // 发送数据
/// try await connection.send("Hello".data(using: .utf8)!, timeout: 5)
///
/// // 接收数据（通过事件处理器）
/// await connection.on(.message) { data in
///     print("收到: \(String(data: data, encoding: .utf8) ?? "")")
/// }
///
/// // 断开连接
/// await connection.disconnect(reason: .clientInitiated)
/// ```
///
/// ## 状态管理
///
/// 连接具有以下状态：
/// - `.disconnected`: 已断开
/// - `.connecting`: 连接中
/// - `.connected`: 已连接
/// - `.reconnecting(attempt:)`: 重连中
/// - `.disconnecting`: 断开中
///
/// ## 错误处理
///
/// 所有可能失败的操作都会抛出 `NexusError`：
/// ```swift
/// do {
///     try await connection.connect()
/// } catch NexusError.connectionTimeout {
///     print("连接超时")
/// } catch {
///     print("其他错误: \(error)")
/// }
/// ```
public protocol Connection: AnyObject, Sendable {
    /// 连接唯一标识符
    ///
    /// 用于在连接池中标识此连接。如果未指定，系统会自动生成 UUID。
    var id: String { get }

    /// 当前连接状态
    ///
    /// 由于连接状态可能在不同的并发上下文中访问，此属性被标记为 async。
    ///
    /// - Returns: 当前的连接状态枚举值
    var state: ConnectionState { get async }

    /// 建立连接
    ///
    /// 启动连接过程。此方法会阻塞直到连接建立成功或失败。
    ///
    /// - Throws:
    ///   - `NexusError.connectionTimeout`: 连接超时
    ///   - `NexusError.connectionFailed`: 连接失败
    ///   - `NexusError.invalidStateTransition`: 当前状态不允许连接
    ///
    /// ## 示例
    /// ```swift
    /// do {
    ///     try await connection.connect()
    ///     print("连接成功")
    /// } catch NexusError.connectionTimeout {
    ///     print("连接超时，请检查网络")
    /// }
    /// ```
    func connect() async throws

    /// 断开连接
    ///
    /// 优雅地关闭连接。此方法总是成功，即使连接已经断开。
    ///
    /// - Parameter reason: 断开原因，用于日志和诊断
    ///
    /// ## 断开原因
    /// - `.clientInitiated`: 客户端主动断开
    /// - `.serverInitiated`: 服务器断开
    /// - `.timeout`: 超时断开
    /// - `.error(_)`: 发生错误而断开
    /// - `.networkUnavailable`: 网络不可用
    ///
    /// ## 示例
    /// ```swift
    /// await connection.disconnect(reason: .clientInitiated)
    /// ```
    func disconnect(reason: DisconnectReason) async

    /// 发送原始数据
    ///
    /// 发送二进制数据到连接的对端。数据会经过中间件管道处理。
    ///
    /// - Parameters:
    ///   - data: 要发送的原始数据
    ///   - timeout: 超时时间（秒）。传入 `nil` 使用全局配置的默认值
    ///
    /// - Throws:
    ///   - `NexusError.notConnected`: 连接未建立
    ///   - `NexusError.sendFailed`: 发送失败
    ///   - `NexusError.sendTimeout`: 发送超时
    ///
    /// ## 示例
    /// ```swift
    /// let data = "Hello, World!".data(using: .utf8)!
    /// try await connection.send(data, timeout: 5.0)
    /// ```
    func send(_ data: Data, timeout: TimeInterval?) async throws

    /// 发送类型化消息（需要协议适配器）
    ///
    /// 发送一个 Codable 消息。消息会通过协议适配器编码为二进制数据。
    ///
    /// - Parameters:
    ///   - message: 要发送的消息对象，必须遵循 `Encodable`
    ///   - timeout: 超时时间（秒）
    ///
    /// - Throws:
    ///   - `NexusError.noProtocolAdapter`: 未配置协议适配器
    ///   - `NexusError.encodingFailed`: 消息编码失败
    ///   - `NexusError.sendFailed`: 发送失败
    ///
    /// ## 示例
    /// ```swift
    /// struct LoginRequest: Codable {
    ///     let username: String
    ///     let password: String
    /// }
    ///
    /// let request = LoginRequest(username: "admin", password: "secret")
    /// try await connection.send(request, timeout: 5.0)
    /// ```
    ///
    /// ## 注意
    /// 此方法要求连接配置了 `ProtocolAdapter`：
    /// ```swift
    /// .protocol(BinaryProtocolAdapter())
    /// ```
    func send<T: Encodable>(_ message: T, timeout: TimeInterval?) async throws

    /// 接收原始数据
    ///
    /// 从连接接收原始二进制数据。
    ///
    /// - Parameter timeout: 超时时间（秒）
    /// - Returns: 接收到的数据
    ///
    /// - Throws:
    ///   - `NexusError.notConnected`: 连接未建立
    ///   - `NexusError.receiveTimeout`: 接收超时
    ///   - `NexusError.receiveFailed`: 接收失败
    ///
    /// ## 注意
    /// 对于流式协议（如 TCP），建议使用事件处理器而非此方法：
    /// ```swift
    /// await connection.on(.message) { data in
    ///     // 处理接收到的数据
    /// }
    /// ```
    func receive(timeout: TimeInterval?) async throws -> Data

    /// 接收类型化消息（需要协议适配器）
    ///
    /// 接收并解码一个类型化消息。
    ///
    /// - Parameters:
    ///   - type: 期望的消息类型，必须遵循 `Decodable`
    ///   - timeout: 超时时间（秒）
    ///
    /// - Returns: 解码后的消息对象
    ///
    /// - Throws:
    ///   - `NexusError.noProtocolAdapter`: 未配置协议适配器
    ///   - `NexusError.decodingFailed`: 消息解码失败
    ///   - `NexusError.receiveTimeout`: 接收超时
    ///
    /// ## 示例
    /// ```swift
    /// struct LoginResponse: Codable {
    ///     let success: Bool
    ///     let token: String?
    /// }
    ///
    /// let response = try await connection.receive(
    ///     as: LoginResponse.self,
    ///     timeout: 5.0
    /// )
    /// print("登录\(response.success ? "成功" : "失败")")
    /// ```
    func receive<T: Decodable>(as type: T.Type, timeout: TimeInterval?) async throws -> T

    /// 注册事件处理器
    ///
    /// 为特定事件类型注册处理闭包。当事件发生时，所有注册的处理器都会被调用。
    ///
    /// - Parameters:
    ///   - event: 事件类型（`.message`、`.notification`、`.control`）
    ///   - handler: 事件处理闭包，接收事件数据作为参数
    ///
    /// ## 事件类型
    ///
    /// - `.message`: 普通消息（请求-响应）
    /// - `.notification`: 服务器推送通知
    /// - `.control`: 控制消息（心跳等）
    ///
    /// ## 示例
    /// ```swift
    /// // 处理消息
    /// await connection.on(.message) { data in
    ///     print("收到消息: \(data.count) 字节")
    /// }
    ///
    /// // 处理通知
    /// await connection.on(.notification) { data in
    ///     let decoder = JSONDecoder()
    ///     if let notification = try? decoder.decode(Notification.self, from: data) {
    ///         print("收到通知: \(notification.title)")
    ///     }
    /// }
    /// ```
    ///
    /// ## 注意
    /// - 可以为同一事件注册多个处理器
    /// - 处理器按注册顺序依次执行
    /// - 处理器在内部队列中异步执行，不会阻塞连接
    func on(_ event: ConnectionEvent, handler: @escaping (Data) async -> Void)
}

// MARK: - Lifecycle Hooks

/// 生命周期钩子
///
/// 用于监听连接生命周期中的关键事件。所有钩子都是可选的。
///
/// ## 使用示例
///
/// ```swift
/// let hooks = LifecycleHooks(
///     onConnecting: {
///         print("正在连接...")
///     },
///     onConnected: {
///         print("连接成功！")
///     },
///     onDisconnected: { reason in
///         print("连接断开: \(reason)")
///     },
///     onReconnecting: { attempt in
///         print("第 \(attempt) 次重连尝试")
///     },
///     onError: { error in
///         print("错误: \(error)")
///     }
/// )
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .hooks(hooks)
///     .connect()
/// ```
public struct LifecycleHooks: Sendable {
    /// 开始连接时调用
    public var onConnecting: (@Sendable () async -> Void)?

    /// 连接成功时调用
    public var onConnected: (@Sendable () async -> Void)?

    /// 连接断开时调用，包含断开原因
    public var onDisconnected: (@Sendable (DisconnectReason) async -> Void)?

    /// 开始重连时调用，包含重连尝试次数
    public var onReconnecting: (@Sendable (Int) async -> Void)?

    /// 发生错误时调用
    public var onError: (@Sendable (Error) async -> Void)?

    /// 发送消息后调用
    public var onMessageSent: (@Sendable (Data) async -> Void)?

    /// 接收消息后调用
    public var onMessageReceived: (@Sendable (Data) async -> Void)?

    public init(
        onConnecting: (@Sendable () async -> Void)? = nil,
        onConnected: (@Sendable () async -> Void)? = nil,
        onDisconnected: (@Sendable (DisconnectReason) async -> Void)? = nil,
        onReconnecting: (@Sendable (Int) async -> Void)? = nil,
        onError: (@Sendable (Error) async -> Void)? = nil,
        onMessageSent: (@Sendable (Data) async -> Void)? = nil,
        onMessageReceived: (@Sendable (Data) async -> Void)? = nil
    ) {
        self.onConnecting = onConnecting
        self.onConnected = onConnected
        self.onDisconnected = onDisconnected
        self.onReconnecting = onReconnecting
        self.onError = onError
        self.onMessageSent = onMessageSent
        self.onMessageReceived = onMessageReceived
    }
}

// MARK: - Endpoint

/// 连接端点
///
/// 定义不同类型的网络端点。
///
/// ## 支持的端点类型
///
/// - **TCP**: 原始 TCP 连接
/// - **WebSocket**: WebSocket 协议
/// - **Socket.IO**: Socket.IO 协议
/// - **Custom**: 自定义协议
///
/// ## 示例
///
/// ```swift
/// // TCP 端点
/// let tcpEndpoint = Endpoint.tcp(host: "127.0.0.1", port: 8080)
///
/// // WebSocket 端点
/// let wsEndpoint = Endpoint.webSocket(url: URL(string: "wss://example.com/ws")!)
///
/// // Socket.IO 端点（带命名空间）
/// let ioEndpoint = Endpoint.socketIO(url: URL(string: "https://example.com")!, namespace: "/chat")
/// ```
public enum Endpoint: Sendable, Equatable {
    /// TCP 端点
    /// - Parameters:
    ///   - host: 主机地址（IP 或域名）
    ///   - port: 端口号
    case tcp(host: String, port: UInt16)

    /// WebSocket 端点
    /// - Parameter url: WebSocket URL（ws:// 或 wss://）
    case webSocket(url: URL)

    /// Socket.IO 端点
    /// - Parameters:
    ///   - url: 服务器 URL
    ///   - namespace: Socket.IO 命名空间（默认为 "/"）
    case socketIO(url: URL, namespace: String = "/")

    /// 自定义端点
    /// - Parameters:
    ///   - host: 主机地址
    ///   - port: 端口号
    ///   - scheme: 协议方案（如 "custom", "customs"）
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

    /// 是否使用安全连接（TLS/SSL）
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
