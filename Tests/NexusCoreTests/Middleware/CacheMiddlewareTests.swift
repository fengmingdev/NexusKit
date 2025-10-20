//
//  CacheMiddlewareTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore

final class CacheMiddlewareTests: XCTestCase {
    
    // MARK: - Cache Configuration Tests
    
    func testCacheConfigurationDefaults() {
        let config = CacheConfiguration()
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.maxCount, 100)
        XCTAssertEqual(config.maxSize, 10 * 1024 * 1024)
        XCTAssertEqual(config.defaultTTL, 60)
        XCTAssertEqual(config.strategyType, .lru)
    }
    
    func testCacheConfigurationPresets() {
        // Development
        let dev = CacheConfiguration.development
        XCTAssertEqual(dev.maxCount, 50)
        XCTAssertEqual(dev.defaultTTL, 30)
        
        // Production
        let prod = CacheConfiguration.production
        XCTAssertEqual(prod.maxCount, 1000)
        XCTAssertEqual(prod.defaultTTL, 600)
        
        // High Performance
        let hp = CacheConfiguration.highPerformance
        XCTAssertEqual(hp.maxCount, 5000)
        XCTAssertEqual(hp.strategyType, .lfu)
    }
    
    // MARK: - Cache Storage Tests
    
    func testCacheStorageBasicOperations() async {
        let strategy = LRUCacheStrategy()
        let storage = CacheStorage(maxCount: 10, maxSize: 1024, strategy: strategy)
        
        let testData = "Hello Cache".data(using: .utf8)!
        
        // 初始应该为空
        let result1 = await storage.get("key1")
        XCTAssertNil(result1)
        
        // 设置缓存
        await storage.set("key1", data: testData)
        
        // 应该能获取
        let result2 = await storage.get("key1")
        XCTAssertEqual(result2, testData)
        
        // 删除缓存
        await storage.remove("key1")
        let result3 = await storage.get("key1")
        XCTAssertNil(result3)
    }
    
    func testCacheStorageTTL() async {
        let strategy = TTLCacheStrategy(ttl: 1)
        let storage = CacheStorage(maxCount: 10, maxSize: 1024, strategy: strategy)
        
        let testData = "TTL Test".data(using: .utf8)!
        let expiresAt = Date().addingTimeInterval(0.5) // 0.5秒后过期
        
        await storage.set("key1", data: testData, expiresAt: expiresAt)
        
        // 立即获取应该成功
        let result1 = await storage.get("key1")
        XCTAssertNotNil(result1)
        
        // 等待过期
        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6秒
        
        // 应该已过期
        let result2 = await storage.get("key1")
        XCTAssertNil(result2)
    }
    
    func testCacheStorageMaxCount() async {
        let strategy = LRUCacheStrategy()
        let storage = CacheStorage(maxCount: 3, maxSize: 10000, strategy: strategy)
        
        let testData = "Test".data(using: .utf8)!
        
        // 添加3个条目
        await storage.set("key1", data: testData)
        await storage.set("key2", data: testData)
        await storage.set("key3", data: testData)
        
        let count1 = await storage.count()
        XCTAssertEqual(count1, 3)
        
        // 添加第4个应该驱逐最旧的
        await storage.set("key4", data: testData)
        
        let count2 = await storage.count()
        XCTAssertEqual(count2, 3)
        
        // key1应该被驱逐
        let result = await storage.get("key1")
        XCTAssertNil(result)
    }
    
    func testCacheStorageMaxSize() async {
        let strategy = SizeBasedCacheStrategy()
        let storage = CacheStorage(maxCount: 100, maxSize: 100, strategy: strategy)
        
        let largeData = Data(count: 60) // 60字节
        
        await storage.set("key1", data: largeData)
        
        let size1 = await storage.size()
        XCTAssertEqual(size1, 60)
        
        // 添加第二个会超过限制
        await storage.set("key2", data: largeData)
        
        // 应该驱逐了第一个
        let size2 = await storage.size()
        XCTAssertLessThanOrEqual(size2, 100)
    }
    
    func testCacheStorageStatistics() async {
        let strategy = LRUCacheStrategy()
        let storage = CacheStorage(maxCount: 10, maxSize: 1024, strategy: strategy)
        
        let testData = "Stats Test".data(using: .utf8)!
        
        // 未命中
        _ = await storage.get("missing")
        
        var stats = await storage.getStatistics()
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.hits, 0)
        
        // 命中
        await storage.set("key1", data: testData)
        _ = await storage.get("key1")
        
        stats = await storage.getStatistics()
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.sets, 1)
        
        // 命中率
        XCTAssertEqual(stats.hitRate, 0.5) // 1 hit, 1 miss
    }
    
    func testCacheStorageCleanup() async {
        let strategy = TTLCacheStrategy(ttl: 1)
        let storage = CacheStorage(maxCount: 10, maxSize: 1024, strategy: strategy)
        
        let testData = "Cleanup Test".data(using: .utf8)!
        let expiresAt = Date().addingTimeInterval(0.3)
        
        await storage.set("key1", data: testData, expiresAt: expiresAt)
        await storage.set("key2", data: testData, expiresAt: expiresAt)
        await storage.set("key3", data: testData)
        
        let count1 = await storage.count()
        XCTAssertEqual(count1, 3)
        
        // 等待过期
        try? await Task.sleep(nanoseconds: 400_000_000)
        
        // 清理过期项
        let removed = await storage.cleanupExpired()
        XCTAssertEqual(removed, 2)
        
        let count2 = await storage.count()
        XCTAssertEqual(count2, 1)
    }
    
    // MARK: - Cache Strategy Tests
    
    func testLRUStrategy() async {
        let strategy = LRUCacheStrategy()
        
        await strategy.onAdd(key: "key1", size: 10, timestamp: Date())
        await strategy.onAdd(key: "key2", size: 10, timestamp: Date())
        await strategy.onAdd(key: "key3", size: 10, timestamp: Date())
        
        // 访问 key1
        await strategy.onAccess(key: "key1", timestamp: Date())
        
        // 应该驱逐 key2（最久未访问）
        let toEvict = await strategy.selectKeyToEvict()
        XCTAssertEqual(toEvict, "key2")
    }
    
    func testLFUStrategy() async {
        let strategy = LFUCacheStrategy()
        
        await strategy.onAdd(key: "key1", size: 10, timestamp: Date())
        await strategy.onAdd(key: "key2", size: 10, timestamp: Date())
        await strategy.onAdd(key: "key3", size: 10, timestamp: Date())
        
        // key1访问2次
        await strategy.onAccess(key: "key1", timestamp: Date())
        await strategy.onAccess(key: "key1", timestamp: Date())
        
        // key2访问1次
        await strategy.onAccess(key: "key2", timestamp: Date())
        
        // 应该驱逐 key3（频率最低）
        let toEvict = await strategy.selectKeyToEvict()
        XCTAssertEqual(toEvict, "key3")
    }
    
    func testFIFOStrategy() async {
        let strategy = FIFOCacheStrategy()
        
        await strategy.onAdd(key: "key1", size: 10, timestamp: Date())
        try? await Task.sleep(nanoseconds: 10_000_000)
        await strategy.onAdd(key: "key2", size: 10, timestamp: Date())
        try? await Task.sleep(nanoseconds: 10_000_000)
        await strategy.onAdd(key: "key3", size: 10, timestamp: Date())
        
        // 应该驱逐 key1（最先添加）
        let toEvict = await strategy.selectKeyToEvict()
        XCTAssertEqual(toEvict, "key1")
    }
    
    func testTTLStrategy() async {
        let strategy = TTLCacheStrategy(ttl: 1)
        
        let now = Date()
        await strategy.onAdd(key: "key1", size: 10, timestamp: now.addingTimeInterval(-2))
        await strategy.onAdd(key: "key2", size: 10, timestamp: now.addingTimeInterval(-0.5))
        await strategy.onAdd(key: "key3", size: 10, timestamp: now)
        
        // 应该驱逐 key1（最早添加，已过期）
        let toEvict = await strategy.selectKeyToEvict()
        XCTAssertEqual(toEvict, "key1")
    }
    
    func testSizeBasedStrategy() async {
        let strategy = SizeBasedCacheStrategy()
        
        await strategy.onAdd(key: "key1", size: 100, timestamp: Date())
        await strategy.onAdd(key: "key2", size: 50, timestamp: Date())
        await strategy.onAdd(key: "key3", size: 200, timestamp: Date())
        
        // 应该驱逐 key3（最大）
        let toEvict = await strategy.selectKeyToEvict()
        XCTAssertEqual(toEvict, "key3")
    }
    
    // MARK: - Multi-Level Cache Tests
    
    func testMultiLevelCacheBasicOperations() async {
        let multiLevel = MultiLevelCacheStorage()
        
        let l1Strategy = LRUCacheStrategy()
        let l1 = CacheStorage(maxCount: 5, maxSize: 1024, strategy: l1Strategy)
        
        let l2Strategy = LRUCacheStrategy()
        let l2 = CacheStorage(maxCount: 10, maxSize: 2048, strategy: l2Strategy)
        
        await multiLevel.addLevel(.l1, storage: l1)
        await multiLevel.addLevel(.l2, storage: l2)
        
        let testData = "Multi-Level Test".data(using: .utf8)!
        
        // 设置数据
        await multiLevel.set("key1", data: testData)
        
        // 应该能从L1获取
        let result1 = await multiLevel.get("key1")
        XCTAssertEqual(result1, testData)
        
        // 删除
        await multiLevel.remove("key1")
        let result2 = await multiLevel.get("key1")
        XCTAssertNil(result2)
    }
    
    func testMultiLevelCachePromotion() async {
        let multiLevel = MultiLevelCacheStorage()
        
        let l1Strategy = LRUCacheStrategy()
        let l1 = CacheStorage(maxCount: 5, maxSize: 1024, strategy: l1Strategy)
        
        let l2Strategy = LRUCacheStrategy()
        let l2 = CacheStorage(maxCount: 10, maxSize: 2048, strategy: l2Strategy)
        
        await multiLevel.addLevel(.l1, storage: l1)
        await multiLevel.addLevel(.l2, storage: l2)
        
        let testData = "Promotion Test".data(using: .utf8)!
        
        // 直接设置到L2
        await l2.set("key1", data: testData)
        
        // 从多级缓存获取，应该提升到L1
        let result = await multiLevel.get("key1")
        XCTAssertEqual(result, testData)
        
        // 验证L1现在有这个数据
        let l1Result = await l1.get("key1")
        XCTAssertNotNil(l1Result)
    }
    
    func testMultiLevelCacheStatistics() async {
        let multiLevel = MultiLevelCacheStorage()
        
        let l1Strategy = LRUCacheStrategy()
        let l1 = CacheStorage(maxCount: 5, maxSize: 1024, strategy: l1Strategy)
        
        let l2Strategy = LRUCacheStrategy()
        let l2 = CacheStorage(maxCount: 10, maxSize: 2048, strategy: l2Strategy)
        
        await multiLevel.addLevel(.l1, storage: l1)
        await multiLevel.addLevel(.l2, storage: l2)
        
        let testData = "Stats Test".data(using: .utf8)!
        await multiLevel.set("key1", data: testData)
        
        let stats = await multiLevel.getAllStatistics()
        XCTAssertEqual(stats.count, 2)
        XCTAssertNotNil(stats[.l1])
        XCTAssertNotNil(stats[.l2])
    }
    
    // MARK: - Cache Middleware Tests
    
    func testCacheMiddlewareBasicFlow() async {
        let config = CacheConfiguration(maxCount: 10, defaultTTL: 60)
        let middleware = await CacheMiddleware(configuration: config)
        
        let testData = "Middleware Test".data(using: .utf8)!
        let context = MiddlewareContext(
            connectionId: "conn-1",
            endpoint: .tcp(host: "localhost", port: 8080)
        )
        
        // 第一次处理 - 应该缓存
        let result1 = try? await middleware.handleIncoming(testData, context: context)
        XCTAssertEqual(result1, testData)
        
        // 第二次处理 - 应该从缓存获取
        let result2 = try? await middleware.handleIncoming(testData, context: context)
        XCTAssertEqual(result2, testData)
        
        let stats = await middleware.getStatistics()
        XCTAssertGreaterThan(stats.hits, 0)
    }
    
    func testCacheMiddlewareDisabled() async {
        let config = CacheConfiguration(enabled: false)
        let middleware = await CacheMiddleware(configuration: config)
        
        let testData = "Disabled Test".data(using: .utf8)!
        let context = MiddlewareContext(
            connectionId: "conn-1",
            endpoint: .tcp(host: "localhost", port: 8080)
        )
        
        let result = try? await middleware.handleIncoming(testData, context: context)
        XCTAssertEqual(result, testData)
        
        // 应该没有缓存
        let count = await middleware.getCacheCount()
        XCTAssertEqual(count, 0)
    }
    
    func testCacheMiddlewareClearAll() async {
        let config = CacheConfiguration(maxCount: 10)
        let middleware = await CacheMiddleware(configuration: config)
        
        let testData = "Clear Test".data(using: .utf8)!
        let context = MiddlewareContext(
            connectionId: "conn-1",
            endpoint: .tcp(host: "localhost", port: 8080)
        )
        
        _ = try? await middleware.handleIncoming(testData, context: context)
        
        let count1 = await middleware.getCacheCount()
        XCTAssertGreaterThan(count1, 0)
        
        // 清空缓存
        await middleware.clearAll()
        
        let count2 = await middleware.getCacheCount()
        XCTAssertEqual(count2, 0)
    }
    
    func testCacheMiddlewareStatistics() async {
        let config = CacheConfiguration.development
        let middleware = await CacheMiddleware(configuration: config)
        
        let testData = "Stats Test".data(using: .utf8)!
        let context = MiddlewareContext(
            connectionId: "conn-1",
            endpoint: .tcp(host: "localhost", port: 8080)
        )
        
        // 处理一些数据
        _ = try? await middleware.handleIncoming(testData, context: context)
        _ = try? await middleware.handleIncoming(testData, context: context)
        
        let stats = await middleware.getStatistics()
        XCTAssertGreaterThan(stats.hits + stats.misses, 0)
        XCTAssertGreaterThanOrEqual(stats.hitRate, 0)
        XCTAssertLessThanOrEqual(stats.hitRate, 1)
    }
    
    // MARK: - Cache Key Generator Tests
    
    func testCacheKeyGeneratorFromData() {
        let data1 = "Test Data".data(using: .utf8)!
        let data2 = "Test Data".data(using: .utf8)!
        let data3 = "Different Data".data(using: .utf8)!
        
        let key1 = CacheKeyGenerator.generate(from: data1)
        let key2 = CacheKeyGenerator.generate(from: data2)
        let key3 = CacheKeyGenerator.generate(from: data3)
        
        // 相同数据应该生成相同的键
        XCTAssertEqual(key1, key2)
        // 不同数据应该生成不同的键
        XCTAssertNotEqual(key1, key3)
    }
    
    func testCacheKeyGeneratorFromString() {
        let key1 = CacheKeyGenerator.generate(from: "test")
        let key2 = CacheKeyGenerator.generate(from: "test")
        let key3 = CacheKeyGenerator.generate(from: "different")
        
        XCTAssertEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
    }
    
    func testCacheKeyGeneratorWithSalt() {
        let data = "Test".data(using: .utf8)!
        let key1 = CacheKeyGenerator.generate(from: data, salt: "salt1")
        let key2 = CacheKeyGenerator.generate(from: data, salt: "salt2")
        
        // 不同的盐应该生成不同的键
        XCTAssertNotEqual(key1, key2)
    }
    
    func testCacheKeyGeneratorFromComponents() {
        let key1 = CacheKeyGenerator.generate(components: ["user", "123", "profile"])
        let key2 = CacheKeyGenerator.generate(components: ["user", "123", "profile"])
        let key3 = CacheKeyGenerator.generate(components: ["user", "456", "profile"])
        
        XCTAssertEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
    }
}
