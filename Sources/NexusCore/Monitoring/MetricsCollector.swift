//
//  MetricsCollector.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Metrics Collector

/// 指标收集器 - 收集和管理所有性能指标
public actor MetricsCollector {
    
    // MARK: - Properties
    
    private let configuration: MonitoringConfiguration
    private var metrics: [String: Metric] = [:]
    private var timeSeries: [String: TimeSeries] = [:]
    private var lastCollectionTime: Date?
    
    // MARK: - Initialization
    
    public init(configuration: MonitoringConfiguration = .development) {
        self.configuration = configuration
    }
    
    // MARK: - Metric Recording
    
    /// 记录计数器指标
    public func recordCounter(_ name: String, value: Int64, tags: [String: String] = [:]) {
        guard configuration.enabled, shouldSample() else { return }
        
        let metric = Metric(
            name: name,
            type: .counter,
            value: .integer(value),
            tags: tags,
            timestamp: Date()
        )
        
        metrics[name] = metric
        appendToTimeSeries(name: name, value: Double(value))
    }
    
    /// 记录计量器指标
    public func recordGauge(_ name: String, value: Double, tags: [String: String] = [:]) {
        guard configuration.enabled, shouldSample() else { return }
        
        let metric = Metric(
            name: name,
            type: .gauge,
            value: .double(value),
            tags: tags,
            timestamp: Date()
        )
        
        metrics[name] = metric
        appendToTimeSeries(name: name, value: value)
    }
    
    /// 记录直方图指标
    public func recordHistogram(_ name: String, value: Double, tags: [String: String] = [:]) {
        guard configuration.enabled, shouldSample() else { return }
        
        let metric = Metric(
            name: name,
            type: .histogram,
            value: .double(value),
            tags: tags,
            timestamp: Date()
        )
        
        metrics[name] = metric
        appendToTimeSeries(name: name, value: value)
    }
    
    /// 记录定时器指标 (纳秒)
    public func recordTiming(_ name: String, nanoseconds: UInt64, tags: [String: String] = [:]) {
        let milliseconds = Double(nanoseconds) / 1_000_000.0
        recordHistogram(name, value: milliseconds, tags: tags)
    }
    
    // MARK: - Query
    
    /// 获取指标
    public func getMetric(_ name: String) -> Metric? {
        metrics[name]
    }
    
    /// 获取所有指标
    public func getAllMetrics() -> [Metric] {
        Array(metrics.values)
    }
    
    /// 获取时间序列数据
    public func getTimeSeries(_ name: String) -> TimeSeries? {
        timeSeries[name]
    }
    
    /// 获取统计摘要
    public func getSummary() -> MonitoringMetricsSummary {
        MonitoringMetricsSummary(
            totalMetrics: metrics.count,
            lastCollectionTime: lastCollectionTime,
            metrics: getAllMetrics(),
            timeSeries: Array(timeSeries.values)
        )
    }
    
    // MARK: - Cleanup
    
    /// 清理过期数据
    public func cleanup() {
        let cutoffTime = Date().addingTimeInterval(-configuration.retentionPeriod)
        
        // 清理过期指标
        metrics = metrics.filter { $0.value.timestamp > cutoffTime }
        
        // 清理时间序列
        for (name, series) in timeSeries {
            timeSeries[name] = series.filtered(after: cutoffTime)
        }
    }
    
    /// 重置所有指标
    public func reset() {
        metrics.removeAll()
        timeSeries.removeAll()
        lastCollectionTime = nil
    }
    
    // MARK: - Private Methods
    
    private func shouldSample() -> Bool {
        Double.random(in: 0..<1.0) < configuration.samplingRate
    }
    
    private func appendToTimeSeries(name: String, value: Double) {
        var series = timeSeries[name] ?? TimeSeries(name: name)
        series.append(value: value, timestamp: Date())
        timeSeries[name] = series
    }
}

// MARK: - Metric

/// 指标
public struct Metric: Sendable, Codable {
    /// 指标名称
    public let name: String
    
    /// 指标类型
    public let type: MetricType
    
    /// 指标值
    public let value: MetricValue
    
    /// 标签
    public let tags: [String: String]
    
    /// 时间戳
    public let timestamp: Date
    
    public init(
        name: String,
        type: MetricType,
        value: MetricValue,
        tags: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.name = name
        self.type = type
        self.value = value
        self.tags = tags
        self.timestamp = timestamp
    }
}

/// 指标类型
public enum MetricType: String, Sendable, Codable {
    case counter    // 计数器
    case gauge      // 计量器
    case histogram  // 直方图
    case timer      // 定时器
}

/// 指标值
public enum MetricValue: Sendable, Codable {
    case integer(Int64)
    case double(Double)
    
    public var doubleValue: Double {
        switch self {
        case .integer(let value):
            return Double(value)
        case .double(let value):
            return value
        }
    }
}

// MARK: - Time Series

/// 时间序列数据
public struct TimeSeries: Sendable {
    public let name: String
    public private(set) var dataPoints: [DataPoint]
    
    public init(name: String, dataPoints: [DataPoint] = []) {
        self.name = name
        self.dataPoints = dataPoints
    }
    
    public mutating func append(value: Double, timestamp: Date) {
        dataPoints.append(DataPoint(value: value, timestamp: timestamp))
    }
    
    public func filtered(after cutoffTime: Date) -> TimeSeries {
        TimeSeries(
            name: name,
            dataPoints: dataPoints.filter { $0.timestamp > cutoffTime }
        )
    }
    
    public struct DataPoint: Sendable {
        public let value: Double
        public let timestamp: Date
    }
}

// MARK: - Monitoring Metrics Summary

/// 监控指标摘要
public struct MonitoringMetricsSummary: Sendable, Codable {
    public let totalMetrics: Int
    public let lastCollectionTime: Date?
    public let metrics: [Metric]
    public let timeSeries: [TimeSeriesData]
    
    init(totalMetrics: Int, lastCollectionTime: Date?, metrics: [Metric], timeSeries: [TimeSeries]) {
        self.totalMetrics = totalMetrics
        self.lastCollectionTime = lastCollectionTime
        self.metrics = metrics
        self.timeSeries = timeSeries.map { TimeSeriesData(name: $0.name, dataPoints: $0.dataPoints) }
    }
    
    public struct TimeSeriesData: Sendable, Codable {
        public let name: String
        public let dataPoints: [DataPointData]
        
        public struct DataPointData: Sendable, Codable {
            public let value: Double
            public let timestamp: Date
        }
        
        init(name: String, dataPoints: [TimeSeries.DataPoint]) {
            self.name = name
            self.dataPoints = dataPoints.map { DataPointData(value: $0.value, timestamp: $0.timestamp) }
        }
    }
}
