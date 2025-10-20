//
//  ErrorClassification.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  错误分类系统 - 用于智能错误处理和重试决策

import Foundation

// MARK: - Error Classification

/// 错误恢复性分类
///
/// 用于判断错误是否可以通过重试或其他策略恢复。
public enum ErrorRecoverability: Sendable {
    /// 可恢复错误 - 可以通过重试解决
    case recoverable

    /// 临时错误 - 可能在短时间后自行恢复
    case transient

    /// 永久错误 - 无法通过重试解决
    case permanent

    /// 致命错误 - 需要立即终止连接
    case fatal
}

/// 错误严重程度
///
/// 用于日志记录和监控告警。
public enum ErrorSeverity: Int, Sendable, Comparable {
    case trace = 0      // 追踪信息
    case debug = 1      // 调试信息
    case info = 2       // 普通信息
    case warning = 3    // 警告
    case error = 4      // 错误
    case critical = 5   // 严重错误

    public static func < (lhs: ErrorSeverity, rhs: ErrorSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 错误类别
///
/// 用于统计和分析不同类型的错误。
public enum ErrorCategory: Sendable {
    /// 网络相关错误
    case network

    /// 连接相关错误
    case connection

    /// 认证/授权错误
    case authentication

    /// 协议错误
    case `protocol`

    /// 超时错误
    case timeout

    /// 资源限制错误
    case resourceLimit

    /// 配置错误
    case configuration

    /// 未知错误
    case unknown
}

/// 错误分类信息
///
/// 包含错误的完整分类信息，用于决策处理策略。
public struct ErrorClassification: Sendable {
    /// 错误恢复性
    public let recoverability: ErrorRecoverability

    /// 错误严重程度
    public let severity: ErrorSeverity

    /// 错误类别
    public let category: ErrorCategory

    /// 是否应该重试
    public let shouldRetry: Bool

    /// 建议的重试延迟（秒）
    public let suggestedRetryDelay: TimeInterval?

    /// 是否应该触发熔断器
    public let shouldTriggerCircuitBreaker: Bool

    /// 是否应该告警
    public let shouldAlert: Bool

    /// 错误描述
    public let description: String

    public init(
        recoverability: ErrorRecoverability,
        severity: ErrorSeverity,
        category: ErrorCategory,
        shouldRetry: Bool = false,
        suggestedRetryDelay: TimeInterval? = nil,
        shouldTriggerCircuitBreaker: Bool = false,
        shouldAlert: Bool = false,
        description: String = ""
    ) {
        self.recoverability = recoverability
        self.severity = severity
        self.category = category
        self.shouldRetry = shouldRetry
        self.suggestedRetryDelay = suggestedRetryDelay
        self.shouldTriggerCircuitBreaker = shouldTriggerCircuitBreaker
        self.shouldAlert = shouldAlert
        self.description = description
    }
}

// MARK: - Error Classifier

/// 错误分类器
///
/// 负责将各种错误转换为标准化的错误分类信息。
public struct ErrorClassifier: Sendable {

    /// 分类错误
    /// - Parameter error: 要分类的错误
    /// - Returns: 错误分类信息
    public static func classify(_ error: Error) -> ErrorClassification {
        // 处理NexusError
        if let nexusError = error as? NexusError {
            return classifyNexusError(nexusError)
        }

        // 处理URLError
        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }

        // 处理POSIXError
        if let posixError = error as? POSIXError {
            return classifyPOSIXError(posixError)
        }

        // 处理CocoaError
        if let cocoaError = error as? CocoaError {
            return classifyCocoaError(cocoaError)
        }

        // 未知错误
        return ErrorClassification(
            recoverability: .permanent,
            severity: .error,
            category: .unknown,
            shouldRetry: false,
            description: error.localizedDescription
        )
    }

    // MARK: - NexusError Classification

    private static func classifyNexusError(_ error: NexusError) -> ErrorClassification {
        switch error {
        // 网络错误 - 可恢复
        case .networkUnreachable:
            return ErrorClassification(
                recoverability: .transient,
                severity: .warning,
                category: .network,
                shouldRetry: true,
                suggestedRetryDelay: 2.0,
                shouldTriggerCircuitBreaker: false,
                description: "网络不可达"
            )

        case .connectionTimeout, .connectionRefused:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .error,
                category: .network,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                shouldTriggerCircuitBreaker: true,
                description: "连接失败"
            )

        // 连接错误 - 部分可恢复
        case .connectionAlreadyExists, .connectionNotFound:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .error,
                category: .connection,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                shouldTriggerCircuitBreaker: true,
                description: "连接失败"
            )

        case .connectionClosed:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .warning,
                category: .connection,
                shouldRetry: true,
                suggestedRetryDelay: 0.5,
                shouldTriggerCircuitBreaker: false,
                description: "连接已关闭"
            )

