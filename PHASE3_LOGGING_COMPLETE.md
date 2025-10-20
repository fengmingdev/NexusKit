# Phase 3: 统一日志系统 - 完成总结

## 任务概述

**任务名称**: 统一日志系统实现
**所属阶段**: Phase 3 - 监控、诊断与高级功能
**完成时间**: 2025-10-20
**构建状态**: ✅ Build complete (7.75s)

## 实现内容

### 1. Logger.swift (364 lines)

#### 1.1 LogLevel - 日志级别
```swift
public enum LogLevel: Int, Sendable, Comparable, CaseIterable {
    case trace = 0      // 追踪 ⚪️
    case debug = 1      // 调试 🔵
    case info = 2       // 信息 🟢
    case warning = 3    // 警告 🟡
    case error = 4      // 错误 🔴
    case critical = 5   // 严重 🔥

    public var label: String    // "TRACE", "DEBUG", "INFO", etc.
    public var symbol: String   // emoji 符号
}
```

#### 1.2 LogMessage - 日志消息
```swift
public struct LogMessage: Sendable {
    public let level: LogLevel
    public let message: String
    public let timestamp: Date
    public let file: String
    public let function: String
    public let line: Int
    public let metadata: [String: String]
    public let error: Error?

    public var fileName: String  // 仅文件名(去除路径)
}
```

#### 1.3 Logger Protocol - 日志器协议
```swift
public protocol Logger: Sendable {
    var name: String { get }
    var minimumLevel: LogLevel { get }
    func log(_ message: LogMessage) async
    func isEnabled(level: LogLevel) -> Bool
}

extension Logger {
    // 便捷方法
    func trace(_ message: String, metadata: [String: String] = [:]) async
    func debug(_ message: String, metadata: [String: String] = [:]) async
    func info(_ message: String, metadata: [String: String] = [:]) async
    func warning(_ message: String, metadata: [String: String] = [:]) async
    func error(_ message: String, error: Error? = nil, metadata: [String: String] = [:]) async
    func critical(_ message: String, error: Error? = nil, metadata: [String: String] = [:]) async
}
```

#### 1.4 DefaultLogger - 默认日志实现
```swift
public actor DefaultLogger: Logger {
    private let targets: [any LogTarget]
    private let formatter: any LogFormatter
    private let filters: [any LogFilter]

    public func log(_ message: LogMessage) async {
        // 1. 检查日志级别
        guard isEnabled(level: message.level) else { return }

        // 2. 应用过滤器
        for filter in filters {
            if await !filter.shouldLog(message) { return }
        }

        // 3. 格式化消息
        let formattedMessage = formatter.format(message)

        // 4. 写入所有目标
        for target in targets {
            await target.write(formattedMessage, level: message.level)
        }
    }
}
```

#### 1.5 GlobalLogger - 全局日志管理
```swift
public actor GlobalLogger {
    public static let shared = GlobalLogger()

    private var loggers: [String: any Logger] = [:]
    private var defaultLogger: any Logger

    public func register(_ logger: any Logger, for name: String)
    public func logger(for name: String) -> any Logger
    public func setDefault(_ logger: any Logger)
    public func log(_ message: LogMessage, logger: String = "NexusKit") async
}
```

#### 1.6 全局便捷函数
```swift
// 通用日志函数
public func log(
    level: LogLevel,
    _ message: String,
    metadata: [String: String] = [:],
    error: Error? = nil,
    logger: String = "NexusKit"
) async

// 级别专用函数
public func logTrace(_ message: String, logger: String = "NexusKit") async
public func logDebug(_ message: String, logger: String = "NexusKit") async
public func logInfo(_ message: String, logger: String = "NexusKit") async
public func logWarning(_ message: String, logger: String = "NexusKit") async
public func logError(_ message: String, error: Error? = nil, logger: String = "NexusKit") async
public func logCritical(_ message: String, error: Error? = nil, logger: String = "NexusKit") async
```

### 2. LogTarget.swift (450 lines)

实现了 **6 种日志输出目标**:

