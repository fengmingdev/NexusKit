//
//  SocketIOClient.swift
//  NexusIO
//
//  Created by NexusKit Contributors
//

import Foundation

/// Socket.IO 客户端配置
public struct SocketIOConfiguration: Sendable {
    // 连接配置
    public var reconnect: Bool = true
    public var reconnectionAttempts: Int = .max
    public var reconnectionDelay: TimeInterval = 1.0
    public var reconnectionDelayMax: TimeInterval = 5.0
    
    // Engine.IO配置
    public var path: String = "/socket.io/"
    public var query: [String: String] = [:]
    public var extraHeaders: [String: String] = [:]
    
    // 超时配置
    public var timeout: TimeInterval = 20.0
    
    // 其他
    public var autoConnect: Bool = true
    
    public static let `default` = SocketIOConfiguration()
    
    public init() {}
}

/// Socket.IO 客户端
public actor SocketIOClient {
    
    // MARK: - Properties
    
    /// URL
    private let url: URL
    
    /// 配置
    private let configuration: SocketIOConfiguration
    
    /// Engine.IO 客户端
    private var engineIO: EngineIOClient?
    
    /// Socket.IO 解析器
    private let parser: SocketIOParser
    
    /// 连接状态
    private var isConnected = false
    
    /// 代理（弱引用，遵循代理模式）
    private weak var delegate: (any SocketIOClientDelegate)?
    
    /// 事件处理器映射
    private var eventHandlers: [String: [([Any]) async -> Void]] = [:]
    
    /// 确认ID计数器
    private var ackId = 0
    
    /// 确认回调映射
    private var ackCallbacks: [Int: ([Any]) async -> Void] = [:]
    
    /// 当前命名空间
    private var namespace: String = "/"
    
    /// 重连尝试次数
    private var reconnectionAttempts = 0
    
    /// 重连定时器
    private var reconnectTimer: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// 初始化Socket.IO客户端
    /// - Parameters:
    ///   - url: 服务器URL
    ///   - configuration: 配置
    public init(url: URL, configuration: SocketIOConfiguration = .default) {
        self.url = url
        self.configuration = configuration
        self.parser = SocketIOParser()
    }
    
    // MARK: - Public Methods - 连接管理
    
    /// 设置代理
    /// - Parameter delegate: 代理对象
    public func setDelegate(_ delegate: (any SocketIOClientDelegate)?) {
        self.delegate = delegate
    }
    
    /// 连接到服务器
    public func connect() async throws {
        guard !isConnected else { return }
        
        // 创建Engine.IO客户端
        let engineConfig = EngineIOConfiguration(
            path: configuration.path,
            query: configuration.query,
            extraHeaders: configuration.extraHeaders
        )
        
        let engineIO = EngineIOClient(url: url, configuration: engineConfig)
        self.engineIO = engineIO
        
        // 设置消息处理器
        await engineIO.setMessageHandler { [weak self] message in
            Task {
                await self?.handleEngineMessage(message)
            }
        }
        
        // 设置关闭处理器
        await engineIO.setCloseHandler { [weak self] in
            Task {
                await self?.handleDisconnect(reason: "transport close")
            }
        }
        
        // 连接Engine.IO
        try await engineIO.connect()
        
        // 发送Socket.IO连接包
        let connectPacket = SocketIOPacket.connect(namespace: namespace)
        try await sendPacket(connectPacket)
        
        isConnected = true
        reconnectionAttempts = 0
        
        // 通知代理
        await delegate?.socketIOClientDidConnect(self)
    }
    
    /// 断开连接
    public func disconnect() async {
        guard isConnected else { return }
        
        // 取消重连定时器
        reconnectTimer?.cancel()
        reconnectTimer = nil
        
        // 发送断开包
        let disconnectPacket = SocketIOPacket.disconnect(namespace: namespace)
        try? await sendPacket(disconnectPacket)
        
        // 关闭Engine.IO
        await engineIO?.close()
        engineIO = nil
        
        isConnected = false
        
        // 通知代理
        await delegate?.socketIOClientDidDisconnect(self, reason: "client disconnect")
    }
    
    // MARK: - Public Methods - 事件发送
    
    /// 发送事件
    /// - Parameters:
    ///   - event: 事件名称
    ///   - items: 事件数据
    public func emit(_ event: String, _ items: Any...) async throws {
        guard isConnected else {
            throw SocketIOError.notConnected
        }
        
        let packet = SocketIOPacket.event(event, items: items, namespace: namespace)
        try await sendPacket(packet)
    }
    
    /// 发送事件并等待确认
    /// - Parameters:
    ///   - event: 事件名称
    ///   - items: 事件数据
    ///   - callback: 确认回调
    public func emit(_ event: String, _ items: Any..., callback: @escaping ([Any]) async -> Void) async throws {
        guard isConnected else {
            throw SocketIOError.notConnected
        }
        
        // 生成确认ID
        let id = generateAckId()
        ackCallbacks[id] = callback
        
        let packet = SocketIOPacket.event(event, items: items, namespace: namespace, id: id)
        try await sendPacket(packet)
        
        // 设置超时
        Task {
            try? await Task.sleep(nanoseconds: UInt64(configuration.timeout * 1_000_000_000))
            if ackCallbacks[id] != nil {
                ackCallbacks.removeValue(forKey: id)
                // 超时不调用回调
            }
        }
    }
    
    // MARK: - Public Methods - 事件监听
    
    /// 监听事件
    /// - Parameters:
    ///   - event: 事件名称
    ///   - callback: 事件处理器
    public func on(_ event: String, callback: @escaping ([Any]) async -> Void) {
        if eventHandlers[event] == nil {
            eventHandlers[event] = []
        }
        eventHandlers[event]?.append(callback)
    }
    
    /// 监听一次事件
    /// - Parameters:
    ///   - event: 事件名称
    ///   - callback: 事件处理器
    public func once(_ event: String, callback: @escaping ([Any]) async -> Void) {
        var onceCallback: (([Any]) async -> Void)?
        onceCallback = { [weak self] data in
            await callback(data)
            // 移除自己
            if let event = event as String? {
                await self?.off(event, callback: onceCallback!)
            }
        }
        on(event, callback: onceCallback!)
    }
    
    /// 移除事件监听器
    /// - Parameters:
    ///   - event: 事件名称
    ///   - callback: 要移除的处理器（可选）
    public func off(_ event: String, callback: (([Any]) async -> Void)? = nil) {
        if callback == nil {
            // 移除所有监听器
            eventHandlers.removeValue(forKey: event)
        } else {
            // 移除特定监听器（注：由于闭包比较限制，实际使用中建议移除所有）
            eventHandlers.removeValue(forKey: event)
        }
    }
    
    // MARK: - Private Methods
    
    /// 发送Socket.IO包
    private func sendPacket(_ packet: SocketIOPacket) async throws {
        let encoded = try await parser.encode(packet)
        try await engineIO?.send(encoded)
    }
    
    /// 处理Engine.IO消息
    private func handleEngineMessage(_ message: String) async {
        do {
            let packet = try await parser.decode(message)
            await handlePacket(packet)
        } catch {
            print("[SocketIO] 解析消息失败: \(error)")
        }
    }
    
    /// 处理Socket.IO包
    private func handlePacket(_ packet: SocketIOPacket) async {
        switch packet.type {
        case .connect:
            // 连接成功确认
            isConnected = true
            await delegate?.socketIOClientDidConnect(self)
            
        case .disconnect:
            // 服务器断开
            await handleDisconnect(reason: "server disconnect")
            
        case .event:
            // 处理事件
            if let eventName = await parser.extractEventName(from: packet) {
                let eventData = await parser.extractEventData(from: packet)
                
                // 触发事件处理器
                if let handlers = eventHandlers[eventName] {
                    for handler in handlers {
                        await handler(eventData)
                    }
                }
                
                // 通知代理
                await delegate?.socketIOClient(self, didReceiveEvent: eventName, data: eventData)
            }
            
        case .ack:
            // 处理确认
            if let id = packet.id, let callback = ackCallbacks[id] {
                let ackData = packet.data ?? []
                await callback(ackData)
                ackCallbacks.removeValue(forKey: id)
            }
            
        case .connectError:
            // 连接错误
            let errorMsg = packet.data?.first as? [String: Any]
            let message = errorMsg?["message"] as? String ?? "Unknown error"
            let error = SocketIOError.connectionError(message)
            await delegate?.socketIOClient(self, didFailWithError: error)
            
        case .binaryEvent, .binaryAck:
            // 暂不支持二进制
            break
        }
    }
    
    /// 处理断开连接
    private func handleDisconnect(reason: String) async {
        let wasConnected = isConnected
        isConnected = false
        
        if wasConnected {
            await delegate?.socketIOClientDidDisconnect(self, reason: reason)
            
            // 自动重连
            if configuration.reconnect && reconnectionAttempts < configuration.reconnectionAttempts {
                await scheduleReconnect()
            }
        }
    }
    
    /// 调度重连
    private func scheduleReconnect() async {
        reconnectionAttempts += 1
        
        await delegate?.socketIOClient(self, isReconnecting: reconnectionAttempts)
        
        let delay = min(
            configuration.reconnectionDelay * Double(reconnectionAttempts),
            configuration.reconnectionDelayMax
        )
        
        reconnectTimer?.cancel()
        reconnectTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            try? await self?.connect()
        }
    }
    
    /// 生成确认ID
    private func generateAckId() -> Int {
        ackId += 1
        return ackId
    }
}

/// Socket.IO 错误
public enum SocketIOError: Error, Sendable {
    case notConnected
    case connectionError(String)
    case timeout
    case invalidResponse
}
