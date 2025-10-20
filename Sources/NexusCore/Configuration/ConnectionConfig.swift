//
//  ConnectionConfig.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 连接配置
///
/// 控制网络连接的行为，包括超时、重试、心跳等。
public struct ConnectionConfig: Sendable {
    
    // MARK: - Timeout
    
    /// 连接超时 (seconds)
    public var connectTimeout: TimeInterval
    
    /// 读取超时 (seconds)
    public var readTimeout: TimeInterval
    
    /// 写入超时 (seconds)
    public var writeTimeout: TimeInterval
    
    // MARK: - Retry
    
    /// 最大重试次数
    public var maxRetryCount: Int
    
    /// 初始重试延迟 (seconds)
    public var initialRetryDelay: TimeInterval
    
    /// 最大重试延迟 (seconds)
    public var maxRetryDelay: TimeInterval
    
    /// 重试指数退避系数
    public var retryBackoffMultiplier: Double
    
    // MARK: - Heartbeat
    
    /// 是否启用心跳
    public var enableHeartbeat: Bool
    
    /// 心跳间隔 (seconds)
    public var heartbeatInterval: TimeInterval
    
    /// 心跳超时 (seconds)
    public var heartbeatTimeout: TimeInterval
    
    /// 最大失败心跳次数
    public var maxFailedHeartbeats: Int
    
    // MARK: - Reconnection
    
    /// 是否启用自动重连
    public var enableAutoReconnect: Bool
    
    /// 重连延迟 (seconds)
    public var reconnectDelay: TimeInterval
    
    /// 最大重连延迟 (seconds)
    public var maxReconnectDelay: TimeInterval
    
    /// 最大重连次数 (0 = 无限)
    public var maxReconnectAttempts: Int
    
    // MARK: - Buffer
    
    /// 接收缓冲区大小 (bytes)
    public var receiveBufferSize: Int
    
    /// 发送缓冲区大小 (bytes)
    public var sendBufferSize: Int
    
    // MARK: - Connection Pooling
    
    /// 是否启用连接池
    public var enableConnectionPool: Bool
    
    /// 最小连接数
    public var minPoolSize: Int
    
    /// 最大连接数
    public var maxPoolSize: Int
    
    /// 连接空闲超时 (seconds)
    public var idleTimeout: TimeInterval
    
    // MARK: - Initialization
    
    /// 初始化连接配置
    public init(
        connectTimeout: TimeInterval = 30,
        readTimeout: TimeInterval = 60,
        writeTimeout: TimeInterval = 30,
        maxRetryCount: Int = 3,
        initialRetryDelay: TimeInterval = 1,
        maxRetryDelay: TimeInterval = 60,
        retryBackoffMultiplier: Double = 2.0,
        enableHeartbeat: Bool = true,
        heartbeatInterval: TimeInterval = 30,
        heartbeatTimeout: TimeInterval = 10,
        maxFailedHeartbeats: Int = 3,
        enableAutoReconnect: Bool = true,
        reconnectDelay: TimeInterval = 1,
        maxReconnectDelay: TimeInterval = 30,
        maxReconnectAttempts: Int = 0,
        receiveBufferSize: Int = 8192,
        sendBufferSize: Int = 8192,
        enableConnectionPool: Bool = false,
        minPoolSize: Int = 1,
        maxPoolSize: Int = 10,
        idleTimeout: TimeInterval = 300
    ) {
        self.connectTimeout = connectTimeout
        self.readTimeout = readTimeout
        self.writeTimeout = writeTimeout
        self.maxRetryCount = maxRetryCount
        self.initialRetryDelay = initialRetryDelay
        self.maxRetryDelay = maxRetryDelay
        self.retryBackoffMultiplier = retryBackoffMultiplier
        self.enableHeartbeat = enableHeartbeat
        self.heartbeatInterval = heartbeatInterval
        self.heartbeatTimeout = heartbeatTimeout
        self.maxFailedHeartbeats = maxFailedHeartbeats
        self.enableAutoReconnect = enableAutoReconnect
        self.reconnectDelay = reconnectDelay
        self.maxReconnectDelay = maxReconnectDelay
        self.maxReconnectAttempts = maxReconnectAttempts
        self.receiveBufferSize = receiveBufferSize
        self.sendBufferSize = sendBufferSize
        self.enableConnectionPool = enableConnectionPool
        self.minPoolSize = minPoolSize
        self.maxPoolSize = maxPoolSize
        self.idleTimeout = idleTimeout
    }
    
    // MARK: - Defaults
    
    /// 默认配置
    public static let `default` = ConnectionConfig()
    
    /// 快速配置 (短超时)
    public static let fast = ConnectionConfig(
        connectTimeout: 10,
        readTimeout: 30,
        writeTimeout: 10,
        heartbeatInterval: 15
    )
    
    /// 慢速配置 (长超时)
    public static let slow = ConnectionConfig(
        connectTimeout: 60,
        readTimeout: 120,
        writeTimeout: 60,
        heartbeatInterval: 60
    )
    
    /// 可靠配置 (高重试)
    public static let reliable = ConnectionConfig(
        maxRetryCount: 10,
        enableHeartbeat: true,
        enableAutoReconnect: true,
        maxReconnectAttempts: 0
    )
    
    // MARK: - Validation
    
    /// 验证配置有效性
    public func validate() throws {
        guard connectTimeout > 0 else {
            throw ConfigurationError.invalidTimeout(connectTimeout)
        }
        
        guard readTimeout > 0 else {
            throw ConfigurationError.invalidTimeout(readTimeout)
        }
        
        guard writeTimeout > 0 else {
            throw ConfigurationError.invalidTimeout(writeTimeout)
        }
        
        guard maxRetryCount >= 0 else {
            throw ConfigurationError.invalidRetryCount(maxRetryCount)
        }
        
        guard heartbeatInterval > 0 else {
            throw ConfigurationError.invalidHeartbeatInterval(heartbeatInterval)
        }
        
        guard maxReconnectDelay > 0 else {
            throw ConfigurationError.invalidMaxReconnectDelay(maxReconnectDelay)
        }
        
        guard receiveBufferSize > 0 else {
            throw ConfigurationError.invalidBufferSize(receiveBufferSize)
        }
        
        guard sendBufferSize > 0 else {
            throw ConfigurationError.invalidBufferSize(sendBufferSize)
        }
        
        guard minPoolSize <= maxPoolSize else {
            throw ConfigurationError.missingRequiredConfig("minPoolSize must <= maxPoolSize")
        }
    }
}

// MARK: - CustomStringConvertible

extension ConnectionConfig: CustomStringConvertible {
    public var description: String {
        """
        ConnectionConfig(
            timeout: \(connectTimeout)s,
            retry: \(maxRetryCount),
            heartbeat: \(enableHeartbeat ? "\(heartbeatInterval)s" : "disabled"),
            autoReconnect: \(enableAutoReconnect),
            bufferSize: \(receiveBufferSize)
        )
        """
    }
}
