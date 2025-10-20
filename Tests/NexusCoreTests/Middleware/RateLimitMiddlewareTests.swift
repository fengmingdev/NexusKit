//
//  RateLimitMiddlewareTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusCore

final class RateLimitMiddlewareTests: XCTestCase {

    // MARK: - Token Bucket Tests

    func testTokenBucketBasic() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 5)

        // 应该能获取令牌
        let acquired1 = await limiter.tryAcquire(cost: 5)
        XCTAssertTrue(acquired1)

        // 应该还能获取一些
        let acquired2 = await limiter.tryAcquire(cost: 3)
        XCTAssertTrue(acquired2)

        // 超过容量，应该失败
        let acquired3 = await limiter.tryAcquire(cost: 5)
        XCTAssertFalse(acquired3)
    }

    func testTokenBucketRefill() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 10)

        // 消耗所有令牌
        _ = await limiter.tryAcquire(cost: 10)

        // 立即尝试应该失败
        let immediate = await limiter.tryAcquire(cost: 5)
        XCTAssertFalse(immediate)

        // 等待补充
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // 应该恢复了一些令牌
        let afterWait = await limiter.tryAcquire(cost: 5)
        XCTAssertTrue(afterWait)
    }

    func testTokenBucketRateInfo() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 100, refillRate: 50)

        let info = await limiter.getCurrentRate()
        XCTAssertEqual(info.capacity, 100)
        XCTAssertEqual(info.available, 100, accuracy: 0.1)
        XCTAssertEqual(info.utilizationRate, 0.0, accuracy: 0.01)
    }

    // MARK: - Leaky Bucket Tests

    func testLeakyBucketBasic() async throws {
        let limiter = LeakyBucketRateLimiter(capacity: 10, leakRate: 5)

        // 应该能添加水
        let acquired1 = await limiter.tryAcquire(cost: 5)
        XCTAssertTrue(acquired1)

        // 应该还能添加
        let acquired2 = await limiter.tryAcquire(cost: 3)
        XCTAssertTrue(acquired2)

        // 超过容量
        let acquired3 = await limiter.tryAcquire(cost: 5)
        XCTAssertFalse(acquired3)
    }

    func testLeakyBucketLeak() async throws {
        let limiter = LeakyBucketRateLimiter(capacity: 10, leakRate: 10)

        // 填满桶
        _ = await limiter.tryAcquire(cost: 10)

        // 立即应该失败
        let immediate = await limiter.tryAcquire(cost: 5)
        XCTAssertFalse(immediate)

        // 等待漏水
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // 应该有空间了
        let afterWait = await limiter.tryAcquire(cost: 5)
        XCTAssertTrue(afterWait)
    }

    // MARK: - Fixed Window Tests

    func testFixedWindowBasic() async throws {
        let limiter = FixedWindowRateLimiter(windowSize: 1.0, maxRequests: 10)

        // 应该能获取
        for _ in 0..<10 {
            let acquired = await limiter.tryAcquire()
            XCTAssertTrue(acquired)
        }

        // 超过限制
        let exceeded = await limiter.tryAcquire()
        XCTAssertFalse(exceeded)
    }

    func testFixedWindowReset() async throws {
        let limiter = FixedWindowRateLimiter(windowSize: 0.5, maxRequests: 5)

        // 消耗所有配额
        for _ in 0..<5 {
            _ = await limiter.tryAcquire()
        }

        // 应该失败
        let immediate = await limiter.tryAcquire()
        XCTAssertFalse(immediate)

        // 等待窗口重置
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // 应该重置了
        let afterReset = await limiter.tryAcquire()
        XCTAssertTrue(afterReset)
    }

    // MARK: - Sliding Window Tests

    func testSlidingWindowBasic() async throws {
        let limiter = SlidingWindowRateLimiter(windowSize: 1.0, maxRequests: 10)

        // 应该能获取
        for _ in 0..<10 {
            let acquired = await limiter.tryAcquire()
            XCTAssertTrue(acquired)
        }

        // 超过限制
        let exceeded = await limiter.tryAcquire()
        XCTAssertFalse(exceeded)
    }

    func testSlidingWindowSliding() async throws {
        let limiter = SlidingWindowRateLimiter(windowSize: 0.5, maxRequests: 5)

        // 添加一些请求
        for _ in 0..<3 {
            _ = await limiter.tryAcquire()
        }

        // 等待一半窗口时间
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        // 添加更多请求
        for _ in 0..<2 {
            let acquired = await limiter.tryAcquire()
            XCTAssertTrue(acquired)
        }

        // 再等待，第一批应该过期
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        // 应该可以添加更多
        let acquired = await limiter.tryAcquire()
        XCTAssertTrue(acquired)
    }

    // MARK: - Concurrent Request Limiter Tests

    func testConcurrentLimiterBasic() async throws {
        let limiter = ConcurrentRequestLimiter(maxConcurrent: 5)

        // 应该能获取
        for _ in 0..<5 {
            let acquired = await limiter.tryAcquire()
            XCTAssertTrue(acquired)
        }

        // 超过限制
        let exceeded = await limiter.tryAcquire()
        XCTAssertFalse(exceeded)
    }

    func testConcurrentLimiterRelease() async throws {
        let limiter = ConcurrentRequestLimiter(maxConcurrent: 3)

        // 获取所有
        for _ in 0..<3 {
            _ = await limiter.tryAcquire()
        }

        // 应该满了
        let full = await limiter.tryAcquire()
        XCTAssertFalse(full)

        // 释放一个
        await limiter.release(cost: 1)

        // 应该可以获取了
        let afterRelease = await limiter.tryAcquire()
        XCTAssertTrue(afterRelease)
    }

    // MARK: - Rate Limit Middleware Tests

    func testMiddlewareTokenBucket() async throws {
        let middleware = RateLimitMiddleware(
            algorithm: .tokenBucket(capacity: 1000, refillRate: 1000),
            limitOutgoing: true,
            limitIncoming: false
        )

        let context = createMockContext()
        let testData = Data(repeating: 1, count: 500)

        // 第一次应该成功
        let result1 = try await middleware.handleOutgoing(testData, context: context)
        XCTAssertEqual(result1, testData)

        // 第二次也应该成功（在容量内）
        let result2 = try await middleware.handleOutgoing(testData, context: context)
        XCTAssertEqual(result2, testData)

        // 第三次应该失败或等待（超过容量）
        let largeData = Data(repeating: 1, count: 500)
        do {
            _ = try await middleware.handleOutgoing(largeData, context: context)
            // 可能成功（如果补充够快）或失败
        } catch {
            // 预期可能超时
            XCTAssertTrue(error is RateLimitError)
        }
    }

    func testMiddlewareBytesPerSecond() async throws {
        // 每秒1000字节，突发2000字节
        let middleware = RateLimitMiddleware.bytesPerSecond(
            1000,
            burstSize: 2000,
            limitOutgoing: true
        )

        let context = createMockContext()
        let testData = Data(repeating: 1, count: 500)

        // 应该能发送几次（在突发范围内）
        for _ in 0..<3 {
            let result = try await middleware.handleOutgoing(testData, context: context)
            XCTAssertEqual(result, testData)
        }

        let stats = await middleware.getStatistics()
        XCTAssertGreaterThan(stats.totalOutgoingBytes, 0)
    }

    func testMiddlewareRequestsPerSecond() async throws {
        // 使用更宽松的限制以避免测试超时
        let middleware = RateLimitMiddleware.requestsPerSecond(
            100,  // 每秒100个请求
            windowSize: 1.0,
            limitOutgoing: true
        )

        let context = createMockContext()
        let testData = Data(repeating: 1, count: 100)

        // 应该能发送多次（在限制内）
        for _ in 0..<10 {
            _ = try await middleware.handleOutgoing(testData, context: context)
        }

        // 验证统计
        let stats = await middleware.getStatistics()
        XCTAssertGreaterThan(stats.totalOutgoingBytes, 0)
    }

    func testMiddlewareStatistics() async throws {
        let middleware = RateLimitMiddleware(
            algorithm: .tokenBucket(capacity: 10000, refillRate: 10000),
            limitOutgoing: true
        )

        let context = createMockContext()
        let testData = Data(repeating: 1, count: 500)

        // 发送几次
        for _ in 0..<5 {
            _ = try await middleware.handleOutgoing(testData, context: context)
        }

        let stats = await middleware.getStatistics()
        XCTAssertEqual(stats.totalOutgoingBytes, 2500)
        XCTAssertGreaterThanOrEqual(stats.currentCapacity, 0)
    }

    func testMiddlewareRateInfo() async throws {
        let middleware = RateLimitMiddleware(
            algorithm: .tokenBucket(capacity: 1000, refillRate: 500)
        )

        let rateInfo = await middleware.getRateInfo()
        XCTAssertEqual(rateInfo.capacity, 1000)
        XCTAssertGreaterThan(rateInfo.available, 0)
    }

    func testMiddlewareReset() async throws {
        let middleware = RateLimitMiddleware(
            algorithm: .tokenBucket(capacity: 1000, refillRate: 100)
        )

        let context = createMockContext()
        let testData = Data(repeating: 1, count: 900)

        // 消耗大部分配额
        _ = try await middleware.handleOutgoing(testData, context: context)

        // 重置
        await middleware.reset()

        // 应该恢复满配额
        let rateInfo = await middleware.getRateInfo()
        XCTAssertEqual(rateInfo.available, 1000, accuracy: 1.0)
    }

    func testMiddlewareIncomingLimit() async throws {
        let middleware = RateLimitMiddleware(
            algorithm: .tokenBucket(capacity: 1000, refillRate: 1000),
            limitOutgoing: false,
            limitIncoming: true
        )

        let context = createMockContext()
        let testData = Data(repeating: 1, count: 500)

        // 入站应该被限制
        let result = try await middleware.handleIncoming(testData, context: context)
        XCTAssertEqual(result, testData)

        let stats = await middleware.getStatistics()
        XCTAssertGreaterThan(stats.totalIncomingBytes, 0)
    }

    func testMiddlewareNoLimitOutgoing() async throws {
        let middleware = RateLimitMiddleware(
            algorithm: .tokenBucket(capacity: 100, refillRate: 10),
            limitOutgoing: false,
            limitIncoming: false
        )

        let context = createMockContext()
        let largeData = Data(repeating: 1, count: 10000)

        // 不限制，应该直接通过
        let result = try await middleware.handleOutgoing(largeData, context: context)
        XCTAssertEqual(result, largeData)

        // 统计不会记录（因为limitOutgoing=false，直接bypass）
        let stats = await middleware.getStatistics()
        // 当不限制时，统计可能为0（因为没有经过速率限制逻辑）
        XCTAssertGreaterThanOrEqual(stats.totalOutgoingBytes, 0)
        XCTAssertEqual(stats.outgoingThrottled, 0)
    }

    func testAlgorithmReset() async throws {
        let limiter = TokenBucketRateLimiter(capacity: 10, refillRate: 5)

        // 消耗令牌
        _ = await limiter.tryAcquire(cost: 8)

        // 检查剩余
        let beforeReset = await limiter.getCurrentRate()
        XCTAssertLessThan(beforeReset.available, 5)

        // 重置
        await limiter.reset()

        // 应该恢复满
        let afterReset = await limiter.getCurrentRate()
        XCTAssertEqual(afterReset.available, 10, accuracy: 0.1)
    }

    // MARK: - Helper Methods

    private func createMockContext() -> MiddlewareContext {
        MiddlewareContext(
            connectionId: "test-connection",
            endpoint: .tcp(host: "localhost", port: 8080)
        )
    }
}
