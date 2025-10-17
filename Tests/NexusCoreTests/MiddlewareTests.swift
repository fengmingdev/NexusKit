//
//  MiddlewareTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore

/// 中间件系统测试
final class MiddlewareTests: XCTestCase {

    // MARK: - Test Middleware Implementations

    /// 测试用中间件：为数据添加前缀
    final class PrefixMiddleware: Middleware, @unchecked Sendable {
        let id = UUID().uuidString
        let name = "PrefixMiddleware"
        let priority: Int
        let prefix: String

        init(prefix: String, priority: Int = 100) {
            self.prefix = prefix
            self.priority = priority
        }

        func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
            var result = prefix.data(using: .utf8)!
            result.append(data)
            return result
        }

        func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
            // 移除前缀
            let prefixData = prefix.data(using: .utf8)!
            guard data.starts(with: prefixData) else {
                return data
            }
            return data.dropFirst(prefixData.count)
        }
    }

    /// 测试用中间件：添加后缀
    final class SuffixMiddleware: Middleware, @unchecked Sendable {
        let id = UUID().uuidString
        let name = "SuffixMiddleware"
        let priority: Int
        let suffix: String

        init(suffix: String, priority: Int = 100) {
            self.suffix = suffix
            self.priority = priority
        }

        func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
            var result = data
            result.append(suffix.data(using: .utf8)!)
            return result
        }

        func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
            // 移除后缀
            let suffixData = suffix.data(using: .utf8)!
            guard data.hasSuffix(suffixData) else {
                return data
            }
            return data.dropLast(suffixData.count)
        }
    }

    /// 测试用中间件：统计数据
    actor CounterMiddleware: Middleware {
        let id = UUID().uuidString
        let name = "CounterMiddleware"
        let priority: Int = 100

        private(set) var outgoingCount = 0
        private(set) var incomingCount = 0

        func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
            outgoingCount += 1
            return data
        }

        func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
            incomingCount += 1
            return data
        }
    }

    /// 测试用中间件：抛出错误
    final class ErrorMiddleware: Middleware, @unchecked Sendable {
        let id = UUID().uuidString
        let name = "ErrorMiddleware"
        let priority: Int = 100
        let shouldThrow: Bool

        init(shouldThrow: Bool = true) {
            self.shouldThrow = shouldThrow
        }

        func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
            if shouldThrow {
                throw NexusError.middlewareError(name: "ErrorMiddleware", error: NSError(domain: "test", code: 1))
            }
            return data
        }

        func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
            if shouldThrow {
                throw NexusError.middlewareError(name: "ErrorMiddleware", error: NSError(domain: "test", code: 1))
            }
            return data
        }
    }

    // MARK: - Middleware Pipeline Tests

    func testMiddlewarePipelineBasic() async throws {
        let pipeline = MiddlewarePipeline()

        // 添加中间件
        let prefix = PrefixMiddleware(prefix: "PREFIX:")
        let suffix = SuffixMiddleware(suffix: ":SUFFIX")

        await pipeline.add(prefix)
        await pipeline.add(suffix)

        // 测试发送流程
        let originalData = "Hello".data(using: .utf8)!
        let context = MiddlewareContext(connectionId: "test-1", endpoint: .tcp(host: "localhost", port: 8080))

        let processedData = try await pipeline.processOutgoing(originalData, context: context)
        let resultString = String(data: processedData, encoding: .utf8)

        XCTAssertEqual(resultString, "PREFIX:Hello:SUFFIX")
    }

    func testMiddlewarePipelinePriority() async throws {
        let pipeline = MiddlewarePipeline()

        // 添加不同优先级的中间件
        let lowPriority = PrefixMiddleware(prefix: "LOW:", priority: 200)
        let highPriority = PrefixMiddleware(prefix: "HIGH:", priority: 50)
        let mediumPriority = PrefixMiddleware(prefix: "MED:", priority: 100)

        // 乱序添加
        await pipeline.add(mediumPriority)
        await pipeline.add(lowPriority)
        await pipeline.add(highPriority)

        // 测试发送流程（应该按优先级排序：HIGH -> MED -> LOW）
        let originalData = "DATA".data(using: .utf8)!
        let context = MiddlewareContext(connectionId: "test-2", endpoint: .tcp(host: "localhost", port: 8080))

        let processedData = try await pipeline.processOutgoing(originalData, context: context)
        let resultString = String(data: processedData, encoding: .utf8)

        XCTAssertEqual(resultString, "HIGH:MED:LOW:DATA")
    }

    func testMiddlewarePipelineIncoming() async throws {
        let pipeline = MiddlewarePipeline()

        let prefix = PrefixMiddleware(prefix: "PREFIX:", priority: 50)
        let suffix = SuffixMiddleware(suffix: ":SUFFIX", priority: 100)

        await pipeline.add(prefix)
        await pipeline.add(suffix)

        // 测试接收流程（应该反向处理）
        let incomingData = "PREFIX:Hello:SUFFIX".data(using: .utf8)!
        let context = MiddlewareContext(connectionId: "test-3", endpoint: .tcp(host: "localhost", port: 8080))

        let processedData = try await pipeline.processIncoming(incomingData, context: context)
        let resultString = String(data: processedData, encoding: .utf8)

        XCTAssertEqual(resultString, "Hello")
    }

    func testMiddlewareRemoval() async throws {
        let pipeline = MiddlewarePipeline()

        let prefix = PrefixMiddleware(prefix: "PREFIX:")
        let suffix = SuffixMiddleware(suffix: ":SUFFIX")

        await pipeline.add(prefix)
        await pipeline.add(suffix)

        // 移除前缀中间件
        await pipeline.remove(named: prefix.id)

        // 测试
        let originalData = "Hello".data(using: .utf8)!
        let context = MiddlewareContext(connectionId: "test-4", endpoint: .tcp(host: "localhost", port: 8080))

        let processedData = try await pipeline.processOutgoing(originalData, context: context)
        let resultString = String(data: processedData, encoding: .utf8)

        XCTAssertEqual(resultString, "Hello:SUFFIX")
    }

    func testMiddlewareClear() async throws {
        let pipeline = MiddlewarePipeline()

        await pipeline.add(PrefixMiddleware(prefix: "A:"))
        await pipeline.add(SuffixMiddleware(suffix: ":B"))

        // 清除所有中间件
        await pipeline.clear()

        // 测试
        let originalData = "Hello".data(using: .utf8)!
        let context = MiddlewareContext(connectionId: "test-5", endpoint: .tcp(host: "localhost", port: 8080))

        let processedData = try await pipeline.processOutgoing(originalData, context: context)

        XCTAssertEqual(processedData, originalData)
    }

    func testMiddlewareCounter() async throws {
        let pipeline = MiddlewarePipeline()
        let counter = CounterMiddleware()

        await pipeline.add(counter)

        let context = MiddlewareContext(connectionId: "test-6", endpoint: .tcp(host: "localhost", port: 8080))
        let testData = "Test".data(using: .utf8)!

        // 测试发送
        _ = try await pipeline.processOutgoing(testData, context: context)
        _ = try await pipeline.processOutgoing(testData, context: context)

        let outgoingCount = await counter.outgoingCount
        XCTAssertEqual(outgoingCount, 2)

        // 测试接收
        _ = try await pipeline.processIncoming(testData, context: context)

        let incomingCount = await counter.incomingCount
        XCTAssertEqual(incomingCount, 1)
    }

    func testMiddlewareErrorHandling() async throws {
        let pipeline = MiddlewarePipeline()
        let errorMiddleware = ErrorMiddleware(shouldThrow: true)

        await pipeline.add(errorMiddleware)

        let context = MiddlewareContext(connectionId: "test-7", endpoint: .tcp(host: "localhost", port: 8080))
        let testData = "Test".data(using: .utf8)!

        // 测试错误传播
        do {
            _ = try await pipeline.processOutgoing(testData, context: context)
            XCTFail("应该抛出错误")
        } catch let error as NexusError {
            switch error {
            case .middlewareError(let name, _):
                XCTAssertEqual(name, "ErrorMiddleware")
            default:
                XCTFail("错误类型不正确")
            }
        }
    }

    // MARK: - Conditional Middleware Tests

    func testConditionalMiddleware() async throws {
        let pipeline = MiddlewarePipeline()

        let baseMiddleware = PrefixMiddleware(prefix: "PREFIX:")
        let condition: (MiddlewareContext) async -> Bool = { context in
            context.connectionId == "allowed"
        }

        let conditionalMiddleware = ConditionalMiddleware(
            middleware: baseMiddleware,
            condition: condition
        )

        await pipeline.add(conditionalMiddleware)

        let testData = "Hello".data(using: .utf8)!

        // 测试条件满足
        let allowedContext = MiddlewareContext(connectionId: "allowed", endpoint: .tcp(host: "localhost", port: 8080))
        let allowedResult = try await pipeline.processOutgoing(testData, context: allowedContext)
        let allowedString = String(data: allowedResult, encoding: .utf8)
        XCTAssertEqual(allowedString, "PREFIX:Hello")

        // 测试条件不满足
        let deniedContext = MiddlewareContext(connectionId: "denied", endpoint: .tcp(host: "localhost", port: 8080))
        let deniedResult = try await pipeline.processOutgoing(testData, context: deniedContext)
        let deniedString = String(data: deniedResult, encoding: .utf8)
        XCTAssertEqual(deniedString, "Hello")
    }

    // MARK: - Composed Middleware Tests

    func testComposedMiddleware() async throws {
        let pipeline = MiddlewarePipeline()

        let prefix = PrefixMiddleware(prefix: "A:", priority: 50)
        let suffix = SuffixMiddleware(suffix: ":B", priority: 100)

        let composed = ComposedMiddleware(middlewares: [prefix, suffix])

        await pipeline.add(composed)

        let testData = "Hello".data(using: .utf8)!
        let context = MiddlewareContext(connectionId: "test-8", endpoint: .tcp(host: "localhost", port: 8080))

        // 测试组合中间件
        let result = try await pipeline.processOutgoing(testData, context: context)
        let resultString = String(data: result, encoding: .utf8)

        // 组合中间件内部也按优先级执行
        XCTAssertEqual(resultString, "A:Hello:B")
    }

    // MARK: - Context Tests

    func testMiddlewareContext() {
        let context = MiddlewareContext(
            connectionId: "conn-1",
            endpoint: .tcp(host: "localhost", port: 8080),
            metadata: ["key1": "value1", "key2": "value2"]
        )

        XCTAssertEqual(context.connectionId, "conn-1")
        XCTAssertEqual(context.metadata["key1"], "value1")
        XCTAssertEqual(context.metadata["key2"], "value2")
    }

    func testMiddlewareContextEquality() {
        let context1 = MiddlewareContext(connectionId: "conn-1", endpoint: .tcp(host: "localhost", port: 8080))
        let context2 = MiddlewareContext(connectionId: "conn-1", endpoint: .tcp(host: "localhost", port: 8080))
        let context3 = MiddlewareContext(connectionId: "conn-2", endpoint: .tcp(host: "localhost", port: 8080))

        XCTAssertEqual(context1.connectionId, context2.connectionId)
        XCTAssertNotEqual(context1.connectionId, context3.connectionId)
    }

    // MARK: - Performance Tests

    func testMiddlewarePipelinePerformance() async throws {
        let pipeline = MiddlewarePipeline()

        // 添加多个中间件
        for i in 0..<10 {
            await pipeline.add(PrefixMiddleware(prefix: "\(i):", priority: i * 10))
        }

        let testData = "PerformanceTest".data(using: .utf8)!
        let context = MiddlewareContext(connectionId: "perf-test", endpoint: .tcp(host: "localhost", port: 8080))

        measure {
            let expectation = self.expectation(description: "Performance test")

            Task {
                for _ in 0..<100 {
                    _ = try await pipeline.processOutgoing(testData, context: context)
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }
}

// MARK: - Data Extension for Testing

extension Data {
    func hasSuffix(_ suffix: Data) -> Bool {
        guard self.count >= suffix.count else { return false }
        return self.suffix(suffix.count) == suffix
    }
}
