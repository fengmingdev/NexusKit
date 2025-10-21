//
//  BuiltinPluginsTests.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-10-20.
//

import XCTest
@testable import NexusKit

final class BuiltinPluginsTests: XCTestCase {
    
    // MARK: - LoggingPlugin Tests
    
    func testLoggingPluginInfo() async throws {
        let plugin = LoggingPlugin()
        
        XCTAssertEqual(plugin.name, "LoggingPlugin")
        XCTAssertEqual(plugin.version, "1.0.0")
        XCTAssertTrue(plugin.isEnabled)
    }
    
    func testLoggingPluginLifecycle() async throws {
        let plugin = LoggingPlugin(logLevel: .debug)
        let context = PluginContext(
            connectionId: "test-conn",
            remoteHost: "example.com",
            remotePort: 8080
        )
        
        // 测试生命周期钩子不抛出异常
        try await plugin.willConnect(context)
        await plugin.didConnect(context)
        await plugin.willDisconnect(context)
        await plugin.didDisconnect(context)
    }
    
    func testLoggingPluginDataHooks() async throws {
        let plugin = LoggingPlugin(logLevel: .debug, logDataContent: true)
        let context = PluginContext(connectionId: "test-conn")
        
        let testData = "Hello, World!".data(using: .utf8)!
        
        // willSend 应该返回原数据
        let sentData = try await plugin.willSend(testData, context: context)
        XCTAssertEqual(sentData, testData)
        
        await plugin.didSend(testData, context: context)
        
        // willReceive 应该返回原数据
        let receivedData = try await plugin.willReceive(testData, context: context)
        XCTAssertEqual(receivedData, testData)
        
        await plugin.didReceive(testData, context: context)
    }
    
    func testLoggingPluginErrorHandling() async throws {
        let plugin = LoggingPlugin(logLevel: .error)
        let context = PluginContext(connectionId: "test-conn")
        
        let testError = NSError(domain: "Test", code: 123, userInfo: nil)
        
        // 错误处理不应该抛出异常
        await plugin.handleError(testError, context: context)
    }
    
    func testLoggingPluginDisabled() async throws {
        let plugin = LoggingPlugin(isEnabled: false)
        
        XCTAssertFalse(plugin.isEnabled)
        
        let context = PluginContext(connectionId: "test-conn")
        let testData = "test".data(using: .utf8)!
        
        // 即使禁用，数据处理也应该正常返回
        let processedData = try await plugin.willSend(testData, context: context)
        XCTAssertEqual(processedData, testData)
    }
    
    // MARK: - MetricsPlugin Tests
    
    func testMetricsPluginInfo() async throws {
        let plugin = MetricsPlugin()
        
        let name = await plugin.name
        let version = await plugin.version
        let isEnabled = plugin.isEnabled
        
        XCTAssertEqual(name, "MetricsPlugin")
        XCTAssertEqual(version, "1.0.0")
        XCTAssertTrue(isEnabled)
    }
    
    func testMetricsPluginConnectionTracking() async throws {
        let plugin = MetricsPlugin()
        let context = PluginContext(
            connectionId: "conn1",
            remoteHost: "example.com",
            remotePort: 8080
        )
        
        // 连接
        await plugin.didConnect(context)
        
        let globalMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(globalMetrics.totalConnections, 1)
        XCTAssertEqual(globalMetrics.activeConnections, 1)
        
        // 断开连接
        await plugin.didDisconnect(context)
        
        let updatedMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(updatedMetrics.activeConnections, 0)
    }
    
    func testMetricsPluginDataTracking() async throws {
        let plugin = MetricsPlugin()
        let context = PluginContext(connectionId: "conn1")
        
        await plugin.didConnect(context)
        
        let testData = Data(repeating: 0xFF, count: 1024)
        
        // 发送数据
        await plugin.didSend(testData, context: context)
        
        var globalMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(globalMetrics.totalBytesSent, 1024)
        
        // 接收数据
        await plugin.didReceive(testData, context: context)
        
        globalMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(globalMetrics.totalBytesReceived, 1024)
        
        // 检查连接指标
        let connMetrics = await plugin.getConnectionMetrics("conn1")
        XCTAssertNotNil(connMetrics)
        XCTAssertEqual(connMetrics?.bytesSent, 1024)
        XCTAssertEqual(connMetrics?.bytesReceived, 1024)
        XCTAssertEqual(connMetrics?.sendCount, 1)
        XCTAssertEqual(connMetrics?.receiveCount, 1)
    }
    
