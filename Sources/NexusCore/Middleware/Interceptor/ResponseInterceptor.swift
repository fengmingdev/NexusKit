//
//  ResponseInterceptor.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  响应拦截器

import Foundation

// MARK: - Response Interceptor Protocol

/// 响应拦截器协议
///
/// 拦截入站数据（响应），可以修改、记录、验证或拒绝响应。
public protocol ResponseInterceptor: Sendable {
    /// 拦截器名称
    var name: String { get }

    /// 拦截响应
    /// - Parameters:
    ///   - response: 响应数据和元数据
    ///   - context: 中间件上下文
    /// - Returns: 处理结果（通过、修改、拒绝）
    func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult
}

// MARK: - Interceptor Response

/// 拦截器响应
public struct InterceptorResponse: Sendable {
    /// 响应数据
    public var data: Data

    /// 响应元数据
    public var metadata: [String: String]

    /// 响应时间戳
    public let timestamp: Date

    /// 响应唯一标识
    public let responseId: String

    /// 对应的请求ID（如果有）
    public var requestId: String?

    public init(
        data: Data,
        metadata: [String: String] = [:],
        timestamp: Date = Date(),
        responseId: String = UUID().uuidString,
        requestId: String? = nil
    ) {
        self.data = data
        self.metadata = metadata
        self.timestamp = timestamp
        self.responseId = responseId
        self.requestId = requestId
    }
}

// MARK: - Common Response Interceptors

/// 日志响应拦截器
public struct LoggingResponseInterceptor: ResponseInterceptor {
    public let name = "LoggingResponse"

    private let logLevel: LogLevel
    private let includeData: Bool

    public init(logLevel: LogLevel = .info, includeData: Bool = false) {
        self.logLevel = logLevel
        self.includeData = includeData
    }

    public func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult {
        var logMessage = "[响应] ID: \(response.responseId), 大小: \(response.data.count) bytes"

        if let requestId = response.requestId {
            logMessage += ", 请求ID: \(requestId)"
        }

        if includeData && response.data.count < 1024 {
            if let dataString = String(data: response.data, encoding: .utf8) {
                logMessage += ", 内容: \(dataString)"
            }
        }

        switch logLevel {
        case .trace:
            await logTrace(logMessage)
        case .debug:
            await logDebug(logMessage)
        case .info:
            await logInfo(logMessage)
        case .warning:
            await logWarning(logMessage)
        case .error:
            await logError(logMessage)
        case .critical:
            await logCritical(logMessage)
        }

        return .passthrough(response.data)
    }
}

/// 响应验证拦截器
public struct ValidationResponseInterceptor: ResponseInterceptor {
    public let name = "ValidationResponse"

    private let minSize: Int
    private let maxSize: Int
    private let validator: (@Sendable (Data) -> Bool)?

    public init(
        minSize: Int = 0,
        maxSize: Int = 10 * 1024 * 1024,  // 10MB
        validator: (@Sendable (Data) -> Bool)? = nil
    ) {
        self.minSize = minSize
        self.maxSize = maxSize
        self.validator = validator
    }

    public func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult {
        // 大小验证
        if response.data.count < minSize {
            return .rejected(reason: "响应数据太小: \(response.data.count) < \(minSize)")
        }

        if response.data.count > maxSize {
            return .rejected(reason: "响应数据太大: \(response.data.count) > \(maxSize)")
        }

        // 自定义验证
        if let validator = validator, !validator(response.data) {
            return .rejected(reason: "响应自定义验证失败")
        }

        return .passthrough(response.data)
    }
}

/// 响应转换拦截器
public struct TransformResponseInterceptor: ResponseInterceptor {
    public let name = "TransformResponse"

    private let transform: @Sendable (Data, [String: String]) async throws -> (Data, [String: String])

    public init(transform: @escaping @Sendable (Data, [String: String]) async throws -> (Data, [String: String])) {
        self.transform = transform
    }

    public func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult {
        let (transformedData, transformedMetadata) = try await transform(response.data, response.metadata)
        return .modified(transformedData, metadata: transformedMetadata)
    }
}

