//
//  WebSocketConnectionFactory.swift
//  NexusWebSocket
//
//  Created by NexusKit Contributors
//

import Foundation
import NexusCore

// MARK: - WebSocket Connection Factory

/// WebSocket 连接工厂
@available(iOS 13.0, macOS 10.15, *)
public final class WebSocketConnectionFactory {
    public static let shared = WebSocketConnectionFactory()

    private init() {}

    /// 创建 WebSocket 连接
    public func createConnection(
        id: String,
        endpoint: Endpoint,
        configuration: WebSocketConfiguration
    ) -> WebSocketConnection {
        guard case .webSocket = endpoint else {
            fatalError("WebSocketConnectionFactory requires WebSocket endpoint")
        }

        return WebSocketConnection(
            id: id,
            endpoint: endpoint,
            configuration: configuration
        )
    }
}

// MARK: - NexusKit Extension

extension NexusKit {
    /// 创建 WebSocket 连接构建器
    /// - Parameter url: WebSocket URL (ws:// 或 wss://)
    /// - Returns: WebSocket 连接构建器
    @available(iOS 13.0, macOS 10.15, *)
    public func webSocket(url: URL) -> WebSocketConnectionBuilder {
        let endpoint = Endpoint.webSocket(url: url)
        return WebSocketConnectionBuilder(
            endpoint: endpoint,
            configuration: configuration
        )
    }
}

// MARK: - WebSocket Connection Builder

/// WebSocket 连接构建器
@available(iOS 13.0, macOS 10.15, *)
public final class WebSocketConnectionBuilder {
    private let endpoint: Endpoint
    private let globalConfig: GlobalConfiguration

    // Configuration properties
    private var connectionId: String?
    private var protocolAdapter: (any ProtocolAdapter)?
    private var reconnectionStrategy: (any ReconnectionStrategy)?
    private var middlewares: [any Middleware] = []
    private var connectTimeout: TimeInterval?
    private var headers: [String: String] = [:]
    private var protocols: [String] = []
    private var pingInterval: TimeInterval = 30
    private var lifecycleHooks: LifecycleHooks = LifecycleHooks()

    init(
        endpoint: Endpoint,
        configuration: GlobalConfiguration
    ) {
        self.endpoint = endpoint
        self.globalConfig = configuration
    }

    // MARK: - Configuration Methods

    /// 设置连接 ID
    @discardableResult
    public func id(_ id: String) -> Self {
        self.connectionId = id
        return self
    }

    /// 设置协议适配器
    @discardableResult
    public func `protocol`(_ adapter: any ProtocolAdapter) -> Self {
        self.protocolAdapter = adapter
        return self
    }

    /// 设置重连策略
    @discardableResult
    public func reconnection(_ strategy: any ReconnectionStrategy) -> Self {
        self.reconnectionStrategy = strategy
        return self
    }

    /// 添加中间件
    @discardableResult
    public func middleware(_ middleware: any Middleware) -> Self {
        middlewares.append(middleware)
        return self
    }

    /// 批量添加中间件
    @discardableResult
    public func middlewares(_ middlewares: [any Middleware]) -> Self {
        self.middlewares.append(contentsOf: middlewares)
        return self
    }

    /// 设置连接超时
    @discardableResult
    public func timeout(_ timeout: TimeInterval) -> Self {
        self.connectTimeout = timeout
        return self
    }

    /// 添加自定义 HTTP 头
    /// - Parameters:
    ///   - name: 头部名称
    ///   - value: 头部值
    @discardableResult
    public func header(name: String, value: String) -> Self {
        headers[name] = value
        return self
    }

    /// 批量设置 HTTP 头
    @discardableResult
    public func headers(_ headers: [String: String]) -> Self {
        self.headers.merge(headers) { _, new in new }
        return self
    }

    /// 设置 WebSocket 子协议
    /// - Parameter protocols: 子协议列表
    @discardableResult
    public func protocols(_ protocols: [String]) -> Self {
        self.protocols = protocols
        return self
    }

    /// 设置 Ping 间隔
    /// - Parameter interval: Ping 间隔（秒），0 表示禁用
    @discardableResult
    public func pingInterval(_ interval: TimeInterval) -> Self {
        self.pingInterval = interval
        return self
    }

    /// 设置生命周期钩子
    @discardableResult
    public func hooks(_ hooks: LifecycleHooks) -> Self {
        self.lifecycleHooks = hooks
        return self
    }

    // MARK: - Build and Connect

    /// 构建并连接
    public func connect() async throws -> WebSocketConnection {
        let config = buildConfiguration()
        let connection = WebSocketConnectionFactory.shared.createConnection(
            id: config.id,
            endpoint: endpoint,
            configuration: config
        )

        try await connection.connect()
        return connection
    }

    /// 仅构建连接（不立即连接）
    public func build() async throws -> WebSocketConnection {
        let config = buildConfiguration()
        return WebSocketConnectionFactory.shared.createConnection(
            id: config.id,
            endpoint: endpoint,
            configuration: config
        )
    }

    // MARK: - Private Methods

    private func buildConfiguration() -> WebSocketConfiguration {
        WebSocketConfiguration(
            id: connectionId ?? UUID().uuidString,
            endpoint: endpoint,
            protocolAdapter: protocolAdapter,
            reconnectionStrategy: reconnectionStrategy ?? globalConfig.defaultReconnectionStrategy,
            middlewares: middlewares,
            connectTimeout: connectTimeout ?? globalConfig.defaultConnectTimeout,
            headers: headers,
            protocols: protocols,
            pingInterval: pingInterval,
            lifecycleHooks: lifecycleHooks
        )
    }
}
