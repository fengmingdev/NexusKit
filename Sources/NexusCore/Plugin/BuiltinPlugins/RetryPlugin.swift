//
//  RetryPlugin.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 重试插件
///
/// 在特定错误发生时提供重试建议。
public actor RetryPlugin: NexusPlugin {
    
    // MARK: - Plugin Info
    
    public let name = "RetryPlugin"
    public let version = "1.0.0"
    private let _isEnabled: Bool
    public nonisolated var isEnabled: Bool { _isEnabled }
    
    // MARK: - Configuration
    
    /// 最大重试次数
    public let maxRetryCount: Int
    
    /// 初始重试延迟（秒）
    public let initialRetryDelay: TimeInterval
    
    /// 重试退避系数
    public let retryBackoffMultiplier: Double
    
    /// 可重试的错误类型
    public let retryableErrors: [String]
    
    // MARK: - State
    
    private var retryCounters: [String: Int] = [:]
    private var lastErrors: [String: Error] = [:]
    
    // MARK: - Delegate
    
    /// 重试代理
    public weak var delegate: RetryPluginDelegate?
    
    /// 设置代理
    public func setDelegate(_ delegate: RetryPluginDelegate?) {
        self.delegate = delegate
    }
    
    // MARK: - Initialization
    
    public init(
        maxRetryCount: Int = 3,
        initialRetryDelay: TimeInterval = 1.0,
        retryBackoffMultiplier: Double = 2.0,
        retryableErrors: [String] = [
            "connection",
            "timeout",
            "network",
            "temporary"
        ],
        isEnabled: Bool = true
    ) {
        self.maxRetryCount = maxRetryCount
        self.initialRetryDelay = initialRetryDelay
        self.retryBackoffMultiplier = retryBackoffMultiplier
        self.retryableErrors = retryableErrors
        self._isEnabled = isEnabled
    }
    
    // MARK: - Lifecycle Hooks
    
    public func didConnect(_ context: PluginContext) async {
        // 连接成功，重置重试计数器
        retryCounters[context.connectionId] = 0
        lastErrors.removeValue(forKey: context.connectionId)
    }
    
    public func didDisconnect(_ context: PluginContext) async {
        // 断开连接，清理状态
        retryCounters.removeValue(forKey: context.connectionId)
        lastErrors.removeValue(forKey: context.connectionId)
    }
    
    // MARK: - Error Hooks
    
    public func handleError(_ error: Error, context: PluginContext) async {
        lastErrors[context.connectionId] = error
        
        // 检查是否应该重试
        if shouldRetry(error: error, connectionId: context.connectionId) {
            let retryCount = retryCounters[context.connectionId] ?? 0
            let delay = calculateRetryDelay(retryCount: retryCount)
            
            print("🔄 [NexusKit] Error on \(context.connectionId): \(error.localizedDescription)")
            print("   Will retry in \(String(format: "%.2f", delay))s (attempt \(retryCount + 1)/\(maxRetryCount))")
            
            // 增加重试计数
            retryCounters[context.connectionId] = retryCount + 1
            
            // 通知代理
            if let delegate = delegate {
                await delegate.retryPlugin(self, shouldRetryConnection: context.connectionId, afterDelay: delay)
            }
        } else {
            print("❌ [NexusKit] Error on \(context.connectionId) is not retryable or exceeded max retries")
        }
    }
    
    // MARK: - Retry Logic
    
    /// 是否应该重试
    public func shouldRetry(error: Error, connectionId: String) -> Bool {
        // 检查重试次数
        let retryCount = retryCounters[connectionId] ?? 0
        guard retryCount < maxRetryCount else {
            return false
        }
        
        // 检查错误类型
        let errorDescription = error.localizedDescription.lowercased()
        return retryableErrors.contains { keyword in
            errorDescription.contains(keyword)
        }
    }
    
    /// 计算重试延迟
    public func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        return initialRetryDelay * pow(retryBackoffMultiplier, Double(retryCount))
    }
    
    /// 获取重试次数
    public func getRetryCount(_ connectionId: String) -> Int {
        retryCounters[connectionId] ?? 0
    }
    
    /// 获取最后的错误
    public func getLastError(_ connectionId: String) -> Error? {
        lastErrors[connectionId]
    }
    
    /// 重置重试计数器
    public func resetRetryCounter(_ connectionId: String) {
        retryCounters[connectionId] = 0
        lastErrors.removeValue(forKey: connectionId)
    }
    
    /// 清空所有状态
    public func clearAll() {
        retryCounters.removeAll()
        lastErrors.removeAll()
    }
}

// MARK: - Retry Plugin Delegate

/// 重试插件代理协议
///
/// 注意：根据用户偏好，使用代理模式进行组件间通信
public protocol RetryPluginDelegate: AnyObject, Sendable {
    
    /// 应该重试连接
    /// - Parameters:
    ///   - plugin: 重试插件
    ///   - connectionId: 连接 ID
    ///   - delay: 重试延迟
    func retryPlugin(_ plugin: RetryPlugin, shouldRetryConnection connectionId: String, afterDelay delay: TimeInterval) async
}
