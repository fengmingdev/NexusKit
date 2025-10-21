//
//  ConnectionBuilder.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Connection Builder

/// 连接构建器 - 使用流畅的链式 API 配置和创建连接
public final class ConnectionBuilder {
    private let endpoint: Endpoint
    private let manager: ConnectionManager
    private let globalConfig: GlobalConfiguration

    // Configuration properties
    private var connectionId: String?
    private var protocolAdapter: (any ProtocolAdapter)?
    private var reconnectionStrategy: (any ReconnectionStrategy)?
    private var middlewares: [any Middleware] = []
    private var connectTimeout: TimeInterval?
    private var readWriteTimeout: TimeInterval?
    private var heartbeatConfig: HeartbeatConfiguration?
    private var tlsConfig: LegacyTLSConfiguration?
    private var proxyConfig: ProxyConfiguration?
    private var lifecycleHooks: LifecycleHooks = LifecycleHooks()
    private var customMetadata: [String: String] = [:]

    init(
        endpoint: Endpoint,
        manager: ConnectionManager,
        globalConfig: GlobalConfiguration
    ) {
        self.endpoint = endpoint
        self.manager = manager
        self.globalConfig = globalConfig
    }

    // MARK: - Configuration Methods

    /// 设置连接 ID（默认自动生成）
    /// - Parameter id: 连接标识符
    /// - Returns: 构建器实例
    @discardableResult
    public func id(_ id: String) -> Self {
        self.connectionId = id
        return self
    }

    /// 设置协议适配器
    /// - Parameter adapter: 协议适配器
    /// - Returns: 构建器实例
    @discardableResult
    public func `protocol`(_ adapter: any ProtocolAdapter) -> Self {
        self.protocolAdapter = adapter
        return self
    }

    /// 设置重连策略
    /// - Parameter strategy: 重连策略
    /// - Returns: 构建器实例
    @discardableResult
    public func reconnection(_ strategy: any ReconnectionStrategy) -> Self {
        self.reconnectionStrategy = strategy
        return self
    }

    /// 添加中间件
    /// - Parameter middleware: 中间件实例
    /// - Returns: 构建器实例
    @discardableResult
    public func middleware(_ middleware: any Middleware) -> Self {
        middlewares.append(middleware)
        return self
    }

    /// 批量添加中间件
    /// - Parameter middlewares: 中间件数组
    /// - Returns: 构建器实例
    @discardableResult
    public func middlewares(_ middlewares: [any Middleware]) -> Self {
        self.middlewares.append(contentsOf: middlewares)
        return self
    }

    /// 设置连接超时
    /// - Parameter timeout: 超时时间（秒）
    /// - Returns: 构建器实例
    @discardableResult
    public func timeout(_ timeout: TimeInterval) -> Self {
        self.connectTimeout = timeout
        return self
    }

    /// 设置读写超时
    /// - Parameter timeout: 超时时间（秒）
    /// - Returns: 构建器实例
    @discardableResult
    public func readWriteTimeout(_ timeout: TimeInterval) -> Self {
        self.readWriteTimeout = timeout
        return self
    }

    /// 配置心跳
    /// - Parameters:
    ///   - interval: 心跳间隔（秒）
    ///   - timeout: 心跳超时（秒）
    /// - Returns: 构建器实例
    @discardableResult
    public func heartbeat(interval: TimeInterval, timeout: TimeInterval) -> Self {
        self.heartbeatConfig = HeartbeatConfiguration(
            interval: interval,
            timeout: timeout,
            enabled: true
        )
        return self
    }

    /// 禁用心跳
    /// - Returns: 构建器实例
    @discardableResult
    public func disableHeartbeat() -> Self {
        self.heartbeatConfig = HeartbeatConfiguration(
            interval: 0,
            timeout: 0,
            enabled: false
        )
        return self
    }

    /// 启用 TLS/SSL
    /// - Parameter certificate: TLS 证书配置（nil 使用系统默认）
    /// - Returns: 构建器实例
    @discardableResult
    public func enableTLS(certificate: TLSCertificate? = nil) -> Self {
        self.tlsConfig = LegacyTLSConfiguration(
            enabled: true,
            certificate: certificate
        )
        return self
    }

    /// 配置代理
    /// - Parameter config: 代理配置
    /// - Returns: 构建器实例
    @discardableResult
    public func proxy(_ config: ProxyConfiguration) -> Self {
        self.proxyConfig = config
        return self
    }

    /// 设置生命周期钩子
    /// - Parameter hooks: 生命周期钩子
    /// - Returns: 构建器实例
    @discardableResult
    public func hooks(_ hooks: LifecycleHooks) -> Self {
        self.lifecycleHooks = hooks
        return self
    }

    /// 添加自定义元数据
    /// - Parameters:
    ///   - key: 键
    ///   - value: 值
    /// - Returns: 构建器实例
    @discardableResult
    public func metadata(key: String, value: String) -> Self {
        customMetadata[key] = value
        return self
    }

    // MARK: - Build and Connect

    /// 构建并连接
    /// - Returns: 连接实例
    /// - Throws: 连接失败时抛出错误
    public func connect() async throws -> any Connection {
        let config = buildConfiguration()
        let connection = try await manager.createConnection(
            endpoint: endpoint,
            configuration: config
        )
        try await connection.connect()
        return connection
    }

