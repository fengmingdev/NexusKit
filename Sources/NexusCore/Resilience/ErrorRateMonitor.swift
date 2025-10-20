//
//  ErrorRateMonitor.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  错误率监控 - 实时统计和告警

import Foundation

// MARK: - Error Rate Configuration

/// 错误率监控配置
public struct ErrorRateConfiguration: Sendable {
    /// 统计窗口时间（秒）
    public let windowDuration: TimeInterval

    /// 告警阈值（0.0-1.0）
    public let alertThreshold: Double

    /// 严重告警阈值（0.0-1.0）
    public let criticalThreshold: Double

    /// 最小样本数（低于此数量不触发告警）
    public let minimumSamples: Int

    /// 是否启用趋势分析
    public let enableTrendAnalysis: Bool

    public static let `default` = ErrorRateConfiguration(
        windowDuration: 60.0,        // 60秒窗口
        alertThreshold: 0.1,          // 10%告警
        criticalThreshold: 0.3,       // 30%严重告警
        minimumSamples: 10,           // 至少10个样本
        enableTrendAnalysis: true
    )

    public init(
        windowDuration: TimeInterval,
        alertThreshold: Double,
        criticalThreshold: Double,
        minimumSamples: Int,
        enableTrendAnalysis: Bool = true
    ) {
        self.windowDuration = windowDuration
        self.alertThreshold = alertThreshold
        self.criticalThreshold = criticalThreshold
        self.minimumSamples = minimumSamples
        self.enableTrendAnalysis = enableTrendAnalysis
    }
}

// MARK: - Error Event

/// 错误事件
private struct ErrorEvent: Sendable {
    let timestamp: Date
    let error: ErrorClassification
    let isSuccess: Bool
}

// MARK: - Alert Level

/// 告警级别
public enum AlertLevel: Sendable {
    case normal       // 正常
    case warning      // 警告
    case critical     // 严重
}

// MARK: - Error Rate Metrics

/// 错误率指标
public struct ErrorRateMetrics: Sendable {
    /// 总请求数
    public let totalRequests: Int

    /// 失败请求数
    public let failedRequests: Int

    /// 成功请求数
    public let successfulRequests: Int

    /// 错误率（0.0-1.0）
    public let errorRate: Double

    /// 成功率（0.0-1.0）
    public let successRate: Double

    /// 告警级别
    public let alertLevel: AlertLevel

    /// 错误趋势（上升/稳定/下降）
    public let trend: ErrorTrend?

    /// 按类别统计的错误
    public let errorsByCategory: [ErrorCategory: Int]

    /// 按严重程度统计的错误
    public let errorsBySeverity: [ErrorSeverity: Int]

    /// 统计窗口起止时间
    public let windowStart: Date
    public let windowEnd: Date
}

/// 错误趋势
public enum ErrorTrend: Sendable {
    case increasing   // 上升
    case stable       // 稳定
    case decreasing   // 下降

    /// 趋势描述
    var description: String {
        switch self {
        case .increasing: return "上升"
        case .stable: return "稳定"
        case .decreasing: return "下降"
        }
    }
}

// MARK: - Error Rate Monitor

