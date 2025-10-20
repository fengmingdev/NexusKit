//
//  NodeSocketAdapter.swift
//  NexusCompat
//
//  Created by NexusKit Contributors
//
//  提供与原NodeSocket完全兼容的API,内部使用NexusKit实现
//  允许无缝迁移现有代码

import Foundation
import NexusCore
import NexusTCP

#if canImport(UIKit)
import UIKit
#endif

// MARK: - NodeSocketDelegate Protocol

/// NodeSocket代理协议(完全兼容原接口)
public protocol NodeSocketDelegate: AnyObject {
    /// 已建立连接
    func nodeSocketDidConnect(socket: NodeSocketAdapter)

    /// 已断开连接
    func nodeSocketDidDisconnect(socket: NodeSocketAdapter, error: Error?, isReconnecting: Bool)

    /// 接收到消息
    func nodeSocket(socket: NodeSocketAdapter, didReceive message: Data, header: SocketHeader, shouldExecuteOnMainThread: Bool)

    /// 发送消息失败
    func nodeSocket(socket: NodeSocketAdapter, sendFail data: Data, shouldExecuteOnMainThread: Bool)

    /// 需要发送心跳包
    func nodeSocket(socket: NodeSocketAdapter, sendHeartBeat data: Data, shouldExecuteOnMainThread: Bool)

    /// 本地证书验证回调
    func nodeSocketCertificate(socket: NodeSocketAdapter) -> SecCertificate?
}

// 提供默认实现
public extension NodeSocketDelegate {
    func nodeSocketDidConnect(socket: NodeSocketAdapter) {}
    func nodeSocketDidDisconnect(socket: NodeSocketAdapter, error: Error?, isReconnecting: Bool) {}
    func nodeSocket(socket: NodeSocketAdapter, didReceive message: Data, header: SocketHeader, shouldExecuteOnMainThread: Bool) {}
    func nodeSocket(socket: NodeSocketAdapter, sendFail data: Data, shouldExecuteOnMainThread: Bool) {}
    func nodeSocket(socket: NodeSocketAdapter, sendHeartBeat data: Data, shouldExecuteOnMainThread: Bool) {}
    func nodeSocketCertificate(socket: NodeSocketAdapter) -> SecCertificate? { nil }
}

// MARK: - SocketHeader (兼容原结构)

/// Socket消息头(完全兼容原实现)
public class SocketHeader {
    public var len: UInt32 = 0    // header + body长度
    public var tag: UInt16 = 0    // 协议标签
    public var ver: UInt16 = 0    // 版本
    public var tp: UInt8 = 0      // 类型标志
    public var res: UInt8 = 0     // 响应标志
    public var qid: UInt32 = 0    // 请求ID
    public var fid: UInt32 = 0    // 功能ID
    public var code: UInt32 = 0   // 错误码
    public var dh: UInt16 = 0     // 保留字段

    public init() {}

    /// 从Data读取header
    public func readSocketHeader(_ data: Data) -> Bool {
        guard data.count >= 24 else { return false }

        data.withUnsafeBytes { bufferPtr in
            let bytes = bufferPtr.bindMemory(to: UInt8.self)

            len  = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
            tag  = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
            ver  = (UInt16(bytes[6]) << 8) | UInt16(bytes[7])
            tp   = bytes[8]
            res  = bytes[9]
            qid  = (UInt32(bytes[10]) << 24) | (UInt32(bytes[11]) << 16) | (UInt32(bytes[12]) << 8) | UInt32(bytes[13])
            fid  = (UInt32(bytes[14]) << 24) | (UInt32(bytes[15]) << 16) | (UInt32(bytes[16]) << 8) | UInt32(bytes[17])
            code = (UInt32(bytes[18]) << 24) | (UInt32(bytes[19]) << 16) | (UInt32(bytes[20]) << 8) | UInt32(bytes[21])
            dh   = (UInt16(bytes[22]) << 8) | UInt16(bytes[23])
        }

        return true
    }
}

// MARK: - NodeSocketAdapter

