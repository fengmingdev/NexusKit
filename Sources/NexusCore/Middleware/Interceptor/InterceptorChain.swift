//
//  InterceptorChain.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  拦截器链

import Foundation

// MARK: - Interceptor Chain Middleware

/// 拦截器链中间件
///
/// 将请求和响应拦截器组织成链式处理管道。
///
/// ## 功能特性
///
/// - 请求拦截链 (RequestInterceptor)
/// - 响应拦截链 (ResponseInterceptor)
/// - 双向独立配置
/// - 顺序处理
/// - 统计信息
///
/// ## 使用示例
///
/// ```swift
/// let interceptorChain = InterceptorChain()
///     .addRequestInterceptor(LoggingRequestInterceptor())
///     .addRequestInterceptor(ValidationRequestInterceptor(maxSize: 1024 * 1024))
///     .addResponseInterceptor(LoggingResponseInterceptor())
///     .addResponseInterceptor(CacheResponseInterceptor())
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(interceptorChain)
///     .connect()
/// ```
public actor InterceptorChain: Middleware {

    public let name = "InterceptorChain"
    public let priority: Int

    /// 请求拦截器列表
    private var requestInterceptors: [any RequestInterceptor] = []

    /// 响应拦截器列表
    private var responseInterceptors: [any ResponseInterceptor] = []

    /// 统计信息
    private var stats: Statistics

    private struct Statistics {
        var totalRequestsProcessed: Int = 0
        var totalResponsesProcessed: Int = 0
        var requestsRejected: Int = 0
        var responsesRejected: Int = 0
        var requestsModified: Int = 0
        var responsesModified: Int = 0
        var totalRequestProcessingTime: TimeInterval = 0
        var totalResponseProcessingTime: TimeInterval = 0
    }

    // MARK: - Initialization

    public init(priority: Int = 5) {
        self.priority = priority
        self.stats = Statistics()
    }

    // MARK: - Interceptor Management

    /// 添加请求拦截器
    public func addRequestInterceptor(_ interceptor: any RequestInterceptor) {
        requestInterceptors.append(interceptor)
    }

    /// 添加响应拦截器
    public func addResponseInterceptor(_ interceptor: any ResponseInterceptor) {
        responseInterceptors.append(interceptor)
    }

    /// 移除请求拦截器
    public func removeRequestInterceptor(named name: String) {
        requestInterceptors.removeAll { $0.name == name }
    }

    /// 移除响应拦截器
    public func removeResponseInterceptor(named name: String) {
        responseInterceptors.removeAll { $0.name == name }
    }

    /// 清空所有请求拦截器
    public func clearRequestInterceptors() {
        requestInterceptors.removeAll()
    }

    /// 清空所有响应拦截器
    public func clearResponseInterceptors() {
        responseInterceptors.removeAll()
    }

    /// 获取所有请求拦截器
    public func getRequestInterceptors() -> [String] {
        requestInterceptors.map { $0.name }
    }

    /// 获取所有响应拦截器
    public func getResponseInterceptors() -> [String] {
        responseInterceptors.map { $0.name }
    }

    // MARK: - Middleware Protocol

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        let startTime = Date()
        stats.totalRequestsProcessed += 1

        var request = InterceptorRequest(
            data: data,
            metadata: context.metadata
        )

        var processedData = data

        // 依次执行所有请求拦截器
        for interceptor in requestInterceptors {
            do {
                let result = try await interceptor.intercept(request: request, context: context)

                // 处理结果
                switch result {
                case .passthrough(let resultData):
                    processedData = resultData
                    request.data = resultData

                case .modified(let resultData, let metadata):
                    processedData = resultData
                    request.data = resultData
                    request.metadata = metadata
                    stats.requestsModified += 1

                case .rejected(let reason):
                    stats.requestsRejected += 1
                    await logWarning("请求被拦截器 [\(interceptor.name)] 拒绝: \(reason)")
                    throw InterceptorError.requestRejected(reason: reason, interceptor: interceptor.name)

                case .delayed(let duration, let resultData):
                    // 延迟处理
                    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    processedData = resultData
                    request.data = resultData
                }

            } catch let error as InterceptorError {
                throw error
            } catch {
                await logError("拦截器 [\(interceptor.name)] 处理失败: \(error)")
                throw InterceptorError.invalid(reason: "拦截器处理失败: \(error.localizedDescription)")
            }
        }

        let processingTime = Date().timeIntervalSince(startTime)
        stats.totalRequestProcessingTime += processingTime

        return processedData
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        let startTime = Date()
        stats.totalResponsesProcessed += 1

        var response = InterceptorResponse(
            data: data,
            metadata: context.metadata
        )

        var processedData = data

        // 依次执行所有响应拦截器
        for interceptor in responseInterceptors {
            do {
                let result = try await interceptor.intercept(response: response, context: context)

                // 处理结果
                switch result {
                case .passthrough(let resultData):
                    processedData = resultData
                    response.data = resultData

                case .modified(let resultData, let metadata):
                    processedData = resultData
                    response.data = resultData
                    response.metadata = metadata
                    stats.responsesModified += 1

                case .rejected(let reason):
                    stats.responsesRejected += 1
                    await logWarning("响应被拦截器 [\(interceptor.name)] 拒绝: \(reason)")
                    throw InterceptorError.responseRejected(reason: reason, interceptor: interceptor.name)

                case .delayed(let duration, let resultData):
                    // 延迟处理
                    try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    processedData = resultData
                    response.data = resultData
                }

            } catch let error as InterceptorError {
                throw error
            } catch {
                await logError("拦截器 [\(interceptor.name)] 处理失败: \(error)")
                throw InterceptorError.invalid(reason: "拦截器处理失败: \(error.localizedDescription)")
            }
        }

        let processingTime = Date().timeIntervalSince(startTime)
        stats.totalResponseProcessingTime += processingTime

        return processedData
    }

    // MARK: - Statistics

    /// 获取统计信息
    public func getStatistics() -> InterceptorChainStatistics {
        InterceptorChainStatistics(
            totalRequestsProcessed: stats.totalRequestsProcessed,
            totalResponsesProcessed: stats.totalResponsesProcessed,
            requestsRejected: stats.requestsRejected,
            responsesRejected: stats.responsesRejected,
            requestsModified: stats.requestsModified,
            responsesModified: stats.responsesModified,
            averageRequestProcessingTime: stats.totalRequestsProcessed > 0
                ? stats.totalRequestProcessingTime / Double(stats.totalRequestsProcessed)
                : 0.0,
            averageResponseProcessingTime: stats.totalResponsesProcessed > 0
                ? stats.totalResponseProcessingTime / Double(stats.totalResponsesProcessed)
                : 0.0,
            totalRequestInterceptors: requestInterceptors.count,
            totalResponseInterceptors: responseInterceptors.count
        )
    }

    /// 重置统计信息
    public func resetStatistics() {
        stats = Statistics()
    }
}

