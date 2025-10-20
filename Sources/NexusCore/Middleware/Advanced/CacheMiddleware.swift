//
//  CacheMiddleware.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Cache Configuration

/// 缓存配置
public struct CacheConfiguration: Sendable {
    /// 是否启用缓存
    public let enabled: Bool
    
    /// 最大缓存项数
    public let maxCount: Int
    
    /// 最大缓存大小（字节）
    public let maxSize: Int64
    
    /// 默认 TTL（秒）
    public let defaultTTL: TimeInterval?
    
    /// 缓存策略类型
    public let strategyType: StrategyType
    
    /// 是否缓存错误响应
    public let cacheErrors: Bool
    
    /// 清理间隔（秒）
    public let cleanupInterval: TimeInterval
    
    public enum StrategyType: String, Sendable {
        case lru
        case lfu
        case fifo
        case ttl
        case sizeBased
    }
    
    public init(
        enabled: Bool = true,
        maxCount: Int = 100,
        maxSize: Int64 = 10 * 1024 * 1024,
        defaultTTL: TimeInterval? = 60,
        strategyType: StrategyType = .lru,
        cacheErrors: Bool = false,
        cleanupInterval: TimeInterval = 300
    ) {
        self.enabled = enabled
        self.maxCount = maxCount
        self.maxSize = maxSize
        self.defaultTTL = defaultTTL
        self.strategyType = strategyType
        self.cacheErrors = cacheErrors
        self.cleanupInterval = cleanupInterval
    }
    
    /// 开发环境配置
    public static let development = CacheConfiguration(
        maxCount: 50,
        maxSize: 5 * 1024 * 1024,
        defaultTTL: 30,
        strategyType: .lru
    )
    
    /// 生产环境配置
    public static let production = CacheConfiguration(
        maxCount: 1000,
        maxSize: 100 * 1024 * 1024,
        defaultTTL: 600,
        strategyType: .lru
    )
    
    /// 高性能配置
    public static let highPerformance = CacheConfiguration(
        maxCount: 5000,
        maxSize: 500 * 1024 * 1024,
        defaultTTL: 3600,
        strategyType: .lfu
    )
}

// MARK: - Cache Middleware

/// 缓存中间件
public actor CacheMiddleware: Middleware {
    
    public let name = "CacheMiddleware"
    public let priority = 50
    
    private let configuration: CacheConfiguration
    private let storage: CacheStorage
    private var cleanupTask: Task<Void, Never>?
    
    public init(configuration: CacheConfiguration = .production) async {
        self.configuration = configuration
        
        // 创建缓存策略
        let strategy: CacheStrategy
        switch configuration.strategyType {
        case .lru:
            strategy = LRUCacheStrategy()
        case .lfu:
            strategy = LFUCacheStrategy()
        case .fifo:
            strategy = FIFOCacheStrategy()
        case .ttl:
            strategy = TTLCacheStrategy(ttl: configuration.defaultTTL ?? 60)
        case .sizeBased:
            strategy = SizeBasedCacheStrategy()
        }
        
        self.storage = CacheStorage(
            maxCount: configuration.maxCount,
            maxSize: configuration.maxSize,
            strategy: strategy
        )
        
        // 启动定期清理任务
        if configuration.enabled {
            startCleanupTask()
        }
    }
    
    // MARK: - Middleware Protocol
    
    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        // 发送时不缓存
        return data
    }
    
    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard configuration.enabled else { return data }
        
        // 生成缓存键
        let cacheKey = generateCacheKey(from: context)
        
        // 检查缓存
        if let cachedData = await storage.get(cacheKey) {
            return cachedData
        }
        
        // 缓存新数据
        let expiresAt = configuration.defaultTTL.map { Date().addingTimeInterval($0) }
        await storage.set(cacheKey, data: data, expiresAt: expiresAt)
        
        return data
    }
    
    // MARK: - Cache Management
    
    /// 清除所有缓存
    public func clearAll() async {
        await storage.removeAll()
    }
    
    /// 获取缓存统计
    public func getStatistics() async -> CacheMiddlewareStatistics {
        await storage.getStatistics()
    }
    
    /// 手动触发清理
    public func cleanup() async {
        _ = await storage.cleanupExpired()
    }
    
    /// 获取缓存项数量
    public func getCacheCount() async -> Int {
        await storage.count()
    }
    
    /// 获取缓存大小
    public func getCacheSize() async -> Int64 {
        await storage.size()
    }
    
    // MARK: - Private Methods
    
    private func generateCacheKey(from context: MiddlewareContext) -> String {
        // 基于连接ID和时间戳生成缓存键
        return "\(context.connectionId)_\(context.timestamp.timeIntervalSince1970)"
    }
    
    private func startCleanupTask() {
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(configuration.cleanupInterval * 1_000_000_000))
                _ = await storage.cleanupExpired()
            }
        }
    }
    
    deinit {
        cleanupTask?.cancel()
    }
}

// MARK: - Cache Key Generator

/// 缓存键生成器
public struct CacheKeyGenerator: Sendable {
    
    /// 从数据生成键
    public static func generate(from data: Data, salt: String = "") -> String {
        var hasher = Hasher()
        hasher.combine(data)
        hasher.combine(salt)
        return String(hasher.finalize())
    }
    
    /// 从字符串生成键
    public static func generate(from string: String, salt: String = "") -> String {
        var hasher = Hasher()
        hasher.combine(string)
        hasher.combine(salt)
        return String(hasher.finalize())
    }
    
    /// 从多个参数生成键
    public static func generate(components: [String]) -> String {
        var hasher = Hasher()
        for component in components {
            hasher.combine(component)
        }
        return String(hasher.finalize())
    }
}

// MARK: - Cache Eviction Policy

/// 缓存驱逐策略
public enum CacheEvictionPolicy: Sendable {
    /// 不驱逐
    case none
    
    /// LRU - 最近最少使用
    case lru
    
    /// LFU - 最不经常使用
    case lfu
    
    /// FIFO - 先进先出
    case fifo
    
    /// TTL - 基于时间
    case ttl(TimeInterval)
    
    /// 基于大小
    case size
    
    /// 自定义策略
    case custom(CacheStrategy)
}
