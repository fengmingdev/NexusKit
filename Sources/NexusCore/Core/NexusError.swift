//
//  NexusError.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

/// NexusKit 错误类型
public enum NexusError: Error, LocalizedError, Equatable {
    // MARK: - Connection Errors

    /// 连接超时
    case connectionTimeout

    /// 连接被拒绝
    case connectionRefused

    /// 网络不可达
    case networkUnreachable

    /// 连接已断开
    case connectionClosed

    /// 未连接
    case notConnected

    /// 心跳超时
    case heartbeatTimeout

    /// 连接已存在
    case connectionAlreadyExists(id: String)

    /// 连接不存在
    case connectionNotFound(id: String)

    // MARK: - Authentication Errors

    /// 认证失败
    case authenticationFailed(reason: String)

    /// 证书验证失败
    case certificateValidationFailed

    /// 无效的凭证
    case invalidCredentials

    // MARK: - TLS/SSL Errors

    /// TLS错误
    case tlsError(reason: String)

    /// TLS握手失败
    case tlsHandshakeFailed

    /// 证书加载失败
    case certificateLoadFailed(reason: String)

    /// 不受信任的证书
    case untrustedCertificate

    // MARK: - Proxy Errors

    /// 代理连接失败
    case proxyConnectionFailed(reason: String)

    /// 代理认证失败
    case proxyAuthenticationFailed

    /// 不支持的代理类型
    case unsupportedProxyType(String)

    // MARK: - Protocol Errors

    /// 协议错误
    case protocolError(message: String)

    /// 无效的消息格式
    case invalidMessageFormat(reason: String)

    /// 不支持的协议版本
    case unsupportedProtocolVersion(version: String)

    /// 编码失败
    case encodingFailed(Error)

    /// 解码失败
    case decodingFailed(Error)

    // MARK: - State Errors

    /// 无效的状态转换
    case invalidStateTransition(from: String, to: String)

    /// 操作在当前状态下不允许
    case operationNotAllowed(state: String)

    // MARK: - Send/Receive Errors

    /// 发送失败
    case sendFailed(Error?)

    /// 接收失败
    case receiveFailed(Error?)

    /// 请求超时
    case requestTimeout

    /// 响应格式错误
    case invalidResponse

    // MARK: - Resource Errors

    /// 缓冲区溢出
    case bufferOverflow

    /// 资源耗尽
    case resourceExhausted

    /// 内存不足
    case outOfMemory

    // MARK: - Configuration Errors

    /// 无效的配置
    case invalidConfiguration(reason: String)

    /// 缺少必需的配置
    case missingRequiredConfiguration(key: String)

    /// 无效的端点
    case invalidEndpoint(Endpoint)

    /// 没有协议适配器
    case noProtocolAdapter

    /// 不支持的操作
    case unsupportedOperation(operation: String, reason: String)

    // MARK: - Middleware Errors

    /// 中间件错误
    case middlewareError(name: String, error: Error)

    /// 中间件链中断
    case middlewareChainBroken

    // MARK: - Pool Errors

    /// 连接池已满
    case poolExhausted

    /// 连接池已关闭
    case poolClosed

    // MARK: - Custom Errors

    /// 自定义错误
    case custom(message: String, underlyingError: Error?)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .connectionTimeout:
            return "Connection timed out"

        case .connectionRefused:
            return "Connection refused by server"

        case .networkUnreachable:
            return "Network is unreachable"

        case .connectionClosed:
            return "Connection has been closed"

        case .notConnected:
            return "Not connected"

        case .heartbeatTimeout:
            return "Heartbeat timeout"

        case .connectionAlreadyExists(let id):
            return "Connection with id '\(id)' already exists"

        case .connectionNotFound(let id):
            return "Connection with id '\(id)' not found"

        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"

        case .certificateValidationFailed:
            return "Certificate validation failed"

        case .invalidCredentials:
            return "Invalid credentials"

        case .tlsError(let reason):
            return "TLS error: \(reason)"

        case .tlsHandshakeFailed:
            return "TLS handshake failed"

        case .certificateLoadFailed(let reason):
            return "Certificate load failed: \(reason)"

        case .untrustedCertificate:
            return "Untrusted certificate"

        case .proxyConnectionFailed(let reason):
            return "Proxy connection failed: \(reason)"

        case .proxyAuthenticationFailed:
            return "Proxy authentication failed"

        case .unsupportedProxyType(let type):
            return "Unsupported proxy type: \(type)"

        case .protocolError(let message):
            return "Protocol error: \(message)"

        case .invalidMessageFormat(let reason):
            return "Invalid message format: \(reason)"

        case .unsupportedProtocolVersion(let version):
            return "Unsupported protocol version: \(version)"

        case .encodingFailed(let error):
            return "Message encoding failed: \(error.localizedDescription)"

        case .decodingFailed(let error):
            return "Message decoding failed: \(error.localizedDescription)"

