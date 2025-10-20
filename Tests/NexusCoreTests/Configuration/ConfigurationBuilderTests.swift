//
//  ConfigurationBuilderTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusCore

final class ConfigurationBuilderTests: XCTestCase {
    
    // MARK: - Test Builder Creation
    
    func testBuilderDefaultCreation() async throws {
        let builder = NexusConfiguration.Builder()
        let config = try builder.build()
        
        // 应该使用默认配置
        XCTAssertEqual(config.global.logLevel, .info)
        XCTAssertEqual(config.connection.connectTimeout, 30)
    }
    
    func testBuilderFromExistingConfig() async throws {
        let existingConfig = NexusConfiguration(
            global: .debug,
            connection: .fast
        )
        
        let builder = NexusConfiguration.Builder(from: existingConfig)
        let config = try builder.build()
        
        XCTAssertEqual(config.global.logLevel, .debug)
        XCTAssertEqual(config.connection.connectTimeout, 10)
    }
    
    // MARK: - Test Fluent API
    
    func testBuilderFluentAPI() async throws {
        let config = try NexusConfiguration.Builder()
            .timeout(60)
            .retryCount(5)
            .enableHeartbeat(true, interval: 45)
            .enableAutoReconnect(true)
            .logLevel(.debug)
            .debugMode(true)
            .bufferSize(16384)
            .maxConcurrentConnections(50)
            .build()
        
        XCTAssertEqual(config.connection.connectTimeout, 60)
        XCTAssertEqual(config.connection.maxRetryCount, 5)
        XCTAssertEqual(config.connection.heartbeatInterval, 45)
        XCTAssertTrue(config.connection.enableHeartbeat)
        XCTAssertTrue(config.connection.enableAutoReconnect)
        XCTAssertEqual(config.global.logLevel, .debug)
        XCTAssertTrue(config.global.debugMode)
        XCTAssertEqual(config.global.defaultBufferSize, 16384)
        XCTAssertEqual(config.global.maxConcurrentConnections, 50)
    }
    
    // MARK: - Test Configuration Options
    
    func testTimeoutConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .timeout(120)
            .build()
        
        XCTAssertEqual(config.connection.connectTimeout, 120)
    }
    
    func testRetryConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .retryCount(10)
            .build()
        
        XCTAssertEqual(config.connection.maxRetryCount, 10)
    }
    
    func testHeartbeatConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .enableHeartbeat(true, interval: 20)
            .build()
        
        XCTAssertTrue(config.connection.enableHeartbeat)
        XCTAssertEqual(config.connection.heartbeatInterval, 20)
    }
    
    func testDisableHeartbeat() async throws {
        let config = try NexusConfiguration.Builder()
            .enableHeartbeat(false)
            .build()
        
        XCTAssertFalse(config.connection.enableHeartbeat)
    }
    
    func testAutoReconnectConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .enableAutoReconnect(true)
            .build()
        
        XCTAssertTrue(config.connection.enableAutoReconnect)
    }
    
    func testConnectionPoolConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .enableConnectionPool(true, minSize: 5, maxSize: 20)
            .build()
        
        XCTAssertTrue(config.connection.enableConnectionPool)
        XCTAssertEqual(config.connection.minPoolSize, 5)
        XCTAssertEqual(config.connection.maxPoolSize, 20)
    }
    
    func testLogLevelConfiguration() async throws {
        for level in NexusLogLevel.allCases {
            let config = try NexusConfiguration.Builder()
                .logLevel(level)
                .build()
            
            XCTAssertEqual(config.global.logLevel, level)
        }
    }
    
    func testVerboseLoggingConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .verboseLogging(true)
            .build()
        
        XCTAssertTrue(config.global.verboseLogging)
    }
    
    func testBufferSizeConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .bufferSize(32768)
            .build()
        
        XCTAssertEqual(config.global.defaultBufferSize, 32768)
    }
    
    func testMetricsConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .enableMetrics(true)
            .build()
        
        XCTAssertTrue(config.global.enableMetrics)
    }
    
    func testDebugModeConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .debugMode(true)
            .build()
        
        XCTAssertTrue(config.global.debugMode)
    }
    
    func testMaxConcurrentConnectionsConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            .maxConcurrentConnections(200)
            .build()
        
        XCTAssertEqual(config.global.maxConcurrentConnections, 200)
    }
    
    // MARK: - Test Build Validation
    
    func testBuildWithInvalidConfiguration() async throws {
        let builder = NexusConfiguration.Builder()
            .timeout(0) // Invalid
        
        XCTAssertThrowsError(try builder.build()) { error in
            XCTAssertTrue(error is ConfigurationError)
        }
    }
    
    func testBuildOrDefault() async throws {
        let builder = NexusConfiguration.Builder()
            .timeout(0) // Invalid
        
        let config = builder.buildOrDefault()
        
        // 应该返回默认配置
        XCTAssertEqual(config.global.logLevel, .info)
        XCTAssertEqual(config.connection.connectTimeout, 30)
    }
    
    // MARK: - Test Merge
    
    func testMergeConfiguration() async throws {
        let config1 = try NexusConfiguration.Builder()
            .timeout(60)
            .retryCount(5)
            .build()
        
        let config2 = try NexusConfiguration.Builder()
            .merge(with: config1)
            .logLevel(.debug)
            .build()
        
        // 应该合并配置
        XCTAssertEqual(config2.connection.connectTimeout, 60)
        XCTAssertEqual(config2.connection.maxRetryCount, 5)
        XCTAssertEqual(config2.global.logLevel, .debug)
    }
    
    // MARK: - Test Complex Scenarios
    
    func testComplexConfiguration() async throws {
        let config = try NexusConfiguration.Builder()
            // 全局配置
            .logLevel(.verbose)
            .verboseLogging(true)
            .bufferSize(65536)
            .enableMetrics(true)
            .debugMode(true)
            .maxConcurrentConnections(500)
            // 连接配置
            .timeout(90)
            .retryCount(15)
            .enableHeartbeat(true, interval: 25)
            .enableAutoReconnect(true)
            .enableConnectionPool(true, minSize: 10, maxSize: 100)
            .build()
        
        // 验证所有配置
        XCTAssertEqual(config.global.logLevel, .verbose)
        XCTAssertTrue(config.global.verboseLogging)
        XCTAssertEqual(config.global.defaultBufferSize, 65536)
        XCTAssertTrue(config.global.enableMetrics)
        XCTAssertTrue(config.global.debugMode)
        XCTAssertEqual(config.global.maxConcurrentConnections, 500)
        
        XCTAssertEqual(config.connection.connectTimeout, 90)
        XCTAssertEqual(config.connection.maxRetryCount, 15)
        XCTAssertTrue(config.connection.enableHeartbeat)
        XCTAssertEqual(config.connection.heartbeatInterval, 25)
        XCTAssertTrue(config.connection.enableAutoReconnect)
        XCTAssertTrue(config.connection.enableConnectionPool)
        XCTAssertEqual(config.connection.minPoolSize, 10)
        XCTAssertEqual(config.connection.maxPoolSize, 100)
        
        // 验证配置有效
        XCTAssertNoThrow(try config.validate())
    }
}
