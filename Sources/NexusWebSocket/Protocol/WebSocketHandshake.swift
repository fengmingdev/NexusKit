//
//  WebSocketHandshake.swift
//  NexusWebSocket
//
//  Created by NexusKit on 2025-10-20.
//
//  WebSocket 握手实现 - HTTP 升级协议

import Foundation
import CryptoKit

// MARK: - WebSocket Handshake

/// WebSocket 握手处理器
///
/// 负责 WebSocket 连接的 HTTP 升级握手过程。
///
/// ## 握手流程
///
/// 1. 客户端发送 HTTP 升级请求
/// 2. 服务器响应 101 Switching Protocols
/// 3. 连接升级为 WebSocket 协议
///
/// ## 示例
///
/// ```swift
/// // 客户端握手
/// let request = WebSocketHandshake.createClientRequest(
///     url: URL(string: "wss://example.com/ws")!,
///     protocols: ["chat", "superchat"],
///     extensions: ["permessage-deflate"]
/// )
///
/// // 验证服务器响应
/// try WebSocketHandshake.validateServerResponse(
///     response: responseData,
///     expectedAcceptKey: request.acceptKey
/// )
/// ```
public enum WebSocketHandshake {

    // MARK: - Client Request

    /// 客户端握手请求
    public struct ClientRequest: Sendable {
        /// WebSocket Key（用于验证）
        public let key: String

        /// 预期的 Sec-WebSocket-Accept 值
        public let acceptKey: String

        /// HTTP 请求数据
        public let requestData: Data

        /// 子协议列表
        public let protocols: [String]

        /// 扩展列表
        public let extensions: [String]
    }

    /// 创建客户端握手请求
    ///
    /// - Parameters:
    ///   - url: WebSocket URL
    ///   - protocols: 子协议列表（可选）
    ///   - extensions: 扩展列表（可选）
    ///   - headers: 额外的 HTTP 头（可选）
    /// - Returns: 客户端请求
    public static func createClientRequest(
        url: URL,
        protocols: [String] = [],
        extensions: [String] = [],
        headers: [String: String] = [:]
    ) -> ClientRequest {
        // 生成随机 WebSocket Key（16字节 Base64 编码）
        let keyBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let key = Data(keyBytes).base64EncodedString()

        // 计算预期的 Accept Key
        let acceptKey = calculateAcceptKey(from: key)

        // 构建 HTTP 请求
        var requestLines: [String] = []

        // 请求行
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        requestLines.append("GET \(path)\(query) HTTP/1.1")

        // 必需的头部
        requestLines.append("Host: \(url.host ?? "localhost")")
        requestLines.append("Upgrade: websocket")
        requestLines.append("Connection: Upgrade")
        requestLines.append("Sec-WebSocket-Key: \(key)")
        requestLines.append("Sec-WebSocket-Version: 13")

        // 子协议
        if !protocols.isEmpty {
            requestLines.append("Sec-WebSocket-Protocol: \(protocols.joined(separator: ", "))")
        }

        // 扩展
        if !extensions.isEmpty {
            requestLines.append("Sec-WebSocket-Extensions: \(extensions.joined(separator: ", "))")
        }

        // 额外头部
        for (name, value) in headers {
            requestLines.append("\(name): \(value)")
        }

        // 空行（标记头部结束）
        requestLines.append("")
        requestLines.append("")

        let requestString = requestLines.joined(separator: "\r\n")
        let requestData = requestString.data(using: .utf8) ?? Data()

        return ClientRequest(
            key: key,
            acceptKey: acceptKey,
            requestData: requestData,
            protocols: protocols,
            extensions: extensions
        )
    }

    // MARK: - Server Response

    /// 服务器握手响应
    public struct ServerResponse: Sendable {
        /// HTTP 状态码
        public let statusCode: Int

        /// 响应头
        public let headers: [String: String]

        /// 选择的子协议（如果有）
        public let selectedProtocol: String?

        /// 选择的扩展（如果有）
        public let selectedExtensions: [String]
    }

    /// 解析服务器响应
    ///
    /// - Parameter data: 响应数据
    /// - Returns: 服务器响应
    /// - Throws: 如果响应格式无效
    public static func parseServerResponse(_ data: Data) throws -> ServerResponse {
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw HandshakeError.invalidResponse
        }

