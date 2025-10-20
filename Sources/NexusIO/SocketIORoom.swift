//
//  SocketIORoom.swift
//  NexusIO
//
//  Created by NexusKit Contributors
//

import Foundation

/// Socket.IO 房间管理器
/// - Note: 遵循模块化设计偏好，将房间功能作为独立服务模块
public actor SocketIORoom {
    
    // MARK: - Properties
    
    /// 当前加入的房间集合
    private var joinedRooms: Set<String> = []
    
    /// 关联的Socket.IO客户端
    private weak var client: SocketIOClient?
    
    /// 命名空间路径
    private let namespace: String
    
    // MARK: - Initialization
    
    /// 初始化房间管理器
    /// - Parameters:
    ///   - client: Socket.IO客户端
    ///   - namespace: 命名空间路径
    internal init(client: SocketIOClient, namespace: String = "/") {
        self.client = client
        self.namespace = namespace
    }
    
    // MARK: - Public Methods
    
    /// 加入房间
    /// - Parameter room: 房间名称
    /// - Throws: Socket.IO错误
    public func join(_ room: String) async throws {
        guard let client = client else {
            throw SocketIOError.notConnected
        }
        
        // 发送加入房间事件
        try await client.emit("join", room)
        
        // 添加到已加入集合
        joinedRooms.insert(room)
    }
    
    /// 离开房间
    /// - Parameter room: 房间名称
    /// - Throws: Socket.IO错误
    public func leave(_ room: String) async throws {
        guard let client = client else {
            throw SocketIOError.notConnected
        }
        
        // 发送离开房间事件
        try await client.emit("leave", room)
        
        // 从已加入集合移除
        joinedRooms.remove(room)
    }
    
    /// 离开所有房间
    /// - Throws: Socket.IO错误
    public func leaveAll() async throws {
        guard let client = client else {
            throw SocketIOError.notConnected
        }
        
        // 逐个离开房间
        for room in joinedRooms {
            try await client.emit("leave", room)
        }
        
        // 清空集合
        joinedRooms.removeAll()
    }
    
    /// 向房间发送消息
    /// - Parameters:
    ///   - room: 房间名称
    ///   - event: 事件名称
    ///   - items: 事件数据
    /// - Throws: Socket.IO错误
    public func emit(to room: String, event: String, _ items: Any...) async throws {
        guard let client = client else {
            throw SocketIOError.notConnected
        }
        
        // Socket.IO的房间消息通过to事件发送
        try await client.emit("to", room, event, items)
    }
    
    /// 获取当前加入的房间列表
    /// - Returns: 房间名称数组
    public func getRooms() -> [String] {
        return Array(joinedRooms)
    }
    
    /// 检查是否在某个房间中
    /// - Parameter room: 房间名称
    /// - Returns: 是否在房间中
    public func isInRoom(_ room: String) -> Bool {
        return joinedRooms.contains(room)
    }
    
    // MARK: - Internal Methods
    
    /// 清除所有房间状态（用于断开连接时）
    internal func clear() {
        joinedRooms.removeAll()
    }
}
