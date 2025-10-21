//
//  PluginManagerTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusKit

final class PluginManagerTests: XCTestCase {
    
    // MARK: - Test Plugin Registration
    
    func testRegisterPlugin() async throws {
        let manager = PluginManager()
        let plugin = TestPlugin(name: "Test1")
        
        try await manager.register(plugin)
        
        let count = await manager.count
        XCTAssertEqual(count, 1)
        
        let contains = await manager.contains("Test1")
        XCTAssertTrue(contains)
    }
    
    func testRegisterMultiplePlugins() async throws {
        let manager = PluginManager()
        
        try await manager.register(TestPlugin(name: "Plugin1"))
        try await manager.register(TestPlugin(name: "Plugin2"))
        try await manager.register(TestPlugin(name: "Plugin3"))
        
        let count = await manager.count
        XCTAssertEqual(count, 3)
        
        let names = await manager.names
        XCTAssertEqual(names.count, 3)
        XCTAssertTrue(names.contains("Plugin1"))
        XCTAssertTrue(names.contains("Plugin2"))
        XCTAssertTrue(names.contains("Plugin3"))
    }
    
    func testRegisterDuplicatePlugin() async throws {
        let manager = PluginManager()
        let plugin = TestPlugin(name: "Duplicate")
        
        try await manager.register(plugin)
        
        // 尝试注册同名插件应该抛出错误
        do {
            try await manager.register(TestPlugin(name: "Duplicate"))
            XCTFail("Should throw pluginAlreadyRegistered error")
        } catch let error as PluginError {
            if case .pluginAlreadyRegistered(let name) = error {
                XCTAssertEqual(name, "Duplicate")
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func testRegisterWithPriority() async throws {
        let manager = PluginManager()
        
        try await manager.register(TestPlugin(name: "Low"), priority: .low)
        try await manager.register(TestPlugin(name: "High"), priority: .high)
        try await manager.register(TestPlugin(name: "Normal"), priority: .normal)
        
        let names = await manager.names
        
        // 应该按优先级排序：High, Normal, Low
        XCTAssertEqual(names[0], "High")
        XCTAssertEqual(names[1], "Normal")
        XCTAssertEqual(names[2], "Low")
    }
    
    // MARK: - Test Plugin Unregistration
    
    func testUnregisterPlugin() async throws {
        let manager = PluginManager()
        
        try await manager.register(TestPlugin(name: "ToRemove"))
        
        var count = await manager.count
        XCTAssertEqual(count, 1)
        
        let removed = await manager.unregister("ToRemove")
        XCTAssertTrue(removed)
        
        count = await manager.count
        XCTAssertEqual(count, 0)
    }
    
    func testUnregisterNonexistentPlugin() async throws {
        let manager = PluginManager()
        
        let removed = await manager.unregister("Nonexistent")
        XCTAssertFalse(removed)
    }
    
    func testClearAllPlugins() async throws {
        let manager = PluginManager()
        
        try await manager.register(TestPlugin(name: "Plugin1"))
        try await manager.register(TestPlugin(name: "Plugin2"))
        try await manager.register(TestPlugin(name: "Plugin3"))
        
        var count = await manager.count
        XCTAssertEqual(count, 3)
        
        await manager.clear()
        
        count = await manager.count
        XCTAssertEqual(count, 0)
    }
    
    // MARK: - Test Plugin Query
    
    func testGetPlugin() async throws {
        let manager = PluginManager()
        let plugin = TestPlugin(name: "MyPlugin")
        
        try await manager.register(plugin)
        
        let retrieved = await manager.get("MyPlugin")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "MyPlugin")
    }
    
    func testGetNonexistentPlugin() async throws {
        let manager = PluginManager()
        
        let retrieved = await manager.get("Nonexistent")
        XCTAssertNil(retrieved)
    }
    
    func testContainsPlugin() async throws {
        let manager = PluginManager()
        
        try await manager.register(TestPlugin(name: "Exists"))
        
        let contains1 = await manager.contains("Exists")
        XCTAssertTrue(contains1)
        
        let contains2 = await manager.contains("NotExists")
        XCTAssertFalse(contains2)
    }
    
    func testEnabledCount() async throws {
        let manager = PluginManager()
        
        try await manager.register(TestPlugin(name: "Enabled1", enabled: true))
        try await manager.register(TestPlugin(name: "Enabled2", enabled: true))
        try await manager.register(TestPlugin(name: "Disabled", enabled: false))
        
        let enabledCount = await manager.enabledCount
        XCTAssertEqual(enabledCount, 2)
    }
    
    // MARK: - Test Lifecycle Invocation
    
    func testInvokeWillConnect() async throws {
        let manager = PluginManager()
        let plugin = TestPlugin(name: "Test")
        
        try await manager.register(plugin)
        
        let context = PluginContext(connectionId: "conn1")
        try await manager.invokeWillConnect(context)
        
        // 验证插件被调用（通过实际插件的行为验证）
        // 这里只验证不抛出异常
    }
    
    func testInvokeDidConnect() async throws {
        let manager = PluginManager()
        let plugin = TestPlugin(name: "Test")
        
        try await manager.register(plugin)
        
        let context = PluginContext(connectionId: "conn1")
        await manager.invokeDidConnect(context)
        
        // 验证插件被调用
    }
    
    func testInvokeDisconnectHooks() async throws {
        let manager = PluginManager()
        let plugin = TestPlugin(name: "Test")
        
        try await manager.register(plugin)
        
        let context = PluginContext(connectionId: "conn1")
        await manager.invokeWillDisconnect(context)
        await manager.invokeDidDisconnect(context)
        
        // 验证插件被调用
    }
    
    // MARK: - Test Data Processing
    
    func testProcessWillSend() async throws {
        let manager = PluginManager()
        let plugin = DataModifierPlugin(name: "Modifier", suffix: "-modified")
        
        try await manager.register(plugin)
        
        let context = PluginContext(connectionId: "conn1")
        let originalData = "test".data(using: .utf8)!
        
        let processedData = try await manager.processWillSend(originalData, context: context)
        let processedString = String(data: processedData, encoding: .utf8)
        
        XCTAssertEqual(processedString, "test-modified")
    }
    
    func testProcessWillReceive() async throws {
        let manager = PluginManager()
        let plugin = DataModifierPlugin(name: "Modifier", suffix: "-received")
        
        try await manager.register(plugin)
        
        let context = PluginContext(connectionId: "conn1")
        let originalData = "test".data(using: .utf8)!
        
        let processedData = try await manager.processWillReceive(originalData, context: context)
        let processedString = String(data: processedData, encoding: .utf8)
        
        XCTAssertEqual(processedString, "test-received")
    }
    
    func testPluginChain() async throws {
        let manager = PluginManager()
        
        // 注册多个插件，数据会依次经过它们处理
        try await manager.register(DataModifierPlugin(name: "Plugin1", suffix: "-1"))
        try await manager.register(DataModifierPlugin(name: "Plugin2", suffix: "-2"))
        try await manager.register(DataModifierPlugin(name: "Plugin3", suffix: "-3"))
        
        let context = PluginContext(connectionId: "conn1")
        let originalData = "test".data(using: .utf8)!
        
        let processedData = try await manager.processWillSend(originalData, context: context)
        let processedString = String(data: processedData, encoding: .utf8)
        
        // 数据应该经过所有插件处理
        XCTAssertEqual(processedString, "test-1-2-3")
    }
    
    // MARK: - Test Statistics
    
    func testStatistics() async throws {
        let manager = PluginManager()
        let plugin = TestPlugin(name: "Test")
        
        try await manager.register(plugin)
        
        let context = PluginContext(connectionId: "conn1")
        let data = "test".data(using: .utf8)!
        
        // 执行一些操作
        try await manager.invokeWillConnect(context)
        await manager.invokeDidConnect(context)
        _ = try await manager.processWillSend(data, context: context)
        await manager.notifyDidSend(data, context: context)
        
        let stats = await manager.getStatistics()
        
        XCTAssertEqual(stats.hooksInvoked, 2) // willConnect, didConnect
        XCTAssertEqual(stats.dataProcessed, 1) // processWillSend
        XCTAssertTrue(stats.executionTimes.count > 0)
    }
    
    func testResetStatistics() async throws {
        let manager = PluginManager()
        let plugin = TestPlugin(name: "Test")
        
        try await manager.register(plugin)
        
        let context = PluginContext(connectionId: "conn1")
        try await manager.invokeWillConnect(context)
        
        var stats = await manager.getStatistics()
        XCTAssertGreaterThan(stats.hooksInvoked, 0)
        
        await manager.resetStatistics()
        
        stats = await manager.getStatistics()
        XCTAssertEqual(stats.hooksInvoked, 0)
        XCTAssertEqual(stats.dataProcessed, 0)
    }
    
    // MARK: - Test Disabled Manager
    
    func testDisabledManager() async throws {
        let manager = PluginManager()
        await manager.setEnabled(false)
        
        let plugin = TestPlugin(name: "Test")
        try await manager.register(plugin)
        
        let context = PluginContext(connectionId: "conn1")
        let data = "test".data(using: .utf8)!
        
        // 插件管理器禁用时，所有操作应该直接返回
        try await manager.invokeWillConnect(context)
        
        let processedData = try await manager.processWillSend(data, context: context)
        XCTAssertEqual(processedData, data) // 数据应该未被修改
        
        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.hooksInvoked, 0) // 没有调用任何钩子
    }
}

// MARK: - Test Plugins

/// 测试插件
struct TestPlugin: NexusPlugin {
    let name: String
    let version = "1.0.0"
    let isEnabled: Bool
    
    init(name: String, enabled: Bool = true) {
        self.name = name
        self.isEnabled = enabled
    }
}

/// 数据修改插件
struct DataModifierPlugin: NexusPlugin {
    let name: String
    let version = "1.0.0"
    let suffix: String
    
    func willSend(_ data: Data, context: PluginContext) async throws -> Data {
        guard let string = String(data: data, encoding: .utf8) else {
            return data
        }
        let modified = string + suffix
        return modified.data(using: .utf8)!
    }
    
    func willReceive(_ data: Data, context: PluginContext) async throws -> Data {
        guard let string = String(data: data, encoding: .utf8) else {
            return data
        }
        let modified = string + suffix
        return modified.data(using: .utf8)!
    }
}
