//
//  PluginManager.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 插件管理器
///
/// 管理插件的注册、查询和执行。
///
/// 使用示例:
/// ```swift
/// let manager = PluginManager()
/// manager.register(LoggingPlugin())
/// manager.register(MetricsPlugin())
/// 
/// // 执行生命周期钩子
/// await manager.invokeWillConnect(context)
/// 
/// // 执行数据处理
/// let processedData = try await manager.processWillSend(data, context: context)
/// ```
public actor PluginManager {
    
    // MARK: - Properties
    
    /// 已注册的插件（按优先级排序）
    private var plugins: [(plugin: any NexusPlugin, priority: PluginPriority)] = []
    
    /// 插件名称索引
    private var pluginIndex: [String: Int] = [:]
    
    /// 是否启用插件系统
    public var isEnabled: Bool = true
    
    /// 设置插件系统启用状态
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    // MARK: - Statistics
    
    /// 统计信息
    private var stats = Statistics()
    
    private struct Statistics {
        var totalHooksInvoked: Int = 0
        var totalDataProcessed: Int = 0
        var totalErrors: Int = 0
        var pluginExecutionTimes: [String: TimeInterval] = [:]
    }
    
    // MARK: - Initialization
    
    /// 初始化插件管理器
    public init() {}
    
    // MARK: - Plugin Registration
    
    /// 注册插件
    /// - Parameters:
    ///   - plugin: 要注册的插件
    ///   - priority: 插件优先级（默认 normal）
    /// - Throws: 如果插件已存在则抛出错误
    public func register(_ plugin: any NexusPlugin, priority: PluginPriority = .normal) throws {
        // 检查是否已注册
        if pluginIndex[plugin.name] != nil {
            throw PluginError.pluginAlreadyRegistered(plugin.name)
        }
        
        // 添加到列表
        plugins.append((plugin, priority))
        
        // 按优先级排序（高优先级在前）
        plugins.sort { $0.priority > $1.priority }
        
        // 重建索引
        rebuildIndex()
    }
    
    /// 注销插件
    /// - Parameter name: 插件名称
    /// - Returns: 是否成功注销
    @discardableResult
    public func unregister(_ name: String) -> Bool {
        guard let index = pluginIndex[name] else {
            return false
        }
        
        plugins.remove(at: index)
        rebuildIndex()
        
        return true
    }
    
    /// 清空所有插件
    public func clear() {
        plugins.removeAll()
        pluginIndex.removeAll()
        stats = Statistics()
    }
    
    // MARK: - Plugin Query
    
    /// 获取插件
    /// - Parameter name: 插件名称
    /// - Returns: 插件实例，如果不存在返回 nil
    public func get(_ name: String) -> (any NexusPlugin)? {
        guard let index = pluginIndex[name] else {
            return nil
        }
        return plugins[index].plugin
    }
    
    /// 是否包含插件
    public func contains(_ name: String) -> Bool {
        pluginIndex[name] != nil
    }
    
    /// 已注册的插件数量
    public var count: Int {
        plugins.count
    }
    
    /// 所有插件名称
    public var names: [String] {
        plugins.map { $0.plugin.name }
    }
    
    /// 启用的插件数量
    public var enabledCount: Int {
        plugins.filter { $0.plugin.isEnabled }.count
    }
    
    // MARK: - Lifecycle Invocation
    
    /// 调用 willConnect 钩子
    public func invokeWillConnect(_ context: PluginContext) async throws {
        guard isEnabled else { return }
        
        for (plugin, _) in plugins where plugin.isEnabled {
            let start = Date()
            do {
                try await plugin.willConnect(context)
                recordExecution(plugin: plugin.name, duration: Date().timeIntervalSince(start))
            } catch {
                stats.totalErrors += 1
                throw PluginError.pluginExecutionFailed(plugin.name, error)
            }
        }
        
        stats.totalHooksInvoked += 1
    }
    
    /// 调用 didConnect 钩子
    public func invokeDidConnect(_ context: PluginContext) async {
        guard isEnabled else { return }
        
        for (plugin, _) in plugins where plugin.isEnabled {
            let start = Date()
            await plugin.didConnect(context)
            recordExecution(plugin: plugin.name, duration: Date().timeIntervalSince(start))
        }
        
        stats.totalHooksInvoked += 1
    }
    
    /// 调用 willDisconnect 钩子
    public func invokeWillDisconnect(_ context: PluginContext) async {
        guard isEnabled else { return }
        
        for (plugin, _) in plugins where plugin.isEnabled {
            let start = Date()
            await plugin.willDisconnect(context)
            recordExecution(plugin: plugin.name, duration: Date().timeIntervalSince(start))
        }
        
        stats.totalHooksInvoked += 1
    }
    
    /// 调用 didDisconnect 钩子
    public func invokeDidDisconnect(_ context: PluginContext) async {
        guard isEnabled else { return }
        
        for (plugin, _) in plugins where plugin.isEnabled {
            let start = Date()
            await plugin.didDisconnect(context)
            recordExecution(plugin: plugin.name, duration: Date().timeIntervalSince(start))
        }
        
        stats.totalHooksInvoked += 1
    }
    
    // MARK: - Data Processing
    
    /// 处理即将发送的数据（插件链）
    public func processWillSend(_ data: Data, context: PluginContext) async throws -> Data {
        guard isEnabled else { return data }
        
        var processedData = data
        
        for (plugin, _) in plugins where plugin.isEnabled {
            let start = Date()
            do {
                processedData = try await plugin.willSend(processedData, context: context)
                recordExecution(plugin: plugin.name, duration: Date().timeIntervalSince(start))
            } catch {
                stats.totalErrors += 1
                throw PluginError.pluginExecutionFailed(plugin.name, error)
            }
        }
        
        stats.totalDataProcessed += 1
        return processedData
    }
    
    /// 通知数据已发送
    public func notifyDidSend(_ data: Data, context: PluginContext) async {
        guard isEnabled else { return }
        
        for (plugin, _) in plugins where plugin.isEnabled {
            let start = Date()
            await plugin.didSend(data, context: context)
            recordExecution(plugin: plugin.name, duration: Date().timeIntervalSince(start))
        }
    }
    
    /// 处理即将接收的数据（插件链）
    public func processWillReceive(_ data: Data, context: PluginContext) async throws -> Data {
        guard isEnabled else { return data }
        
        var processedData = data
        
        for (plugin, _) in plugins where plugin.isEnabled {
            let start = Date()
            do {
                processedData = try await plugin.willReceive(processedData, context: context)
                recordExecution(plugin: plugin.name, duration: Date().timeIntervalSince(start))
            } catch {
                stats.totalErrors += 1
                throw PluginError.pluginExecutionFailed(plugin.name, error)
            }
        }
        
        stats.totalDataProcessed += 1
        return processedData
    }
    
    /// 通知数据已接收
    public func notifyDidReceive(_ data: Data, context: PluginContext) async {
        guard isEnabled else { return }
        
        for (plugin, _) in plugins where plugin.isEnabled {
            let start = Date()
            await plugin.didReceive(data, context: context)
            recordExecution(plugin: plugin.name, duration: Date().timeIntervalSince(start))
        }
    }
    
    // MARK: - Error Handling
    
    /// 通知错误
    public func notifyError(_ error: Error, context: PluginContext) async {
        guard isEnabled else { return }
        
        for (plugin, _) in plugins where plugin.isEnabled {
            await plugin.handleError(error, context: context)
        }
        
        stats.totalErrors += 1
    }
    
    // MARK: - Statistics
    
    /// 获取统计信息
    public func getStatistics() -> (
        hooksInvoked: Int,
        dataProcessed: Int,
        errorsHandled: Int,
        executionTimes: [String: TimeInterval]
    ) {
        (
            hooksInvoked: stats.totalHooksInvoked,
            dataProcessed: stats.totalDataProcessed,
            errorsHandled: stats.totalErrors,
            executionTimes: stats.pluginExecutionTimes
        )
    }
    
    /// 重置统计信息
    public func resetStatistics() {
        stats = Statistics()
    }
    
    // MARK: - Private Methods
    
    /// 重建索引
    private func rebuildIndex() {
        pluginIndex.removeAll()
        for (index, (plugin, _)) in plugins.enumerated() {
            pluginIndex[plugin.name] = index
        }
    }
    
    /// 记录执行时间
    private func recordExecution(plugin name: String, duration: TimeInterval) {
        let current = stats.pluginExecutionTimes[name] ?? 0
        stats.pluginExecutionTimes[name] = current + duration
    }
}

// MARK: - CustomStringConvertible

extension PluginManager: CustomStringConvertible {
    public nonisolated var description: String {
        "PluginManager()"
    }
}