// MARK: - Interceptor Chain Statistics

/// 拦截器链统计信息
public struct InterceptorChainStatistics: Sendable {
    /// 处理的请求总数
    public let totalRequestsProcessed: Int

    /// 处理的响应总数
    public let totalResponsesProcessed: Int

    /// 被拒绝的请求数
    public let requestsRejected: Int

    /// 被拒绝的响应数
    public let responsesRejected: Int

    /// 被修改的请求数
    public let requestsModified: Int

    /// 被修改的响应数
    public let responsesModified: Int

    /// 平均请求处理时间（秒）
    public let averageRequestProcessingTime: TimeInterval

    /// 平均响应处理时间（秒）
    public let averageResponseProcessingTime: TimeInterval

    /// 请求拦截器总数
    public let totalRequestInterceptors: Int

    /// 响应拦截器总数
    public let totalResponseInterceptors: Int

    /// 请求通过率
    public var requestPassRate: Double {
        guard totalRequestsProcessed > 0 else { return 1.0 }
        return Double(totalRequestsProcessed - requestsRejected) / Double(totalRequestsProcessed)
    }

    /// 响应通过率
    public var responsePassRate: Double {
        guard totalResponsesProcessed > 0 else { return 1.0 }
        return Double(totalResponsesProcessed - responsesRejected) / Double(totalResponsesProcessed)
    }
}

// MARK: - Convenience Builders

extension InterceptorChain {

    /// 创建带日志的拦截器链
    public static func withLogging(
        logLevel: LogLevel = .info,
        includeData: Bool = false,
        priority: Int = 5
    ) async -> InterceptorChain {
        let chain = InterceptorChain(priority: priority)
        await chain.addRequestInterceptor(LoggingRequestInterceptor(logLevel: logLevel, includeData: includeData))
        await chain.addResponseInterceptor(LoggingResponseInterceptor(logLevel: logLevel, includeData: includeData))
        return chain
    }

    /// 创建带验证的拦截器链
    public static func withValidation(
        minSize: Int = 0,
        maxSize: Int = 10 * 1024 * 1024,
        priority: Int = 5
    ) async -> InterceptorChain {
        let chain = InterceptorChain(priority: priority)
        await chain.addRequestInterceptor(ValidationRequestInterceptor(minSize: minSize, maxSize: maxSize))
        await chain.addResponseInterceptor(ValidationResponseInterceptor(minSize: minSize, maxSize: maxSize))
        return chain
    }

    /// 创建带缓存的拦截器链
    public static func withCache(
        maxCacheSize: Int = 100,
        cacheTTL: TimeInterval = 300,
        priority: Int = 5
    ) async -> InterceptorChain {
        let chain = InterceptorChain(priority: priority)
        await chain.addResponseInterceptor(CacheResponseInterceptor(maxCacheSize: maxCacheSize, cacheTTL: cacheTTL))
        return chain
    }
}
