//
//  LogFilter.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  日志过滤器

import Foundation

// MARK: - Log Filter Protocol

/// 日志过滤器协议
public protocol LogFilter: Sendable {
    /// 判断是否应该记录日志
    func shouldLog(_ message: LogMessage) async -> Bool
}

// MARK: - Level Filter

/// 日志级别过滤器
///
/// 只记录指定级别及以上的日志。
public struct LevelFilter: LogFilter, Sendable {

    /// 最小日志级别
    public let minimumLevel: LogLevel

    public init(minimumLevel: LogLevel) {
        self.minimumLevel = minimumLevel
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        message.level >= minimumLevel
    }
}

// MARK: - Module Filter

/// 模块过滤器
///
/// 根据文件名过滤日志。
public struct ModuleFilter: LogFilter, Sendable {

    /// 包含的模块（文件名前缀）
    public let includedModules: Set<String>

    /// 排除的模块（文件名前缀）
    public let excludedModules: Set<String>

    public init(
        includedModules: Set<String> = [],
        excludedModules: Set<String> = []
    ) {
        self.includedModules = includedModules
        self.excludedModules = excludedModules
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        let fileName = message.fileName

        // 如果在排除列表中，不记录
        if !excludedModules.isEmpty {
            for excluded in excludedModules {
                if fileName.hasPrefix(excluded) {
                    return false
                }
            }
        }

        // 如果指定了包含列表，必须在列表中
        if !includedModules.isEmpty {
            for included in includedModules {
                if fileName.hasPrefix(included) {
                    return true
                }
            }
            return false
        }

        return true
    }
}

// MARK: - Sampling Filter

/// 采样过滤器
///
/// 按照一定比例采样日志，用于高频场景。
public actor SamplingFilter: LogFilter {

    /// 采样率（0.0 - 1.0）
    public let samplingRate: Double

    /// 计数器
    private var counter: UInt64 = 0

    public init(samplingRate: Double) {
        self.samplingRate = max(0.0, min(1.0, samplingRate))
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        counter += 1

        // 如果采样率为 1.0，记录所有日志
        if samplingRate >= 1.0 {
            return true
        }

        // 如果采样率为 0.0，不记录任何日志
        if samplingRate <= 0.0 {
            return false
        }

        // 按比例采样（使用计数器进行简单采样）
        let shouldLog = Double(counter % 100) < (samplingRate * 100.0)
        return shouldLog
    }
}

// MARK: - Rate Limit Filter

/// 速率限制过滤器
///
/// 限制在指定时间窗口内记录的日志数量。
public actor RateLimitFilter: LogFilter {

    /// 时间窗口（秒）
    public let windowSize: TimeInterval

    /// 窗口内最大日志数量
    public let maxLogsPerWindow: Int

    /// 日志时间戳队列
    private var timestamps: [Date] = []

    public init(windowSize: TimeInterval, maxLogsPerWindow: Int) {
        self.windowSize = windowSize
        self.maxLogsPerWindow = maxLogsPerWindow
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        let now = Date()

        // 移除过期的时间戳
        let cutoff = now.addingTimeInterval(-windowSize)
        timestamps.removeAll { $0 < cutoff }

        // 检查是否超过限制
        if timestamps.count >= maxLogsPerWindow {
            return false
        }

        // 记录时间戳
        timestamps.append(now)
        return true
    }
}

// MARK: - Burst Filter

/// 突发过滤器
///
/// 允许短时间内的突发日志，但长期限制平均速率。
public actor BurstFilter: LogFilter {

    /// 突发容量
    public let burstCapacity: Int

    /// 补充速率（日志/秒）
    public let refillRate: Double

    /// 当前令牌数
    private var tokens: Double

    /// 上次补充时间
    private var lastRefillTime: Date

    public init(burstCapacity: Int, refillRate: Double) {
        self.burstCapacity = burstCapacity
        self.refillRate = refillRate
        self.tokens = Double(burstCapacity)
        self.lastRefillTime = Date()
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        let now = Date()

        // 补充令牌
        let elapsed = now.timeIntervalSince(lastRefillTime)
        let newTokens = elapsed * refillRate
        tokens = min(Double(burstCapacity), tokens + newTokens)
        lastRefillTime = now

        // 检查是否有可用令牌
        if tokens >= 1.0 {
            tokens -= 1.0
            return true
        }

        return false
    }
}

