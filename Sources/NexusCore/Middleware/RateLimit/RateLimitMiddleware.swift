//
//  RateLimitMiddleware.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  流量控制中间件

import Foundation

// MARK: - Rate Limit Middleware

/// 流量控制中间件
///
/// 限制数据传输速率，防止过载和滥用。
///
/// ## 功能特性
///
/// - 多种速率限制算法 (TokenBucket, LeakyBucket, FixedWindow, SlidingWindow)
/// - 双向速率限制 (出站/入站)
/// - 自动降级和重试
/// - 详细统计信息
///
/// ## 使用示例
///
/// ```swift
/// // 使用令牌桶算法，每秒100KB
/// let rateLimit = RateLimitMiddleware(
///     algorithm: .tokenBucket(capacity: 102400, refillRate: 102400),
///     limitOutgoing: true,
///     limitIncoming: false
/// )
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(rateLimit)
///     .connect()
/// ```
public actor RateLimitMiddleware: Middleware {

    // MARK: - Properties

    public let name = "RateLimitMiddleware"
    public let priority = 30  // 在压缩之前，加密之后

    /// 速率限制算法
    private let algorithm: any RateLimitAlgorithm

    /// 是否限制出站流量
    public let limitOutgoing: Bool

    /// 是否限制入站流量
    public let limitIncoming: Bool

    /// 超时时间
    private let timeout: TimeInterval?

    /// 统计信息
    private var stats: Statistics

    private struct Statistics {
        var totalOutgoingBytes: Int64 = 0
        var totalIncomingBytes: Int64 = 0
        var outgoingThrottled: Int = 0
        var incomingThrottled: Int = 0
        var outgoingRejected: Int = 0
        var incomingRejected: Int = 0
        var totalWaitTime: TimeInterval = 0
    }

    // MARK: - Algorithm Type

    /// 速率限制算法类型
    public enum AlgorithmType: Sendable {
        /// 令牌桶算法
        case tokenBucket(capacity: Double, refillRate: Double)

        /// 漏桶算法
        case leakyBucket(capacity: Double, leakRate: Double)

        /// 固定窗口算法
        case fixedWindow(windowSize: TimeInterval, maxRequests: Int)

        /// 滑动窗口算法
        case slidingWindow(windowSize: TimeInterval, maxRequests: Int)

        /// 并发限制
        case concurrent(maxConcurrent: Int)
    }

    // MARK: - Initialization

    /// 初始化流量控制中间件
    /// - Parameters:
    ///   - algorithm: 速率限制算法
    ///   - limitOutgoing: 是否限制出站流量
    ///   - limitIncoming: 是否限制入站流量
    ///   - timeout: 获取许可的超时时间
    public init(
        algorithm: AlgorithmType,
        limitOutgoing: Bool = true,
        limitIncoming: Bool = false,
        timeout: TimeInterval? = 5.0
    ) {
        switch algorithm {
        case .tokenBucket(let capacity, let refillRate):
            self.algorithm = TokenBucketRateLimiter(capacity: capacity, refillRate: refillRate)

        case .leakyBucket(let capacity, let leakRate):
            self.algorithm = LeakyBucketRateLimiter(capacity: capacity, leakRate: leakRate)

        case .fixedWindow(let windowSize, let maxRequests):
            self.algorithm = FixedWindowRateLimiter(windowSize: windowSize, maxRequests: maxRequests)

        case .slidingWindow(let windowSize, let maxRequests):
            self.algorithm = SlidingWindowRateLimiter(windowSize: windowSize, maxRequests: maxRequests)

        case .concurrent(let maxConcurrent):
            self.algorithm = ConcurrentRequestLimiter(maxConcurrent: maxConcurrent)
        }

        self.limitOutgoing = limitOutgoing
        self.limitIncoming = limitIncoming
        self.timeout = timeout
        self.stats = Statistics()
    }

    /// 使用自定义算法初始化
    public init(
        customAlgorithm: any RateLimitAlgorithm,
        limitOutgoing: Bool = true,
        limitIncoming: Bool = false,
        timeout: TimeInterval? = 5.0
    ) {
        self.algorithm = customAlgorithm
        self.limitOutgoing = limitOutgoing
        self.limitIncoming = limitIncoming
        self.timeout = timeout
        self.stats = Statistics()
    }

    // MARK: - Middleware Protocol

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard limitOutgoing else { return data }

        stats.totalOutgoingBytes += Int64(data.count)

        // 尝试获取许可
        let cost = data.count
        let startTime = Date()

        do {
            let acquired = try await algorithm.acquire(cost: cost, timeout: timeout)

            let waitTime = Date().timeIntervalSince(startTime)
            stats.totalWaitTime += waitTime

            if acquired {
                if waitTime > 0.001 {
                    stats.outgoingThrottled += 1
                    await logDebug("出站流量被限制: \(data.count) bytes, 等待 \(waitTime)s")
                }
                return data
            } else {
                stats.outgoingRejected += 1
                await logWarning("出站流量被拒绝: \(data.count) bytes")
                throw RateLimitError.rateLimitExceeded(retryAfter: timeout)
            }
        } catch {
            stats.outgoingRejected += 1
            throw error
        }
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard limitIncoming else { return data }

        stats.totalIncomingBytes += Int64(data.count)

        // 尝试获取许可
        let cost = data.count
        let startTime = Date()

        do {
            let acquired = try await algorithm.acquire(cost: cost, timeout: timeout)

            let waitTime = Date().timeIntervalSince(startTime)
            stats.totalWaitTime += waitTime

            if acquired {
                if waitTime > 0.001 {
                    stats.incomingThrottled += 1
                    await logDebug("入站流量被限制: \(data.count) bytes, 等待 \(waitTime)s")
                }
                return data
            } else {
                stats.incomingRejected += 1
                await logWarning("入站流量被拒绝: \(data.count) bytes")
                throw RateLimitError.rateLimitExceeded(retryAfter: timeout)
            }
        } catch {
            stats.incomingRejected += 1
            throw error
        }
    }

    // MARK: - Statistics and Management

    /// 获取统计信息
    public func getStatistics() async -> RateLimitStatistics {
        let rateInfo = await algorithm.getCurrentRate()

        return RateLimitStatistics(
            totalOutgoingBytes: stats.totalOutgoingBytes,
            totalIncomingBytes: stats.totalIncomingBytes,
            outgoingThrottled: stats.outgoingThrottled,
            incomingThrottled: stats.incomingThrottled,
            outgoingRejected: stats.outgoingRejected,
            incomingRejected: stats.incomingRejected,
            totalWaitTime: stats.totalWaitTime,
            currentAvailable: rateInfo.available,
            currentCapacity: rateInfo.capacity,
            utilizationRate: rateInfo.utilizationRate
        )
    }

    /// 获取当前速率信息
    public func getRateInfo() async -> RateInfo {
        await algorithm.getCurrentRate()
    }

    /// 重置统计和算法状态
    public func reset() async {
        stats = Statistics()
        await algorithm.reset()
    }
}

