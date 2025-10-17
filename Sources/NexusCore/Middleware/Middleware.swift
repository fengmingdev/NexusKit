//
//  Middleware.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Middleware Protocol

/// 中间件协议 - 拦截和处理消息的中间层
///
/// `Middleware` 提供了一种可扩展的方式来处理连接中的数据流。
/// 中间件可以用于日志记录、数据压缩、加密、性能监控等场景。
///
/// ## 设计模式
///
/// 中间件基于**管道模式**（Pipeline Pattern）：
/// - **出站数据**: 按优先级顺序依次处理
/// - **入站数据**: 按优先级逆序处理（先进后出）
///
/// ## 优先级
///
/// - 数字越小，优先级越高
/// - 默认优先级为 100
/// - 推荐范围：0-1000
///
/// ## 使用示例
///
/// ### 定义中间件
/// ```swift
/// struct LoggingMiddleware: Middleware {
///     let name = "Logging"
///     let priority = 10  // 高优先级，最先处理
///
///     func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
///         print("[发送] \(data.count) 字节")
///         return data  // 不修改数据
///     }
///
///     func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
///         print("[接收] \(data.count) 字节")
///         return data
///     }
/// }
/// ```
///
/// ### 应用中间件
/// ```swift
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(LoggingMiddleware())
///     .middleware(CompressionMiddleware())
///     .connect()
/// ```
///
/// ### 处理顺序
///
/// 假设有两个中间件：
/// - LoggingMiddleware (优先级 10)
/// - CompressionMiddleware (优先级 20)
///
/// **发送流程**:
/// ```
/// 原始数据 → Logging → Compression → 网络
/// ```
///
/// **接收流程**:
/// ```
/// 网络 → Compression → Logging → 应用
/// ```
public protocol Middleware: Sendable {
    /// 中间件唯一名称
    ///
    /// 用于标识和管理中间件。建议使用描述性名称。
    var name: String { get }

    /// 优先级（数字越小优先级越高）
    ///
    /// 默认值为 100。推荐范围：
    /// - 0-50: 高优先级（日志、监控）
    /// - 50-100: 中等优先级（压缩、加密）
    /// - 100-200: 低优先级（自定义处理）
    var priority: Int { get }

    /// 处理出站数据（发送前）
    ///
    /// 在数据发送到网络之前调用。可以修改、记录或检查数据。
    ///
    /// - Parameters:
    ///   - data: 原始数据
    ///   - context: 中间件上下文（包含连接信息、方向、元数据等）
    ///
    /// - Returns: 处理后的数据。如果不需要修改，返回原数据
    ///
    /// - Throws: 处理失败时抛出错误，会被包装为 `NexusError.middlewareError`
    ///
    /// ## 示例
    /// ```swift
    /// func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
    ///     // 记录日志
    ///     print("发送到 \(context.connectionId): \(data.count) 字节")
    ///
    ///     // 压缩数据（如果大于 1KB）
    ///     if data.count > 1024 {
    ///         return try data.gzipped()
    ///     }
    ///
    ///     return data
    /// }
    /// ```
    func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data

    /// 处理入站数据（接收后）
    ///
    /// 在从网络接收数据后调用。可以解密、解压或验证数据。
    ///
    /// - Parameters:
    ///   - data: 原始接收数据
    ///   - context: 中间件上下文
    ///
    /// - Returns: 处理后的数据
    ///
    /// - Throws: 处理失败时抛出错误
    ///
    /// ## 示例
    /// ```swift
    /// func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
    ///     // 尝试解压缩
    ///     if let decompressed = try? data.gunzipped() {
    ///         print("解压: \(data.count) → \(decompressed.count) 字节")
    ///         return decompressed
    ///     }
    ///
    ///     return data
    /// }
    /// ```
    func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data

