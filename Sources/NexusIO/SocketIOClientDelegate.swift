//
//  SocketIOClientDelegate.swift
//  NexusIO
//
//  Created by NexusKit Contributors
//

import Foundation

/// Socket.IO 客户端代理协议
/// - Note: 遵循用户偏好的代理模式进行组件间通信
public protocol SocketIOClientDelegate: AnyObject, Sendable {
    
    /// 连接成功
    /// - Parameter client: Socket.IO客户端
    func socketIOClientDidConnect(_ client: SocketIOClient) async
    
    /// 连接断开
    /// - Parameters:
    ///   - client: Socket.IO客户端
    ///   - reason: 断开原因
    func socketIOClientDidDisconnect(_ client: SocketIOClient, reason: String) async
    
    /// 连接错误
    /// - Parameters:
    ///   - client: Socket.IO客户端
    ///   - error: 错误信息
    func socketIOClient(_ client: SocketIOClient, didFailWithError error: Error) async
    
    /// 收到事件
    /// - Parameters:
    ///   - client: Socket.IO客户端
    ///   - event: 事件名称
    ///   - data: 事件数据
    func socketIOClient(_ client: SocketIOClient, didReceiveEvent event: String, data: [Any]) async
    
    /// 重连中
    /// - Parameters:
    ///   - client: Socket.IO客户端
    ///   - attemptNumber: 重连尝试次数
    func socketIOClient(_ client: SocketIOClient, isReconnecting attemptNumber: Int) async
}

// MARK: - 可选方法的默认实现

public extension SocketIOClientDelegate {
    func socketIOClient(_ client: SocketIOClient, isReconnecting attemptNumber: Int) async {
        // 默认空实现
    }
}

/// Socket.IO 命名空间代理协议
public protocol SocketIONamespaceDelegate: AnyObject, Sendable {
    
    /// 命名空间连接成功
    /// - Parameter namespace: 命名空间路径
    func namespaceDidConnect(_ namespace: String) async
    
    /// 命名空间断开
    /// - Parameters:
    ///   - namespace: 命名空间路径
    ///   - reason: 断开原因
    func namespace(_ namespace: String, didDisconnectWithReason reason: String) async
    
    /// 命名空间收到事件
    /// - Parameters:
    ///   - namespace: 命名空间路径
    ///   - event: 事件名称
    ///   - data: 事件数据
    func namespace(_ namespace: String, didReceiveEvent event: String, data: [Any]) async
}
