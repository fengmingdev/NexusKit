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
#if canImport(NexusCore)
import NexusCore
#endif

// MARK: - TCP Connection

/// TCP 连接实现（基于 Network framework）
/// 集成了增强的TLS、SOCKS5代理、网络监控、高性能缓冲区和智能心跳
public final class TCPConnection: Connection, @unchecked Sendable {
    // MARK: - Properties

    public let id: String
    private let endpoint: Endpoint
    private let configuration: ConnectionConfiguration

    /// 线程安全锁
    private let lock = UnfairLock()

    /// 内部状态
    private var _state: ConnectionState = .disconnected

    /// 底层 TCP 连接
    private var nwConnection: NWConnection?

    /// 高性能缓冲区管理器
    private var bufferManager: BufferManager?

    /// 增强的心跳管理器
    private var heartbeatManager: HeartbeatManager?

    /// 网络监控器
    private var networkMonitor: NetworkMonitor?

    /// 网络监控任务
    private var networkMonitorTask: Task<Void, Never>?

    /// 重连计数
    private var reconnectionAttempt = 0

    /// 生命周期钩子
    private let lifecycleHooks: LifecycleHooks

    /// 中间件管道
    private let middlewarePipeline: MiddlewarePipeline

    /// 事件处理器
    private var eventHandlers: [ConnectionEvent: [@Sendable (Data) async -> Void]] = [:]

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
        self.middlewarePipeline = MiddlewarePipeline()

        // 初始化高性能缓冲区
        self.bufferManager = BufferManager(
            initialCapacity: 8192
        )

