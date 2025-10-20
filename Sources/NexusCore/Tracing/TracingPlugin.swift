//
//  TracingPlugin.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Tracing Plugin

/// 追踪插件 - 集成分布式追踪到 NexusKit 插件系统
public actor TracingPlugin: NexusPlugin {
    
    // MARK: - Properties
    
    public let name = "TracingPlugin"
    public let version = "1.0.0"
    private let _isEnabled: Bool
    public nonisolated var isEnabled: Bool { _isEnabled }
    
    private let spanManager: SpanManager
    private let propagator: TracePropagator
    private var activeSpans: [String: Span] = [:] // connectionId -> Span
    
    // MARK: - Initialization
    
    public init(
        isEnabled: Bool = true,
        spanManager: SpanManager = .shared,
        propagator: TracePropagator = W3CTracePropagator()
    ) {
        self._isEnabled = isEnabled
        self.spanManager = spanManager
        self.propagator = propagator
    }
    
    // MARK: - NexusPlugin - Lifecycle
    
    public func willConnect(_ context: PluginContext) async throws {
        guard isEnabled else { return }
        
        // 创建连接 Span
        let endpoint = context.remoteHost.map { "\($0):\(context.remotePort ?? 0)" } ?? "unknown"
        let span = await spanManager.startSpan(
            name: "connection.establish",
            kind: .client,
            attributes: [
                "connection.id": .string(context.connectionId),
                "endpoint": .string(endpoint)
            ]
        )
        
        activeSpans[context.connectionId] = span
        
        // 注入追踪上下文到元数据
        var headers: [String: String] = [:]
        propagator.inject(context: span.context, into: &headers)
        
        // TODO: 将 headers 传播到连接握手中
    }
    
    public func didConnect(_ context: PluginContext) async {
        guard isEnabled else { return }
        
        // 连接建立成功，添加事件
        if let span = activeSpans[context.connectionId] {
            span.addEvent("connection.established")
            span.setStatus(.ok)
            await spanManager.endSpan(span)
        }
    }
    
    public func willDisconnect(_ context: PluginContext) async {
        guard isEnabled else { return }
        
        // 创建断开连接 Span
        let span = await spanManager.startSpan(
            name: "connection.disconnect",
            kind: .client,
            attributes: [
                "connection.id": .string(context.connectionId)
            ]
        )
        
        span.addEvent("disconnect.initiated")
        await spanManager.endSpan(span)
    }
    
    public func didDisconnect(_ context: PluginContext) async {
        guard isEnabled else { return }
        
        // 清理活跃 Span
        activeSpans.removeValue(forKey: context.connectionId)
    }
    
    // MARK: - NexusPlugin - Data
    
    public func willSend(_ data: Data, context: PluginContext) async throws -> Data {
        guard isEnabled else { return data }
        
        // 创建发送 Span
        let span = await spanManager.startSpan(
            name: "message.send",
            kind: .producer,
            attributes: [
                "connection.id": .string(context.connectionId),
                "message.size": .int(Int64(data.count))
            ]
        )
        
        span.addEvent("message.encode")
        await spanManager.endSpan(span)
        
        return data
    }
    
    public func didSend(_ data: Data, context: PluginContext) async {
        // 可以记录发送完成事件
    }
    
    public func willReceive(_ data: Data, context: PluginContext) async throws -> Data {
        guard isEnabled else { return data }
        
        // 创建接收 Span
        let span = await spanManager.startSpan(
            name: "message.receive",
            kind: .consumer,
            attributes: [
                "connection.id": .string(context.connectionId),
                "message.size": .int(Int64(data.count))
            ]
        )
        
        span.addEvent("message.decode")
        await spanManager.endSpan(span)
        
        return data
    }
    
    public func didReceive(_ data: Data, context: PluginContext) async {
        // 可以记录接收完成事件
    }
    
    // MARK: - NexusPlugin - Error
    
    public func handleError(_ error: Error, context: PluginContext) async {
        guard isEnabled else { return }
        
        // 如果有活跃 Span，标记为错误
        if let span = activeSpans[context.connectionId] {
            span.setStatus(.error)
            span.setAttribute(key: "error.type", value: .string(String(describing: type(of: error))))
            span.setAttribute(key: "error.message", value: .string(error.localizedDescription))
            await spanManager.endSpan(span)
        }
    }
    
    // MARK: - Public Methods
    
    /// 获取活跃追踪
    public func getActiveTraces() -> [String: Span] {
        activeSpans
    }
    
    /// 导出追踪数据
    public func flush() async {
        await spanManager.flush()
    }
}
