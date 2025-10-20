//
//  WebSocketTransport.swift
//  NexusIO
//
//  Created by NexusKit Contributors
//

import Foundation

/// WebSocket 传输层（用于Engine.IO）
public actor WebSocketTransport {
    
    // MARK: - Properties
    
    /// WebSocket URL
    private let url: URL
    
    /// WebSocket连接
    private var webSocket: URLSessionWebSocketTask?
    
    /// URL Session
    private var session: URLSession?
    
    /// 是否已连接
    private var isConnected = false
    
    /// 消息处理器
    private var messageHandler: (@Sendable (String) async -> Void)?
    
    // MARK: - Initialization
    
    public init(url: URL) {
        self.url = url
    }
    
    // MARK: - Public Methods
    
    /// 连接
    public func connect() async throws {
        guard !isConnected else { return }
        
        // 创建URL Session
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        
        // 创建WebSocket任务
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
        
        isConnected = true
        
        // 开始接收消息
        startReceiving()
    }
    
    /// 发送消息
    public func send(_ message: String) async throws {
        guard isConnected, let webSocket = webSocket else {
            throw EngineIOError.connectionClosed
        }
        
        let message = URLSessionWebSocketTask.Message.string(message)
        try await webSocket.send(message)
    }
    
    /// 关闭连接
    public func close() async {
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
    }
    
    /// 设置消息处理器
    public func setMessageHandler(_ handler: @escaping @Sendable (String) async -> Void) {
        self.messageHandler = handler
    }
    
    // MARK: - Private Methods
    
    /// 开始接收消息
    private func startReceiving() {
        guard isConnected, let webSocket = webSocket else { return }
        
        Task {
            do {
                let message = try await webSocket.receive()
                
                switch message {
                case .string(let text):
                    await messageHandler?(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await messageHandler?(text)
                    }
                @unknown default:
                    break
                }
                
                // 继续接收下一条消息
                if isConnected {
                    startReceiving()
                }
            } catch {
                // 连接关闭或错误
                await close()
            }
        }
    }
}