/// 响应缓存拦截器
public actor CacheResponseInterceptor: ResponseInterceptor {
    public let name = "CacheResponse"

    private var cache: [String: CachedResponse] = [:]
    private let maxCacheSize: Int
    private let cacheTTL: TimeInterval

    struct CachedResponse {
        let data: Data
        let timestamp: Date
        let metadata: [String: String]
    }

    public init(maxCacheSize: Int = 100, cacheTTL: TimeInterval = 300) {
        self.maxCacheSize = maxCacheSize
        self.cacheTTL = cacheTTL
    }

    public func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult {
        // 缓存响应
        if let requestId = response.requestId {
            cache[requestId] = CachedResponse(
                data: response.data,
                timestamp: response.timestamp,
                metadata: response.metadata
            )

            // 清理过期缓存
            cleanupExpiredCache()

            // 限制缓存大小
            if cache.count > maxCacheSize {
                // 移除最旧的条目
                if let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                    cache.removeValue(forKey: oldestKey)
                }
            }
        }

        return .passthrough(response.data)
    }

    /// 获取缓存的响应
    public func getCachedResponse(for requestId: String) -> Data? {
        guard let cached = cache[requestId] else { return nil }

        // 检查是否过期
        let age = Date().timeIntervalSince(cached.timestamp)
        if age > cacheTTL {
            cache.removeValue(forKey: requestId)
            return nil
        }

        return cached.data
    }

    /// 清理过期缓存
    private func cleanupExpiredCache() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) <= cacheTTL }
    }

    /// 清空缓存
    public func clearCache() {
        cache.removeAll()
    }
}

/// 条件响应拦截器
public struct ConditionalResponseInterceptor: ResponseInterceptor {
    public let name: String

    private let condition: @Sendable (InterceptorResponse, MiddlewareContext) async -> Bool
    private let onMatch: any ResponseInterceptor
    private let onNoMatch: (any ResponseInterceptor)?

    public init(
        name: String = "ConditionalResponse",
        condition: @escaping @Sendable (InterceptorResponse, MiddlewareContext) async -> Bool,
        onMatch: any ResponseInterceptor,
        onNoMatch: (any ResponseInterceptor)? = nil
    ) {
        self.name = name
        self.condition = condition
        self.onMatch = onMatch
        self.onNoMatch = onNoMatch
    }

    public func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult {
        if await condition(response, context) {
            return try await onMatch.intercept(response: response, context: context)
        } else if let noMatch = onNoMatch {
            return try await noMatch.intercept(response: response, context: context)
        } else {
            return .passthrough(response.data)
        }
    }
}

/// 响应验签拦截器
public struct VerifyResponseInterceptor: ResponseInterceptor {
    public let name = "VerifyResponse"

    private let verifyData: @Sendable (Data) async throws -> Bool

    public init(verifyData: @escaping @Sendable (Data) async throws -> Bool) {
        self.verifyData = verifyData
    }

    public func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult {
        let isValid = try await verifyData(response.data)

        if isValid {
            return .passthrough(response.data)
        } else {
            return .rejected(reason: "响应签名验证失败")
        }
    }
}

/// 响应解析拦截器
public struct ParserResponseInterceptor: ResponseInterceptor {
    public let name = "ParserResponse"

    public enum ParseError: Error {
        case invalidFormat(String)
        case parseFailure(String)
    }

    private let parser: @Sendable (Data) async throws -> Data

    public init(parser: @escaping @Sendable (Data) async throws -> Data) {
        self.parser = parser
    }

    public func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult {
        do {
            let parsedData = try await parser(response.data)
            return .modified(parsedData, metadata: response.metadata)
        } catch {
            return .rejected(reason: "响应解析失败: \(error.localizedDescription)")
        }
    }
}

/// 响应超时检测拦截器
public struct TimeoutResponseInterceptor: ResponseInterceptor {
    public let name = "TimeoutResponse"

    private let maxResponseTime: TimeInterval

    public init(maxResponseTime: TimeInterval = 30.0) {
        self.maxResponseTime = maxResponseTime
    }

    public func intercept(response: InterceptorResponse, context: MiddlewareContext) async throws -> InterceptorResult {
        // 检查响应时间（需要从元数据中获取请求时间）
        if let requestTimeString = response.metadata["request.timestamp"],
           let requestTime = TimeInterval(requestTimeString) {
            let responseTime = response.timestamp.timeIntervalSince1970 - requestTime

            if responseTime > maxResponseTime {
                return .rejected(reason: "响应超时: \(responseTime)s > \(maxResponseTime)s")
            }
        }

        return .passthrough(response.data)
    }
}
