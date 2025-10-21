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
    private var eventHandlers: [String: [@Sendable ([Any]) async -> Void]] = [:]

    /// 确认ID计数器
    private var ackId = 0

    /// 确认回调映射
    private var ackCallbacks: [Int: @Sendable ([Any]) async -> Void] = [:]
    
    /// 命名空间映射
    private var namespaces: [String: SocketIONamespace] = [:]
    
    /// 房间管理器
    private var roomManager: SocketIORoom?
    
    /// 二进制消息缓存（用于多部分二进制消息）
    private var binaryBuffers: [Data] = []
    private var expectedBinaryAttachments: Int = 0
    
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
        self.roomManager = nil
    }
    
    // MARK: - Public Methods - 命名空间管理
    
    /// 获取或创建命名空间
    /// - Parameter path: 命名空间路径
    /// - Returns: 命名空间实例
    public func socket(forNamespace path: String) -> SocketIONamespace {
        if let existing = namespaces[path] {
            return existing
        }
        
        let namespace = SocketIONamespace(path: path, client: self)
        namespaces[path] = namespace
        return namespace
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
        
        // 创建房间管理器
        if roomManager == nil {
            roomManager = SocketIORoom(client: self, namespace: namespace)
        }
        
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
        
        // 清理房间状态
        await roomManager?.clear()
        
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
    public func emit(_ event: String, _ items: Any..., callback: @escaping @Sendable ([Any]) async -> Void) async throws {
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
    public func on(_ event: String, callback: @escaping @Sendable ([Any]) async -> Void) {
        if eventHandlers[event] == nil {
            eventHandlers[event] = []
        }
        eventHandlers[event]?.append(callback)
    }
    
    /// 监听一次事件
    /// - Parameters:
    ///   - event: 事件名称
    ///   - callback: 事件处理器
    public func once(_ event: String, callback: @escaping @Sendable ([Any]) async -> Void) {
        let onceCallback: @Sendable ([Any]) async -> Void = { [weak self] data in
            await callback(data)
            // 移除该事件的所有监听器
            await self?.off(event)
        }
        on(event, callback: onceCallback)
    }
    
    /// 移除事件监听器
    /// - Parameters:
    ///   - event: 事件名称
    ///   - callback: 要移除的处理器（可选）
    public func off(_ event: String, callback: (@Sendable ([Any]) async -> Void)? = nil) {
        if callback == nil {
            // 移除所有监听器
            eventHandlers.removeValue(forKey: event)
        } else {
            // 移除特定监听器（注：由于闭包比较限制，实际使用中建议移除所有）
            eventHandlers.removeValue(forKey: event)
        }
    }
    
    /// 获取房间管理器
    /// - Returns: 房间管理器实例
    public func rooms() -> SocketIORoom {
        if roomManager == nil {
            roomManager = SocketIORoom(client: self, namespace: namespace)
        }
        return roomManager!
    }
    
    // MARK: - Internal Methods
    
    /// 发送Socket.IO包（供命名空间使用）
    internal func sendPacket(_ packet: SocketIOPacket) async throws {
        let encoded = try await parser.encode(packet)
        try await engineIO?.send(encoded)
    }
    
    // MARK: - Private Methods
    
    /// 处理Engine.IO消息
    private func handleEngineMessage(_ message: String) async {
        do {
            let packet = try await parser.decode(message)
            
            // 根据命名空间路由包
            if packet.namespace != "/" {
                // 非默认命名空间，转发到对应的命名空间处理
                if let namespace = namespaces[packet.namespace] {
                    await namespace.handlePacket(packet)
                }
                return
            }
            
            // 默认命名空间，由客户端自己处理
            await handlePacket(packet)
        } catch {
            print("[NexusKit] 解析消息失败: \(error)")
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
            if let eventName = parser.extractEventName(from: packet) {
                let eventData = parser.extractEventData(from: packet)
                
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
            
        case .binaryEvent:
            // 二进制事件消息
            await handleBinaryEvent(packet)
            
        case .binaryAck:
            // 二进制确认消息
            await handleBinaryAck(packet)
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
    
    // MARK: - Binary Message Support
    
    /// 处理二进制事件
    private func handleBinaryEvent(_ packet: SocketIOPacket) async {
        // Socket.IO 二进制消息格式：
        // 1. 首先收到一个 binaryEvent 包，包含 attachments 数量
        // 2. 然后收到对应数量的二进制数据包
        
        // 暂时简化处理：将二进制数据作为 Data 类型传递
        if let eventName = parser.extractEventName(from: packet) {
            var eventData = parser.extractEventData(from: packet)
            
            // 如果有二进制附件，添加到数据中
            if !binaryBuffers.isEmpty {
                eventData.append(contentsOf: binaryBuffers)
                binaryBuffers.removeAll()
                expectedBinaryAttachments = 0
            }
            
            // 触发事件处理器
            if let handlers = eventHandlers[eventName] {
                for handler in handlers {
                    await handler(eventData)
                }
            }
            
            // 通知代理
            await delegate?.socketIOClient(self, didReceiveEvent: eventName, data: eventData)
        }
    }
    
    /// 处理二进制确认
    private func handleBinaryAck(_ packet: SocketIOPacket) async {
        guard let id = packet.id, let callback = ackCallbacks[id] else {
            return
        }
        
        var ackData = packet.data ?? []
        
        // 如果有二进制附件，添加到数据中
        if !binaryBuffers.isEmpty {
            ackData.append(contentsOf: binaryBuffers)
            binaryBuffers.removeAll()
            expectedBinaryAttachments = 0
        }
        
        await callback(ackData)
        ackCallbacks.removeValue(forKey: id)
    }
    
    /// 发送二进制事件
    /// - Parameters:
    ///   - event: 事件名称
    ///   - items: 事件数据（可包含 Data 类型）
    public func emitBinary(_ event: String, _ items: Any...) async throws {
        guard isConnected else {
            throw SocketIOError.notConnected
        }
        
        // 提取二进制数据
        var regularData: [Any] = [event]
        var binaryAttachments: [Data] = []
        
        for item in items {
            if let data = item as? Data {
                binaryAttachments.append(data)
                // 用占位符替换二进制数据
                regularData.append(["_placeholder": true, "num": binaryAttachments.count - 1])
            } else {
                regularData.append(item)
            }
        }
        
        if binaryAttachments.isEmpty {
            // 没有二进制数据，使用普通事件
            try await emit(event, items)
        } else {
            // 有二进制数据，使用 binaryEvent
            let packet = SocketIOPacket(
                type: .binaryEvent,
                namespace: namespace,
                data: regularData,
                id: nil,
                attachments: binaryAttachments.count
            )
            
            // 发送主包
            try await sendPacket(packet)
            
            // 发送二进制附件（注：需要 Engine.IO 支持）
            // 暂时简化：将二进制数据编码到主包中
        }
    }
}

/// Socket.IO 错误
public enum SocketIOError: Error, Sendable {
    case notConnected
    case connectionError(String)
    case timeout
    case invalidResponse
}
