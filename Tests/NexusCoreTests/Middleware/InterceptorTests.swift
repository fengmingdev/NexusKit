//
//  InterceptorTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusKit

final class InterceptorTests: XCTestCase {

    // MARK: - Request Interceptor Tests

    func testLoggingRequestInterceptor() async throws {
        let interceptor = LoggingRequestInterceptor(logLevel: .info, includeData: true)
        let request = InterceptorRequest(data: "Test Request".data(using: .utf8)!)
        let context = createMockContext()

        let result = try await interceptor.intercept(request: request, context: context)

        // 应该通过不修改
        XCTAssertEqual(result.data, request.data)
        XCTAssertFalse(result.isRejected)
        XCTAssertFalse(result.isModified)
    }

    func testValidationRequestInterceptor() async throws {
        let interceptor = ValidationRequestInterceptor(minSize: 10, maxSize: 100)

        // 测试正常数据
        let validRequest = InterceptorRequest(data: Data(repeating: 1, count: 50))
        let context = createMockContext()

        let validResult = try await interceptor.intercept(request: validRequest, context: context)
        XCTAssertFalse(validResult.isRejected)

        // 测试太小的数据
        let tooSmallRequest = InterceptorRequest(data: Data(repeating: 1, count: 5))
        let tooSmallResult = try await interceptor.intercept(request: tooSmallRequest, context: context)
        XCTAssertTrue(tooSmallResult.isRejected)

        // 测试太大的数据
        let tooBigRequest = InterceptorRequest(data: Data(repeating: 1, count: 150))
        let tooBigResult = try await interceptor.intercept(request: tooBigRequest, context: context)
        XCTAssertTrue(tooBigResult.isRejected)
    }

    func testValidationWithCustomValidator() async throws {
        // 自定义验证器：只允许包含 "VALID" 前缀的数据
        let interceptor = ValidationRequestInterceptor(
            validator: { data in
                guard let string = String(data: data, encoding: .utf8) else { return false }
                return string.hasPrefix("VALID")
            }
        )

        let context = createMockContext()

        // 有效数据
        let validRequest = InterceptorRequest(data: "VALID:123".data(using: .utf8)!)
        let validResult = try await interceptor.intercept(request: validRequest, context: context)
        XCTAssertFalse(validResult.isRejected)

        // 无效数据
        let invalidRequest = InterceptorRequest(data: "INVALID:123".data(using: .utf8)!)
        let invalidResult = try await interceptor.intercept(request: invalidRequest, context: context)
        XCTAssertTrue(invalidResult.isRejected)
    }

    func testTransformRequestInterceptor() async throws {
        // 转换器：将数据转为大写并添加前缀
        let interceptor = TransformRequestInterceptor { data, metadata in
            guard let string = String(data: data, encoding: .utf8) else {
                return (data, metadata)
            }
            let transformed = "PREFIX:\(string.uppercased())".data(using: .utf8)!
            var newMetadata = metadata
            newMetadata["transformed"] = "true"
            return (transformed, newMetadata)
        }

        let request = InterceptorRequest(data: "hello".data(using: .utf8)!)
        let context = createMockContext()

        let result = try await interceptor.intercept(request: request, context: context)

        XCTAssertTrue(result.isModified)
        let transformedString = String(data: result.data!, encoding: .utf8)
        XCTAssertEqual(transformedString, "PREFIX:HELLO")
    }

    func testThrottleRequestInterceptor() async throws {
        let delay: TimeInterval = 0.1
        let interceptor = ThrottleRequestInterceptor(delay: delay)

        let request = InterceptorRequest(data: Data(repeating: 1, count: 10))
        let context = createMockContext()

        let startTime = Date()
        let result = try await interceptor.intercept(request: request, context: context)

        // 应该返回延迟结果
        if case .delayed(let duration, let data) = result {
            XCTAssertEqual(duration, delay, accuracy: 0.01)
            XCTAssertEqual(data, request.data)
        } else {
            XCTFail("应该返回延迟结果")
        }
    }

    func testConditionalRequestInterceptor() async throws {
        let loggingInterceptor = LoggingRequestInterceptor()
        let validationInterceptor = ValidationRequestInterceptor(maxSize: 100)

        // 条件：数据大小 > 50 时使用验证，否则使用日志
        let interceptor = ConditionalRequestInterceptor(
            condition: { request, _ in
                request.data.count > 50
            },
            onMatch: validationInterceptor,
            onNoMatch: loggingInterceptor
        )

        let context = createMockContext()

        // 小数据应该使用日志拦截器（通过）
        let smallRequest = InterceptorRequest(data: Data(repeating: 1, count: 30))
        let smallResult = try await interceptor.intercept(request: smallRequest, context: context)
        XCTAssertFalse(smallResult.isRejected)

        // 大数据应该使用验证拦截器（拒绝，因为超过100）
        let largeRequest = InterceptorRequest(data: Data(repeating: 1, count: 120))
        let largeResult = try await interceptor.intercept(request: largeRequest, context: context)
        XCTAssertTrue(largeResult.isRejected)
    }

