//
//  SOCKS5ProxyHandler.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
import Network

// MARK: - SOCKS5 Proxy Handler

/// SOCKS5代理处理器
/// 实现SOCKS5协议的完整握手流程
public actor SOCKS5ProxyHandler {

    // MARK: - Nested Types

    /// SOCKS5认证方法
    private enum AuthMethod: UInt8 {
        case noAuth = 0x00          // 无需认证
        case gssapi = 0x01          // GSSAPI认证
        case usernamePassword = 0x02 // 用户名密码认证
        case noAcceptable = 0xFF     // 无可接受的方法
    }

    /// SOCKS5命令
    private enum Command: UInt8 {
        case connect = 0x01    // 建立TCP连接
        case bind = 0x02       // 绑定端口
        case udpAssociate = 0x03 // UDP关联
    }

    /// 地址类型
    private enum AddressType: UInt8 {
        case ipv4 = 0x01       // IPv4地址
        case domainName = 0x03 // 域名
        case ipv6 = 0x04       // IPv6地址
    }

    /// 回复状态
    private enum ReplyStatus: UInt8 {
        case succeeded = 0x00               // 成功
        case generalFailure = 0x01          // 一般性SOCKS服务器故障
        case connectionNotAllowed = 0x02    // 规则不允许连接
        case networkUnreachable = 0x03      // 网络不可达
        case hostUnreachable = 0x04         // 主机不可达
        case connectionRefused = 0x05       // 连接被拒绝
        case ttlExpired = 0x06              // TTL过期
        case commandNotSupported = 0x07     // 不支持的命令
        case addressTypeNotSupported = 0x08 // 不支持的地址类型
    }

    // MARK: - Properties

    private let configuration: NexusCore.ProxyConfiguration
    private var ipv4Cache: [String: Data] = [:]
    private var ipv6Cache: [String: Data] = [:]

    // MARK: - Initialization

    public init(configuration: NexusCore.ProxyConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// 通过SOCKS5代理建立连接
    /// - Parameters:
    ///   - connection: NWConnection实例
    ///   - destination: 目标端点
    public func negotiate(
        through connection: NWConnection,
        to destination: Endpoint
    ) async throws {
        print("[SOCKS5] 开始代理握手流程")

        // 1. 认证协商
        try await sendAuthenticationRequest(through: connection)
        let authMethod = try await receiveAuthenticationResponse(from: connection)

        // 2. 用户名密码认证(如果需要)
        if authMethod == .usernamePassword {
            guard configuration.credentials != nil else {
                throw NexusError.proxyAuthenticationFailed
            }
            try await performUsernamePasswordAuth(through: connection)
        }

        // 3. 发送连接请求
        try await sendConnectRequest(through: connection, to: destination)

        // 4. 接收连接响应
        try await receiveConnectResponse(from: connection)

        print("[SOCKS5] 代理握手完成")
    }

    // MARK: - Authentication

    /// 发送认证方法协商请求
    private func sendAuthenticationRequest(through connection: NWConnection) async throws {
        var methods: [UInt8] = [AuthMethod.noAuth.rawValue]

        // 如果有凭证,添加用户名密码认证
        if configuration.credentials != nil {
            methods.append(AuthMethod.usernamePassword.rawValue)
        }

        var request = Data(capacity: 2 + methods.count)
        request.append(0x05) // SOCKS版本5
        request.append(UInt8(methods.count)) // 方法数量
        request.append(contentsOf: methods)

        try await send(data: request, through: connection)
        print("[SOCKS5] 已发送认证方法: \(methods)")
    }

    /// 接收认证方法响应
    private func receiveAuthenticationResponse(from connection: NWConnection) async throws -> AuthMethod {
        let response = try await receive(length: 2, from: connection)

        guard response.count == 2 else {
            throw NexusError.proxyConnectionFailed(reason: "认证响应长度错误")
        }

        let version = response[0]
        let method = response[1]

        guard version == 0x05 else {
            throw NexusError.proxyConnectionFailed(reason: "SOCKS版本不匹配")
        }

        guard let authMethod = AuthMethod(rawValue: method) else {
            throw NexusError.proxyConnectionFailed(reason: "未知的认证方法: \(method)")
        }

        guard authMethod != .noAcceptable else {
            throw NexusError.proxyConnectionFailed(reason: "服务器不接受任何认证方法")
        }

        print("[SOCKS5] 服务器选择认证方法: \(authMethod)")
        return authMethod
    }

    /// 执行用户名密码认证
    private func performUsernamePasswordAuth(through connection: NWConnection) async throws {
        guard let credentials = configuration.credentials else {
            throw NexusError.proxyAuthenticationFailed
        }

        guard let usernameData = credentials.username.data(using: .utf8),
              let passwordData = credentials.password.data(using: .utf8),
              usernameData.count <= 255,
              passwordData.count <= 255 else {
            throw NexusError.proxyConnectionFailed(reason: "凭证格式错误")
        }

        // 构造认证请求
        var authRequest = Data(capacity: 3 + usernameData.count + passwordData.count)
        authRequest.append(0x01) // 子协商版本
        authRequest.append(UInt8(usernameData.count))
        authRequest.append(usernameData)
        authRequest.append(UInt8(passwordData.count))
        authRequest.append(passwordData)

        try await send(data: authRequest, through: connection)
        print("[SOCKS5] 已发送用户名密码认证")

        // 接收认证响应
        let authResponse = try await receive(length: 2, from: connection)

        guard authResponse.count == 2 else {
            throw NexusError.proxyAuthenticationFailed
        }

        let authVersion = authResponse[0]
        let authStatus = authResponse[1]

        guard authVersion == 0x01, authStatus == 0x00 else {
            throw NexusError.proxyAuthenticationFailed
        }

        print("[SOCKS5] 用户名密码认证成功")
    }

    // MARK: - Connection Request

    /// 发送连接请求
    private func sendConnectRequest(
        through connection: NWConnection,
        to destination: Endpoint
    ) async throws {
        var request = Data(capacity: 262) // 最大: 4 + 1 + 255 + 2
        request.append(0x05) // SOCKS版本
        request.append(Command.connect.rawValue) // CONNECT命令
        request.append(0x00) // 保留字段

        // 添加目标地址
        try appendDestinationAddress(to: &request, destination: destination)

        // 添加目标端口
        try appendDestinationPort(to: &request, destination: destination)

        try await send(data: request, through: connection)
        print("[SOCKS5] 已发送连接请求: \(destination)")
    }

    /// 接收连接响应
    private func receiveConnectResponse(from connection: NWConnection) async throws {
        // 接收前4字节
        let header = try await receive(length: 4, from: connection)

        guard header.count == 4 else {
            throw NexusError.proxyConnectionFailed(reason: "连接响应头长度错误")
        }

        let version = header[0]
        let reply = header[1]
        let addressType = header[3]

        guard version == 0x05 else {
            throw NexusError.proxyConnectionFailed(reason: "SOCKS版本不匹配")
        }

        // 检查回复状态
        guard let status = ReplyStatus(rawValue: reply) else {
            throw NexusError.proxyConnectionFailed(reason: "未知的回复状态: \(reply)")
        }

        guard status == .succeeded else {
            throw NexusError.proxyConnectionFailed(reason: "连接失败: \(status)")
        }

        // 读取绑定地址和端口
        try await readBindAddress(addressType: addressType, from: connection)
        _ = try await receive(length: 2, from: connection) // 端口

        print("[SOCKS5] 连接响应成功")
    }

    // MARK: - Helper Methods

    /// 添加目标地址到请求
    private func appendDestinationAddress(
        to request: inout Data,
        destination: Endpoint
    ) throws {
        switch destination {
        case .tcp(let host, _):
            // 尝试IPv4
            if let ipv4Data = getIPv4Address(host) {
                request.append(AddressType.ipv4.rawValue)
                request.append(ipv4Data)
                return
            }

            // 尝试IPv6
            if let ipv6Data = getIPv6Address(host) {
                request.append(AddressType.ipv6.rawValue)
                request.append(ipv6Data)
                return
            }

            // 使用域名
            guard let hostData = host.data(using: .utf8), hostData.count <= 255 else {
                throw NexusError.proxyConnectionFailed(reason: "域名过长")
            }

            request.append(AddressType.domainName.rawValue)
            request.append(UInt8(hostData.count))
            request.append(hostData)

        default:
            throw NexusError.invalidEndpoint(destination)
        }
    }

    /// 添加目标端口到请求
    private func appendDestinationPort(
        to request: inout Data,
        destination: Endpoint
    ) throws {
        switch destination {
        case .tcp(_, let port):
            request.append(contentsOf: withUnsafeBytes(of: port.bigEndian) { Array($0) })

        default:
            throw NexusError.invalidEndpoint(destination)
        }
    }

    /// 读取绑定地址
    private func readBindAddress(
        addressType: UInt8,
        from connection: NWConnection
    ) async throws {
        guard let addrType = AddressType(rawValue: addressType) else {
            throw NexusError.proxyConnectionFailed(reason: "未知的地址类型: \(addressType)")
        }

        switch addrType {
        case .ipv4:
            _ = try await receive(length: 4, from: connection)
        case .ipv6:
            _ = try await receive(length: 16, from: connection)
        case .domainName:
            let lengthData = try await receive(length: 1, from: connection)
            let length = Int(lengthData[0])
            _ = try await receive(length: length, from: connection)
        }
    }

    /// 获取IPv4地址数据
    private func getIPv4Address(_ host: String) -> Data? {
        if let cached = ipv4Cache[host] {
            return cached
        }

        var addr = in_addr()
        guard inet_pton(AF_INET, host, &addr) == 1 else {
            return nil
        }

        let data = withUnsafeBytes(of: addr) { Data($0) }
        ipv4Cache[host] = data
        return data
    }

    /// 获取IPv6地址数据
    private func getIPv6Address(_ host: String) -> Data? {
        if let cached = ipv6Cache[host] {
            return cached
        }

        var addr = in6_addr()
        guard inet_pton(AF_INET6, host, &addr) == 1 else {
            return nil
        }

        let data = withUnsafeBytes(of: addr) { Data($0) }
        ipv6Cache[host] = data
        return data
    }

    // MARK: - Network I/O

    /// 发送数据
    private func send(data: Data, through connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: NexusError.sendFailed(error))
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    /// 接收指定长度的数据
    private func receive(length: Int, from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(
                minimumIncompleteLength: length,
                maximumLength: length
            ) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: NexusError.receiveFailed(error))
                } else if let data = data {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: NexusError.connectionClosed)
                } else {
                    continuation.resume(throwing: NexusError.receiveFailed(nil))
                }
            }
        }
    }
}
