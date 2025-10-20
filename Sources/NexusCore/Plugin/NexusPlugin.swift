//
//  NexusPlugin.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 插件协议
///
/// 定义插件的基本接口和生命周期钩子。
///
/// 使用示例:
/// ```swift
/// struct MyPlugin: NexusPlugin {
///     let name = "MyPlugin"
///     let version = "1.0.0"
///     
///     func didConnect(_ context: PluginContext) async {
///         print("Connected: \(context.connectionId)")
///     }
/// }
/// ```
public protocol NexusPlugin: Sendable {
    
    // MARK: - Plugin Info
    
    /// 插件名称
    var name: String { get }
    
    /// 插件版本
    var version: String { get }
    
    /// 插件描述
    var description: String { get }
    
    /// 是否启用
    var isEnabled: Bool { get }
    
    // MARK: - Lifecycle Hooks
    
    /// 连接即将建立
    /// - Parameter context: 插件上下文
    /// - Throws: 如果返回错误，连接将被中止
    func willConnect(_ context: PluginContext) async throws
    
    /// 连接已建立
    /// - Parameter context: 插件上下文
    func didConnect(_ context: PluginContext) async
    
    /// 连接即将断开
    /// - Parameter context: 插件上下文
    func willDisconnect(_ context: PluginContext) async
    
    /// 连接已断开
    /// - Parameter context: 插件上下文
    func didDisconnect(_ context: PluginContext) async
    
    // MARK: - Data Hooks
    
    /// 数据即将发送
    /// - Parameters:
    ///   - data: 原始数据
    ///   - context: 插件上下文
    /// - Returns: 处理后的数据
    /// - Throws: 如果返回错误，数据将不会被发送
    func willSend(_ data: Data, context: PluginContext) async throws -> Data
    
    /// 数据已发送
    /// - Parameters:
    ///   - data: 发送的数据
    ///   - context: 插件上下文
    func didSend(_ data: Data, context: PluginContext) async
    
    /// 数据即将接收
    /// - Parameters:
    ///   - data: 接收的原始数据
    ///   - context: 插件上下文
    /// - Returns: 处理后的数据
    /// - Throws: 如果返回错误，数据将被丢弃
    func willReceive(_ data: Data, context: PluginContext) async throws -> Data
    
    /// 数据已接收
    /// - Parameters:
    ///   - data: 接收的数据
    ///   - context: 插件上下文
    func didReceive(_ data: Data, context: PluginContext) async
    
    // MARK: - Error Hooks
    
    /// 处理错误
    /// - Parameters:
    ///   - error: 发生的错误
    ///   - context: 插件上下文
    func handleError(_ error: Error, context: PluginContext) async
}

// MARK: - Default Implementation

extension NexusPlugin {
    
    /// 默认描述
    public var description: String {
        "\(name) v\(version)"
    }
    
    /// 默认启用
    public var isEnabled: Bool {
        true
    }
    
    // MARK: - Default Lifecycle Implementations
    
    public func willConnect(_ context: PluginContext) async throws {
        // 默认不做任何操作
    }
    
    public func didConnect(_ context: PluginContext) async {
        // 默认不做任何操作
    }
    
    public func willDisconnect(_ context: PluginContext) async {
        // 默认不做任何操作
    }
    
    public func didDisconnect(_ context: PluginContext) async {
        // 默认不做任何操作
    }
    
    // MARK: - Default Data Implementations
    
    public func willSend(_ data: Data, context: PluginContext) async throws -> Data {
        // 默认直接返回原数据
        return data
    }
    
    public func didSend(_ data: Data, context: PluginContext) async {
        // 默认不做任何操作
    }
    
    public func willReceive(_ data: Data, context: PluginContext) async throws -> Data {
        // 默认直接返回原数据
        return data
    }
    
    public func didReceive(_ data: Data, context: PluginContext) async {
        // 默认不做任何操作
    }
    
    // MARK: - Default Error Implementation
    
    public func handleError(_ error: Error, context: PluginContext) async {
        // 默认不做任何操作
    }
}

// MARK: - Plugin Priority

/// 插件优先级
public enum PluginPriority: Int, Sendable, Comparable {
    case lowest = 0
    case low = 25
    case normal = 50
    case high = 75
    case highest = 100
    
    public static func < (lhs: PluginPriority, rhs: PluginPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Plugin Error

/// 插件错误
public enum PluginError: Error, Sendable {
    case pluginNotFound(String)
    case pluginAlreadyRegistered(String)
    case pluginDisabled(String)
    case pluginExecutionFailed(String, Error)
    case invalidPluginChain
    
    public var localizedDescription: String {
        switch self {
        case .pluginNotFound(let name):
            return "Plugin not found: \(name)"
        case .pluginAlreadyRegistered(let name):
            return "Plugin already registered: \(name)"
        case .pluginDisabled(let name):
            return "Plugin is disabled: \(name)"
        case .pluginExecutionFailed(let name, let error):
            return "Plugin '\(name)' execution failed: \(error.localizedDescription)"
        case .invalidPluginChain:
            return "Invalid plugin chain configuration"
        }
    }
}
