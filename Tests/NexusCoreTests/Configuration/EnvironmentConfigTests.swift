//
//  EnvironmentConfigTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusKit

final class EnvironmentConfigTests: XCTestCase {
    
    // MARK: - Test Environment Config Creation
    
    func testDefaultEnvironmentConfig() async throws {
        let config = EnvironmentConfig.default
        
        XCTAssertEqual(config.prefix, "NEXUS_")
        XCTAssertTrue(config.loadFromEnvironment)
        XCTAssertTrue(config.customVariables.isEmpty)
    }
    
    func testCustomEnvironmentConfig() async throws {
        let config = EnvironmentConfig(
            prefix: "MY_APP_",
            loadFromEnvironment: false,
            customVariables: ["KEY1": "VALUE1"]
        )
        
        XCTAssertEqual(config.prefix, "MY_APP_")
        XCTAssertFalse(config.loadFromEnvironment)
        XCTAssertEqual(config.customVariables.count, 1)
    }
    
    // MARK: - Test Custom Variables
    
    func testGetCustomVariable() async throws {
        let config = EnvironmentConfig(
            loadFromEnvironment: false,
            customVariables: [
                "TIMEOUT": "60",
                "RETRY_COUNT": "5",
                "ENABLE_DEBUG": "true"
            ]
        )
        
        XCTAssertEqual(config.get("TIMEOUT"), "60")
        XCTAssertEqual(config.get("RETRY_COUNT"), "5")
        XCTAssertEqual(config.get("ENABLE_DEBUG"), "true")
        XCTAssertNil(config.get("NONEXISTENT"))
    }
    
    func testGetWithDefault() async throws {
        let config = EnvironmentConfig(
            loadFromEnvironment: false,
            customVariables: ["KEY1": "VALUE1"]
        )
        
        XCTAssertEqual(config.get("KEY1", default: "DEFAULT"), "VALUE1")
        XCTAssertEqual(config.get("KEY2", default: "DEFAULT"), "DEFAULT")
    }
    
    // MARK: - Test Type Conversion
    
    func testGetIntVariable() async throws {
        let config = EnvironmentConfig(
            loadFromEnvironment: false,
            customVariables: [
                "VALID_INT": "123",
                "INVALID_INT": "abc"
            ]
        )
        
        XCTAssertEqual(config.getInt("VALID_INT"), 123)
        XCTAssertNil(config.getInt("INVALID_INT"))
        XCTAssertNil(config.getInt("NONEXISTENT"))
    }
    
    func testGetDoubleVariable() async throws {
        let config = EnvironmentConfig(
            loadFromEnvironment: false,
            customVariables: [
                "VALID_DOUBLE": "123.45",
                "INVALID_DOUBLE": "xyz"
            ]
        )
        
        XCTAssertEqual(config.getDouble("VALID_DOUBLE"), 123.45)
        XCTAssertNil(config.getDouble("INVALID_DOUBLE"))
        XCTAssertNil(config.getDouble("NONEXISTENT"))
    }
    
    func testGetBoolVariable() async throws {
        let config = EnvironmentConfig(
            loadFromEnvironment: false,
            customVariables: [
                "TRUE1": "true",
                "TRUE2": "TRUE",
                "TRUE3": "yes",
                "TRUE4": "YES",
                "TRUE5": "1",
                "TRUE6": "on",
                "TRUE7": "ON",
                "FALSE1": "false",
                "FALSE2": "no",
                "FALSE3": "0",
                "FALSE4": "off"
            ]
        )
        
        // True values
        XCTAssertTrue(config.getBool("TRUE1") == true)
        XCTAssertTrue(config.getBool("TRUE2") == true)
        XCTAssertTrue(config.getBool("TRUE3") == true)
        XCTAssertTrue(config.getBool("TRUE4") == true)
        XCTAssertTrue(config.getBool("TRUE5") == true)
        XCTAssertTrue(config.getBool("TRUE6") == true)
        XCTAssertTrue(config.getBool("TRUE7") == true)
        
        // False values
        XCTAssertTrue(config.getBool("FALSE1") == false)
        XCTAssertTrue(config.getBool("FALSE2") == false)
        XCTAssertTrue(config.getBool("FALSE3") == false)
        XCTAssertTrue(config.getBool("FALSE4") == false)
        
        // Nonexistent
        XCTAssertNil(config.getBool("NONEXISTENT"))
    }
    
    func testGetTimeIntervalVariable() async throws {
        let config = EnvironmentConfig(
            loadFromEnvironment: false,
            customVariables: [
                "VALID_INTERVAL": "30.5",
                "INVALID_INTERVAL": "abc"
            ]
        )
        
        XCTAssertEqual(config.getTimeInterval("VALID_INTERVAL"), 30.5)
        XCTAssertNil(config.getTimeInterval("INVALID_INTERVAL"))
        XCTAssertNil(config.getTimeInterval("NONEXISTENT"))
    }
    
    // MARK: - Test Environment Variable Keys
    
    func testEnvironmentVariableKeys() async throws {
        // 验证所有定义的键
        XCTAssertEqual(EnvironmentConfig.Key.timeout.rawValue, "TIMEOUT")
        XCTAssertEqual(EnvironmentConfig.Key.retryCount.rawValue, "RETRY_COUNT")
        XCTAssertEqual(EnvironmentConfig.Key.enableHeartbeat.rawValue, "ENABLE_HEARTBEAT")
        XCTAssertEqual(EnvironmentConfig.Key.heartbeatInterval.rawValue, "HEARTBEAT_INTERVAL")
        XCTAssertEqual(EnvironmentConfig.Key.logLevel.rawValue, "LOG_LEVEL")
        XCTAssertEqual(EnvironmentConfig.Key.debugMode.rawValue, "DEBUG_MODE")
        XCTAssertEqual(EnvironmentConfig.Key.bufferSize.rawValue, "BUFFER_SIZE")
        XCTAssertEqual(EnvironmentConfig.Key.maxConnections.rawValue, "MAX_CONNECTIONS")
    }
    
    // MARK: - Test Load All
    
    func testLoadAllCustomVariables() async throws {
        let config = EnvironmentConfig(
            loadFromEnvironment: false,
            customVariables: [
                "KEY1": "VALUE1",
                "KEY2": "VALUE2",
                "KEY3": "VALUE3"
            ]
        )
        
        let allVars = config.loadAll()
        
        XCTAssertEqual(allVars.count, 3)
        XCTAssertEqual(allVars["KEY1"], "VALUE1")
        XCTAssertEqual(allVars["KEY2"], "VALUE2")
        XCTAssertEqual(allVars["KEY3"], "VALUE3")
    }
    
    // MARK: - Test Validation
    
    func testEnvironmentConfigValidation() async throws {
        let config = EnvironmentConfig.default
        
        // 环境配置不需要验证，应该总是通过
        XCTAssertNoThrow(try config.validate())
    }
    
    // MARK: - Test Description
    
    func testEnvironmentConfigDescription() async throws {
        let config = EnvironmentConfig(
            prefix: "TEST_",
            loadFromEnvironment: true,
            customVariables: ["KEY": "VALUE"]
        )
        
        let description = config.description
        
        XCTAssertTrue(description.contains("EnvironmentConfig"))
        XCTAssertTrue(description.contains("TEST_"))
        XCTAssertTrue(description.contains("true"))
        XCTAssertTrue(description.contains("1"))
    }
}
