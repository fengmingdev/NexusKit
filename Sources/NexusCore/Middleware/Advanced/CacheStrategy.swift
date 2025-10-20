//
//  CacheStrategy.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Cache Strategy Protocol

/// 缓存策略协议
public protocol CacheStrategy: Sendable {
    /// 策略名称
    var name: String { get }
    
    /// 当访问缓存项时调用
    func onAccess(key: String, timestamp: Date) async
    
    /// 当添加缓存项时调用
    func onAdd(key: String, size: Int, timestamp: Date) async
    
    /// 当移除缓存项时调用
    func onRemove(key: String) async
    
    /// 选择要驱逐的缓存键
    func selectKeyToEvict() async -> String?
    
    /// 重置策略状态
    func reset() async
}

// MARK: - LRU Strategy

/// LRU (Least Recently Used) 缓存策略
public actor LRUCacheStrategy: CacheStrategy {
    public let name = "LRU"
    
    private var accessOrder: [String] = []
    private var accessTimes: [String: Date] = [:]
    
    public init() {}
    
    public func onAccess(key: String, timestamp: Date) {
        // 移除旧位置
        accessOrder.removeAll { $0 == key }
        // 添加到末尾（最近使用）
        accessOrder.append(key)
        accessTimes[key] = timestamp
    }
    
    public func onAdd(key: String, size: Int, timestamp: Date) {
        accessOrder.append(key)
        accessTimes[key] = timestamp
    }
    
    public func onRemove(key: String) {
        accessOrder.removeAll { $0 == key }
        accessTimes.removeValue(forKey: key)
    }
    
    public func selectKeyToEvict() -> String? {
        // 返回最久未使用的（队列头部）
        accessOrder.first
    }
    
    public func reset() {
        accessOrder.removeAll()
        accessTimes.removeAll()
    }
}

// MARK: - LFU Strategy

/// LFU (Least Frequently Used) 缓存策略
public actor LFUCacheStrategy: CacheStrategy {
    public let name = "LFU"
    
    private var frequencies: [String: Int] = [:]
    private var addTimes: [String: Date] = [:]
    
    public init() {}
    
    public func onAccess(key: String, timestamp: Date) {
        frequencies[key, default: 0] += 1
    }
    
    public func onAdd(key: String, size: Int, timestamp: Date) {
        frequencies[key] = 1
        addTimes[key] = timestamp
    }
    
    public func onRemove(key: String) {
        frequencies.removeValue(forKey: key)
        addTimes.removeValue(forKey: key)
    }
    
    public func selectKeyToEvict() -> String? {
        // 返回访问次数最少的，如果相同则返回最早添加的
        guard !frequencies.isEmpty else { return nil }
        
        let minFreq = frequencies.values.min() ?? 0
        let candidates = frequencies.filter { $0.value == minFreq }.map(\.key)
        
        if candidates.count == 1 {
            return candidates.first
        }
        
        // 多个候选，选择最早添加的
        return candidates.min { key1, key2 in
            (addTimes[key1] ?? Date.distantFuture) < (addTimes[key2] ?? Date.distantFuture)
        }
    }
    
    public func reset() {
        frequencies.removeAll()
        addTimes.removeAll()
    }
}

// MARK: - FIFO Strategy

/// FIFO (First In First Out) 缓存策略
public actor FIFOCacheStrategy: CacheStrategy {
    public let name = "FIFO"
    
    private var insertionOrder: [String] = []
    
    public init() {}
    
    public func onAccess(key: String, timestamp: Date) {
        // FIFO 不关心访问顺序
    }
    
    public func onAdd(key: String, size: Int, timestamp: Date) {
        insertionOrder.append(key)
    }
    
    public func onRemove(key: String) {
        insertionOrder.removeAll { $0 == key }
    }
    
    public func selectKeyToEvict() -> String? {
        // 返回最先插入的（队列头部）
        insertionOrder.first
    }
    
    public func reset() {
        insertionOrder.removeAll()
    }
}

// MARK: - TTL Strategy

/// TTL (Time To Live) 缓存策略
public actor TTLCacheStrategy: CacheStrategy {
    public let name = "TTL"
    
    private var expirationTimes: [String: Date] = [:]
    private let ttl: TimeInterval
    
    public init(ttl: TimeInterval = 60) {
        self.ttl = ttl
    }
    
    public func onAccess(key: String, timestamp: Date) {
        // 更新过期时间
        expirationTimes[key] = timestamp.addingTimeInterval(ttl)
    }
    
    public func onAdd(key: String, size: Int, timestamp: Date) {
        expirationTimes[key] = timestamp.addingTimeInterval(ttl)
    }
    
    public func onRemove(key: String) {
        expirationTimes.removeValue(forKey: key)
    }
    
    public func selectKeyToEvict() -> String? {
        let now = Date()
        
        // 返回已过期的键，或者最早过期的
        let expired = expirationTimes.filter { $0.value < now }
        if !expired.isEmpty {
            return expired.first?.key
        }
        
        // 返回最早过期的
        return expirationTimes.min { $0.value < $1.value }?.key
    }
    
    /// 获取已过期的所有键
    public func getExpiredKeys() -> [String] {
        let now = Date()
        return expirationTimes.filter { $0.value < now }.map(\.key)
    }
    
    public func reset() {
        expirationTimes.removeAll()
    }
}

// MARK: - Size-Based Strategy

/// 基于大小的缓存策略
public actor SizeBasedCacheStrategy: CacheStrategy {
    public let name = "SizeBased"
    
    private var sizes: [String: Int] = [:]
    
    public init() {}
    
    public func onAccess(key: String, timestamp: Date) {
        // 不影响大小
    }
    
    public func onAdd(key: String, size: Int, timestamp: Date) {
        sizes[key] = size
    }
    
    public func onRemove(key: String) {
        sizes.removeValue(forKey: key)
    }
    
    public func selectKeyToEvict() -> String? {
        // 返回占用空间最大的
        sizes.max { $0.value < $1.value }?.key
    }
    
    public func reset() {
        sizes.removeAll()
    }
}

// MARK: - Composite Strategy

/// 组合策略 - 结合多个策略
public actor CompositeCacheStrategy: CacheStrategy {
    public let name: String
    
    private let strategies: [CacheStrategy]
    private let weights: [Double]
    
    public init(strategies: [CacheStrategy], weights: [Double]? = nil) {
        self.name = "Composite(\(strategies.map(\.name).joined(separator: "+")))"
        self.strategies = strategies
        
        if let weights = weights {
            self.weights = weights
        } else {
            // 默认均等权重
            self.weights = Array(repeating: 1.0 / Double(strategies.count), count: strategies.count)
        }
    }
    
    public func onAccess(key: String, timestamp: Date) {
        Task {
            for strategy in strategies {
                await strategy.onAccess(key: key, timestamp: timestamp)
            }
        }
    }
    
    public func onAdd(key: String, size: Int, timestamp: Date) {
        Task {
            for strategy in strategies {
                await strategy.onAdd(key: key, size: size, timestamp: timestamp)
            }
        }
    }
    
    public func onRemove(key: String) {
        Task {
            for strategy in strategies {
                await strategy.onRemove(key: key)
            }
        }
    }
    
    public func selectKeyToEvict() -> String? {
        // 简化实现：使用第一个策略
        // 实际可以实现投票机制
        Task {
            await strategies.first?.selectKeyToEvict()
        }
        return nil
    }
    
    public func reset() {
        Task {
            for strategy in strategies {
                await strategy.reset()
            }
        }
    }
}
