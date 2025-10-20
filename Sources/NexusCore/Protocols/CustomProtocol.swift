//
//  CustomProtocol.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Custom Protocol

/// 自定义协议接口 - 扩展协议适配器，支持协议协商和能力检测
public protocol CustomProtocol: ProtocolAdapter {
    
    /// 协议能力集合
    var capabilities: ProtocolCapabilities { get }
    
    /// 协议元数据
    var metadata: ProtocolMetadata { get }
    
    /// 协议优先级（用于协商时的选择）
    var priority: Int { get }
    
    /// 验证协议兼容性
    /// - Parameter otherProtocol: 另一个协议
    /// - Returns: 是否兼容
    func isCompatible(with otherProtocol: any CustomProtocol) async -> Bool
    
    /// 协商协议版本
    /// - Parameter versions: 支持的版本列表
    /// - Returns: 选定的版本，如果无法协商则返回 nil
    func negotiateVersion(with versions: [String]) async -> String?
    
    /// 升级到新协议
    /// - Parameter protocol: 目标协议
    /// - Returns: 是否成功升级
    func upgradeTo(_ protocol: any CustomProtocol) async throws -> Bool
    
    /// 协议特定的配置
    func configure(with options: [String: Any]) async throws
}

// MARK: - Protocol Capabilities

/// 协议能力集合
public struct ProtocolCapabilities: Sendable, OptionSet {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    /// 支持压缩
    public static let compression = ProtocolCapabilities(rawValue: 1 << 0)
    
    /// 支持加密
    public static let encryption = ProtocolCapabilities(rawValue: 1 << 1)
    
    /// 支持心跳
    public static let heartbeat = ProtocolCapabilities(rawValue: 1 << 2)
    
    /// 支持分片
    public static let fragmentation = ProtocolCapabilities(rawValue: 1 << 3)
    
    /// 支持流式传输
    public static let streaming = ProtocolCapabilities(rawValue: 1 << 4)
    
    /// 支持双向通信
    public static let bidirectional = ProtocolCapabilities(rawValue: 1 << 5)
    
    /// 支持多路复用
    public static let multiplexing = ProtocolCapabilities(rawValue: 1 << 6)
    
    /// 支持优先级
    public static let prioritization = ProtocolCapabilities(rawValue: 1 << 7)
    
    /// 支持确认机制
    public static let acknowledgement = ProtocolCapabilities(rawValue: 1 << 8)
    
    /// 支持版本协商
    public static let versionNegotiation = ProtocolCapabilities(rawValue: 1 << 9)
    
    /// 所有能力
    public static let all: ProtocolCapabilities = [
        .compression, .encryption, .heartbeat, .fragmentation,
        .streaming, .bidirectional, .multiplexing, .prioritization,
        .acknowledgement, .versionNegotiation
    ]
}

// MARK: - Protocol Metadata

/// 协议元数据
public struct ProtocolMetadata: Sendable {
    /// 协议描述
    public let description: String
    
    /// 协议作者
    public let author: String
    
    /// 协议创建日期
    public let createdAt: Date
    
    /// 协议最后更新日期
    public let updatedAt: Date
    
    /// 协议文档 URL
    public let documentationURL: String?
    
    /// 协议许可证
    public let license: String?
    
    /// 自定义标签
    public let tags: [String]
    
    /// 自定义属性
    public let customProperties: [String: String]
    
    public init(
        description: String,
        author: String = "NexusKit",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        documentationURL: String? = nil,
        license: String? = nil,
        tags: [String] = [],
        customProperties: [String: String] = [:]
    ) {
        self.description = description
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.documentationURL = documentationURL
        self.license = license
        self.tags = tags
        self.customProperties = customProperties
    }
}

// MARK: - Default Implementations

public extension CustomProtocol {
    var priority: Int { 0 }
    
    func isCompatible(with otherProtocol: any CustomProtocol) async -> Bool {
        // 默认实现：名称相同即兼容
        return name.lowercased() == otherProtocol.name.lowercased()
    }
    
    func negotiateVersion(with versions: [String]) async -> String? {
        // 默认实现：返回自己的版本（如果对方支持）
        return versions.contains(version) ? version : nil
    }
    
    func upgradeTo(_ protocol: any CustomProtocol) async throws -> Bool {
        // 默认实现：不支持升级
        return false
    }
    
    func configure(with options: [String: Any]) async throws {
        // 默认实现：无配置
    }
}

// MARK: - Protocol Info

/// 协议信息（用于协议发现和协商）
public struct ProtocolInfo: Sendable, Codable {
    /// 协议标识符
    public let identifier: String
    
    /// 协议名称
    public let name: String
    
    /// 协议版本
    public let version: String
    
    /// 支持的版本列表
    public let supportedVersions: [String]
    
    /// 协议能力（以数字表示）
    public let capabilities: UInt32
    
    /// 协议优先级
    public let priority: Int
    
    /// 协议元数据
    public let metadata: [String: String]
    
    public init(
        identifier: String,
        name: String,
        version: String,
        supportedVersions: [String],
        capabilities: UInt32,
        priority: Int,
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.supportedVersions = supportedVersions
        self.capabilities = capabilities
        self.priority = priority
        self.metadata = metadata
    }
    
    /// 从自定义协议创建
    public init(from protocol: any CustomProtocol, supportedVersions: [String] = []) {
        self.identifier = `protocol`.name.lowercased()
        self.name = `protocol`.name
        self.version = `protocol`.version
        self.supportedVersions = supportedVersions.isEmpty ? [`protocol`.version] : supportedVersions
        self.capabilities = `protocol`.capabilities.rawValue
        self.priority = `protocol`.priority
        self.metadata = `protocol`.metadata.customProperties
    }
}