    func testSignatureRequestInterceptor() async throws {
        // 简单签名：添加固定后缀
        let interceptor = SignatureRequestInterceptor { data in
            var signed = data
            signed.append("SIGNATURE".data(using: .utf8)!)
            return signed
        }

        let request = InterceptorRequest(data: "Data".data(using: .utf8)!)
        let context = createMockContext()

        let result = try await interceptor.intercept(request: request, context: context)

        XCTAssertTrue(result.isModified)
        let signedString = String(data: result.data!, encoding: .utf8)
        XCTAssertEqual(signedString, "DataSIGNATURE")
    }

    // MARK: - Response Interceptor Tests

    func testLoggingResponseInterceptor() async throws {
        let interceptor = LoggingResponseInterceptor(logLevel: .info, includeData: true)
        let response = InterceptorResponse(
            data: "Test Response".data(using: .utf8)!,
            requestId: "req-123"
        )
        let context = createMockContext()

        let result = try await interceptor.intercept(response: response, context: context)

        XCTAssertEqual(result.data, response.data)
        XCTAssertFalse(result.isRejected)
    }

    func testValidationResponseInterceptor() async throws {
        let interceptor = ValidationResponseInterceptor(minSize: 5, maxSize: 50)
        let context = createMockContext()

        // 有效响应
        let validResponse = InterceptorResponse(data: Data(repeating: 1, count: 20))
        let validResult = try await interceptor.intercept(response: validResponse, context: context)
        XCTAssertFalse(validResult.isRejected)

        // 太小的响应
        let tooSmallResponse = InterceptorResponse(data: Data(repeating: 1, count: 2))
        let tooSmallResult = try await interceptor.intercept(response: tooSmallResponse, context: context)
        XCTAssertTrue(tooSmallResult.isRejected)
    }

    func testTransformResponseInterceptor() async throws {
        // 转换器：将响应数据转为小写
        let interceptor = TransformResponseInterceptor { data, metadata in
            guard let string = String(data: data, encoding: .utf8) else {
                return (data, metadata)
            }
            let transformed = string.lowercased().data(using: .utf8)!
            var newMetadata = metadata
            newMetadata["case"] = "lower"
            return (transformed, newMetadata)
        }

        let response = InterceptorResponse(data: "HELLO WORLD".data(using: .utf8)!)
        let context = createMockContext()

        let result = try await interceptor.intercept(response: response, context: context)

        XCTAssertTrue(result.isModified)
        let transformedString = String(data: result.data!, encoding: .utf8)
        XCTAssertEqual(transformedString, "hello world")
    }

    func testCacheResponseInterceptor() async throws {
        let interceptor = CacheResponseInterceptor(maxCacheSize: 5, cacheTTL: 1.0)

        let requestId = "test-request-123"
        let responseData = "Cached Response".data(using: .utf8)!
        let response = InterceptorResponse(data: responseData, requestId: requestId)
        let context = createMockContext()

        // 拦截响应（应该缓存）
        _ = try await interceptor.intercept(response: response, context: context)

        // 从缓存获取
        let cachedData = await interceptor.getCachedResponse(for: requestId)
        XCTAssertNotNil(cachedData)
        XCTAssertEqual(cachedData, responseData)

        // 等待过期
        try await Task.sleep(nanoseconds: 1_100_000_000)  // 1.1s

        // 应该过期了
        let expiredData = await interceptor.getCachedResponse(for: requestId)
        XCTAssertNil(expiredData)
    }

    func testCacheResponseInterceptorMaxSize() async throws {
        let maxSize = 3
        let interceptor = CacheResponseInterceptor(maxCacheSize: maxSize, cacheTTL: 10.0)
        let context = createMockContext()

        // 添加超过最大数量的缓存
        for i in 0..<5 {
            let response = InterceptorResponse(
                data: "Response \(i)".data(using: .utf8)!,
                requestId: "req-\(i)"
            )
            _ = try await interceptor.intercept(response: response, context: context)

            // 给一点时间确保时间戳不同
            try await Task.sleep(nanoseconds: 10_000_000)  // 0.01s
        }

        // 最老的应该被移除（req-0, req-1）
        let oldest = await interceptor.getCachedResponse(for: "req-0")
        XCTAssertNil(oldest, "最老的缓存应该被移除")

        // 最新的应该还在（req-2, req-3, req-4）
        let newest = await interceptor.getCachedResponse(for: "req-4")
        XCTAssertNotNil(newest, "最新的缓存应该还在")
    }

