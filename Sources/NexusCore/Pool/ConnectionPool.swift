//
//  ConnectionPool.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 连接池协议
///
/// 定义连接必须实现的基本接口。
public protocol PoolableConnection: Sendable {
    /// 验证连接是否可用
    func validate() async throws -> Bool
    
    /// 关闭连接
    func close() async throws
}

/// 连接池
///
/// 管理可复用的连接，支持连接获取、释放、健康检查等功能。
///
/// 使用示例:
/// ```swift
/// let pool = ConnectionPool<MyConnection>(
///     configuration: .default,
///     strategy: RoundRobinStrategy(),
///     connectionFactory: { MyConnection() }
/// )
///
/// // 获取连接
/// let conn = try await pool.acquire()
///
/// // 使用连接...
///
/// // 释放连接
/// await pool.release(conn)
/// ```
public actor ConnectionPool<T: PoolableConnection> {
    
    // MARK: - Properties
    
    /// 配置
    public let configuration: PoolConfiguration
    
    /// 分配策略
    private let strategy: any PoolStrategy
    
    /// 连接工厂
    private let connectionFactory: @Sendable () async throws -> T
    
    /// 所有连接
    private var connections: [PooledConnection<T>] = []
    
    /// 池状态
    private var state: PoolState = .active
    
    /// 健康检查任务
    private var healthCheckTask: Task<Void, Never>?
    
    /// 等待队列
    private var waitQueue: [CheckedContinuation<PooledConnection<T>, Error>] = []
    
    // MARK: - Statistics
    
    private var stats = Statistics()
    
    private struct Statistics {
        var totalAcquired: Int = 0
        var totalReleased: Int = 0
        var totalCreated: Int = 0
        var totalClosed: Int = 0
        var totalValidationFailures: Int = 0
    }
    
    // MARK: - Pool State
    
    private enum PoolState {
        case active
        case draining
        case closed
    }
    
    // MARK: - Initialization
    
    /// 初始化连接池
    /// - Parameters:
    ///   - configuration: 连接池配置
    ///   - strategy: 分配策略
    ///   - connectionFactory: 连接工厂闭包
    public init(
        configuration: PoolConfiguration = .default,
        strategy: any PoolStrategy = RoundRobinStrategy(),
        connectionFactory: @escaping @Sendable () async throws -> T
    ) throws {
        try configuration.validate()
        
        self.configuration = configuration
        self.strategy = strategy
        self.connectionFactory = connectionFactory
    }
    
    /// 启动连接池
    public func start() async throws {
        guard state == .active else {
            throw PoolError.poolClosed
        }
        
        // 创建最小连接数
        for _ in 0..<configuration.minConnections {
            try await createConnection()
        }
        
        // 启动健康检查
        if configuration.enableHealthCheck {
            startHealthCheck()
        }
    }
    
    // MARK: - Connection Management
    
    /// 获取连接
    /// - Returns: 池化连接
    /// - Throws: 如果超时或池已关闭
    public func acquire() async throws -> PooledConnection<T> {
        guard state == .active else {
            throw state == .draining ? PoolError.poolDraining : PoolError.poolClosed
        }
        
        stats.totalAcquired += 1
        
        // 尝试从现有连接中获取
        if let conn = try await tryAcquireExisting() {
            return conn
        }
        
        // 尝试创建新连接
        if connections.count < configuration.maxConnections {
            let conn = try await createConnection()
            conn.markAsAcquired()
            return conn
        }
        
        // 池已满
        if configuration.waitWhenPoolFull {
            return try await waitForConnection()
        } else {
            throw PoolError.poolExhausted
        }
    }
    
    /// 释放连接
    /// - Parameter connection: 要释放的连接
    public func release(_ connection: PooledConnection<T>) async {
        stats.totalReleased += 1
        
        // 验证连接（如果启用）
        if configuration.validateOnRelease {
            do {
                let isValid = try await connection.connection.validate()
                if !isValid {
                    await removeConnection(connection)
                    stats.totalValidationFailures += 1
                    return
                }
            } catch {
                await removeConnection(connection)
                stats.totalValidationFailures += 1
                return
            }
        }
        
        connection.markAsReleased()
        
        // 处理等待队列
        if let continuation = waitQueue.first {
            waitQueue.removeFirst()
            connection.markAsAcquired()
            continuation.resume(returning: connection)
        }
    }
    
    /// 排空连接池
    ///
    /// 停止接受新的连接请求，等待所有连接归还后关闭。
    public func drain() async {
        state = .draining
        
        // 停止健康检查
        healthCheckTask?.cancel()
        healthCheckTask = nil
        
        // 拒绝所有等待的请求
        for continuation in waitQueue {
            continuation.resume(throwing: PoolError.poolDraining)
        }
        waitQueue.removeAll()
        
        // 等待所有连接归还
        while connections.contains(where: { !$0.isAvailable }) {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        // 关闭所有连接
        await closeAllConnections()
        
        state = .closed
    }
    
    // MARK: - Query
    
    /// 活动连接数
    public var activeConnections: Int {
        connections.filter { !$0.isAvailable }.count
    }
    
    /// 空闲连接数
    public var idleConnections: Int {
        connections.filter { $0.isAvailable }.count
    }
    
    /// 总连接数
    public var totalConnections: Int {
        connections.count
    }
    
    /// 获取统计信息
    public func getStatistics() -> (
        totalAcquired: Int,
        totalReleased: Int,
        totalCreated: Int,
        totalClosed: Int,
        validationFailures: Int,
        activeConnections: Int,
        idleConnections: Int
    ) {
        (
            totalAcquired: stats.totalAcquired,
            totalReleased: stats.totalReleased,
            totalCreated: stats.totalCreated,
            totalClosed: stats.totalClosed,
            validationFailures: stats.totalValidationFailures,
            activeConnections: activeConnections,
            idleConnections: idleConnections
        )
    }
    
    // MARK: - Private Methods
    
    /// 尝试从现有连接中获取
    private func tryAcquireExisting() async throws -> PooledConnection<T>? {
        let availableConnections = connections.filter { $0.isAvailable }
        
        guard !availableConnections.isEmpty else {
            return nil
        }
        
        guard let index = strategy.selectConnection(from: availableConnections) else {
            return nil
        }
        
        let conn = availableConnections[index]
        
        // 验证连接（如果启用）
        if configuration.validateOnAcquire {
            let isValid = try await conn.connection.validate()
            if !isValid {
                await removeConnection(conn)
                stats.totalValidationFailures += 1
                return try await tryAcquireExisting() // 递归尝试下一个
            }
        }
        
        // 检查连接生命周期
        if configuration.maxConnectionLifetime > 0 &&
           conn.age > configuration.maxConnectionLifetime {
            await removeConnection(conn)
            return try await tryAcquireExisting() // 递归尝试下一个
        }
        
        conn.markAsAcquired()
        return conn
    }
    
    /// 等待连接可用
    private func waitForConnection() async throws -> PooledConnection<T> {
        return try await withCheckedThrowingContinuation { continuation in
            waitQueue.append(continuation)
            
            // 设置超时
            Task {
                try? await Task.sleep(nanoseconds: UInt64(configuration.acquireTimeout * 1_000_000_000))
                
                if let index = waitQueue.firstIndex(where: { $0 as AnyObject === continuation as AnyObject }) {
                    waitQueue.remove(at: index)
                    continuation.resume(throwing: PoolError.acquireTimeout)
                }
            }
        }
    }
    
    /// 创建新连接
    @discardableResult
    private func createConnection() async throws -> PooledConnection<T> {
        let connection = try await connectionFactory()
        let pooled = PooledConnection(connection: connection)
        connections.append(pooled)
        stats.totalCreated += 1
        return pooled
    }
    
    /// 移除连接
    private func removeConnection(_ connection: PooledConnection<T>) async {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections.remove(at: index)
        }
        
        do {
            try await connection.connection.close()
            stats.totalClosed += 1
        } catch {
            // 忽略关闭错误
        }
    }
    
    /// 关闭所有连接
    private func closeAllConnections() async {
        for conn in connections {
            do {
                try await conn.connection.close()
                stats.totalClosed += 1
            } catch {
                // 忽略关闭错误
            }
        }
        connections.removeAll()
    }
    
    // MARK: - Health Check
    
    /// 启动健康检查
    private func startHealthCheck() {
        healthCheckTask = Task {
            while !Task.isCancelled && state == .active {
                try? await Task.sleep(nanoseconds: UInt64(configuration.healthCheckInterval * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                await performHealthCheck()
            }
        }
    }
    
    /// 执行健康检查
    private func performHealthCheck() async {
        var toRemove: [PooledConnection<T>] = []
        
        for conn in connections where conn.isAvailable {
            // 检查空闲超时
            if conn.idleDuration > configuration.idleTimeout {
                toRemove.append(conn)
                continue
            }
            
            // 检查连接有效性
            do {
                let isValid = try await conn.connection.validate()
                if !isValid {
                    toRemove.append(conn)
                    stats.totalValidationFailures += 1
                }
            } catch {
                toRemove.append(conn)
                stats.totalValidationFailures += 1
            }
        }
        
        // 移除无效连接
        for conn in toRemove {
            await removeConnection(conn)
        }
        
        // 确保最小连接数
        while connections.count < configuration.minConnections {
            do {
                try await createConnection()
            } catch {
                break
            }
        }
    }
}

// MARK: - CustomStringConvertible

extension ConnectionPool: CustomStringConvertible {
    public nonisolated var description: String {
        "ConnectionPool<\(T.self)>"
    }
}
