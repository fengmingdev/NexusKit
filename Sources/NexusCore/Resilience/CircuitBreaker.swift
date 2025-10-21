//
//  CircuitBreaker.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  熔断器实现 - 防止级联故障，提供快速失败机制

import Foundation

// MARK: - Circuit Breaker State

/// 熔断器状态
public enum CircuitBreakerState: Sendable {
    /// 关闭状态 - 正常工作，允许所有请求通过
    case closed

    /// 打开状态 - 熔断触发，拒绝所有请求
    case open(openedAt: Date)

    /// 半开状态 - 探测恢复，允许有限请求通过
    case halfOpen

    /// 是否为打开状态
    public var isOpen: Bool {
        if case .open = self { return true }
        return false
    }

    /// 是否为半开状态
    public var isHalfOpen: Bool {
        if case .halfOpen = self { return true }
        return false
    }

    /// 是否为关闭状态
    public var isClosed: Bool {
        if case .closed = self { return true }
        return false
    }
}

// MARK: - Circuit Breaker Configuration

/// 熔断器配置
public struct CircuitBreakerConfiguration: Sendable {
    /// 失败率阈值（0.0-1.0），超过此值触发熔断
    public let failureThreshold: Double

    /// 最小请求数量，达到此数量后才开始统计失败率
    public let minimumRequests: Int

    /// 统计窗口时间（秒）
    public let windowDuration: TimeInterval

    /// 熔断器打开后的冷却时间（秒），超过后转为半开状态
    public let resetTimeout: TimeInterval

    /// 半开状态下的探测请求数量
    public let halfOpenMaxRequests: Int

    /// 半开状态下成功率阈值，超过此值关闭熔断器
    public let halfOpenSuccessThreshold: Double

    /// 慢调用阈值（秒），超过此时间的调用视为慢调用
    public let slowCallThreshold: TimeInterval?

    /// 慢调用率阈值（0.0-1.0），超过此值也会触发熔断
    public let slowCallRateThreshold: Double?

    /// 默认配置
    public static let `default` = CircuitBreakerConfiguration(
        failureThreshold: 0.5,           // 50%失败率
        minimumRequests: 10,             // 至少10个请求
        windowDuration: 60.0,            // 60秒窗口
        resetTimeout: 30.0,              // 30秒冷却
        halfOpenMaxRequests: 5,          // 半开状态允许5个请求
        halfOpenSuccessThreshold: 0.6,   // 60%成功率
        slowCallThreshold: 5.0,          // 5秒算慢调用
        slowCallRateThreshold: 0.3       // 30%慢调用率
    )

    public init(
        failureThreshold: Double,
        minimumRequests: Int,
        windowDuration: TimeInterval,
        resetTimeout: TimeInterval,
        halfOpenMaxRequests: Int,
        halfOpenSuccessThreshold: Double,
        slowCallThreshold: TimeInterval? = nil,
        slowCallRateThreshold: Double? = nil
    ) {
        self.failureThreshold = failureThreshold
        self.minimumRequests = minimumRequests
        self.windowDuration = windowDuration
        self.resetTimeout = resetTimeout
        self.halfOpenMaxRequests = halfOpenMaxRequests
        self.halfOpenSuccessThreshold = halfOpenSuccessThreshold
        self.slowCallThreshold = slowCallThreshold
        self.slowCallRateThreshold = slowCallRateThreshold
    }
}

// MARK: - Call Record

/// 调用记录
private struct CallRecord: Sendable {
    let timestamp: Date
    let isSuccess: Bool
    let duration: TimeInterval
}

// MARK: - Circuit Breaker Error

/// 熔断器错误
public enum CircuitBreakerError: Error, Sendable {
    /// 熔断器打开，拒绝请求
    case circuitOpen

    /// 半开状态下，超出最大允许请求数
    case halfOpenLimitExceeded
}

// MARK: - Circuit Breaker