    /// 连接建立时调用
    ///
    /// 可用于初始化资源、记录连接事件等。
    ///
    /// - Parameter connection: 新建立的连接对象
    ///
    /// ## 注意
    /// 默认实现为空，可选实现。
    func onConnect(connection: any Connection) async

    /// 连接断开时调用
    ///
    /// 可用于清理资源、记录断开事件等。
    ///
    /// - Parameters:
    ///   - connection: 已断开的连接对象
    ///   - reason: 断开原因
    ///
    /// ## 注意
    /// 默认实现为空，可选实现。
    func onDisconnect(connection: any Connection, reason: DisconnectReason) async

    /// 错误处理
    ///
    /// 当中间件处理过程中发生错误时调用。
    ///
    /// - Parameters:
    ///   - error: 发生的错误
    ///   - context: 错误发生时的上下文
    ///
    /// ## 注意
    /// 默认实现为空，可选实现。可用于错误日志记录。
    func onError(error: Error, context: MiddlewareContext) async
}

// MARK: - Default Implementations

public extension Middleware {
    var priority: Int { 100 }

    func onConnect(connection: any Connection) async {}
    func onDisconnect(connection: any Connection, reason: DisconnectReason) async {}
    func onError(error: Error, context: MiddlewareContext) async {}
}

// MARK: - Middleware Context

/// 中间件上下文
///
/// 提供中间件处理数据时所需的上下文信息。
///
/// ## 使用示例
///
/// ```swift
/// struct MetricsMiddleware: Middleware {
///     let name = "Metrics"
///
///     func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
///         // 使用上下文信息
///         print("连接 \(context.connectionId)")
///         print("端点: \(context.endpoint)")
///         print("数据: \(data.count) 字节")
///
///         // 访问自定义元数据
///         if let userId = context.metadata["userId"] {
///             print("用户: \(userId)")
///         }
///
///         return data
///     }
/// }
/// ```
public struct MiddlewareContext: Sendable {
    /// 连接唯一标识符
    public let connectionId: String

    /// 连接端点信息
    public let endpoint: Endpoint

    /// 时间戳
    public let timestamp: Date

    /// 自定义元数据
    ///
    /// 用于在中间件之间传递额外信息
    public var metadata: [String: Any] = [:]

    public init(
        connectionId: String,
        endpoint: Endpoint,
        timestamp: Date = Date(),
        metadata: [String: Any] = [:]
    ) {
        self.connectionId = connectionId
        self.endpoint = endpoint
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - Middleware Pipeline

/// 中间件管道
public actor MiddlewarePipeline {
    private var middlewares: [any Middleware] = []

    public init() {}

    /// 添加中间件
    /// - Parameter middleware: 中间件实例
    public func add(_ middleware: any Middleware) {
        middlewares.append(middleware)
        // 按优先级排序
        middlewares.sort { $0.priority < $1.priority }
    }

    /// 移除中间件
    /// - Parameter name: 中间件名称
    public func remove(named name: String) {
        middlewares.removeAll { $0.name == name }
    }

    /// 清空所有中间件
    public func removeAll() {
        middlewares.removeAll()
    }

    /// 获取所有中间件
    public func all() -> [any Middleware] {
        middlewares
    }

    /// 处理出站数据（通过所有中间件）
    /// - Parameters:
    ///   - data: 原始数据
    ///   - context: 上下文
    /// - Returns: 处理后的数据
    /// - Throws: 任何中间件抛出的错误
    public func processOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        var processedData = data

        for middleware in middlewares {
            do {
                processedData = try await middleware.handleOutgoing(processedData, context: context)
            } catch {
                await middleware.onError(error: error, context: context)
                throw NexusError.middlewareError(name: middleware.name, error: error)
            }
        }

        return processedData
    }

    /// 处理入站数据（通过所有中间件，逆序）
    /// - Parameters:
    ///   - data: 原始数据
    ///   - context: 上下文
    /// - Returns: 处理后的数据
    /// - Throws: 任何中间件抛出的错误
    public func processIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        var processedData = data

        // 入站数据逆序处理（先进后出）
        for middleware in middlewares.reversed() {
            do {
                processedData = try await middleware.handleIncoming(processedData, context: context)
            } catch {
                await middleware.onError(error: error, context: context)
                throw NexusError.middlewareError(name: middleware.name, error: error)
            }
        }

        return processedData
    }

