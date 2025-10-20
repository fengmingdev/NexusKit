//
//  PerformanceMonitor.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Performance Monitor

/// 性能监控器 - 统一的性能监控入口
public actor PerformanceMonitor {
    
    // MARK: - Singleton
    
    public static let shared = PerformanceMonitor()
    
    // MARK: - Properties
    
    private let configuration: MonitoringConfiguration
    private let collector: MetricsCollector
    private var monitoringTask: Task<Void, Never>?
    private var isMonitoring = false
    
    // MARK: - Initialization
    
    public init(configuration: MonitoringConfiguration = .development) {
        self.configuration = configuration
        self.collector = MetricsCollector(configuration: configuration)
    }
    
    // MARK: - Control
    
    /// 开始监控
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        monitoringTask = Task {
            while !Task.isCancelled && isMonitoring {
                await collectMetrics()
                try? await Task.sleep(nanoseconds: UInt64(configuration.collectionInterval * 1_000_000_000))
            }
        }
    }
    
    /// 停止监控
    public func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    // MARK: - Metric Recording
    
    /// 记录连接建立时间
    public func recordConnectionEstablishment(duration: TimeInterval, endpoint: String) {
        Task {
            await collector.recordHistogram(
                "connection.establishment.duration",
                value: duration * 1000, // convert to ms
                tags: ["endpoint": endpoint]
            )
            await collector.recordCounter(
                "connection.total",
                value: 1,
                tags: ["endpoint": endpoint]
            )
        }
    }
    
    /// 记录消息发送
    public func recordMessageSent(bytes: Int, endpoint: String) {
        Task {
            await collector.recordCounter(
                "messages.sent.total",
                value: 1,
                tags: ["endpoint": endpoint]
            )
            await collector.recordCounter(
                "bytes.sent.total",
                value: Int64(bytes),
                tags: ["endpoint": endpoint]
            )
        }
    }
    
    /// 记录消息接收
    public func recordMessageReceived(bytes: Int, endpoint: String) {
        Task {
            await collector.recordCounter(
                "messages.received.total",
                value: 1,
                tags: ["endpoint": endpoint]
            )
            await collector.recordCounter(
                "bytes.received.total",
                value: Int64(bytes),
                tags: ["endpoint": endpoint]
            )
        }
    }
    
    /// 记录错误
    public func recordError(type: String, endpoint: String) {
        Task {
            await collector.recordCounter(
                "errors.total",
                value: 1,
                tags: ["type": type, "endpoint": endpoint]
            )
        }
    }
    
    /// 记录延迟
    public func recordLatency(duration: TimeInterval, endpoint: String) {
        Task {
            await collector.recordHistogram(
                "latency.duration",
                value: duration * 1000, // convert to ms
                tags: ["endpoint": endpoint]
            )
        }
    }
    
    // MARK: - Resource Monitoring
    
    /// 记录内存使用
    public func recordMemoryUsage(_ bytes: Int) {
        Task {
            await collector.recordGauge(
                "memory.usage",
                value: Double(bytes)
            )
        }
    }
    
    /// 记录 CPU 使用
    public func recordCPUUsage(_ percentage: Double) {
        Task {
            await collector.recordGauge(
                "cpu.usage",
                value: percentage
            )
        }
    }
    
    // MARK: - Query
    
    /// 获取性能摘要
    public func getPerformanceSummary() async -> PerformanceSummary {
        let metricsSummary = await collector.getSummary()
        
        return PerformanceSummary(
            totalConnections: await getMetricValue("connection.total"),
            totalMessagesSent: await getMetricValue("messages.sent.total"),
            totalMessagesReceived: await getMetricValue("messages.received.total"),
            totalBytesSent: await getMetricValue("bytes.sent.total"),
            totalBytesReceived: await getMetricValue("bytes.received.total"),
            totalErrors: await getMetricValue("errors.total"),
            averageLatency: await getAverageMetricValue("latency.duration"),
            memoryUsage: await getMetricValue("memory.usage"),
            cpuUsage: await getMetricValue("cpu.usage"),
            metricsSummary: metricsSummary
        )
    }
    
    /// 导出性能报告
    public func exportReport(format: ExportFormat = .json) async throws -> Data {
        let summary = await getPerformanceSummary()
        
        switch format {
        case .json:
            return try JSONEncoder().encode(summary)
        case .markdown:
            return generateMarkdownReport(summary: summary).data(using: .utf8) ?? Data()
        case .prometheus, .csv:
            // TODO: 实现其他格式
            return try JSONEncoder().encode(summary)
        }
    }
    
    // MARK: - Private Methods
    
    private func collectMetrics() async {
        // 收集系统资源指标
        await collectSystemMetrics()
        
        // 清理过期数据
        await collector.cleanup()
    }
    
    private func collectSystemMetrics() async {
        // 获取内存使用
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            await collector.recordGauge("memory.usage", value: Double(info.resident_size))
        }
    }
    
    private func getMetricValue(_ name: String) async -> Double {
        guard let metric = await collector.getMetric(name) else { return 0.0 }
        return metric.value.doubleValue
    }
    
    private func getAverageMetricValue(_ name: String) async -> Double {
        guard let timeSeries = await collector.getTimeSeries(name) else { return 0.0 }
        let values = timeSeries.dataPoints.map { $0.value }
        guard !values.isEmpty else { return 0.0 }
        return values.reduce(0.0, +) / Double(values.count)
    }
    
    private func generateMarkdownReport(summary: PerformanceSummary) -> String {
        """
        # Performance Report
        
        ## Overview
        - Total Connections: \(summary.totalConnections)
        - Total Messages Sent: \(summary.totalMessagesSent)
        - Total Messages Received: \(summary.totalMessagesReceived)
        - Total Bytes Sent: \(summary.totalBytesSent)
        - Total Bytes Received: \(summary.totalBytesReceived)
        - Total Errors: \(summary.totalErrors)
        
        ## Performance
        - Average Latency: \(String(format: "%.2f", summary.averageLatency)) ms
        - Memory Usage: \(summary.memoryUsage / 1024 / 1024) MB
        - CPU Usage: \(String(format: "%.2f", summary.cpuUsage))%
        
        ## Timestamp
        Generated at: \(Date())
        """
    }
}

// MARK: - Performance Summary

/// 性能摘要
public struct PerformanceSummary: Sendable, Codable {
    public let totalConnections: Double
    public let totalMessagesSent: Double
    public let totalMessagesReceived: Double
    public let totalBytesSent: Double
    public let totalBytesReceived: Double
    public let totalErrors: Double
    public let averageLatency: Double
    public let memoryUsage: Double
    public let cpuUsage: Double
    public let metricsSummary: MonitoringMetricsSummary
}
