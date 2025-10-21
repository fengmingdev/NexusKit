//
//  MiddlewareIntegrationTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//
//  中间件集成测试 - 测试多个中间件协同工作

import XCTest
@testable import NexusKit

final class MiddlewareIntegrationTests: XCTestCase {

    // MARK: - 测试：日志 + 压缩

    func testLoggingWithCompression() async throws {
        let loggingMiddleware = LoggingMiddleware(
            logLevel: .info,
            logData: false
        )

        let compressionMiddleware = CompressionMiddleware(
            profile: .balanced,
            compressOutgoing: true,
            decompressIncoming: true
        )

        let pipeline = MiddlewarePipeline()
        await pipeline.add(loggingMiddleware)     // 优先级 50
        await pipeline.add(compressionMiddleware) // 优先级 20

        let context = createMockContext()
        let testData = generateTestData(size: 2048, pattern: "Integration Test ")

        // 出站: 日志 -> 压缩
        let outgoing = try await pipeline.processOutgoing(testData, context: context)
        XCTAssertLessThan(outgoing.count, testData.count, "应该被压缩")

        // 入站: 压缩 -> 日志
        let incoming = try await pipeline.processIncoming(outgoing, context: context)
        XCTAssertEqual(incoming, testData, "解压缩后应该恢复原数据")
    }

    // MARK: - 测试：拦截器 + 验证 + 压缩

    func testInterceptorWithValidationAndCompression() async throws {
        // 拦截器链：验证请求大小
        let interceptorChain = await InterceptorChain.withValidation(
            minSize: 10,
            maxSize: 10 * 1024
        )

        // 压缩中间件
        let compressionMiddleware = CompressionMiddleware.balanced()

        let pipeline = MiddlewarePipeline()
        await pipeline.add(interceptorChain)         // 优先级 5
        await pipeline.add(compressionMiddleware)    // 优先级 20

        let context = createMockContext()

        // 测试1：正常大小的数据应该通过拦截器并被压缩
        let normalData = generateTestData(size: 1024, pattern: "Normal ")
        let outgoing1 = try await pipeline.processOutgoing(normalData, context: context)
        XCTAssertLessThan(outgoing1.count, normalData.count, "应该被压缩")

        // 测试2：太小的数据应该被拦截器拒绝
        let tooSmallData = Data(repeating: 1, count: 5)
        do {
            _ = try await pipeline.processOutgoing(tooSmallData, context: context)
            XCTFail("应该被拦截器拒绝")
        } catch {
            // 应该是NexusError.middlewareError wrapping an InterceptorError
            XCTAssertTrue(error is NexusError)
        }

        // 测试3：太大的数据应该被拦截器拒绝
        let tooBigData = Data(repeating: 1, count: 20 * 1024)
        do {
            _ = try await pipeline.processOutgoing(tooBigData, context: context)
            XCTFail("应该被拦截器拒绝")
        } catch {
            // 应该是NexusError.middlewareError wrapping an InterceptorError
            XCTAssertTrue(error is NexusError)
        }
    }

    // MARK: - 测试：流量控制 + 日志

    func testRateLimitWithLogging() async throws {
        let rateLimitMiddleware = RateLimitMiddleware.bytesPerSecond(
            2000,  // 2KB/s
            burstSize: 3000,  // 3KB burst
            limitOutgoing: true
        )

        let loggingMiddleware = LoggingMiddleware(
            logLevel: .debug,
            logData: false
        )

        let pipeline = MiddlewarePipeline()
        await pipeline.add(loggingMiddleware)     // 优先级 50
        await pipeline.add(rateLimitMiddleware)   // 优先级 30

        let context = createMockContext()
        let testData = Data(repeating: 1, count: 1000)

        // 发送多次，应该受到流量控制
        let startTime = Date()
        for _ in 0..<8 {
            _ = try await pipeline.processOutgoing(testData, context: context)
        }
        let elapsed = Date().timeIntervalSince(startTime)

        // 发送8KB数据，速率2KB/s且突发3KB，应该花费一些时间
        // 前3KB走突发，后5KB受限
        XCTAssertGreaterThan(elapsed, 1.5, "应该被流量控制延迟")

        let stats = await rateLimitMiddleware.getStatistics()
        XCTAssertEqual(stats.totalOutgoingBytes, 8000)
    }