    func testVerifyResponseInterceptor() async throws {
        // 验证器：检查响应是否以 "OK:" 开头
        let interceptor = VerifyResponseInterceptor { data in
            guard let string = String(data: data, encoding: .utf8) else { return false }
            return string.hasPrefix("OK:")
        }

        let context = createMockContext()

        // 有效响应
        let validResponse = InterceptorResponse(data: "OK:SUCCESS".data(using: .utf8)!)
        let validResult = try await interceptor.intercept(response: validResponse, context: context)
        XCTAssertFalse(validResult.isRejected)

        // 无效响应
        let invalidResponse = InterceptorResponse(data: "ERROR:FAILURE".data(using: .utf8)!)
        let invalidResult = try await interceptor.intercept(response: invalidResponse, context: context)
        XCTAssertTrue(invalidResult.isRejected)
    }

    func testParserResponseInterceptor() async throws {
        // 解析器：提取 JSON 中的 "data" 字段
        let interceptor = ParserResponseInterceptor { data in
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataValue = json["data"] as? String else {
                throw ParserResponseInterceptor.ParseError.parseFailure("无效JSON格式")
            }
            return dataValue.data(using: .utf8)!
        }

        let context = createMockContext()

        // 有效JSON
        let validJSON = "{\"data\":\"Hello World\"}".data(using: .utf8)!
        let validResponse = InterceptorResponse(data: validJSON)
        let validResult = try await interceptor.intercept(response: validResponse, context: context)

        XCTAssertTrue(validResult.isModified)
        let parsedString = String(data: validResult.data!, encoding: .utf8)
        XCTAssertEqual(parsedString, "Hello World")

        // 无效JSON
        let invalidJSON = "{\"error\":\"No data\"}".data(using: .utf8)!
        let invalidResponse = InterceptorResponse(data: invalidJSON)
        let invalidResult = try await interceptor.intercept(response: invalidResponse, context: context)
        XCTAssertTrue(invalidResult.isRejected)
    }

    // MARK: - Interceptor Chain Tests

    func testInterceptorChainBasic() async throws {
        let chain = InterceptorChain()
        await chain.addRequestInterceptor(LoggingRequestInterceptor())
        await chain.addResponseInterceptor(LoggingResponseInterceptor())

        let context = createMockContext()
        let testData = "Test Data".data(using: .utf8)!

        // 测试出站
        let outgoing = try await chain.handleOutgoing(testData, context: context)
        XCTAssertEqual(outgoing, testData)

        // 测试入站
        let incoming = try await chain.handleIncoming(testData, context: context)
        XCTAssertEqual(incoming, testData)

        // 检查统计
        let stats = await chain.getStatistics()
        XCTAssertEqual(stats.totalRequestsProcessed, 1)
        XCTAssertEqual(stats.totalResponsesProcessed, 1)
    }

    func testInterceptorChainValidation() async throws {
        let chain = InterceptorChain()
        await chain.addRequestInterceptor(ValidationRequestInterceptor(maxSize: 50))
        await chain.addResponseInterceptor(ValidationResponseInterceptor(maxSize: 50))

        let context = createMockContext()

        // 有效数据应该通过
        let validData = Data(repeating: 1, count: 30)
        let outgoing = try await chain.handleOutgoing(validData, context: context)
        XCTAssertEqual(outgoing, validData)

        // 无效数据应该被拒绝
        let invalidData = Data(repeating: 1, count: 100)
        do {
            _ = try await chain.handleOutgoing(invalidData, context: context)
            XCTFail("应该抛出错误")
        } catch let error as InterceptorError {
            if case .requestRejected = error {
                // 预期错误
                XCTAssertTrue(true)
            } else {
                XCTFail("错误类型不正确")
            }
        }

        let stats = await chain.getStatistics()
        XCTAssertEqual(stats.requestsRejected, 1)
    }

    func testInterceptorChainTransformation() async throws {
        let chain = InterceptorChain()
        await chain.addRequestInterceptor(TransformRequestInterceptor { data, metadata in
            // 添加前缀
            var transformed = "REQ:".data(using: .utf8)!
            transformed.append(data)
            return (transformed, metadata)
        })
        await chain.addResponseInterceptor(TransformResponseInterceptor { data, metadata in
            // 添加后缀
            var transformed = data
            transformed.append(":RESP".data(using: .utf8)!)
            return (transformed, metadata)
        })

        let context = createMockContext()
        let testData = "DATA".data(using: .utf8)!

        // 测试请求转换
        let outgoing = try await chain.handleOutgoing(testData, context: context)
        let outgoingString = String(data: outgoing, encoding: .utf8)
        XCTAssertEqual(outgoingString, "REQ:DATA")

        // 测试响应转换
        let incoming = try await chain.handleIncoming(testData, context: context)
        let incomingString = String(data: incoming, encoding: .utf8)
        XCTAssertEqual(incomingString, "DATA:RESP")

        let stats = await chain.getStatistics()
        XCTAssertEqual(stats.requestsModified, 1)
        XCTAssertEqual(stats.responsesModified, 1)
    }