/// NodeSocket适配器
/// 提供与原NodeSocket完全兼容的API,内部使用NexusKit实现
@MainActor
public class NodeSocketAdapter {

    // MARK: - State Enum (兼容原状态)

    public enum State {
        case reconnecting  // 等待重连中
        case connecting    // 正在连接中
        case connected     // 已连接
        case closing       // 断开连接中
        case closed        // 已断开
    }

    // MARK: - Public Properties (完全兼容原API)

    /// 节点唯一标识符
    public let nodeId: String

    /// Socket连接的目标主机地址
    public var socketHost: String = ""

    /// Socket连接的目标端口号
    public var socketPort: UInt16 = 0

    /// 代理服务器配置
    public var proxyHost: String = ""
    public var proxyPort: UInt16 = 0
    public var enableProxy = false
    public var proxyUsename: String = ""
    public var proxyPwd: String = ""

    /// 代理对象
    public weak var delegate: NodeSocketDelegate?

    /// 当前状态
    public private(set) var state: State = .closed

    // MARK: - Private Properties (NexusKit实现)

    private var connection: TCPConnection?
    private var connectionTask: Task<Void, Never>?
    private var bufferManager: BufferManager?
    private let stateQueue = DispatchQueue(label: "com.nexuskit.adapter.state")

    // MARK: - Initialization

    public init(nodeId: String, socketHost: String, socketPort: UInt16) {
        self.nodeId = nodeId
        self.socketHost = socketHost
        self.socketPort = socketPort
    }

    deinit {
        connectionTask?.cancel()
    }

    // MARK: - Public Methods (兼容原API)

    /// 连接
    public func connect() {
        guard state == .closed else {
            print("[NodeSocketAdapter] 无效的状态转换: 当前状态 \(state)")
            return
        }

        updateState(.connecting)

        connectionTask = Task {
            do {
                try await performConnect()
            } catch {
                await handleConnectionError(error)
            }
        }
    }

    /// 断开连接
    public func disconnect() {
        guard state != .closed && state != .closing else {
            return
        }

        updateState(.closing)

        Task {
            await performDisconnect()
        }
    }

    /// 发送数据
    public func send(data: Data) {
        guard let connection = connection else {
            delegate?.nodeSocket(socket: self, sendFail: data, shouldExecuteOnMainThread: true)
            return
        }

        Task {
            do {
                try await connection.send(data, timeout: 30.0)
            } catch {
                delegate?.nodeSocket(socket: self, sendFail: data, shouldExecuteOnMainThread: true)
            }
        }
    }

    /// 检查是否已连接
    public func isConnected() -> Bool {
        state == .connected
    }

    // MARK: - Private Methods

    /// 执行连接
    private func performConnect() async throws {
        // 使用TCPConnectionBuilder构建连接
        var builder = NexusKit.shared.tcp(host: socketHost, port: socketPort)

        // 配置代理
        if enableProxy, !proxyHost.isEmpty {
            let proxyConfig = NexusCore.ProxyConfiguration.socks5(
                host: proxyHost,
                port: proxyPort,
                username: proxyUsename.isEmpty ? nil : proxyUsename,
                password: proxyPwd.isEmpty ? nil : proxyPwd
            )
            builder = builder.proxy(proxyConfig)
        }

        // 配置TLS
        if let certificate = delegate?.nodeSocketCertificate(socket: self) {
            let certData = SecCertificateCopyData(certificate) as Data
            let tlsConfig = NexusCore.TLSConfiguration.withPinning(
                certificates: [.init(data: certData)]
            )
            builder = builder.tls(tlsConfig)
        } else {
            builder = builder.enableTLS()
        }

        // 配置重连策略
        builder = builder.reconnection(.exponentialBackoff(maxAttempts: 5))

        // 配置心跳
        builder = builder.heartbeat(interval: 30, timeout: 60)

        // 建立连接
        let newConnection = try await builder.connect()
        self.connection = newConnection

        // 初始化缓冲区
        bufferManager = BufferManager()

        // 监听消息
        startReceiving()

        // 更新状态
        await MainActor.run {
            updateState(.connected)
            delegate?.nodeSocketDidConnect(socket: self)
        }
    }