// MARK: - Duplicate Filter

/// 重复过滤器
///
/// 过滤重复的日志消息，只保留第一条和统计信息。
public actor DuplicateFilter: LogFilter {

    /// 时间窗口（秒）
    public let windowSize: TimeInterval

    /// 消息哈希值到最后记录时间的映射
    private var lastLogged: [Int: (date: Date, count: Int)] = [:]

    public init(windowSize: TimeInterval = 60.0) {
        self.windowSize = windowSize
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        let now = Date()
        let messageHash = message.message.hashValue

        // 清理过期记录
        let cutoff = now.addingTimeInterval(-windowSize)
        lastLogged = lastLogged.filter { $0.value.date >= cutoff }

        // 检查是否重复
        if let record = lastLogged[messageHash] {
            lastLogged[messageHash] = (date: now, count: record.count + 1)
            return false
        }

        // 记录新消息
        lastLogged[messageHash] = (date: now, count: 1)
        return true
    }

    /// 获取重复计数
    public func getDuplicateCount(for message: LogMessage) -> Int {
        let messageHash = message.message.hashValue
        return lastLogged[messageHash]?.count ?? 0
    }
}

// MARK: - Metadata Filter

/// 元数据过滤器
///
/// 根据元数据键值对过滤日志。
public struct MetadataFilter: LogFilter, Sendable {

    /// 要匹配的元数据
    public let requiredMetadata: [String: String]

    public init(requiredMetadata: [String: String]) {
        self.requiredMetadata = requiredMetadata
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        // 检查所有必需的元数据是否存在且匹配
        for (key, value) in requiredMetadata {
            guard let messageValue = message.metadata[key],
                  messageValue == value else {
                return false
            }
        }
        return true
    }
}

// MARK: - Composite Filter

/// 组合过滤器
///
/// 组合多个过滤器，支持 AND/OR 逻辑。
public struct CompositeFilter: LogFilter, Sendable {

    /// 逻辑操作类型
    public enum Logic: Sendable {
        /// 所有过滤器都通过才记录
        case and

        /// 任一过滤器通过就记录
        case or
    }

    /// 子过滤器
    private let filters: [any LogFilter]

    /// 逻辑操作
    public let logic: Logic

    public init(filters: [any LogFilter], logic: Logic = .and) {
        self.filters = filters
        self.logic = logic
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        switch logic {
        case .and:
            // 所有过滤器都通过
            for filter in filters {
                if await !filter.shouldLog(message) {
                    return false
                }
            }
            return true

        case .or:
            // 任一过滤器通过
            for filter in filters {
                if await filter.shouldLog(message) {
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - Custom Filter

/// 自定义过滤器
///
/// 使用闭包自定义过滤逻辑。
public struct CustomFilter: LogFilter, Sendable {

    private let predicate: @Sendable (LogMessage) async -> Bool

    public init(predicate: @escaping @Sendable (LogMessage) async -> Bool) {
        self.predicate = predicate
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        await predicate(message)
    }
}

// MARK: - Time-Based Filter

/// 时间段过滤器
///
/// 只在特定时间段记录日志。
public struct TimeBasedFilter: LogFilter, Sendable {

    /// 允许记录的时间段
    public let allowedTimeRanges: [(start: Int, end: Int)]  // 小时 (0-23)

    public init(allowedTimeRanges: [(start: Int, end: Int)]) {
        self.allowedTimeRanges = allowedTimeRanges
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: message.timestamp)

        for range in allowedTimeRanges {
            if hour >= range.start && hour <= range.end {
                return true
            }
        }

        return false
    }
}

// MARK: - Pattern Filter

/// 模式过滤器
///
/// 根据消息内容的正则表达式模式过滤。
public struct PatternFilter: LogFilter, Sendable {

    /// 要匹配的正则表达式
    private let regex: NSRegularExpression

    /// 是否反转匹配（排除匹配的日志）
    public let inverted: Bool

    public init(pattern: String, inverted: Bool = false) throws {
        self.regex = try NSRegularExpression(pattern: pattern, options: [])
        self.inverted = inverted
    }

    public func shouldLog(_ message: LogMessage) async -> Bool {
        let range = NSRange(message.message.startIndex..., in: message.message)
        let matches = regex.numberOfMatches(in: message.message, options: [], range: range)
        let hasMatch = matches > 0

        return inverted ? !hasMatch : hasMatch
    }
}
