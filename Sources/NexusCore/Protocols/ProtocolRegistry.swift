//
//  ProtocolRegistry.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Protocol Registry

/// 协议注册表 - 管理自定义协议的注册、查询和生命周期
public actor ProtocolRegistry {
    
    // MARK: - Singleton
    
    /// 全局共享实例
    public static let shared = ProtocolRegistry()
    
    // MARK: - Properties
    
    /// 注册的协议适配器（identifier -> adapter）
    private var adapters: [String: any ProtocolAdapter] = [:]
    
    /// 协议别名（alias -> identifier）
    private var aliases: [String: String] = [:]
    
    /// 协议版本映射（identifier -> versions）
    private var versions: [String: Set<String>] = [:]
    
    /// 默认协议标识符
    private var defaultProtocol: String?
    
    /// 统计信息
    private var statistics = RegistryStatistics()
    
    // MARK: - Initialization
    
    public init() {
        // 注册内置协议
        Task {
            await registerBuiltinProtocols()
        }
    }
    
    // MARK: - Registration
    
    /// 注册协议适配器
    /// - Parameters:
    ///   - adapter: 协议适配器
    ///   - identifier: 协议标识符（默认使用 adapter.name）
    ///   - aliases: 协议别名列表
    ///   - isDefault: 是否设为默认协议
    /// - Throws: 如果标识符已存在则抛出错误
    public func register(
        _ adapter: any ProtocolAdapter,
        identifier: String? = nil,
        aliases: [String] = [],
        isDefault: Bool = false
    ) throws {
        let id = identifier ?? adapter.name.lowercased()
        
        // 检查标识符是否已存在
        if adapters[id] != nil {
            throw ProtocolRegistryError.protocolAlreadyRegistered(id)
        }
        
        // 注册适配器
        adapters[id] = adapter
        
        // 记录版本
        var versionSet = versions[id] ?? []
        versionSet.insert(adapter.version)
        versions[id] = versionSet
        
        // 注册别名
        for alias in aliases {
            let lowercaseAlias = alias.lowercased()
            if self.aliases[lowercaseAlias] != nil {
                throw ProtocolRegistryError.aliasAlreadyExists(lowercaseAlias)
            }
            self.aliases[lowercaseAlias] = id
        }
        
        // 设置默认协议
        if isDefault || defaultProtocol == nil {
            defaultProtocol = id
        }
        
        statistics.registeredCount += 1
    }
    
    /// 注销协议适配器
    /// - Parameter identifier: 协议标识符
    public func unregister(_ identifier: String) {
        let id = identifier.lowercased()
        
        guard adapters.removeValue(forKey: id) != nil else { return }
        
        // 移除版本记录
        versions.removeValue(forKey: id)
        
        // 移除所有相关别名
        aliases = aliases.filter { $0.value != id }
        
        // 如果是默认协议，清除默认设置
        if defaultProtocol == id {
            defaultProtocol = adapters.keys.first
        }
        
        statistics.registeredCount -= 1
    }
    
    // MARK: - Query
    
    /// 获取协议适配器
    /// - Parameter identifier: 协议标识符或别名
    /// - Returns: 协议适配器，如果未找到则返回 nil
    public func get(_ identifier: String) -> (any ProtocolAdapter)? {
        let id = resolveIdentifier(identifier)
        return adapters[id]
    }
    
    /// 获取默认协议适配器
    /// - Returns: 默认协议适配器
    public func getDefault() throws -> any ProtocolAdapter {
        guard let id = defaultProtocol, let adapter = adapters[id] else {
            throw ProtocolRegistryError.noDefaultProtocol
        }
        return adapter
    }
    
    /// 设置默认协议
    /// - Parameter identifier: 协议标识符
    /// - Throws: 如果协议不存在则抛出错误
    public func setDefault(_ identifier: String) throws {
        let id = resolveIdentifier(identifier)
        guard adapters[id] != nil else {
            throw ProtocolRegistryError.protocolNotFound(identifier)
        }
        defaultProtocol = id
    }
    
    /// 检查协议是否已注册
    /// - Parameter identifier: 协议标识符或别名
    /// - Returns: 是否已注册
    public func contains(_ identifier: String) -> Bool {
        let id = resolveIdentifier(identifier)
        return adapters[id] != nil
    }
    
    /// 获取所有已注册的协议标识符
    /// - Returns: 协议标识符列表
    public func allProtocols() -> [String] {
        Array(adapters.keys)
    }
    
    /// 获取协议的所有版本
    /// - Parameter identifier: 协议标识符
    /// - Returns: 版本列表
    public func getVersions(for identifier: String) -> [String] {
        let id = resolveIdentifier(identifier)
        return Array(versions[id] ?? [])
    }
    
    // MARK: - Statistics
    
    /// 获取注册表统计信息
    public func getStatistics() -> RegistryStatistics {
        statistics
    }
    
    /// 增加使用计数
    public func recordUsage(for identifier: String) {
        let id = resolveIdentifier(identifier)
        statistics.usageCount[id, default: 0] += 1
    }
    
    // MARK: - Private Methods
    
    /// 解析标识符（处理别名）
    private func resolveIdentifier(_ identifier: String) -> String {
        let lowercaseId = identifier.lowercased()
        return aliases[lowercaseId] ?? lowercaseId
    }
    
    /// 注册内置协议
    private func registerBuiltinProtocols() async {
        // 默认实现为空，子类可以重写
    }
    
    // MARK: - Statistics
    
    /// 注册表统计信息
    public struct RegistryStatistics: Sendable {
        /// 已注册协议数量
        public var registeredCount: Int = 0
        
        /// 每个协议的使用次数
        public var usageCount: [String: Int] = [:]
        
        public init() {}
    }
}

// MARK: - Protocol Registry Error

/// 协议注册表错误
public enum ProtocolRegistryError: Error, Sendable {
    /// 协议已注册
    case protocolAlreadyRegistered(String)
    
    /// 协议未找到
    case protocolNotFound(String)
    
    /// 别名已存在
    case aliasAlreadyExists(String)
    
    /// 没有默认协议
    case noDefaultProtocol
    
    /// 无效的协议标识符
    case invalidIdentifier(String)
}

// MARK: - CustomStringConvertible

extension ProtocolRegistry: CustomStringConvertible {
    public nonisolated var description: String {
        "ProtocolRegistry()"
    }
}

extension ProtocolRegistryError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .protocolAlreadyRegistered(let id):
            return "Protocol already registered: \(id)"
        case .protocolNotFound(let id):
            return "Protocol not found: \(id)"
        case .aliasAlreadyExists(let alias):
            return "Alias already exists: \(alias)"
        case .noDefaultProtocol:
            return "No default protocol set"
        case .invalidIdentifier(let id):
            return "Invalid protocol identifier: \(id)"
        }
    }
}