/// 错误率监控器
///
/// 实时监控错误率，提供统计分析和告警功能。
///
/// ## 功能特性
///
/// - 实时错误率计算
/// - 滑动窗口统计
/// - 错误分类统计
/// - 趋势分析
/// - 自动告警
///
/// ## 使用示例
///
/// ```swift
/// let monitor = ErrorRateMonitor(name: "api")
///
/// // 设置告警回调
/// await monitor.onAlert { level, metrics in
///     print("[\(level)] 错误率: \(metrics.errorRate)")
/// }
///
/// // 记录请求结果
/// await monitor.recordSuccess()
/// await monitor.recordFailure(error)
///
/// // 获取指标
/// let metrics = await monitor.getMetrics()
/// print("当前错误率: \(metrics.errorRate)")
/// ```
public actor ErrorRateMonitor {

    // MARK: - Properties

    /// 监控器名称
    public let name: String

    /// 配置
    public let configuration: ErrorRateConfiguration

    /// 事件历史（滑动窗口）
    private var events: [ErrorEvent] = []

    /// 告警回调
    private var alertHandlers: [(@Sendable (AlertLevel, ErrorRateMetrics) -> Void)] = []

    /// 当前告警级别
    private var currentAlertLevel: AlertLevel = .normal

    // MARK: - Initialization

    /// 初始化错误率监控器
    /// - Parameters:
    ///   - name: 监控器名称
    ///   - configuration: 配置
    public init(
        name: String,
        configuration: ErrorRateConfiguration = .default
    ) {
        self.name = name
        self.configuration = configuration
    }

    // MARK: - Recording

    /// 记录成功请求
    public func recordSuccess() {
        let event = ErrorEvent(
            timestamp: Date(),
            error: ErrorClassification(
                recoverability: .recoverable,
                severity: .info,
                category: .unknown
            ),
            isSuccess: true
        )
        events.append(event)
        cleanupOldEvents()
        checkAndAlert()
    }

    /// 记录失败请求
    /// - Parameter error: 错误
    public func recordFailure(_ error: Error) {
        let classification = ErrorClassifier.classify(error)
        let event = ErrorEvent(
            timestamp: Date(),
            error: classification,
            isSuccess: false
        )
        events.append(event)
        cleanupOldEvents()
        checkAndAlert()
    }

    // MARK: - Metrics

    /// 获取当前指标
    /// - Returns: 错误率指标
    public func getMetrics() -> ErrorRateMetrics {
        cleanupOldEvents()

        let failures = events.filter { !$0.isSuccess }
        let total = events.count

        let errorRate = total > 0 ? Double(failures.count) / Double(total) : 0.0
        let successRate = 1.0 - errorRate

        // 计算告警级别
        let alertLevel = calculateAlertLevel(
            errorRate: errorRate,
            sampleCount: total
        )

        // 计算趋势
        let trend = configuration.enableTrendAnalysis ? calculateTrend() : nil

        // 按类别统计
        let errorsByCategory = Dictionary(grouping: failures) { $0.error.category }
            .mapValues { $0.count }

        // 按严重程度统计
        let errorsBySeverity = Dictionary(grouping: failures) { $0.error.severity }
            .mapValues { $0.count }

        let now = Date()
        let windowStart = now.addingTimeInterval(-configuration.windowDuration)

        return ErrorRateMetrics(
            totalRequests: total,
            failedRequests: failures.count,
            successfulRequests: total - failures.count,
            errorRate: errorRate,
            successRate: successRate,
            alertLevel: alertLevel,
            trend: trend,
            errorsByCategory: errorsByCategory,
            errorsBySeverity: errorsBySeverity,
            windowStart: windowStart,
            windowEnd: now
        )
    }

    /// 获取错误分布
    /// - Returns: 错误分类及其数量
    public func getErrorDistribution() -> [(category: ErrorCategory, count: Int)] {
        let failures = events.filter { !$0.isSuccess }
        let distribution = Dictionary(grouping: failures) { $0.error.category }
            .map { (category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        return distribution
    }

    /// 获取严重错误列表
    /// - Parameter severity: 最低严重程度
    /// - Returns: 严重错误事件
    public func getSevereErrors(minimumSeverity: ErrorSeverity = .error) -> [ErrorClassification] {
        events
            .filter { !$0.isSuccess && $0.error.severity >= minimumSeverity }
            .map { $0.error }
    }

    // MARK: - Alert Management

    /// 设置告警回调
    /// - Parameter handler: 告警处理闭包
    public func onAlert(_ handler: @escaping @Sendable (AlertLevel, ErrorRateMetrics) -> Void) {
        alertHandlers.append(handler)
    }

    /// 重置监控器
    public func reset() {
        events.removeAll()
        currentAlertLevel = .normal
    }

    // MARK: - Private Methods

    /// 清理过期事件
    private func cleanupOldEvents() {
        let cutoff = Date().addingTimeInterval(-configuration.windowDuration)
        events.removeAll { $0.timestamp < cutoff }
    }

    /// 计算告警级别
    private func calculateAlertLevel(errorRate: Double, sampleCount: Int) -> AlertLevel {
        // 样本数不足，不触发告警
        guard sampleCount >= configuration.minimumSamples else {
            return .normal
        }

        if errorRate >= configuration.criticalThreshold {
            return .critical
        } else if errorRate >= configuration.alertThreshold {
            return .warning
        } else {
            return .normal
        }
    }

    /// 计算错误趋势
    private func calculateTrend() -> ErrorTrend {
        guard events.count >= 20 else {
            return .stable
        }

        // 将窗口分为两半
        let midpoint = events.count / 2
        let firstHalf = events.prefix(midpoint)
        let secondHalf = events.suffix(events.count - midpoint)

        let firstHalfErrorRate = calculateErrorRate(Array(firstHalf))
        let secondHalfErrorRate = calculateErrorRate(Array(secondHalf))

        let delta = secondHalfErrorRate - firstHalfErrorRate

        if delta > 0.05 {
            return .increasing
        } else if delta < -0.05 {
            return .decreasing
        } else {
            return .stable
        }
    }

    /// 计算指定事件列表的错误率
    private func calculateErrorRate(_ events: [ErrorEvent]) -> Double {
        guard !events.isEmpty else { return 0.0 }
        let failures = events.filter { !$0.isSuccess }.count
        return Double(failures) / Double(events.count)
    }

    /// 检查并触发告警
    private func checkAndAlert() {
        let metrics = getMetrics()
        let newAlertLevel = metrics.alertLevel

        // 告警级别变化时触发
        if newAlertLevel != currentAlertLevel {
            currentAlertLevel = newAlertLevel

            for handler in alertHandlers {
                handler(newAlertLevel, metrics)
            }
        }
    }
}

// MARK: - Error Rate Monitor Registry

/// 错误率监控器注册表
public actor ErrorRateMonitorRegistry {
    private var monitors: [String: ErrorRateMonitor] = [:]

    public static let shared = ErrorRateMonitorRegistry()

    private init() {}

    /// 获取或创建监控器
    /// - Parameters:
    ///   - name: 监控器名称
    ///   - configuration: 配置（仅在创建时使用）
    /// - Returns: 监控器实例
    public func get(
        name: String,
        configuration: ErrorRateConfiguration = .default
    ) -> ErrorRateMonitor {
        if let monitor = monitors[name] {
            return monitor
        }

        let monitor = ErrorRateMonitor(name: name, configuration: configuration)
        monitors[name] = monitor
        return monitor
    }

    /// 移除监控器
    /// - Parameter name: 监控器名称
    public func remove(name: String) {
        monitors.removeValue(forKey: name)
    }

    /// 获取所有监控器
    public func all() -> [ErrorRateMonitor] {
        Array(monitors.values)
    }

    /// 重置所有监控器
    public func resetAll() async {
        for monitor in monitors.values {
            await monitor.reset()
        }
    }

    /// 获取全局错误率
    /// - Returns: 聚合的错误率指标
    public func getGlobalMetrics() async -> ErrorRateMetrics? {
        let allMonitors = Array(monitors.values)
        guard !allMonitors.isEmpty else { return nil }

        var totalRequests = 0
        var totalFailures = 0
        var errorsByCategory: [ErrorCategory: Int] = [:]
        var errorsBySeverity: [ErrorSeverity: Int] = [:]

        for monitor in allMonitors {
            let metrics = await monitor.getMetrics()
            totalRequests += metrics.totalRequests
            totalFailures += metrics.failedRequests

            // 合并错误分类统计
            for (category, count) in metrics.errorsByCategory {
                errorsByCategory[category, default: 0] += count
            }

            for (severity, count) in metrics.errorsBySeverity {
                errorsBySeverity[severity, default: 0] += count
            }
        }

        let errorRate = totalRequests > 0 ? Double(totalFailures) / Double(totalRequests) : 0.0
        let successRate = 1.0 - errorRate

        return ErrorRateMetrics(
            totalRequests: totalRequests,
            failedRequests: totalFailures,
            successfulRequests: totalRequests - totalFailures,
            errorRate: errorRate,
            successRate: successRate,
            alertLevel: .normal,
            trend: nil,
            errorsByCategory: errorsByCategory,
            errorsBySeverity: errorsBySeverity,
            windowStart: Date(),
            windowEnd: Date()
        )
    }
}

// MARK: - CustomStringConvertible

extension ErrorRateMetrics: CustomStringConvertible {
    public var description: String {
        """
        ErrorRateMetrics(
            total: \(totalRequests),
            failed: \(failedRequests),
            errorRate: \(String(format: "%.2f%%", errorRate * 100)),
            alertLevel: \(alertLevel),
            trend: \(trend?.description ?? "N/A")
        )
        """
    }
}
