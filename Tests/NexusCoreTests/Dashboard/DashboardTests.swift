//
//  DashboardTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

final class DashboardTests: XCTestCase {
    
    // MARK: - Configuration Tests
    
    func testDashboardConfigurationDefaults() {
        let config = DashboardConfiguration()
        
        XCTAssertEqual(config.updateInterval, 1.0)
        XCTAssertEqual(config.historyRetention, 3600)
        XCTAssertEqual(config.maxHistoryPoints, 1000)
        XCTAssertEqual(config.aggregationInterval, 1.0)
        XCTAssertEqual(config.pushMode, .websocket)
        XCTAssertEqual(config.maxClients, 100)
        XCTAssertTrue(config.enableCompression)
        XCTAssertTrue(config.includeDetailedMetrics)
    }
    
    func testDashboardConfigurationPresets() {
        // 开发配置
        let dev = DashboardConfiguration.development
        XCTAssertEqual(dev.updateInterval, 0.5)
        XCTAssertEqual(dev.maxClients, 10)
        XCTAssertFalse(dev.enableCompression)
        
        // 生产配置
        let prod = DashboardConfiguration.production
        XCTAssertEqual(prod.updateInterval, 5.0)
        XCTAssertEqual(prod.maxClients, 100)
        XCTAssertTrue(prod.enableCompression)
        
        // 高性能配置
        let highPerf = DashboardConfiguration.highPerformance
        XCTAssertEqual(highPerf.updateInterval, 10.0)
        XCTAssertEqual(highPerf.pushMode, .polling)
        
        // 详细配置
        let detailed = DashboardConfiguration.detailed
        XCTAssertTrue(detailed.includeDetailedMetrics)
        XCTAssertEqual(detailed.maxHistoryPoints, 5000)
    }
    
    func testDashboardFeatures() {
        let all = DashboardFeatures.all
        
        XCTAssertTrue(all.contains(.overview))
        XCTAssertTrue(all.contains(.connections))
        XCTAssertTrue(all.contains(.performance))
        XCTAssertTrue(all.contains(.health))
        XCTAssertTrue(all.contains(.errors))
        XCTAssertTrue(all.contains(.tracing))
        
        let custom: DashboardFeatures = [.overview, .health]
        XCTAssertTrue(custom.contains(.overview))
        XCTAssertTrue(custom.contains(.health))
        XCTAssertFalse(custom.contains(.connections))
    }
    
    // MARK: - Metrics Aggregator Tests
    
    func testMetricsAggregatorInitialization() async {
        let aggregator = MetricsAggregator()
        let metrics = await aggregator.aggregate()
        
        XCTAssertEqual(metrics.overview.activeConnections, 0)
        XCTAssertEqual(metrics.overview.totalConnections, 0)
        XCTAssertEqual(metrics.overview.messagesPerSecond, 0)
    }
    
    func testRecordConnectionMetric() async {
        let aggregator = MetricsAggregator()
        
        await aggregator.recordConnectionMetric(
            connectionId: "conn-1",
            bytesReceived: 1024,
            bytesSent: 512,
            messagesReceived: 10,
            messagesSent: 5,
            latency: 25.5
        )
        
        let details = await aggregator.getConnectionDetails(connectionId: "conn-1")
        XCTAssertNotNil(details)
        XCTAssertEqual(details?.bytesReceived, 1024)
        XCTAssertEqual(details?.bytesSent, 512)
        XCTAssertEqual(details?.messagesReceived, 10)
        XCTAssertEqual(details?.messagesSent, 5)
        XCTAssertEqual(details?.latencies.first, 25.5)
    }
    
    func testConnectionStatusUpdate() async {
        let aggregator = MetricsAggregator()
        
        await aggregator.updateConnectionStatus(connectionId: "conn-1", status: .connected)
        
        let details = await aggregator.getConnectionDetails(connectionId: "conn-1")
        XCTAssertEqual(details?.status, .connected)
        
        await aggregator.updateConnectionStatus(connectionId: "conn-1", status: .disconnected)
        let updated = await aggregator.getConnectionDetails(connectionId: "conn-1")
        XCTAssertEqual(updated?.status, .disconnected)
    }
    
    func testRemoveConnection() async {
        let aggregator = MetricsAggregator()
        
        await aggregator.recordConnectionMetric(
            connectionId: "conn-1",
            bytesReceived: 1024,
            bytesSent: 512,
            messagesReceived: 10,
            messagesSent: 5,
            latency: 25.5
        )
        
        var details = await aggregator.getConnectionDetails(connectionId: "conn-1")
        XCTAssertNotNil(details)
        
        await aggregator.removeConnection(connectionId: "conn-1")
        details = await aggregator.getConnectionDetails(connectionId: "conn-1")
        XCTAssertNil(details)
    }
    
