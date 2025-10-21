//
//  PerformanceMonitorTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

final class PerformanceMonitorTests: XCTestCase {
    
    var monitor: PerformanceMonitor!
    
    override func setUp() async throws {
        monitor = PerformanceMonitor(configuration: .development)
    }
    
    override func tearDown() async throws {
        await monitor.stopMonitoring()
        monitor = nil
    }
    
    // MARK: - Basic Tests
    
    func testRecordConnectionEstablishment() async throws {
        // Given
        let endpoint = "tcp://example.com:8080"
        let duration: TimeInterval = 0.5
        
        // When
        await monitor.recordConnectionEstablishment(duration: duration, endpoint: endpoint)
        
        // Allow some time for async recording
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Then
        let summary = await monitor.getPerformanceSummary()
        XCTAssertGreaterThan(summary.totalConnections, 0)
    }
    
    func testRecordMessageSent() async throws {
        // Given
        let endpoint = "tcp://example.com:8080"
        let bytes = 1024
        
        // When
        await monitor.recordMessageSent(bytes: bytes, endpoint: endpoint)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        let summary = await monitor.getPerformanceSummary()
        XCTAssertGreaterThan(summary.totalMessagesSent, 0)
        XCTAssertGreaterThan(summary.totalBytesSent, 0)
    }
    
    func testRecordMessageReceived() async throws {
        // Given
        let endpoint = "tcp://example.com:8080"
        let bytes = 2048
        
        // When
        await monitor.recordMessageReceived(bytes: bytes, endpoint: endpoint)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        let summary = await monitor.getPerformanceSummary()
        XCTAssertGreaterThan(summary.totalMessagesReceived, 0)
        XCTAssertGreaterThan(summary.totalBytesReceived, 0)
    }
    
    func testRecordError() async throws {
        // Given
        let endpoint = "tcp://example.com:8080"
        let errorType = "timeout"
        
        // When
        await monitor.recordError(type: errorType, endpoint: endpoint)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        let summary = await monitor.getPerformanceSummary()
        XCTAssertGreaterThan(summary.totalErrors, 0)
    }
    
    func testRecordLatency() async throws {
        // Given
        let endpoint = "tcp://example.com:8080"
        let duration: TimeInterval = 0.05 // 50ms
        
        // When
        await monitor.recordLatency(duration: duration, endpoint: endpoint)
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        let summary = await monitor.getPerformanceSummary()
        XCTAssertGreaterThan(summary.averageLatency, 0)
    }
    
    // MARK: - Export Tests
    
    func testExportJSONReport() async throws {
        // Given
        await monitor.recordConnectionEstablishment(duration: 0.5, endpoint: "test")
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // When
        let data = try await monitor.exportReport(format: .json)
        
        // Then
        XCTAssertGreaterThan(data.count, 0)
        
        // Verify it's valid JSON
        let summary = try JSONDecoder().decode(PerformanceSummary.self, from: data)
        XCTAssertNotNil(summary)
    }
    
    func testExportMarkdownReport() async throws {
        // Given
        await monitor.recordConnectionEstablishment(duration: 0.5, endpoint: "test")
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // When
        let data = try await monitor.exportReport(format: .markdown)
        let markdown = String(data: data, encoding: .utf8)
        
        // Then
        XCTAssertNotNil(markdown)
        XCTAssertTrue(markdown!.contains("Performance Report"))
        XCTAssertTrue(markdown!.contains("Overview"))
    }
    
    // MARK: - Monitoring Tests
    
    func testStartStopMonitoring() async throws {
        // When
        await monitor.startMonitoring()
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1s
        
        // Then - should be monitoring
        await monitor.stopMonitoring()
        
        // No assertion needed, just verify no crash
    }
}
