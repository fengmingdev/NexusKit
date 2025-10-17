//
//  ConnectionManager.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Connection Manager

/// 连接管理器 - 管理所有连接的生命周期
actor ConnectionManager {
    // MARK: - Properties

    /// 连接存储 [id: Connection]
    private var connections: [String: any Connection] = [:]

    /// 连接元数据 [id: ConnectionMetadata]
    private var metadata: [String: ConnectionMetadata] = [:]

    /// 统计信息
    private var stats = ConnectionStatistics()

    /// 最大连接数
    private let maxConnections: Int

    // MARK: - Initialization

    init(maxConnections: Int = 100) {
        self.maxConnections = maxConnections
    }

    // MARK: - Connection Creation

    /// 创建连接
    /// - Parameters:
    ///   - endpoint: 连接端点
    ///   - configuration: 连接配置
    /// - Returns: 连接实例
    /// - Throws: 创建失败时抛出错误
    // MARK: - Connection Creation

    /// 注册连接
    ///
    /// 由 ConnectionFactory 调用此方法来注册已创建的连接。
    ///
    /// - Parameters:
    ///   - connection: 已创建的连接实例
    ///   - endpoint: 连接端点
    ///   - configuration: 连接配置
    /// - Throws: 如果连接 ID 已存在或超出最大连接数
    func register(
        connection: any Connection,
        endpoint: Endpoint,
        configuration: ConnectionConfiguration
    ) throws {
        // 检查连接数限制
        guard connections.count < maxConnections else {
            throw NexusError.resourceExhausted
        }

        // 检查 ID 是否已存在
        if connections[configuration.id] != nil {
            throw NexusError.connectionAlreadyExists(id: configuration.id)
        }

        // 注册连接
        connections[configuration.id] = connection
        metadata[configuration.id] = ConnectionMetadata(
            id: configuration.id,
            endpoint: endpoint,
            createdAt: Date(),
            configuration: configuration
        )

        // 更新统计
        stats = ConnectionStatistics(
            totalConnections: stats.totalConnections + 1,
            activeConnections: connections.count,
            totalBytesSent: stats.totalBytesSent,
            totalBytesReceived: stats.totalBytesReceived,
            totalMessagesSent: stats.totalMessagesSent,
            totalMessagesReceived: stats.totalMessagesReceived,
            averageConnectionDuration: stats.averageConnectionDuration,
            reconnectionCount: stats.reconnectionCount
        )
    }

    /// 创建连接 (仅用于兼容性)
    ///
    /// 此方法由 ConnectionBuilder 使用，但总是抛出错误。
    /// 请直接使用 TCPConnectionFactory 或 WebSocketConnectionFactory。
    ///
    /// - Parameters:
    ///   - endpoint: 连接端点
    ///   - configuration: 连接配置
    /// - Throws: 总是抛出 NexusError
    func createConnection(
        endpoint: Endpoint,
        configuration: ConnectionConfiguration
    ) async throws -> any Connection {
        // 检查连接数限制
        guard connections.count < maxConnections else {
            throw NexusError.resourceExhausted
        }

        // 检查 ID 是否已存在
        if connections[configuration.id] != nil {
            throw NexusError.connectionAlreadyExists(id: configuration.id)
        }

        // 所有 case 都抛出异常，要求使用具体的 Factory
        switch endpoint {
        case .tcp:
            throw NexusError.custom(
                message: "TCP connection requires NexusTCP module. Use TCPConnectionFactory.",
                underlyingError: nil
            )

        case .webSocket:
            throw NexusError.custom(
                message: "WebSocket connection not yet implemented. Import NexusWebSocket module.",
                underlyingError: nil
            )

        case .socketIO:
            throw NexusError.custom(
                message: "Socket.IO connection not yet implemented. Import NexusIO module.",
                underlyingError: nil
            )

        case .custom:
            throw NexusError.custom(
                message: "Custom endpoint requires custom connection implementation.",
                underlyingError: nil
            )
        }
    }

    // MARK: - Connection Retrieval

    /// 获取指定连接
    /// - Parameter id: 连接 ID
    /// - Returns: 连接实例
    func connection(id: String) -> (any Connection)? {
        connections[id]
    }

    /// 获取所有活跃连接
    /// - Returns: 连接数组
    func activeConnections() -> [any Connection] {
        Array(connections.values)
    }

    /// 获取连接元数据
    /// - Parameter id: 连接 ID
    /// - Returns: 元数据
    func connectionMetadata(id: String) -> ConnectionMetadata? {
        metadata[id]
    }

    // MARK: - Connection Removal

    /// 断开指定连接
    /// - Parameters:
    ///   - id: 连接 ID
    ///   - reason: 断开原因
    func disconnect(id: String, reason: DisconnectReason) async {
        guard let connection = connections[id] else { return }

        await connection.disconnect(reason: reason)

        // 移除连接
        connections.removeValue(forKey: id)

        // 更新元数据的断开时间
        if var meta = metadata[id] {
            meta.disconnectedAt = Date()
            metadata[id] = meta
        }

        // 更新统计
        stats = ConnectionStatistics(
            totalConnections: stats.totalConnections,
            activeConnections: connections.count,
            totalBytesSent: stats.totalBytesSent,
            totalBytesReceived: stats.totalBytesReceived,
            totalMessagesSent: stats.totalMessagesSent,
            totalMessagesReceived: stats.totalMessagesReceived,
            averageConnectionDuration: calculateAverageConnectionDuration(),
            reconnectionCount: stats.reconnectionCount
        )
    }

    /// 断开所有连接
    func disconnectAll() async {
        let connectionIds = Array(connections.keys)

        for id in connectionIds {
            await disconnect(id: id, reason: .clientInitiated)
        }
    }

    /// 清理已断开的连接元数据
    /// - Parameter olderThan: 保留时间（秒）
    func cleanupMetadata(olderThan timeInterval: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-timeInterval)

        metadata = metadata.filter { _, meta in
            guard let disconnectedAt = meta.disconnectedAt else {
                return true // 保留仍在连接的
            }
            return disconnectedAt > cutoff
        }
    }

    // MARK: - Statistics

    /// 获取统计信息
    /// - Returns: 连接统计
    func statistics() -> ConnectionStatistics {
        stats
    }

    /// 更新发送统计
    /// - Parameters:
    ///   - id: 连接 ID
    ///   - bytes: 发送字节数
    func recordBytesSent(id: String, bytes: Int64) {
        stats = ConnectionStatistics(
            totalConnections: stats.totalConnections,
            activeConnections: stats.activeConnections,
            totalBytesSent: stats.totalBytesSent + bytes,
            totalBytesReceived: stats.totalBytesReceived,
            totalMessagesSent: stats.totalMessagesSent + 1,
            totalMessagesReceived: stats.totalMessagesReceived,
            averageConnectionDuration: stats.averageConnectionDuration,
            reconnectionCount: stats.reconnectionCount
        )
    }

    /// 更新接收统计
    /// - Parameters:
    ///   - id: 连接 ID
    ///   - bytes: 接收字节数
    func recordBytesReceived(id: String, bytes: Int64) {
        stats = ConnectionStatistics(
            totalConnections: stats.totalConnections,
            activeConnections: stats.activeConnections,
            totalBytesSent: stats.totalBytesSent,
            totalBytesReceived: stats.totalBytesReceived + bytes,
            totalMessagesSent: stats.totalMessagesSent,
            totalMessagesReceived: stats.totalMessagesReceived + 1,
            averageConnectionDuration: stats.averageConnectionDuration,
            reconnectionCount: stats.reconnectionCount
        )
    }

    /// 记录重连
    /// - Parameter id: 连接 ID
    func recordReconnection(id: String) {
        stats = ConnectionStatistics(
            totalConnections: stats.totalConnections,
            activeConnections: stats.activeConnections,
            totalBytesSent: stats.totalBytesSent,
            totalBytesReceived: stats.totalBytesReceived,
            totalMessagesSent: stats.totalMessagesSent,
            totalMessagesReceived: stats.totalMessagesReceived,
            averageConnectionDuration: stats.averageConnectionDuration,
            reconnectionCount: stats.reconnectionCount + 1
        )
    }

    // MARK: - Private Methods

    /// 计算平均连接时长
    private func calculateAverageConnectionDuration() -> TimeInterval {
        let durations = metadata.values.compactMap { meta -> TimeInterval? in
            guard let disconnectedAt = meta.disconnectedAt else {
                // 仍在连接中，使用当前时间
                return Date().timeIntervalSince(meta.createdAt)
            }
            return disconnectedAt.timeIntervalSince(meta.createdAt)
        }

        guard !durations.isEmpty else { return 0 }

        let total = durations.reduce(0, +)
        return total / Double(durations.count)
    }
}

// MARK: - Connection Metadata

/// 连接元数据
struct ConnectionMetadata: Sendable {
    /// 连接 ID
    let id: String

    /// 连接端点
    let endpoint: Endpoint

    /// 创建时间
    let createdAt: Date

    /// 断开时间
    var disconnectedAt: Date?

    /// 连接配置
    let configuration: ConnectionConfiguration

    /// 连接时长（秒）
    var duration: TimeInterval {
        let endTime = disconnectedAt ?? Date()
        return endTime.timeIntervalSince(createdAt)
    }
}
