//
//  LogTarget.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  日志输出目标

import Foundation
#if canImport(OSLog)
import OSLog
#endif

// MARK: - Log Target Protocol

/// 日志输出目标协议
public protocol LogTarget: Sendable {
    /// 写入日志
    func write(_ message: String, level: LogLevel) async

    /// 刷新缓冲区
    func flush() async
}

// MARK: - Console Log Target

/// 控制台日志输出
public actor ConsoleLogTarget: LogTarget {

    /// 是否使用彩色输出
    public let useColors: Bool

    /// 是否包含时间戳
    public let includeTimestamp: Bool

    public init(useColors: Bool = true, includeTimestamp: Bool = true) {
        self.useColors = useColors
        self.includeTimestamp = includeTimestamp
    }

    public func write(_ message: String, level: LogLevel) async {
        var output = ""

        // 添加时间戳
        if includeTimestamp {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            output += "[\(formatter.string(from: Date()))] "
        }

        // 添加级别标签
        if useColors {
            output += coloredLabel(for: level)
        } else {
            output += "[\(level.label)] "
        }

        // 添加消息
        output += message

        // 输出到标准输出或错误
        if level >= .error {
            fputs(output + "\n", stderr)
        } else {
            print(output)
        }
    }

    public func flush() async {
        fflush(stdout)
        fflush(stderr)
    }

    /// 获取彩色标签
    private func coloredLabel(for level: LogLevel) -> String {
        let reset = "\u{001B}[0m"
        let color: String

        switch level {
        case .trace:
            color = "\u{001B}[37m"  // 白色
        case .debug:
            color = "\u{001B}[36m"  // 青色
        case .info:
            color = "\u{001B}[32m"  // 绿色
        case .warning:
            color = "\u{001B}[33m"  // 黄色
        case .error:
            color = "\u{001B}[31m"  // 红色
        case .critical:
            color = "\u{001B}[35m"  // 洋红色
        }

        return "\(color)\(level.symbol) \(level.label)\(reset) "
    }
}

// MARK: - File Log Target

/// 文件日志输出
public actor FileLogTarget: LogTarget {

    /// 文件路径
    public let fileURL: URL

    /// 最大文件大小（字节）
    public let maxFileSize: Int64

    /// 保留的日志文件数量
    public let maxBackupCount: Int

    /// 文件句柄
    private var fileHandle: FileHandle?

    /// 当前文件大小
    private var currentSize: Int64 = 0

    /// 写入缓冲区
    private var buffer: [String] = []

    /// 缓冲区大小限制
    private let bufferLimit: Int

    public init(
        fileURL: URL,
        maxFileSize: Int64 = 10 * 1024 * 1024,  // 10MB
        maxBackupCount: Int = 5,
        bufferLimit: Int = 10
    ) {
        self.fileURL = fileURL
        self.maxFileSize = maxFileSize
        self.maxBackupCount = maxBackupCount
        self.bufferLimit = bufferLimit
    }

    public func write(_ message: String, level: LogLevel) async {
        // 添加到缓冲区
        buffer.append(message)

        // 缓冲区满时刷新
        if buffer.count >= bufferLimit {
            await flush()
        }
    }

    public func flush() async {
        guard !buffer.isEmpty else { return }

        do {
            // 确保文件句柄打开
            try ensureFileHandleOpen()

            // 写入所有缓冲的消息
            for message in buffer {
                let line = message + "\n"
                if let data = line.data(using: .utf8) {
                    if #available(macOS 10.15.4, iOS 13.4, *) {
                        try fileHandle?.write(contentsOf: data)
                    } else {
                        fileHandle?.write(data)
                    }
                    currentSize += Int64(data.count)
                }
            }

            // 清空缓冲区
            buffer.removeAll()

            // 检查是否需要轮转
            if currentSize >= maxFileSize {
                await rotateLogFile()
            }

        } catch {
            // 日志写入失败，输出到标准错误
            fputs("Failed to write log to file: \(error)\n", stderr)
        }
    }

    /// 确保文件句柄已打开
    private func ensureFileHandleOpen() throws {
        if fileHandle == nil {
            let fileManager = FileManager.default

            // 创建目录（如果不存在）
            let directory = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }

            // 创建文件（如果不存在）
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            // 打开文件句柄
            fileHandle = try FileHandle(forWritingTo: fileURL)

            // 移动到文件末尾
            if #available(macOS 10.15.4, iOS 13.4, *) {
                try fileHandle?.seekToEnd()
            } else {
                fileHandle?.seekToEndOfFile()
            }

            // 获取当前文件大小
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            currentSize = attributes[.size] as? Int64 ?? 0
        }
    }

    /// 轮转日志文件
    private func rotateLogFile() async {
        do {
            // 关闭当前文件句柄
            try fileHandle?.close()
            fileHandle = nil

            let fileManager = FileManager.default

            // 删除最旧的备份
            let oldestBackup = backupURL(index: maxBackupCount)
            if fileManager.fileExists(atPath: oldestBackup.path) {
                try fileManager.removeItem(at: oldestBackup)
            }

            // 重命名现有备份
            for i in (1..<maxBackupCount).reversed() {
                let from = backupURL(index: i)
                let to = backupURL(index: i + 1)
                if fileManager.fileExists(atPath: from.path) {
                    try fileManager.moveItem(at: from, to: to)
                }
            }

            // 重命名当前日志文件为 .1
            let firstBackup = backupURL(index: 1)
            try fileManager.moveItem(at: fileURL, to: firstBackup)

            // 重置文件大小
            currentSize = 0

        } catch {
            fputs("Failed to rotate log file: \(error)\n", stderr)
        }
    }

    /// 获取备份文件 URL
    private func backupURL(index: Int) -> URL {
        let path = fileURL.path
        return URL(fileURLWithPath: "\(path).\(index)")
    }

    deinit {
        // 注意：deinit 中不能使用 await
        try? fileHandle?.close()
    }
}

