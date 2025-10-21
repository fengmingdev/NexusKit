//
//  EngineIOClient.swift
//  NexusIO
//
//  Created by NexusKit Contributors
//

import Foundation
#if canImport(NexusCore)
import NexusCore
#endif

/// Engine.IO 客户端
public actor EngineIOClient {
    
    // MARK: - Properties
    
    /// WebSocket传输（暂时只支持WebSocket）
    private var transport: WebSocketTransport?
    
    /// 会话ID
    private var sessionId: String?
    
    /// 心跳间隔（秒）
    private var pingInterval: TimeInterval?
    
    /// 心跳超时（秒）
    private var pingTimeout: TimeInterval?
    
    /// 心跳定时器
    private var pingTimer: Task<Void, Never>?
    
    /// 连接状态
    private var isConnected = false
    
    /// 消息处理器
    private var messageHandler: (@Sendable (String) -> Void)?
    
    /// 关闭处理器
    private var closeHandler: (@Sendable () -> Void)?
    
    /// URL
    private let url: URL
    
    /// 配置
    private let configuration: EngineIOConfiguration
    
    // MARK: - Initialization
    
    public init(url: URL, configuration: EngineIOConfiguration = .default) {
        self.url = url
        self.configuration = configuration
    }
    
    // MARK: - Public Methods
    
    /// 连接
    public func connect() async throws {
        guard !isConnected else { return }
        
        // 构建Engine.IO URL
        let engineURL = buildEngineURL()
        
        // 创建WebSocket传输
        let transport = WebSocketTransport(url: engineURL)
        self.transport = transport
        
        // 设置消息处理
        await transport.setMessageHandler { [weak self] message in
            await self?.handleMessage(message)
        }
        
        // 连接
        try await transport.connect()
        
        // 等待握手完成
        try await waitForHandshake()
        
        isConnected = true
    }
    
    /// 发送消息
    public func send(_ message: String) async throws {
        guard isConnected else {
            throw EngineIOError.connectionClosed
        }
        
        let packet = EngineIOPacket.message(message)
        try await transport?.send(packet.encode())
    }
    
    /// 关闭连接
    public func close() async {
        isConnected = false
        
        // 取消心跳定时器
        pingTimer?.cancel()
        pingTimer = nil
        
        // 发送关闭包
        if let transport = transport {
            let closePacket = EngineIOPacket.close()
            try? await transport.send(closePacket.encode())
            await transport.close()
        }
        
        transport = nil
        sessionId = nil
        
        // 通知关闭
        closeHandler?()
    }
    
    /// 设置消息处理器
    public func setMessageHandler(_ handler: @escaping @Sendable (String) -> Void) {
        self.messageHandler = handler
    }
    
    /// 设置关闭处理器
    public func setCloseHandler(_ handler: @escaping @Sendable () -> Void) {
        self.closeHandler = handler
    }
    
    // MARK: - Private Methods
    
    /// 构建Engine.IO URL
    private func buildEngineURL() -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        
        // 设置路径
        components.path = configuration.path
        
        // 添加查询参数
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "EIO", value: "4"),  // Engine.IO版本
            URLQueryItem(name: "transport", value: "websocket")
        ]
        
        // 添加自定义查询参数
        for (key, value) in configuration.query {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        
        components.queryItems = queryItems
        
        // 转换为WebSocket协议
        if components.scheme == "http" {
            components.scheme = "ws"
        } else if components.scheme == "https" {
            components.scheme = "wss"
        }
        
        return components.url!
    }
    
    /// 等待握手完成
    private func waitForHandshake() async throws {
        // 握手应该在连接后立即收到
        // 这里简化处理，实际应该等待OPEN包
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }
    
    /// 处理接收到的消息
    private func handleMessage(_ message: String) {
        Task {
            do {
                let packet = try EngineIOPacket.decode(message)
                
                switch packet.type {
                case .open:
                    // 处理握手
                    try await handleHandshake(packet)
                    
                case .ping:
                    // 响应PING
                    try await sendPong()
                    
                case .pong:
                    // 收到PONG，心跳正常
                    break
                    
                case .message:
                    // 转发消息到上层
                    if let data = packet.data {
                        messageHandler?(data)
                    }
                    
                case .close:
                    // 服务器关闭连接
                    await close()
                    
                case .upgrade, .noop:
                    // 暂不处理
                    break
                }
            } catch {
                print("[NexusKit] 处理消息失败: \(error)")
            }
        }
    }
    
    /// 处理握手
    private func handleHandshake(_ packet: EngineIOPacket) async throws {
        guard let data = packet.data,
              let jsonData = data.data(using: .utf8) else {
            throw EngineIOError.invalidHandshake
        }
        
        let handshake = try JSONDecoder().decode(EngineIOHandshake.self, from: jsonData)
        
        // 保存会话信息
        sessionId = handshake.sid
        pingInterval = TimeInterval(handshake.pingInterval) / 1000.0
        pingTimeout = TimeInterval(handshake.pingTimeout) / 1000.0
        
        // 启动心跳
        startPingTimer()
    }
    
    /// 启动心跳定时器
    private func startPingTimer() {
        guard let interval = pingInterval else { return }
        
        pingTimer?.cancel()
        
        pingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                // 发送PING
                await self?.sendPing()
            }
        }
    }
    
    /// 发送PING
    private func sendPing() async {
        let pingPacket = EngineIOPacket.ping()
        try? await transport?.send(pingPacket.encode())
    }
    
    /// 发送PONG
    private func sendPong() async throws {
        let pongPacket = EngineIOPacket.pong()
        try await transport?.send(pongPacket.encode())
    }
}

/// Engine.IO 配置
public struct EngineIOConfiguration: Sendable {
    /// 路径
    public var path: String
    
    /// 查询参数
    public var query: [String: String]
    
    /// 额外头部
    public var extraHeaders: [String: String]
    
    /// 默认配置
    public static let `default` = EngineIOConfiguration()
    
    public init(path: String = "/socket.io/", query: [String: String] = [:], extraHeaders: [String: String] = [:]) {
        self.path = path
        self.query = query
        self.extraHeaders = extraHeaders
    }
}