        case .invalidStateTransition(let from, let to):
            return "Invalid state transition from '\(from)' to '\(to)'"

        case .operationNotAllowed(let state):
            return "Operation not allowed in current state: \(state)"

        case .sendFailed(let error):
            if let error = error {
                return "Send failed: \(error.localizedDescription)"
            }
            return "Send failed"

        case .receiveFailed(let error):
            if let error = error {
                return "Receive failed: \(error.localizedDescription)"
            }
            return "Receive failed"

        case .requestTimeout:
            return "Request timed out"

        case .invalidResponse:
            return "Invalid response from server"

        case .bufferOverflow:
            return "Buffer overflow"

        case .resourceExhausted:
            return "Resource exhausted"

        case .outOfMemory:
            return "Out of memory"

        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"

        case .missingRequiredConfiguration(let key):
            return "Missing required configuration: \(key)"

        case .invalidEndpoint(let endpoint):
            return "Invalid endpoint: \(endpoint)"

        case .noProtocolAdapter:
            return "No protocol adapter configured"

        case .unsupportedOperation(let operation, let reason):
            return "Unsupported operation '\(operation)': \(reason)"

        case .middlewareError(let name, let error):
            return "Middleware '\(name)' error: \(error.localizedDescription)"

        case .middlewareChainBroken:
            return "Middleware chain broken"

        case .poolExhausted:
            return "Connection pool exhausted"

        case .poolClosed:
            return "Connection pool is closed"

        case .custom(let message, let underlyingError):
            if let error = underlyingError {
                return "\(message): \(error.localizedDescription)"
            }
            return message
        }
    }

    // MARK: - Equatable

    public static func == (lhs: NexusError, rhs: NexusError) -> Bool {
        switch (lhs, rhs) {
        case (.connectionTimeout, .connectionTimeout),
             (.connectionRefused, .connectionRefused),
             (.networkUnreachable, .networkUnreachable),
             (.connectionClosed, .connectionClosed),
             (.notConnected, .notConnected),
             (.heartbeatTimeout, .heartbeatTimeout),
             (.certificateValidationFailed, .certificateValidationFailed),
             (.invalidCredentials, .invalidCredentials),
             (.tlsHandshakeFailed, .tlsHandshakeFailed),
             (.untrustedCertificate, .untrustedCertificate),
             (.proxyAuthenticationFailed, .proxyAuthenticationFailed),
             (.requestTimeout, .requestTimeout),
             (.invalidResponse, .invalidResponse),
             (.bufferOverflow, .bufferOverflow),
             (.resourceExhausted, .resourceExhausted),
             (.outOfMemory, .outOfMemory),
             (.noProtocolAdapter, .noProtocolAdapter),
             (.middlewareChainBroken, .middlewareChainBroken),
             (.poolExhausted, .poolExhausted),
             (.poolClosed, .poolClosed):
            return true

        case (.invalidMessageFormat(let lhsReason), .invalidMessageFormat(let rhsReason)),
             (.unsupportedProtocolVersion(let lhsReason), .unsupportedProtocolVersion(let rhsReason)):
            return lhsReason == rhsReason

        case (.connectionAlreadyExists(let lhsId), .connectionAlreadyExists(let rhsId)),
             (.connectionNotFound(let lhsId), .connectionNotFound(let rhsId)):
            return lhsId == rhsId

        case (.authenticationFailed(let lhsReason), .authenticationFailed(let rhsReason)),
             (.protocolError(let lhsReason), .protocolError(let rhsReason)),
             (.invalidConfiguration(let lhsReason), .invalidConfiguration(let rhsReason)),
             (.tlsError(let lhsReason), .tlsError(let rhsReason)),
             (.certificateLoadFailed(let lhsReason), .certificateLoadFailed(let rhsReason)),
             (.proxyConnectionFailed(let lhsReason), .proxyConnectionFailed(let rhsReason)):
            return lhsReason == rhsReason

        case (.unsupportedProxyType(let lhsType), .unsupportedProxyType(let rhsType)):
            return lhsType == rhsType

        case (.missingRequiredConfiguration(let lhsKey), .missingRequiredConfiguration(let rhsKey)):
            return lhsKey == rhsKey

        case (.invalidStateTransition(let lhsFrom, let lhsTo), .invalidStateTransition(let rhsFrom, let rhsTo)):
            return lhsFrom == rhsFrom && lhsTo == rhsTo

        case (.operationNotAllowed(let lhsState), .operationNotAllowed(let rhsState)):
            return lhsState == rhsState

        case (.unsupportedOperation(let lhsOp, let lhsReason), .unsupportedOperation(let rhsOp, let rhsReason)):
            return lhsOp == rhsOp && lhsReason == rhsReason

        case (.middlewareError(let lhsName, _), .middlewareError(let rhsName, _)):
            return lhsName == rhsName

        case (.custom(let lhsMessage, _), .custom(let rhsMessage, _)):
            return lhsMessage == rhsMessage

        default:
            return false
        }
    }
}
