//
//  NexusKit.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - NexusKit Main Class

/// NexusKit 主类 - 统一入口
@MainActor
public final class NexusKit {
    /// 共享实例
    public static let shared = NexusKit()

    /// 全局配置
    public var configuration = GlobalConfiguration()

    /// 连接管理器
    private let connectionManager: ConnectionManager

    private init() {
        self.connectionManager = ConnectionManager()
    }

    // MARK: - Connection Builder

    /// 创建连接构建器
    /// - Parameter endpoint: 连接端点
    /// - Returns: 连接构建器
    public func connection(to endpoint: Endpoint) -> ConnectionBuilder {
        ConnectionBuilder(
            endpoint: endpoint,
            manager: connectionManager,
            globalConfig: configuration
        )
    }

    // MARK: - Connection Management

    /// 获取指定连接
    /// - Parameter id: 连接 ID
    /// - Returns: 连接实例
    public func connection(id: String) async -> (any Connection)? {
        await connectionManager.connection(id: id)
    }

    /// 获取所有活跃连接
    public func activeConnections() async -> [any Connection] {
        await connectionManager.activeConnections()
    }

    /// 断开所有连接
    public func disconnectAll() async {
        await connectionManager.disconnectAll()
    }

    /// 断开指定连接
    /// - Parameter id: 连接 ID
    public func disconnect(id: String, reason: DisconnectReason = .clientInitiated) async {
        await connectionManager.disconnect(id: id, reason: reason)
    }

    // MARK: - Statistics

    /// 获取连接统计信息
    public func statistics() async -> ConnectionStatistics {
        await connectionManager.statistics()
    }
}

// MARK: - Global Configuration

/// 全局配置
public struct GlobalConfiguration: Sendable {
    /// 默认连接超时（秒）
    public var defaultConnectTimeout: TimeInterval = 30

    /// 默认读写超时（秒）
    public var defaultReadWriteTimeout: TimeInterval = 60

    /// 默认重连策略
    public var defaultReconnectionStrategy: (any ReconnectionStrategy)?

    /// 最大并发连接数
    public var maxConcurrentConnections: Int = 100

    /// 是否启用性能指标
    public var enableMetrics: Bool = false

    /// 日志级别
    public var logLevel: LogLevel = .info

    /// 默认心跳间隔（秒）
    public var defaultHeartbeatInterval: TimeInterval = 30

    /// 默认心跳超时（秒）
    public var defaultHeartbeatTimeout: TimeInterval = 90

    public init() {
        // 默认使用指数退避重连策略
        self.defaultReconnectionStrategy = ExponentialBackoffStrategy()
    }
}

// MARK: - Log Level

/// 日志级别
public enum LogLevel: Int, Sendable, Comparable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case none = 5

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Connection Statistics

/// 连接统计信息
public struct ConnectionStatistics: Sendable {
    /// 总连接数
    public let totalConnections: Int

    /// 活跃连接数
    public let activeConnections: Int

    /// 总发送字节数
    public let totalBytesSent: Int64

    /// 总接收字节数
    public let totalBytesReceived: Int64

    /// 总发送消息数
    public let totalMessagesSent: Int64

    /// 总接收消息数
    public let totalMessagesReceived: Int64

    /// 平均连接时长（秒）
    public let averageConnectionDuration: TimeInterval

    /// 重连次数
    public let reconnectionCount: Int

    public init(
        totalConnections: Int = 0,
        activeConnections: Int = 0,
        totalBytesSent: Int64 = 0,
        totalBytesReceived: Int64 = 0,
        totalMessagesSent: Int64 = 0,
        totalMessagesReceived: Int64 = 0,
        averageConnectionDuration: TimeInterval = 0,
        reconnectionCount: Int = 0
    ) {
        self.totalConnections = totalConnections
        self.activeConnections = activeConnections
        self.totalBytesSent = totalBytesSent
        self.totalBytesReceived = totalBytesReceived
        self.totalMessagesSent = totalMessagesSent
        self.totalMessagesReceived = totalMessagesReceived
        self.averageConnectionDuration = averageConnectionDuration
        self.reconnectionCount = reconnectionCount
    }
}
