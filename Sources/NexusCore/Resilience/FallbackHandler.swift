//
//  FallbackHandler.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  Fallback处理器 - 提供降级和兜底方案

import Foundation

// MARK: - Fallback Strategy

/// Fallback策略协议
///
/// 定义在主操作失败时的降级处理逻辑。
public protocol FallbackStrategy<Value>: Sendable {
    associatedtype Value: Sendable

    /// 执行Fallback
    /// - Parameters:
    ///   - error: 主操作失败的错误
    ///   - context: 上下文信息
    /// - Returns: Fallback值
    func execute(error: Error, context: FallbackContext) async throws -> Value
}

/// Fallback上下文
public struct FallbackContext: Sendable {
    /// 操作名称
    public let operationName: String

    /// 尝试次数
    public let attemptCount: Int

    /// 额外元数据
    public let metadata: [String: String]

    public init(
        operationName: String = "",
        attemptCount: Int = 0,
        metadata: [String: String] = [:]
    ) {
        self.operationName = operationName
        self.attemptCount = attemptCount
        self.metadata = metadata
    }
}

// MARK: - Default Value Fallback

/// 默认值Fallback策略
///
/// 在操作失败时返回预设的默认值。
public struct DefaultValueFallback<T: Sendable>: FallbackStrategy {
    public typealias Value = T

    private let defaultValue: T

    public init(defaultValue: T) {
        self.defaultValue = defaultValue
    }

    public func execute(error: Error, context: FallbackContext) async throws -> T {
        return defaultValue
    }
}

// MARK: - Cache Fallback

/// 缓存Fallback策略
///
/// 在操作失败时返回缓存的值（如果存在）。
public actor CacheFallback<T: Sendable>: FallbackStrategy {
    public typealias Value = T

    private var cache: [String: CachedValue] = [:]
    private let maxAge: TimeInterval

    private struct CachedValue {
        let value: T
        let timestamp: Date
    }

    public init(maxAge: TimeInterval = 3600) {
        self.maxAge = maxAge
    }

    /// 更新缓存
    public func updateCache(key: String, value: T) {
        cache[key] = CachedValue(value: value, timestamp: Date())
    }

    /// 清除过期缓存
    public func cleanupExpiredCache() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        cache = cache.filter { $0.value.timestamp >= cutoff }
    }

    public func execute(error: Error, context: FallbackContext) async throws -> T {
        // 清理过期缓存
        await cleanupExpiredCache()

        // 获取缓存值
        guard let cached = cache[context.operationName] else {
            throw FallbackError.noCachedValue
        }

        // 检查是否过期
        let age = Date().timeIntervalSince(cached.timestamp)
        guard age <= maxAge else {
            throw FallbackError.cacheExpired
        }

        return cached.value
    }
}

// MARK: - Degraded Service Fallback

/// 降级服务Fallback策略
///
/// 在主服务失败时调用降级服务。
public struct DegradedServiceFallback<T: Sendable>: FallbackStrategy {
    public typealias Value = T

    private let fallbackService: @Sendable () async throws -> T

    public init(fallbackService: @escaping @Sendable () async throws -> T) {
        self.fallbackService = fallbackService
    }

    public func execute(error: Error, context: FallbackContext) async throws -> T {
        return try await fallbackService()
    }
}

// MARK: - Chain Fallback

/// 链式Fallback策略
///
/// 按顺序尝试多个Fallback策略，直到成功或全部失败。
@available(macOS 13.0, iOS 16.0, *)
public struct ChainFallback<T: Sendable>: FallbackStrategy {
    public typealias Value = T

    private let strategies: [any FallbackStrategy<T>]

    public init(strategies: [any FallbackStrategy<T>]) {
        self.strategies = strategies
    }

    public func execute(error: Error, context: FallbackContext) async throws -> T {
        var lastError = error

        for strategy in strategies {
            do {
                return try await strategy.execute(error: lastError, context: context)
            } catch {
                lastError = error
                continue
            }
        }

        // 所有策略都失败
        throw FallbackError.allStrategiesFailed(lastError: lastError)
    }
}

// MARK: - Conditional Fallback

/// 条件Fallback策略
///
/// 根据错误类型选择不同的Fallback策略。
@available(macOS 13.0, iOS 16.0, *)
public struct ConditionalFallback<T: Sendable>: FallbackStrategy {
    public typealias Value = T

    private let strategies: [(condition: @Sendable (Error) -> Bool, strategy: any FallbackStrategy<T>)]
    private let defaultStrategy: (any FallbackStrategy<T>)?

