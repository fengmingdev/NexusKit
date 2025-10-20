//
//  ConfigurationBuilder.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 配置构建器
///
/// 提供流式 API 构建 NexusConfiguration。
///
/// 使用示例:
/// ```swift
/// let config = NexusConfiguration.Builder()
///     .timeout(30)
///     .retryCount(3)
///     .enableHeartbeat(true)
///     .logLevel(.debug)
///     .build()
/// ```
extension NexusConfiguration {
    
    public final class Builder {
        
        // MARK: - Properties
        
        private var globalConfig: GlobalConfig
        private var connectionConfig: ConnectionConfig
        private var protocolRegistry: ProtocolConfigRegistry
        private var environmentConfig: EnvironmentConfig
        
        // MARK: - Initialization
        
        /// 初始化构建器
        public init() {
            self.globalConfig = .default
            self.connectionConfig = .default
            self.protocolRegistry = .default
            self.environmentConfig = .default
        }
        
        /// 从现有配置初始化
        public init(from config: NexusConfiguration) {
            self.globalConfig = config.global
            self.connectionConfig = config.connection
            self.protocolRegistry = config.protocols
            self.environmentConfig = config.environment
        }
        
        // MARK: - Global Config
        
        /// 设置日志级别
        @discardableResult
        public func logLevel(_ level: NexusLogLevel) -> Builder {
            globalConfig = GlobalConfig(
                logLevel: level,
                verboseLogging: globalConfig.verboseLogging,
                defaultBufferSize: globalConfig.defaultBufferSize,
                enableMetrics: globalConfig.enableMetrics,
                metricsInterval: globalConfig.metricsInterval,
                debugMode: globalConfig.debugMode,
                printTraffic: globalConfig.printTraffic,
                maxConcurrentConnections: globalConfig.maxConcurrentConnections,
                taskPriority: globalConfig.taskPriority
            )
            return self
        }
        
        /// 启用详细日志
        @discardableResult
        public func verboseLogging(_ enabled: Bool = true) -> Builder {
            globalConfig = GlobalConfig(
                logLevel: globalConfig.logLevel,
                verboseLogging: enabled,
                defaultBufferSize: globalConfig.defaultBufferSize,
                enableMetrics: globalConfig.enableMetrics,
                metricsInterval: globalConfig.metricsInterval,
                debugMode: globalConfig.debugMode,
                printTraffic: globalConfig.printTraffic,
                maxConcurrentConnections: globalConfig.maxConcurrentConnections,
                taskPriority: globalConfig.taskPriority
            )
            return self
        }
        
        /// 设置缓冲区大小
        @discardableResult
        public func bufferSize(_ size: Int) -> Builder {
            globalConfig = GlobalConfig(
                logLevel: globalConfig.logLevel,
                verboseLogging: globalConfig.verboseLogging,
                defaultBufferSize: size,
                enableMetrics: globalConfig.enableMetrics,
                metricsInterval: globalConfig.metricsInterval,
                debugMode: globalConfig.debugMode,
                printTraffic: globalConfig.printTraffic,
                maxConcurrentConnections: globalConfig.maxConcurrentConnections,
                taskPriority: globalConfig.taskPriority
            )
            return self
        }
        
        /// 启用性能监控
        @discardableResult
        public func enableMetrics(_ enabled: Bool = true) -> Builder {
            globalConfig = GlobalConfig(
                logLevel: globalConfig.logLevel,
                verboseLogging: globalConfig.verboseLogging,
                defaultBufferSize: globalConfig.defaultBufferSize,
                enableMetrics: enabled,
                metricsInterval: globalConfig.metricsInterval,
                debugMode: globalConfig.debugMode,
                printTraffic: globalConfig.printTraffic,
                maxConcurrentConnections: globalConfig.maxConcurrentConnections,
                taskPriority: globalConfig.taskPriority
            )
            return self
        }
        
