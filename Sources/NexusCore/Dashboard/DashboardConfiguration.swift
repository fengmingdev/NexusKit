//
//  DashboardConfiguration.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Dashboard Configuration

/// 监控面板配置
public struct DashboardConfiguration: Sendable {
    /// 推送间隔（秒）
    public let updateInterval: TimeInterval
    
    /// 历史数据保留时长（秒）
    public let historyRetention: TimeInterval
    
    /// 最大历史数据点数
    public let maxHistoryPoints: Int
    
    /// 启用的面板功能
    public let enabledFeatures: DashboardFeatures
    
    /// 数据聚合间隔（秒）
    public let aggregationInterval: TimeInterval
    
    /// 推送模式
    public let pushMode: PushMode
    
    /// 最大并发客户端数
    public let maxClients: Int
    
    /// 是否启用压缩
    public let enableCompression: Bool
    
    /// 是否包含详细指标
    public let includeDetailedMetrics: Bool
    
    public init(
        updateInterval: TimeInterval = 1.0,
        historyRetention: TimeInterval = 3600,
        maxHistoryPoints: Int = 1000,
        enabledFeatures: DashboardFeatures = .all,
        aggregationInterval: TimeInterval = 1.0,
        pushMode: PushMode = .websocket,
        maxClients: Int = 100,
        enableCompression: Bool = true,
        includeDetailedMetrics: Bool = true
    ) {
        self.updateInterval = updateInterval
        self.historyRetention = historyRetention
        self.maxHistoryPoints = maxHistoryPoints
        self.enabledFeatures = enabledFeatures
        self.aggregationInterval = aggregationInterval
        self.pushMode = pushMode
        self.maxClients = maxClients
        self.enableCompression = enableCompression
        self.includeDetailedMetrics = includeDetailedMetrics
    }
}

// MARK: - Dashboard Features

/// 监控面板功能集
public struct DashboardFeatures: OptionSet, Sendable {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// 概览面板
    public static let overview = DashboardFeatures(rawValue: 1 << 0)
    
    /// 连接列表
    public static let connections = DashboardFeatures(rawValue: 1 << 1)
    
    /// 性能图表
    public static let performance = DashboardFeatures(rawValue: 1 << 2)
    
    /// 健康状态
    public static let health = DashboardFeatures(rawValue: 1 << 3)
    
    /// 错误日志
    public static let errors = DashboardFeatures(rawValue: 1 << 4)
    
    /// 追踪视图
    public static let tracing = DashboardFeatures(rawValue: 1 << 5)
    
    /// 所有功能
    public static let all: DashboardFeatures = [
        .overview, .connections, .performance, .health, .errors, .tracing
    ]
}

// MARK: - Push Mode

/// 数据推送模式
public enum PushMode: String, Sendable, Codable {
    /// WebSocket 推送
    case websocket
    
    /// Server-Sent Events
    case sse
    
    /// 轮询模式
    case polling
}

// MARK: - Predefined Configurations

extension DashboardConfiguration {
    /// 开发环境配置（高频更新）
    public static let development = DashboardConfiguration(
        updateInterval: 0.5,
        historyRetention: 1800,
        maxHistoryPoints: 500,
        enabledFeatures: .all,
        aggregationInterval: 0.5,
        pushMode: .websocket,
        maxClients: 10,
        enableCompression: false,
        includeDetailedMetrics: true
    )
    
    /// 生产环境配置（平衡性能）
    public static let production = DashboardConfiguration(
        updateInterval: 5.0,
        historyRetention: 7200,
        maxHistoryPoints: 2000,
        enabledFeatures: [.overview, .connections, .performance, .health],
        aggregationInterval: 5.0,
        pushMode: .websocket,
        maxClients: 100,
        enableCompression: true,
        includeDetailedMetrics: false
    )
    
    /// 高性能配置（低开销）
    public static let highPerformance = DashboardConfiguration(
        updateInterval: 10.0,
        historyRetention: 3600,
        maxHistoryPoints: 500,
        enabledFeatures: [.overview, .health],
        aggregationInterval: 10.0,
        pushMode: .polling,
        maxClients: 50,
        enableCompression: true,
        includeDetailedMetrics: false
    )
    
    /// 详细监控配置（完整信息）
    public static let detailed = DashboardConfiguration(
        updateInterval: 1.0,
        historyRetention: 14400,
        maxHistoryPoints: 5000,
        enabledFeatures: .all,
        aggregationInterval: 1.0,
        pushMode: .websocket,
        maxClients: 50,
        enableCompression: true,
        includeDetailedMetrics: true
    )
}