// MARK: - Rate Limit Statistics

/// 流量控制统计信息
public struct RateLimitStatistics: Sendable {
    /// 总出站字节数
    public let totalOutgoingBytes: Int64

    /// 总入站字节数
    public let totalIncomingBytes: Int64

    /// 出站被限制次数
    public let outgoingThrottled: Int

    /// 入站被限制次数
    public let incomingThrottled: Int

    /// 出站被拒绝次数
    public let outgoingRejected: Int

    /// 入站被拒绝次数
    public let incomingRejected: Int

    /// 总等待时间（秒）
    public let totalWaitTime: TimeInterval

    /// 当前可用配额
    public let currentAvailable: Double

    /// 当前总容量
    public let currentCapacity: Double

    /// 当前使用率 (0.0 - 1.0)
    public let utilizationRate: Double

    public init(
        totalOutgoingBytes: Int64,
        totalIncomingBytes: Int64,
        outgoingThrottled: Int,
        incomingThrottled: Int,
        outgoingRejected: Int,
        incomingRejected: Int,
        totalWaitTime: TimeInterval,
        currentAvailable: Double,
        currentCapacity: Double,
        utilizationRate: Double
    ) {
        self.totalOutgoingBytes = totalOutgoingBytes
        self.totalIncomingBytes = totalIncomingBytes
        self.outgoingThrottled = outgoingThrottled
        self.incomingThrottled = incomingThrottled
        self.outgoingRejected = outgoingRejected
        self.incomingRejected = incomingRejected
        self.totalWaitTime = totalWaitTime
        self.currentAvailable = currentAvailable
        self.currentCapacity = currentCapacity
        self.utilizationRate = utilizationRate
    }
}

// MARK: - Convenience Initializers

extension RateLimitMiddleware {

    /// 创建基于字节速率的流量控制（令牌桶）
    /// - Parameters:
    ///   - bytesPerSecond: 每秒字节数
    ///   - burstSize: 突发大小（默认为2倍速率）
    ///   - limitOutgoing: 是否限制出站
    ///   - limitIncoming: 是否限制入站
    public static func bytesPerSecond(
        _ bytesPerSecond: Double,
        burstSize: Double? = nil,
        limitOutgoing: Bool = true,
        limitIncoming: Bool = false
    ) -> RateLimitMiddleware {
        let burst = burstSize ?? (bytesPerSecond * 2)
        return RateLimitMiddleware(
            algorithm: .tokenBucket(capacity: burst, refillRate: bytesPerSecond),
            limitOutgoing: limitOutgoing,
            limitIncoming: limitIncoming
        )
    }

    /// 创建基于请求数的流量控制（滑动窗口）
    /// - Parameters:
    ///   - requestsPerSecond: 每秒请求数
    ///   - windowSize: 窗口大小
    ///   - limitOutgoing: 是否限制出站
    ///   - limitIncoming: 是否限制入站
    public static func requestsPerSecond(
        _ requestsPerSecond: Int,
        windowSize: TimeInterval = 1.0,
        limitOutgoing: Bool = true,
        limitIncoming: Bool = false
    ) -> RateLimitMiddleware {
        RateLimitMiddleware(
            algorithm: .slidingWindow(windowSize: windowSize, maxRequests: requestsPerSecond),
            limitOutgoing: limitOutgoing,
            limitIncoming: limitIncoming
        )
    }

    /// 创建并发限制
    /// - Parameters:
    ///   - maxConcurrent: 最大并发数
    ///   - limitOutgoing: 是否限制出站
    ///   - limitIncoming: 是否限制入站
    public static func concurrent(
        _ maxConcurrent: Int,
        limitOutgoing: Bool = true,
        limitIncoming: Bool = false
    ) -> RateLimitMiddleware {
        RateLimitMiddleware(
            algorithm: .concurrent(maxConcurrent: maxConcurrent),
            limitOutgoing: limitOutgoing,
            limitIncoming: limitIncoming
        )
    }
}
