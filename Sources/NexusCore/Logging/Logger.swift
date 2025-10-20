//
//  Logger.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  统一日志系统

import Foundation

// MARK: - Log Level

/// 日志级别
public enum LogLevel: Int, Sendable, Comparable, CaseIterable {
    case trace = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case critical = 5

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 日志级别标签
    public var label: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRIT"
        }
    }

    /// 日志级别符号
    public var symbol: String {
        switch self {
        case .trace: return "⚪️"
        case .debug: return "🔵"
        case .info: return "🟢"
        case .warning: return "🟡"
        case .error: return "🔴"
        case .critical: return "🔥"
        }
    }
}

// MARK: - Log Message

/// 日志消息
public struct LogMessage: Sendable {
    /// 日志级别
    public let level: LogLevel

    /// 消息内容
    public let message: String

    /// 时间戳
    public let timestamp: Date

    /// 文件名
    public let file: String

    /// 函数名
    public let function: String

    /// 行号
    public let line: Int

    /// 上下文元数据
    public let metadata: [String: String]

    /// 错误信息（如果有）
    public let error: Error?

    public init(
        level: LogLevel,
        message: String,
        timestamp: Date = Date(),
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        metadata: [String: String] = [:],
        error: Error? = nil
    ) {
        self.level = level
        self.message = message
        self.timestamp = timestamp
        self.file = file
        self.function = function
        self.line = line
        self.metadata = metadata
        self.error = error
    }

    /// 文件名（去除路径）
    public var fileName: String {
        (file as NSString).lastPathComponent
    }
}

// MARK: - Logger Protocol

/// 日志器协议
public protocol Logger: Sendable {
    /// 日志器名称
    var name: String { get }

    /// 最小日志级别
    var minimumLevel: LogLevel { get }

    /// 记录日志
    func log(_ message: LogMessage) async

    /// 是否启用指定级别的日志
    func isEnabled(level: LogLevel) -> Bool
}

extension Logger {
    public func isEnabled(level: LogLevel) -> Bool {
        level >= minimumLevel
    }
}

// MARK: - Default Logger

/// 默认日志实现
public actor DefaultLogger: Logger {
    public let name: String
    public let minimumLevel: LogLevel
    private let targets: [any LogTarget]
    private let formatter: any LogFormatter
    private let filters: [any LogFilter]

    public init(
        name: String,
        minimumLevel: LogLevel = .info,
        targets: [any LogTarget] = [],
        formatter: any LogFormatter = DefaultLogFormatter(),
        filters: [any LogFilter] = []
    ) {
        self.name = name
        self.minimumLevel = minimumLevel
        self.targets = targets.isEmpty ? [ConsoleLogTarget()] : targets
        self.formatter = formatter
        self.filters = filters
    }

    public func log(_ message: LogMessage) async {
        guard isEnabled(level: message.level) else { return }

        // 应用过滤器
        for filter in filters {
            if await !filter.shouldLog(message) {
                return
            }
        }

        // 格式化消息
        let formattedMessage = formatter.format(message)

        // 写入所有目标
        for target in targets {
            await target.write(formattedMessage, level: message.level)
        }
    }
}

// MARK: - Global Logger

/// 全局日志器
public actor GlobalLogger {
    public static let shared = GlobalLogger()

    private var loggers: [String: any Logger] = [:]
    private var defaultLogger: any Logger

    private init() {
        self.defaultLogger = DefaultLogger(
            name: "NexusKit",
            minimumLevel: .info
        )
    }

    /// 注册日志器
    public func register(_ logger: any Logger, for name: String) {
        loggers[name] = logger
    }

    /// 获取日志器
    public func logger(for name: String) -> any Logger {
        loggers[name] ?? defaultLogger
    }

    /// 设置默认日志器
    public func setDefault(_ logger: any Logger) {
        self.defaultLogger = logger
    }

    /// 记录日志
    public func log(_ message: LogMessage, logger: String = "NexusKit") async {
        let targetLogger = loggers[logger] ?? defaultLogger
        await targetLogger.log(message)
    }
}

// MARK: - Logging Extensions

extension Logger {
    /// 记录 trace 日志
    public func trace(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(LogMessage(
            level: .trace,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata
        ))
    }

    /// 记录 debug 日志
    public func debug(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(LogMessage(
            level: .debug,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata
        ))
    }

    /// 记录 info 日志
    public func info(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(LogMessage(
            level: .info,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata
        ))
    }

    /// 记录 warning 日志
    public func warning(
        _ message: String,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(LogMessage(
            level: .warning,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata
        ))
    }

    /// 记录 error 日志
    public func error(
        _ message: String,
        error: Error? = nil,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(LogMessage(
            level: .error,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata,
            error: error
        ))
    }

    /// 记录 critical 日志
    public func critical(
        _ message: String,
        error: Error? = nil,
        metadata: [String: String] = [:],
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        await log(LogMessage(
            level: .critical,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata,
            error: error
        ))
    }
}

// MARK: - Convenience Functions

/// 全局日志函数
public func log(
    level: LogLevel,
    _ message: String,
    metadata: [String: String] = [:],
    error: Error? = nil,
    logger: String = "NexusKit",
    file: String = #file,
    function: String = #function,
    line: Int = #line
) async {
    await GlobalLogger.shared.log(
        LogMessage(
            level: level,
            message: message,
            file: file,
            function: function,
            line: line,
            metadata: metadata,
            error: error
        ),
        logger: logger
    )
}

public func logTrace(_ message: String, logger: String = "NexusKit") async {
    await log(level: .trace, message, logger: logger)
}

public func logDebug(_ message: String, logger: String = "NexusKit") async {
    await log(level: .debug, message, logger: logger)
}

public func logInfo(_ message: String, logger: String = "NexusKit") async {
    await log(level: .info, message, logger: logger)
}

public func logWarning(_ message: String, logger: String = "NexusKit") async {
    await log(level: .warning, message, logger: logger)
}

public func logError(_ message: String, error: Error? = nil, logger: String = "NexusKit") async {
    await log(level: .error, message, error: error, logger: logger)
}

public func logCritical(_ message: String, error: Error? = nil, logger: String = "NexusKit") async {
    await log(level: .critical, message, error: error, logger: logger)
}