    func testMetricsPluginErrorTracking() async throws {
        let plugin = MetricsPlugin()
        let context = PluginContext(connectionId: "conn1")
        
        await plugin.didConnect(context)
        
        let testError = NSError(domain: "Test", code: 1, userInfo: nil)
        
        // 记录错误
        await plugin.handleError(testError, context: context)
        await plugin.handleError(testError, context: context)
        
        let globalMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(globalMetrics.totalErrors, 2)
        
        let connMetrics = await plugin.getConnectionMetrics("conn1")
        XCTAssertEqual(connMetrics?.errors, 2)
    }
    
    func testMetricsPluginMultipleConnections() async throws {
        let plugin = MetricsPlugin()
        
        // 创建多个连接
        for i in 1...5 {
            let context = PluginContext(connectionId: "conn\(i)")
            await plugin.didConnect(context)
        }
        
        let globalMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(globalMetrics.totalConnections, 5)
        XCTAssertEqual(globalMetrics.activeConnections, 5)
        
        // 断开部分连接
        for i in 1...3 {
            let context = PluginContext(connectionId: "conn\(i)")
            await plugin.didDisconnect(context)
        }
        
        let updatedMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(updatedMetrics.totalConnections, 5)
        XCTAssertEqual(updatedMetrics.activeConnections, 2)
    }
    
    func testMetricsPluginResetMetrics() async throws {
        let plugin = MetricsPlugin()
        let context = PluginContext(connectionId: "conn1")
        
        await plugin.didConnect(context)
        
        var globalMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(globalMetrics.totalConnections, 1)
        
        // 重置指标
        await plugin.resetMetrics()
        
        globalMetrics = await plugin.getGlobalMetrics()
        XCTAssertEqual(globalMetrics.totalConnections, 0)
        XCTAssertEqual(globalMetrics.activeConnections, 0)
    }
    
    // MARK: - RetryPlugin Tests
    
    func testRetryPluginInfo() async throws {
        let plugin = RetryPlugin()
        
        let name = await plugin.name
        let version = await plugin.version
        let isEnabled = plugin.isEnabled
        
        XCTAssertEqual(name, "RetryPlugin")
        XCTAssertEqual(version, "1.0.0")
        XCTAssertTrue(isEnabled)
    }
    
    func testRetryPluginConfiguration() async throws {
        let plugin = RetryPlugin(
            maxRetryCount: 5,
            initialRetryDelay: 2.0,
            retryBackoffMultiplier: 3.0
        )
        
        let maxRetryCount = await plugin.maxRetryCount
        let initialDelay = await plugin.initialRetryDelay
        let multiplier = await plugin.retryBackoffMultiplier
        
        XCTAssertEqual(maxRetryCount, 5)
        XCTAssertEqual(initialDelay, 2.0)
        XCTAssertEqual(multiplier, 3.0)
    }
    
    func testRetryPluginShouldRetry() async throws {
        let plugin = RetryPlugin(maxRetryCount: 3)
        
        // 可重试的错误
        let networkError = NSError(
            domain: "NetworkError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Network connection failed"]
        )
        
        let shouldRetry1 = await plugin.shouldRetry(error: networkError, connectionId: "conn1")
        XCTAssertTrue(shouldRetry1)
        
