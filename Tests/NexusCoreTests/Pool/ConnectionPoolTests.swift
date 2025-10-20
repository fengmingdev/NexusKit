//
//  ConnectionPoolTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusCore

final class ConnectionPoolTests: XCTestCase {
    
    // MARK: - Test Configuration
    
    func testDefaultConfiguration() async throws {
        let config = PoolConfiguration.default
        
        XCTAssertEqual(config.minConnections, 1)
        XCTAssertEqual(config.maxConnections, 10)
        XCTAssertTrue(config.enableHealthCheck)
        
        XCTAssertNoThrow(try config.validate())
    }
    
    func testPresetConfigurations() async throws {
        let small = PoolConfiguration.small
        XCTAssertEqual(small.maxConnections, 5)
        
        let medium = PoolConfiguration.medium
        XCTAssertEqual(medium.maxConnections, 20)
        
        let large = PoolConfiguration.large
        XCTAssertEqual(large.maxConnections, 50)
    }
    
    func testInvalidConfiguration() async throws {
        // minConnections > maxConnections
        let config1 = PoolConfiguration(minConnections: 10, maxConnections: 5)
        XCTAssertThrowsError(try config1.validate())
        
        // maxConnections <= 0
        let config2 = PoolConfiguration(maxConnections: 0)
        XCTAssertThrowsError(try config2.validate())
        
        // minConnections < 0
        let config3 = PoolConfiguration(minConnections: -1)
        XCTAssertThrowsError(try config3.validate())
    }
    
    // MARK: - Test Pool Creation
    
    func testPoolCreation() async throws {
        let pool = try ConnectionPool<TestConnection>(
            configuration: .small,
            connectionFactory: { TestConnection() }
        )
        
        try await pool.start()
        
        let total = await pool.totalConnections
        XCTAssertGreaterThanOrEqual(total, 1) // 至少创建了最小连接数
    }
    
    func testPoolWithMinConnections() async throws {
        let config = PoolConfiguration(minConnections: 3, maxConnections: 10)
        let pool = try ConnectionPool<TestConnection>(
            configuration: config,
            connectionFactory: { TestConnection() }
        )
        
        try await pool.start()
        
        let total = await pool.totalConnections
        XCTAssertEqual(total, 3) // 应该创建 3 个最小连接
    }
    
    // MARK: - Test Acquire and Release
    
    func testAcquireConnection() async throws {
        let pool = try ConnectionPool<TestConnection>(
            configuration: .small,
            connectionFactory: { TestConnection() }
        )
        
        try await pool.start()
        
        let conn = try await pool.acquire()
        XCTAssertNotNil(conn)
        XCTAssertFalse(conn.isAvailable) // 应该被标记为使用中
        
        await pool.release(conn)
        XCTAssertTrue(conn.isAvailable) // 应该被标记为可用
    }
    
    func testAcquireMultipleConnections() async throws {
        let pool = try ConnectionPool<TestConnection>(
            configuration: .small,
            connectionFactory: { TestConnection() }
        )
        
        try await pool.start()
        
        let conn1 = try await pool.acquire()
        let conn2 = try await pool.acquire()
        let conn3 = try await pool.acquire()
        
        let active = await pool.activeConnections
        XCTAssertEqual(active, 3)
        
        await pool.release(conn1)
        await pool.release(conn2)
        await pool.release(conn3)
        
        let idle = await pool.idleConnections
        XCTAssertGreaterThanOrEqual(idle, 3)
    }
    
    func testAcquireWhenPoolFull() async throws {
        let config = PoolConfiguration(
            minConnections: 1,
            maxConnections: 2,
            acquireTimeout: 1,
            waitWhenPoolFull: false
        )
        
        let pool = try ConnectionPool<TestConnection>(
            configuration: config,
            connectionFactory: { TestConnection() }
        )
        
        try await pool.start()
        
        let conn1 = try await pool.acquire()
        let conn2 = try await pool.acquire()
        
        // 池已满，不等待，应该抛出错误
        do {
            _ = try await pool.acquire()
            XCTFail("Should throw poolExhausted error")
        } catch let error as PoolError {
            if case .poolExhausted = error {
                // Expected
            } else {
                XCTFail("Wrong error type")
            }
        }
        
        await pool.release(conn1)
        await pool.release(conn2)
    }
    
    // MARK: - Test Strategies
    
    func testRoundRobinStrategy() async throws {
        let strategy = RoundRobinStrategy()
        
        let connections = [
            PooledConnection(connection: TestConnection()),
            PooledConnection(connection: TestConnection()),
            PooledConnection(connection: TestConnection())
        ]
        
        let index1 = strategy.selectConnection(from: connections)
        let index2 = strategy.selectConnection(from: connections)
        let index3 = strategy.selectConnection(from: connections)
        
        XCTAssertNotNil(index1)
        XCTAssertNotNil(index2)
        XCTAssertNotNil(index3)
        
        // 应该按顺序选择
        XCTAssertNotEqual(index1, index2)
    }
    
