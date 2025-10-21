//
//  NexusConfigurationTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusKit

final class NexusConfigurationTests: XCTestCase {
    
    // MARK: - Test Default Configuration
    
    func testDefaultConfiguration() async throws {
        let config = NexusConfiguration.default
        
        // 验证默认值
        XCTAssertEqual(config.global.logLevel, .info)
        XCTAssertEqual(config.global.defaultBufferSize, 8192)
        XCTAssertFalse(config.global.enableMetrics)
        XCTAssertFalse(config.global.debugMode)
        
        XCTAssertEqual(config.connection.connectTimeout, 30)
        XCTAssertEqual(config.connection.maxRetryCount, 3)
        XCTAssertTrue(config.connection.enableHeartbeat)
        XCTAssertTrue(config.connection.enableAutoReconnect)
        
        // 验证配置有效性
        XCTAssertNoThrow(try config.validate())
    }
    
    // MARK: - Test Configuration Creation
    
    func testConfigurationCreation() async throws {
        let globalConfig = GlobalConfig(
            logLevel: .debug,
            verboseLogging: true,
            debugMode: true
        )
        
        let connectionConfig = ConnectionConfig(
            connectTimeout: 60,
            maxRetryCount: 5,
            enableHeartbeat: false
        )
        
        let config = NexusConfiguration(
            global: globalConfig,
            connection: connectionConfig
        )
        
        XCTAssertEqual(config.global.logLevel, .debug)
        XCTAssertTrue(config.global.verboseLogging)
        XCTAssertTrue(config.global.debugMode)
        XCTAssertEqual(config.connection.connectTimeout, 60)
        XCTAssertEqual(config.connection.maxRetryCount, 5)
        XCTAssertFalse(config.connection.enableHeartbeat)
        
        XCTAssertNoThrow(try config.validate())
    }
    
    // MARK: - Test Configuration Validation
    
    func testInvalidBufferSize() async throws {
        let config = GlobalConfig(defaultBufferSize: 0)
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ConfigurationError.invalidBufferSize(let size) = error else {
                XCTFail("Expected invalidBufferSize error")
                return
            }
            XCTAssertEqual(size, 0)
        }
    }
    
    func testInvalidTimeout() async throws {
        let config = ConnectionConfig(connectTimeout: 0)
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ConfigurationError.invalidTimeout(let timeout) = error else {
                XCTFail("Expected invalidTimeout error")
                return
            }
            XCTAssertEqual(timeout, 0)
        }
    }
    
    func testInvalidRetryCount() async throws {
        let config = ConnectionConfig(maxRetryCount: -1)
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ConfigurationError.invalidRetryCount(let count) = error else {
                XCTFail("Expected invalidRetryCount error")
                return
            }
            XCTAssertEqual(count, -1)
        }
    }
    
    func testInvalidPoolSize() async throws {
        let config = ConnectionConfig(
            minPoolSize: 10,
            maxPoolSize: 5
        )
        
        XCTAssertThrowsError(try config.validate()) { error in
            guard case ConfigurationError.missingRequiredConfig = error else {
                XCTFail("Expected missingRequiredConfig error")
                return
            }
        }
    }
    
    // MARK: - Test Preset Configurations
    
    func testDebugConfiguration() async throws {
        let config = GlobalConfig.debug
        
        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertTrue(config.verboseLogging)
        XCTAssertTrue(config.debugMode)
        XCTAssertTrue(config.printTraffic)
        
        XCTAssertNoThrow(try config.validate())
    }
    
    func testProductionConfiguration() async throws {
        let config = GlobalConfig.production
        
        XCTAssertEqual(config.logLevel, .warning)
        XCTAssertFalse(config.verboseLogging)
        XCTAssertFalse(config.debugMode)
        XCTAssertFalse(config.printTraffic)
        XCTAssertTrue(config.enableMetrics)
        
        XCTAssertNoThrow(try config.validate())
    }
    
    func testFastConnectionConfig() async throws {
        let config = ConnectionConfig.fast
        
        XCTAssertEqual(config.connectTimeout, 10)
        XCTAssertEqual(config.readTimeout, 30)
        XCTAssertEqual(config.heartbeatInterval, 15)
        
        XCTAssertNoThrow(try config.validate())
    }
    
    func testSlowConnectionConfig() async throws {
        let config = ConnectionConfig.slow
        
        XCTAssertEqual(config.connectTimeout, 60)
        XCTAssertEqual(config.readTimeout, 120)
        XCTAssertEqual(config.heartbeatInterval, 60)
        
        XCTAssertNoThrow(try config.validate())
    }
    
    func testReliableConnectionConfig() async throws {
        let config = ConnectionConfig.reliable
        
        XCTAssertEqual(config.maxRetryCount, 10)
        XCTAssertTrue(config.enableAutoReconnect)
        XCTAssertEqual(config.maxReconnectAttempts, 0) // 无限重连
        XCTAssertTrue(config.enableHeartbeat)
        
        XCTAssertNoThrow(try config.validate())
    }
    
    // MARK: - Test Description
    
    func testConfigurationDescription() async throws {
        let config = NexusConfiguration.default
        let description = config.description
        
        XCTAssertTrue(description.contains("NexusConfiguration"))
        XCTAssertTrue(description.contains("Global"))
        XCTAssertTrue(description.contains("Connection"))
        XCTAssertTrue(description.contains("Protocols"))
        XCTAssertTrue(description.contains("Environment"))
    }
    
    func testGlobalConfigDescription() async throws {
        let config = GlobalConfig.debug
        let description = config.description
        
        XCTAssertTrue(description.contains("GlobalConfig"))
        XCTAssertTrue(description.contains("DEBUG"))
        XCTAssertTrue(description.contains("8192"))
    }
    
    func testConnectionConfigDescription() async throws {
        let config = ConnectionConfig.reliable
        let description = config.description
        
        XCTAssertTrue(description.contains("ConnectionConfig"))
        XCTAssertTrue(description.contains("30"))
        XCTAssertTrue(description.contains("10"))
    }
}
