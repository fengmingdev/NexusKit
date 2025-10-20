//
//  LoggingPlugin.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 日志插件
///
/// 记录连接生命周期和数据传输日志。
public struct LoggingPlugin: NexusPlugin {
    
    // MARK: - Plugin Info
    
    public let name = "LoggingPlugin"
    public let version = "1.0.0"
    public var isEnabled: Bool
    
    // MARK: - Configuration
    
    /// 日志级别
    public let logLevel: NexusLogLevel
    
    /// 是否记录数据内容
    public let logDataContent: Bool
    
    /// 最大数据日志长度
    public let maxDataLogLength: Int
    
    // MARK: - Initialization
    
    /// 初始化日志插件
    public init(
        logLevel: NexusLogLevel = .info,
        logDataContent: Bool = false,
        maxDataLogLength: Int = 100,
        isEnabled: Bool = true
    ) {
        self.logLevel = logLevel
        self.logDataContent = logDataContent
        self.maxDataLogLength = maxDataLogLength
        self.isEnabled = isEnabled
    }
    
    // MARK: - Lifecycle Hooks
    
    public func willConnect(_ context: PluginContext) async throws {
        log(.info, "🔌 [WillConnect] \(context.connectionId) -> \(context.remoteHost ?? "unknown"):\(context.remotePort ?? 0)")
    }
    
    public func didConnect(_ context: PluginContext) async {
        log(.info, "✅ [DidConnect] \(context.connectionId) connected to \(context.remoteHost ?? "unknown"):\(context.remotePort ?? 0)")
    }
    
    public func willDisconnect(_ context: PluginContext) async {
        let duration = context.connectionDuration ?? 0
        log(.info, "🔌 [WillDisconnect] \(context.connectionId) (duration: \(String(format: "%.2f", duration))s, bytes: \(context.totalBytes))")
    }
    
    public func didDisconnect(_ context: PluginContext) async {
        log(.info, "❌ [DidDisconnect] \(context.connectionId) disconnected")
    }
    
    // MARK: - Data Hooks
    
    public func willSend(_ data: Data, context: PluginContext) async throws -> Data {
        if logDataContent {
            let preview = dataPreview(data)
            log(.debug, "📤 [WillSend] \(context.connectionId) sending \(data.count) bytes: \(preview)")
        } else {
            log(.debug, "📤 [WillSend] \(context.connectionId) sending \(data.count) bytes")
        }
        return data
    }
    
    public func didSend(_ data: Data, context: PluginContext) async {
        log(.verbose, "✓ [DidSend] \(context.connectionId) sent \(data.count) bytes")
    }
    
    public func willReceive(_ data: Data, context: PluginContext) async throws -> Data {
        if logDataContent {
            let preview = dataPreview(data)
            log(.debug, "📥 [WillReceive] \(context.connectionId) receiving \(data.count) bytes: \(preview)")
        } else {
            log(.debug, "📥 [WillReceive] \(context.connectionId) receiving \(data.count) bytes")
        }
        return data
    }
    
    public func didReceive(_ data: Data, context: PluginContext) async {
        log(.verbose, "✓ [DidReceive] \(context.connectionId) received \(data.count) bytes")
    }
    
    // MARK: - Error Hooks
    
    public func handleError(_ error: Error, context: PluginContext) async {
        log(.error, "⚠️ [Error] \(context.connectionId): \(error.localizedDescription)")
    }
    
    // MARK: - Private Methods
    
    /// 记录日志
    private func log(_ level: NexusLogLevel, _ message: String) {
        guard logLevel.shouldLog(level: level) else { return }
        print("[\(level.rawValue)] [LoggingPlugin] \(message)")
    }
    
    /// 数据预览
    private func dataPreview(_ data: Data) -> String {
        if data.count == 0 {
            return "<empty>"
        }
        
        let length = min(data.count, maxDataLogLength)
        let preview = data.prefix(length)
        
        // 尝试转换为字符串
        if let string = String(data: preview, encoding: .utf8) {
            let truncated = data.count > maxDataLogLength ? "..." : ""
            return "\"\(string)\"\(truncated)"
        }
        
        // 否则显示十六进制
        let hex = preview.map { String(format: "%02x", $0) }.joined(separator: " ")
        let truncated = data.count > maxDataLogLength ? "..." : ""
        return "0x\(hex)\(truncated)"
    }
}
