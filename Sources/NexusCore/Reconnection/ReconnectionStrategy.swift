//
//  ReconnectionStrategy.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Reconnection Strategy Protocol

/// 重连策略协议
public protocol ReconnectionStrategy: Sendable {
    /// 计算下次重连延迟
    /// - Parameters:
    ///   - attempt: 当前重连尝试次数（从 0 开始）
    ///   - lastError: 上次连接失败的错误
    /// - Returns: 延迟时间（秒），返回 nil 表示不再重连
    func nextDelay(attempt: Int, lastError: Error?) -> TimeInterval?

    /// 判断是否应该重连
    /// - Parameter error: 导致断开的错误
    /// - Returns: 是否应该重连
    func shouldReconnect(error: Error) -> Bool

    /// 重置策略状态
    func reset()
}

// MARK: - Default Implementations

public extension ReconnectionStrategy {
    func reset() {}
}

// MARK: - Exponential Backoff Strategy

/// 指数退避重连策略
public struct ExponentialBackoffStrategy: ReconnectionStrategy {
    /// 初始延迟
    public let initialDelay: TimeInterval

    /// 最大延迟
    public let maxDelay: TimeInterval

    /// 最大重连次数
    public let maxAttempts: Int

    /// 退避倍数
    public let multiplier: Double

    /// 是否添加随机抖动（避免雷鸣群效应）
    public let jitter: Bool

    public init(
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        maxAttempts: Int = 10,
        multiplier: Double = 2.0,
        jitter: Bool = true
    ) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
        self.multiplier = multiplier
        self.jitter = jitter
    }

    public func nextDelay(attempt: Int, lastError: Error?) -> TimeInterval? {
        guard attempt < maxAttempts else {
            return nil
        }

        var delay = min(
            initialDelay * pow(multiplier, Double(attempt)),
            maxDelay
        )

        // 添加随机抖动 ±25%
        if jitter {
            let jitterRange = delay * 0.25
            let randomJitter = Double.random(in: -jitterRange...jitterRange)
            delay += randomJitter
            delay = max(0, delay) // 确保非负
        }

        return delay
    }

    public func shouldReconnect(error: Error) -> Bool {
        // 某些错误不应该重连
        if let nexusError = error as? NexusError {
            switch nexusError {
            case .authenticationFailed, .invalidCredentials:
                return false
            default:
                return true
            }
        }
        return true
    }
}

// MARK: - Fixed Interval Strategy

/// 固定间隔重连策略
public struct FixedIntervalStrategy: ReconnectionStrategy {
    /// 重连间隔
    public let interval: TimeInterval

    /// 最大重连次数
    public let maxAttempts: Int

    public init(
        interval: TimeInterval = 5.0,
        maxAttempts: Int = 5
    ) {
        self.interval = interval
        self.maxAttempts = maxAttempts
    }

    public func nextDelay(attempt: Int, lastError: Error?) -> TimeInterval? {
        attempt < maxAttempts ? interval : nil
    }

    public func shouldReconnect(error: Error) -> Bool {
        if let nexusError = error as? NexusError {
            switch nexusError {
            case .authenticationFailed, .invalidCredentials:
                return false
            default:
                return true
            }
        }
        return true
    }
}

// MARK: - Adaptive Strategy

/// 自适应重连策略（根据网络状况动态调整）
public actor AdaptiveStrategy: ReconnectionStrategy {
    /// 初始延迟
    public let initialDelay: TimeInterval

    /// 最大延迟
    public let maxDelay: TimeInterval

    /// 最大重连次数
    public let maxAttempts: Int

    /// 成功连接历史（用于判断网络质量）
    private var successfulConnections: [Date] = []

    /// 失败连接历史
    private var failedConnections: [Date] = []

    /// 时间窗口（秒）
    private let timeWindow: TimeInterval = 300 // 5分钟

    public init(
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        maxAttempts: Int = 10
    ) {
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }

    public func nextDelay(attempt: Int, lastError: Error?) -> TimeInterval? {
        guard attempt < maxAttempts else {
            return nil
        }

        // 清理过期记录
        cleanupOldRecords()

        // 记录失败
        failedConnections.append(Date())

        // 根据成功率计算延迟
        let successRate = calculateSuccessRate()

        var delay: TimeInterval
        if successRate > 0.8 {
            // 网络质量好，使用较短延迟
            delay = initialDelay * pow(1.5, Double(attempt))
        } else if successRate > 0.5 {
            // 网络质量一般，使用标准延迟
            delay = initialDelay * pow(2.0, Double(attempt))
        } else {
            // 网络质量差，使用较长延迟
            delay = initialDelay * pow(2.5, Double(attempt))
        }

        return min(delay, maxDelay)
    }

    public func shouldReconnect(error: Error) -> Bool {
        if let nexusError = error as? NexusError {
            switch nexusError {
            case .authenticationFailed, .invalidCredentials:
                return false
            default:
                return true
            }
        }
        return true
    }

    /// 记录成功连接
    public func recordSuccess() {
        successfulConnections.append(Date())
        cleanupOldRecords()
    }

    public func reset() {
        successfulConnections.removeAll()
        failedConnections.removeAll()
    }

    // MARK: - Private Methods

    private func cleanupOldRecords() {
        let cutoff = Date().addingTimeInterval(-timeWindow)

        successfulConnections.removeAll { $0 < cutoff }
        failedConnections.removeAll { $0 < cutoff }
    }

    private func calculateSuccessRate() -> Double {
        let totalAttempts = successfulConnections.count + failedConnections.count
        guard totalAttempts > 0 else { return 1.0 }

        return Double(successfulConnections.count) / Double(totalAttempts)
    }
}

// MARK: - Custom Strategy

/// 自定义重连策略
public struct CustomStrategy: ReconnectionStrategy {
    private let delayCalculator: @Sendable (Int, Error?) -> TimeInterval?
    private let reconnectChecker: @Sendable (Error) -> Bool

    public init(
        delayCalculator: @escaping @Sendable (Int, Error?) -> TimeInterval?,
        shouldReconnect: @escaping @Sendable (Error) -> Bool = { _ in true }
    ) {
        self.delayCalculator = delayCalculator
        self.reconnectChecker = shouldReconnect
    }

    public func nextDelay(attempt: Int, lastError: Error?) -> TimeInterval? {
        delayCalculator(attempt, lastError)
    }

    public func shouldReconnect(error: Error) -> Bool {
        reconnectChecker(error)
    }
}

// MARK: - Convenience Extensions

public extension ReconnectionStrategy where Self == ExponentialBackoffStrategy {
    /// 指数退避策略（使用默认参数）
    static func exponentialBackoff(
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        maxAttempts: Int = 10
    ) -> ExponentialBackoffStrategy {
        ExponentialBackoffStrategy(
            initialDelay: initialDelay,
            maxDelay: maxDelay,
            maxAttempts: maxAttempts
        )
    }
}

public extension ReconnectionStrategy where Self == FixedIntervalStrategy {
    /// 固定间隔策略（使用默认参数）
    static func fixedInterval(
        interval: TimeInterval = 5.0,
        maxAttempts: Int = 5
    ) -> FixedIntervalStrategy {
        FixedIntervalStrategy(interval: interval, maxAttempts: maxAttempts)
    }
}

public extension ReconnectionStrategy where Self == AdaptiveStrategy {
    /// 自适应策略（使用默认参数）
    static func adaptive(
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        maxAttempts: Int = 10
    ) -> AdaptiveStrategy {
        AdaptiveStrategy(
            initialDelay: initialDelay,
            maxDelay: maxDelay,
            maxAttempts: maxAttempts
        )
    }
}