    /// 仅构建连接（不立即连接）
    /// - Returns: 连接实例
    /// - Throws: 构建失败时抛出错误
    public func build() async throws -> any Connection {
        let config = buildConfiguration()
        return try await manager.createConnection(
            endpoint: endpoint,
            configuration: config
        )
    }

    // MARK: - Private Methods

    private func buildConfiguration() -> ConnectionConfiguration {
        // 转换 LegacyTLSConfiguration 到新的 TLSConfiguration
        let newTLSConfig: TLSConfiguration?
        if let legacy = tlsConfig {
            if legacy.enabled {
                // 创建简单的 TLS 配置（使用系统默认）
                newTLSConfig = TLSConfiguration(
                    enabled: true,
                    version: .automatic,
                    p12Certificate: nil,
                    validationPolicy: legacy.allowSelfSigned ? .disabled : .system,
                    cipherSuites: .default,
                    serverName: nil,
                    alpnProtocols: nil,
                    allowSelfSigned: legacy.allowSelfSigned
                )
            } else {
                newTLSConfig = nil
            }
        } else {
            newTLSConfig = nil
        }

        return ConnectionConfiguration(
            id: connectionId ?? UUID().uuidString,
            endpoint: endpoint,
            protocolAdapter: protocolAdapter,
            reconnectionStrategy: reconnectionStrategy ?? globalConfig.defaultReconnectionStrategy,
            middlewares: middlewares,
            connectTimeout: connectTimeout ?? globalConfig.defaultConnectTimeout,
            readWriteTimeout: readWriteTimeout ?? globalConfig.defaultReadWriteTimeout,
            heartbeatConfig: heartbeatConfig ?? HeartbeatConfiguration(
                interval: globalConfig.defaultHeartbeatInterval,
                timeout: globalConfig.defaultHeartbeatTimeout,
                enabled: true
            ),
            tlsConfig: newTLSConfig,
            proxyConfig: proxyConfig,
            lifecycleHooks: lifecycleHooks,
            metadata: customMetadata
        )
    }
}

// MARK: - Connection Configuration

/// 连接配置
public struct ConnectionConfiguration: Sendable {
    public let id: String
    public let endpoint: Endpoint
    public let protocolAdapter: (any ProtocolAdapter)?
    public let reconnectionStrategy: (any ReconnectionStrategy)?
    public let middlewares: [any Middleware]
    public let connectTimeout: TimeInterval
    public let readWriteTimeout: TimeInterval
    public let heartbeatConfig: HeartbeatConfiguration
    public let tlsConfig: TLSConfiguration? // 使用增强的TLSConfiguration
    public let proxyConfig: ProxyConfiguration? // 使用增强的ProxyConfiguration
    public let lifecycleHooks: LifecycleHooks
    public let metadata: [String: String]

    public init(
        id: String,
        endpoint: Endpoint,
        protocolAdapter: (any ProtocolAdapter)?,
        reconnectionStrategy: (any ReconnectionStrategy)?,
        middlewares: [any Middleware],
        connectTimeout: TimeInterval,
        readWriteTimeout: TimeInterval,
        heartbeatConfig: HeartbeatConfiguration,
        tlsConfig: TLSConfiguration?,
        proxyConfig: ProxyConfiguration?,
        lifecycleHooks: LifecycleHooks,
        metadata: [String: String]
    ) {
        self.id = id
        self.endpoint = endpoint
        self.protocolAdapter = protocolAdapter
        self.reconnectionStrategy = reconnectionStrategy
        self.middlewares = middlewares
        self.connectTimeout = connectTimeout
        self.readWriteTimeout = readWriteTimeout
        self.heartbeatConfig = heartbeatConfig
        self.tlsConfig = tlsConfig
        self.proxyConfig = proxyConfig
        self.lifecycleHooks = lifecycleHooks
        self.metadata = metadata
    }
}

// MARK: - Heartbeat Configuration

/// 心跳配置
public struct HeartbeatConfiguration: Sendable {
    /// 心跳间隔（秒）
    public let interval: TimeInterval

    /// 心跳超时（秒）
    public let timeout: TimeInterval

    /// 是否启用
    public let enabled: Bool

    public init(
        interval: TimeInterval,
        timeout: TimeInterval,
        enabled: Bool
    ) {
        self.interval = interval
        self.timeout = timeout
        self.enabled = enabled
    }
}

// MARK: - TLS Configuration (Legacy)

/// TLS 配置 (旧版 - 保留向后兼容)
/// 新代码请使用 NexusCore/Security/TLSConfiguration.swift
public struct LegacyTLSConfiguration: Sendable {
    /// 是否启用 TLS
    public let enabled: Bool

    /// 证书
    public let certificate: TLSCertificate?

    /// 是否验证主机名
    public let validateHostname: Bool

    /// 是否允许自签名证书
    public let allowSelfSigned: Bool

    public init(
        enabled: Bool,
        certificate: TLSCertificate? = nil,
        validateHostname: Bool = true,
        allowSelfSigned: Bool = false
    ) {
        self.enabled = enabled
        self.certificate = certificate
        self.validateHostname = validateHostname
        self.allowSelfSigned = allowSelfSigned
    }
}

/// TLS 证书
public struct TLSCertificate: Sendable {
    /// 证书路径
    public let path: String

    /// 证书密码
    public let password: String?

    public init(path: String, password: String? = nil) {
        self.path = path
        self.password = password
    }
}

// MARK: - Proxy Configuration
// 代理配置已移至 NexusCore/Proxy/ProxyConfiguration.swift
