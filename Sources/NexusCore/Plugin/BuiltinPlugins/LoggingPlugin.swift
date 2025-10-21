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
        log("🔌 [WillConnect] \(context.connectionId) -> \(context.remoteHost ?? "unknown"):\(context.remotePort ?? 0)", level: .info)
    }
    
    public func didConnect(_ context: PluginContext) async {
        log("✅ [DidConnect] \(context.connectionId) connected to \(context.remoteHost ?? "unknown"):\(context.remotePort ?? 0)", level: .info)
    }
    
    public func willDisconnect(_ context: PluginContext) async {
        let duration = context.connectionDuration ?? 0
        log("🔌 [WillDisconnect] \(context.connectionId) (duration: \(String(format: "%.2f", duration))s, bytes: \(context.totalBytes))", level: .info)
    }
    
    public func didDisconnect(_ context: PluginContext) async {
        log("❌ [DidDisconnect] \(context.connectionId) disconnected", level: .info)
    }
    
    // MARK: - Data Hooks
    
    public func willSend(_ data: Data, context: PluginContext) async throws -> Data {
        if logDataContent {
            let preview = dataPreview(data)
            log("📤 [WillSend] \(context.connectionId) sending \(data.count) bytes: \(preview)", level: .debug)
        } else {
            log("📤 [WillSend] \(context.connectionId) sending \(data.count) bytes", level: .debug)
        }
        return data
    }
    
    public func didSend(_ data: Data, context: PluginContext) async {
        log("✓ [DidSend] \(context.connectionId) sent \(data.count) bytes", level: .verbose)
    }
    
    public func willReceive(_ data: Data, context: PluginContext) async throws -> Data {
        if logDataContent {
            let preview = dataPreview(data)
            log("📥 [WillReceive] \(context.connectionId) receiving \(data.count) bytes: \(preview)", level: .debug)
        } else {
            log("📥 [WillReceive] \(context.connectionId) receiving \(data.count) bytes", level: .debug)
        }
        return data
    }
    
    public func didReceive(_ data: Data, context: PluginContext) async {
        log("✓ [DidReceive] \(context.connectionId) received \(data.count) bytes", level: .verbose)
    }
    
    // MARK: - Error Hooks
    
    public func handleError(_ error: Error, context: PluginContext) async {
        log("⚠️ [Error] \(context.connectionId): \(error.localizedDescription)", level: .error)
    }
    
    // MARK: - Private Methods
    
    /// 记录日志
    private func log(_ message: String, level: NexusLogLevel = .info) {
        guard isEnabled && logLevel.shouldLog(level: level) else { return }
        print("[NexusKit] [\(level.rawValue)] \(message)")
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
