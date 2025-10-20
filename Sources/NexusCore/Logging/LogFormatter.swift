//
//  LogFormatter.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  日志格式化器

import Foundation

// MARK: - Log Formatter Protocol

/// 日志格式化器协议
public protocol LogFormatter: Sendable {
    /// 格式化日志消息
    func format(_ message: LogMessage) -> String
}

// MARK: - Default Log Formatter

/// 默认日志格式化器
///
/// 输出格式：
/// ```
/// 2025-10-20 15:30:45.123 [INFO] 🟢 MyModule - Connection established
/// ```
public struct DefaultLogFormatter: LogFormatter, Sendable {

    /// 是否包含时间戳
    public let includeTimestamp: Bool

    /// 是否包含文件位置
    public let includeLocation: Bool

    /// 是否包含符号（emoji）
    public let includeSymbol: Bool

    /// 是否包含元数据
    public let includeMetadata: Bool

    /// 时间戳格式
    public let timestampFormat: String

    public init(
        includeTimestamp: Bool = true,
        includeLocation: Bool = false,
        includeSymbol: Bool = true,
        includeMetadata: Bool = true,
        timestampFormat: String = "yyyy-MM-dd HH:mm:ss.SSS"
    ) {
        self.includeTimestamp = includeTimestamp
        self.includeLocation = includeLocation
        self.includeSymbol = includeSymbol
        self.includeMetadata = includeMetadata
        self.timestampFormat = timestampFormat
    }

    public func format(_ message: LogMessage) -> String {
        var parts: [String] = []

        // 时间戳
        if includeTimestamp {
            let formatter = DateFormatter()
            formatter.dateFormat = timestampFormat
            parts.append(formatter.string(from: message.timestamp))
        }

        // 日志级别
        var levelPart = "[\(message.level.label)]"
        if includeSymbol {
            levelPart += " \(message.level.symbol)"
        }
        parts.append(levelPart)

        // 消息内容
        parts.append(message.message)

        // 元数据
        if includeMetadata && !message.metadata.isEmpty {
            let metadataStr = message.metadata
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            parts.append("[\(metadataStr)]")
        }

        // 错误信息
        if let error = message.error {
            parts.append("Error: \(error)")
        }

        // 文件位置
        if includeLocation {
            parts.append("(\(message.fileName):\(message.line) \(message.function))")
        }

        return parts.joined(separator: " ")
    }
}

// MARK: - JSON Log Formatter

/// JSON 日志格式化器
///
/// 输出格式：
/// ```json
/// {
///   "timestamp": "2025-10-20T15:30:45.123Z",
///   "level": "info",
///   "message": "Connection established",
///   "metadata": {"host": "localhost", "port": "8080"},
///   "location": {
///     "file": "TCPConnection.swift",
///     "function": "connect()",
///     "line": 42
///   }
/// }
/// ```
public struct JSONLogFormatter: LogFormatter, Sendable {

    /// 是否美化输出
    public let prettyPrint: Bool

    /// 是否包含文件位置
    public let includeLocation: Bool

    public init(prettyPrint: Bool = false, includeLocation: Bool = true) {
        self.prettyPrint = prettyPrint
        self.includeLocation = includeLocation
    }

    public func format(_ message: LogMessage) -> String {
        var json: [String: Any] = [:]

        // 时间戳（ISO 8601 格式）
        json["timestamp"] = ISO8601DateFormatter().string(from: message.timestamp)

        // 日志级别
        json["level"] = message.level.label.lowercased()

        // 消息内容
        json["message"] = message.message

        // 元数据
        if !message.metadata.isEmpty {
            json["metadata"] = message.metadata
        }

        // 错误信息
        if let error = message.error {
            json["error"] = [
                "description": String(describing: error),
                "type": String(describing: type(of: error))
            ]
        }

        // 文件位置
        if includeLocation {
            json["location"] = [
                "file": message.fileName,
                "function": message.function,
                "line": message.line
            ]
        }

        // 序列化为 JSON
        do {
            let options: JSONSerialization.WritingOptions = prettyPrint ? [.prettyPrinted, .sortedKeys] : []
            let data = try JSONSerialization.data(withJSONObject: json, options: options)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to serialize log message\"}"
        }
    }
}

// MARK: - Compact Log Formatter

/// 紧凑日志格式化器
///
/// 输出格式：
/// ```
/// 15:30:45 I Connection established
/// ```
public struct CompactLogFormatter: LogFormatter, Sendable {

    public init() {}

    public func format(_ message: LogMessage) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: message.timestamp)

        let levelChar = String(message.level.label.prefix(1))

        return "\(time) \(levelChar) \(message.message)"
    }
}

// MARK: - Detailed Log Formatter