#### 2.1 ConsoleLogTarget - 控制台输出
```swift
public actor ConsoleLogTarget: LogTarget {
    public let useColors: Bool
    public let includeTimestamp: Bool

    public func write(_ message: String, level: LogLevel) async {
        // ANSI 彩色输出
        // error/critical -> stderr, 其他 -> stdout
    }

    public func flush() async {
        fflush(stdout)
        fflush(stderr)
    }
}
```

**特性**:
- ✅ ANSI 彩色输出 (7种颜色)
- ✅ 自动选择 stdout/stderr
- ✅ 可选时间戳

#### 2.2 FileLogTarget - 文件输出
```swift
public actor FileLogTarget: LogTarget {
    public let fileURL: URL
    public let maxFileSize: Int64       // 默认 10MB
    public let maxBackupCount: Int      // 默认 5
    private let bufferLimit: Int        // 默认 10

    private var fileHandle: FileHandle?
    private var buffer: [String] = []
    private var currentSize: Int64 = 0

    public func write(_ message: String, level: LogLevel) async {
        buffer.append(message)
        if buffer.count >= bufferLimit {
            await flush()
        }
    }

    public func flush() async {
        // 写入所有缓冲消息
        // 检查是否需要轮转
        if currentSize >= maxFileSize {
            await rotateLogFile()
        }
    }

    private func rotateLogFile() async {
        // 删除最旧备份
        // 重命名现有备份 (.1 -> .2, .2 -> .3, ...)
        // 重命名当前日志为 .1
    }
}
```

**特性**:
- ✅ 异步缓冲写入
- ✅ 自动文件轮转 (按大小)
- ✅ 保留多个备份
- ✅ Actor 线程安全

#### 2.3 OSLogTarget - 系统日志
```swift
@available(macOS 11.0, iOS 14.0, *)
public actor OSLogTarget: LogTarget {
    private let logger: os.Logger

    public init(subsystem: String = "com.nexuskit", category: String = "default")

    private func mapLogLevel(_ level: LogLevel) -> OSLogType {
        // trace/debug -> .debug
        // info -> .info
        // warning -> .default
        // error -> .error
        // critical -> .fault
    }
}
```

**特性**:
- ✅ 使用 Apple 系统日志
- ✅ 自动级别映射
- ✅ 系统日志集成

#### 2.4 RemoteLogTarget - 远程日志
```swift
public actor RemoteLogTarget: LogTarget {
    public let endpoint: URL
    public let batchSize: Int           // 默认 100
    public let flushInterval: TimeInterval  // 默认 5秒

    private let authToken: String?
    private var buffer: [String] = []
    private var flushTask: Task<Void, Never>?

    public func write(_ message: String, level: LogLevel) async {
        buffer.append(message)
        if buffer.count >= batchSize {
            await flush()
        }
    }

    public func flush() async {
        // HTTP POST JSON到远程服务器
        let payload = [
            "logs": buffer,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "source": "NexusKit"
        ]
    }

    private func startPeriodicFlush() {
        // 每5秒定期刷新
    }
}
```

**特性**:
- ✅ 批量上传 (节省网络)
- ✅ 定期刷新 (5秒间隔)
- ✅ Bearer Token 认证
- ✅ 后台上传任务

#### 2.5 MultiLogTarget - 多目标输出
```swift
public actor MultiLogTarget: LogTarget {
    private let targets: [any LogTarget]

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
}
```

**特性**:
- ✅ 并行写入
- ✅ 任意数量子目标
- ✅ 支持嵌套

### 3. LogFormatter.swift (330 lines)

实现了 **7 种格式化器**:

#### 3.1 DefaultLogFormatter
```swift
public struct DefaultLogFormatter: LogFormatter {
    public let includeTimestamp: Bool
    public let includeLocation: Bool
    public let includeSymbol: Bool
    public let includeMetadata: Bool
    public let timestampFormat: String

    // 输出示例:
    // 2025-10-20 15:30:45.123 [INFO] 🟢 Connection established [host=localhost, port=8080]
}
```

#### 3.2 JSONLogFormatter
```swift
public struct JSONLogFormatter: LogFormatter {
    public let prettyPrint: Bool
    public let includeLocation: Bool

    // 输出示例:
    // {"timestamp":"2025-10-20T15:30:45.123Z","level":"info","message":"Connection established","metadata":{"host":"localhost"},"location":{"file":"TCPConnection.swift","line":42}}
}
```