        case .notConnected:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .warning,
                category: .connection,
                shouldRetry: true,
                suggestedRetryDelay: 0.5,
                description: "未连接"
            )

        // 超时错误 - 可重试
        case .requestTimeout:
            return ErrorClassification(
                recoverability: .transient,
                severity: .warning,
                category: .timeout,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                shouldTriggerCircuitBreaker: true,
                description: "超时"
            )

        case .heartbeatTimeout:
            return ErrorClassification(
                recoverability: .transient,
                severity: .warning,
                category: .timeout,
                shouldRetry: true,
                suggestedRetryDelay: 2.0,
                shouldTriggerCircuitBreaker: true,
                description: "心跳超时"
            )

        // 认证错误 - 不可恢复
        case .authenticationFailed, .invalidCredentials:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .error,
                category: .authentication,
                shouldRetry: false,
                shouldAlert: true,
                description: "认证失败"
            )

        // 协议错误 - 永久错误
        case .protocolError:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .error,
                category: .protocol,
                shouldRetry: false,
                shouldAlert: true,
                description: "协议错误"
            )

        case .invalidMessageFormat:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .error,
                category: .protocol,
                shouldRetry: false,
                description: "无效消息格式"
            )

        // 资源限制 - 临时错误
        case .bufferOverflow:
            return ErrorClassification(
                recoverability: .transient,
                severity: .warning,
                category: .resourceLimit,
                shouldRetry: true,
                suggestedRetryDelay: 0.5,
                description: "缓冲区溢出"
            )

        // 配置错误 - 永久错误
        case .invalidConfiguration, .invalidEndpoint:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .critical,
                category: .configuration,
                shouldRetry: false,
                shouldAlert: true,
                description: "配置错误"
            )

        case .tlsError, .tlsHandshakeFailed:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .critical,
                category: .configuration,
                shouldRetry: false,
                shouldAlert: true,
                description: "TLS配置错误"
            )

        // 其他错误
        case .sendFailed, .receiveFailed:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .error,
                category: .network,
                shouldRetry: true,
                suggestedRetryDelay: 0.5,
                shouldTriggerCircuitBreaker: true,
                description: "发送/接收失败"
            )

        case .invalidStateTransition:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .error,
                category: .unknown,
                shouldRetry: false,
                description: "无效状态转换"
            )

        default:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .error,
                category: .unknown,
                shouldRetry: false,
                description: error.localizedDescription
            )
        }
    }

    // MARK: - URLError Classification

    private static func classifyURLError(_ error: URLError) -> ErrorClassification {
        switch error.code {
        // 网络不可达
        case .notConnectedToInternet, .networkConnectionLost:
            return ErrorClassification(
                recoverability: .transient,
                severity: .warning,
                category: .network,
                shouldRetry: true,
                suggestedRetryDelay: 2.0,
                shouldTriggerCircuitBreaker: false,
                description: "网络不可达"
            )

        // 超时
        case .timedOut:
            return ErrorClassification(
                recoverability: .transient,
                severity: .warning,
                category: .timeout,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                shouldTriggerCircuitBreaker: true,
                description: "请求超时"
            )

        // DNS解析失败
        case .cannotFindHost, .dnsLookupFailed:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .error,
                category: .network,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                shouldTriggerCircuitBreaker: true,
                description: "DNS解析失败"
            )

        // 服务器错误
        case .cannotConnectToHost, .badServerResponse:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .error,
                category: .connection,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                shouldTriggerCircuitBreaker: true,
                description: "服务器连接失败"
            )

        // TLS错误
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .critical,
                category: .configuration,
                shouldRetry: false,
                shouldAlert: true,
                description: "TLS验证失败"
            )

        // 取消操作
        case .cancelled:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .info,
                category: .unknown,
                shouldRetry: false,
                description: "操作已取消"
            )

        default:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .error,
                category: .network,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                description: error.localizedDescription
            )
        }
    }

    // MARK: - POSIXError Classification

    private static func classifyPOSIXError(_ error: POSIXError) -> ErrorClassification {
        switch error.code {
        // 连接被拒绝
        case .ECONNREFUSED:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .error,
                category: .connection,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                shouldTriggerCircuitBreaker: true,
                description: "连接被拒绝"
            )

        // 连接重置
        case .ECONNRESET:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .warning,
                category: .connection,
                shouldRetry: true,
                suggestedRetryDelay: 0.5,
                shouldTriggerCircuitBreaker: true,
                description: "连接被重置"
            )

        // 网络不可达
        case .ENETUNREACH, .EHOSTUNREACH:
            return ErrorClassification(
                recoverability: .transient,
                severity: .warning,
                category: .network,
                shouldRetry: true,
                suggestedRetryDelay: 2.0,
                shouldTriggerCircuitBreaker: false,
                description: "网络不可达"
            )

        // 超时
        case .ETIMEDOUT:
            return ErrorClassification(
                recoverability: .transient,
                severity: .warning,
                category: .timeout,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                shouldTriggerCircuitBreaker: true,
                description: "操作超时"
            )

        // 管道破裂（对端关闭）
        case .EPIPE:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .warning,
                category: .connection,
                shouldRetry: true,
                suggestedRetryDelay: 0.5,
                description: "连接已断开"
            )

        default:
            return ErrorClassification(
                recoverability: .recoverable,
                severity: .error,
                category: .unknown,
                shouldRetry: true,
                suggestedRetryDelay: 1.0,
                description: error.localizedDescription
            )
        }
    }

    // MARK: - CocoaError Classification

    private static func classifyCocoaError(_ error: CocoaError) -> ErrorClassification {
        switch error.code {
        case .fileReadNoSuchFile, .fileNoSuchFile:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .error,
                category: .configuration,
                shouldRetry: false,
                description: "文件不存在"
            )

        case .fileReadNoPermission:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .error,
                category: .configuration,
                shouldRetry: false,
                shouldAlert: true,
                description: "文件权限不足"
            )

        default:
            return ErrorClassification(
                recoverability: .permanent,
                severity: .error,
                category: .unknown,
                shouldRetry: false,
                description: error.localizedDescription
            )
        }
    }
}

