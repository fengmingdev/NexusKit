//
//  LoggingMiddleware.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
import OSLog

// MARK: - Logging Middleware

/// 日志中间件
///
/// 记录所有发送和接收的数据，用于调试和监控。
///
/// ## 功能特性
///
/// - 记录数据方向（发送/接收）
/// - 数据大小统计
/// - 时间戳
/// - 连接信息
/// - 支持自定义日志级别
/// - 使用 OSLog 进行高性能日志记录
///
/// ## 使用示例
///
/// ### 基础使用
/// ```swift
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(LoggingMiddleware())
///     .connect()
/// ```
///
/// ### 自定义配置
/// ```swift
/// let logger = LoggingMiddleware(
///     level: .debug,
///     logData: true,          // 记录数据内容（仅开发环境）
///     maxDataLength: 200      // 最多显示 200 字节
/// )
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(logger)
///     .connect()
/// ```
///
/// ### 输出示例
/// ```
/// [NexusKit][Outgoing] Connection: tcp-1, Size: 1024 bytes
/// [NexusKit][Incoming] Connection: tcp-1, Size: 2048 bytes
/// ```
public struct LoggingMiddleware: Middleware {
    // MARK: - Properties

    public let name = "LoggingMiddleware"
    public let priority: Int

    /// 日志级别
    private let level: LogLevel

    /// 是否记录数据内容
    private let logData: Bool

    /// 最大数据长度（记录时）
    private let maxDataLength: Int

    /// OSLog 日志器
    private let logger: Logger

    // MARK: - Log Level

    /// 日志级别
    public enum LogLevel: Int, Comparable {
        case verbose = 0
        case debug = 1
        case info = 2
        case warning = 3
        case error = 4
        case none = 5

        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Initialization

    /// 初始化日志中间件
    /// - Parameters:
    ///   - level: 日志级别，默认为 `.info`
    ///   - logData: 是否记录数据内容，默认为 `false`
    ///   - maxDataLength: 记录数据内容时的最大长度，默认为 100 字节
    ///   - priority: 中间件优先级，默认为 10（高优先级）
    public init(
        level: LogLevel = .info,
        logData: Bool = false,
        maxDataLength: Int = 100,
        priority: Int = 10
    ) {
        self.level = level
        self.logData = logData
        self.maxDataLength = maxDataLength
        self.priority = priority
        self.logger = Logger(subsystem: "com.nexuskit", category: "network")
    }

    // MARK: - Middleware Protocol

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard level <= .info else { return data }

        let message = formatMessage(
            direction: "Outgoing",
            connectionId: context.connectionId,
            endpoint: context.endpoint,
            dataSize: data.count,
            data: logData ? data : nil
        )

        switch level {
        case .verbose, .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .none:
            break
        }

        return data
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard level <= .info else { return data }

        let message = formatMessage(
            direction: "Incoming",
            connectionId: context.connectionId,
            endpoint: context.endpoint,
            dataSize: data.count,
            data: logData ? data : nil
        )

        switch level {
        case .verbose, .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .none:
            break
        }

        return data
    }

    public func onConnect(connection: any Connection) async {
        guard level <= .info else { return }

        let connectionId = connection.id
        logger.info("🟢 [Connected] \(connectionId, privacy: .public)")
    }

    public func onDisconnect(connection: any Connection, reason: DisconnectReason) async {
        guard level <= .info else { return }

        let connectionId = connection.id
        logger.info("🔴 [Disconnected] \(connectionId, privacy: .public), Reason: \(String(describing: reason), privacy: .public)")
    }

    public func onError(error: Error, context: MiddlewareContext) async {
        guard level <= .error else { return }

        logger.error("⚠️ [Error] Connection: \(context.connectionId, privacy: .public), Error: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Private Methods

    private func formatMessage(
        direction: String,
        connectionId: String,
        endpoint: Endpoint,
        dataSize: Int,
        data: Data?
    ) -> String {
        var message = "[\(direction)] Connection: \(connectionId), Endpoint: \(endpoint.host):\(endpoint.port ?? 0), Size: \(dataSize) bytes"

        if let data = data, !data.isEmpty {
            let displayData = data.prefix(maxDataLength)
            if let string = String(data: displayData, encoding: .utf8) {
                message += ", Data: \"\(string)\""
            } else {
                message += ", Data (hex): \(displayData.hexString)"
            }

            if data.count > maxDataLength {
                message += "..."
            }
        }

        return message
    }
}

// MARK: - Print Logging Middleware

/// 简单的打印日志中间件（用于调试）
///
/// 使用标准 `print` 函数输出日志，适合快速调试。
///
/// ## 使用示例
/// ```swift
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(PrintLoggingMiddleware())
///     .connect()
/// ```
public struct PrintLoggingMiddleware: Middleware {
    public let name = "PrintLoggingMiddleware"
    public let priority = 10

    /// 是否显示时间戳
    private let showTimestamp: Bool

    /// 是否显示数据内容
    private let showData: Bool

    /// 初始化
    /// - Parameters:
    ///   - showTimestamp: 是否显示时间戳，默认为 `true`
    ///   - showData: 是否显示数据内容，默认为 `false`
    public init(showTimestamp: Bool = true, showData: Bool = false) {
        self.showTimestamp = showTimestamp
        self.showData = showData
    }

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        let timestamp = showTimestamp ? "[\(formatTimestamp())] " : ""
        var message = "\(timestamp)📤 发送: \(data.count) 字节"

        if showData, let string = String(data: data.prefix(100), encoding: .utf8) {
            message += " -> \"\(string)\""
        }

        print(message)
        return data
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        let timestamp = showTimestamp ? "[\(formatTimestamp())] " : ""
        var message = "\(timestamp)📥 接收: \(data.count) 字节"

        if showData, let string = String(data: data.prefix(100), encoding: .utf8) {
            message += " <- \"\(string)\""
        }

        print(message)
        return data
    }

    public func onConnect(connection: any Connection) async {
        let timestamp = showTimestamp ? "[\(formatTimestamp())] " : ""
        print("\(timestamp)🟢 已连接: \(connection.id)")
    }

    public func onDisconnect(connection: any Connection, reason: DisconnectReason) async {
        let timestamp = showTimestamp ? "[\(formatTimestamp())] " : ""
        print("\(timestamp)🔴 已断开: \(connection.id) - \(reason)")
    }

    private func formatTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
