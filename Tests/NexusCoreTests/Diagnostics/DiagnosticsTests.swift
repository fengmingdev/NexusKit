//
//  DiagnosticsTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

final class DiagnosticsTests: XCTestCase {
    
    // MARK: - Connection Diagnostics Tests
    
    func testConnectionDiagnostics() async {
        // 测试本地连接诊断
        let diagnostics = ConnectionDiagnostics(
            connectionId: "test-conn-1",
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let health = await diagnostics.diagnose()
        
        // 验证诊断结果包含必要信息
        XCTAssertNotNil(health.status)
        XCTAssertNotNil(health.connectionState)
    }
    
    func testDNSResolution() async {
        let diagnostics = ConnectionDiagnostics(
            connectionId: "test-conn-2",
            remoteHost: "localhost",
            remotePort: 8080
        )
        
        let resolved = await diagnostics.checkDNSResolution()
        XCTAssertTrue(resolved, "localhost should always resolve")
    }
    
    func testInvalidHostDNSResolution() async {
        let diagnostics = ConnectionDiagnostics(
            connectionId: "test-conn-3",
            remoteHost: "invalid-host-that-does-not-exist-12345.com",
            remotePort: 8080
        )
        
        let resolved = await diagnostics.checkDNSResolution()
        XCTAssertFalse(resolved, "Invalid host should not resolve")
    }
    
    func testConnectionLatencyMeasurement() async {
        let diagnostics = ConnectionDiagnostics(
            connectionId: "test-conn-4",
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let latency = await diagnostics.measureConnectionLatency()
        
        if let latency = latency {
            XCTAssertGreaterThan(latency, 0, "Latency should be positive")
            XCTAssertLessThan(latency, 5000, "Latency should be reasonable")
        }
    }
    
    func testConnectionHealthRecommendations() async {
        let diagnostics = ConnectionDiagnostics(
            connectionId: "test-conn-5",
            remoteHost: "invalid-host.com",
            remotePort: 8080
        )
        
        let health = await diagnostics.diagnose()
        let recommendations = await diagnostics.generateRecommendations(health: health)
        
        XCTAssertFalse(recommendations.isEmpty, "Should generate recommendations")
    }
    
    // MARK: - Network Diagnostics Tests
    
    func testNetworkDiagnostics() async {
        let diagnostics = NetworkDiagnostics(
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let quality = await diagnostics.diagnose()
        
        // 验证网络质量指标
        XCTAssertGreaterThanOrEqual(quality.latency, 0)
        XCTAssertGreaterThanOrEqual(quality.packetLoss, 0)
        XCTAssertLessThanOrEqual(quality.packetLoss, 100)
        XCTAssertGreaterThanOrEqual(quality.jitter, 0)
    }
    
    func testLatencyMeasurement() async {
        let diagnostics = NetworkDiagnostics(
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let latency = await diagnostics.measureLatency(samples: 3)
        XCTAssertGreaterThan(latency, 0, "Latency should be positive")
    }
    
    func testJitterMeasurement() async {
        let diagnostics = NetworkDiagnostics(
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let jitter = await diagnostics.measureJitter(samples: 5)
        XCTAssertGreaterThanOrEqual(jitter, 0, "Jitter should be non-negative")
    }
    
    func testPacketLossEstimation() async {
        let diagnostics = NetworkDiagnostics(
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let packetLoss = await diagnostics.estimatePacketLoss(samples: 10)
        XCTAssertGreaterThanOrEqual(packetLoss, 0)
        XCTAssertLessThanOrEqual(packetLoss, 100)
    }
    
    func testNetworkInterfaceInfo() async {
        let diagnostics = NetworkDiagnostics(
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let interfaces = await diagnostics.getNetworkInterfaceInfo()
        
        // 应该至少有一个网络接口
        XCTAssertFalse(interfaces.isEmpty, "Should have at least one network interface")
        
        // 验证接口信息
        for interface in interfaces {
            XCTAssertFalse(interface.name.isEmpty)
            XCTAssertFalse(interface.address.isEmpty)
        }
    }
    
    // MARK: - Performance Diagnostics Tests
    
    func testPerformanceDiagnostics() async {
        let diagnostics = PerformanceDiagnostics(connectionId: "test-perf-1")
        
        // 记录一些模拟数据
        await diagnostics.recordMessage(bytes: 1024, latency: 10.5)
        await diagnostics.recordMessage(bytes: 2048, latency: 15.2)
        await diagnostics.recordMessage(bytes: 512, latency: 8.3)
        
        let metrics = await diagnostics.diagnose()
        
        // 验证性能指标
        XCTAssertGreaterThan(metrics.throughput, 0)
        XCTAssertGreaterThan(metrics.averageLatency, 0)
        XCTAssertGreaterThanOrEqual(metrics.memoryUsage, 0)
        XCTAssertGreaterThanOrEqual(metrics.cpuUsage, 0)
    }
    
    func testThroughputCalculation() async {
        let diagnostics = PerformanceDiagnostics(connectionId: "test-perf-2")
        
        // 记录消息
        for i in 0..<10 {
            await diagnostics.recordMessage(bytes: 1024, latency: Double(i) + 5.0)
        }
        
        let throughput = await diagnostics.calculateThroughput()
        XCTAssertGreaterThan(throughput, 0, "Throughput should be positive")
    }
    
    func testAverageLatencyCalculation() async {
        let diagnostics = PerformanceDiagnostics(connectionId: "test-perf-3")
        
        await diagnostics.recordMessage(bytes: 100, latency: 10.0)
        await diagnostics.recordMessage(bytes: 100, latency: 20.0)
        await diagnostics.recordMessage(bytes: 100, latency: 30.0)
        
        let avgLatency = await diagnostics.calculateAverageLatency()
        XCTAssertEqual(avgLatency, 20.0, accuracy: 0.1)
    }
    
    func testPercentileLatencyCalculation() async {
        let diagnostics = PerformanceDiagnostics(connectionId: "test-perf-4")
        
        // 记录 100 个延迟值
        for i in 1...100 {
            await diagnostics.recordMessage(bytes: 100, latency: Double(i))
        }
        
        let p95 = await diagnostics.calculatePercentileLatency(percentile: 0.95)
        let p99 = await diagnostics.calculatePercentileLatency(percentile: 0.99)
        
        XCTAssertNotNil(p95)
        XCTAssertNotNil(p99)
        
        if let p95 = p95, let p99 = p99 {
            XCTAssertLessThanOrEqual(p95, p99, "P95 should be <= P99")
            XCTAssertGreaterThanOrEqual(p95, 90.0, "P95 should be around 95")
            XCTAssertGreaterThanOrEqual(p99, 95.0, "P99 should be around 99")
        }
    }
    
    func testMemoryUsageMeasurement() async {
        let diagnostics = PerformanceDiagnostics(connectionId: "test-perf-5")
        
        let memory = await diagnostics.measureMemoryUsage()
        XCTAssertGreaterThanOrEqual(memory, 0, "Memory usage should be non-negative")
    }
    
    func testCPUUsageMeasurement() async {
        let diagnostics = PerformanceDiagnostics(connectionId: "test-perf-6")
        
        let cpu = await diagnostics.measureCPUUsage()
        XCTAssertGreaterThanOrEqual(cpu, 0, "CPU usage should be non-negative")
    }
    
    // MARK: - Integrated Diagnostics Tool Tests
    
    func testDiagnosticsToolIntegration() async {
        let tool = DiagnosticsTool(
            connectionId: "test-tool-1",
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let report = await tool.runDiagnostics()
        
        // 验证报告完整性
        XCTAssertEqual(report.connectionId, "test-tool-1")
        XCTAssertEqual(report.remoteHost, "127.0.0.1")
        XCTAssertEqual(report.remotePort, 80)
        XCTAssertNotNil(report.connectionHealth)
        XCTAssertNotNil(report.networkQuality)
        XCTAssertNotNil(report.performance)
    }
    
    func testQuickHealthCheck() async {
        let tool = DiagnosticsTool(
            connectionId: "test-tool-2",
            remoteHost: "localhost",
            remotePort: 80
        )
        
        let status = await tool.quickHealthCheck()
        XCTAssertNotNil(status)
    }
    
    func testDiagnosticReportJSONExport() async throws {
        let tool = DiagnosticsTool(
            connectionId: "test-tool-3",
            remoteHost: "127.0.0.1",
            remotePort: 8080
        )
        
        let jsonData = try await tool.exportReport(format: .json)
        XCTAssertFalse(jsonData.isEmpty, "JSON data should not be empty")
        
        // 验证 JSON 可以解码
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(DiagnosticsReport.self, from: jsonData)
        XCTAssertEqual(report.connectionId, "test-tool-3")
    }
    
    func testDiagnosticReportMarkdownExport() async throws {
        let tool = DiagnosticsTool(
            connectionId: "test-tool-4",
            remoteHost: "127.0.0.1",
            remotePort: 8080
        )
        
        let markdownData = try await tool.exportReport(format: .markdown)
        XCTAssertFalse(markdownData.isEmpty, "Markdown data should not be empty")
        
        let markdown = String(data: markdownData, encoding: .utf8)
        XCTAssertNotNil(markdown)
        XCTAssertTrue(markdown!.contains("# Diagnostics Report"))
        XCTAssertTrue(markdown!.contains("Connection Health"))
    }
    
    func testDiagnosticsSummary() async {
        let tool = DiagnosticsTool(
            connectionId: "test-tool-5",
            remoteHost: "127.0.0.1",
            remotePort: 80
        )
        
        let summary = await tool.getSummary()
        XCTAssertFalse(summary.isEmpty)
        XCTAssertTrue(summary.contains("test-tool-5"))
        XCTAssertTrue(summary.contains("Status:"))
    }
    
    // MARK: - Report Format Tests
    
    func testDiagnosticsReportToJSON() throws {
        let report = createSampleReport()
        let json = try report.toJSON()
        
        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("connectionId"))
        XCTAssertTrue(json.contains("test-report"))
    }
    
    func testDiagnosticsReportToMarkdown() {
        let report = createSampleReport()
        let markdown = report.toMarkdown()
        
        XCTAssertFalse(markdown.isEmpty)
        XCTAssertTrue(markdown.contains("# Diagnostics Report"))
        XCTAssertTrue(markdown.contains("## Connection Health"))
        XCTAssertTrue(markdown.contains("## Network Quality"))
        XCTAssertTrue(markdown.contains("## Performance"))
    }
    
    // MARK: - Helper Methods
    
    private func createSampleReport() -> DiagnosticsReport {
        DiagnosticsReport(
            connectionId: "test-report",
            remoteHost: "127.0.0.1",
            remotePort: 8080,
            connectionHealth: ConnectionHealth(
                status: .healthy,
                connectionState: "connected",
                dnsResolved: true,
                portReachable: true,
                tlsCertificateValid: true,
                connectionLatency: 45.2
            ),
            networkQuality: NetworkQuality(
                bandwidth: 100.0,
                latency: 50.0,
                packetLoss: 0.1,
                jitter: 5.0,
                rtt: 48.0,
                networkType: "WiFi"
            ),
            performance: PerformanceMetrics(
                throughput: 1250.0,
                averageLatency: 42.5,
                p95Latency: 95.0,
                p99Latency: 150.0,
                memoryUsage: 128 * 1024 * 1024,
                cpuUsage: 25.5,
                bufferUtilization: 45.0,
                activeConnections: 10
            ),
            issues: [],
            recommendations: ["Continue monitoring"]
        )
    }
}
