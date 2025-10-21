//
//  ReconnectionStrategyTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

/// 重连策略测试
final class ReconnectionStrategyTests: XCTestCase {

    // MARK: - Exponential Backoff Strategy Tests

    func testExponentialBackoffInitialDelay() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 5,
            multiplier: 2.0,
            jitter: true
        )

        let delay = strategy.nextDelay(attempt: 1, lastError: nil)

        // 第一次重连应该是初始延迟
        XCTAssertNotNil(delay)
        if let delay = delay {
            XCTAssertEqual(delay, 1.0, accuracy: 0.5) // 允许一定误差（因为有jitter）
        }
    }

    func testExponentialBackoffMultiplier() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 100.0,
            maxAttempts: 5,
            multiplier: 2.0,
            jitter: false // 禁用jitter以便精确测试
        )

        let delay1 = strategy.nextDelay(attempt: 1, lastError: nil)
        let delay2 = strategy.nextDelay(attempt: 2, lastError: nil)
        let delay3 = strategy.nextDelay(attempt: 3, lastError: nil)

        XCTAssertEqual(delay1, 1.0)
        XCTAssertEqual(delay2, 2.0)
        XCTAssertEqual(delay3, 4.0)
    }

    func testExponentialBackoffMaxDelay() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 10.0,
            maxAttempts: 10,
            multiplier: 2.0,
            jitter: false
        )

        // 第10次重连的延迟应该被限制在maxDelay
        let delay = strategy.nextDelay(attempt: 10, lastError: nil)

        XCTAssertNotNil(delay)
        if let delay = delay {
            XCTAssertLessThanOrEqual(delay, 10.0)
        }
    }

    func testExponentialBackoffMaxAttempts() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 3,
            multiplier: 2.0,
            jitter: true
        )

        let delay1 = strategy.nextDelay(attempt: 1, lastError: nil)
        let delay2 = strategy.nextDelay(attempt: 2, lastError: nil)
        let delay3 = strategy.nextDelay(attempt: 3, lastError: nil)
        let delay4 = strategy.nextDelay(attempt: 4, lastError: nil)

        XCTAssertNotNil(delay1)
        XCTAssertNotNil(delay2)
        XCTAssertNotNil(delay3)
        XCTAssertNil(delay4)
    }

    func testExponentialBackoffJitter() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 10.0,
            maxDelay: 100.0,
            maxAttempts: 5,
            multiplier: 2.0,
            jitter: true
        )

        // 测试多次获取延迟，应该有不同的值（由于jitter）
        var delays: [TimeInterval] = []
        for _ in 0..<10 {
            if let delay = strategy.nextDelay(attempt: 1, lastError: nil) {
                delays.append(delay)
            }
        }

        // 检查延迟在合理范围内（应该有变化）
        XCTAssertEqual(delays.count, 10)
        let allSame = delays.allSatisfy { $0 == delays.first }
        XCTAssertFalse(allSame, "Jitter should produce different delays")
    }

    func testExponentialBackoffReset() {
        var strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 3,
            multiplier: 2.0,
            jitter: false
        )

        // 达到最大尝试次数
        _ = strategy.nextDelay(attempt: 4, lastError: nil)

        // 重置
        strategy.reset()

        // 重置后应该可以重试
        let delay = strategy.nextDelay(attempt: 1, lastError: nil)
        XCTAssertNotNil(delay)
    }

    func testExponentialBackoffShouldReconnect() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 3,
            multiplier: 2.0,
            jitter: false
        )

        enum TestError: Error {
            case generic
        }

        // 默认实现应该总是返回true
        let shouldReconnect = strategy.shouldReconnect(error: TestError.generic)
        XCTAssertTrue(shouldReconnect)
    }

    // MARK: - Fixed Interval Strategy Tests

    func testFixedIntervalConstantDelay() {
        let strategy = FixedIntervalStrategy(
            interval: 5.0,
            maxAttempts: 5
        )

        let delay1 = strategy.nextDelay(attempt: 1, lastError: nil)
        let delay2 = strategy.nextDelay(attempt: 2, lastError: nil)
        let delay3 = strategy.nextDelay(attempt: 5, lastError: nil)

        XCTAssertEqual(delay1, 5.0)
        XCTAssertEqual(delay2, 5.0)
        XCTAssertEqual(delay3, 5.0)
    }

    func testFixedIntervalMaxAttempts() {
        let strategy = FixedIntervalStrategy(
            interval: 2.0,
            maxAttempts: 3
        )

        let delay1 = strategy.nextDelay(attempt: 1, lastError: nil)
        let delay3 = strategy.nextDelay(attempt: 3, lastError: nil)
        let delay4 = strategy.nextDelay(attempt: 4, lastError: nil)

        XCTAssertNotNil(delay1)
        XCTAssertNotNil(delay3)
        XCTAssertNil(delay4)
    }

    func testFixedIntervalReset() {
        var strategy = FixedIntervalStrategy(
            interval: 1.0,
            maxAttempts: 2
        )

        // 达到最大尝试次数
        _ = strategy.nextDelay(attempt: 3, lastError: nil)

        // 重置
        strategy.reset()

        // 重置后应该可以重试
        let delay = strategy.nextDelay(attempt: 1, lastError: nil)
        XCTAssertNotNil(delay)
    }

    func testFixedIntervalShouldReconnect() {
        let strategy = FixedIntervalStrategy(
            interval: 2.0,
            maxAttempts: 3
        )

        enum TestError: Error {
            case generic
        }

        // 默认实现应该总是返回true
        let shouldReconnect = strategy.shouldReconnect(error: TestError.generic)
        XCTAssertTrue(shouldReconnect)
    }

    // MARK: - Adaptive Strategy Tests

    func testAdaptiveStrategyInitialDelay() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 2.0,
            maxDelay: 60.0,
            maxAttempts: 5
        )

        let delay = await strategy.nextDelay(attempt: 1, lastError: nil)

        XCTAssertNotNil(delay)
        if let delay = delay {
            XCTAssertGreaterThan(delay, 0.0)
        }
    }

    func testAdaptiveStrategyRecordSuccess() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 2.0,
            maxDelay: 60.0,
            maxAttempts: 5
        )

        // 记录成功连接
        await strategy.recordSuccess()

        let delay = await strategy.nextDelay(attempt: 1, lastError: nil)

        XCTAssertNotNil(delay)
        if let delay = delay {
            XCTAssertGreaterThan(delay, 0.0)
        }
    }

    func testAdaptiveStrategyMultipleSuccesses() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 5.0,
            maxDelay: 60.0,
            maxAttempts: 5
        )

        // 记录多次成功连接
        await strategy.recordSuccess()
        await strategy.recordSuccess()
        await strategy.recordSuccess()

        let delay = await strategy.nextDelay(attempt: 1, lastError: nil)

        // 多次成功后延迟应该减少
        XCTAssertNotNil(delay)
        if let delay = delay {
            XCTAssertLessThan(delay, 5.0)
        }
    }

    func testAdaptiveStrategyReset() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 2.0,
            maxDelay: 60.0,
            maxAttempts: 3
        )

        // 记录一些成功
        await strategy.recordSuccess()
        await strategy.recordSuccess()

        // 重置
        await strategy.reset()

        // 重置后延迟应该回到初始值附近
        let delay = await strategy.nextDelay(attempt: 1, lastError: nil)
        XCTAssertNotNil(delay)
        if let delay = delay {
            XCTAssertEqual(delay, 2.0, accuracy: 1.0)
        }
    }

    func testAdaptiveStrategyMaxAttempts() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 2.0,
            maxDelay: 60.0,
            maxAttempts: 3
        )

        let delay1 = await strategy.nextDelay(attempt: 1, lastError: nil)
        let delay3 = await strategy.nextDelay(attempt: 3, lastError: nil)
        let delay4 = await strategy.nextDelay(attempt: 4, lastError: nil)

        XCTAssertNotNil(delay1)
        XCTAssertNotNil(delay3)
        XCTAssertNil(delay4)
    }

    func testAdaptiveStrategyShouldReconnect() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 2.0,
            maxDelay: 60.0,
            maxAttempts: 3
        )

        enum TestError: Error {
            case generic
        }

        // 默认实现应该总是返回true
        let shouldReconnect = await strategy.shouldReconnect(error: TestError.generic)
        XCTAssertTrue(shouldReconnect)
    }

    // MARK: - Custom Strategy Tests

    func testCustomStrategy() {
        let customStrategy = CustomStrategy(
            delayCalculator: { attempt, _ in
                // 自定义延迟：最多5次尝试，每次attempt * 2秒
                guard attempt <= 5 else { return nil }
                return TimeInterval(attempt * 2)
            },
            shouldReconnect: { _ in true }
        )

        let delay1 = customStrategy.nextDelay(attempt: 1, lastError: nil)
        let delay3 = customStrategy.nextDelay(attempt: 3, lastError: nil)
        let delay6 = customStrategy.nextDelay(attempt: 6, lastError: nil)

        XCTAssertEqual(delay1, 2.0)
        XCTAssertEqual(delay3, 6.0)
        XCTAssertNil(delay6)
    }

    func testCustomStrategyNoLimit() {
        let unlimitedStrategy = CustomStrategy(
            delayCalculator: { _, _ in 1.0 },
            shouldReconnect: { _ in true }
        )

        let delay100 = unlimitedStrategy.nextDelay(attempt: 100, lastError: nil)
        XCTAssertEqual(delay100, 1.0)
    }

    func testCustomStrategyWithErrorHandling() {
        enum NetworkError: Error {
            case timeout
            case unauthorized
        }

        let strategy = CustomStrategy(
            delayCalculator: { attempt, _ in
                guard attempt <= 5 else { return nil }
                return TimeInterval(attempt)
            },
            shouldReconnect: { error in
                // 对于unauthorized错误不重连
                if case NetworkError.unauthorized = error {
                    return false
                }
                return true
            }
        )

        XCTAssertTrue(strategy.shouldReconnect(error: NetworkError.timeout))
        XCTAssertFalse(strategy.shouldReconnect(error: NetworkError.unauthorized))
    }

    func testCustomStrategyReset() {
        var resetCalled = false
        var strategy = CustomStrategy(
            delayCalculator: { attempt, _ in
                guard attempt <= 5 else { return nil }
                return TimeInterval(attempt)
            },
            shouldReconnect: { _ in true }
        )

        strategy.reset()
        // Reset调用成功，不会崩溃
        XCTAssertNotNil(strategy.nextDelay(attempt: 1, lastError: nil))
    }

    // MARK: - Edge Cases Tests

    func testZeroMaxAttempts() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 0,
            multiplier: 2.0,
            jitter: false
        )

        let delay = strategy.nextDelay(attempt: 1, lastError: nil)
        XCTAssertNil(delay)
    }

    func testNegativeAttempt() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 5,
            multiplier: 2.0,
            jitter: false
        )

        // 负数尝试的行为取决于具体实现
        let delay = strategy.nextDelay(attempt: -1, lastError: nil)
        // 可能返回nil或某个值，取决于实现
        // 只验证不会崩溃
    }

    func testVeryLargeAttempt() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 60.0,
            maxAttempts: 1000,
            multiplier: 2.0,
            jitter: false
        )

        let delay = strategy.nextDelay(attempt: 1000, lastError: nil)

        // 应该被限制在maxDelay
        XCTAssertNotNil(delay)
        if let delay = delay {
            XCTAssertEqual(delay, 60.0)
        }
    }

    func testErrorPropagation() {
        enum TestError: Error {
            case network
            case timeout
        }

        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 5,
            multiplier: 2.0,
            jitter: false
        )

        // 传递不同的错误
        let delay1 = strategy.nextDelay(attempt: 1, lastError: TestError.network)
        let delay2 = strategy.nextDelay(attempt: 1, lastError: TestError.timeout)
        let delay3 = strategy.nextDelay(attempt: 1, lastError: nil)

        // 所有情况都应该返回有效延迟
        XCTAssertNotNil(delay1)
        XCTAssertNotNil(delay2)
        XCTAssertNotNil(delay3)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentAccess() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 100
        )

        // 并发调用
        await withTaskGroup(of: TimeInterval?.self) { group in
            for i in 1...10 {
                group.addTask {
                    await strategy.nextDelay(attempt: i, lastError: nil)
                }
            }

            var delays: [TimeInterval] = []
            for await delay in group {
                if let delay = delay {
                    delays.append(delay)
                }
            }

            // 应该返回10个有效的延迟值
            XCTAssertEqual(delays.count, 10)
            for delay in delays {
                XCTAssertGreaterThan(delay, 0.0)
            }
        }
    }

    func testConcurrentRecordSuccess() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 2.0,
            maxDelay: 60.0,
            maxAttempts: 10
        )

        // 并发记录成功
        await withTaskGroup(of: Void.self) { group in
            for _ in 1...20 {
                group.addTask {
                    await strategy.recordSuccess()
                }
            }
        }

        // 应该能正常获取延迟
        let delay = await strategy.nextDelay(attempt: 1, lastError: nil)
        XCTAssertNotNil(delay)
    }

    // MARK: - Performance Tests

    func testExponentialBackoffPerformance() {
        let strategy = ExponentialBackoffStrategy(
            initialDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 100,
            multiplier: 2.0,
            jitter: false
        )

        measure {
            for i in 1...1000 {
                _ = strategy.nextDelay(attempt: i, lastError: nil)
            }
        }
    }

    func testFixedIntervalPerformance() {
        let strategy = FixedIntervalStrategy(
            interval: 5.0,
            maxAttempts: 100
        )

        measure {
            for i in 1...1000 {
                _ = strategy.nextDelay(attempt: i, lastError: nil)
            }
        }
    }

    func testAdaptiveStrategyPerformance() async {
        let strategy = AdaptiveStrategy(
            initialDelay: 2.0,
            maxDelay: 60.0,
            maxAttempts: 100
        )

        await withCheckedContinuation { continuation in
            Task {
                for i in 1...1000 {
                    _ = await strategy.nextDelay(attempt: i, lastError: nil)
                }
                continuation.resume()
            }
        }
    }
}