    func testLeastConnectionsStrategy() async throws {
        let strategy = LeastConnectionsStrategy()
        
        let conn1 = PooledConnection(connection: TestConnection())
        let conn2 = PooledConnection(connection: TestConnection())
        let conn3 = PooledConnection(connection: TestConnection())
        
        // 模拟使用次数
        conn1.markAsAcquired()
        conn1.markAsReleased()
        conn1.markAsAcquired()
        conn1.markAsReleased()
        
        conn2.markAsAcquired()
        conn2.markAsReleased()
        
        let connections = [conn1, conn2, conn3]
        let index = strategy.selectConnection(from: connections)
        
        XCTAssertNotNil(index)
        XCTAssertEqual(index, 2) // 应该选择 conn3（使用次数为 0）
    }
    
    func testRandomStrategy() async throws {
        let strategy = RandomStrategy()
        
        let connections = [
            PooledConnection(connection: TestConnection()),
            PooledConnection(connection: TestConnection()),
            PooledConnection(connection: TestConnection())
        ]
        
        let index = strategy.selectConnection(from: connections)
        
        XCTAssertNotNil(index)
        XCTAssertTrue(index! >= 0 && index! < connections.count)
    }
    
    func testLeastRecentlyUsedStrategy() async throws {
        let strategy = LeastRecentlyUsedStrategy()
        
        let conn1 = PooledConnection(connection: TestConnection())
        let conn2 = PooledConnection(connection: TestConnection())
        let conn3 = PooledConnection(connection: TestConnection())
        
        // 模拟使用
        conn1.markAsAcquired()
        conn1.markAsReleased()
        
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        conn2.markAsAcquired()
        conn2.markAsReleased()
        
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        conn3.markAsAcquired()
        conn3.markAsReleased()
        
        let connections = [conn1, conn2, conn3]
        let index = strategy.selectConnection(from: connections)
        
        XCTAssertNotNil(index)
        XCTAssertEqual(index, 0) // 应该选择 conn1（最久未使用）
    }
    
    // MARK: - Test Statistics
    
    func testStatistics() async throws {
        let pool = try ConnectionPool<TestConnection>(
            configuration: .small,
            connectionFactory: { TestConnection() }
        )
        
        try await pool.start()
        
        let conn1 = try await pool.acquire()
        let conn2 = try await pool.acquire()
        
        await pool.release(conn1)
        await pool.release(conn2)
        
        let stats = await pool.getStatistics()
        
        XCTAssertGreaterThanOrEqual(stats.totalAcquired, 2)
        XCTAssertGreaterThanOrEqual(stats.totalReleased, 2)
        XCTAssertGreaterThanOrEqual(stats.totalCreated, 1)
    }
    
    // MARK: - Test Drain
    
    func testDrain() async throws {
        let pool = try ConnectionPool<TestConnection>(
            configuration: .small,
            connectionFactory: { TestConnection() }
        )
        
        try await pool.start()
        
        let conn = try await pool.acquire()
        
        // 在后台排空池
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            await pool.drain()
        }
        
        // 释放连接
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        await pool.release(conn)
        
        // 等待排空完成
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        // 池已关闭，获取连接应该失败
        do {
            _ = try await pool.acquire()
            XCTFail("Should throw poolClosed error")
        } catch {
            // Expected
        }
    }
    
    // MARK: - Test PooledConnection
    
    func testPooledConnectionMetadata() async throws {
        let conn = PooledConnection(connection: TestConnection())
        
        XCTAssertTrue(conn.isAvailable)
        XCTAssertEqual(conn.usageCount, 0)
        
        conn.markAsAcquired()
        XCTAssertFalse(conn.isAvailable)
        XCTAssertEqual(conn.usageCount, 1)
        
        conn.markAsReleased()
        XCTAssertTrue(conn.isAvailable)
        XCTAssertEqual(conn.usageCount, 1)
        
        conn.markAsAcquired()
        XCTAssertEqual(conn.usageCount, 2)
    }
    
    func testPooledConnectionAge() async throws {
        let conn = PooledConnection(connection: TestConnection())
        
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        let age = conn.age
        XCTAssertGreaterThan(age, 0.05) // 应该至少 0.05 秒
    }
}

// MARK: - Test Connection

/// 测试连接
actor TestConnection: PoolableConnection {
    var isValid: Bool = true
    var isClosed: Bool = false
    
    func validate() async throws -> Bool {
        return isValid && !isClosed
    }
    
    func close() async throws {
        isClosed = true
    }
}