    // MARK: - 测试：完整管道（拦截器 + 流量控制 + 压缩 + 日志）

    func testFullMiddlewarePipeline() async throws {
        // 1. 拦截器（优先级 5）
        let interceptorChain = InterceptorChain()
        await interceptorChain.addRequestInterceptor(ValidationRequestInterceptor(maxSize: 100 * 1024))
        await interceptorChain.addRequestInterceptor(LoggingRequestInterceptor(logLevel: .debug))

        // 2. 日志中间件（优先级 10）
        let loggingMiddleware = LoggingMiddleware(
            logLevel: .info,
            logData: false
        )

        // 3. 压缩中间件（优先级 20）
        let compressionMiddleware = CompressionMiddleware.highSpeed()

        // 4. 流量控制（优先级 30）
        let rateLimitMiddleware = RateLimitMiddleware.bytesPerSecond(
            10000,  // 10KB/s
            limitOutgoing: true
        )

        // 构建管道
        let pipeline = MiddlewarePipeline()
        await pipeline.add(loggingMiddleware)
        await pipeline.add(interceptorChain)
        await pipeline.add(compressionMiddleware)
        await pipeline.add(rateLimitMiddleware)

        let context = createMockContext()
        let testData = generateTestData(size: 4096, pattern: "Full Pipeline Test ")

        // 执行完整管道
        let result = try await pipeline.processOutgoing(testData, context: context)

        // 验证结果
        XCTAssertGreaterThan(result.count, 0)

        // 检查统计
        let interceptorStats = await interceptorChain.getStatistics()
        XCTAssertEqual(interceptorStats.totalRequestsProcessed, 1)

        let rateLimitStats = await rateLimitMiddleware.getStatistics()
        XCTAssertGreaterThan(rateLimitStats.totalOutgoingBytes, 0)
    }

    // MARK: - 测试：管道中的错误处理

    func testMiddlewarePipelineErrorHandling() async throws {
        // 创建会拒绝数据的拦截器
        let strictValidator = ValidationRequestInterceptor(minSize: 1000, maxSize: 2000)

        let interceptorChain = InterceptorChain()
        await interceptorChain.addRequestInterceptor(strictValidator)

        let pipeline = MiddlewarePipeline()
        await pipeline.add(interceptorChain)

        let context = createMockContext()

        // 测试：小数据应该失败
        let smallData = Data(repeating: 1, count: 500)
        do {
            _ = try await pipeline.processOutgoing(smallData, context: context)
            XCTFail("应该抛出错误")
        } catch {
            // 预期错误
            XCTAssertTrue(error is NexusError)
            if case let NexusError.middlewareError(name, _) = error {
                XCTAssertEqual(name, "InterceptorChain")
            } else {
                XCTFail("错误类型不正确")
            }
        }
    }

    // MARK: - 测试：并发请求通过管道

