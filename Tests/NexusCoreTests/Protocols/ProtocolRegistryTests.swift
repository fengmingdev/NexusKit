//
//  ProtocolRegistryTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

final class ProtocolRegistryTests: XCTestCase {
    
    var registry: ProtocolRegistry!
    
    override func setUp() async throws {
        registry = ProtocolRegistry()
    }
    
    override func tearDown() async throws {
        registry = nil
    }
    
    // MARK: - Registration Tests
    
    func testRegisterProtocol() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        
        // When
        try await registry.register(jsonProtocol)
        
        // Then
        let retrieved = await registry.get("json")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "JSON")
    }
    
    func testRegisterProtocolWithCustomIdentifier() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        
        // When
        try await registry.register(jsonProtocol, identifier: "custom-json")
        
        // Then
        let retrieved = await registry.get("custom-json")
        XCTAssertNotNil(retrieved)
    }
    
    func testRegisterProtocolWithAliases() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        
        // When
        try await registry.register(jsonProtocol, aliases: ["js", "javascript-object-notation"])
        
        // Then
        let js = await registry.get("js")
        let jsNotation = await registry.get("javascript-object-notation")
        let json = await registry.get("json")
        XCTAssertNotNil(js)
        XCTAssertNotNil(jsNotation)
        XCTAssertNotNil(json)
    }
    
    func testRegisterDuplicateProtocol() async throws {
        // Given
        let jsonProtocol1 = JSONProtocol()
        let jsonProtocol2 = JSONProtocol()
        try await registry.register(jsonProtocol1)
        
        // When/Then
        do {
            try await registry.register(jsonProtocol2)
            XCTFail("Should throw error")
        } catch ProtocolRegistryError.protocolAlreadyRegistered {
            // Expected
        }
    }
    
    func testRegisterProtocolAsDefault() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        
        // When
        try await registry.register(jsonProtocol, isDefault: true)
        
        // Then
        let defaultProtocol = try await registry.getDefault()
        XCTAssertEqual(defaultProtocol.name, "JSON")
    }
    
    // MARK: - Unregistration Tests
    
    func testUnregisterProtocol() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        try await registry.register(jsonProtocol)
        
        // When
        await registry.unregister("json")
        
        // Then
        let retrieved = await registry.get("json")
        XCTAssertNil(retrieved)
    }
    
    func testUnregisterProtocolRemovesAliases() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        try await registry.register(jsonProtocol, aliases: ["js"])
        
        // When
        await registry.unregister("json")
        
        // Then
        let retrieved = await registry.get("js")
        XCTAssertNil(retrieved)
    }
    
    // MARK: - Query Tests
    
    func testGetProtocol() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        try await registry.register(jsonProtocol)
        
        // When
        let retrieved = await registry.get("json")
        
        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "JSON")
    }
    
    func testGetProtocolByAlias() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        try await registry.register(jsonProtocol, aliases: ["js"])
        
        // When
        let retrieved = await registry.get("js")
        
        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "JSON")
    }
    
    func testGetNonExistentProtocol() async throws {
        // When
        let retrieved = await registry.get("non-existent")
        
        // Then
        XCTAssertNil(retrieved)
    }
    
    func testGetDefaultProtocol() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        try await registry.register(jsonProtocol, isDefault: true)
        
        // When
        let defaultProtocol = try await registry.getDefault()
        
        // Then
        XCTAssertEqual(defaultProtocol.name, "JSON")
    }
    
    func testGetDefaultProtocolWhenNoneSet() async throws {
        // When/Then
        do {
            _ = try await registry.getDefault()
            XCTFail("Should throw error")
        } catch ProtocolRegistryError.noDefaultProtocol {
            // Expected
        }
    }
    
    func testSetDefaultProtocol() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        let msgpackProtocol = MessagePackProtocol()
        try await registry.register(jsonProtocol)
        try await registry.register(msgpackProtocol)
        
        // When
        try await registry.setDefault("messagepack")
        
        // Then
        let defaultProtocol = try await registry.getDefault()
        XCTAssertEqual(defaultProtocol.name, "MessagePack")
    }
    
    func testContainsProtocol() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        try await registry.register(jsonProtocol)
        
        // When/Then
        let contains = await registry.contains("json")
        XCTAssertTrue(contains)
        
        let notContains = await registry.contains("non-existent")
        XCTAssertFalse(notContains)
    }
    
    func testAllProtocols() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        let msgpackProtocol = MessagePackProtocol()
        try await registry.register(jsonProtocol)
        try await registry.register(msgpackProtocol)
        
        // When
        let allProtocols = await registry.allProtocols()
        
        // Then
        XCTAssertEqual(allProtocols.count, 2)
        XCTAssertTrue(allProtocols.contains("json"))
        XCTAssertTrue(allProtocols.contains("messagepack"))
    }
    
    func testGetVersions() async throws {
        // Given
        let jsonProtocol = JSONProtocol(version: "2.0")
        try await registry.register(jsonProtocol)
        
        // When
        let versions = await registry.getVersions(for: "json")
        
        // Then
        XCTAssertEqual(versions.count, 1)
        XCTAssertTrue(versions.contains("2.0"))
    }
    
    // MARK: - Statistics Tests
    
    func testStatistics() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        try await registry.register(jsonProtocol)
        
        // When
        await registry.recordUsage(for: "json")
        await registry.recordUsage(for: "json")
        let stats = await registry.getStatistics()
        
        // Then
        XCTAssertEqual(stats.registeredCount, 1)
        XCTAssertEqual(stats.usageCount["json"], 2)
    }
    
    // MARK: - Case Insensitivity Tests
    
    func testCaseInsensitiveIdentifier() async throws {
        // Given
        let jsonProtocol = JSONProtocol()
        try await registry.register(jsonProtocol)
        
        // When/Then
        let upperCase = await registry.get("JSON")
        let lowerCase = await registry.get("json")
        let titleCase = await registry.get("Json")
        XCTAssertNotNil(upperCase)
        XCTAssertNotNil(lowerCase)
        XCTAssertNotNil(titleCase)
    }
}
