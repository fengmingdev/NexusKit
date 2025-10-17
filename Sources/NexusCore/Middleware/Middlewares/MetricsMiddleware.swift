//
//  MetricsMiddleware.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Metrics Middleware

/// 性能监控中间件
///
/// 收集和记录连接的性能指标，用于监控和分析。
///
/// ## 收集的指标
///
/// - 消息数量（发送/接收）
/// - 数据流量（字节）
/// - 平均消息大小
/// - 吞吐量（bytes/sec）
/// - 延迟统计
/// - 错误率
///
/// ## 使用示例
///
/// ### 基础使用
/// ```swift
/// let metrics = MetricsMiddleware()
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(metrics)
///     .connect()
///
/// // 稍后获取指标
/// let summary = await metrics.summary()
/// print("发送: \(summary.totalBytesSent) 字节")
/// print("接收: \(summary.totalBytesReceived) 字节")
/// print("吞吐量: \(summary.throughput) bytes/s")
/// ```
///
/// ### 自动报告
/// ```swift
/// let metrics = MetricsMiddleware(
///     reportInterval: 60.0  // 每 60 秒自动打印一次报告
/// )
/// 
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(metrics)
///     .connect()
/// 
/// // 启动自动报告
/// await metrics.startReporting()
/// ```
public actor MetricsMiddleware: Middleware {
    // MARK: - Properties

    public nonisolated let name = "MetricsMiddleware"
    public nonisolated let priority = 5  // 高优先级，第一个处理

    /// 开始时间
    private var startTime: Date = Date()

    /// 发送消息计数
    private var messagesSent: Int64 = 0

    /// 接收消息计数
    private var messagesReceived: Int64 = 0

    /// 发送字节数
    private var bytesSent: Int64 = 0

    /// 接收字节数
    private var bytesReceived: Int64 = 0

    /// 错误计数
    private var errorCount: Int64 = 0

    /// 最后报告时间
    private var lastReportTime: Date = Date()

    /// 自动报告间隔（秒）
    private let reportInterval: TimeInterval?

    /// 报告定时器
    private var reportTimer: Task<Void, Never>?

    // MARK: - Initialization

    /// 初始化性能监控中间件
    /// - Parameters:
    ///   - reportInterval: 自动报告间隔（秒），nil 表示不自动报告
    public init(reportInterval: TimeInterval? = nil) {
        self.reportInterval = reportInterval
        // reportTimer 将在 startReporting() 中初始化
    }

    deinit {
        reportTimer?.cancel()
    }

    /// 启动自动报告（需要在 actor 上下文中调用）
    public func startReporting() {
        guard let interval = reportInterval, reportTimer == nil else {
            return
        }

        self.reportTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                if !Task.isCancelled {
                    await printReport()
                }
            }
        }
    }

    // MARK: - Middleware Protocol

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        messagesSent += 1
        bytesSent += Int64(data.count)
        return data
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        messagesReceived += 1
        bytesReceived += Int64(data.count)
        return data
    }

    public func onError(error: Error, context: MiddlewareContext) async {
        errorCount += 1
    }

    public func onDisconnect(connection: any Connection, reason: DisconnectReason) async {
        await printFinalReport()
    }

    // MARK: - Metrics

    /// 获取性能摘要
    /// - Returns: 性能指标摘要
    public func summary() -> MetricsSummary {
        let duration = Date().timeIntervalSince(startTime)

        let throughputSent = duration > 0 ? Double(bytesSent) / duration : 0
        let throughputReceived = duration > 0 ? Double(bytesReceived) / duration : 0

        let avgMessageSizeSent = messagesSent > 0 ? Double(bytesSent) / Double(messagesSent) : 0
        let avgMessageSizeReceived = messagesReceived > 0 ? Double(bytesReceived) / Double(messagesReceived) : 0

        return MetricsSummary(
            duration: duration,
            messagesSent: messagesSent,
            messagesReceived: messagesReceived,
            totalBytesSent: bytesSent,
            totalBytesReceived: bytesReceived,
            throughputSent: throughputSent,
            throughputReceived: throughputReceived,
            avgMessageSizeSent: avgMessageSizeSent,
            avgMessageSizeReceived: avgMessageSizeReceived,
            errorCount: errorCount
        )
    }

    /// 重置所有指标
    public func reset() {
        startTime = Date()
        lastReportTime = Date()
        messagesSent = 0
        messagesReceived = 0
        bytesSent = 0
        bytesReceived = 0
        errorCount = 0
    }

    // MARK: - Reporting

    private func printReport() async {
        let summary = self.summary()
        let sinceLastReport = Date().timeIntervalSince(lastReportTime)

        print("\n📊 [Metrics Report]")
        print("   Duration: \(String(format: "%.1f", summary.duration))s")
        print("   Messages: ↑ \(summary.messagesSent) | ↓ \(summary.messagesReceived)")
        print("   Bytes: ↑ \(formatBytes(summary.totalBytesSent)) | ↓ \(formatBytes(summary.totalBytesReceived))")
        print("   Throughput: ↑ \(formatBytes(Int64(summary.throughputSent)))/s | ↓ \(formatBytes(Int64(summary.throughputReceived)))/s")
        print("   Avg Size: ↑ \(formatBytes(Int64(summary.avgMessageSizeSent))) | ↓ \(formatBytes(Int64(summary.avgMessageSizeReceived)))")

        if summary.errorCount > 0 {
            print("   Errors: ⚠️ \(summary.errorCount)")
        }

        print("   Since last report: \(String(format: "%.1f", sinceLastReport))s\n")

        lastReportTime = Date()
    }

    private func printFinalReport() async {
        let summary = self.summary()

        print("\n📊 [Final Metrics Report]")
        print("   Total Duration: \(String(format: "%.1f", summary.duration))s")
        print("   Total Messages: ↑ \(summary.messagesSent) | ↓ \(summary.messagesReceived)")
        print("   Total Bytes: ↑ \(formatBytes(summary.totalBytesSent)) | ↓ \(formatBytes(summary.totalBytesReceived))")
        print("   Avg Throughput: ↑ \(formatBytes(Int64(summary.throughputSent)))/s | ↓ \(formatBytes(Int64(summary.throughputReceived)))/s")
        print("   Avg Message Size: ↑ \(formatBytes(Int64(summary.avgMessageSizeSent))) | ↓ \(formatBytes(Int64(summary.avgMessageSizeReceived)))")

        if summary.errorCount > 0 {
            print("   Total Errors: ⚠️ \(summary.errorCount)")
        }

        print()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024

        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.2f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.2f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }
}