        // 不可重试的错误
        let otherError = NSError(
            domain: "OtherError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Some other error"]
        )
        
        let shouldRetry2 = await plugin.shouldRetry(error: otherError, connectionId: "conn1")
        XCTAssertFalse(shouldRetry2)
    }
    
    func testRetryPluginRetryCount() async throws {
        let plugin = RetryPlugin(maxRetryCount: 3)
        let context = PluginContext(connectionId: "conn1")
        
        // 第一次错误
        let error = NSError(
            domain: "NetworkError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]
        )
        
        await plugin.handleError(error, context: context)
        
        var retryCount = await plugin.getRetryCount("conn1")
        XCTAssertEqual(retryCount, 1)
        
        // 第二次错误
        await plugin.handleError(error, context: context)
        
        retryCount = await plugin.getRetryCount("conn1")
        XCTAssertEqual(retryCount, 2)
        
        // 第三次错误
        await plugin.handleError(error, context: context)
        
        retryCount = await plugin.getRetryCount("conn1")
        XCTAssertEqual(retryCount, 3)
        
        // 第四次错误 - 超过最大重试次数
        await plugin.handleError(error, context: context)
        
        retryCount = await plugin.getRetryCount("conn1")
        XCTAssertEqual(retryCount, 3) // 不再增加
    }
    
    func testRetryPluginCalculateDelay() async throws {
        let plugin = RetryPlugin(
            initialRetryDelay: 1.0,
            retryBackoffMultiplier: 2.0
        )
        
        let delay0 = await plugin.calculateRetryDelay(retryCount: 0)
        XCTAssertEqual(delay0, 1.0) // 1.0 * 2^0 = 1.0
        
        let delay1 = await plugin.calculateRetryDelay(retryCount: 1)
        XCTAssertEqual(delay1, 2.0) // 1.0 * 2^1 = 2.0
        
        let delay2 = await plugin.calculateRetryDelay(retryCount: 2)
        XCTAssertEqual(delay2, 4.0) // 1.0 * 2^2 = 4.0
        
        let delay3 = await plugin.calculateRetryDelay(retryCount: 3)
        XCTAssertEqual(delay3, 8.0) // 1.0 * 2^3 = 8.0
    }
    
    func testRetryPluginResetCounter() async throws {
        let plugin = RetryPlugin()
        let context = PluginContext(connectionId: "conn1")
        
        let error = NSError(
            domain: "NetworkError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Temporary network issue"]
        )
        
        // 触发几次错误
        await plugin.handleError(error, context: context)
        await plugin.handleError(error, context: context)
        
        var retryCount = await plugin.getRetryCount("conn1")
        XCTAssertEqual(retryCount, 2)
        
        // 重置计数器
        await plugin.resetRetryCounter("conn1")
        
        retryCount = await plugin.getRetryCount("conn1")
        XCTAssertEqual(retryCount, 0)
    }
    
    func testRetryPluginDidConnect() async throws {
        let plugin = RetryPlugin()
        let context = PluginContext(connectionId: "conn1")
        
        let error = NSError(
            domain: "NetworkError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Connection failed"]
        )
        
        // 触发错误
        await plugin.handleError(error, context: context)
        
        var retryCount = await plugin.getRetryCount("conn1")
        XCTAssertEqual(retryCount, 1)
        
        // 连接成功应该重置计数器
        await plugin.didConnect(context)
        
        retryCount = await plugin.getRetryCount("conn1")
        XCTAssertEqual(retryCount, 0)
    }
    
    func testRetryPluginClearAll() async throws {
        let plugin = RetryPlugin()
        
        let error = NSError(
            domain: "NetworkError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Connection timeout"]
        )
        
        // 为多个连接触发错误
        for i in 1...3 {
            let context = PluginContext(connectionId: "conn\(i)")
            await plugin.handleError(error, context: context)
        }
        
        // 清空所有状态
        await plugin.clearAll()
        
        for i in 1...3 {
            let retryCount = await plugin.getRetryCount("conn\(i)")
            XCTAssertEqual(retryCount, 0)
        }
    }
    
    func testRetryPluginDelegate() async throws {
        let plugin = RetryPlugin(maxRetryCount: 2)
        let delegate = TestRetryDelegate()
        
        await plugin.setDelegate(delegate)
        
        let context = PluginContext(connectionId: "conn1")
        let error = NSError(
            domain: "NetworkError",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Network connection lost"]
        )
        
        // 触发错误应该调用代理
        await plugin.handleError(error, context: context)
        
        // 等待一下确保代理被调用
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        let callCount = await delegate.callCount
        XCTAssertEqual(callCount, 1)
    }
}

// MARK: - Test Delegate

/// 测试重试代理
actor TestRetryDelegate: RetryPluginDelegate {
    var callCount = 0
    var lastConnectionId: String?
    var lastDelay: TimeInterval?
    
    func retryPlugin(_ plugin: RetryPlugin, shouldRetryConnection connectionId: String, afterDelay delay: TimeInterval) async {
        callCount += 1
        lastConnectionId = connectionId
        lastDelay = delay
    }
}
