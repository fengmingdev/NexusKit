//
//  EnvironmentConfig.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 环境配置
///
/// 从环境变量和运行时环境读取配置。
public struct EnvironmentConfig: Sendable {
    
    // MARK: - Properties
    
    /// 环境变量前缀
    public var prefix: String
    
    /// 是否从环境变量加载
    public var loadFromEnvironment: Bool
    
    /// 自定义环境变量
    public var customVariables: [String: String]
    
    // MARK: - Initialization
    
    /// 初始化环境配置
    public init(
        prefix: String = "NEXUS_",
        loadFromEnvironment: Bool = true,
        customVariables: [String: String] = [:]
    ) {
        self.prefix = prefix
        self.loadFromEnvironment = loadFromEnvironment
        self.customVariables = customVariables
    }
    
    // MARK: - Defaults
    
    /// 默认配置
    public static let `default` = EnvironmentConfig()
    
    // MARK: - Environment Access
    
    /// 获取环境变量值
    /// - Parameter key: 变量键 (不包含前缀)
    /// - Returns: 变量值，如果不存在返回 nil
    public func get(_ key: String) -> String? {
        // 优先从自定义变量获取
        if let value = customVariables[key] {
            return value
        }
        
        // 从系统环境变量获取
        if loadFromEnvironment {
            let fullKey = prefix + key
            return ProcessInfo.processInfo.environment[fullKey]
        }
        
        return nil
    }
    
    /// 获取环境变量值 (带默认值)
    /// - Parameters:
    ///   - key: 变量键
    ///   - defaultValue: 默认值
    /// - Returns: 变量值或默认值
    public func get(_ key: String, default defaultValue: String) -> String {
        get(key) ?? defaultValue
    }
    
    /// 获取 Int 类型环境变量
    public func getInt(_ key: String) -> Int? {
        guard let value = get(key) else { return nil }
        return Int(value)
    }
    
    /// 获取 Double 类型环境变量
    public func getDouble(_ key: String) -> Double? {
        guard let value = get(key) else { return nil }
        return Double(value)
    }
    
    /// 获取 Bool 类型环境变量
    public func getBool(_ key: String) -> Bool? {
        guard let value = get(key) else { return nil }
        return ["true", "yes", "1", "on"].contains(value.lowercased())
    }
    
    /// 获取 TimeInterval 类型环境变量
    public func getTimeInterval(_ key: String) -> TimeInterval? {
        guard let value = get(key) else { return nil }
        return TimeInterval(value)
    }
    
    // MARK: - Validation
    
    /// 验证配置有效性
    public func validate() throws {
        // 环境配置无需验证
    }
    
    // MARK: - Common Variables
    
    /// 常用环境变量键
    public enum Key: String {
        case timeout = "TIMEOUT"
        case retryCount = "RETRY_COUNT"
        case enableHeartbeat = "ENABLE_HEARTBEAT"
        case heartbeatInterval = "HEARTBEAT_INTERVAL"
        case logLevel = "LOG_LEVEL"
        case debugMode = "DEBUG_MODE"
        case bufferSize = "BUFFER_SIZE"
        case maxConnections = "MAX_CONNECTIONS"
        case connectTimeout = "CONNECT_TIMEOUT"
        case readTimeout = "READ_TIMEOUT"
        case writeTimeout = "WRITE_TIMEOUT"
        case enableMetrics = "ENABLE_METRICS"
        case enableAutoReconnect = "ENABLE_AUTO_RECONNECT"
        case maxRetryDelay = "MAX_RETRY_DELAY"
        case enableConnectionPool = "ENABLE_CONNECTION_POOL"
        case minPoolSize = "MIN_POOL_SIZE"
        case maxPoolSize = "MAX_POOL_SIZE"
    }
}

// MARK: - CustomStringConvertible

extension EnvironmentConfig: CustomStringConvertible {
    public var description: String {
        """
        EnvironmentConfig(
            prefix: \(prefix),
            loadFromEnvironment: \(loadFromEnvironment),
            customVariables: \(customVariables.count)
        )
        """
    }
}

// MARK: - Environment Variable Loading

extension EnvironmentConfig {
    
    /// 从环境变量加载完整配置
    /// - Returns: 加载的配置值字典
    public func loadAll() -> [String: String] {
        var result: [String: String] = [:]
        
        // 添加自定义变量
        result.merge(customVariables) { _, new in new }
        
        // 从系统环境变量加载
        if loadFromEnvironment {
            let env = ProcessInfo.processInfo.environment
            for (key, value) in env where key.hasPrefix(prefix) {
                let shortKey = String(key.dropFirst(prefix.count))
                result[shortKey] = value
            }
        }
        
        return result
    }
}
