//
//  RateLimitAlgorithm.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  速率限制算法

import Foundation

// MARK: - Rate Limit Algorithm

/// 速率限制算法协议
public protocol RateLimitAlgorithm: Sendable {
    /// 算法名称
    var name: String { get }

    /// 尝试获取许可
    /// - Parameter cost: 操作成本（默认为1）
    /// - Returns: 是否允许通过
    func tryAcquire(cost: Int) async -> Bool

    /// 等待获取许可
    /// - Parameter cost: 操作成本
    /// - Parameter timeout: 超时时间
    /// - Returns: 是否成功获取
    func acquire(cost: Int, timeout: TimeInterval?) async throws -> Bool

    /// 获取当前速率信息
    func getCurrentRate() async -> RateInfo

    /// 重置算法状态
    func reset() async
}

// MARK: - Rate Info

/// 速率信息
public struct RateInfo: Sendable {
    /// 当前可用令牌/配额
    public let available: Double

    /// 总容量
    public let capacity: Double

    /// 当前使用率 (0.0 - 1.0)
    public var utilizationRate: Double {
        guard capacity > 0 else { return 0.0 }
        return (capacity - available) / capacity
    }

    /// 预计恢复时间（秒）
    public let estimatedRecoveryTime: TimeInterval?

    public init(
        available: Double,
        capacity: Double,
        estimatedRecoveryTime: TimeInterval? = nil
    ) {
        self.available = available
        self.capacity = capacity
        self.estimatedRecoveryTime = estimatedRecoveryTime
    }
}

// MARK: - Rate Limit Error

/// 速率限制错误
public enum RateLimitError: Error, Sendable {
    /// 超过速率限制
    case rateLimitExceeded(retryAfter: TimeInterval?)

    /// 获取超时
    case acquireTimeout

    /// 成本过高
    case costTooHigh(cost: Int, capacity: Int)
}

// MARK: - Token Bucket Algorithm

/// 令牌桶算法
///
/// 以固定速率生成令牌，请求消耗令牌。
/// 支持突发流量，但长期限制平均速率。
public actor TokenBucketRateLimiter: RateLimitAlgorithm {
    public let name = "TokenBucket"

    /// 桶容量
    private let capacity: Double

    /// 补充速率（令牌/秒）
    private let refillRate: Double

    /// 当前令牌数
    private var tokens: Double

    /// 上次补充时间
    private var lastRefillTime: Date

    public init(capacity: Double, refillRate: Double) {
        self.capacity = capacity
        self.refillRate = refillRate
        self.tokens = capacity
        self.lastRefillTime = Date()
    }

    public func tryAcquire(cost: Int = 1) async -> Bool {
        await refill()

        guard Double(cost) <= capacity else {
            return false
        }

        if tokens >= Double(cost) {
            tokens -= Double(cost)
            return true
        }

        return false
    }

    public func acquire(cost: Int = 1, timeout: TimeInterval? = nil) async throws -> Bool {
        let startTime = Date()

        while true {
            if await tryAcquire(cost: cost) {
                return true
            }

            // 检查超时
            if let timeout = timeout {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= timeout {
                    throw RateLimitError.acquireTimeout
                }
            }

            // 计算需要等待的时间
            let tokensNeeded = Double(cost) - tokens
            let waitTime = tokensNeeded / refillRate

            // 等待一小段时间
            try await Task.sleep(nanoseconds: UInt64(min(waitTime, 0.1) * 1_000_000_000))
        }
    }

    public func getCurrentRate() async -> RateInfo {
        await refill()
        return RateInfo(
            available: tokens,
            capacity: capacity,
            estimatedRecoveryTime: tokens < capacity ? (capacity - tokens) / refillRate : 0
        )
    }

    public func reset() async {
        tokens = capacity
        lastRefillTime = Date()
    }

    /// 补充令牌
    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefillTime)

        let newTokens = elapsed * refillRate
        tokens = min(capacity, tokens + newTokens)
        lastRefillTime = now
    }
}

// MARK: - Leaky Bucket Algorithm

