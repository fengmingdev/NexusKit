//
//  LoggingMiddleware.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//
//  使用统一日志系统的日志中间件

import Foundation

// MARK: - Logging Middleware

/// 日志中间件
///
/// 记录所有发送和接收的数据,用于调试和监控。
///
/// ## 功能特性
///
/// - 记录数据方向（发送/接收）
/// - 数据大小统计
/// - 时间戳
/// - 连接信息
/// - 支持自定义日志级别
/// - 使用统一日志系统
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
///     logLevel: .debug,
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
    private let logLevel: LogLevel

    /// 是否记录数据内容
    private let logData: Bool

    /// 最大数据长度（记录时）
    private let maxDataLength: Int

    /// 日志器名称
    private let loggerName: String

    // MARK: - Initialization

    /// 初始化日志中间件
    /// - Parameters:
    ///   - logLevel: 日志级别，默认为 `.info`
    ///   - logData: 是否记录数据内容，默认为 `false`
    ///   - maxDataLength: 记录数据内容时的最大长度，默认为 100 字节
    ///   - priority: 中间件优先级，默认为 10（高优先级）
    ///   - loggerName: 日志器名称，默认为 "NexusKit.Network"
    public init(
        logLevel: LogLevel = .info,
        logData: Bool = false,
        maxDataLength: Int = 100,
        priority: Int = 10,
        loggerName: String = "NexusKit.Network"
    ) {
        self.logLevel = logLevel
        self.logData = logData
        self.maxDataLength = maxDataLength
        self.priority = priority
        self.loggerName = loggerName
    }

    // MARK: - Middleware Protocol

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard logLevel <= .info else { return data }

        let message = formatMessage(
            direction: "Outgoing",
            connectionId: context.connectionId,
            endpoint: context.endpoint,
            dataSize: data.count,
            data: logData ? data : nil
        )

        await logMessage(message, level: logLevel)
        return data
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard logLevel <= .info else { return data }

        let message = formatMessage(
            direction: "Incoming",
            connectionId: context.connectionId,
            endpoint: context.endpoint,
            dataSize: data.count,
            data: logData ? data : nil
        )

        await logMessage(message, level: logLevel)
        return data
    }

    public func onConnect(connection: any Connection) async {
        guard logLevel <= .info else { return }
        await logMessage("🟢 [Connected] \(connection.id)", level: .info)
    }

    public func onDisconnect(connection: any Connection, reason: DisconnectReason) async {
        guard logLevel <= .info else { return }
        await logMessage("🔴 [Disconnected] \(connection.id), Reason: \(reason)", level: .info)
    }

    public func onError(error: Error, context: MiddlewareContext) async {
        guard logLevel <= .error else { return }
        await logMessage("⚠️ [Error] Connection: \(context.connectionId), Error: \(error.localizedDescription)", level: .error, error: error)
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

    private func logMessage(_ message: String, level: LogLevel, error: Error? = nil) async {
        await log(
            level: level,
            message,
            error: error,
            logger: loggerName
        )
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