    func testSystemSnapshotRecording() async {
        let aggregator = MetricsAggregator()
        
        await aggregator.recordSystemSnapshot(
            cpuUsage: 45.5,
            memoryUsage: 128 * 1024 * 1024,
            activeConnections: 10,
            totalThroughput: 1250.0,
            errorRate: 0.5
        )
        
        let metrics = await aggregator.aggregate()
        XCTAssertEqual(metrics.health.cpuUsage, 45.5)
        XCTAssertEqual(metrics.health.memoryUsage, 128 * 1024 * 1024)
        XCTAssertEqual(metrics.health.activeConnections, 10)
    }
    
    func testMetricsAggregation() async {
        let aggregator = MetricsAggregator()
        
        // 记录多个连接
        for i in 1...5 {
            await aggregator.recordConnectionMetric(
                connectionId: "conn-\(i)",
                bytesReceived: Int64(i * 1024),
                bytesSent: Int64(i * 512),
                messagesReceived: Int64(i * 10),
                messagesSent: Int64(i * 5),
                latency: Double(i) * 10.0
            )
            await aggregator.updateConnectionStatus(connectionId: "conn-\(i)", status: .connected)
        }
        
        let metrics = await aggregator.aggregate()
        
        // 验证概览数据
        XCTAssertEqual(metrics.overview.totalConnections, 5)
        XCTAssertEqual(metrics.overview.activeConnections, 5)
        XCTAssertGreaterThan(metrics.overview.totalMessages, 0)
        XCTAssertGreaterThan(metrics.overview.totalBytes, 0)
        
        // 验证连接列表
        XCTAssertEqual(metrics.connections.count, 5)
        
        // 验证健康状态
        XCTAssertNotNil(metrics.health.status)
    }
    
    func testHistoryRetention() async {
        let config = DashboardConfiguration(
            historyRetention: 1.0,  // 1秒保留
            maxHistoryPoints: 10
        )
        let aggregator = MetricsAggregator(configuration: config)
        
        // 记录一个快照
        await aggregator.recordSystemSnapshot(
            cpuUsage: 50.0,
            memoryUsage: 100 * 1024 * 1024,
            activeConnections: 5,
            totalThroughput: 1000.0,
            errorRate: 0.1
        )
        
        // 等待超过保留时间
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        // 记录新快照（会触发清理）
        await aggregator.recordSystemSnapshot(
            cpuUsage: 60.0,
            memoryUsage: 120 * 1024 * 1024,
            activeConnections: 6,
            totalThroughput: 1200.0,
            errorRate: 0.2
        )
        
        let metrics = await aggregator.aggregate()
        // 旧数据应该被清理
        XCTAssertLessThanOrEqual(metrics.history.dataPoints, 2)
    }
    
    // MARK: - Realtime Stream Tests
    
    func testRealtimeStreamSubscription() async {
        let aggregator = MetricsAggregator()
        let stream = RealtimeStream(aggregator: aggregator)
        
        var receivedMetrics: AggregatedMetrics?
        
        let subscribed = await stream.subscribe(id: "client-1") { metrics in
            receivedMetrics = metrics
        }
        
        XCTAssertTrue(subscribed)
        
        let count = await stream.getSubscriberCount()
        XCTAssertEqual(count, 1)
        
        // 发送更新
        await stream.sendUpdate(to: "client-1")
        
        // 短暂等待
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertNotNil(receivedMetrics)
    }
    
    func testRealtimeStreamUnsubscribe() async {
        let aggregator = MetricsAggregator()
        let stream = RealtimeStream(aggregator: aggregator)
        
        _ = await stream.subscribe(id: "client-1") { _ in }
        
        var count = await stream.getSubscriberCount()
        XCTAssertEqual(count, 1)
        
        await stream.unsubscribe(id: "client-1")
        
        count = await stream.getSubscriberCount()
        XCTAssertEqual(count, 0)
    }
    
    func testRealtimeStreamMaxClients() async {
        let config = DashboardConfiguration(maxClients: 2)
        let aggregator = MetricsAggregator(configuration: config)
        let stream = RealtimeStream(configuration: config, aggregator: aggregator)
        
        let sub1 = await stream.subscribe(id: "client-1") { _ in }
        XCTAssertTrue(sub1)
        
        let sub2 = await stream.subscribe(id: "client-2") { _ in }
        XCTAssertTrue(sub2)
        
        // 第三个应该失败
        let sub3 = await stream.subscribe(id: "client-3") { _ in }
        XCTAssertFalse(sub3)
    }
    
    func testRealtimeStreamBroadcast() async {
        let aggregator = MetricsAggregator()
        let stream = RealtimeStream(aggregator: aggregator)
        
        var client1Received = 0
        var client2Received = 0
        
        _ = await stream.subscribe(id: "client-1") { _ in
            client1Received += 1
        }
        
        _ = await stream.subscribe(id: "client-2") { _ in
            client2Received += 1
        }
        
        await stream.broadcastUpdate()
        
        // 短暂等待
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(client1Received, 1)
        XCTAssertEqual(client2Received, 1)
    }
    
