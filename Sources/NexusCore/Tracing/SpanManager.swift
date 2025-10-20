//
//  SpanManager.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Span Manager

/// Span 管理器 - 管理 Span 的生命周期和导出
public actor SpanManager {
    
    // MARK: - Singleton
    
    public static let shared = SpanManager()
    
    // MARK: - Properties
    
    private var activeSpans: [String: Span] = [:]
    private var completedSpans: [Span] = []
    private let exporter: SpanExporter?
    private let sampler: Sampler
    private let maxCompletedSpans: Int
    
    // MARK: - Initialization
    
    public init(
        exporter: SpanExporter? = nil,
        sampler: Sampler = AlwaysOnSampler(),
        maxCompletedSpans: Int = 1000
    ) {
        self.exporter = exporter
        self.sampler = sampler
        self.maxCompletedSpans = maxCompletedSpans
    }
    
    // MARK: - Span Creation
    
    /// 创建 Span
    @discardableResult
    public func startSpan(
        name: String,
        context: TraceContext? = nil,
        kind: SpanKind = .internal,
        attributes: [String: AttributeValue] = [:]
    ) -> Span {
        // 使用现有上下文或创建新上下文
        let traceContext = context ?? TraceContext()
        
        // 采样决策
        let shouldSample = sampler.shouldSample(
            traceId: traceContext.traceId,
            spanId: traceContext.spanId,
            name: name
        )
        
        // 创建 Span
        let span = Span(
            name: name,
            context: traceContext,
            kind: kind,
            startTime: Date(),
            attributes: attributes
        )
        
        // 如果采样，则记录
        if shouldSample {
            activeSpans[traceContext.spanId] = span
        }
        
        return span
    }
    
    /// 创建子 Span
    @discardableResult
    public func startChildSpan(
        name: String,
        parent: Span,
        kind: SpanKind = .internal,
        attributes: [String: AttributeValue] = [:]
    ) -> Span {
        let childContext = parent.context.createChild()
        return startSpan(
            name: name,
            context: childContext,
            kind: kind,
            attributes: attributes
        )
    }
    
    // MARK: - Span End
    
    /// 结束 Span
    public func endSpan(_ span: Span) {
        span.end()
        
        // 从活跃列表移除
        activeSpans.removeValue(forKey: span.context.spanId)
        
        // 添加到完成列表
        completedSpans.append(span)
        
        // 限制完成 Span 数量
        if completedSpans.count > maxCompletedSpans {
            completedSpans.removeFirst()
        }
        
        // 导出
        if let exporter = exporter {
            Task {
                await exporter.export(spans: [span])
            }
        }
    }
    
    // MARK: - Query
    
    /// 获取活跃 Span
    public func getActiveSpan(spanId: String) -> Span? {
        activeSpans[spanId]
    }
    
    /// 获取所有活跃 Span
    public func getAllActiveSpans() -> [Span] {
        Array(activeSpans.values)
    }
    
    /// 获取完成的 Span
    public func getCompletedSpans() -> [Span] {
        completedSpans
    }
    
    // MARK: - Cleanup
    
    /// 清理完成的 Span
    public func cleanup() {
        completedSpans.removeAll()
    }
    
    /// 强制导出所有 Span
    public func flush() async {
        guard let exporter = exporter else { return }
        
        let allSpans = activeSpans.values + completedSpans
        await exporter.export(spans: Array(allSpans))
    }
}

// MARK: - Sampler

/// 采样器协议
public protocol Sampler: Sendable {
    func shouldSample(traceId: String, spanId: String, name: String) -> Bool
}

/// 始终采样
public struct AlwaysOnSampler: Sampler {
    public init() {}
    
    public func shouldSample(traceId: String, spanId: String, name: String) -> Bool {
        true
    }
}

/// 始终不采样
public struct AlwaysOffSampler: Sampler {
    public init() {}
    
    public func shouldSample(traceId: String, spanId: String, name: String) -> Bool {
        false
    }
}

/// 基于概率的采样器
public struct ProbabilitySampler: Sampler {
    private let probability: Double
    
    public init(probability: Double) {
        self.probability = max(0.0, min(1.0, probability))
    }
    
    public func shouldSample(traceId: String, spanId: String, name: String) -> Bool {
        Double.random(in: 0..<1.0) < probability
    }
}

// MARK: - Span Exporter

/// Span 导出器协议
public protocol SpanExporter: Sendable {
    func export(spans: [Span]) async
}

/// 控制台导出器（用于调试）
public struct ConsoleSpanExporter: SpanExporter {
    public init() {}
    
    public func export(spans: [Span]) async {
        for span in spans {
            print("📊 Span: \(span.name)")
            print("   TraceID: \(span.context.traceId)")
            print("   SpanID: \(span.context.spanId)")
            if let duration = span.duration() {
                print("   Duration: \(String(format: "%.2f", duration * 1000))ms")
            }
            print("   Status: \(span.status.rawValue)")
            print("---")
        }
    }
}

/// JSON 文件导出器
public actor JSONFileSpanExporter: SpanExporter {
    private let fileURL: URL
    
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    public func export(spans: [Span]) async {
        let spansData = spans.map { $0.toDictionary() }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: spansData, options: .prettyPrinted)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ Failed to export spans: \(error)")
        }
    }
}
