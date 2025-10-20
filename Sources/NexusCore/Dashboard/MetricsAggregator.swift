//
//  MetricsAggregator.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Metrics Aggregator

/// 指标聚合器 - 聚合和计算监控指标
public actor MetricsAggregator {
    
    // MARK: - Properties
    
    private let configuration: DashboardConfiguration
    private var connectionMetrics: [String: ConnectionMetrics] = [:]
    private var systemMetrics: [SystemMetricsSnapshot] = []
    private var aggregatedData: AggregatedMetrics?
    private var lastAggregationTime: Date?
    
    // MARK: - Initialization
    
    public init(configuration: DashboardConfiguration = .production) {
        self.configuration = configuration
    }
    
    // MARK: - Public Methods
    
    /// 记录连接指标
    public func recordConnectionMetric(
        connectionId: String,
        bytesReceived: Int64,
        bytesSent: Int64,
        messagesReceived: Int64,
        messagesSent: Int64,
        latency: Double
    ) {
        var metrics = connectionMetrics[connectionId] ?? ConnectionMetrics(
            connectionId: connectionId,
            startTime: Date()
        )
        
        metrics.bytesReceived += bytesReceived
        metrics.bytesSent += bytesSent
        metrics.messagesReceived += messagesReceived
        metrics.messagesSent += messagesSent
        metrics.latencies.append(latency)
        metrics.lastUpdateTime = Date()
        
        // 限制延迟历史大小
        if metrics.latencies.count > 100 {
            metrics.latencies.removeFirst(metrics.latencies.count - 100)
        }
        
        connectionMetrics[connectionId] = metrics
    }
    
    /// 记录连接状态变更
    public func updateConnectionStatus(connectionId: String, status: ConnectionStatus) {
        var metrics = connectionMetrics[connectionId] ?? ConnectionMetrics(
            connectionId: connectionId,
            startTime: Date()
        )
        metrics.status = status
        connectionMetrics[connectionId] = metrics
    }
    
    /// 移除连接指标
    public func removeConnection(connectionId: String) {
        connectionMetrics.removeValue(forKey: connectionId)
    }
    
    /// 记录系统指标快照
    public func recordSystemSnapshot(
        cpuUsage: Double,
        memoryUsage: Int64,
        activeConnections: Int,
        totalThroughput: Double,
        errorRate: Double
    ) {
        let snapshot = SystemMetricsSnapshot(
            timestamp: Date(),
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            activeConnections: activeConnections,
            totalThroughput: totalThroughput,
            errorRate: errorRate
        )
        
        systemMetrics.append(snapshot)
        
        // 清理过期数据
        let cutoffTime = Date().addingTimeInterval(-configuration.historyRetention)
        systemMetrics.removeAll { $0.timestamp < cutoffTime }
        
        // 限制历史点数
        if systemMetrics.count > configuration.maxHistoryPoints {
            systemMetrics.removeFirst(systemMetrics.count - configuration.maxHistoryPoints)
        }
    }
    
    /// 聚合指标数据
    public func aggregate() -> AggregatedMetrics {
        let now = Date()
        
        // 如果最近刚聚合过，返回缓存结果
        if let lastTime = lastAggregationTime,
           let cached = aggregatedData,
           now.timeIntervalSince(lastTime) < configuration.aggregationInterval {
            return cached
        }
        
        let metrics = AggregatedMetrics(
            timestamp: now,
            overview: calculateOverview(),
            connections: calculateConnectionMetrics(),
            performance: calculatePerformanceMetrics(),
            health: calculateHealthMetrics(),
            history: calculateHistoryMetrics()
        )
        
        aggregatedData = metrics
        lastAggregationTime = now
        
        return metrics
    }
    
    /// 获取指定连接的详细指标
    public func getConnectionDetails(connectionId: String) -> ConnectionMetrics? {
        connectionMetrics[connectionId]
    }
    
    /// 获取所有连接列表
    public func getAllConnections() -> [ConnectionMetrics] {
        Array(connectionMetrics.values).sorted { $0.startTime < $1.startTime }
    }
    
    /// 清理所有数据
    public func reset() {
        connectionMetrics.removeAll()
        systemMetrics.removeAll()
        aggregatedData = nil
        lastAggregationTime = nil
    }
    
    // MARK: - Private Methods
    
    private func calculateOverview() -> OverviewMetrics {
        let activeConnections = connectionMetrics.values.filter { $0.status == .connected }.count
        
        let totalMessages = connectionMetrics.values.reduce(0) { sum, metrics in
            sum + metrics.messagesReceived + metrics.messagesSent
        }
        
        let totalBytes = connectionMetrics.values.reduce(0) { sum, metrics in
            sum + metrics.bytesReceived + metrics.bytesSent
        }
        
        let avgLatency = calculateAverageLatency()
        let errorRate = calculateErrorRate()
        let messagesPerSecond = calculateMessagesPerSecond()
        
        return OverviewMetrics(
            activeConnections: activeConnections,
            totalConnections: connectionMetrics.count,
            messagesPerSecond: messagesPerSecond,
            averageLatency: avgLatency,
            errorRate: errorRate,
            totalMessages: totalMessages,
            totalBytes: totalBytes
        )
    }
    
    private func calculateConnectionMetrics() -> [ConnectionSummary] {
        connectionMetrics.values.map { metrics in
            let throughput = calculateThroughput(for: metrics)
            let avgLatency = metrics.latencies.isEmpty ? 0 :
                metrics.latencies.reduce(0, +) / Double(metrics.latencies.count)
            
            return ConnectionSummary(
                connectionId: metrics.connectionId,
                status: metrics.status,
                uptime: Date().timeIntervalSince(metrics.startTime),
                throughput: throughput,
                averageLatency: avgLatency,
                messagesReceived: metrics.messagesReceived,
                messagesSent: metrics.messagesSent,
                bytesReceived: metrics.bytesReceived,
                bytesSent: metrics.bytesSent
            )
        }.sorted { $0.throughput > $1.throughput }
    }
    
    private func calculatePerformanceMetrics() -> PerformanceChartData {
        let recentSnapshots = systemMetrics.suffix(100)
        
        return PerformanceChartData(
            throughputHistory: recentSnapshots.map { $0.totalThroughput },
            latencyHistory: calculateLatencyHistory(),
            memoryHistory: recentSnapshots.map { Double($0.memoryUsage) / 1024 / 1024 },
            cpuHistory: recentSnapshots.map { $0.cpuUsage },
            timestamps: recentSnapshots.map { $0.timestamp }
        )
    }
    
    private func calculateHealthMetrics() -> HealthMetrics {
        let latestSnapshot = systemMetrics.last
        
        return HealthMetrics(
            cpuUsage: latestSnapshot?.cpuUsage ?? 0,
            memoryUsage: latestSnapshot?.memoryUsage ?? 0,
            activeConnections: latestSnapshot?.activeConnections ?? 0,
            errorRate: latestSnapshot?.errorRate ?? 0,
            status: determineHealthStatus()
        )
    }
    
    private func calculateHistoryMetrics() -> HistoryMetrics {
        HistoryMetrics(
            dataPoints: systemMetrics.count,
            startTime: systemMetrics.first?.timestamp ?? Date(),
            endTime: systemMetrics.last?.timestamp ?? Date(),
            sampleInterval: configuration.aggregationInterval
        )
    }
    
    private func calculateAverageLatency() -> Double {
        var allLatencies: [Double] = []
        for metrics in connectionMetrics.values {
            allLatencies.append(contentsOf: metrics.latencies)
        }
        
        guard !allLatencies.isEmpty else { return 0 }
        return allLatencies.reduce(0, +) / Double(allLatencies.count)
    }
    
    private func calculateErrorRate() -> Double {
        systemMetrics.last?.errorRate ?? 0
    }
    
    private func calculateMessagesPerSecond() -> Double {
        guard !systemMetrics.isEmpty else { return 0 }
        
        let recent = systemMetrics.suffix(10)
        guard recent.count > 1 else { return 0 }
        
        let totalMessages = connectionMetrics.values.reduce(0) { sum, metrics in
            sum + metrics.messagesReceived + metrics.messagesSent
        }
        
        let timeSpan = recent.last!.timestamp.timeIntervalSince(recent.first!.timestamp)
        guard timeSpan > 0 else { return 0 }
        
        return Double(totalMessages) / timeSpan
    }
    
    private func calculateThroughput(for metrics: ConnectionMetrics) -> Double {
        let uptime = Date().timeIntervalSince(metrics.startTime)
        guard uptime > 0 else { return 0 }
        
        let totalMessages = metrics.messagesReceived + metrics.messagesSent
        return Double(totalMessages) / uptime
    }
    
    private func calculateLatencyHistory() -> [Double] {
        // 从系统快照中获取延迟历史
        // 这里简化实现，使用当前连接的平均延迟
        systemMetrics.suffix(100).map { _ in
            calculateAverageLatency()
        }
    }
    
    private func determineHealthStatus() -> String {
        guard let latest = systemMetrics.last else { return "unknown" }
        
        if latest.cpuUsage > 80 || latest.errorRate > 10 {
            return "critical"
        } else if latest.cpuUsage > 60 || latest.errorRate > 5 {
            return "warning"
        } else {
            return "healthy"
        }
    }
}