    /// 执行断开
    private func performDisconnect() async {
        connectionTask?.cancel()

        if let connection = connection {
            await connection.disconnect(reason: .clientInitiated)
            self.connection = nil
        }

        await MainActor.run {
            updateState(.closed)
            delegate?.nodeSocketDidDisconnect(socket: self, error: nil, isReconnecting: false)
        }
    }

    /// 处理连接错误
    private func handleConnectionError(_ error: Error) async {
        await MainActor.run {
            updateState(.closed)
            delegate?.nodeSocketDidDisconnect(socket: self, error: error, isReconnecting: false)
        }
    }

    /// 开始接收数据
    private func startReceiving() {
        guard let connection = connection else { return }

        // 注册消息处理器
        connection.on(.message) { [weak self] data in
            await self?.handleReceivedData(data)
        }
    }

    /// 处理接收到的数据
    private func handleReceivedData(_ data: Data) async {
        guard let buffer = bufferManager else { return }

        do {
            try await buffer.append(data)

            // 解析消息
            while let message = try await parseMessage(from: buffer) {
                await MainActor.run {
                    delegate?.nodeSocket(
                        socket: self,
                        didReceive: message.body,
                        header: message.header,
                        shouldExecuteOnMainThread: false
                    )
                }
            }
        } catch {
            print("[NodeSocketAdapter] 数据处理错误: \(error)")
        }
    }

    /// 解析消息
    private func parseMessage(from buffer: BufferManager) async throws -> (header: SocketHeader, body: Data)? {
        // 检查是否有完整的header
        guard await buffer.availableBytes >= 24 else {
            return nil
        }

        // 读取header
        guard let headerData = await buffer.peek(length: 24) else {
            return nil
        }

        let header = SocketHeader()
        guard header.readSocketHeader(headerData) else {
            throw NexusError.invalidMessageFormat(reason: "Header解析失败")
        }

        let totalLength = Int(header.len) + 4 // header + body + 4字节长度字段

        // 检查是否有完整的消息
        guard await buffer.availableBytes >= totalLength else {
            return nil
        }

        // 跳过长度字段(4字节)和header(20字节)
        _ = await buffer.read(length: 24)

        // 读取body
        let bodyLength = Int(header.len) - 20 // 总长度 - header长度
        let body: Data
        if bodyLength > 0 {
            body = await buffer.read(length: bodyLength) ?? Data()
        } else {
            body = Data()
        }

        return (header, body)
    }

    /// 更新状态
    private func updateState(_ newState: State) {
        state = newState
    }
}

// MARK: - Migration Helper

/// 迁移辅助工具
public struct NodeSocketMigrationHelper {

    /// 从原NodeSocket配置转换为NexusKit配置
    public static func convertConfiguration(
        nodeId: String,
        socketHost: String,
        socketPort: UInt16,
        proxyHost: String? = nil,
        proxyPort: UInt16 = 0,
        proxyUsername: String? = nil,
        proxyPassword: String? = nil,
        enableProxy: Bool = false
    ) -> (endpoint: Endpoint, proxyConfig: ProxyConfiguration?) {
        let endpoint = Endpoint.tcp(host: socketHost, port: socketPort)

        let proxyConfig: ProxyConfiguration? = if enableProxy, let host = proxyHost, !host.isEmpty {
            .socks5(
                host: host,
                port: proxyPort,
                username: proxyUsername,
                password: proxyPassword
            )
        } else {
            nil
        }

        return (endpoint, proxyConfig)
    }

    /// 快速创建兼容适配器
    @MainActor
    public static func createAdapter(
        nodeId: String,
        socketHost: String,
        socketPort: UInt16
    ) -> NodeSocketAdapter {
        NodeSocketAdapter(
            nodeId: nodeId,
            socketHost: socketHost,
            socketPort: socketPort
        )
    }
}
