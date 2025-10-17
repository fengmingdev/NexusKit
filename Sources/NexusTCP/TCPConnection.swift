//
//  TCPConnection.swift
//  NexusTCP
//
//  Created by NexusKit Contributors
//
//  基于 Network framework 的高性能 TCP 连接实现
//

import Foundation
import Network
import NexusCore

// MARK: - TCP Connection

/// TCP 连接实现（基于 Network framework）
public actor TCPConnection: Connection {
    // MARK: - Properties

    public let id: String
    private let endpoint: Endpoint
    private let configuration: ConnectionConfiguration

    /// 内部状态
    private var _state: ConnectionState = .disconnected

    /// 底层 TCP 连接
    private var nwConnection: NWConnection?

    /// 消息接收缓冲区
    private var receiveBuffer = Data()

    /// 心跳定时器
    private var heartbeatTimer: DispatchSourceTimer?

    /// 最后心跳响应时间（毫秒）
    private var lastHeartbeatTime: UInt64 = 0

    /// 重连计数
    private var reconnectionAttempt = 0

    /// 生命周期钩子
    private let lifecycleHooks: LifecycleHooks

    /// 中间件管道
    private let middlewarePipeline: MiddlewarePipeline

    /// 事件处理器
    private var eventHandlers: [ConnectionEvent: [(Data) async -> Void]] = [:]

    /// 连接队列
    private let connectionQueue = DispatchQueue(
        label: "com.nexuskit.tcp.connection",
        qos: .userInitiated
    )

    /// 是否正在接收数据
    private var isReceiving = false

    // MARK: - Initialization

    public init(
        id: String,
        endpoint: Endpoint,
        configuration: ConnectionConfiguration
    ) {
        self.id = id
        self.endpoint = endpoint
        self.configuration = configuration
        self.lifecycleHooks = configuration.lifecycleHooks
        self.middlewarePipeline = MiddlewarePipeline(middlewares: configuration.middlewares)
    }

    // MARK: - Connection Protocol

    public var state: ConnectionState {
        _state
    }

    public func connect() async throws {
        guard _state == .disconnected || _state == .reconnecting(attempt: 0) else {
            throw NexusError.invalidStateTransition(from: _state, to: .connecting)
        }

        _state = .connecting
        await lifecycleHooks.onConnecting?()

        // 解析端点
        guard case .tcp(let host, let port) = endpoint else {
            throw NexusError.invalidEndpoint(endpoint)
        }

        // 创建 NWEndpoint
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!

        // 配置 TCP 参数
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 60 // 60 秒
        tcpOptions.keepaliveInterval = 30 // 30 秒
        tcpOptions.keepaliveCount = 3 // 3 次
        tcpOptions.noDelay = true // 禁用 Nagle 算法，减少延迟

        // 配置 TLS（如果需要）
        let parameters: NWParameters
        if let tlsConfig = configuration.tlsConfig, tlsConfig.enabled {
            let tlsOptions = NWProtocolTLS.Options()

            // 配置证书验证
            if !tlsConfig.validateHostname {
                sec_protocol_options_set_peer_authentication_required(
                    tlsOptions.securityProtocolOptions,
                    false
                )
            }

            parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcpOptions)
        }

        // 配置代理（如果需要）
        if let proxyConfig = configuration.proxyConfig {
            parameters.setProxy(from: proxyConfig)
        }

        // 创建连接
        let connection = NWConnection(
            host: nwHost,
            port: nwPort,
            using: parameters
        )

        self.nwConnection = connection

        // 设置状态更新处理器
        connection.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleStateUpdate(state)
            }
        }

        // 启动连接
        connection.start(queue: connectionQueue)

        // 等待连接成功（使用超时）
        try await withTimeout(configuration.connectTimeout) {
            while self._state == .connecting {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if self._state != .connected {
                throw NexusError.connectionTimeout
            }
        }
    }

    public func disconnect(reason: DisconnectReason) async {
        guard _state != .disconnected else { return }

        _state = .disconnecting
        await lifecycleHooks.onDisconnecting?()

        // 停止心跳
        stopHeartbeat()

        // 断开连接
        nwConnection?.cancel()
        nwConnection = nil

        _state = .disconnected
        await lifecycleHooks.onDisconnected?(reason)

        // 清空缓冲区
        receiveBuffer.removeAll()
        isReceiving = false
    }

    public func send(_ data: Data, timeout: TimeInterval?) async throws {
        guard _state == .connected else {
            throw NexusError.notConnected
        }

        guard let connection = nwConnection else {
            throw NexusError.notConnected
        }

        // 应用中间件
        let processedData = try await middlewarePipeline.processOutgoing(
            data,
            context: MiddlewareContext(connectionId: id, endpoint: endpoint)
        )

        // 发送数据
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: processedData,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: NexusError.sendFailed(reason: error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            )
        }

        await lifecycleHooks.onMessageSent?(data)
    }

    public func send<T: Encodable>(_ message: T, timeout: TimeInterval?) async throws {
        guard let adapter = configuration.protocolAdapter else {
            throw NexusError.noProtocolAdapter
        }

        let context = EncodingContext(connectionId: id, endpoint: endpoint)
        let data = try adapter.encode(message, context: context)
        try await send(data, timeout: timeout)
    }

    public func receive(timeout: TimeInterval?) async throws -> Data {
        // TCP 是流式协议，接收通过事件处理器异步推送
        throw NexusError.unsupportedOperation(operation: "receive", reason: "Use event handlers for TCP")
    }

    public func receive<T: Decodable>(as type: T.Type, timeout: TimeInterval?) async throws -> T {
        throw NexusError.unsupportedOperation(operation: "receive", reason: "Use event handlers for TCP")
    }

    public func on(_ event: ConnectionEvent, handler: @escaping (Data) async -> Void) {
        if eventHandlers[event] == nil {
            eventHandlers[event] = []
        }
        eventHandlers[event]?.append(handler)
    }

    // MARK: - State Handling

    private func handleStateUpdate(_ state: NWConnection.State) async {
        switch state {
        case .ready:
            _state = .connected
            reconnectionAttempt = 0
            await lifecycleHooks.onConnected?()

            // 启动心跳
            if configuration.heartbeatConfig.enabled {
                startHeartbeat()
            }

            // 开始接收数据
            startReceiving()

        case .waiting(let error):
            // 连接等待中（网络不可用等）
            await lifecycleHooks.onError?(error)

        case .failed(let error):
            // 连接失败
            await handleDisconnected(error: error)

        case .cancelled:
            // 连接已取消
            if _state != .disconnecting {
                await handleDisconnected(error: nil)
            }

        case .preparing, .setup:
            // 准备中，无需处理
            break

        @unknown default:
            break
        }
    }

    private func handleDisconnected(error: Error?) async {
        let previousState = _state

        // 停止接收
        isReceiving = false

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
            .error(error)
        } else {
            .clientInitiated
        }

        await lifecycleHooks.onDisconnected?(reason)
    }

    // MARK: - Data Receiving

    private func startReceiving() {
        guard !isReceiving, let connection = nwConnection else { return }

        isReceiving = true

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { [weak self] in
                await self?.handleReceivedData(data, isComplete: isComplete, error: error)
            }
        }
    }

    private func handleReceivedData(_ data: Data?, isComplete: Bool, error: Error?) async {
        // 处理错误
        if let error = error {
            await handleDisconnected(error: error)
            return
        }

        // 处理数据
        if let data = data, !data.isEmpty {
            receiveBuffer.append(data)
            await parseMessages()
        }

        // 检查是否完成
        if isComplete {
            await handleDisconnected(error: nil)
            return
        }

        // 继续接收
        startReceiving()
    }

    // MARK: - Message Parsing

    private func parseMessages() async {
        while true {
            // 检查是否有完整的消息（至少 4 字节长度前缀）
            guard receiveBuffer.count >= 4 else { break }

            // 读取消息长度（大端序）
            guard let totalLength = receiveBuffer.readBigEndianUInt32(at: 0) else { break }

            // 检查是否接收到完整消息（4字节长度 + 实际消息）
            guard receiveBuffer.count >= 4 + Int(totalLength) else { break }

            // 提取消息数据（不包括长度前缀）
            let messageData = receiveBuffer.subdata(in: 4..<(4 + Int(totalLength)))

            // 从缓冲区移除已处理的消息
            receiveBuffer.removeFirst(4 + Int(totalLength))

            // 处理消息
            await processMessage(messageData)
        }
    }

    private func processMessage(_ data: Data) async {
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
        case .response(let data):
            await dispatchEvent(.message, data: data)

        case .notification(let data):
            await dispatchEvent(.notification, data: data)

        case .control(let type, let data):
            if type == "heartbeat" {
                await handleHeartbeatResponse()
            }
            await dispatchEvent(.control, data: data)
        }
    }

    private func dispatchEvent(_ event: ConnectionEvent, data: Data) async {
        guard let handlers = eventHandlers[event] else { return }

        for handler in handlers {
            await handler(data)
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()

        let interval = configuration.heartbeatConfig.interval
        let timer = DispatchSource.makeTimerSource(queue: connectionQueue)

        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(100)
        )

        timer.setEventHandler { [weak self] in
            Task { [weak self] in
                await self?.sendHeartbeat()
            }
        }

        timer.resume()
        self.heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func sendHeartbeat() async {
        let currentTime = UInt64(Date().timeIntervalSince1970 * 1000)

        // 检查心跳超时
        let timeout = configuration.heartbeatConfig.timeout
        if lastHeartbeatTime > 0 && currentTime - lastHeartbeatTime > UInt64(timeout * 1000) {
            // 心跳超时，断开连接
            await handleDisconnected(error: NexusError.heartbeatTimeout)
            return
        }

        // 发送心跳
        do {
            if let adapter = configuration.protocolAdapter {
                let heartbeatData = try await adapter.createHeartbeat()
                try await send(heartbeatData, timeout: timeout)
            }
        } catch {
            await lifecycleHooks.onError?(error)
        }
    }

    private func handleHeartbeatResponse() async {
        lastHeartbeatTime = UInt64(Date().timeIntervalSince1970 * 1000)
    }
}

