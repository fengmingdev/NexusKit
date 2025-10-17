//
//  ReconnectionStrategyTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore

/// 重连策略测试
final class ReconnectionStrategyTests: XCTestCase {

    // MARK: - Exponential Backoff Strategy Tests

    func testExponentialBackoffInitialDelay() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 5,
            initialInterval: 1.0,
            maxInterval: 30.0,
            multiplier: 2.0
        )

        let delay = await strategy.nextDelay(for: 1)

        // 第一次重连应该是初始延迟
        XCTAssertEqual(delay, 1.0, accuracy: 0.5) // 允许一定误差（因为有jitter）
    }

    func testExponentialBackoffMultiplier() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 5,
            initialInterval: 1.0,
            maxInterval: 100.0,
            multiplier: 2.0,
            jitter: 0.0 // 禁用jitter以便精确测试
        )

        let delay1 = await strategy.nextDelay(for: 1)
        let delay2 = await strategy.nextDelay(for: 2)
        let delay3 = await strategy.nextDelay(for: 3)

        XCTAssertEqual(delay1, 1.0)
        XCTAssertEqual(delay2, 2.0)
        XCTAssertEqual(delay3, 4.0)
    }

    func testExponentialBackoffMaxInterval() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 10,
            initialInterval: 1.0,
            maxInterval: 10.0,
            multiplier: 2.0,
            jitter: 0.0
        )

        // 第10次重连的延迟应该被限制在maxInterval
        let delay = await strategy.nextDelay(for: 10)

        XCTAssertLessThanOrEqual(delay, 10.0)
    }

    func testExponentialBackoffMaxAttempts() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 3,
            initialInterval: 1.0,
            maxInterval: 30.0
        )

        let shouldRetry1 = await strategy.shouldRetry(attempt: 1)
        let shouldRetry2 = await strategy.shouldRetry(attempt: 2)
        let shouldRetry3 = await strategy.shouldRetry(attempt: 3)
        let shouldRetry4 = await strategy.shouldRetry(attempt: 4)

        XCTAssertTrue(shouldRetry1)
        XCTAssertTrue(shouldRetry2)
        XCTAssertTrue(shouldRetry3)
        XCTAssertFalse(shouldRetry4)
    }

    func testExponentialBackoffJitter() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 5,
            initialInterval: 10.0,
            maxInterval: 100.0,
            multiplier: 2.0,
            jitter: 0.2 // 20% jitter
        )

        // 测试多次获取延迟，应该有不同的值（由于jitter）
        var delays: [TimeInterval] = []
        for _ in 0..<10 {
            let delay = await strategy.nextDelay(for: 1)
            delays.append(delay)
        }

        // 检查延迟在合理范围内（8.0 - 12.0）
        for delay in delays {
            XCTAssertGreaterThanOrEqual(delay, 8.0)
            XCTAssertLessThanOrEqual(delay, 12.0)
        }
    }

    func testExponentialBackoffReset() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 3,
            initialInterval: 1.0,
            maxInterval: 30.0
        )

        // 达到最大尝试次数
        _ = await strategy.shouldRetry(attempt: 4)

        // 重置
        await strategy.reset()

        // 重置后应该可以重试
        let shouldRetry = await strategy.shouldRetry(attempt: 1)
        XCTAssertTrue(shouldRetry)
    }

    // MARK: - Fixed Interval Strategy Tests

    func testFixedIntervalConstantDelay() async {
        let strategy = FixedIntervalStrategy(
            maxAttempts: 5,
            interval: 5.0
        )

        let delay1 = await strategy.nextDelay(for: 1)
        let delay2 = await strategy.nextDelay(for: 2)
        let delay3 = await strategy.nextDelay(for: 5)

        XCTAssertEqual(delay1, 5.0)
        XCTAssertEqual(delay2, 5.0)
        XCTAssertEqual(delay3, 5.0)
    }

    func testFixedIntervalMaxAttempts() async {
        let strategy = FixedIntervalStrategy(
            maxAttempts: 3,
            interval: 2.0
        )

        let shouldRetry1 = await strategy.shouldRetry(attempt: 1)
        let shouldRetry3 = await strategy.shouldRetry(attempt: 3)
        let shouldRetry4 = await strategy.shouldRetry(attempt: 4)

        XCTAssertTrue(shouldRetry1)
        XCTAssertTrue(shouldRetry3)
        XCTAssertFalse(shouldRetry4)
    }

    func testFixedIntervalReset() async {
        let strategy = FixedIntervalStrategy(
            maxAttempts: 2,
            interval: 1.0
        )

        // 达到最大尝试次数
        _ = await strategy.shouldRetry(attempt: 3)

        // 重置
        await strategy.reset()

        // 重置后应该可以重试
        let shouldRetry = await strategy.shouldRetry(attempt: 1)
        XCTAssertTrue(shouldRetry)
    }

    // MARK: - Adaptive Strategy Tests

    func testAdaptiveStrategyGoodNetwork() async {
        let strategy = AdaptiveStrategy(
            maxAttempts: 5,
            baseInterval: 2.0
        )

        // 模拟良好的网络状态（快速连接）
        await strategy.recordConnectionAttempt(successful: true, duration: 0.1)
        await strategy.recordConnectionAttempt(successful: true, duration: 0.2)

        let delay = await strategy.nextDelay(for: 1)

        // 良好网络应该有较短的延迟
        XCTAssertLessThan(delay, 2.0)
    }

    func testAdaptiveStrategyPoorNetwork() async {
        let strategy = AdaptiveStrategy(
            maxAttempts: 5,
            baseInterval: 2.0
        )

        // 模拟不良的网络状态（连接失败或超时）
        await strategy.recordConnectionAttempt(successful: false, duration: 5.0)
        await strategy.recordConnectionAttempt(successful: false, duration: 5.0)

        let delay = await strategy.nextDelay(for: 1)

        // 不良网络应该有较长的延迟
        XCTAssertGreaterThan(delay, 2.0)
    }

    func testAdaptiveStrategyMixedNetwork() async {
        let strategy = AdaptiveStrategy(
            maxAttempts: 5,
            baseInterval: 2.0
        )

        // 混合网络状态
        await strategy.recordConnectionAttempt(successful: true, duration: 0.5)
        await strategy.recordConnectionAttempt(successful: false, duration: 3.0)
        await strategy.recordConnectionAttempt(successful: true, duration: 1.0)

        let delay = await strategy.nextDelay(for: 1)

        // 延迟应该在合理范围内
        XCTAssertGreaterThan(delay, 0.0)
        XCTAssertLessThan(delay, 10.0)
    }

    func testAdaptiveStrategyReset() async {
        let strategy = AdaptiveStrategy(
            maxAttempts: 3,
            baseInterval: 2.0
        )

        // 记录一些历史
        await strategy.recordConnectionAttempt(successful: false, duration: 5.0)
        await strategy.recordConnectionAttempt(successful: false, duration: 5.0)

        // 重置
        await strategy.reset()

        // 重置后延迟应该回到基础值附近
        let delay = await strategy.nextDelay(for: 1)
        XCTAssertEqual(delay, 2.0, accuracy: 1.0)
    }

    func testAdaptiveStrategyMaxAttempts() async {
        let strategy = AdaptiveStrategy(
            maxAttempts: 3,
            baseInterval: 2.0
        )

        let shouldRetry1 = await strategy.shouldRetry(attempt: 1)
        let shouldRetry3 = await strategy.shouldRetry(attempt: 3)
        let shouldRetry4 = await strategy.shouldRetry(attempt: 4)

        XCTAssertTrue(shouldRetry1)
        XCTAssertTrue(shouldRetry3)
        XCTAssertFalse(shouldRetry4)
    }

    // MARK: - Custom Strategy Tests

    func testCustomStrategy() async {
        let customStrategy = CustomStrategy { attempt in
            // 自定义逻辑：最多重试5次
            return attempt <= 5
        } nextDelay: { attempt in
            // 自定义延迟：attempt * 2 秒
            return TimeInterval(attempt * 2)
        } reset: {
            // 重置逻辑（可选）
        }

        let shouldRetry3 = await customStrategy.shouldRetry(attempt: 3)
        let shouldRetry6 = await customStrategy.shouldRetry(attempt: 6)

        XCTAssertTrue(shouldRetry3)
        XCTAssertFalse(shouldRetry6)

        let delay1 = await customStrategy.nextDelay(for: 1)
        let delay3 = await customStrategy.nextDelay(for: 3)

        XCTAssertEqual(delay1, 2.0)
        XCTAssertEqual(delay3, 6.0)
    }

    func testCustomStrategyNoLimit() async {
        let unlimitedStrategy = CustomStrategy { _ in
            // 永远重试
            return true
        } nextDelay: { attempt in
            // 固定延迟
            return 1.0
        }

        let shouldRetry100 = await unlimitedStrategy.shouldRetry(attempt: 100)
        XCTAssertTrue(shouldRetry100)
    }

    // MARK: - Edge Cases Tests

    func testZeroMaxAttempts() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 0,
            initialInterval: 1.0,
            maxInterval: 30.0
        )

        let shouldRetry = await strategy.shouldRetry(attempt: 1)
        XCTAssertFalse(shouldRetry)
    }

    func testNegativeAttempt() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 5,
            initialInterval: 1.0,
            maxInterval: 30.0
        )

        // 负数尝试应该被当作1处理
        let delay = await strategy.nextDelay(for: -1)
        XCTAssertGreaterThan(delay, 0.0)
    }

    func testVeryLargeAttempt() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 1000,
            initialInterval: 1.0,
            maxInterval: 60.0,
            jitter: 0.0
        )

        let delay = await strategy.nextDelay(for: 1000)

        // 应该被限制在maxInterval
        XCTAssertEqual(delay, 60.0)
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentAccess() async {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 100,
            initialInterval: 1.0,
            maxInterval: 30.0
        )

        // 并发调用
        await withTaskGroup(of: TimeInterval.self) { group in
            for i in 1...10 {
                group.addTask {
                    await strategy.nextDelay(for: i)
                }
            }

            var delays: [TimeInterval] = []
            for await delay in group {
                delays.append(delay)
            }

            // 应该返回10个有效的延迟值
            XCTAssertEqual(delays.count, 10)
            for delay in delays {
                XCTAssertGreaterThan(delay, 0.0)
            }
        }
    }

    // MARK: - Performance Tests

    func testExponentialBackoffPerformance() {
        let strategy = ExponentialBackoffStrategy(
            maxAttempts: 100,
            initialInterval: 1.0,
            maxInterval: 30.0
        )

        measure {
            let expectation = self.expectation(description: "Performance test")

            Task {
                for i in 1...1000 {
                    _ = await strategy.nextDelay(for: i)
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }
}