/// 漏桶算法
///
/// 以固定速率处理请求，超出速率的请求被丢弃或排队。
/// 严格限制输出速率，平滑突发流量。
public actor LeakyBucketRateLimiter: RateLimitAlgorithm {
    public let name = "LeakyBucket"

    /// 桶容量
    private let capacity: Double

    /// 漏出速率（请求/秒）
    private let leakRate: Double

    /// 当前水位
    private var waterLevel: Double

    /// 上次漏出时间
    private var lastLeakTime: Date

    public init(capacity: Double, leakRate: Double) {
        self.capacity = capacity
        self.leakRate = leakRate
        self.waterLevel = 0.0
        self.lastLeakTime = Date()
    }

    public func tryAcquire(cost: Int = 1) async -> Bool {
        await leak()

        if waterLevel + Double(cost) <= capacity {
            waterLevel += Double(cost)
            return true
        }

        return false
    }

    public func acquire(cost: Int = 1, timeout: TimeInterval? = nil) async throws -> Bool {
        let startTime = Date()

        while true {
            if await tryAcquire(cost: cost) {
                return true
            }

            if let timeout = timeout {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= timeout {
                    throw RateLimitError.acquireTimeout
                }
            }

            // 等待水位下降
            let spaceNeeded = waterLevel + Double(cost) - capacity
            let waitTime = spaceNeeded / leakRate

            try await Task.sleep(nanoseconds: UInt64(min(waitTime, 0.1) * 1_000_000_000))
        }
    }

    public func getCurrentRate() async -> RateInfo {
        await leak()
        return RateInfo(
            available: capacity - waterLevel,
            capacity: capacity,
            estimatedRecoveryTime: waterLevel > 0 ? waterLevel / leakRate : 0
        )
    }

    public func reset() async {
        waterLevel = 0.0
        lastLeakTime = Date()
    }

    /// 漏水
    private func leak() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastLeakTime)

        let leaked = elapsed * leakRate
        waterLevel = max(0, waterLevel - leaked)
        lastLeakTime = now
    }
}

// MARK: - Fixed Window Algorithm

/// 固定窗口算法
///
/// 在固定时间窗口内限制请求数量。
/// 简单高效，但可能出现窗口边界突发。
public actor FixedWindowRateLimiter: RateLimitAlgorithm {
    public let name = "FixedWindow"

    /// 窗口大小（秒）
    private let windowSize: TimeInterval

    /// 窗口内最大请求数
    private let maxRequests: Int

    /// 当前窗口开始时间
    private var windowStart: Date

    /// 当前窗口请求计数
    private var requestCount: Int

    public init(windowSize: TimeInterval, maxRequests: Int) {
        self.windowSize = windowSize
        self.maxRequests = maxRequests
        self.windowStart = Date()
        self.requestCount = 0
    }

    public func tryAcquire(cost: Int = 1) async -> Bool {
        await checkWindow()

        if requestCount + cost <= maxRequests {
            requestCount += cost
            return true
        }

        return false
    }

    public func acquire(cost: Int = 1, timeout: TimeInterval? = nil) async throws -> Bool {
        let startTime = Date()

        while true {
            if await tryAcquire(cost: cost) {
                return true
            }

            if let timeout = timeout {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= timeout {
                    throw RateLimitError.acquireTimeout
                }
            }

            // 等待到下一个窗口
            let now = Date()
            let windowElapsed = now.timeIntervalSince(windowStart)
            let waitTime = windowSize - windowElapsed

            if waitTime > 0 {
                try await Task.sleep(nanoseconds: UInt64(min(waitTime, 0.1) * 1_000_000_000))
            }
        }
    }

    public func getCurrentRate() async -> RateInfo {
        await checkWindow()
        return RateInfo(
            available: Double(maxRequests - requestCount),
            capacity: Double(maxRequests),
            estimatedRecoveryTime: requestCount >= maxRequests ? windowSize - Date().timeIntervalSince(windowStart) : 0
        )
    }

    public func reset() async {
        windowStart = Date()
        requestCount = 0
    }

    /// 检查并重置窗口
    private func checkWindow() {
        let now = Date()
        let elapsed = now.timeIntervalSince(windowStart)

        if elapsed >= windowSize {
            windowStart = now
            requestCount = 0
        }
    }
}

