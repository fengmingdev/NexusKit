//
//  TraceContext.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Trace Context

/// 追踪上下文 - 用于在分布式系统中传播追踪信息
public struct TraceContext: Sendable, Codable {
    
    /// 追踪 ID（全局唯一）
    public let traceId: String
    
    /// Span ID（当前 Span 的唯一标识）
    public let spanId: String
    
    /// 父 Span ID（可选）
    public let parentSpanId: String?
    
    /// 追踪标志
    public let traceFlags: TraceFlags
    
    /// 追踪状态
    public let traceState: String?
    
    /// 采样决策
    public let sampled: Bool
    
    /// 自定义属性
    public let attributes: [String: String]
    
    // MARK: - Initialization
    
    public init(
        traceId: String = TraceContext.generateTraceId(),
        spanId: String = TraceContext.generateSpanId(),
        parentSpanId: String? = nil,
        traceFlags: TraceFlags = .sampled,
        traceState: String? = nil,
        sampled: Bool = true,
        attributes: [String: String] = [:]
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.traceFlags = traceFlags
        self.traceState = traceState
        self.sampled = sampled
        self.attributes = attributes
    }
    
    // MARK: - Child Context
    
    /// 创建子追踪上下文
    public func createChild() -> TraceContext {
        TraceContext(
            traceId: traceId,
            spanId: TraceContext.generateSpanId(),
            parentSpanId: spanId,
            traceFlags: traceFlags,
            traceState: traceState,
            sampled: sampled,
            attributes: attributes
        )
    }
    
    // MARK: - W3C Trace Context
    
    /// 生成 W3C Trace Context 头部
    public func toW3CHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        
        // traceparent: version-traceId-spanId-flags
        let flags = String(format: "%02x", traceFlags.rawValue)
        headers["traceparent"] = "00-\(traceId)-\(spanId)-\(flags)"
        
        // tracestate (可选)
        if let state = traceState {
            headers["tracestate"] = state
        }
        
        return headers
    }
    
    /// 从 W3C Trace Context 头部解析
    public static func fromW3CHeaders(_ headers: [String: String]) -> TraceContext? {
        guard let traceparent = headers["traceparent"] else {
            return nil
        }
        
        let components = traceparent.split(separator: "-")
        guard components.count == 4,
              components[0] == "00" else { // 版本检查
            return nil
        }
        
        let traceId = String(components[1])
        let spanId = String(components[2])
        let flagsHex = String(components[3])
        
        guard let flagsValue = UInt8(flagsHex, radix: 16) else {
            return nil
        }
        
        let flags = TraceFlags(rawValue: flagsValue)
        let traceState = headers["tracestate"]
        
        return TraceContext(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: nil,
            traceFlags: flags,
            traceState: traceState,
            sampled: flags.contains(.sampled)
        )
    }
    
    // MARK: - ID Generation
    
    /// 生成 Trace ID (32 字符十六进制)
    public static func generateTraceId() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// 生成 Span ID (16 字符十六进制)
    public static func generateSpanId() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Trace Flags

/// 追踪标志
public struct TraceFlags: OptionSet, Sendable, Codable {
    public let rawValue: UInt8
    
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
    
    /// 采样标志
    public static let sampled = TraceFlags(rawValue: 1 << 0)
    
    /// 随机标志（用于采样决策）
    public static let random = TraceFlags(rawValue: 1 << 1)
}

// MARK: - Trace Propagator

/// 追踪传播器 - 负责在不同协议间传播追踪上下文
public protocol TracePropagator: Sendable {
    /// 注入追踪上下文到载体
    func inject(context: TraceContext, into carrier: inout [String: String])
    
    /// 从载体中提取追踪上下文
    func extract(from carrier: [String: String]) -> TraceContext?
}

// MARK: - W3C Trace Propagator

/// W3C 标准追踪传播器
public struct W3CTracePropagator: TracePropagator {
    
    public init() {}
    
    public func inject(context: TraceContext, into carrier: inout [String: String]) {
        let headers = context.toW3CHeaders()
        carrier.merge(headers) { _, new in new }
    }
    
    public func extract(from carrier: [String: String]) -> TraceContext? {
        TraceContext.fromW3CHeaders(carrier)
    }
}

// MARK: - Custom Trace Propagator

/// 自定义追踪传播器（用于非标准格式）
public struct CustomTracePropagator: TracePropagator {
    
    private let traceIdKey: String
    private let spanIdKey: String
    private let parentSpanIdKey: String
    private let sampledKey: String
    
    public init(
        traceIdKey: String = "X-Trace-ID",
        spanIdKey: String = "X-Span-ID",
        parentSpanIdKey: String = "X-Parent-Span-ID",
        sampledKey: String = "X-Sampled"
    ) {
        self.traceIdKey = traceIdKey
        self.spanIdKey = spanIdKey
        self.parentSpanIdKey = parentSpanIdKey
        self.sampledKey = sampledKey
    }
    
    public func inject(context: TraceContext, into carrier: inout [String: String]) {
        carrier[traceIdKey] = context.traceId
        carrier[spanIdKey] = context.spanId
        
        if let parentSpanId = context.parentSpanId {
            carrier[parentSpanIdKey] = parentSpanId
        }
        
        carrier[sampledKey] = context.sampled ? "1" : "0"
    }
    
    public func extract(from carrier: [String: String]) -> TraceContext? {
        guard let traceId = carrier[traceIdKey],
              let spanId = carrier[spanIdKey] else {
            return nil
        }
        
        let parentSpanId = carrier[parentSpanIdKey]
        let sampled = carrier[sampledKey] == "1"
        
        return TraceContext(
            traceId: traceId,
            spanId: spanId,
            parentSpanId: parentSpanId,
            sampled: sampled
        )
    }
}
