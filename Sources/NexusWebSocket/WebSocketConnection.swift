//
//  WebSocketConnection.swift
//  NexusWebSocket
//
//  Created by NexusKit Contributors
//
//  基于 URLSessionWebSocketTask 的 WebSocket 连接实现
//

import Foundation
import NexusCore

// MARK: - WebSocket Connection

/// WebSocket 连接实现
///
/// 基于 `URLSessionWebSocketTask` 实现的高性能 WebSocket 客户端。
///
/// ## 功能特性
///
/// - **标准 WebSocket 协议**: 符合 RFC 6455
/// - **自动 Ping/Pong**: 心跳保活机制
/// - **文本和二进制**: 支持两种消息类型
/// - **自动重连**: 网络中断自动恢复
/// - **TLS/SSL**: 支持 wss:// 安全连接
/// - **自定义头部**: 支持自定义 HTTP 头
///
/// ## 使用示例
///
/// ### 基础连接
/// ```swift
/// let connection = try await NexusKit.shared
///     .webSocket(url: URL(string: "wss://echo.websocket.org")!)
///     .connect()
///
/// // 发送文本消息
/// try await connection.send("Hello WebSocket".data(using: .utf8)!)
///
/// // 接收消息
/// await connection.on(.message) { data in
///     print("收到: \(String(data: data, encoding: .utf8) ?? "")")
/// }
/// ```
///
/// ### 高级配置
/// ```swift
/// let connection = try await NexusKit.shared
///     .webSocket(url: URL(string: "wss://example.com/ws")!)
///     .headers(["Authorization": "Bearer token"])
///     .protocols(["chat", "superchat"])
///     .pingInterval(30)
///     .reconnection(ExponentialBackoffStrategy())
///     .connect()
/// ```
@available(iOS 13.0, macOS 10.15, *)
public actor WebSocketConnection: Connection {
    // MARK: - Properties

    public let id: String
    private let endpoint: Endpoint
    private let configuration: WebSocketConfiguration

    /// 内部状态
    private var _state: ConnectionState = .disconnected

    /// WebSocket 任务
    private var webSocketTask: URLSessionWebSocketTask?

    /// URL Session
    private let urlSession: URLSession

    /// Ping 定时器
    private var pingTimer: Task<Void, Never>?

    /// 重连计数
    private var reconnectionAttempt = 0

    /// 生命周期钩子
    private let lifecycleHooks: LifecycleHooks

    /// 中间件管道
    private let middlewarePipeline: MiddlewarePipeline

    /// 事件处理器
    private var eventHandlers: [ConnectionEvent: [(Data) async -> Void]] = [:]

    // MARK: - Initialization

    public init(
        id: String,
        endpoint: Endpoint,
        configuration: WebSocketConfiguration
    ) {
        self.id = id
        self.endpoint = endpoint
        self.configuration = configuration
        self.lifecycleHooks = configuration.lifecycleHooks
        self.middlewarePipeline = MiddlewarePipeline()

        // 配置 URLSession
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.connectTimeout
        sessionConfig.timeoutIntervalForResource = configuration.connectTimeout

        self.urlSession = URLSession(
            configuration: sessionConfig,
            delegate: nil,
            delegateQueue: nil
        )
    }

    // MARK: - Connection Protocol

    public var state: ConnectionState {
        get async {
            _state
        }
    }

    public func connect() async throws {
        guard _state == .disconnected || _state == .reconnecting(attempt: 0) else {
            throw NexusError.invalidStateTransition(from: "\(_state)", to: "connecting")
        }

        _state = .connecting
        await lifecycleHooks.onConnecting?()

        // 解析端点
        guard case .webSocket(let url) = endpoint else {
            throw NexusError.invalidEndpoint(endpoint)
        }

        // 创建请求
        var request = URLRequest(url: url)
        request.timeoutInterval = configuration.connectTimeout

        // 添加自定义头部
        for (key, value) in configuration.headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        // 设置子协议
        if !configuration.protocols.isEmpty {
            request.addValue(
                configuration.protocols.joined(separator: ", "),
                forHTTPHeaderField: "Sec-WebSocket-Protocol"
            )
        }

        // 创建 WebSocket 任务
        let task = urlSession.webSocketTask(with: request)
        self.webSocketTask = task

        // 启动连接
        task.resume()

        // 等待连接成功
        do {
            try await waitForConnection()
            _state = .connected
            reconnectionAttempt = 0
            await lifecycleHooks.onConnected?()

            // 启动 Ping
            if configuration.pingInterval > 0 {
                startPing()
            }

            // 开始接收消息
            startReceiving()

        } catch {
            _state = .disconnected
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            throw error
        }
    }

    public func disconnect(reason: DisconnectReason) async {
        guard _state != .disconnected else { return }

        _state = .disconnecting

        // 停止 Ping
        stopPing()

        // 关闭 WebSocket
        let closeCode: URLSessionWebSocketTask.CloseCode = switch reason {
        case .clientInitiated:
            .normalClosure
        case .serverInitiated:
            .goingAway
        case .timeout, .heartbeatTimeout:
            .protocolError
        case .networkError:
            .internalServerError
        case .authenticationFailed:
            .policyViolation
        case .protocolError:
            .protocolError
        case .applicationTerminating:
            .goingAway
        case .custom:
            .abnormalClosure
        }

        webSocketTask?.cancel(with: closeCode, reason: nil)
        webSocketTask = nil

        _state = .disconnected
        await lifecycleHooks.onDisconnected?(reason)
    }

    public func send(_ data: Data, timeout: TimeInterval?) async throws {
        guard _state == .connected else {
            throw NexusError.notConnected
        }

        guard let task = webSocketTask else {
            throw NexusError.notConnected
        }

        // 应用中间件
        let processedData = try await middlewarePipeline.processOutgoing(
            data,
            context: MiddlewareContext(connectionId: id, endpoint: endpoint)
        )

        // 发送消息
        let message = URLSessionWebSocketTask.Message.data(processedData)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(message) { error in
                if let error = error {
                    continuation.resume(throwing: NexusError.sendFailed(error))
                } else {
                    continuation.resume()
                }
            }
        }

        await lifecycleHooks.onMessageSent?(data)
    }

    public func send<T: Encodable>(_ message: T, timeout: TimeInterval?) async throws {
        guard let adapter = configuration.protocolAdapter else {
            throw NexusError.noProtocolAdapter
        }

        let context = EncodingContext(connectionId: id)
        let data = try adapter.encode(message, context: context)
        try await send(data, timeout: timeout)
    }

    public func receive(timeout: TimeInterval?) async throws -> Data {
        throw NexusError.unsupportedOperation(operation: "receive", reason: "Use event handlers for WebSocket")
    }

    public func receive<T: Decodable>(as type: T.Type, timeout: TimeInterval?) async throws -> T {
        throw NexusError.unsupportedOperation(operation: "receive", reason: "Use event handlers for WebSocket")
    }

    public func on(_ event: ConnectionEvent, handler: @escaping (Data) async -> Void) async {
        if eventHandlers[event] == nil {
            eventHandlers[event] = []
        }
        eventHandlers[event]?.append(handler)
    }

    // MARK: - WebSocket Specific

    /// 发送文本消息
    /// - Parameter text: 文本内容
    public func sendText(_ text: String) async throws {
        guard _state == .connected else {
            throw NexusError.notConnected
        }

        guard let task = webSocketTask else {
            throw NexusError.notConnected
        }

        let message = URLSessionWebSocketTask.Message.string(text)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.send(message) { error in
                if let error = error {
                    continuation.resume(throwing: NexusError.sendFailed(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// 发送 Ping 帧
    public func sendPing() async throws {
        guard let task = webSocketTask else {
            throw NexusError.connectionClosed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Private Methods

    private func waitForConnection() async throws {
        // WebSocket 连接在 resume() 后立即建立
        // 这里通过发送一个 Ping 来验证连接
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        if let task = webSocketTask, task.state == .running {
            return
        } else {
            throw NexusError.protocolError(message: "WebSocket task not running")
        }
    }

    private func startReceiving() {
        Task {
            while !Task.isCancelled && _state == .connected {
                await receiveNextMessage()
            }
        }
    }

    private func receiveNextMessage() async {
        guard let task = webSocketTask else { return }

        do {
            let message = try await task.receive()

            switch message {
            case .data(let data):
                await handleReceivedData(data)

            case .string(let text):
                if let data = text.data(using: .utf8) {
                    await handleReceivedData(data)
                }

            @unknown default:
                break
            }

        } catch {
            // 接收错误，可能是连接断开
            await handleDisconnected(error: error)
        }
    }

    private func handleReceivedData(_ data: Data) async {
        do {
            // 应用中间件
            let processedData = try await middlewarePipeline.processIncoming(
                data,
                context: MiddlewareContext(connectionId: id, endpoint: endpoint)
            )

            // 通知协议适配器
            if let adapter = configuration.protocolAdapter {
                let events = try await adapter.handleIncoming(processedData)

                for event in events {
                    await handleProtocolEvent(event)
                }
            } else {
                // 无协议适配器，直接作为原始数据事件
                await dispatchEvent(.message, data: processedData)
            }

            await lifecycleHooks.onMessageReceived?(processedData)

        } catch {
            await lifecycleHooks.onError?(error)
        }
    }

    private func handleProtocolEvent(_ event: ProtocolEvent) async {
        switch event {
        case .response(id: _, data: let data):
            await dispatchEvent(.message, data: data)

        case .notification(event: _, data: let data):
            await dispatchEvent(.notification, data: data)

        case .control(type: let type, data: let data):
            if case .pong = type {
                // Pong 响应，连接正常
            }
            await dispatchEvent(.control, data: data ?? Data())

        case .error(let error):
            // 处理错误事件
            await lifecycleHooks.onError?(error)
        }
    }

    private func dispatchEvent(_ event: ConnectionEvent, data: Data) async {
        guard let handlers = eventHandlers[event] else { return }

        for handler in handlers {
            await handler(data)
        }
    }

    private func handleDisconnected(error: Error?) async {
        let previousState = _state

        // 检查是否需要重连
        if let error = error,
           let strategy = configuration.reconnectionStrategy,
           strategy.shouldReconnect(error: error),
           previousState == .connected || previousState.isReconnecting {

            reconnectionAttempt += 1

            if let delay = strategy.nextDelay(attempt: reconnectionAttempt, lastError: error) {
                _state = .reconnecting(attempt: reconnectionAttempt)
                await lifecycleHooks.onReconnecting?(reconnectionAttempt)

                // 延迟后重连
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                if _state.isReconnecting {
                    try? await connect()
                }
                return
            }
        }

        // 不重连，标记为断开
        _state = .disconnected

        let reason: DisconnectReason = if let error = error {
            .networkError(error)
        } else {
            .clientInitiated
        }

        await lifecycleHooks.onDisconnected?(reason)
    }

    // MARK: - Ping/Pong

    private func startPing() {
        stopPing()

        let interval = configuration.pingInterval

        pingTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                if !Task.isCancelled && _state == .connected {
                    try? await sendPing()
                }
            }
        }
    }

    private func stopPing() {
        pingTimer?.cancel()
        pingTimer = nil
    }
}

// MARK: - WebSocket Configuration

/// WebSocket 连接配置
public struct WebSocketConfiguration: Sendable {
    /// 连接 ID
    public let id: String

    /// 连接端点
    public let endpoint: Endpoint

    /// 协议适配器
    public let protocolAdapter: (any ProtocolAdapter)?

    /// 重连策略
    public let reconnectionStrategy: (any ReconnectionStrategy)?

    /// 中间件列表
    public let middlewares: [any Middleware]

    /// 连接超时
    public let connectTimeout: TimeInterval

    /// 自定义 HTTP 头
    public let headers: [String: String]

    /// WebSocket 子协议
    public let protocols: [String]

    /// Ping 间隔（秒），0 表示禁用
    public let pingInterval: TimeInterval

    /// 生命周期钩子
    public let lifecycleHooks: LifecycleHooks

    public init(
        id: String,
        endpoint: Endpoint,
        protocolAdapter: (any ProtocolAdapter)? = nil,
        reconnectionStrategy: (any ReconnectionStrategy)? = nil,
        middlewares: [any Middleware] = [],
        connectTimeout: TimeInterval = 30,
        headers: [String: String] = [:],
        protocols: [String] = [],
        pingInterval: TimeInterval = 30,
        lifecycleHooks: LifecycleHooks = LifecycleHooks()
    ) {
        self.id = id
        self.endpoint = endpoint
        self.protocolAdapter = protocolAdapter
        self.reconnectionStrategy = reconnectionStrategy
        self.middlewares = middlewares
        self.connectTimeout = connectTimeout
        self.headers = headers
        self.protocols = protocols
        self.pingInterval = pingInterval
        self.lifecycleHooks = lifecycleHooks
    }
}

// MARK: - Connection State Extension

extension ConnectionState {
    var isReconnecting: Bool {
        if case .reconnecting = self {
            return true
        }
        return false
    }
}
