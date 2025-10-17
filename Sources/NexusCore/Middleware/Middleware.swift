//
//  Middleware.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Middleware Protocol

/// 中间件协议 - 处理消息的中间层
public protocol Middleware: Sendable {
    /// 中间件名称
    var name: String { get }

    /// 优先级（数字越小优先级越高）
    var priority: Int { get }

    /// 处理出站数据（发送前）
    /// - Parameters:
    ///   - data: 原始数据
    ///   - context: 中间件上下文
    /// - Returns: 处理后的数据
    /// - Throws: 处理失败时抛出错误
    func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data

    /// 处理入站数据（接收后）
    /// - Parameters:
    ///   - data: 原始数据
    ///   - context: 中间件上下文
    /// - Returns: 处理后的数据
    /// - Throws: 处理失败时抛出错误
    func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data

    /// 连接建立时调用
    /// - Parameter connection: 连接对象
    func onConnect(connection: any Connection) async

    /// 连接断开时调用
    /// - Parameters:
    ///   - connection: 连接对象
    ///   - reason: 断开原因
    func onDisconnect(connection: any Connection, reason: DisconnectReason) async

    /// 错误处理
    /// - Parameters:
    ///   - error: 错误
    ///   - context: 上下文
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
public struct MiddlewareContext: Sendable {
    /// 连接标识符
    public let connectionId: String

    /// 方向
    public let direction: Direction

    /// 数据大小
    public let dataSize: Int

    /// 时间戳
    public let timestamp: Date

    /// 元数据
    public var metadata: [String: String]

    public enum Direction: Sendable {
        case outgoing  // 发送
        case incoming  // 接收
    }

    public init(
        connectionId: String,
        direction: Direction,
        dataSize: Int,
        timestamp: Date = Date(),
        metadata: [String: String] = [:]
    ) {
        self.connectionId = connectionId
        self.direction = direction
        self.dataSize = dataSize
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