/// 熔断器
///
/// 实现了Circuit Breaker模式，用于防止级联故障和提供快速失败机制。
///
/// ## 状态转换
///
/// ```
/// Closed --[失败率 > 阈值]--> Open
/// Open   --[冷却时间后]----> HalfOpen
/// HalfOpen --[探测成功]--> Closed
/// HalfOpen --[探测失败]--> Open
/// ```
///
/// ## 使用示例
///
/// ```swift
/// let breaker = CircuitBreaker(name: "api", configuration: .default)
///
/// do {
///     try await breaker.execute {
///         try await apiCall()
///     }
/// } catch CircuitBreakerError.circuitOpen {
///     // 熔断器已打开，使用降级方案
///     return fallbackResponse
/// }
/// ```
public actor CircuitBreaker {

    // MARK: - Properties

    /// 熔断器名称
    public let name: String

    /// 配置
    public let configuration: CircuitBreakerConfiguration

    /// 当前状态
    private var state: CircuitBreakerState = .closed

    /// 调用记录（滑动窗口）
    private var callHistory: [CallRecord] = []

    /// 半开状态下的调用计数
    private var halfOpenCallCount: Int = 0

    /// 状态变更回调
    private var onStateChange: (@Sendable (CircuitBreakerState, CircuitBreakerState) -> Void)?

    /// 统计信息
    private var stats = Statistics()

    // MARK: - Statistics

    private struct Statistics {
        var totalCalls: Int = 0
        var successfulCalls: Int = 0
        var failedCalls: Int = 0
        var slowCalls: Int = 0
        var rejectedCalls: Int = 0
        var stateTransitions: Int = 0
    }

    // MARK: - Initialization

    /// 初始化熔断器
    /// - Parameters:
    ///   - name: 熔断器名称（用于日志和监控）
    ///   - configuration: 配置
    public init(
        name: String,
        configuration: CircuitBreakerConfiguration = .default
    ) {
        self.name = name
        self.configuration = configuration
    }

    // MARK: - Execution

    /// 执行操作（带熔断保护）
    ///
    /// - Parameter operation: 要执行的操作
    /// - Returns: 操作结果
    /// - Throws: 操作错误或熔断器错误
    public func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        // 检查是否允许执行
        try checkAndUpdateState()

        // 记录开始时间
        let startTime = Date()

        do {
            // 执行操作
            let result = try await operation()

            // 记录成功
            let duration = Date().timeIntervalSince(startTime)
            recordSuccess(duration: duration)

            return result

        } catch {
            // 记录失败
            let duration = Date().timeIntervalSince(startTime)
            recordFailure(duration: duration, error: error)

            throw error
        }
    }

    /// 执行操作（带超时）
    ///
    /// - Parameters:
    ///   - timeout: 超时时间（秒）
    ///   - operation: 要执行的操作
    /// - Returns: 操作结果
    /// - Throws: 操作错误、超时错误或熔断器错误
    public func execute<T: Sendable>(
        timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await execute {
            try await withTimeout(timeout) {
                try await operation()
            }
        }
    }

    // MARK: - State Management

    /// 获取当前状态
    public func getState() -> CircuitBreakerState {
        state
    }

    /// 手动重置熔断器（重置为关闭状态）
    public func reset() {
        transitionTo(.closed)
        callHistory.removeAll()
        halfOpenCallCount = 0
    }

    /// 手动打开熔断器
    public func trip() {
        transitionTo(.open(openedAt: Date()))
    }

    /// 设置状态变更回调
    public func onStateChange(_ callback: @escaping @Sendable (CircuitBreakerState, CircuitBreakerState) -> Void) {
        self.onStateChange = callback
    }

    // MARK: - Statistics

    /// 获取统计信息
    public func getStatistics() -> (
        totalCalls: Int,
        successfulCalls: Int,
        failedCalls: Int,
        slowCalls: Int,
        rejectedCalls: Int,
        currentState: CircuitBreakerState,
        failureRate: Double,
        slowCallRate: Double
    ) {
        let metrics = calculateMetrics()

        return (
            totalCalls: stats.totalCalls,
            successfulCalls: stats.successfulCalls,
            failedCalls: stats.failedCalls,
            slowCalls: stats.slowCalls,
            rejectedCalls: stats.rejectedCalls,
            currentState: state,
            failureRate: metrics.failureRate,
            slowCallRate: metrics.slowCallRate
        )
    }

    // MARK: - Private Methods

    /// 检查并更新状态
    private func checkAndUpdateState() throws {
        // 清理过期记录
        cleanupOldRecords()

        switch state {
        case .closed:
            // 检查是否应该打开
            if shouldOpenCircuit() {
                transitionTo(.open(openedAt: Date()))
                stats.rejectedCalls += 1
                throw CircuitBreakerError.circuitOpen
            }

        case .open(let openedAt):
            // 检查是否应该转为半开
            let elapsed = Date().timeIntervalSince(openedAt)
            if elapsed >= configuration.resetTimeout {
                transitionTo(.halfOpen)
            } else {
                stats.rejectedCalls += 1
                throw CircuitBreakerError.circuitOpen
            }

        case .halfOpen:
            // 检查是否超出半开状态的最大请求数
            if halfOpenCallCount >= configuration.halfOpenMaxRequests {
                stats.rejectedCalls += 1
                throw CircuitBreakerError.halfOpenLimitExceeded
            }
            halfOpenCallCount += 1
        }
    }

    /// 记录成功调用
    private func recordSuccess(duration: TimeInterval) {
        stats.totalCalls += 1
        stats.successfulCalls += 1

        let isSlow = isSlowCall(duration: duration)
        if isSlow {
            stats.slowCalls += 1
        }

        let record = CallRecord(
            timestamp: Date(),
            isSuccess: true,
            duration: duration
        )
        callHistory.append(record)

        // 半开状态处理
        if case .halfOpen = state {
            let metrics = calculateMetrics()
            if metrics.successRate >= configuration.halfOpenSuccessThreshold {
                // 探测成功，关闭熔断器
                transitionTo(.closed)
                halfOpenCallCount = 0
            }
        }
    }

    /// 记录失败调用
    private func recordFailure(duration: TimeInterval, error: Error) {
        stats.totalCalls += 1
        stats.failedCalls += 1

        let record = CallRecord(
            timestamp: Date(),
            isSuccess: false,
            duration: duration
        )
        callHistory.append(record)

        // 半开状态处理
        if case .halfOpen = state {
            // 探测失败，重新打开熔断器
            transitionTo(.open(openedAt: Date()))
            halfOpenCallCount = 0
        }
    }

    /// 判断是否应该打开熔断器
    private func shouldOpenCircuit() -> Bool {
        let metrics = calculateMetrics()

        // 请求数不足，不触发熔断
        guard metrics.totalCalls >= configuration.minimumRequests else {
            return false
        }

        // 检查失败率
        if metrics.failureRate > configuration.failureThreshold {
            return true
        }

        // 检查慢调用率（如果配置了）
        if let threshold = configuration.slowCallRateThreshold,
           metrics.slowCallRate > threshold {
            return true
        }

        return false
    }

    /// 计算指标
    private func calculateMetrics() -> (
        totalCalls: Int,
        failedCalls: Int,
        slowCalls: Int,
        failureRate: Double,
        slowCallRate: Double,
        successRate: Double
    ) {
        guard !callHistory.isEmpty else {
            return (0, 0, 0, 0.0, 0.0, 1.0)
        }

        let total = callHistory.count
        let failed = callHistory.filter { !$0.isSuccess }.count
        let slow = callHistory.filter { isSlowCall(duration: $0.duration) }.count
        let success = total - failed

        let failureRate = Double(failed) / Double(total)
        let slowCallRate = Double(slow) / Double(total)
        let successRate = Double(success) / Double(total)

        return (total, failed, slow, failureRate, slowCallRate, successRate)
    }

    /// 判断是否为慢调用
    private func isSlowCall(duration: TimeInterval) -> Bool {
        guard let threshold = configuration.slowCallThreshold else {
            return false
        }
        return duration >= threshold
    }

    /// 清理过期记录
    private func cleanupOldRecords() {
        let cutoffTime = Date().addingTimeInterval(-configuration.windowDuration)
        callHistory.removeAll { $0.timestamp < cutoffTime }
    }

    /// 状态转换
    private func transitionTo(_ newState: CircuitBreakerState) {
        let oldState = state
        guard !isSameState(oldState, newState) else { return }

        state = newState
        stats.stateTransitions += 1

        // 触发回调
        onStateChange?(oldState, newState)
    }

    /// 判断是否为相同状态
    private func isSameState(_ s1: CircuitBreakerState, _ s2: CircuitBreakerState) -> Bool {
        switch (s1, s2) {
        case (.closed, .closed), (.halfOpen, .halfOpen):
            return true
        case (.open, .open):
            return true
        default:
            return false
        }
    }

    /// 带超时执行
    private func withTimeout<T: Sendable>(
        _ timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // 执行操作
            group.addTask {
                try await operation()
            }

            // 超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NexusError.requestTimeout
            }

            // 返回第一个完成的结果
            guard let result = try await group.next() else {
                throw NexusError.requestTimeout
            }

            // 取消其他任务
            group.cancelAll()

            return result
        }
    }
}