    func testConcurrentRequestsThroughPipeline() async throws {
        let compressionMiddleware = CompressionMiddleware.highSpeed()
        let rateLimitMiddleware = RateLimitMiddleware.requestsPerSecond(
            50,  // 每秒50个请求
            limitOutgoing: true
        )

        let pipeline = MiddlewarePipeline()
        await pipeline.add(compressionMiddleware)
        await pipeline.add(rateLimitMiddleware)

        let context = createMockContext()

        // 并发发送10个请求
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let data = "Request \(i)".data(using: .utf8)!
                    _ = try await pipeline.processOutgoing(data, context: context)
                }
            }

            try await group.waitForAll()
        }

        let stats = await rateLimitMiddleware.getStatistics()
        XCTAssertEqual(stats.totalOutgoingBytes, 90) // "Request X" = 9 bytes each
    }

    // MARK: - 测试：双向处理（出站+入站）

    func testBidirectionalProcessing() async throws {
        let compressionMiddleware = CompressionMiddleware(
            profile: .balanced,
            compressOutgoing: true,
            decompressIncoming: true
        )

        let loggingMiddleware = LoggingMiddleware(
            logLevel: .info,
            logData: false
        )

        let pipeline = MiddlewarePipeline()
        await pipeline.add(loggingMiddleware)
        await pipeline.add(compressionMiddleware)

        let context = createMockContext()
        let originalData = generateTestData(size: 2048, pattern: "Bidirectional ")

        // 出站处理
        let compressed = try await pipeline.processOutgoing(originalData, context: context)
        XCTAssertLessThan(compressed.count, originalData.count, "应该被压缩")

        // 入站处理（模拟接收到压缩数据）
        let decompressed = try await pipeline.processIncoming(compressed, context: context)
        XCTAssertEqual(decompressed, originalData, "解压缩后应该恢复")
    }

    // MARK: - 测试：中间件优先级顺序

    func testMiddlewarePriorityOrdering() async throws {
        // 创建不同优先级的中间件
        let priority5 = InterceptorChain(priority: 5)
        let priority10 = LoggingMiddleware(logLevel: .info, priority: 10)
        let priority40 = CompressionMiddleware.disabled() // priority 40
        let priority30 = RateLimitMiddleware.bytesPerSecond(10000) // priority 30

        let pipeline = MiddlewarePipeline()

        // 乱序添加
        await pipeline.add(priority30)
        await pipeline.add(priority10)
        await pipeline.add(priority5)
        await pipeline.add(priority40)

        // 获取所有中间件
        let middlewares = await pipeline.all()

        // 验证顺序（应该按优先级排序）
        XCTAssertEqual(middlewares.count, 4)
        XCTAssertEqual(middlewares[0].priority, 5)
        XCTAssertEqual(middlewares[1].priority, 10)
        XCTAssertEqual(middlewares[2].priority, 30)
        XCTAssertEqual(middlewares[3].priority, 40)
    }

    // MARK: - 测试：动态添加/移除中间件

    func testDynamicMiddlewareManagement() async throws {
        let pipeline = MiddlewarePipeline()

        let logging = LoggingMiddleware(logLevel: .debug)
        let compression = CompressionMiddleware.balanced()

        // 初始添加
        await pipeline.add(logging)
        var all = await pipeline.all()
        XCTAssertEqual(all.count, 1)

        // 再添加一个
        await pipeline.add(compression)
        all = await pipeline.all()
        XCTAssertEqual(all.count, 2)

        // 移除一个
        await pipeline.remove(named: "LoggingMiddleware")
        all = await pipeline.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "CompressionMiddleware")

        // 清空所有
        await pipeline.removeAll()
        all = await pipeline.all()
        XCTAssertEqual(all.count, 0)
    }

    // MARK: - 测试：缓存中间件集成

    func testCacheMiddlewareIntegration() async throws {
        let cacheMiddleware = await CacheMiddleware(configuration: .production)

        let loggingMiddleware = LoggingMiddleware(
            logLevel: .info,
            logData: false
        )

        let pipeline = MiddlewarePipeline()
        await pipeline.add(loggingMiddleware)
        await pipeline.add(cacheMiddleware)

        let context = createMockContext()
        let testData = "Cached Data".data(using: .utf8)!

        // 第一次接收 - 应该缓存
        let incoming1 = try await pipeline.processIncoming(testData, context: context)
        XCTAssertEqual(incoming1, testData)

        let stats1 = await cacheMiddleware.getStatistics()
        XCTAssertEqual(stats1.misses, 1)
        XCTAssertEqual(stats1.hits, 0)

        // 第二次相同数据 - 应该命中缓存
        let incoming2 = try await pipeline.processIncoming(testData, context: context)
        XCTAssertEqual(incoming2, testData)

        let stats2 = await cacheMiddleware.getStatistics()
        XCTAssertEqual(stats2.hits, 1)
    }

    // MARK: - Helper Methods

    private func createMockContext() -> MiddlewareContext {
        MiddlewareContext(
            connectionId: "integration-test-\(UUID().uuidString)",
            endpoint: .tcp(host: "localhost", port: 8080)
        )
    }

    private func generateTestData(size: Int, pattern: String) -> Data {
        var data = Data(capacity: size)
        let patternData = pattern.data(using: .utf8)!

        while data.count < size {
            data.append(patternData)
        }

        if data.count > size {
            data = data.prefix(size)
        }

        return data
    }
}