/// 详细日志格式化器
///
/// 输出格式：
/// ```
/// ========================================
/// Time:     2025-10-20 15:30:45.123
/// Level:    INFO 🟢
/// Message:  Connection established
/// Location: TCPConnection.swift:42 connect()
/// Metadata: host=localhost, port=8080
/// ========================================
/// ```
public struct DetailedLogFormatter: LogFormatter, Sendable {

    public init() {}

    public func format(_ message: LogMessage) -> String {
        var lines: [String] = []

        lines.append("========================================")

        // 时间戳
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        lines.append("Time:     \(formatter.string(from: message.timestamp))")

        // 日志级别
        lines.append("Level:    \(message.level.label) \(message.level.symbol)")

        // 消息内容
        lines.append("Message:  \(message.message)")

        // 文件位置
        lines.append("Location: \(message.fileName):\(message.line) \(message.function)")

        // 元数据
        if !message.metadata.isEmpty {
            let metadataStr = message.metadata
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            lines.append("Metadata: \(metadataStr)")
        }

        // 错误信息
        if let error = message.error {
            lines.append("Error:    \(error)")
        }

        lines.append("========================================")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Custom Log Formatter

/// 自定义日志格式化器
///
/// 使用闭包自定义格式化逻辑。
public struct CustomLogFormatter: LogFormatter, Sendable {

    private let formatter: @Sendable (LogMessage) -> String

    public init(formatter: @escaping @Sendable (LogMessage) -> String) {
        self.formatter = formatter
    }

    public func format(_ message: LogMessage) -> String {
        formatter(message)
    }
}

// MARK: - Template Log Formatter

/// 模板日志格式化器
///
/// 使用模板字符串格式化日志。
///
/// ## 支持的占位符
///
/// - `{timestamp}` - 时间戳
/// - `{level}` - 日志级别
/// - `{symbol}` - 日志符号
/// - `{message}` - 消息内容
/// - `{file}` - 文件名
/// - `{function}` - 函数名
/// - `{line}` - 行号
/// - `{metadata}` - 元数据
/// - `{error}` - 错误信息
///
/// ## 示例
///
/// ```swift
/// let formatter = TemplateLogFormatter(
///     template: "[{timestamp}] {level} - {message} ({file}:{line})"
/// )
/// ```
public struct TemplateLogFormatter: LogFormatter, Sendable {

    /// 模板字符串
    public let template: String

    /// 时间戳格式
    public let timestampFormat: String

    public init(
        template: String = "{timestamp} [{level}] {symbol} {message}",
        timestampFormat: String = "yyyy-MM-dd HH:mm:ss.SSS"
    ) {
        self.template = template
        self.timestampFormat = timestampFormat
    }

    public func format(_ message: LogMessage) -> String {
        var result = template

        // 替换占位符
        let replacements: [String: String] = [
            "{timestamp}": formatTimestamp(message.timestamp),
            "{level}": message.level.label,
            "{symbol}": message.level.symbol,
            "{message}": message.message,
            "{file}": message.fileName,
            "{function}": message.function,
            "{line}": String(message.line),
            "{metadata}": formatMetadata(message.metadata),
            "{error}": message.error.map { String(describing: $0) } ?? ""
        ]

        for (placeholder, value) in replacements {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }

        return result
    }

    /// 格式化时间戳
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = timestampFormat
        return formatter.string(from: date)
    }

    /// 格式化元数据
    private func formatMetadata(_ metadata: [String: String]) -> String {
        guard !metadata.isEmpty else { return "" }
        return metadata
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }
}

// MARK: - Color Log Formatter

/// 彩色日志格式化器（支持 ANSI 转义码）
public struct ColorLogFormatter: LogFormatter, Sendable {

    /// 是否启用颜色
    public let enabled: Bool

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public func format(_ message: LogMessage) -> String {
        guard enabled else {
            return DefaultLogFormatter().format(message)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let time = formatter.string(from: message.timestamp)

        let levelColor = colorCode(for: message.level)
        let reset = "\u{001B}[0m"

        var parts: [String] = []
        parts.append("[\(time)]")
        parts.append("\(levelColor)\(message.level.symbol) \(message.level.label)\(reset)")
        parts.append(message.message)

        if !message.metadata.isEmpty {
            let metadataStr = message.metadata
                .map { "\(colorCode(for: .info))\($0.key)\(reset)=\($0.value)" }
                .joined(separator: ", ")
            parts.append("[\(metadataStr)]")
        }

        return parts.joined(separator: " ")
    }

    /// 获取级别对应的颜色代码
    private func colorCode(for level: LogLevel) -> String {
        switch level {
        case .trace:
            return "\u{001B}[37m"  // 白色
        case .debug:
            return "\u{001B}[36m"  // 青色
        case .info:
            return "\u{001B}[32m"  // 绿色
        case .warning:
            return "\u{001B}[33m"  // 黄色
        case .error:
            return "\u{001B}[31m"  // 红色
        case .critical:
            return "\u{001B}[35m"  // 洋红色
        }
    }
}
