//
//  CacheStorage.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Cache Entry

/// 缓存条目
public struct CacheEntry: Sendable {
    /// 缓存键
    public let key: String
    
    /// 缓存数据
    public let data: Data
    
    /// 数据大小（字节）
    public let size: Int
    
    /// 创建时间
    public let createdAt: Date
    
    /// 最后访问时间
    public var lastAccessedAt: Date
    
    /// 访问次数
    public var accessCount: Int
    
    /// 过期时间（可选）
    public var expiresAt: Date?
    
    /// 元数据
    public var metadata: [String: String]
    
    public init(
        key: String,
        data: Data,
        createdAt: Date = Date(),
        expiresAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.key = key
        self.data = data
        self.size = data.count
        self.createdAt = createdAt
        self.lastAccessedAt = createdAt
        self.accessCount = 0
        self.expiresAt = expiresAt
        self.metadata = metadata
    }
    
    /// 是否已过期
    public func isExpired(at date: Date = Date()) -> Bool {
        guard let expiresAt = expiresAt else { return false }
        return date >= expiresAt
    }
}

// MARK: - Cache Storage

/// 缓存存储 - 内存缓存实现
public actor CacheStorage {
    
    // MARK: - Properties
    
    /// 最大容量（项数）
    private let maxCount: Int
    
    /// 最大大小（字节）
    private let maxSize: Int64
    
    /// 缓存条目
    private var entries: [String: CacheEntry] = [:]
    
    /// 当前总大小
    private var currentSize: Int64 = 0
    
    /// 缓存策略
    private let strategy: CacheStrategy
    
    /// 统计信息
    private var stats: CacheMiddlewareStatistics
    
    // MARK: - Initialization
    
    public init(
        maxCount: Int = 100,
        maxSize: Int64 = 10 * 1024 * 1024, // 10 MB
        strategy: CacheStrategy
    ) {
        self.maxCount = maxCount
        self.maxSize = maxSize
        self.strategy = strategy
        self.stats = CacheMiddlewareStatistics()
    }
    
    // MARK: - Public Methods
    
    /// 获取缓存数据
    public func get(_ key: String) async -> Data? {
        guard var entry = entries[key] else {
            await stats.recordMiss()
            return nil
        }
        
        // 检查是否过期
        if entry.isExpired() {
            await remove(key)
            await stats.recordMiss()
            return nil
        }
        
        // 更新访问信息
        entry.lastAccessedAt = Date()
        entry.accessCount += 1
        entries[key] = entry
        
        // 通知策略
        await strategy.onAccess(key: key, timestamp: entry.lastAccessedAt)
        
        await stats.recordHit()
        return entry.data
    }
    
    /// 设置缓存数据
    public func set(_ key: String, data: Data, expiresAt: Date? = nil, metadata: [String: String] = [:]) async {
        // 如果键已存在，先删除
        if entries[key] != nil {
            await remove(key)
        }
        
        let entry = CacheEntry(key: key, data: data, expiresAt: expiresAt, metadata: metadata)
        
        // 检查是否需要驱逐
        while (entries.count >= maxCount || currentSize + Int64(entry.size) > maxSize),
              let keyToEvict = await strategy.selectKeyToEvict() {
            await remove(keyToEvict)
            await stats.recordEviction()
        }
        
        // 添加新条目
        entries[key] = entry
        currentSize += Int64(entry.size)
        
        // 通知策略
        await strategy.onAdd(key: key, size: entry.size, timestamp: entry.createdAt)
        
        await stats.recordSet()
    }
    
    /// 删除缓存
    public func remove(_ key: String) async {
        guard let entry = entries.removeValue(forKey: key) else { return }
        
        currentSize -= Int64(entry.size)
        await strategy.onRemove(key: key)
    }
    
    /// 检查键是否存在
    public func contains(_ key: String) async -> Bool {
        guard let entry = entries[key] else { return false }
        return !entry.isExpired()
    }
    
    /// 清空所有缓存
    public func removeAll() async {
        entries.removeAll()
        currentSize = 0
        await strategy.reset()
        stats = CacheMiddlewareStatistics()
    }
    
    /// 清理过期条目
    public func cleanupExpired() async -> Int {
        let now = Date()
        var removedCount = 0
        
        for (key, entry) in entries where entry.isExpired(at: now) {
            await remove(key)
            removedCount += 1
        }
        
        return removedCount
    }
    
    /// 获取所有键
    public func getAllKeys() -> [String] {
        Array(entries.keys)
    }
    
    /// 获取缓存条目数
    public func count() -> Int {
        entries.count
    }
    
    /// 获取当前大小
    public func size() -> Int64 {
        currentSize
    }
    
    /// 获取统计信息
    public func getStatistics() -> CacheMiddlewareStatistics {
        stats
    }
    
    /// 重置统计信息
    public func resetStatistics() {
        stats = CacheMiddlewareStatistics()
    }
}

