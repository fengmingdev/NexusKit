//
//  DashboardServer.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Dashboard Server

/// 监控面板服务器 - 统一的监控数据服务
public actor DashboardServer {
    
    // MARK: - Singleton
    
    public static let shared = DashboardServer()
    
    // MARK: - Properties
    
    private let configuration: DashboardConfiguration
    private let aggregator: MetricsAggregator
    private let stream: RealtimeStream
    private var isRunning = false
    private var startTime: Date?
    
    // MARK: - Initialization
    
    public init(configuration: DashboardConfiguration = .production) {
        self.configuration = configuration
        self.aggregator = MetricsAggregator(configuration: configuration)
        self.stream = RealtimeStream(configuration: configuration, aggregator: aggregator)
    }
    
    // MARK: - Server Control
    
    /// 启动监控服务器
    public func start() {
        guard !isRunning else { return }
        
        isRunning = true
        startTime = Date()
        
        // 启动实时数据流
        Task {
            await stream.startStreaming()
        }
    }
    
    /// 停止监控服务器
    public func stop() {
        guard isRunning else { return }
        
        isRunning = false
        
        Task {
            await stream.stopStreaming()
        }
    }
    
    /// 服务器是否运行中
    public func isServerRunning() -> Bool {
        isRunning
    }
    
    // MARK: - Metrics Recording
    
    /// 记录连接指标
    public func recordConnection(
        id: String,
        bytesReceived: Int64 = 0,
        bytesSent: Int64 = 0,
        messagesReceived: Int64 = 0,
        messagesSent: Int64 = 0,
        latency: Double = 0
    ) async {
        await aggregator.recordConnectionMetric(
            connectionId: id,
            bytesReceived: bytesReceived,
            bytesSent: bytesSent,
            messagesReceived: messagesReceived,
            messagesSent: messagesSent,
            latency: latency
        )
    }
    
    /// 更新连接状态
    public func updateConnectionStatus(id: String, status: ConnectionStatus) async {
        await aggregator.updateConnectionStatus(connectionId: id, status: status)
    }
    
    /// 移除连接
    public func removeConnection(id: String) async {
        await aggregator.removeConnection(connectionId: id)
    }
    
    /// 记录系统快照
    public func recordSystemSnapshot(
        cpuUsage: Double,
        memoryUsage: Int64,
        activeConnections: Int,
        totalThroughput: Double,
        errorRate: Double
    ) async {
        await aggregator.recordSystemSnapshot(
            cpuUsage: cpuUsage,
            memoryUsage: memoryUsage,
            activeConnections: activeConnections,
            totalThroughput: totalThroughput,
            errorRate: errorRate
        )
    }
    
    // MARK: - Data Access
    
    /// 获取当前聚合数据
    public func getCurrentMetrics() async -> AggregatedMetrics {
        await aggregator.aggregate()
    }
    
    /// 获取概览数据
    public func getOverview() async -> OverviewMetrics {
        let metrics = await aggregator.aggregate()
        return metrics.overview
    }
    
    /// 获取连接列表
    public func getConnections() async -> [ConnectionSummary] {
        let metrics = await aggregator.aggregate()
        return metrics.connections
    }
    
    /// 获取性能图表数据
    public func getPerformanceData() async -> PerformanceChartData {
        let metrics = await aggregator.aggregate()
        return metrics.performance
    }
    
    /// 获取健康状态
    public func getHealth() async -> HealthMetrics {
        let metrics = await aggregator.aggregate()
        return metrics.health
    }
    
    /// 获取指定连接的详细信息
    public func getConnectionDetails(id: String) async -> ConnectionMetrics? {
        await aggregator.getConnectionDetails(connectionId: id)
    }
    
    // MARK: - Subscription Management
    
    /// 订阅实时数据流
    public func subscribe(
        id: String,
        handler: @escaping @Sendable (AggregatedMetrics) async -> Void
    ) async -> Bool {
        await stream.subscribe(id: id, handler: handler)
    }
    
    /// 取消订阅
    public func unsubscribe(id: String) async {
        await stream.unsubscribe(id: id)
    }
    
    /// 获取订阅者数量
    public func getSubscriberCount() async -> Int {
        await stream.getSubscriberCount()
    }
    
    // MARK: - Export
    
    /// 导出当前监控数据为 JSON
    public func exportJSON() async throws -> Data {
        let metrics = await aggregator.aggregate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(metrics)
    }
    
    /// 导出当前监控数据为文本报告
    public func exportTextReport() async -> String {
        let metrics = await aggregator.aggregate()
        return formatTextReport(metrics)
    }
    
    /// 保存监控数据到文件
    public func saveSnapshot(to url: URL, format: DashboardExportFormat = .json) async throws {
        let data: Data
        
        switch format {
        case .json:
            data = try await exportJSON()
        case .text:
            data = await exportTextReport().data(using: .utf8) ?? Data()
        }
        
        try data.write(to: url)
    }
    
    // MARK: - Statistics
    
    /// 获取服务器统计信息
    public func getStatistics() async -> DashboardStatistics {
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let subscriberCount = await stream.getSubscriberCount()
        let connections = await aggregator.getAllConnections()
        let metrics = await aggregator.aggregate()
        
        return DashboardStatistics(
            isRunning: isRunning,
            uptime: uptime,
            subscriberCount: subscriberCount,
            totalConnections: connections.count,
            activeConnections: connections.filter { $0.status == .connected }.count,
            totalMessagesProcessed: metrics.overview.totalMessages,
            totalBytesTransferred: metrics.overview.totalBytes,
            averageLatency: metrics.overview.averageLatency,
            currentCPU: metrics.health.cpuUsage,
            currentMemory: metrics.health.memoryUsage
        )
    }
    
    /// 重置所有监控数据
    public func reset() async {
        await aggregator.reset()
    }
    
    // MARK: - Private Methods
    
    private func formatTextReport(_ metrics: AggregatedMetrics) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        
        var report = """
        # NexusKit Dashboard Report
        Generated: \(formatter.string(from: metrics.timestamp))
        
        ## Overview
        - Active Connections: \(metrics.overview.activeConnections)
        - Total Connections: \(metrics.overview.totalConnections)
        - Messages/sec: \(String(format: "%.2f", metrics.overview.messagesPerSecond))
        - Average Latency: \(String(format: "%.2f", metrics.overview.averageLatency)) ms
        - Error Rate: \(String(format: "%.2f", metrics.overview.errorRate))%
        - Total Messages: \(metrics.overview.totalMessages)
        - Total Bytes: \(formatBytes(metrics.overview.totalBytes))
        
        ## Health
        - Status: \(metrics.health.status)
        - CPU Usage: \(String(format: "%.2f", metrics.health.cpuUsage))%
        - Memory Usage: \(formatBytes(metrics.health.memoryUsage))
        - Active Connections: \(metrics.health.activeConnections)
        - Error Rate: \(String(format: "%.2f", metrics.health.errorRate))%
        
        ## Top Connections
        """
        
        for (index, conn) in metrics.connections.prefix(10).enumerated() {
            report += """
            
            \(index + 1). \(conn.connectionId) [\(conn.status.rawValue)]
               - Uptime: \(formatDuration(conn.uptime))
               - Throughput: \(String(format: "%.2f", conn.throughput)) msg/s
               - Avg Latency: \(String(format: "%.2f", conn.averageLatency)) ms
               - Messages: ↓\(conn.messagesReceived) ↑\(conn.messagesSent)
               - Bytes: ↓\(formatBytes(conn.bytesReceived)) ↑\(formatBytes(conn.bytesSent))
            """
        }
        
        report += """
        
        
        ## History
        - Data Points: \(metrics.history.dataPoints)
        - Time Range: \(formatter.string(from: metrics.history.startTime)) - \(formatter.string(from: metrics.history.endTime))
        - Sample Interval: \(String(format: "%.1f", metrics.history.sampleInterval))s
        """
        
        return report
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

// MARK: - Dashboard Export Format

/// 监控面板导出格式
public enum DashboardExportFormat: String, Sendable {
    case json
    case text
}

// MARK: - Dashboard Statistics

/// 监控面板统计信息
public struct DashboardStatistics: Sendable, Codable {
    public let isRunning: Bool
    public let uptime: TimeInterval
    public let subscriberCount: Int
    public let totalConnections: Int
    public let activeConnections: Int
    public let totalMessagesProcessed: Int64
    public let totalBytesTransferred: Int64
    public let averageLatency: Double
    public let currentCPU: Double
    public let currentMemory: Int64
}