    /// 通知所有中间件连接已建立
    /// - Parameter connection: 连接对象
    public func notifyConnect(connection: any Connection) async {
        for middleware in middlewares {
            await middleware.onConnect(connection: connection)
        }
    }

    /// 通知所有中间件连接已断开
    /// - Parameters:
    ///   - connection: 连接对象
    ///   - reason: 断开原因
    public func notifyDisconnect(connection: any Connection, reason: DisconnectReason) async {
        for middleware in middlewares {
            await middleware.onDisconnect(connection: connection, reason: reason)
        }
    }
}

// MARK: - Conditional Middleware

/// 条件中间件 - 只在满足条件时执行
public struct ConditionalMiddleware: Middleware {
    public let name: String
    public let priority: Int
    private let condition: @Sendable (MiddlewareContext) -> Bool
    private let wrapped: any Middleware

    public init(
        name: String,
        priority: Int = 100,
        condition: @escaping @Sendable (MiddlewareContext) -> Bool,
        middleware: any Middleware
    ) {
        self.name = name
        self.priority = priority
        self.condition = condition
        self.wrapped = middleware
    }

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard condition(context) else { return data }
        return try await wrapped.handleOutgoing(data, context: context)
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard condition(context) else { return data }
        return try await wrapped.handleIncoming(data, context: context)
    }

    public func onConnect(connection: any Connection) async {
        await wrapped.onConnect(connection: connection)
    }

    public func onDisconnect(connection: any Connection, reason: DisconnectReason) async {
        await wrapped.onDisconnect(connection: connection, reason: reason)
    }

    public func onError(error: Error, context: MiddlewareContext) async {
        await wrapped.onError(error: error, context: context)
    }
}

// MARK: - Middleware Composition

public extension Middleware {
    /// 组合两个中间件
    /// - Parameter other: 另一个中间件
    /// - Returns: 组合后的中间件
    func compose(with other: any Middleware) -> ComposedMiddleware {
        ComposedMiddleware(first: self, second: other)
    }

    /// 添加条件
    /// - Parameter condition: 执行条件
    /// - Returns: 条件中间件
    func when(_ condition: @escaping @Sendable (MiddlewareContext) -> Bool) -> ConditionalMiddleware {
        ConditionalMiddleware(
            name: "\(name) (conditional)",
            priority: priority,
            condition: condition,
            middleware: self
        )
    }
}

/// 组合中间件
public struct ComposedMiddleware: Middleware {
    public let name: String
    public let priority: Int
    private let first: any Middleware
    private let second: any Middleware

    init(first: any Middleware, second: any Middleware) {
        self.first = first
        self.second = second
        self.name = "\(first.name) -> \(second.name)"
        self.priority = min(first.priority, second.priority)
    }

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        let intermediate = try await first.handleOutgoing(data, context: context)
        return try await second.handleOutgoing(intermediate, context: context)
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        let intermediate = try await second.handleIncoming(data, context: context)
        return try await first.handleIncoming(intermediate, context: context)
    }

    public func onConnect(connection: any Connection) async {
        await first.onConnect(connection: connection)
        await second.onConnect(connection: connection)
    }

    public func onDisconnect(connection: any Connection, reason: DisconnectReason) async {
        await first.onDisconnect(connection: connection, reason: reason)
        await second.onDisconnect(connection: connection, reason: reason)
    }

    public func onError(error: Error, context: MiddlewareContext) async {
        await first.onError(error: error, context: context)
        await second.onError(error: error, context: context)
    }
}