        /// 启用调试模式
        @discardableResult
        public func debugMode(_ enabled: Bool = true) -> Builder {
            globalConfig = GlobalConfig(
                logLevel: globalConfig.logLevel,
                verboseLogging: globalConfig.verboseLogging,
                defaultBufferSize: globalConfig.defaultBufferSize,
                enableMetrics: globalConfig.enableMetrics,
                metricsInterval: globalConfig.metricsInterval,
                debugMode: enabled,
                printTraffic: globalConfig.printTraffic,
                maxConcurrentConnections: globalConfig.maxConcurrentConnections,
                taskPriority: globalConfig.taskPriority
            )
            return self
        }
        
        /// 设置最大并发连接数
        @discardableResult
        public func maxConcurrentConnections(_ count: Int) -> Builder {
            globalConfig = GlobalConfig(
                logLevel: globalConfig.logLevel,
                verboseLogging: globalConfig.verboseLogging,
                defaultBufferSize: globalConfig.defaultBufferSize,
                enableMetrics: globalConfig.enableMetrics,
                metricsInterval: globalConfig.metricsInterval,
                debugMode: globalConfig.debugMode,
                printTraffic: globalConfig.printTraffic,
                maxConcurrentConnections: count,
                taskPriority: globalConfig.taskPriority
            )
            return self
        }
        
        // MARK: - Connection Config
        
        /// 设置连接超时
        @discardableResult
        public func timeout(_ timeout: TimeInterval) -> Builder {
            connectionConfig = ConnectionConfig(
                connectTimeout: timeout,
                readTimeout: connectionConfig.readTimeout,
                writeTimeout: connectionConfig.writeTimeout,
                maxRetryCount: connectionConfig.maxRetryCount,
                initialRetryDelay: connectionConfig.initialRetryDelay,
                maxRetryDelay: connectionConfig.maxRetryDelay,
                retryBackoffMultiplier: connectionConfig.retryBackoffMultiplier,
                enableHeartbeat: connectionConfig.enableHeartbeat,
                heartbeatInterval: connectionConfig.heartbeatInterval,
                heartbeatTimeout: connectionConfig.heartbeatTimeout,
                maxFailedHeartbeats: connectionConfig.maxFailedHeartbeats,
                enableAutoReconnect: connectionConfig.enableAutoReconnect,
                reconnectDelay: connectionConfig.reconnectDelay,
                maxReconnectDelay: connectionConfig.maxReconnectDelay,
                maxReconnectAttempts: connectionConfig.maxReconnectAttempts,
                receiveBufferSize: connectionConfig.receiveBufferSize,
                sendBufferSize: connectionConfig.sendBufferSize,
                enableConnectionPool: connectionConfig.enableConnectionPool,
                minPoolSize: connectionConfig.minPoolSize,
                maxPoolSize: connectionConfig.maxPoolSize,
                idleTimeout: connectionConfig.idleTimeout
            )
            return self
        }
        
        /// 设置重试次数
        @discardableResult
        public func retryCount(_ count: Int) -> Builder {
            connectionConfig = ConnectionConfig(
                connectTimeout: connectionConfig.connectTimeout,
                readTimeout: connectionConfig.readTimeout,
                writeTimeout: connectionConfig.writeTimeout,
                maxRetryCount: count,
                initialRetryDelay: connectionConfig.initialRetryDelay,
                maxRetryDelay: connectionConfig.maxRetryDelay,
                retryBackoffMultiplier: connectionConfig.retryBackoffMultiplier,
                enableHeartbeat: connectionConfig.enableHeartbeat,
                heartbeatInterval: connectionConfig.heartbeatInterval,
                heartbeatTimeout: connectionConfig.heartbeatTimeout,
                maxFailedHeartbeats: connectionConfig.maxFailedHeartbeats,
                enableAutoReconnect: connectionConfig.enableAutoReconnect,
                reconnectDelay: connectionConfig.reconnectDelay,
                maxReconnectDelay: connectionConfig.maxReconnectDelay,
                maxReconnectAttempts: connectionConfig.maxReconnectAttempts,
                receiveBufferSize: connectionConfig.receiveBufferSize,
                sendBufferSize: connectionConfig.sendBufferSize,
                enableConnectionPool: connectionConfig.enableConnectionPool,
                minPoolSize: connectionConfig.minPoolSize,
                maxPoolSize: connectionConfig.maxPoolSize,
                idleTimeout: connectionConfig.idleTimeout
            )
            return self
        }
        
