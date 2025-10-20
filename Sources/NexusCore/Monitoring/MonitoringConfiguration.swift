//
//  MonitoringConfiguration.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Monitoring Configuration

/// 监控配置
public struct MonitoringConfiguration: Sendable {
    
    /// 是否启用监控
    public let enabled: Bool
    
    /// 采样率 (0.0 - 1.0)
    public let samplingRate: Double
    
    /// 指标收集间隔
    public let collectionInterval: TimeInterval
    
    /// 历史数据保留时间
    public let retentionPeriod: TimeInterval
    
    /// 启用的指标类别
    public let enabledMetrics: MetricCategories
    
    /// 导出配置
    public let exportConfiguration: ExportConfiguration
    
    /// 性能预算
    public let performanceBudget: PerformanceBudget
    
    // MARK: - Initialization
    
    public init(
        enabled: Bool = true,
        samplingRate: Double = 1.0,
        collectionInterval: TimeInterval = 5.0,
        retentionPeriod: TimeInterval = 3600.0, // 1 hour
        enabledMetrics: MetricCategories = .all,
        exportConfiguration: ExportConfiguration = .default,
        performanceBudget: PerformanceBudget = .default
    ) {
        self.enabled = enabled
        self.samplingRate = max(0.0, min(1.0, samplingRate))
        self.collectionInterval = max(1.0, collectionInterval)
        self.retentionPeriod = max(60.0, retentionPeriod)
        self.enabledMetrics = enabledMetrics
        self.exportConfiguration = exportConfiguration
        self.performanceBudget = performanceBudget
    }
    
    // MARK: - Presets
    
    /// 禁用监控
    public static let disabled = MonitoringConfiguration(enabled: false)
    
    /// 开发环境配置
    public static let development = MonitoringConfiguration(
        enabled: true,
        samplingRate: 1.0,
        collectionInterval: 1.0,
        retentionPeriod: 600.0
    )
    
    /// 生产环境配置
    public static let production = MonitoringConfiguration(
        enabled: true,
        samplingRate: 0.1,
        collectionInterval: 10.0,
        retentionPeriod: 7200.0
    )
    
    /// 高频监控配置
    public static let highFrequency = MonitoringConfiguration(
        enabled: true,
        samplingRate: 1.0,
        collectionInterval: 0.5,
        retentionPeriod: 300.0
    )
}

// MARK: - Metric Categories

/// 指标类别
public struct MetricCategories: OptionSet, Sendable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    /// 连接指标
    public static let connection = MetricCategories(rawValue: 1 << 0)
    
    /// 性能指标
    public static let performance = MetricCategories(rawValue: 1 << 1)
    
    /// 资源指标
    public static let resource = MetricCategories(rawValue: 1 << 2)
    
    /// 错误指标
    public static let error = MetricCategories(rawValue: 1 << 3)
    
    /// 网络指标
    public static let network = MetricCategories(rawValue: 1 << 4)
    
    /// 缓冲区指标
    public static let buffer = MetricCategories(rawValue: 1 << 5)
    
    /// 所有指标
    public static let all: MetricCategories = [
        .connection, .performance, .resource,
        .error, .network, .buffer
    ]
    
    /// 基础指标
    public static let basic: MetricCategories = [
        .connection, .performance, .error
    ]
}

// MARK: - Export Configuration

/// 导出配置
public struct ExportConfiguration: Sendable {
    
    /// 导出格式
    public let formats: Set<ExportFormat>
    
    /// 导出间隔
    public let exportInterval: TimeInterval
    
    /// 导出路径
    public let exportPath: String?
    
    /// 是否自动导出
    public let autoExport: Bool
    
    public init(
        formats: Set<ExportFormat> = [.json],
        exportInterval: TimeInterval = 60.0,
        exportPath: String? = nil,
        autoExport: Bool = false
    ) {
        self.formats = formats
        self.exportInterval = exportInterval
        self.exportPath = exportPath
        self.autoExport = autoExport
    }
    
    public static let `default` = ExportConfiguration()
}

/// 导出格式
public enum ExportFormat: String, Sendable, Hashable {
    case json
    case prometheus
    case csv
    case markdown
}

// MARK: - Performance Budget

/// 性能预算
public struct PerformanceBudget: Sendable {
    
    /// 最大 CPU 使用率 (0.0 - 1.0)
    public let maxCPUUsage: Double
    
    /// 最大内存占用 (bytes)
    public let maxMemoryUsage: Int
    
    /// 最大采集延迟 (seconds)
    public let maxCollectionLatency: TimeInterval
    
    public init(
        maxCPUUsage: Double = 0.01, // 1%
        maxMemoryUsage: Int = 10 * 1024 * 1024, // 10MB
        maxCollectionLatency: TimeInterval = 0.1 // 100ms
    ) {
        self.maxCPUUsage = max(0.0, min(1.0, maxCPUUsage))
        self.maxMemoryUsage = max(0, maxMemoryUsage)
        self.maxCollectionLatency = max(0.0, maxCollectionLatency)
    }
    
    public static let `default` = PerformanceBudget()
    
    public static let strict = PerformanceBudget(
        maxCPUUsage: 0.005, // 0.5%
        maxMemoryUsage: 5 * 1024 * 1024, // 5MB
        maxCollectionLatency: 0.05 // 50ms
    )
    
    public static let relaxed = PerformanceBudget(
        maxCPUUsage: 0.02, // 2%
        maxMemoryUsage: 20 * 1024 * 1024, // 20MB
        maxCollectionLatency: 0.2 // 200ms
    )
}