// MARK: - OSLog Target

#if canImport(OSLog)
/// OSLog 日志输出（Apple 平台）
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public actor OSLogTarget: LogTarget {

    /// 日志记录器
    private let logger: os.Logger

    public init(subsystem: String = "com.nexuskit", category: String = "default") {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    public func write(_ message: String, level: LogLevel) async {
        let osLogLevel = mapLogLevel(level)
        logger.log(level: osLogLevel, "\(message)")
    }

    public func flush() async {
        // OSLog 自动管理刷新
    }

    /// 映射日志级别
    private func mapLogLevel(_ level: LogLevel) -> OSLogType {
        switch level {
        case .trace, .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        case .critical:
            return .fault
        }
    }
}
#endif

// MARK: - Remote Log Target

/// 远程日志输出（通过 HTTP）
public actor RemoteLogTarget: LogTarget {

    /// 远程端点 URL
    public let endpoint: URL

    /// 批量发送的日志数量
    public let batchSize: Int

    /// 发送间隔
    public let flushInterval: TimeInterval

    /// 认证令牌
    private let authToken: String?

    /// 日志缓冲区
    private var buffer: [String] = []

    /// 上次刷新时间
    private var lastFlushTime: Date = Date()

    /// 后台刷新任务
    private var flushTask: Task<Void, Never>?

    public init(
        endpoint: URL,
        authToken: String? = nil,
        batchSize: Int = 100,
        flushInterval: TimeInterval = 5.0
    ) {
        self.endpoint = endpoint
        self.authToken = authToken
        self.batchSize = batchSize
        self.flushInterval = flushInterval

        // 启动定期刷新任务需要在异步上下文中
        // 延迟到第一次使用时启动
    }

    /// 确保定期刷新任务已启动
    private func ensureFlushTaskStarted() {
        guard flushTask == nil else { return }
        startPeriodicFlush()
    }

    public func write(_ message: String, level: LogLevel) async {
        ensureFlushTaskStarted()
        buffer.append(message)

        // 缓冲区满时立即发送
        if buffer.count >= batchSize {
            await flush()
        }
    }

    public func flush() async {
        guard !buffer.isEmpty else { return }

        let logsToSend = buffer
        buffer.removeAll()
        lastFlushTime = Date()

        // 在后台发送日志
        Task {
            await sendLogs(logsToSend)
        }
    }

    /// 发送日志到远程服务器
    private func sendLogs(_ logs: [String]) async {
        do {
            // 构建 JSON 数据
            let payload: [String: Any] = [
                "logs": logs,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "source": "NexusKit"
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: payload)

            // 创建请求
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let token = authToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            request.httpBody = jsonData

            // 发送请求
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                fputs("Remote log upload failed with status: \(httpResponse.statusCode)\n", stderr)
            }

        } catch {
            fputs("Failed to send logs to remote server: \(error)\n", stderr)
        }
    }

    /// 启动定期刷新任务
    private func startPeriodicFlush() {
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(5_000_000_000)) // 5秒
                await self?.checkAndFlush()
            }
        }
    }

    /// 检查并刷新
    private func checkAndFlush() async {
        let elapsed = Date().timeIntervalSince(lastFlushTime)
        if elapsed >= flushInterval && !buffer.isEmpty {
            await flush()
        }
    }

    deinit {
        flushTask?.cancel()
    }
}

// MARK: - Multi Target

/// 多目标日志输出
public actor MultiLogTarget: LogTarget {

    /// 子目标列表
    private let targets: [any LogTarget]

    public init(targets: [any LogTarget]) {
        self.targets = targets
    }

    public func write(_ message: String, level: LogLevel) async {
        // 并行写入所有目标
        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask {
                    await target.write(message, level: level)
                }
            }
        }
    }

    public func flush() async {
        // 并行刷新所有目标
        await withTaskGroup(of: Void.self) { group in
            for target in targets {
                group.addTask {
                    await target.flush()
                }
            }
        }
    }
}