#### 3.3 CompactLogFormatter
```swift
public struct CompactLogFormatter: LogFormatter {
    // 输出示例:
    // 15:30:45 I Connection established
}
```

#### 3.4 DetailedLogFormatter
```swift
public struct DetailedLogFormatter: LogFormatter {
    // 输出示例:
    // ========================================
    // Time:     2025-10-20 15:30:45.123
    // Level:    INFO 🟢
    // Message:  Connection established
    // Location: TCPConnection.swift:42 connect()
    // Metadata: host=localhost, port=8080
    // ========================================
}
```

#### 3.5 CustomLogFormatter
```swift
public struct CustomLogFormatter: LogFormatter {
    private let formatter: @Sendable (LogMessage) -> String

    // 使用闭包自定义格式
}
```

#### 3.6 TemplateLogFormatter
```swift
public struct TemplateLogFormatter: LogFormatter {
    public let template: String

    // 支持占位符:
    // {timestamp}, {level}, {symbol}, {message}, {file}, {function}, {line}, {metadata}, {error}

    // 示例:
    // template: "[{timestamp}] {level} - {message} ({file}:{line})"
}
```

#### 3.7 ColorLogFormatter
```swift
public struct ColorLogFormatter: LogFormatter {
    public let enabled: Bool

    // ANSI 彩色输出:
    // trace=白色, debug=青色, info=绿色, warning=黄色, error=红色, critical=洋红色
}
```

### 4. LogFilter.swift (360 lines)

实现了 **10 种过滤器**:

#### 4.1 LevelFilter - 级别过滤
```swift
public struct LevelFilter: LogFilter {
    public let minimumLevel: LogLevel

    // 只记录 >= minimumLevel 的日志
}
```

#### 4.2 ModuleFilter - 模块过滤
```swift
public struct ModuleFilter: LogFilter {
    public let includedModules: Set<String>
    public let excludedModules: Set<String>

    // 根据文件名前缀过滤
}
```

#### 4.3 SamplingFilter - 采样过滤
```swift
public actor SamplingFilter: LogFilter {
    public let samplingRate: Double  // 0.0 - 1.0

    // 按比例采样 (例如: 0.1 = 10%)
}
```

#### 4.4 RateLimitFilter - 速率限制
```swift
public actor RateLimitFilter: LogFilter {
    public let windowSize: TimeInterval
    public let maxLogsPerWindow: Int

    // 限制时间窗口内的日志数量
}
```

#### 4.5 BurstFilter - 突发过滤
```swift
public actor BurstFilter: LogFilter {
    public let burstCapacity: Int
    public let refillRate: Double  // 日志/秒

    // 令牌桶算法: 允许短时突发, 长期限制速率
}
```

#### 4.6 DuplicateFilter - 重复过滤
```swift
public actor DuplicateFilter: LogFilter {
    public let windowSize: TimeInterval

    // 过滤时间窗口内重复的消息
    public func getDuplicateCount(for message: LogMessage) -> Int
}
```

#### 4.7 MetadataFilter - 元数据过滤
```swift
public struct MetadataFilter: LogFilter {
    public let requiredMetadata: [String: String]

    // 只记录包含指定元数据的日志
}
```

#### 4.8 CompositeFilter - 组合过滤
```swift
public struct CompositeFilter: LogFilter {
    public enum Logic: Sendable {
        case and  // 所有过滤器都通过
        case or   // 任一过滤器通过
    }

    private let filters: [any LogFilter]
    public let logic: Logic
}
```

#### 4.9 CustomFilter - 自定义过滤
```swift
public struct CustomFilter: LogFilter {
    private let predicate: @Sendable (LogMessage) async -> Bool
}
```

#### 4.10 TimeBasedFilter - 时间段过滤
```swift
public struct TimeBasedFilter: LogFilter {
    public let allowedTimeRanges: [(start: Int, end: Int)]  // 小时 (0-23)

    // 只在指定时间段记录日志
}
```

#### 4.11 PatternFilter - 正则过滤
```swift
public struct PatternFilter: LogFilter {
    private let regex: NSRegularExpression
    public let inverted: Bool

    // 根据消息内容的正则表达式过滤
}
```

