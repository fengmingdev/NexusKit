//
//  TracingTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore

final class TracingTests: XCTestCase {
    
    // MARK: - TraceContext Tests
    
    func testTraceContextGeneration() {
        // When
        let context = TraceContext()
        
        // Then
        XCTAssertEqual(context.traceId.count, 32) // 16 bytes = 32 hex chars
        XCTAssertEqual(context.spanId.count, 16)  // 8 bytes = 16 hex chars
        XCTAssertNil(context.parentSpanId)
        XCTAssertTrue(context.sampled)
    }
    
    func testTraceContextChild() {
        // Given
        let parent = TraceContext()
        
        // When
        let child = parent.createChild()
        
        // Then
        XCTAssertEqual(child.traceId, parent.traceId) // 同一个 trace
        XCTAssertNotEqual(child.spanId, parent.spanId) // 不同的 span
        XCTAssertEqual(child.parentSpanId, parent.spanId) // 父span正确
    }
    
    func testW3CHeadersGeneration() {
        // Given
        let context = TraceContext(
            traceId: "0123456789abcdef0123456789abcdef",
            spanId: "0123456789abcdef",
            sampled: true
        )
        
        // When
        let headers = context.toW3CHeaders()
        
        // Then
        XCTAssertNotNil(headers["traceparent"])
        XCTAssertTrue(headers["traceparent"]!.hasPrefix("00-"))
        XCTAssertTrue(headers["traceparent"]!.contains(context.traceId))
        XCTAssertTrue(headers["traceparent"]!.contains(context.spanId))
    }
    
    func testW3CHeadersParsing() {
        // Given
        let headers = [
            "traceparent": "00-0123456789abcdef0123456789abcdef-0123456789abcdef-01"
        ]
        
        // When
        let context = TraceContext.fromW3CHeaders(headers)
        
        // Then
        XCTAssertNotNil(context)
        XCTAssertEqual(context?.traceId, "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(context?.spanId, "0123456789abcdef")
        XCTAssertTrue(context?.sampled ?? false)
    }
    
    // MARK: - Span Tests
    
    func testSpanCreation() {
        // Given
        let context = TraceContext()
        
        // When
        let span = Span(
            name: "test.operation",
            context: context,
            kind: .client
        )
        
        // Then
        XCTAssertEqual(span.name, "test.operation")
        XCTAssertEqual(span.kind, .client)
        XCTAssertFalse(span.isEnded)
        XCTAssertEqual(span.status, .unset)
    }
    
    func testSpanAttributes() {
        // Given
        let span = Span(name: "test", context: TraceContext())
        
        // When
        span.setAttribute(key: "user.id", value: .string("123"))
        span.setAttribute(key: "request.size", value: .int(1024))
        
        // Then
        let attrs = span.getAttributes()
        XCTAssertEqual(attrs.count, 2)
        XCTAssertEqual(attrs["user.id"]?.stringValue, "123")
        XCTAssertEqual(attrs["request.size"]?.stringValue, "1024")
    }
    
    func testSpanEvents() {
        // Given
        let span = Span(name: "test", context: TraceContext())
        
        // When
        span.addEvent("cache.hit")
        span.addEvent("db.query", attributes: ["table": .string("users")])
        
        // Then
        let events = span.getEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].name, "cache.hit")
        XCTAssertEqual(events[1].name, "db.query")
    }
    
    func testSpanEnd() {
        // Given
        let span = Span(name: "test", context: TraceContext())
        
        // When
        span.end()
        
        // Then
        XCTAssertTrue(span.isEnded)
        XCTAssertNotNil(span.endTime)
        XCTAssertNotNil(span.duration())
    }
    
    func testSpanDuration() {
        // Given
        let span = Span(name: "test", context: TraceContext())
        
        // When
        Thread.sleep(forTimeInterval: 0.1) // 100ms
        span.end()
        
        // Then
        let duration = span.duration()
        XCTAssertNotNil(duration)
        XCTAssertGreaterThan(duration!, 0.09) // 至少90ms
    }
    
    // MARK: - SpanManager Tests
    
    func testSpanManagerStartSpan() async {
        // Given
        let manager = SpanManager()
        
        // When
        let span = await manager.startSpan(name: "test.operation")
        
        // Then
        XCTAssertEqual(span.name, "test.operation")
        XCTAssertFalse(span.isEnded)
    }
    
    func testSpanManagerChildSpan() async {
        // Given
        let manager = SpanManager()
        let parent = await manager.startSpan(name: "parent")
        
        // When
        let child = await manager.startChildSpan(name: "child", parent: parent)
        
        // Then
        XCTAssertEqual(child.context.traceId, parent.context.traceId)
        XCTAssertEqual(child.context.parentSpanId, parent.context.spanId)
    }
    
    func testSpanManagerEndSpan() async {
        // Given
        let manager = SpanManager()
        let span = await manager.startSpan(name: "test")
        
        // When
        await manager.endSpan(span)
        
        // Then
        XCTAssertTrue(span.isEnded)
        let completedSpans = await manager.getCompletedSpans()
        XCTAssertEqual(completedSpans.count, 1)
    }
    
    // MARK: - Sampler Tests
    
    func testAlwaysOnSampler() {
        // Given
        let sampler = AlwaysOnSampler()
        
        // When/Then
        for _ in 0..<100 {
            XCTAssertTrue(sampler.shouldSample(traceId: "test", spanId: "test", name: "test"))
        }
    }
    
    func testAlwaysOffSampler() {
        // Given
        let sampler = AlwaysOffSampler()
        
        // When/Then
        for _ in 0..<100 {
            XCTAssertFalse(sampler.shouldSample(traceId: "test", spanId: "test", name: "test"))
        }
    }
    
    func testProbabilitySampler() {
        // Given
        let sampler = ProbabilitySampler(probability: 0.5)
        var sampledCount = 0
        
        // When
        for _ in 0..<1000 {
            if sampler.shouldSample(traceId: "test", spanId: "test", name: "test") {
                sampledCount += 1
            }
        }
        
        // Then - 应该接近50%
        XCTAssertGreaterThan(sampledCount, 400)
        XCTAssertLessThan(sampledCount, 600)
    }
    
    // MARK: - TracingPlugin Tests
    
    func testTracingPluginLifecycle() async throws {
        // Given
        let manager = SpanManager()
        let plugin = TracingPlugin(spanManager: manager)
        
        let context = PluginContext(
            connectionId: "test-conn-1",
            remoteHost: "example.com",
            remotePort: 8080
        )
        
        // When - 连接
        try await plugin.willConnect(context)
        await plugin.didConnect(context)
        
        // Then
        let completedSpans = await manager.getCompletedSpans()
        XCTAssertGreaterThan(completedSpans.count, 0)
        XCTAssertEqual(completedSpans.first?.name, "connection.establish")
    }
    
    func testTracingPluginDataFlow() async throws {
        // Given
        let manager = SpanManager()
        let plugin = TracingPlugin(spanManager: manager)
        
        let context = PluginContext(connectionId: "test-conn-1")
        let data = "test message".data(using: .utf8)!
        
        // When
        _ = try await plugin.willSend(data, context: context)
        _ = try await plugin.willReceive(data, context: context)
        
        // Then
        let completedSpans = await manager.getCompletedSpans()
        XCTAssertGreaterThanOrEqual(completedSpans.count, 2)
    }
}