// MARK: - Sliding Window Algorithm

/// 滑动窗口算法
///
/// 使用滑动时间窗口限制请求速率。
/// 比固定窗口更平滑，避免边界突发。
public actor SlidingWindowRateLimiter: RateLimitAlgorithm {
    public let name = "SlidingWindow"

    /// 窗口大小（秒）
    private let windowSize: TimeInterval

    /// 窗口内最大请求数
    private let maxRequests: Int

    /// 请求时间戳队列
    private var timestamps: [Date]

    public init(windowSize: TimeInterval, maxRequests: Int) {
        self.windowSize = windowSize
        self.maxRequests = maxRequests
        self.timestamps = []
    }

    public func tryAcquire(cost: Int = 1) async -> Bool {
        await cleanupOldTimestamps()

        if timestamps.count + cost <= maxRequests {
            for _ in 0..<cost {
                timestamps.append(Date())
            }
            return true
        }

        return false
    }

    public func acquire(cost: Int = 1, timeout: TimeInterval? = nil) async throws -> Bool {
        let startTime = Date()

        while true {
            if await tryAcquire(cost: cost) {
                return true
            }

            if let timeout = timeout {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= timeout {
                    throw RateLimitError.acquireTimeout
                }
            }

            // 等待最旧的时间戳过期
            if let oldestTimestamp = timestamps.first {
                let waitTime = windowSize - Date().timeIntervalSince(oldestTimestamp)
                if waitTime > 0 {
                    try await Task.sleep(nanoseconds: UInt64(min(waitTime, 0.1) * 1_000_000_000))
                }
            } else {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
        }
    }

    public func getCurrentRate() async -> RateInfo {
        await cleanupOldTimestamps()
        return RateInfo(
            available: Double(maxRequests - timestamps.count),
            capacity: Double(maxRequests),
            estimatedRecoveryTime: timestamps.first.map { windowSize - Date().timeIntervalSince($0) }
        )
    }

    public func reset() async {
        timestamps.removeAll()
    }

    /// 清理过期时间戳
    private func cleanupOldTimestamps() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-windowSize)
        timestamps.removeAll { $0 < cutoff }
    }
}

// MARK: - Concurrent Request Limiter

/// 并发请求限制器
///
/// 限制同时进行的请求数量。
public actor ConcurrentRequestLimiter: RateLimitAlgorithm {
    public let name = "ConcurrentRequest"

    /// 最大并发数
    private let maxConcurrent: Int

    /// 当前并发数
    private var currentConcurrent: Int

    /// 等待队列
    private var waitingQueue: [CheckedContinuation<Bool, Error>]

    public init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
        self.currentConcurrent = 0
        self.waitingQueue = []
    }

    public func tryAcquire(cost: Int = 1) async -> Bool {
        if currentConcurrent + cost <= maxConcurrent {
            currentConcurrent += cost
            return true
        }
        return false
    }

    public func acquire(cost: Int = 1, timeout: TimeInterval? = nil) async throws -> Bool {
        if await tryAcquire(cost: cost) {
            return true
        }

        // 加入等待队列
        return try await withCheckedThrowingContinuation { continuation in
            waitingQueue.append(continuation)
        }
    }

    /// 释放许可
    public func release(cost: Int = 1) async {
        currentConcurrent = max(0, currentConcurrent - cost)

        // 唤醒等待的请求
        while !waitingQueue.isEmpty && currentConcurrent < maxConcurrent {
            let continuation = waitingQueue.removeFirst()
            currentConcurrent += 1
            continuation.resume(returning: true)
        }
    }

    public func getCurrentRate() async -> RateInfo {
        RateInfo(
            available: Double(maxConcurrent - currentConcurrent),
            capacity: Double(maxConcurrent)
        )
    }

    public func reset() async {
        currentConcurrent = 0
        for continuation in waitingQueue {
            continuation.resume(throwing: RateLimitError.acquireTimeout)
        }
        waitingQueue.removeAll()
    }
}