        /// 启用心跳
        @discardableResult
        public func enableHeartbeat(_ enabled: Bool = true, interval: TimeInterval = 30) -> Builder {
            connectionConfig = ConnectionConfig(
                connectTimeout: connectionConfig.connectTimeout,
                readTimeout: connectionConfig.readTimeout,
                writeTimeout: connectionConfig.writeTimeout,
                maxRetryCount: connectionConfig.maxRetryCount,
                initialRetryDelay: connectionConfig.initialRetryDelay,
                maxRetryDelay: connectionConfig.maxRetryDelay,
                retryBackoffMultiplier: connectionConfig.retryBackoffMultiplier,
                enableHeartbeat: enabled,
                heartbeatInterval: interval,
                heartbeatTimeout: connectionConfig.heartbeatTimeout,
                maxFailedHeartbeats: connectionConfig.maxFailedHeartbeats,
                enableAutoReconnect: connectionConfig.enableAutoReconnect,
                reconnectDelay: connectionConfig.reconnectDelay,
                maxReconnectDelay: connectionConfig.maxReconnectDelay,
                maxReconnectAttempts: connectionConfig.maxReconnectAttempts,
                receiveBufferSize: connectionConfig.receiveBufferSize,
                sendBufferSize: connectionConfig.sendBufferSize,
                enableConnectionPool: connectionConfig.enableConnectionPool,
                minPoolSize: connectionConfig.minPoolSize,
                maxPoolSize: connectionConfig.maxPoolSize,
                idleTimeout: connectionConfig.idleTimeout
            )
            return self
        }
        
        /// 启用自动重连
        @discardableResult
        public func enableAutoReconnect(_ enabled: Bool = true) -> Builder {
            connectionConfig = ConnectionConfig(
                connectTimeout: connectionConfig.connectTimeout,
                readTimeout: connectionConfig.readTimeout,
                writeTimeout: connectionConfig.writeTimeout,
                maxRetryCount: connectionConfig.maxRetryCount,
                initialRetryDelay: connectionConfig.initialRetryDelay,
                maxRetryDelay: connectionConfig.maxRetryDelay,
                retryBackoffMultiplier: connectionConfig.retryBackoffMultiplier,
                enableHeartbeat: connectionConfig.enableHeartbeat,
                heartbeatInterval: connectionConfig.heartbeatInterval,
                heartbeatTimeout: connectionConfig.heartbeatTimeout,
                maxFailedHeartbeats: connectionConfig.maxFailedHeartbeats,
                enableAutoReconnect: enabled,
                reconnectDelay: connectionConfig.reconnectDelay,
                maxReconnectDelay: connectionConfig.maxReconnectDelay,
                maxReconnectAttempts: connectionConfig.maxReconnectAttempts,
                receiveBufferSize: connectionConfig.receiveBufferSize,
                sendBufferSize: connectionConfig.sendBufferSize,
                enableConnectionPool: connectionConfig.enableConnectionPool,
                minPoolSize: connectionConfig.minPoolSize,
                maxPoolSize: connectionConfig.maxPoolSize,
                idleTimeout: connectionConfig.idleTimeout
            )
            return self
        }
        
