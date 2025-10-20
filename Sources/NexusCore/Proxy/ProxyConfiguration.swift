//
//  ProxyConfiguration.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Proxy Configuration

/// 代理配置
public struct ProxyConfiguration: Sendable {

    // MARK: - Nested Types

    /// 代理类型
    public enum ProxyType: Sendable {
        /// SOCKS5代理
        case socks5

        /// SOCKS4代理
        case socks4

        /// HTTP CONNECT代理
        case httpConnect

        var protocolVersion: UInt8 {
            switch self {
            case .socks5: return 5
            case .socks4: return 4
            case .httpConnect: return 0
            }
        }
    }

    /// 认证凭证
    public struct Credentials: Sendable {
        public let username: String
        public let password: String

        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }

    // MARK: - Properties

    /// 代理类型
    public let type: ProxyType

    /// 代理服务器地址
    public let host: String

    /// 代理服务器端口
    public let port: UInt16

    /// 认证凭证(可选)
    public let credentials: Credentials?

    /// 连接超时时间
    public let timeout: TimeInterval

    /// 是否启用代理
    public let enabled: Bool

    // MARK: - Initialization

    public init(
        type: ProxyType = .socks5,
        host: String,
        port: UInt16,
        credentials: Credentials? = nil,
        timeout: TimeInterval = 30.0,
        enabled: Bool = true
    ) {
        self.type = type
        self.host = host
        self.port = port
        self.credentials = credentials
        self.timeout = timeout
        self.enabled = enabled
    }

    // MARK: - Convenience Initializers

    /// 创建SOCKS5代理配置
    public static func socks5(
        host: String,
        port: UInt16,
        username: String? = nil,
        password: String? = nil
    ) -> ProxyConfiguration {
        let credentials: Credentials? = if let username = username, let password = password {
            Credentials(username: username, password: password)
        } else {
            nil
        }

        return ProxyConfiguration(
            type: .socks5,
            host: host,
            port: port,
            credentials: credentials
        )
    }

    /// 创建SOCKS4代理配置
    public static func socks4(
        host: String,
        port: UInt16
    ) -> ProxyConfiguration {
        ProxyConfiguration(
            type: .socks4,
            host: host,
            port: port,
            credentials: nil
        )
    }

    /// 创建HTTP CONNECT代理配置
    public static func httpConnect(
        host: String,
        port: UInt16,
        username: String? = nil,
        password: String? = nil
    ) -> ProxyConfiguration {
        let credentials: Credentials? = if let username = username, let password = password {
            Credentials(username: username, password: password)
        } else {
            nil
        }

        return ProxyConfiguration(
            type: .httpConnect,
            host: host,
            port: port,
            credentials: credentials
        )
    }
}