        let lines = responseString.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            throw HandshakeError.invalidResponse
        }

        // 解析状态行
        let statusLine = lines[0]
        let statusComponents = statusLine.components(separatedBy: " ")
        guard statusComponents.count >= 3,
              let statusCode = Int(statusComponents[1]) else {
            throw HandshakeError.invalidStatusLine
        }

        // 解析头部
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }

            if let separatorIndex = line.firstIndex(of: ":") {
                let name = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[name.lowercased()] = value
            }
        }

        // 提取子协议
        let selectedProtocol = headers["sec-websocket-protocol"]

        // 提取扩展
        let extensionsString = headers["sec-websocket-extensions"] ?? ""
        let selectedExtensions = extensionsString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return ServerResponse(
            statusCode: statusCode,
            headers: headers,
            selectedProtocol: selectedProtocol,
            selectedExtensions: selectedExtensions
        )
    }

    /// 验证服务器响应
    ///
    /// - Parameters:
    ///   - response: 服务器响应数据
    ///   - expectedAcceptKey: 预期的 Accept Key
    /// - Throws: 如果响应验证失败
    public static func validateServerResponse(
        response: Data,
        expectedAcceptKey: String
    ) throws {
        let serverResponse = try parseServerResponse(response)

        // 验证状态码
        guard serverResponse.statusCode == 101 else {
            throw HandshakeError.invalidStatusCode(serverResponse.statusCode)
        }

        // 验证 Upgrade 头
        guard serverResponse.headers["upgrade"]?.lowercased() == "websocket" else {
            throw HandshakeError.missingUpgradeHeader
        }

        // 验证 Connection 头
        guard serverResponse.headers["connection"]?.lowercased().contains("upgrade") == true else {
            throw HandshakeError.missingConnectionHeader
        }

        // 验证 Sec-WebSocket-Accept
        guard let acceptKey = serverResponse.headers["sec-websocket-accept"],
              acceptKey == expectedAcceptKey else {
            throw HandshakeError.invalidAcceptKey
        }
    }

    // MARK: - Accept Key Calculation

    /// 计算 Sec-WebSocket-Accept 值
    ///
    /// 根据 RFC 6455:
    /// ```
    /// Sec-WebSocket-Accept = base64(SHA-1(Sec-WebSocket-Key + GUID))
    /// ```
    ///
    /// - Parameter key: Sec-WebSocket-Key
    /// - Returns: Sec-WebSocket-Accept 值
    public static func calculateAcceptKey(from key: String) -> String {
        // WebSocket GUID (固定值)
        let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + guid

        // SHA-1 哈希
        guard let data = combined.data(using: .utf8) else {
            return ""
        }

        let hash = Insecure.SHA1.hash(data: data)
        let hashData = Data(hash)

        // Base64 编码
        return hashData.base64EncodedString()
    }
}

// MARK: - Handshake Error

/// 握手错误
public enum HandshakeError: Error, Sendable {
    /// 无效的响应
    case invalidResponse

    /// 无效的状态行
    case invalidStatusLine

    /// 无效的状态码
    case invalidStatusCode(Int)

    /// 缺少 Upgrade 头
    case missingUpgradeHeader

    /// 缺少 Connection 头
    case missingConnectionHeader

    /// 无效的 Accept Key
    case invalidAcceptKey

    /// 协议协商失败
    case protocolNegotiationFailed

    /// 扩展协商失败
    case extensionNegotiationFailed
}

// MARK: - Extension Negotiation

extension WebSocketHandshake {

    /// WebSocket 扩展参数
    public struct Extension: Sendable {
        /// 扩展名称
        public let name: String

        /// 扩展参数
        public let parameters: [String: String]

        public init(name: String, parameters: [String: String] = [:]) {
            self.name = name
            self.parameters = parameters
        }

        /// 从字符串解析扩展
        public static func parse(_ string: String) -> Extension {
            let components = string.components(separatedBy: ";").map {
                $0.trimmingCharacters(in: .whitespaces)
            }

            guard let name = components.first else {
                return Extension(name: "", parameters: [:])
            }

            var parameters: [String: String] = [:]
            for param in components.dropFirst() {
                let parts = param.components(separatedBy: "=")
                if parts.count == 2 {
                    parameters[parts[0].trimmingCharacters(in: .whitespaces)] =
                        parts[1].trimmingCharacters(in: .whitespaces)
                } else if parts.count == 1 {
                    parameters[parts[0].trimmingCharacters(in: .whitespaces)] = ""
                }
            }

            return Extension(name: name, parameters: parameters)
        }

        /// 转换为字符串
        public func toString() -> String {
            var result = name
            for (key, value) in parameters {
                if value.isEmpty {
                    result += "; \(key)"
                } else {
                    result += "; \(key)=\(value)"
                }
            }
            return result
        }
    }

    /// 解析扩展列表
    public static func parseExtensions(_ string: String) -> [Extension] {
        string
            .components(separatedBy: ",")
            .map { Extension.parse($0) }
            .filter { !$0.name.isEmpty }
    }
}

// MARK: - CustomStringConvertible

extension WebSocketHandshake.ClientRequest: CustomStringConvertible {
    public var description: String {
        "WebSocketClientRequest(key: \(key), protocols: \(protocols))"
    }
}

extension WebSocketHandshake.ServerResponse: CustomStringConvertible {
    public var description: String {
        "WebSocketServerResponse(statusCode: \(statusCode), protocol: \(selectedProtocol ?? "none"))"
    }
}
