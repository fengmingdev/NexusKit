//
//  RequestInterceptor.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  请求拦截器

import Foundation

// MARK: - Request Interceptor Protocol

/// 请求拦截器协议
///
/// 拦截出站数据（请求），可以修改、记录、验证或拒绝请求。
public protocol RequestInterceptor: Sendable {
    /// 拦截器名称
    var name: String { get }

    /// 拦截请求
    /// - Parameters:
    ///   - request: 请求数据和元数据
    ///   - context: 中间件上下文
    /// - Returns: 处理结果（通过、修改、拒绝）
    func intercept(request: InterceptorRequest, context: MiddlewareContext) async throws -> InterceptorResult
}

// MARK: - Interceptor Request

/// 拦截器请求
public struct InterceptorRequest: Sendable {
    /// 请求数据
    public var data: Data

    /// 请求元数据
    public var metadata: [String: String]

    /// 请求时间戳
    public let timestamp: Date

    /// 请求唯一标识
    public let requestId: String

    public init(
        data: Data,
        metadata: [String: String] = [:],
        timestamp: Date = Date(),
        requestId: String = UUID().uuidString
    ) {
        self.data = data
        self.metadata = metadata
        self.timestamp = timestamp
        self.requestId = requestId
    }
}

// MARK: - Interceptor Result

/// 拦截器处理结果
public enum InterceptorResult: Sendable {
    /// 通过（不修改）
    case passthrough(Data)

    /// 修改数据
    case modified(Data, metadata: [String: String])

    /// 拒绝请求
    case rejected(reason: String)

    /// 延迟处理
    case delayed(duration: TimeInterval, data: Data)

    /// 获取处理后的数据
    public var data: Data? {
        switch self {
        case .passthrough(let data), .modified(let data, _), .delayed(_, let data):
            return data
        case .rejected:
            return nil
        }
    }

    /// 是否被拒绝
    public var isRejected: Bool {
        if case .rejected = self { return true }
        return false
    }

    /// 是否被修改
    public var isModified: Bool {
        if case .modified = self { return true }
        return false
    }
}

// MARK: - Interceptor Error

/// 拦截器错误
public enum InterceptorError: Error, Sendable {
    /// 请求被拒绝
    case requestRejected(reason: String, interceptor: String)

    /// 响应被拒绝
    case responseRejected(reason: String, interceptor: String)

    /// 拦截器超时
    case timeout(interceptor: String)

    /// 无效的请求/响应
    case invalid(reason: String)
}

// MARK: - Common Request Interceptors

/// 日志拦截器
public struct LoggingRequestInterceptor: RequestInterceptor {
    public let name = "LoggingRequest"

    private let logLevel: LogLevel
    private let includeData: Bool

    public init(logLevel: LogLevel = .info, includeData: Bool = false) {
        self.logLevel = logLevel
        self.includeData = includeData
    }

    public func intercept(request: InterceptorRequest, context: MiddlewareContext) async throws -> InterceptorResult {
        var logMessage = "[请求] ID: \(request.requestId), 大小: \(request.data.count) bytes"

        if includeData && request.data.count < 1024 {
            if let dataString = String(data: request.data, encoding: .utf8) {
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

        return .passthrough(request.data)
    }
}

/// 数据验证拦截器
public struct ValidationRequestInterceptor: RequestInterceptor {
    public let name = "ValidationRequest"

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

    public func intercept(request: InterceptorRequest, context: MiddlewareContext) async throws -> InterceptorResult {
        // 大小验证
        if request.data.count < minSize {
            return .rejected(reason: "数据太小: \(request.data.count) < \(minSize)")
        }

        if request.data.count > maxSize {
            return .rejected(reason: "数据太大: \(request.data.count) > \(maxSize)")
        }

        // 自定义验证
        if let validator = validator, !validator(request.data) {
            return .rejected(reason: "自定义验证失败")
        }

        return .passthrough(request.data)
    }
}

/// 请求修改拦截器
public struct TransformRequestInterceptor: RequestInterceptor {
    public let name = "TransformRequest"

    private let transform: @Sendable (Data, [String: String]) async throws -> (Data, [String: String])

    public init(transform: @escaping @Sendable (Data, [String: String]) async throws -> (Data, [String: String])) {
        self.transform = transform
    }

    public func intercept(request: InterceptorRequest, context: MiddlewareContext) async throws -> InterceptorResult {
        let (transformedData, transformedMetadata) = try await transform(request.data, request.metadata)
        return .modified(transformedData, metadata: transformedMetadata)
    }
}

/// 请求节流拦截器
public struct ThrottleRequestInterceptor: RequestInterceptor {
    public let name = "ThrottleRequest"

    private let delay: TimeInterval

    public init(delay: TimeInterval) {
        self.delay = delay
    }

    public func intercept(request: InterceptorRequest, context: MiddlewareContext) async throws -> InterceptorResult {
        return .delayed(duration: delay, data: request.data)
    }
}

/// 条件拦截器
public struct ConditionalRequestInterceptor: RequestInterceptor {
    public let name: String

    private let condition: @Sendable (InterceptorRequest, MiddlewareContext) async -> Bool
    private let onMatch: any RequestInterceptor
    private let onNoMatch: (any RequestInterceptor)?

    public init(
        name: String = "ConditionalRequest",
        condition: @escaping @Sendable (InterceptorRequest, MiddlewareContext) async -> Bool,
        onMatch: any RequestInterceptor,
        onNoMatch: (any RequestInterceptor)? = nil
    ) {
        self.name = name
        self.condition = condition
        self.onMatch = onMatch
        self.onNoMatch = onNoMatch
    }

    public func intercept(request: InterceptorRequest, context: MiddlewareContext) async throws -> InterceptorResult {
        if await condition(request, context) {
            return try await onMatch.intercept(request: request, context: context)
        } else if let noMatch = onNoMatch {
            return try await noMatch.intercept(request: request, context: context)
        } else {
            return .passthrough(request.data)
        }
    }
}

/// 请求重试拦截器
public struct RetryRequestInterceptor: RequestInterceptor {
    public let name = "RetryRequest"

    private let maxRetries: Int
    private let retryDelay: TimeInterval
    private let shouldRetry: @Sendable (Error) -> Bool

    public init(
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0,
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true }
    ) {
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.shouldRetry = shouldRetry
    }

    public func intercept(request: InterceptorRequest, context: MiddlewareContext) async throws -> InterceptorResult {
        // 在实际使用中，重试逻辑需要与连接层协作
        // 这里只是标记需要重试
        var metadata = request.metadata
        metadata["retry.maxRetries"] = "\(maxRetries)"
        metadata["retry.delay"] = "\(retryDelay)"

        return .modified(request.data, metadata: metadata)
    }
}

/// 请求签名拦截器
public struct SignatureRequestInterceptor: RequestInterceptor {
    public let name = "SignatureRequest"

    private let signData: @Sendable (Data) async throws -> Data

    public init(signData: @escaping @Sendable (Data) async throws -> Data) {
        self.signData = signData
    }

    public func intercept(request: InterceptorRequest, context: MiddlewareContext) async throws -> InterceptorResult {
        let signedData = try await signData(request.data)
        return .modified(signedData, metadata: request.metadata)
    }
}