    func testInterceptorChainMultipleInterceptors() async throws {
        let chain = InterceptorChain()
        await chain.addRequestInterceptor(LoggingRequestInterceptor())
        await chain.addRequestInterceptor(ValidationRequestInterceptor(maxSize: 1000))
        await chain.addRequestInterceptor(TransformRequestInterceptor { data, metadata in
            let transformed = data.map { $0 ^ 0xFF }  // 简单XOR
            return (Data(transformed), metadata)
        })

        let context = createMockContext()
        let testData = Data([1, 2, 3, 4, 5])

        let outgoing = try await chain.handleOutgoing(testData, context: context)

        // 应该经过XOR转换
        let expected = Data([254, 253, 252, 251, 250])
        XCTAssertEqual(outgoing, expected)
    }

    func testInterceptorChainStatistics() async throws {
        let chain = InterceptorChain()
        await chain.addRequestInterceptor(ValidationRequestInterceptor(maxSize: 100))
        await chain.addResponseInterceptor(ValidationResponseInterceptor(maxSize: 100))

        let context = createMockContext()

        // 处理多次
        for i in 0..<5 {
            let data = Data(repeating: UInt8(i), count: 50)
            _ = try await chain.handleOutgoing(data, context: context)
            _ = try await chain.handleIncoming(data, context: context)
        }

        // 拒绝一次
        let largeData = Data(repeating: 1, count: 150)
        do {
            _ = try await chain.handleOutgoing(largeData, context: context)
        } catch {
            // 预期错误
        }

        let stats = await chain.getStatistics()
        XCTAssertEqual(stats.totalRequestsProcessed, 6)
        XCTAssertEqual(stats.totalResponsesProcessed, 5)
        XCTAssertEqual(stats.requestsRejected, 1)
        XCTAssertEqual(stats.responsesRejected, 0)
        XCTAssertGreaterThan(stats.averageRequestProcessingTime, 0)
        XCTAssertEqual(stats.requestPassRate, 5.0/6.0, accuracy: 0.01)
    }

    func testInterceptorChainManagement() async throws {
        let chain = InterceptorChain()
        await chain.addRequestInterceptor(LoggingRequestInterceptor())
        await chain.addRequestInterceptor(ValidationRequestInterceptor())
        await chain.addResponseInterceptor(LoggingResponseInterceptor())

        var requestInterceptors = await chain.getRequestInterceptors()
        XCTAssertEqual(requestInterceptors.count, 2)

        var responseInterceptors = await chain.getResponseInterceptors()
        XCTAssertEqual(responseInterceptors.count, 1)

        // 移除请求拦截器
        await chain.removeRequestInterceptor(named: "LoggingRequest")
        requestInterceptors = await chain.getRequestInterceptors()
        XCTAssertEqual(requestInterceptors.count, 1)

        // 清空所有响应拦截器
        await chain.clearResponseInterceptors()
        responseInterceptors = await chain.getResponseInterceptors()
        XCTAssertEqual(responseInterceptors.count, 0)
    }

    func testInterceptorChainConvenienceBuilders() async throws {
        // 测试带日志的链
        let loggingChain = await InterceptorChain.withLogging(logLevel: .debug)
        let loggingRequestInterceptors = await loggingChain.getRequestInterceptors()
        let loggingResponseInterceptors = await loggingChain.getResponseInterceptors()
        XCTAssertEqual(loggingRequestInterceptors.count, 1)
        XCTAssertEqual(loggingResponseInterceptors.count, 1)

        // 测试带验证的链
        let validationChain = await InterceptorChain.withValidation(maxSize: 1024)
        let validationRequestInterceptors = await validationChain.getRequestInterceptors()
        let validationResponseInterceptors = await validationChain.getResponseInterceptors()
        XCTAssertEqual(validationRequestInterceptors.count, 1)
        XCTAssertEqual(validationResponseInterceptors.count, 1)

        // 测试带缓存的链
        let cacheChain = await InterceptorChain.withCache(maxCacheSize: 50)
        let cacheResponseInterceptors = await cacheChain.getResponseInterceptors()
        XCTAssertEqual(cacheResponseInterceptors.count, 1)
    }

    // MARK: - Helper Methods

    private func createMockContext() -> MiddlewareContext {
        MiddlewareContext(
            connectionId: "test-connection",
            endpoint: .tcp(host: "localhost", port: 8080)
        )
    }
}