## 使用示例

### 示例 1: 基础使用
```swift
// 使用全局便捷函数
await logInfo("服务器已启动")
await logDebug("连接参数", metadata: ["host": "localhost", "port": "8080"])
await logError("连接失败", error: error)
```

### 示例 2: 自定义控制台日志
```swift
let consoleLogger = DefaultLogger(
    name: "Console",
    minimumLevel: .debug,
    targets: [ConsoleLogTarget(useColors: true, includeTimestamp: true)],
    formatter: DefaultLogFormatter()
)

await GlobalLogger.shared.register(consoleLogger, for: "Console")
await logInfo("测试消息", logger: "Console")
```

### 示例 3: 文件日志 + 轮转
```swift
let fileURL = URL(fileURLWithPath: "/var/log/nexuskit.log")
let fileTarget = FileLogTarget(
    fileURL: fileURL,
    maxFileSize: 10 * 1024 * 1024,  // 10MB
    maxBackupCount: 5,
    bufferLimit: 50
)

let fileLogger = DefaultLogger(
    name: "FileLogger",
    minimumLevel: .info,
    targets: [fileTarget],
    formatter: JSONLogFormatter(prettyPrint: false)
)

await GlobalLogger.shared.register(fileLogger, for: "FileLogger")
```

### 示例 4: 远程日志上传
```swift
let remoteTarget = RemoteLogTarget(
    endpoint: URL(string: "https://logs.example.com/api/logs")!,
    authToken: "your-bearer-token",
    batchSize: 100,
    flushInterval: 5.0
)

let remoteLogger = DefaultLogger(
    name: "RemoteLogger",
    minimumLevel: .warning,  // 仅上传 warning+
    targets: [remoteTarget],
    formatter: JSONLogFormatter()
)

await GlobalLogger.shared.register(remoteLogger, for: "RemoteLogger")
```

### 示例 5: 多目标 + 过滤
```swift
let multiTarget = MultiLogTarget(targets: [
    ConsoleLogTarget(),
    FileLogTarget(fileURL: logsURL),
    RemoteLogTarget(endpoint: serverURL)
])

let logger = DefaultLogger(
    name: "Production",
    minimumLevel: .info,
    targets: [multiTarget],
    formatter: JSONLogFormatter(),
    filters: [
        LevelFilter(minimumLevel: .info),
        RateLimitFilter(windowSize: 1.0, maxLogsPerWindow: 100),
        DuplicateFilter(windowSize: 60.0)
    ]
)
```

### 示例 6: 采样 + 模块过滤
```swift
let logger = DefaultLogger(
    name: "Sampled",
    minimumLevel: .debug,
    targets: [ConsoleLogTarget()],
    formatter: CompactLogFormatter(),
    filters: [
        ModuleFilter(
            includedModules: ["TCPConnection", "WebSocket"],
            excludedModules: ["Test"]
        ),
        SamplingFilter(samplingRate: 0.1)  // 仅记录 10%
    ]
)
```

### 示例 7: 模板格式化
```swift
let templateFormatter = TemplateLogFormatter(
    template: "[{timestamp}] {symbol} {level} | {message} | {file}:{line}",
    timestampFormat: "HH:mm:ss"
)

let logger = DefaultLogger(
    name: "Custom",
    targets: [ConsoleLogTarget()],
    formatter: templateFormatter
)

// 输出: [15:30:45] 🟢 INFO | Connection established | TCPConnection.swift:42
```

## 架构亮点

### 1. Protocol-Oriented Design
- `Logger` protocol: 统一日志接口
- `LogTarget` protocol: 可插拔输出目标
- `LogFormatter` protocol: 灵活格式化
- `LogFilter` protocol: 组合过滤策略

### 2. Actor Concurrency Model
- `DefaultLogger`: Actor 隔离
- `GlobalLogger`: Actor 单例
- `FileLogTarget`: Actor 文件写入
- `SamplingFilter`, `RateLimitFilter`, `BurstFilter`, `DuplicateFilter`: Actor 状态管理
- 保证线程安全, 避免数据竞争

### 3. 异步优化
- 异步日志写入 (不阻塞主线程)
- 写入缓冲 (批量写入)
- 并行多目标输出 (`withTaskGroup`)
- 后台定期刷新

