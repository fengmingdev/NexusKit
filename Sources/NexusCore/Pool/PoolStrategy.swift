//
//  PoolStrategy.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 连接池分配策略
///
/// 定义从连接池中选择连接的策略。
public protocol PoolStrategy: Sendable {
    
    /// 从可用连接中选择一个
    /// - Parameter connections: 可用的连接列表
    /// - Returns: 选中的连接索引，如果没有合适的连接返回 nil
    func selectConnection<T>(from connections: [PooledConnection<T>]) -> Int?
}

// MARK: - Round Robin Strategy

/// 轮询策略
///
/// 按顺序依次选择连接。
public struct RoundRobinStrategy: PoolStrategy {
    
    private let counter: ThreadSafeCounter
    
    public init() {
        self.counter = ThreadSafeCounter()
    }
    
    public func selectConnection<T>(from connections: [PooledConnection<T>]) -> Int? {
        guard !connections.isEmpty else { return nil }
        
        let index = counter.increment() % connections.count
        return index
    }
}

// MARK: - Least Connections Strategy

/// 最少连接策略
///
/// 选择当前使用次数最少的连接。
public struct LeastConnectionsStrategy: PoolStrategy {
    
    public init() {}
    
    public func selectConnection<T>(from connections: [PooledConnection<T>]) -> Int? {
        guard !connections.isEmpty else { return nil }
        
        var minIndex = 0
        var minUsage = connections[0].usageCount
        
        for (index, conn) in connections.enumerated() {
            if conn.usageCount < minUsage {
                minUsage = conn.usageCount
                minIndex = index
            }
        }
        
        return minIndex
    }
}

// MARK: - Random Strategy

/// 随机策略
///
/// 随机选择一个可用连接。
public struct RandomStrategy: PoolStrategy {
    
    public init() {}
    
    public func selectConnection<T>(from connections: [PooledConnection<T>]) -> Int? {
        guard !connections.isEmpty else { return nil }
        
        return Int.random(in: 0..<connections.count)
    }
}

// MARK: - Least Recently Used Strategy

/// 最近最少使用策略
///
/// 选择最久未使用的连接。
public struct LeastRecentlyUsedStrategy: PoolStrategy {
    
    public init() {}
    
    public func selectConnection<T>(from connections: [PooledConnection<T>]) -> Int? {
        guard !connections.isEmpty else { return nil }
        
        var oldestIndex = 0
        var oldestTime = connections[0].lastUsedTime
        
        for (index, conn) in connections.enumerated() {
            if conn.lastUsedTime < oldestTime {
                oldestTime = conn.lastUsedTime
                oldestIndex = index
            }
        }
        
        return oldestIndex
    }
}

// MARK: - Thread-Safe Counter

/// 线程安全计数器
private final class ThreadSafeCounter: @unchecked Sendable {
    private var value: Int = 0
    private let lock = NSLock()
    
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

// MARK: - Pooled Connection

/// 池化连接
///
/// 包装连接并添加池化元数据。
public final class PooledConnection<T>: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// 底层连接
    public let connection: T
    
    /// 连接 ID
    public let id: String
    
    /// 创建时间
    public let createdAt: Date
    
    /// 最后使用时间
    public private(set) var lastUsedTime: Date
    
    /// 使用次数
    public private(set) var usageCount: Int
    
    /// 是否可用
    public var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAvailable
    }
    
    private var _isAvailable: Bool
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    /// 初始化池化连接
    public init(connection: T, id: String = UUID().uuidString) {
        self.connection = connection
        self.id = id
        self.createdAt = Date()
        self.lastUsedTime = Date()
        self.usageCount = 0
        self._isAvailable = true
    }
    
    // MARK: - Methods
    
    /// 标记为使用中
    public func markAsAcquired() {
        lock.lock()
        defer { lock.unlock() }
        _isAvailable = false
        usageCount += 1
        lastUsedTime = Date()
    }
    
    /// 标记为可用
    public func markAsReleased() {
        lock.lock()
        defer { lock.unlock() }
        _isAvailable = true
        lastUsedTime = Date()
    }
    
    /// 获取连接年龄（秒）
    public var age: TimeInterval {
        Date().timeIntervalSince(createdAt)
    }
    
    /// 获取空闲时长（秒）
    public var idleDuration: TimeInterval {
        Date().timeIntervalSince(lastUsedTime)
    }
}
