//
//  TCPConnectionFactory.swift
//  NexusTCP
//
//  Created by NexusKit Contributors
//

import Foundation
#if canImport(NexusCore)
import NexusCore
#endif

// MARK: - TCP Connection Factory

/// TCP 连接工厂
public final class TCPConnectionFactory {
    public static let shared = TCPConnectionFactory()

    private init() {}

    /// 创建 TCP 连接
    /// - Parameters:
    ///   - id: 连接 ID
    ///   - endpoint: TCP 端点
    ///   - configuration: 连接配置
    /// - Returns: TCP 连接实例
    public func createConnection(
        id: String,
        endpoint: Endpoint,
        configuration: ConnectionConfiguration
    ) -> any Connection {
        guard case .tcp = endpoint else {
            fatalError("TCPConnectionFactory requires TCP endpoint")
        }

        return TCPConnection(
            id: id,
            endpoint: endpoint,
            configuration: configuration
        )
    }
}

// MARK: - NexusKit Extension

extension NexusKit {
    /// 创建 TCP 连接构建器
    /// - Parameters:
    ///   - host: 主机地址
    ///   - port: 端口号
    /// - Returns: 连接构建器
    public func tcp(host: String, port: UInt16) -> TCPConnectionBuilder {
        let endpoint = Endpoint.tcp(host: host, port: port)
        return TCPConnectionBuilder(
            endpoint: endpoint,
            configuration: configuration
        )
    }
}

// MARK: - TCP Connection Builder

/// TCP 连接构建器（扩展版）
public final class TCPConnectionBuilder {
    private let endpoint: Endpoint
    private let globalConfig: GlobalConfiguration

    // Configuration properties
    private var connectionId: String?
    private var protocolAdapter: (any ProtocolAdapter)?
    private var reconnectionStrategy: (any ReconnectionStrategy)?
    private var middlewares: [any Middleware] = []
    private var connectTimeout: TimeInterval?
    private var readWriteTimeout: TimeInterval?
    private var heartbeatConfig: HeartbeatConfiguration?
    private var tlsConfig: NexusCore.TLSConfiguration?
    private var proxyConfig: NexusCore.ProxyConfiguration?
    private var lifecycleHooks: LifecycleHooks = LifecycleHooks()
    private var customMetadata: [String: String] = [:]

    init(
        endpoint: Endpoint,
        configuration: GlobalConfiguration
    ) {
        self.endpoint = endpoint
        self.globalConfig = configuration
    }

    // MARK: - Configuration Methods

    /// 设置连接 ID（默认自动生成）
    @discardableResult
    public func id(_ id: String) -> Self {
        self.connectionId = id
        return self
    }

    /// 使用二进制协议
    @discardableResult
    public func binaryProtocol(
        version: UInt16 = 1,
        compressionEnabled: Bool = true
    ) -> Self {
        self.protocolAdapter = BinaryProtocolAdapter(
            version: version,
            compressionEnabled: compressionEnabled
        )
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

    /// 设置读写超时
    @discardableResult
    public func readWriteTimeout(_ timeout: TimeInterval) -> Self {
        self.readWriteTimeout = timeout
        return self
    }

    /// 配置心跳
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
    @discardableResult
    public func disableHeartbeat() -> Self {
        self.heartbeatConfig = HeartbeatConfiguration(
            interval: 0,
            timeout: 0,
            enabled: false
        )
        return self
    }

    /// 启用 TLS/SSL (简单模式 - 向后兼容)
    @discardableResult
    public func enableTLS(certificate: TLSCertificate? = nil) -> Self {
        // 使用增强的 TLSConfiguration
        self.tlsConfig = NexusCore.TLSConfiguration(
            enabled: true,
            version: .automatic,
            p12Certificate: nil,
            validationPolicy: .system,
            cipherSuites: .default,
            serverName: nil,
            alpnProtocols: nil,
            allowSelfSigned: false
        )
        return self
    }

    /// 配置 TLS (增强版)
    @discardableResult
    public func tls(_ config: NexusCore.TLSConfiguration) -> Self {
        self.tlsConfig = config
        return self
    }

    /// 使用 P12 客户端证书配置 TLS
    @discardableResult
    public func tlsWithP12(
        named: String,
        password: String,
        validation: NexusCore.TLSConfiguration.ValidationPolicy = .system
    ) -> Self {
        do {
            let p12Cert = try NexusCore.TLSConfiguration.P12Certificate.fromBundle(
                named: named,
                password: password
            )

            self.tlsConfig = NexusCore.TLSConfiguration(
                enabled: true,
                version: .automatic,
                p12Certificate: p12Cert,
                validationPolicy: validation,
                cipherSuites: .default,
                serverName: nil,
                alpnProtocols: nil,
                allowSelfSigned: false
            )
        } catch {
            print("[TCPConnectionBuilder] 加载 P12 证书失败: \(error)")
        }

        return self
    }

    /// 配置证书固定
    @discardableResult
    public func tlsWithPinning(certificates: [String]) -> Self {
        var certDataArray: [NexusCore.TLSConfiguration.ValidationPolicy.CertificateData] = []

        for certName in certificates {
            if let certData = try? NexusCore.TLSConfiguration.ValidationPolicy.CertificateData.fromBundle(named: certName) {
                certDataArray.append(certData)
            }
        }

        self.tlsConfig = NexusCore.TLSConfiguration(
            enabled: true,
            version: .automatic,
            p12Certificate: nil,
            validationPolicy: .pinning(certDataArray),
            cipherSuites: .default,
            serverName: nil,
            alpnProtocols: nil,
            allowSelfSigned: false
        )

        return self
    }

    /// 配置代理
    @discardableResult
    public func proxy(_ config: NexusCore.ProxyConfiguration) -> Self {
        self.proxyConfig = config
        return self
    }

    /// 设置生命周期钩子
    @discardableResult
    public func hooks(_ hooks: LifecycleHooks) -> Self {
        self.lifecycleHooks = hooks
        return self
    }

    /// 添加自定义元数据
    @discardableResult
    public func metadata(key: String, value: String) -> Self {
        customMetadata[key] = value
        return self
    }

    // MARK: - Build and Connect

    /// 构建并连接
    public func connect() async throws -> TCPConnection {
        let config = buildConfiguration()
        let connection = TCPConnectionFactory.shared.createConnection(
            id: config.id,
            endpoint: endpoint,
            configuration: config
        ) as! TCPConnection

        try await connection.connect()
        return connection
    }

    /// 仅构建连接（不立即连接）
    public func build() async throws -> TCPConnection {
        let config = buildConfiguration()
        return TCPConnectionFactory.shared.createConnection(
            id: config.id,
            endpoint: endpoint,
            configuration: config
        ) as! TCPConnection
    }

    // MARK: - Private Methods

    private func buildConfiguration() -> ConnectionConfiguration {
        ConnectionConfiguration(
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
            tlsConfig: tlsConfig,
            proxyConfig: proxyConfig,
            lifecycleHooks: lifecycleHooks,
            metadata: customMetadata
        )
    }
}