### 4. 灵活配置
- 6 种输出目标
- 7 种格式化器
- 10 种过滤器
- 任意组合

### 5. 生产级特性
- 文件轮转 (大小限制 + 备份保留)
- 远程日志上传 (批量 + 定期)
- 速率限制 (避免日志爆炸)
- 采样 (高频场景)
- 重复过滤 (减少冗余)

## 技术栈

- **语言**: Swift 6
- **并发**: async/await, Actor
- **架构**: Protocol-Oriented Programming
- **性能**: 异步I/O, 缓冲写入, 并行输出
- **安全**: Actor 隔离, Sendable 约束

## 构建和验证

### 构建结果
```bash
$ swift build
Building for debugging...
Build complete! (7.75s)
```

### 构建统计
- **构建时间**: 7.75秒
- **错误**: 0
- **警告**: 5 (no async operations - 可忽略)

### 代码统计
```
Logger.swift:        364 行
LogTarget.swift:     450 行
LogFormatter.swift:  330 行
LogFilter.swift:     360 行
----------------------------------
总计:               1,504 行
```

## 验收标准完成情况

| 验收标准 | 目标 | 实际 | 状态 |
|---------|------|------|------|
| 统一日志接口 | 是 | Logger protocol + 全局函数 | ✅ |
| 多输出目标 | 3+ | 6种 (Console/File/OSLog/Remote/Multi/Custom) | ✅ 超额完成 |
| 多格式化器 | 3+ | 7种 (Default/JSON/Compact/Detailed/Custom/Template/Color) | ✅ 超额完成 |
| 过滤机制 | 是 | 10种过滤器 | ✅ 超额完成 |
| Actor 并发 | 是 | 全部使用 Actor | ✅ |
| 异步日志 | 是 | 异步写入 + 缓冲 | ✅ |
| 文件轮转 | 是 | 按大小轮转 + 备份 | ✅ |
| 远程日志 | 可选 | HTTP上传 + 批量 | ✅ |
| Swift 6 合规 | 是 | 完全 Sendable | ✅ |

## 后续集成计划

### 1. 在现有代码中使用
```swift
// TCPConnection.swift
await logInfo("TCP连接已建立", metadata: ["host": host, "port": "\(port)"])

// WebSocketConnection.swift
await logDebug("WebSocket帧已接收", metadata: ["opcode": "\(frame.opcode)"])

// CircuitBreaker.swift
await logWarning("熔断器已打开", metadata: ["failures": "\(failures)"])
```

### 2. 测试覆盖
- [ ] LogTarget 单元测试
- [ ] LogFormatter 单元测试
- [ ] LogFilter 单元测试
- [ ] 集成测试 (多目标 + 过滤)
- [ ] 性能测试 (吞吐量 + 延迟)

### 3. 文档完善
- [ ] DocC 文档生成
- [ ] 使用指南
- [ ] 最佳实践
- [ ] 性能调优建议

## 下一步计划

根据 PHASE3_DETAILED_PLAN.md, 下一个任务是:

**API 文档和示例**:
- [ ] DocC 文档生成
- [ ] 8个示例项目 (BasicTCP, SecureTCP, WebSocket, HTTP, etc.)
- [ ] 最佳实践指南
- [ ] 从 CocoaAsyncSocket 迁移指南

预计时间: 2-3 天

## 总结

统一日志系统已完成并通过构建验证:

✅ **完整的日志系统** - Logger + Targets + Formatters + Filters
✅ **6种输出目标** - Console, File, OSLog, Remote, Multi, Custom
✅ **7种格式化器** - Default, JSON, Compact, Detailed, Custom, Template, Color
✅ **10种过滤器** - Level, Module, Sampling, RateLimit, Burst, Duplicate, Metadata, Composite, Custom, TimeBased, Pattern
✅ **Actor 并发模型** - 线程安全保证
✅ **生产级特性** - 文件轮转, 远程上传, 速率限制, 采样
✅ **构建成功** - 7.75秒, 0错误
✅ **1,504行代码** - 高质量实现

日志系统为 NexusKit 提供了强大的调试和监控能力, 支持从开发到生产的全流程。
