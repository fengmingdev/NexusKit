//
//  PoolConfiguration.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 连接池配置
///
/// 定义连接池的行为参数，包括大小限制、超时、健康检查等。
public struct PoolConfiguration: Sendable {
    
    // MARK: - Pool Size
    
    /// 最小连接数
    public let minConnections: Int
    
    /// 最大连接数
    public let maxConnections: Int
    
    // MARK: - Timeout
    
    /// 获取连接超时（秒）
    public let acquireTimeout: TimeInterval
    
    /// 空闲连接超时（秒）
    public let idleTimeout: TimeInterval
    
    /// 连接生命周期最大时长（秒，0 表示无限制）
    public let maxConnectionLifetime: TimeInterval
    
    // MARK: - Health Check
    
    /// 是否启用健康检查
    public let enableHealthCheck: Bool
    
    /// 健康检查间隔（秒）
    public let healthCheckInterval: TimeInterval
    
    /// 健康检查超时（秒）
    public let healthCheckTimeout: TimeInterval
    
    // MARK: - Behavior
    
    /// 是否在池满时等待
    public let waitWhenPoolFull: Bool
    
    /// 是否验证连接可用性
    public let validateOnAcquire: Bool
    
    /// 是否在归还时验证连接
    public let validateOnRelease: Bool
    
    // MARK: - Initialization
    
    /// 初始化连接池配置
    public init(
        minConnections: Int = 1,
        maxConnections: Int = 10,
        acquireTimeout: TimeInterval = 30,
        idleTimeout: TimeInterval = 300,
        maxConnectionLifetime: TimeInterval = 0,
        enableHealthCheck: Bool = true,
        healthCheckInterval: TimeInterval = 60,
        healthCheckTimeout: TimeInterval = 5,
        waitWhenPoolFull: Bool = true,
        validateOnAcquire: Bool = true,
        validateOnRelease: Bool = false
    ) {
        self.minConnections = minConnections
        self.maxConnections = maxConnections
        self.acquireTimeout = acquireTimeout
        self.idleTimeout = idleTimeout
        self.maxConnectionLifetime = maxConnectionLifetime
        self.enableHealthCheck = enableHealthCheck
        self.healthCheckInterval = healthCheckInterval
        self.healthCheckTimeout = healthCheckTimeout
        self.waitWhenPoolFull = waitWhenPoolFull
        self.validateOnAcquire = validateOnAcquire
        self.validateOnRelease = validateOnRelease
    }
    
    // MARK: - Defaults
    
    /// 默认配置
    public static let `default` = PoolConfiguration()
    
    /// 小型池配置
    public static let small = PoolConfiguration(
        minConnections: 1,
        maxConnections: 5
    )
    
    /// 中型池配置
    public static let medium = PoolConfiguration(
        minConnections: 5,
        maxConnections: 20
    )
    
    /// 大型池配置
    public static let large = PoolConfiguration(
        minConnections: 10,
        maxConnections: 50
    )
    
    // MARK: - Validation
    
    /// 验证配置有效性
    public func validate() throws {
        guard minConnections >= 0 else {
            throw PoolError.invalidConfiguration("minConnections must be >= 0")
        }
        
        guard maxConnections > 0 else {
            throw PoolError.invalidConfiguration("maxConnections must be > 0")
        }
        
        guard minConnections <= maxConnections else {
            throw PoolError.invalidConfiguration("minConnections must be <= maxConnections")
        }
        
        guard acquireTimeout > 0 else {
            throw PoolError.invalidConfiguration("acquireTimeout must be > 0")
        }
        
        guard idleTimeout > 0 else {
            throw PoolError.invalidConfiguration("idleTimeout must be > 0")
        }
        
        guard healthCheckInterval > 0 else {
            throw PoolError.invalidConfiguration("healthCheckInterval must be > 0")
        }
        
        guard healthCheckTimeout > 0 else {
            throw PoolError.invalidConfiguration("healthCheckTimeout must be > 0")
        }
    }
}

// MARK: - Pool Error

/// 连接池错误
public enum PoolError: Error, Sendable {
    case invalidConfiguration(String)
    case poolExhausted
    case acquireTimeout
    case connectionInvalid
    case connectionClosed
    case poolDraining
    case poolClosed
    
    public var localizedDescription: String {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid pool configuration: \(message)"
        case .poolExhausted:
            return "Connection pool exhausted"
        case .acquireTimeout:
            return "Acquire connection timeout"
        case .connectionInvalid:
            return "Connection is invalid"
        case .connectionClosed:
            return "Connection is closed"
        case .poolDraining:
            return "Pool is draining"
        case .poolClosed:
            return "Pool is closed"
        }
    }
}

// MARK: - CustomStringConvertible

extension PoolConfiguration: CustomStringConvertible {
    public var description: String {
        """
        PoolConfiguration(
            size: \(minConnections)-\(maxConnections),
            acquireTimeout: \(acquireTimeout)s,
            idleTimeout: \(idleTimeout)s,
            healthCheck: \(enableHealthCheck ? "enabled" : "disabled")
        )
        """
    }
}
