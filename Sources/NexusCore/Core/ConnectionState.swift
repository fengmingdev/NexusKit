//
//  ConnectionState.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

/// 连接状态
public enum ConnectionState: Sendable, Equatable, CustomStringConvertible {
    /// 未连接
    case disconnected

    /// 正在连接
    case connecting

    /// 已连接
    case connected

    /// 正在重连
    case reconnecting(attempt: Int)

    /// 正在断开连接
    case disconnecting

    // MARK: - Computed Properties

    /// 是否处于活跃状态（已连接或正在重连）
    public var isActive: Bool {
        switch self {
        case .connected, .reconnecting:
            return true
        default:
            return false
        }
    }

    /// 是否可以发送数据
    public var canSend: Bool {
        self == .connected
    }

    /// 是否可以接收数据
    public var canReceive: Bool {
        self == .connected
    }

    /// 是否正在进行连接操作
    public var isConnecting: Bool {
        switch self {
        case .connecting, .reconnecting:
            return true
        default:
            return false
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reconnecting(let attempt):
            return "reconnecting(attempt: \(attempt))"
        case .disconnecting:
            return "disconnecting"
        }
    }

    // MARK: - State Transition Validation

    /// 验证状态转换是否合法
    /// - Parameters:
    ///   - from: 当前状态
    ///   - to: 目标状态
    /// - Returns: 是否允许转换
    public static func canTransition(from: ConnectionState, to: ConnectionState) -> Bool {
        switch (from, to) {
        // 从未连接状态可以转到连接中
        case (.disconnected, .connecting):
            return true

        // 从连接中可以转到已连接或断开
        case (.connecting, .connected),
             (.connecting, .disconnected),
             (.connecting, .disconnecting):
            return true

        // 从已连接可以转到断开中或重连中
        case (.connected, .disconnecting),
             (.connected, .reconnecting):
            return true

        // 从重连中可以转到连接中或已断开
        case (.reconnecting, .connecting),
             (.reconnecting, .disconnected),
             (.reconnecting, .disconnecting):
            return true

        // 从断开中只能转到已断开
        case (.disconnecting, .disconnected):
            return true

        // 从未连接可以转到重连中（用于自动重连）
        case (.disconnected, .reconnecting):
            return true

        default:
            return false
        }
    }
}

/// 断开连接原因
public enum DisconnectReason: Sendable, Equatable, CustomStringConvertible {
    /// 客户端主动断开
    case clientInitiated

    /// 服务器主动断开
    case serverInitiated

    /// 网络错误
    case networkError(Error?)

    /// 认证失败
    case authenticationFailed

    /// 超时
    case timeout

    /// 心跳超时
    case heartbeatTimeout

    /// 协议错误
    case protocolError

    /// 应用即将终止
    case applicationTerminating

    /// 自定义原因
    case custom(String)

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .clientInitiated:
            return "client initiated"
        case .serverInitiated:
            return "server initiated"
        case .networkError(let error):
            if let error = error {
                return "network error: \(error.localizedDescription)"
            }
            return "network error"
        case .authenticationFailed:
            return "authentication failed"
        case .timeout:
            return "timeout"
        case .heartbeatTimeout:
            return "heartbeat timeout"
        case .protocolError:
            return "protocol error"
        case .applicationTerminating:
            return "application terminating"
        case .custom(let reason):
            return reason
        }
    }

    // MARK: - Equatable

    public static func == (lhs: DisconnectReason, rhs: DisconnectReason) -> Bool {
        switch (lhs, rhs) {
        case (.clientInitiated, .clientInitiated),
             (.serverInitiated, .serverInitiated),
             (.authenticationFailed, .authenticationFailed),
             (.timeout, .timeout),
             (.heartbeatTimeout, .heartbeatTimeout),
             (.protocolError, .protocolError),
             (.applicationTerminating, .applicationTerminating):
            return true

        case (.networkError, .networkError):
            // 简化比较，只要都是网络错误就认为相等
            return true

        case (.custom(let lhsReason), .custom(let rhsReason)):
            return lhsReason == rhsReason

        default:
            return false
        }
    }
}