// MARK: - Connection Metrics

/// 连接指标
public struct ConnectionMetrics: Sendable {
    public let connectionId: String
    public let startTime: Date
    public var status: ConnectionStatus
    public var bytesReceived: Int64
    public var bytesSent: Int64
    public var messagesReceived: Int64
    public var messagesSent: Int64
    public var latencies: [Double]
    public var lastUpdateTime: Date
    
    public init(
        connectionId: String,
        startTime: Date,
        status: ConnectionStatus = .connected
    ) {
        self.connectionId = connectionId
        self.startTime = startTime
        self.status = status
        self.bytesReceived = 0
        self.bytesSent = 0
        self.messagesReceived = 0
        self.messagesSent = 0
        self.latencies = []
        self.lastUpdateTime = startTime
    }
}

// MARK: - Connection Status

/// 连接状态
public enum ConnectionStatus: String, Sendable, Codable {
    case connecting
    case connected
    case disconnecting
    case disconnected
    case error
}

// MARK: - System Metrics Snapshot

/// 系统指标快照
public struct SystemMetricsSnapshot: Sendable {
    public let timestamp: Date
    public let cpuUsage: Double
    public let memoryUsage: Int64
    public let activeConnections: Int
    public let totalThroughput: Double
    public let errorRate: Double
}