// MARK: - Cache Statistics

/// 缓存统计信息
public struct CacheMiddlewareStatistics: Sendable {
    /// 命中次数
    public private(set) var hits: Int64 = 0
    
    /// 未命中次数
    public private(set) var misses: Int64 = 0
    
    /// 设置次数
    public private(set) var sets: Int64 = 0
    
    /// 驱逐次数
    public private(set) var evictions: Int64 = 0
    
    /// 命中率
    public var hitRate: Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }
    
    /// 未命中率
    public var missRate: Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(misses) / Double(total)
    }
    
    mutating func recordHit() {
        hits += 1
    }
    
    mutating func recordMiss() {
        misses += 1
    }
    
    mutating func recordSet() {
        sets += 1
    }
    
    mutating func recordEviction() {
        evictions += 1
    }
}

// MARK: - Multi-Level Cache Storage

/// 多级缓存存储
public actor MultiLevelCacheStorage {
    
    /// 缓存级别
    public enum CacheLevel: Int, Comparable {
        case l1 = 1
        case l2 = 2
        case l3 = 3
        
        public static func < (lhs: CacheLevel, rhs: CacheLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
    
    private var levels: [CacheLevel: CacheStorage] = [:]
    
    public init() {}
    
    /// 添加缓存级别
    public func addLevel(_ level: CacheLevel, storage: CacheStorage) {
        levels[level] = storage
    }
    
    /// 获取缓存数据（从 L1 开始查找）
    public func get(_ key: String) async -> Data? {
        let sortedLevels = levels.keys.sorted()
        
        for level in sortedLevels {
            guard let storage = levels[level] else { continue }
            
            if let data = await storage.get(key) {
                // 找到数据，提升到更高级别的缓存
                await promoteToHigherLevels(key: key, data: data, currentLevel: level)
                return data
            }
        }
        
        return nil
    }
    
    /// 设置缓存数据（写入所有级别）
    public func set(_ key: String, data: Data, expiresAt: Date? = nil, metadata: [String: String] = [:]) async {
        for (_, storage) in levels {
            await storage.set(key, data: data, expiresAt: expiresAt, metadata: metadata)
        }
    }
    
    /// 删除缓存（从所有级别）
    public func remove(_ key: String) async {
        for (_, storage) in levels {
            await storage.remove(key)
        }
    }
    
    /// 提升数据到更高级别的缓存
    private func promoteToHigherLevels(key: String, data: Data, currentLevel: CacheLevel) async {
        for (level, storage) in levels where level < currentLevel {
            await storage.set(key, data: data)
        }
    }
    
    /// 获取所有级别的统计信息
    public func getAllStatistics() async -> [CacheLevel: CacheMiddlewareStatistics] {
        var stats: [CacheLevel: CacheMiddlewareStatistics] = [:]
        for (level, storage) in levels {
            stats[level] = await storage.getStatistics()
        }
        return stats
    }
}
