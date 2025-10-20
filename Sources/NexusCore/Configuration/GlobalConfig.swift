//
//  GlobalConfig.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 全局配置
///
/// 控制 NexusKit 的全局行为，包括日志、调试、性能等。
public struct GlobalConfig: Sendable {
    
    // MARK: - Logging
    
    /// 日志级别
    public var logLevel: NexusLogLevel
    
    /// 是否启用详细日志
    public var verboseLogging: Bool
    
    // MARK: - Performance
    
    /// 默认缓冲区大小 (bytes)
    public var defaultBufferSize: Int
    
    /// 是否启用性能监控
    public var enableMetrics: Bool
    
    /// 性能指标采样间隔 (seconds)
    public var metricsInterval: TimeInterval
    
    // MARK: - Debug
    
    /// 是否启用调试模式
    public var debugMode: Bool
    
    /// 是否打印网络流量
    public var printTraffic: Bool
    
    // MARK: - Concurrency
    
    /// 最大并发连接数
    public var maxConcurrentConnections: Int
    
    /// 全局任务优先级
    public var taskPriority: TaskPriority
    
    // MARK: - Initialization
    
    /// 初始化全局配置
    public init(
        logLevel: NexusLogLevel = .info,
        verboseLogging: Bool = false,
        defaultBufferSize: Int = 8192,
        enableMetrics: Bool = false,
        metricsInterval: TimeInterval = 60,
        debugMode: Bool = false,
        printTraffic: Bool = false,
        maxConcurrentConnections: Int = 100,
        taskPriority: TaskPriority = .medium
    ) {
        self.logLevel = logLevel
        self.verboseLogging = verboseLogging
        self.defaultBufferSize = defaultBufferSize
        self.enableMetrics = enableMetrics
        self.metricsInterval = metricsInterval
        self.debugMode = debugMode
        self.printTraffic = printTraffic
        self.maxConcurrentConnections = maxConcurrentConnections
        self.taskPriority = taskPriority
    }
    
    // MARK: - Defaults
    
    /// 默认配置
    public static let `default` = GlobalConfig()
    
    /// 调试配置
    public static let debug = GlobalConfig(
        logLevel: .debug,
        verboseLogging: true,
        debugMode: true,
        printTraffic: true
    )
    
    /// 生产配置
    public static let production = GlobalConfig(
        logLevel: .warning,
        verboseLogging: false,
        enableMetrics: true,
        debugMode: false,
        printTraffic: false
    )
    
    // MARK: - Validation
    
    /// 验证配置有效性
    public func validate() throws {
        guard defaultBufferSize > 0 else {
            throw ConfigurationError.invalidBufferSize(defaultBufferSize)
        }
        
        guard metricsInterval > 0 else {
            throw ConfigurationError.invalidHeartbeatInterval(metricsInterval)
        }
        
        guard maxConcurrentConnections > 0 else {
            throw ConfigurationError.invalidRetryCount(maxConcurrentConnections)
        }
    }
}

// MARK: - Log Level

/// 日志级别
public enum NexusLogLevel: String, Sendable, CaseIterable {
    case verbose = "VERBOSE"
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case none = "NONE"
    
    /// 优先级 (数字越大优先级越高)
    public var priority: Int {
        switch self {
        case .verbose: return 0
        case .debug: return 1
        case .info: return 2
        case .warning: return 3
        case .error: return 4
        case .none: return 5
        }
    }
    
    /// 是否应该输出日志
    public func shouldLog(level: NexusLogLevel) -> Bool {
        return level.priority >= self.priority
    }
}

// MARK: - CustomStringConvertible

extension GlobalConfig: CustomStringConvertible {
    public var description: String {
        """
        GlobalConfig(
            logLevel: \(logLevel.rawValue),
            bufferSize: \(defaultBufferSize),
            metrics: \(enableMetrics),
            debug: \(debugMode),
            maxConnections: \(maxConcurrentConnections)
        )
        """
    }
}