// MARK: - CustomStringConvertible

extension CircuitBreaker: CustomStringConvertible {
    public nonisolated var description: String {
        "CircuitBreaker(name: \(name))"
    }
}

extension CircuitBreakerState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .closed:
            return "Closed"
        case .open(let openedAt):
            return "Open (since \(openedAt))"
        case .halfOpen:
            return "HalfOpen"
        }
    }
}

// MARK: - Circuit Breaker Registry

/// 熔断器注册表
///
/// 用于管理多个熔断器实例。
public actor CircuitBreakerRegistry {
    private var breakers: [String: CircuitBreaker] = [:]

    public static let shared = CircuitBreakerRegistry()

    private init() {}

    /// 获取或创建熔断器
    /// - Parameters:
    ///   - name: 熔断器名称
    ///   - configuration: 配置（仅在创建时使用）
    /// - Returns: 熔断器实例
    public func get(
        name: String,
        configuration: CircuitBreakerConfiguration = .default
    ) -> CircuitBreaker {
        if let breaker = breakers[name] {
            return breaker
        }

        let breaker = CircuitBreaker(name: name, configuration: configuration)
        breakers[name] = breaker
        return breaker
    }

    /// 移除熔断器
    /// - Parameter name: 熔断器名称
    public func remove(name: String) {
        breakers.removeValue(forKey: name)
    }

    /// 获取所有熔断器
    public func all() -> [CircuitBreaker] {
        Array(breakers.values)
    }

    /// 重置所有熔断器
    public func resetAll() async {
        for breaker in breakers.values {
            await breaker.reset()
        }
    }
}
