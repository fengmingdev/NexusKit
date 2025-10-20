//
//  MetricsPlugin.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 性能指标插件
///
/// 收集和记录连接性能指标。
public actor MetricsPlugin: NexusPlugin {
    
    // MARK: - Plugin Info
    
    public let name = "MetricsPlugin"
    public let version = "1.0.0"
    private let _isEnabled: Bool
    public nonisolated var isEnabled: Bool { _isEnabled }
    
    // MARK: - Metrics
    
    private var metrics: [String: ConnectionMetrics] = [:]
    private var globalMetrics = GlobalMetrics()
    
    private struct ConnectionMetrics {
        var connectTime: Date?
        var disconnectTime: Date?
        var bytesSent: Int = 0
        var bytesReceived: Int = 0
        var sendCount: Int = 0
        var receiveCount: Int = 0
        var errors: Int = 0
    }
    
    private struct GlobalMetrics {
        var totalConnections: Int = 0
        var activeConnections: Int = 0
        var totalBytesSent: Int = 0
        var totalBytesReceived: Int = 0
        var totalErrors: Int = 0
    }
    
    // MARK: - Configuration
    
    /// 是否自动打印指标
    private let autoPrintMetrics: Bool
    
    /// 指标打印间隔（秒）
    private let printInterval: TimeInterval
    
    /// 最后打印时间
    private var lastPrintTime: Date?
    
    // MARK: - Initialization
    
    public init(
        autoPrintMetrics: Bool = false,
        printInterval: TimeInterval = 60,
        isEnabled: Bool = true
    ) {
        self.autoPrintMetrics = autoPrintMetrics
        self.printInterval = printInterval
        self._isEnabled = isEnabled
    }
    
    // MARK: - Lifecycle Hooks
    
    public func didConnect(_ context: PluginContext) async {
        var metric = metrics[context.connectionId] ?? ConnectionMetrics()
        metric.connectTime = context.timestamp
        metrics[context.connectionId] = metric
        
        globalMetrics.totalConnections += 1
        globalMetrics.activeConnections += 1
        
        checkAndPrintMetrics()
    }
    
    public func didDisconnect(_ context: PluginContext) async {
        if var metric = metrics[context.connectionId] {
            metric.disconnectTime = context.timestamp
            metrics[context.connectionId] = metric
        }
        
        globalMetrics.activeConnections -= 1
        
        checkAndPrintMetrics()
    }
    
    // MARK: - Data Hooks
    
    public func didSend(_ data: Data, context: PluginContext) async {
        if var metric = metrics[context.connectionId] {
            metric.bytesSent += data.count
            metric.sendCount += 1
            metrics[context.connectionId] = metric
        }
        
        globalMetrics.totalBytesSent += data.count
        
        checkAndPrintMetrics()
    }
    
    public func didReceive(_ data: Data, context: PluginContext) async {
        if var metric = metrics[context.connectionId] {
            metric.bytesReceived += data.count
            metric.receiveCount += 1
            metrics[context.connectionId] = metric
        }
        
        globalMetrics.totalBytesReceived += data.count
        
        checkAndPrintMetrics()
    }
    
    // MARK: - Error Hooks
    
    public func handleError(_ error: Error, context: PluginContext) async {
        if var metric = metrics[context.connectionId] {
            metric.errors += 1
            metrics[context.connectionId] = metric
        }
        
        globalMetrics.totalErrors += 1
    }
    
    // MARK: - Metrics Query
    
    /// 获取连接指标
    public func getConnectionMetrics(_ connectionId: String) -> (
        duration: TimeInterval?,
        bytesSent: Int,
        bytesReceived: Int,
        sendCount: Int,
        receiveCount: Int,
        errors: Int
    )? {
        guard let metric = metrics[connectionId] else {
            return nil
        }
        
        let duration: TimeInterval?
        if let start = metric.connectTime {
            if let end = metric.disconnectTime {
                duration = end.timeIntervalSince(start)
            } else {
                duration = Date().timeIntervalSince(start)
            }
        } else {
            duration = nil
        }
        
        return (
            duration: duration,
            bytesSent: metric.bytesSent,
            bytesReceived: metric.bytesReceived,
            sendCount: metric.sendCount,
            receiveCount: metric.receiveCount,
            errors: metric.errors
        )
    }
    
    /// 获取全局指标
    public func getGlobalMetrics() -> (
        totalConnections: Int,
        activeConnections: Int,
        totalBytesSent: Int,
        totalBytesReceived: Int,
        totalErrors: Int
    ) {
        (
            totalConnections: globalMetrics.totalConnections,
            activeConnections: globalMetrics.activeConnections,
            totalBytesSent: globalMetrics.totalBytesSent,
            totalBytesReceived: globalMetrics.totalBytesReceived,
            totalErrors: globalMetrics.totalErrors
        )
    }
    
    /// 重置指标
    public func resetMetrics() {
        metrics.removeAll()
        globalMetrics = GlobalMetrics()
        lastPrintTime = nil
    }
    
    /// 打印指标
    public func printMetrics() {
        print("\n📊 === NexusKit Metrics ===")
        print("Global Metrics:")
        print("  Total Connections: \(globalMetrics.totalConnections)")
        print("  Active Connections: \(globalMetrics.activeConnections)")
        print("  Total Bytes Sent: \(formatBytes(globalMetrics.totalBytesSent))")
        print("  Total Bytes Received: \(formatBytes(globalMetrics.totalBytesReceived))")
        print("  Total Errors: \(globalMetrics.totalErrors)")
        
        if !metrics.isEmpty {
            print("\nConnection Metrics:")
            for (connectionId, metric) in metrics {
                let duration = metric.connectTime.map { start in
                    let end = metric.disconnectTime ?? Date()
                    return end.timeIntervalSince(start)
                } ?? 0
                
                print("  \(connectionId):")
                print("    Duration: \(String(format: "%.2f", duration))s")
                print("    Bytes Sent: \(formatBytes(metric.bytesSent)) (\(metric.sendCount) sends)")
                print("    Bytes Received: \(formatBytes(metric.bytesReceived)) (\(metric.receiveCount) receives)")
                if metric.errors > 0 {
                    print("    Errors: \(metric.errors)")
                }
            }
        }
        print("=========================\n")
        
        lastPrintTime = Date()
    }
    
    // MARK: - Private Methods
    
    /// 检查并打印指标
    private func checkAndPrintMetrics() {
        guard autoPrintMetrics else { return }
        
        let now = Date()
        if let lastPrint = lastPrintTime {
            if now.timeIntervalSince(lastPrint) >= printInterval {
                printMetrics()
            }
        } else {
            lastPrintTime = now
        }
    }
    
    /// 格式化字节数
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
