//
//  NexusConfiguration.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 核心配置类 - NexusKit 的统一配置管理
///
/// 提供层级化配置系统，支持全局、连接和协议级别的配置。
///
/// 使用示例:
/// ```swift
/// let config = NexusConfiguration.Builder()
///     .timeout(30)
///     .retryCount(3)
///     .enableHeartbeat(true)
///     .build()
/// ```
public final class NexusConfiguration: Sendable {
    
    // MARK: - Properties
    
    /// 全局配置
    public let global: GlobalConfig
    
    /// 连接配置
    public let connection: ConnectionConfig
    
    /// 协议配置注册表
    public let protocols: ProtocolConfigRegistry
    
    /// 环境配置
    public let environment: EnvironmentConfig
    
    // MARK: - Initialization
    
    /// 初始化配置
    /// - Parameters:
    ///   - global: 全局配置
    ///   - connection: 连接配置
    ///   - protocols: 协议配置
    ///   - environment: 环境配置
    public init(
        global: GlobalConfig = .default,
        connection: ConnectionConfig = .default,
        protocols: ProtocolConfigRegistry = .default,
        environment: EnvironmentConfig = .default
    ) {
        self.global = global
        self.connection = connection
        self.protocols = protocols
        self.environment = environment
    }
    
    // MARK: - Defaults
    
    /// 默认配置
    public static let `default` = NexusConfiguration()
    
    // MARK: - Validation
    
    /// 验证配置有效性
    /// - Throws: ConfigurationError 如果配置无效
    public func validate() throws {
        try global.validate()
        try connection.validate()
        try protocols.validate()
        try environment.validate()
    }
    
    // MARK: - Description
    
    /// 配置描述
    public var description: String {
        """
        NexusConfiguration {
            Global: \(global)
            Connection: \(connection)
            Protocols: \(protocols.registeredCount) registered
            Environment: \(environment)
        }
        """
    }
}

// MARK: - Configuration Error

/// 配置错误
public enum ConfigurationError: Error, Sendable {
    case invalidTimeout(TimeInterval)
    case invalidRetryCount(Int)
    case invalidBufferSize(Int)
    case invalidHeartbeatInterval(TimeInterval)
    case invalidMaxReconnectDelay(TimeInterval)
    case invalidProtocolName(String)
    case missingRequiredConfig(String)
    case invalidEnvironmentVariable(String)
    
    public var localizedDescription: String {
        switch self {
        case .invalidTimeout(let value):
            return "Invalid timeout: \(value). Must be > 0"
        case .invalidRetryCount(let value):
            return "Invalid retry count: \(value). Must be >= 0"
        case .invalidBufferSize(let value):
            return "Invalid buffer size: \(value). Must be > 0"
        case .invalidHeartbeatInterval(let value):
            return "Invalid heartbeat interval: \(value). Must be > 0"
        case .invalidMaxReconnectDelay(let value):
            return "Invalid max reconnect delay: \(value). Must be > 0"
        case .invalidProtocolName(let name):
            return "Invalid protocol name: \(name)"
        case .missingRequiredConfig(let key):
            return "Missing required config: \(key)"
        case .invalidEnvironmentVariable(let key):
            return "Invalid environment variable: \(key)"
        }
    }
}