        // 初始化网络监控器（用于快速重连）
        self.networkMonitor = NetworkMonitor()
    }

    // MARK: - Connection Protocol

    public var state: ConnectionState {
        get async {
            lock.withLock { _state }
        }
    }

    /// 读取状态（线程安全）
    private func getState() -> ConnectionState {
        lock.withLock { _state }
    }

    /// 更新状态（线程安全）
    private func setState(_ newState: ConnectionState) {
        lock.withLock { _state = newState }
    }

    public func connect() async throws {
        let currentState = getState()
        guard currentState == .disconnected || currentState == .reconnecting(attempt: 0) else {
            throw NexusError.invalidStateTransition(from: "\(currentState)", to: "connecting")
        }

        setState(.connecting)
        await lifecycleHooks.onConnecting?()

        // 启动网络监控
        await startNetworkMonitoring()

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

        // 配置 TLS（使用增强的 TLSConfiguration）
        let parameters: NWParameters
        if let tlsConfig = configuration.tlsConfig {
            let tlsOptions = try await configureTLS(tlsConfig, host: host)
            parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcpOptions)
        }

        // 创建连接
        var targetHost = nwHost
        var targetPort = nwPort

        // 处理 SOCKS5 代理（如果配置）
        if let proxyConfig = configuration.proxyConfig, proxyConfig.type == .socks5 {
            // 先连接到代理服务器
            targetHost = NWEndpoint.Host(proxyConfig.host)
            targetPort = NWEndpoint.Port(rawValue: proxyConfig.port)!
        }

        let connection = NWConnection(
            host: targetHost,
            port: targetPort,
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
            while self.getState() == .connecting {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            if self.getState() != .connected {
                throw NexusError.connectionTimeout
            }
        }

        // 如果使用代理，执行 SOCKS5 握手
        if let proxyConfig = configuration.proxyConfig, proxyConfig.type == .socks5 {
            try await performSOCKS5Handshake(
                connection: connection,
                targetHost: host,
                targetPort: port,
                proxyConfig: proxyConfig
            )
        }
    }

    public func disconnect(reason: DisconnectReason) async {
        guard getState() != .disconnected else { return }

        setState(.disconnecting)

        // 停止心跳
        await stopHeartbeat()

        // 停止网络监控
        await stopNetworkMonitoring()

        // 断开连接
        nwConnection?.cancel()
        nwConnection = nil

        setState(.disconnected)
        await lifecycleHooks.onDisconnected?(reason)

        // 清空缓冲区
        if let bufferManager = bufferManager {
            await bufferManager.clear()
        }

        lock.withLock {
            isReceiving = false
        }
    }

    public func send(_ data: Data, timeout: TimeInterval?) async throws {
        guard getState() == .connected else {
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
                        continuation.resume(throwing: NexusError.sendFailed(error))
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

        let context = EncodingContext(connectionId: id)
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

    /// 注册事件处理器
    ///
    /// 为特定事件类型注册处理闭包。当事件发生时，所有注册的处理器都会被调用。
    ///
    /// - Parameters:
    ///   - event: 事件类型（`.message`、`.notification`、`.control`）
    ///   - handler: 事件处理闭包，接收事件数据作为参数
    public func on(_ event: ConnectionEvent, handler: @escaping @Sendable (Data) async -> Void) {
        lock.withLock {
            if eventHandlers[event] == nil {
                eventHandlers[event] = []
            }
            eventHandlers[event]?.append(handler)
        }
    }

    // MARK: - State Handling

    private func handleStateUpdate(_ state: NWConnection.State) async {
        switch state {
        case .ready:
            setState(.connected)
            lock.withLock { reconnectionAttempt = 0 }
            await lifecycleHooks.onConnected?()

            // 启动增强的心跳管理器
            if configuration.heartbeatConfig.enabled {
                await startHeartbeat()
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
            if getState() != .disconnecting {
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
        let previousState = getState()

        // 停止接收
        lock.withLock { isReceiving = false }

        // 检查是否需要重连
        if let error = error,
           let strategy = configuration.reconnectionStrategy,
           strategy.shouldReconnect(error: error),
           previousState == .connected || previousState.isReconnecting {

            let attempt = lock.withLock { () -> Int in
                reconnectionAttempt += 1
                return reconnectionAttempt
            }

            if let delay = strategy.nextDelay(attempt: attempt, lastError: error) {
                setState(.reconnecting(attempt: attempt))
                await lifecycleHooks.onReconnecting?(attempt)

                // 延迟后重连
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                if getState().isReconnecting {
                    try? await connect()
                }
                return
            }
        }

        // 不重连，标记为断开
        setState(.disconnected)

        let reason: DisconnectReason = if let error = error {
            .networkError(error)
        } else {
            .clientInitiated
        }

        await lifecycleHooks.onDisconnected?(reason)
    }

    // MARK: - Data Receiving

    private func startReceiving() {
        let shouldReceive = lock.withLock { () -> Bool in
            guard !isReceiving, nwConnection != nil else { return false }
            isReceiving = true
            return true
        }

        guard shouldReceive, let connection = nwConnection else { return }

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

        // 处理数据 - 使用 BufferManager 进行高效缓冲
        if let data = data, !data.isEmpty, let bufferManager = bufferManager {
            try? await bufferManager.append(data)
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
        guard let bufferManager = bufferManager else { return }

        while true {
            // 使用 BufferManager 的零拷贝 API 检查消息
            let available = await bufferManager.availableBytes
            guard available >= 4 else { break }

            // 读取消息长度（零拷贝）
            guard let lengthBytes = await bufferManager.withUnsafeBytes(length: 4, { buffer in
                return Data(buffer)
            }) else { break }

            let totalLength = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // 检查是否有完整消息
            guard available >= 4 + Int(totalLength) else { break }

            // 读取完整消息（零拷贝）
            guard let messageData = await bufferManager.read(length: 4 + Int(totalLength)) else { break }

            // 提取消息数据（跳过4字节长度前缀）
            let data = messageData.dropFirst(4)

            // 处理消息
            await processMessage(Data(data))
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
        case .response(id: _, data: let data):
            await dispatchEvent(.message, data: data)

        case .notification(event: _, data: let data):
            await dispatchEvent(.notification, data: data)

        case .control(type: let type, data: let data):
            if case .heartbeat = type {
                // 使用 HeartbeatManager 记录响应
                if let manager = heartbeatManager {
                    await manager.recordHeartbeatResponse()
                }
            }
            await dispatchEvent(.control, data: data ?? Data())

        case .error(let error):
            // 处理错误事件
            await lifecycleHooks.onError?(error)
        }
    }

    private func dispatchEvent(_ event: ConnectionEvent, data: Data) async {
        let handlers = lock.withLock { eventHandlers[event] }
        guard let handlers = handlers else { return }

        for handler in handlers {
            await handler(data)
        }
    }

    // MARK: - Heartbeat (Enhanced with HeartbeatManager)

    private func startHeartbeat() async {
        await stopHeartbeat()

        // 创建 HeartbeatManager 配置
        let config = HeartbeatManager.Configuration(
            interval: configuration.heartbeatConfig.interval,
            timeout: configuration.heartbeatConfig.timeout,
            maxLostCount: 3,
            adaptiveInterval: true,
            minInterval: 10.0,
            maxInterval: 120.0,
            bidirectional: true,
            heartbeatDataProvider: nil // 使用默认心跳数据
        )

        let manager = HeartbeatManager(configuration: config)
        self.heartbeatManager = manager

        // 启动心跳管理器
        await manager.start(
            onHeartbeatNeeded: { [weak self] heartbeatData in
                guard let self = self else { return }

                // 使用协议适配器创建心跳（如果有）
                let data: Data
                if let adapter = self.configuration.protocolAdapter {
                    data = try await adapter.createHeartbeat()
                } else {
                    data = heartbeatData
                }

                try await self.send(data, timeout: self.configuration.heartbeatConfig.timeout)
            },
            onTimeout: { [weak self] in
                guard let self = self else { return }
                print("[TCPConnection] 心跳超时，断开连接")
                await self.handleDisconnected(error: NexusError.heartbeatTimeout)
            },
            onStateChanged: { [weak self] state in
                guard let self = self else { return }
                print("[TCPConnection] 心跳状态变化: \(state)")

                // 可以根据状态触发一些操作
                if state == .warning {
                    await self.lifecycleHooks.onError?(NexusError.heartbeatTimeout)
                }
            }
        )

        print("[TCPConnection] 增强心跳管理器已启动")
    }

    private func stopHeartbeat() async {
        if let manager = heartbeatManager {
            await manager.stop()
            print("[TCPConnection] 增强心跳管理器已停止")
        }
        heartbeatManager = nil
    }
    // MARK: - Network Monitoring

    private func startNetworkMonitoring() async {
        guard let monitor = networkMonitor else { return }

        await monitor.start()

        // 监听网络变化
        networkMonitorTask = Task { [weak self] in
            guard let self = self, let changes = await monitor.changes else { return }

            for await change in changes {
                await self.handleNetworkChange(change)
            }
        }

        print("[TCPConnection] 网络监控已启动")
    }

    private func stopNetworkMonitoring() async {
        networkMonitorTask?.cancel()
        networkMonitorTask = nil

        if let monitor = networkMonitor {
            await monitor.stop()
            print("[TCPConnection] 网络监控已停止")
        }
    }

    private func handleNetworkChange(_ change: NetworkMonitor.NetworkChange) async {
        switch change {
        case .connected(let status):
            print("[TCPConnection] 网络已连接: \(status)")

            // 如果当前断开，尝试快速重连
            if getState() == .disconnected {
                print("[TCPConnection] 检测到网络恢复，尝试重连")
                try? await connect()
            }

        case .disconnected:
            print("[TCPConnection] 网络已断开")

        case .interfaceChanged(let from, let to):
            print("[TCPConnection] 网络接口切换: \(String(describing: from)) → \(String(describing: to))")

            // 网络接口切换，可能需要重建连接
            if getState() == .connected {
                print("[TCPConnection] 检测到接口切换，准备重连")
                await disconnect(reason: .clientInitiated)
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 等待3秒
                try? await connect()
            }

        case .statusChanged(let status):
            print("[TCPConnection] 网络状态变化: \(status)")
            // 可以根据需要处理状态变化
        }
    }

    // MARK: - TLS Configuration

    private func configureTLS(_ config: TLSConfiguration, host: String) async throws -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()
        let secOptions = tlsOptions.securityProtocolOptions

        // 配置 TLS 版本
        switch config.version {
        case .tls10:
            sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv10)
        case .tls11:
            sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv11)
        case .tls12:
            sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv12)
        case .tls13:
            sec_protocol_options_set_min_tls_protocol_version(secOptions, .TLSv13)
        case .automatic:
            // 使用系统默认
            break
        }

        // 配置客户端证书（如果有）
        if let p12Cert = config.p12Certificate {
            let (identity, certificates) = try await certificateCache.loadP12Certificate(p12Cert)

            // 设置客户端证书
            var certArray: [SecCertificate] = [certificates[0]]
            if certificates.count > 1 {
                certArray.append(contentsOf: certificates[1...])
            }

            let identityRef = sec_identity_create(identity)!
            sec_protocol_options_set_local_identity(secOptions, identityRef)
        }

        // 配置验证策略
        switch config.validationPolicy {
        case .system:
            // 使用系统默认验证
            sec_protocol_options_set_peer_authentication_required(secOptions, true)

        case .custom(let certData):
            // 自定义根证书
            sec_protocol_options_set_peer_authentication_required(secOptions, true)
            if let cert = SecCertificateCreateWithData(nil, certData.data as CFData) {
                _ = sec_certificate_create(cert)
                // 添加到信任锚点
                sec_protocol_options_add_tls_application_protocol(secOptions, "h2")
            }

        case .pinning(let certDataArray):
            // 证书固定
            sec_protocol_options_set_peer_authentication_required(secOptions, true)

            var pinnedCerts: [SecCertificate] = []
            for certData in certDataArray {
                if let cert = SecCertificateCreateWithData(nil, certData.data as CFData) {
                    pinnedCerts.append(cert)
                }
            }

            // 设置证书验证回调
            sec_protocol_options_set_verify_block(
                secOptions,
                { (metadata, trust, complete) in
                    let serverTrust = sec_trust_copy_ref(trust).takeRetainedValue()

                    // 验证证书是否在固定列表中
                    let certCount = SecTrustGetCertificateCount(serverTrust)
                    var isValid = false

                    for i in 0..<certCount {
                        if let serverCert = SecTrustGetCertificateAtIndex(serverTrust, i) {
                            let serverCertData = SecCertificateCopyData(serverCert) as Data
                            for pinnedCert in pinnedCerts {
                                let pinnedCertData = SecCertificateCopyData(pinnedCert) as Data
                                if serverCertData == pinnedCertData {
                                    isValid = true
                                    break
                                }
                            }
                            if isValid { break }
                        }
                    }

                    complete(isValid)
                },
                connectionQueue
            )

        case .disabled:
            // 禁用验证（仅测试环境）
            sec_protocol_options_set_peer_authentication_required(secOptions, false)
        }

        // 配置 ALPN
        if let alpnProtocols = config.alpnProtocols {
            for proto in alpnProtocols {
                sec_protocol_options_add_tls_application_protocol(secOptions, proto)
            }
        }

        // 配置密码套件
        for suite in config.cipherSuites.suites {
            sec_protocol_options_append_tls_ciphersuite(secOptions, suite)
        }

        return tlsOptions
    }

    // MARK: - SOCKS5 Proxy

    private func performSOCKS5Handshake(
        connection: NWConnection,
        targetHost: String,
        targetPort: UInt16,
        proxyConfig: NexusCore.ProxyConfiguration
    ) async throws {
        print("[TCPConnection] 执行 SOCKS5 握手")

        let handler = SOCKS5ProxyHandler(configuration: proxyConfig)
        let targetEndpoint = Endpoint.tcp(host: targetHost, port: targetPort)

        do {
            try await handler.negotiate(through: connection, to: targetEndpoint)
            print("[TCPConnection] SOCKS5 握手成功")
        } catch {
            print("[TCPConnection] SOCKS5 握手失败: \(error)")
            throw NexusError.proxyConnectionFailed(reason: error.localizedDescription)
        }
    }
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