// MARK: - Metrics Summary

/// 性能指标摘要
public struct MetricsSummary: Sendable {
    /// 运行时长（秒）
    public let duration: TimeInterval

    /// 发送消息数
    public let messagesSent: Int64

    /// 接收消息数
    public let messagesReceived: Int64

    /// 发送字节数
    public let totalBytesSent: Int64

    /// 接收字节数
    public let totalBytesReceived: Int64

    /// 发送吞吐量（bytes/sec）
    public let throughputSent: Double

    /// 接收吞吐量（bytes/sec）
    public let throughputReceived: Double

    /// 平均发送消息大小（字节）
    public let avgMessageSizeSent: Double

    /// 平均接收消息大小（字节）
    public let avgMessageSizeReceived: Double

    /// 错误计数
    public let errorCount: Int64

    public init(
        duration: TimeInterval,
        messagesSent: Int64,
        messagesReceived: Int64,
        totalBytesSent: Int64,
        totalBytesReceived: Int64,
        throughputSent: Double,
        throughputReceived: Double,
        avgMessageSizeSent: Double,
        avgMessageSizeReceived: Double,
        errorCount: Int64
    ) {
        self.duration = duration
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
        self.totalBytesSent = totalBytesSent
        self.totalBytesReceived = totalBytesReceived
        self.throughputSent = throughputSent
        self.throughputReceived = throughputReceived
        self.avgMessageSizeSent = avgMessageSizeSent
        self.avgMessageSizeReceived = avgMessageSizeReceived
        self.errorCount = errorCount
    }
}