// MARK: - Aggregated Metrics

/// 聚合指标数据
public struct AggregatedMetrics: Sendable, Codable {
    public let timestamp: Date
    public let overview: OverviewMetrics
    public let connections: [ConnectionSummary]
    public let performance: PerformanceChartData
    public let health: HealthMetrics
    public let history: HistoryMetrics
}

// MARK: - Overview Metrics

/// 概览指标
public struct OverviewMetrics: Sendable, Codable {
    public let activeConnections: Int
    public let totalConnections: Int
    public let messagesPerSecond: Double
    public let averageLatency: Double
    public let errorRate: Double
    public let totalMessages: Int64
    public let totalBytes: Int64
}

// MARK: - Connection Summary

/// 连接摘要
public struct ConnectionSummary: Sendable, Codable {
    public let connectionId: String
    public let status: ConnectionStatus
    public let uptime: TimeInterval
    public let throughput: Double
    public let averageLatency: Double
    public let messagesReceived: Int64
    public let messagesSent: Int64
    public let bytesReceived: Int64
    public let bytesSent: Int64
}

// MARK: - Performance Chart Data

/// 性能图表数据
public struct PerformanceChartData: Sendable, Codable {
    public let throughputHistory: [Double]
    public let latencyHistory: [Double]
    public let memoryHistory: [Double]
    public let cpuHistory: [Double]
    public let timestamps: [Date]
}

// MARK: - Health Metrics

/// 健康指标
public struct HealthMetrics: Sendable, Codable {
    public let cpuUsage: Double
    public let memoryUsage: Int64
    public let activeConnections: Int
    public let errorRate: Double
    public let status: String
}

// MARK: - History Metrics

/// 历史指标元数据
public struct HistoryMetrics: Sendable, Codable {
    public let dataPoints: Int
    public let startTime: Date
    public let endTime: Date
    public let sampleInterval: TimeInterval
}
