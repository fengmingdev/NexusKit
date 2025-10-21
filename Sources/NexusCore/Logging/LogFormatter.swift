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
/// [NexusKit] 2025-10-20 15:30:45.123 [INFO] 🟢 MyModule - Connection established
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
    
    /// 统一前缀
    public let prefix: String

    public init(
        includeTimestamp: Bool = true,
        includeLocation: Bool = false,
        includeSymbol: Bool = true,
        includeMetadata: Bool = true,
        timestampFormat: String = "yyyy-MM-dd HH:mm:ss.SSS",
        prefix: String = "NexusKit"
    ) {
        self.includeTimestamp = includeTimestamp
        self.includeLocation = includeLocation
        self.includeSymbol = includeSymbol
        self.includeMetadata = includeMetadata
        self.timestampFormat = timestampFormat
        self.prefix = prefix
    }

    public func format(_ message: LogMessage) -> String {
        var parts: [String] = []

        // 统一前缀
        parts.append("[\(prefix)]")

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
/// 输出格式：`[NexusKit] [INFO] Connection established`
public struct CompactLogFormatter: LogFormatter, Sendable {
    
    /// 统一前缀
    public let prefix: String
    
    public init(prefix: String = "NexusKit") {
        self.prefix = prefix
    }

    public func format(_ message: LogMessage) -> String {
        return "[\(prefix)] [\(message.level.label)] \(message.message)"
    }
}

// MARK: - Detailed Log Formatter

/// 详细日志格式化器
///
/// 输出格式：
/// ```
/// [NexusKit] 2025-10-20 15:30:45.123 [INFO] 🟢 Connection established
/// File: TCPConnection.swift:42 connect()
/// Metadata: host=localhost, port=8080
/// ```
public struct DetailedLogFormatter: LogFormatter, Sendable {
    
    /// 统一前缀
    public let prefix: String
    
    public init(prefix: String = "NexusKit") {
        self.prefix = prefix
    }

    public func format(_ message: LogMessage) -> String {
        var lines: [String] = []

        // 主要日志行
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: message.timestamp)

        let mainLine = "[\(prefix)] \(timestamp) [\(message.level.label)] \(message.level.symbol) \(message.message)"
        lines.append(mainLine)

        // 文件位置
        lines.append("File: \(message.fileName):\(message.line) \(message.function)")

        // 元数据
        if !message.metadata.isEmpty {
            let metadataStr = message.metadata
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            lines.append("Metadata: \(metadataStr)")
        }

        // 错误信息
        if let error = message.error {
            lines.append("Error: \(error)")
        }

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
/// 支持自定义模板格式，可用占位符：
/// - `{prefix}`: 统一前缀
/// - `{timestamp}`: 时间戳
/// - `{level}`: 日志级别
/// - `{symbol}`: 级别符号
/// - `{message}`: 消息内容
/// - `{metadata}`: 元数据
/// - `{file}`: 文件名
/// - `{function}`: 函数名
/// - `{line}`: 行号
///
/// 默认模板：`[{prefix}] {timestamp} [{level}] {symbol} {message}`
public struct TemplateLogFormatter: LogFormatter, Sendable {

    /// 模板字符串
    public let template: String

    /// 时间戳格式
    public let timestampFormat: String
    
    /// 统一前缀
    public let prefix: String

    public init(
        template: String = "[{prefix}] {timestamp} [{level}] {symbol} {message}",
        timestampFormat: String = "yyyy-MM-dd HH:mm:ss.SSS",
        prefix: String = "NexusKit"
    ) {
        self.template = template
        self.timestampFormat = timestampFormat
        self.prefix = prefix
    }

    public func format(_ message: LogMessage) -> String {
        var result = template

        // 替换占位符
        result = result.replacingOccurrences(of: "{prefix}", with: prefix)
        result = result.replacingOccurrences(of: "{timestamp}", with: formatTimestamp(message.timestamp))
        result = result.replacingOccurrences(of: "{level}", with: message.level.label)
        result = result.replacingOccurrences(of: "{symbol}", with: message.level.symbol)
        result = result.replacingOccurrences(of: "{message}", with: message.message)
        result = result.replacingOccurrences(of: "{metadata}", with: formatMetadata(message.metadata))
        result = result.replacingOccurrences(of: "{file}", with: message.fileName)
        result = result.replacingOccurrences(of: "{function}", with: message.function)
        result = result.replacingOccurrences(of: "{line}", with: "\(message.line)")

        return result
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = timestampFormat
        return formatter.string(from: date)
    }

    private func formatMetadata(_ metadata: [String: String]) -> String {
        guard !metadata.isEmpty else { return "" }
        return metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    }
}

// MARK: - Color Log Formatter

/// 彩色日志格式化器
///
/// 为不同日志级别添加颜色，输出格式：`[NexusKit] 15:30:45 [INFO] 🟢 Connection established`
public struct ColorLogFormatter: LogFormatter, Sendable {
    
    /// 统一前缀
    public let prefix: String
    
    public init(prefix: String = "NexusKit") {
        self.prefix = prefix
    }

    public func format(_ message: LogMessage) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: message.timestamp)

        let colorCode = colorForLevel(message.level)
        let resetCode = "\u{001B}[0m"

        return "[\(prefix)] \(colorCode)\(time) [\(message.level.label)] \(message.level.symbol) \(message.message)\(resetCode)"
    }

    private func colorForLevel(_ level: LogLevel) -> String {
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
            return "\u{001B}[35m"  // 紫色
        }
    }
}
