//
//  PluginContext.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//

import Foundation

/// 插件上下文
///
/// 提供插件执行时的上下文信息，包括连接信息、元数据等。
public struct PluginContext: Sendable {
    
    // MARK: - Connection Info
    
    /// 连接 ID
    public let connectionId: String
    
    /// 远程主机
    public let remoteHost: String?
    
    /// 远程端口
    public let remotePort: Int?
    
    /// 连接状态
    public let connectionState: String
    
    // MARK: - Metadata
    
    /// 元数据
    public var metadata: [String: String]
    
    /// 时间戳
    public let timestamp: Date
    
    // MARK: - Performance
    
    /// 已发送字节数
    public var bytesSent: Int
    
    /// 已接收字节数
    public var bytesReceived: Int
    
    /// 连接建立时间
    public let connectionStartTime: Date?
    
    // MARK: - Initialization
    
    /// 初始化插件上下文
    public init(
        connectionId: String,
        remoteHost: String? = nil,
        remotePort: Int? = nil,
        connectionState: String = "unknown",
        metadata: [String: String] = [:],
        timestamp: Date = Date(),
        bytesSent: Int = 0,
        bytesReceived: Int = 0,
        connectionStartTime: Date? = nil
    ) {
        self.connectionId = connectionId
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.connectionState = connectionState
        self.metadata = metadata
        self.timestamp = timestamp
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
        self.connectionStartTime = connectionStartTime
    }
    
    // MARK: - Metadata Operations
    
    /// 获取元数据
    public func get(_ key: String) -> String? {
        metadata[key]
    }
    
    /// 设置元数据
    public mutating func set(_ key: String, value: String) {
        metadata[key] = value
    }
    
    /// 移除元数据
    public mutating func remove(_ key: String) {
        metadata.removeValue(forKey: key)
    }
    
    // MARK: - Computed Properties
    
    /// 连接持续时间（秒）
    public var connectionDuration: TimeInterval? {
        guard let startTime = connectionStartTime else { return nil }
        return timestamp.timeIntervalSince(startTime)
    }
    
    /// 总传输字节数
    public var totalBytes: Int {
        bytesSent + bytesReceived
    }
}

// MARK: - CustomStringConvertible

extension PluginContext: CustomStringConvertible {
    public var description: String {
        """
        PluginContext(
            connectionId: \(connectionId),
            host: \(remoteHost ?? "unknown"):\(remotePort ?? 0),
            state: \(connectionState),
            metadata: \(metadata.count) items,
            bytes: \(totalBytes)
        )
        """
    }
}