    public init(
        strategies: [(condition: @Sendable (Error) -> Bool, strategy: any FallbackStrategy<T>)],
        defaultStrategy: (any FallbackStrategy<T>)? = nil
    ) {
        self.strategies = strategies
        self.defaultStrategy = defaultStrategy
    }

    public func execute(error: Error, context: FallbackContext) async throws -> T {
        // 查找匹配的策略
        for (condition, strategy) in strategies {
            if condition(error) {
                return try await strategy.execute(error: error, context: context)
            }
        }

        // 使用默认策略
        if let defaultStrategy = defaultStrategy {
            return try await defaultStrategy.execute(error: error, context: context)
        }

        // 无匹配策略
        throw FallbackError.noMatchingStrategy
    }
}

// MARK: - Fallback Error

/// Fallback错误
public enum FallbackError: Error, Sendable {
    /// 没有缓存值
    case noCachedValue

    /// 缓存已过期
    case cacheExpired

    /// 所有策略都失败
    case allStrategiesFailed(lastError: Error)

    /// 没有匹配的策略
    case noMatchingStrategy
}

// MARK: - Fallback Handler

/// Fallback处理器
///
/// 整合主操作和Fallback策略。
public struct FallbackHandler<T: Sendable> {
    private let operationName: String
    private let strategy: any FallbackStrategy<T>

    public init(
        operationName: String,
        strategy: any FallbackStrategy<T>
    ) {
        self.operationName = operationName
        self.strategy = strategy
    }

    /// 执行操作（带Fallback保护）
    /// - Parameter operation: 主操作
    /// - Returns: 操作结果或Fallback值
    public func execute(
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            // 主操作失败，尝试Fallback
            let context = FallbackContext(
                operationName: operationName,
                attemptCount: 1
            )
            return try await strategy.execute(error: error, context: context)
        }
    }

    /// 执行操作（带重试和Fallback）
    /// - Parameters:
    ///   - maxRetries: 最大重试次数
    ///   - retryDelay: 重试延迟
    ///   - operation: 主操作
    /// - Returns: 操作结果或Fallback值
    public func execute(
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var attempt = 0

        while attempt < maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                attempt += 1

                // 如果还有重试机会，延迟后继续
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                }
            }
        }

        // 所有重试都失败，尝试Fallback
        let context = FallbackContext(
            operationName: operationName,
            attemptCount: attempt
        )

        if let error = lastError {
            return try await strategy.execute(error: error, context: context)
        } else {
            throw FallbackError.allStrategiesFailed(lastError: NSError(domain: "Unknown", code: -1))
        }
    }
}

// MARK: - Convenience Extensions

// Note: Convenience extensions for FallbackStrategy are commented out due to Swift limitation
// with recursive generic constraints. Use concrete types directly instead:
//
// let strategy = DefaultValueFallback(defaultValue: someValue)
// let strategy = DegradedServiceFallback { try await someService() }

// MARK: - Usage Examples in Documentation

/*
 使用示例：

 1. 默认值Fallback
 ```swift
 let handler = FallbackHandler(
     operationName: "fetchUserData",
     strategy: .defaultValue(User.guest)
 )

 let user = try await handler.execute {
     try await api.fetchUser()
 }
 ```

 2. 缓存Fallback
 ```swift
 let cache = CacheFallback<UserData>(maxAge: 3600)
 let handler = FallbackHandler(
     operationName: "userData",
     strategy: cache
 )

 // 更新缓存
 await cache.updateCache(key: "userData", value: userData)

 // 使用
 let data = try await handler.execute {
     try await api.fetchUserData()
 }
 ```

 3. 链式Fallback
 ```swift
 let handler = FallbackHandler(
     operationName: "content",
     strategy: ChainFallback(strategies: [
         cache,
         degradedService { try await backupAPI.fetch() },
         defaultValue(Content.empty)
     ])
 )
 ```

 4. 条件Fallback
 ```swift
 let handler = FallbackHandler(
     operationName: "data",
     strategy: ConditionalFallback(
         strategies: [
             ({ $0 is NetworkError }, cache),
             ({ $0 is AuthError }, defaultValue(nil))
         ],
         defaultStrategy: degradedService { try await backup() }
     )
 )
 ```

 5. 带重试的Fallback
 ```swift
 let result = try await handler.execute(
     maxRetries: 3,
     retryDelay: 1.0
 ) {
     try await riskyOperation()
 }
 ```
 */