// MARK: - Error Classification Extensions

extension Error {
    /// 获取错误分类
    public var classification: ErrorClassification {
        ErrorClassifier.classify(self)
    }

    /// 是否应该重试
    public var shouldRetry: Bool {
        classification.shouldRetry
    }

    /// 建议的重试延迟
    public var suggestedRetryDelay: TimeInterval? {
        classification.suggestedRetryDelay
    }

    /// 是否应该触发熔断器
    public var shouldTriggerCircuitBreaker: Bool {
        classification.shouldTriggerCircuitBreaker
    }
}

// MARK: - Custom Error Classification

/// 自定义错误分类器协议
///
/// 允许用户提供自定义的错误分类逻辑。
public protocol CustomErrorClassifier: Sendable {
    /// 分类错误
    /// - Parameter error: 要分类的错误
    /// - Returns: 错误分类信息，返回nil表示使用默认分类
    func classify(_ error: Error) -> ErrorClassification?
}

/// 复合错误分类器
///
/// 支持多个自定义分类器链式处理。
public struct CompositeErrorClassifier: Sendable {
    private let classifiers: [any CustomErrorClassifier]

    public init(classifiers: [any CustomErrorClassifier] = []) {
        self.classifiers = classifiers
    }

    /// 分类错误
    /// - Parameter error: 要分类的错误
    /// - Returns: 错误分类信息
    public func classify(_ error: Error) -> ErrorClassification {
        // 尝试自定义分类器
        for classifier in classifiers {
            if let classification = classifier.classify(error) {
                return classification
            }
        }

        // 使用默认分类器
        return ErrorClassifier.classify(error)
    }
}