        /// 启用连接池
        @discardableResult
        public func enableConnectionPool(_ enabled: Bool = true, minSize: Int = 1, maxSize: Int = 10) -> Builder {
            connectionConfig = ConnectionConfig(
                connectTimeout: connectionConfig.connectTimeout,
                readTimeout: connectionConfig.readTimeout,
                writeTimeout: connectionConfig.writeTimeout,
                maxRetryCount: connectionConfig.maxRetryCount,
                initialRetryDelay: connectionConfig.initialRetryDelay,
                maxRetryDelay: connectionConfig.maxRetryDelay,
                retryBackoffMultiplier: connectionConfig.retryBackoffMultiplier,
                enableHeartbeat: connectionConfig.enableHeartbeat,
                heartbeatInterval: connectionConfig.heartbeatInterval,
                heartbeatTimeout: connectionConfig.heartbeatTimeout,
                maxFailedHeartbeats: connectionConfig.maxFailedHeartbeats,
                enableAutoReconnect: connectionConfig.enableAutoReconnect,
                reconnectDelay: connectionConfig.reconnectDelay,
                maxReconnectDelay: connectionConfig.maxReconnectDelay,
                maxReconnectAttempts: connectionConfig.maxReconnectAttempts,
                receiveBufferSize: connectionConfig.receiveBufferSize,
                sendBufferSize: connectionConfig.sendBufferSize,
                enableConnectionPool: enabled,
                minPoolSize: minSize,
                maxPoolSize: maxSize,
                idleTimeout: connectionConfig.idleTimeout
            )
            return self
        }
        
        // MARK: - Environment Config
        
        /// 从环境变量加载配置
        @discardableResult
        public func loadFromEnvironment(prefix: String = "NEXUS_") -> Builder {
            environmentConfig = EnvironmentConfig(
                prefix: prefix,
                loadFromEnvironment: true,
                customVariables: environmentConfig.customVariables
            )
            
            // 从环境变量应用配置
            applyEnvironmentConfig()
            
            return self
        }
        
        /// 合并配置
        @discardableResult
        public func merge(with config: NexusConfiguration) -> Builder {
            self.globalConfig = config.global
            self.connectionConfig = config.connection
            self.protocolRegistry = config.protocols
            self.environmentConfig = config.environment
            return self
        }
        
        // MARK: - Build
        
        /// 构建配置
        /// - Throws: ConfigurationError 如果配置无效
        /// - Returns: 构建的配置
        public func build() throws -> NexusConfiguration {
            let config = NexusConfiguration(
                global: globalConfig,
                connection: connectionConfig,
                protocols: protocolRegistry,
                environment: environmentConfig
            )
            
            try config.validate()
            
            return config
        }
        
        /// 构建配置（不抛出异常版本）
        /// - Returns: 构建的配置，如果验证失败返回默认配置
        public func buildOrDefault() -> NexusConfiguration {
            do {
                return try build()
            } catch {
                print("[NexusConfiguration] Build failed: \(error), using default")
                return .default
            }
        }
        
        // MARK: - Private
        
        /// 应用环境变量配置
        private func applyEnvironmentConfig() {
            // 超时配置
            if let timeout = environmentConfig.getTimeInterval(EnvironmentConfig.Key.timeout.rawValue) {
                _ = self.timeout(timeout)
            }
            
            // 重试配置
            if let retryCount = environmentConfig.getInt(EnvironmentConfig.Key.retryCount.rawValue) {
                _ = self.retryCount(retryCount)
            }
            
            // 心跳配置
            if let enableHeartbeat = environmentConfig.getBool(EnvironmentConfig.Key.enableHeartbeat.rawValue),
               let interval = environmentConfig.getTimeInterval(EnvironmentConfig.Key.heartbeatInterval.rawValue) {
                _ = self.enableHeartbeat(enableHeartbeat, interval: interval)
            }
            
            // 调试模式
            if let debugMode = environmentConfig.getBool(EnvironmentConfig.Key.debugMode.rawValue) {
                _ = self.debugMode(debugMode)
            }
            
            // 缓冲区大小
            if let bufferSize = environmentConfig.getInt(EnvironmentConfig.Key.bufferSize.rawValue) {
                _ = self.bufferSize(bufferSize)
            }
            
            // 自动重连
            if let enableAutoReconnect = environmentConfig.getBool(EnvironmentConfig.Key.enableAutoReconnect.rawValue) {
                _ = self.enableAutoReconnect(enableAutoReconnect)
            }
        }
    }
}