// MARK: - NWParameters Extension

extension NWParameters {
    /// 从代理配置设置代理
    fileprivate func setProxy(from config: ProxyConfiguration) {
        // SOCKS5 代理配置
        if config.type == .socks5 {
            let proxyConfig = ProxyConfiguration.Dictionary()
            proxyConfig[kCFProxyTypeKey as String] = kCFProxyTypeSOCKS as String
            proxyConfig[kCFProxyHostNameKey as String] = config.host
            proxyConfig[kCFProxyPortNumberKey as String] = config.port

            if let username = config.username {
                proxyConfig[kCFProxyUsernameKey as String] = username
            }

            if let password = config.password {
                proxyConfig[kCFProxyPasswordKey as String] = password
            }

            // 设置代理配置（通过私有 API，生产环境需要其他方式）
            // 这里仅作示例，实际需要通过系统设置或 NEProvider
        }
    }
}

extension ProxyConfiguration {
    fileprivate typealias Dictionary = [String: Any]
}

// MARK: - Timeout Helper

/// 带超时的异步执行
private func withTimeout<T>(
    _ timeout: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // 添加实际操作
        group.addTask {
            try await operation()
        }

        // 添加超时任务
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw NexusError.connectionTimeout
        }

        // 返回第一个完成的结果
        let result = try await group.next()!

        // 取消其他任务
        group.cancelAll()

        return result
    }
}

// MARK: - Connection Event

/// 连接事件
public enum ConnectionEvent: Hashable, Sendable {
    case message
    case notification
    case control
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

// MARK: - Protocol Adapter Extension

extension ProtocolAdapter {
    /// 创建心跳消息（默认实现）
    func createHeartbeat() async throws -> Data {
        Data() // 子类应该重写
    }
}