    func testRealtimeStreamAutoUpdate() async {
        let config = DashboardConfiguration(updateInterval: 0.1)
        let aggregator = MetricsAggregator(configuration: config)
        let stream = RealtimeStream(configuration: config, aggregator: aggregator)
        
        var updateCount = 0
        
        _ = await stream.subscribe(id: "client-1") { _ in
            updateCount += 1
        }
        
        await stream.startStreaming()
        
        // 等待几次更新
        try? await Task.sleep(nanoseconds: 350_000_000)
        
        await stream.stopStreaming()
        
        // 应该收到至少 2 次更新
        XCTAssertGreaterThan(updateCount, 1)
    }
    
    // MARK: - Dashboard Server Tests
    
    func testDashboardServerInitialization() async {
        let server = DashboardServer()
        
        let isRunning = await server.isServerRunning()
        XCTAssertFalse(isRunning)
    }
    
    func testDashboardServerStartStop() async {
        let server = DashboardServer()
        
        await server.start()
        var isRunning = await server.isServerRunning()
        XCTAssertTrue(isRunning)
        
        await server.stop()
        isRunning = await server.isServerRunning()
        XCTAssertFalse(isRunning)
    }
    
    func testDashboardServerRecordMetrics() async {
        let server = DashboardServer()
        await server.start()
        
        // 先更新状态，再记录指标
        await server.updateConnectionStatus(id: "conn-1", status: .connected)
        await server.recordConnection(
            id: "conn-1",
            bytesReceived: 2048,
            bytesSent: 1024,
            messagesReceived: 20,
            messagesSent: 10,
            latency: 15.5
        )
        
        // 检查连接详情而不是聚合数据
        let details = await server.getConnectionDetails(id: "conn-1")
        XCTAssertNotNil(details)
        XCTAssertEqual(details?.messagesReceived, 20)
        
        await server.stop()
    }
    
    func testDashboardServerGetCurrentMetrics() async {
        let server = DashboardServer()
        await server.start()
        
        let metrics = await server.getCurrentMetrics()
        
        XCTAssertNotNil(metrics.timestamp)
        XCTAssertNotNil(metrics.overview)
        XCTAssertNotNil(metrics.health)
        
        await server.stop()
    }
    
    func testDashboardServerExportJSON() async throws {
        let server = DashboardServer()
        await server.start()
        
        await server.updateConnectionStatus(id: "conn-1", status: .connected)
        await server.recordConnection(id: "conn-1", messagesReceived: 10)
        
        // 检查连接是否存在
        let details = await server.getConnectionDetails(id: "conn-1")
        XCTAssertNotNil(details)
        
        let jsonData = try await server.exportJSON()
        XCTAssertFalse(jsonData.isEmpty)
        
        // 验证可以解码
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metrics = try decoder.decode(AggregatedMetrics.self, from: jsonData)
        XCTAssertNotNil(metrics.timestamp)
        XCTAssertNotNil(metrics.overview)
        
        await server.stop()
    }
    
    func testDashboardServerExportTextReport() async {
        let server = DashboardServer()
        await server.start()
        
        await server.recordConnection(id: "conn-1", messagesReceived: 10)
        
        let report = await server.exportTextReport()
        
        XCTAssertFalse(report.isEmpty)
        XCTAssertTrue(report.contains("NexusKit Dashboard Report"))
        XCTAssertTrue(report.contains("Overview"))
        XCTAssertTrue(report.contains("Health"))
        
        await server.stop()
    }
    
    func testDashboardServerStatistics() async {
        let server = DashboardServer()
        await server.start()
        
        await server.recordConnection(id: "conn-1")
        await server.updateConnectionStatus(id: "conn-1", status: .connected)
        
        let stats = await server.getStatistics()
        
        XCTAssertTrue(stats.isRunning)
        XCTAssertGreaterThan(stats.uptime, 0)
        XCTAssertEqual(stats.totalConnections, 1)
        XCTAssertEqual(stats.activeConnections, 1)
        
        await server.stop()
    }
    
    func testDashboardServerSubscription() async {
        let server = DashboardServer()
        await server.start()
        
        var received = false
        
        let subscribed = await server.subscribe(id: "test-client") { _ in
            received = true
        }
        
        XCTAssertTrue(subscribed)
        
        let count = await server.getSubscriberCount()
        XCTAssertEqual(count, 1)
        
        // 触发更新
        await server.recordConnection(id: "conn-1")
        
        // 等待回调
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        await server.unsubscribe(id: "test-client")
        await server.stop()
    }
    
    func testDashboardServerReset() async {
        let server = DashboardServer()
        await server.start()
        
        await server.updateConnectionStatus(id: "conn-1", status: .connected)
        await server.recordConnection(id: "conn-1", messagesReceived: 100)
        
        // 检查连接是否存在
        var details = await server.getConnectionDetails(id: "conn-1")
        XCTAssertNotNil(details)
        
        await server.reset()
        
        // 重置后连接应该被清除
        details = await server.getConnectionDetails(id: "conn-1")
        XCTAssertNil(details)
        
        await server.stop()
    }
}
