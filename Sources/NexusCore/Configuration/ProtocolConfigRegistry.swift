//
//  ProtocolConfigRegistry.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 协议配置注册表
///
/// 管理不同协议的配置，支持协议级别的自定义配置。
public final class ProtocolConfigRegistry: Sendable {
    
    // MARK: - Properties
    
    /// 协议配置存储
    private let configs: ThreadSafeBox<[String: ProtocolConfig]>
    
    // MARK: - Initialization
    
    /// 初始化注册表
    public init(configs: [String: ProtocolConfig] = [:]) {
        self.configs = ThreadSafeBox(configs)
    }
    
    // MARK: - Registration
    
    /// 注册协议配置
    /// - Parameters:
    ///   - config: 协议配置
    ///   - name: 协议名称
    public func register(_ config: ProtocolConfig, for name: String) {
        configs.modify { dict in
            dict[name] = config
        }
    }
    
    /// 获取协议配置
    /// - Parameter name: 协议名称
    /// - Returns: 协议配置，如果不存在返回 nil
    public func get(_ name: String) -> ProtocolConfig? {
        configs.value[name]
    }
    
    /// 移除协议配置
    /// - Parameter name: 协议名称
    public func unregister(_ name: String) {
        configs.modify { dict in
            dict.removeValue(forKey: name)
        }
    }
    
    /// 清空所有配置
    public func clear() {
        configs.modify { dict in
            dict.removeAll()
        }
    }
    
    // MARK: - Query
    
    /// 已注册的协议数量
    public var registeredCount: Int {
        configs.value.count
    }
    
    /// 所有已注册的协议名称
    public var registeredNames: [String] {
        Array(configs.value.keys)
    }
    
    /// 是否包含指定协议
    public func contains(_ name: String) -> Bool {
        configs.value[name] != nil
    }
    
    // MARK: - Defaults
    
    /// 默认注册表 (包含常用协议配置)
    public static let `default`: ProtocolConfigRegistry = {
        let registry = ProtocolConfigRegistry()
        
        // TCP 协议配置
        registry.register(ProtocolConfig(
            name: "tcp",
            version: "1.0",
            options: [
                "keepAlive": true,
                "noDelay": true
            ]
        ), for: "tcp")
        
        // WebSocket 协议配置
        registry.register(ProtocolConfig(
            name: "websocket",
            version: "13",
            options: [
                "compression": true,
                "maxFrameSize": 16384
            ]
        ), for: "websocket")
        
        // Socket.IO 协议配置
        registry.register(ProtocolConfig(
            name: "socket.io",
            version: "4",
            options: [
                "transports": ["websocket", "polling"],
                "upgrade": true,
                "rememberUpgrade": false
            ]
        ), for: "socket.io")
        
        return registry
    }()
    
    // MARK: - Validation
    
    /// 验证所有协议配置
    public func validate() throws {
        for (name, config) in configs.value {
            try config.validate()
        }
    }
}

// MARK: - Protocol Config

/// 协议配置
public struct ProtocolConfig: @unchecked Sendable {

    /// 协议名称
    public let name: String

    /// 协议版本
    public let version: String

    /// 协议选项
    public var options: [String: Any]
    
    /// 初始化协议配置
    public init(name: String, version: String, options: [String: Any] = [:]) {
        self.name = name
        self.version = version
        self.options = options
    }
    
    /// 获取选项值
    public func option<T>(_ key: String) -> T? {
        options[key] as? T
    }
    
    /// 设置选项值
    public mutating func setOption<T>(_ key: String, value: T) {
        options[key] = value
    }
    
    /// 验证配置
    public func validate() throws {
        guard !name.isEmpty else {
            throw ConfigurationError.invalidProtocolName(name)
        }
    }
}

// MARK: - Thread-Safe Box

/// 线程安全容器
private final class ThreadSafeBox<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()
    
    init(_ value: T) {
        self._value = value
    }
    
    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    
    func modify(_ block: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        block(&_value)
    }
}

// MARK: - CustomStringConvertible

extension ProtocolConfigRegistry: CustomStringConvertible {
    public var description: String {
        "ProtocolConfigRegistry(registered: \(registeredCount), protocols: \(registeredNames))"
    }
}

extension ProtocolConfig: CustomStringConvertible {
    public var description: String {
        "ProtocolConfig(name: \(name), version: \(version), options: \(options.count))"
    }
}
