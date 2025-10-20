# 中间件和插件开发指南

## 目录

1. [概述](#概述)
2. [中间件系统](#中间件系统)
3. [内置中间件](#内置中间件)
4. [自定义中间件](#自定义中间件)
5. [插件系统](#插件系统)
6. [自定义插件](#自定义插件)
7. [最佳实践](#最佳实践)
8. [示例](#示例)

---

## 概述

NexusKit 提供了强大的中间件和插件系统，允许在不修改核心代码的情况下扩展功能。

### 中间件 vs 插件

**中间件 (Middleware)**:
- 拦截和处理请求/响应
- 链式执行
- 可修改数据
- 用于横切关注点（日志、认证、压缩等）

**插件 (Plugin)**:
- 扩展核心功能
- 生命周期管理
- 独立运行
- 用于功能模块（监控、追踪、缓存等）

---

## 中间件系统

### Middleware 协议

```swift
public protocol Middleware: Sendable {
    /// 中间件名称
    var name: String { get }

    /// 优先级（数值越小优先级越高）
    var priority: Int { get }

    /// 处理请求
    func handleRequest(
        _ request: Request,
        context: MiddlewareContext,
        next: @Sendable (Request, MiddlewareContext) async throws -> Response
    ) async throws -> Response

    /// 处理响应
    func handleResponse(
        _ response: Response,
        context: MiddlewareContext
    ) async throws -> Response
}
```

### MiddlewareContext

```swift
public actor MiddlewareContext {
    private var storage: [String: Any] = [:]

    public func set<T: Sendable>(_ value: T, forKey key: String) {
        storage[key] = value
    }

    public func get<T: Sendable>(forKey key: String) -> T? {
        return storage[key] as? T
    }

    public func remove(forKey key: String) {
        storage.removeValue(forKey: key)
    }
}
```

### MiddlewareChain

```swift
public actor MiddlewareChain {
    private var middlewares: [any Middleware] = []

    public func use(_ middleware: any Middleware) {
        middlewares.append(middleware)
        middlewares.sort { $0.priority < $1.priority }
    }

    public func execute(
        _ request: Request,
        context: MiddlewareContext
    ) async throws -> Response {
        // 构建中间件链
        var index = 0

        func next(_ req: Request, _ ctx: MiddlewareContext) async throws -> Response {
            if index >= middlewares.count {
                // 执行实际处理
                return try await finalHandler(req, ctx)
            }

            let middleware = middlewares[index]
            index += 1

            return try await middleware.handleRequest(req, context: ctx, next: next)
        }

        return try await next(request, context)
    }
}
```

---

## 内置中间件

### 1. LoggingMiddleware

记录请求和响应日志：

```swift
public actor LoggingMiddleware: Middleware {
    public let name = "logging"
    public let priority = 100

    private let logLevel: LogLevel
    private let logger: Logger

    public enum LogLevel {
        case debug
        case info
        case warning
        case error
    }

    public init(logLevel: LogLevel = .info, logger: Logger? = nil) {
        self.logLevel = logLevel
        self.logger = logger ?? DefaultLogger()
    }

    public func handleRequest(
        _ request: Request,
        context: MiddlewareContext,
        next: @Sendable (Request, MiddlewareContext) async throws -> Response
    ) async throws -> Response {
        let startTime = Date()

        logger.log("→ Request: \(request.method) \(request.path)")

        do {
            let response = try await next(request, context)

            let duration = Date().timeIntervalSince(startTime)
            logger.log("← Response: \(response.statusCode) (\(String(format: "%.2f", duration * 1000))ms)")

            return response
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.log("← Error: \(error) (\(String(format: "%.2f", duration * 1000))ms)")
            throw error
        }
    }

    public func handleResponse(_ response: Response, context: MiddlewareContext) async throws -> Response {
        return response
    }
}
```

**使用示例**:
```swift
let chain = MiddlewareChain()
chain.use(LoggingMiddleware(logLevel: .info))
```

### 2. CompressionMiddleware

自动压缩响应数据：

```swift
public actor CompressionMiddleware: Middleware {
    public let name = "compression"
    public let priority = 200

    private let threshold: Int // 最小压缩大小
    private let algorithm: CompressionAlgorithm

    public enum CompressionAlgorithm {
        case gzip
        case deflate
        case br // Brotli
    }

    public init(threshold: Int = 1024, algorithm: CompressionAlgorithm = .gzip) {
        self.threshold = threshold
        self.algorithm = algorithm
    }

    public func handleRequest(
        _ request: Request,
        context: MiddlewareContext,
        next: @Sendable (Request, MiddlewareContext) async throws -> Response
    ) async throws -> Response {
        return try await next(request, context)
    }

    public func handleResponse(_ response: Response, context: MiddlewareContext) async throws -> Response {
        guard response.body.count >= threshold else {
            return response // 太小不压缩
        }

        let compressed = try await compress(response.body)

        var newResponse = response
        newResponse.body = compressed
        newResponse.headers["Content-Encoding"] = algorithm.headerValue
        newResponse.headers["Content-Length"] = "\(compressed.count)"

        return newResponse
    }

    private func compress(_ data: Data) async throws -> Data {
        switch algorithm {
        case .gzip:
            return try await GzipCodec().transform(data)
        case .deflate:
            return try await ZlibCodec().transform(data)
        case .br:
            return try await BrotliCodec().transform(data)
        }
    }
}
```

**使用示例**:
```swift
chain.use(CompressionMiddleware(threshold: 1024, algorithm: .gzip))
```

### 3. AuthenticationMiddleware

处理身份验证：

```swift
public actor AuthenticationMiddleware: Middleware {
    public let name = "authentication"
    public let priority = 10 // 高优先级

    private let authenticator: any Authenticator
    private let excludePaths: Set<String>

    public init(authenticator: any Authenticator, excludePaths: [String] = []) {
        self.authenticator = authenticator
        self.excludePaths = Set(excludePaths)
    }

    public func handleRequest(
        _ request: Request,
        context: MiddlewareContext,
        next: @Sendable (Request, MiddlewareContext) async throws -> Response
    ) async throws -> Response {
        // 跳过排除路径
        if excludePaths.contains(request.path) {
            return try await next(request, context)
        }

        // 获取 token
        guard let token = request.headers["Authorization"] else {
            throw AuthenticationError.missingToken
        }

        // 验证 token
        let user = try await authenticator.authenticate(token)

        // 存储用户信息到上下文
        await context.set(user, forKey: "user")

        return try await next(request, context)
    }

    public func handleResponse(_ response: Response, context: MiddlewareContext) async throws -> Response {
        return response
    }
}
```

**使用示例**:
```swift
let auth = AuthenticationMiddleware(
    authenticator: JWTAuthenticator(),
    excludePaths: ["/login", "/register", "/health"]
)
chain.use(auth)
```

### 4. RateLimitMiddleware

限流中间件：

```swift
public actor RateLimitMiddleware: Middleware {
    public let name = "rateLimit"
    public let priority = 20

    private let maxRequests: Int
    private let window: TimeInterval
    private var requestCounts: [String: (count: Int, resetTime: Date)] = [:]

    public init(maxRequests: Int, window: TimeInterval) {
        self.maxRequests = maxRequests
        self.window = window
    }

    public func handleRequest(
        _ request: Request,
        context: MiddlewareContext,
        next: @Sendable (Request, MiddlewareContext) async throws -> Response
    ) async throws -> Response {
        let clientId = request.clientIP ?? "unknown"
        let now = Date()

        // 检查限流
        if var record = requestCounts[clientId] {
            if now > record.resetTime {
                // 重置计数
                record = (count: 1, resetTime: now.addingTimeInterval(window))
            } else if record.count >= maxRequests {
                // 超过限制
                throw RateLimitError.tooManyRequests
            } else {
                record.count += 1
            }
            requestCounts[clientId] = record
        } else {
            requestCounts[clientId] = (count: 1, resetTime: now.addingTimeInterval(window))
        }

        return try await next(request, context)
    }

    public func handleResponse(_ response: Response, context: MiddlewareContext) async throws -> Response {
        return response
    }
}
```

**使用示例**:
```swift
// 每分钟最多100个请求
chain.use(RateLimitMiddleware(maxRequests: 100, window: 60))
```

### 5. CORSMiddleware

跨域资源共享：

```swift
public actor CORSMiddleware: Middleware {
    public let name = "cors"
    public let priority = 50

    private let allowedOrigins: [String]
    private let allowedMethods: [String]
    private let allowedHeaders: [String]
    private let maxAge: Int

    public init(
        allowedOrigins: [String] = ["*"],
        allowedMethods: [String] = ["GET", "POST", "PUT", "DELETE"],
        allowedHeaders: [String] = ["Content-Type", "Authorization"],
        maxAge: Int = 3600
    ) {
        self.allowedOrigins = allowedOrigins
        self.allowedMethods = allowedMethods
        self.allowedHeaders = allowedHeaders
        self.maxAge = maxAge
    }

    public func handleRequest(
        _ request: Request,
        context: MiddlewareContext,
        next: @Sendable (Request, MiddlewareContext) async throws -> Response
    ) async throws -> Response {
        // 处理 OPTIONS 预检请求
        if request.method == "OPTIONS" {
            return createCORSResponse()
        }

        return try await next(request, context)
    }

    public func handleResponse(_ response: Response, context: MiddlewareContext) async throws -> Response {
        var newResponse = response

        newResponse.headers["Access-Control-Allow-Origin"] = allowedOrigins.joined(separator: ", ")
        newResponse.headers["Access-Control-Allow-Methods"] = allowedMethods.joined(separator: ", ")
        newResponse.headers["Access-Control-Allow-Headers"] = allowedHeaders.joined(separator: ", ")
        newResponse.headers["Access-Control-Max-Age"] = "\(maxAge)"

        return newResponse
    }

    private func createCORSResponse() -> Response {
        Response(
            statusCode: 204,
            headers: [
                "Access-Control-Allow-Origin": allowedOrigins.joined(separator: ", "),
                "Access-Control-Allow-Methods": allowedMethods.joined(separator: ", "),
                "Access-Control-Allow-Headers": allowedHeaders.joined(separator: ", "),
                "Access-Control-Max-Age": "\(maxAge)"
            ],
            body: Data()
        )
    }
}
```

---

## 自定义中间件

### 示例：缓存中间件

```swift
public actor CacheMiddleware: Middleware {
    public let name = "cache"
    public let priority = 150

    private var cache: [String: CachedResponse] = [:]
    private let cacheDuration: TimeInterval

    struct CachedResponse {
        let response: Response
        let expiresAt: Date
    }

    public init(cacheDuration: TimeInterval = 300) { // 默认5分钟
        self.cacheDuration = cacheDuration
    }

    public func handleRequest(
        _ request: Request,
        context: MiddlewareContext,
        next: @Sendable (Request, MiddlewareContext) async throws -> Response
    ) async throws -> Response {
        // 只缓存 GET 请求
        guard request.method == "GET" else {
            return try await next(request, context)
        }

        let cacheKey = request.path

        // 检查缓存
        if let cached = cache[cacheKey], Date() < cached.expiresAt {
            print("Cache hit: \(cacheKey)")
            return cached.response
        }

        // 执行请求
        let response = try await next(request, context)

        // 只缓存成功响应
        if response.statusCode == 200 {
            cache[cacheKey] = CachedResponse(
                response: response,
                expiresAt: Date().addingTimeInterval(cacheDuration)
            )
        }

        return response
    }

    public func handleResponse(_ response: Response, context: MiddlewareContext) async throws -> Response {
        return response
    }

    /// 清除缓存
    public func clear() {
        cache.removeAll()
    }

    /// 清除特定key
    public func invalidate(_ key: String) {
        cache.removeValue(forKey: key)
    }
}
```

---

## 插件系统

### Plugin 协议

```swift
public protocol Plugin: Sendable {
    /// 插件名称
    var name: String { get }

    /// 插件版本
    var version: String { get }

    /// 插件启动
    func start(context: PluginContext) async throws

    /// 插件停止
    func stop() async

    /// 处理事件
    func handleEvent(_ event: PluginEvent) async
}
```

### PluginContext

```swift
public actor PluginContext {
    private weak var connection: (any Connection)?
    private var config: [String: Any] = [:]

    public func getConnection() -> (any Connection)? {
        return connection
    }

    public func getConfig<T>(_ key: String) -> T? {
        return config[key] as? T
    }

    public func setConfig<T>(_ value: T, forKey key: String) {
        config[key] = value
    }
}
```

### PluginManager

```swift
public actor PluginManager {
    private var plugins: [String: any Plugin] = [:]
    private var contexts: [String: PluginContext] = [:]

    public static let shared = PluginManager()

    public func register(_ plugin: any Plugin, config: [String: Any] = [:]) async throws {
        let context = PluginContext()
        for (key, value) in config {
            await context.setConfig(value, forKey: key)
        }

        try await plugin.start(context: context)

        plugins[plugin.name] = plugin
        contexts[plugin.name] = context
    }

    public func unregister(_ name: String) async {
        if let plugin = plugins.removeValue(forKey: name) {
            await plugin.stop()
            contexts.removeValue(forKey: name)
        }
    }

    public func dispatch(_ event: PluginEvent) async {
        for plugin in plugins.values {
            await plugin.handleEvent(event)
        }
    }
}
```

---

## 自定义插件

### 示例1: 性能监控插件

```swift
public actor PerformanceMonitorPlugin: Plugin {
    public let name = "performance-monitor"
    public let version = "1.0"

    private var metrics: [String: Metric] = [:]
    private var isRunning = false

    struct Metric {
        var count: Int = 0
        var totalDuration: TimeInterval = 0
        var minDuration: TimeInterval = .infinity
        var maxDuration: TimeInterval = 0

        var avgDuration: TimeInterval {
            count > 0 ? totalDuration / Double(count) : 0
        }
    }

    public func start(context: PluginContext) async throws {
        isRunning = true
        print("Performance Monitor started")

        // 启动定期报告任务
        Task {
            while isRunning {
                try await Task.sleep(nanoseconds: 60_000_000_000) // 每分钟
                await printReport()
            }
        }
    }

    public func stop() async {
        isRunning = false
        print("Performance Monitor stopped")
    }

    public func handleEvent(_ event: PluginEvent) async {
        switch event {
        case .requestStarted(let request):
            // 记录开始时间
            break

        case .requestCompleted(let request, let duration):
            // 记录指标
            let key = request.path
            var metric = metrics[key] ?? Metric()
            metric.count += 1
            metric.totalDuration += duration
            metric.minDuration = min(metric.minDuration, duration)
            metric.maxDuration = max(metric.maxDuration, duration)
            metrics[key] = metric

        case .requestFailed(let request, let error):
            // 记录错误
            break

        default:
            break
        }
    }

    private func printReport() {
        print("\n=== Performance Report ===")
        for (path, metric) in metrics.sorted(by: { $0.key < $1.key }) {
            print("\(path):")
            print("  Requests: \(metric.count)")
            print("  Avg: \(String(format: "%.2f", metric.avgDuration * 1000))ms")
            print("  Min: \(String(format: "%.2f", metric.minDuration * 1000))ms")
            print("  Max: \(String(format: "%.2f", metric.maxDuration * 1000))ms")
        }
        print("========================\n")
    }

    public func getMetrics() -> [String: Metric] {
        return metrics
    }

    public func resetMetrics() {
        metrics.removeAll()
    }
}
```

### 示例2: 请求追踪插件

```swift
public actor RequestTracingPlugin: Plugin {
    public let name = "request-tracing"
    public let version = "1.0"

    private var traces: [String: Trace] = [:]

    struct Trace {
        let id: String
        let request: Request
        let startTime: Date
        var endTime: Date?
        var spans: [Span] = []
    }

    struct Span {
        let name: String
        let startTime: Date
        var endTime: Date?
        var tags: [String: String] = [:]
    }

    public func start(context: PluginContext) async throws {
        print("Request Tracing started")
    }

    public func stop() async {
        print("Request Tracing stopped")
    }

    public func handleEvent(_ event: PluginEvent) async {
        switch event {
        case .requestStarted(let request):
            let traceId = UUID().uuidString
            traces[traceId] = Trace(
                id: traceId,
                request: request,
                startTime: Date()
            )

        case .requestCompleted(let request, let duration):
            // 完成追踪
            break

        default:
            break
        }
    }

    public func createSpan(traceId: String, name: String) async -> String {
        let spanId = UUID().uuidString

        if var trace = traces[traceId] {
            trace.spans.append(Span(name: name, startTime: Date()))
            traces[traceId] = trace
        }

        return spanId
    }

    public func getTrace(id: String) -> Trace? {
        return traces[id]
    }
}
```

---

## 最佳实践

### 1. 中间件优先级

```swift
// 建议优先级分配
authentication:  10  // 认证最先
rateLimit:      20  // 限流其次
logging:       100  // 日志中等
compression:   200  // 压缩较后
```

### 2. 错误处理

```swift
public func handleRequest(
    _ request: Request,
    context: MiddlewareContext,
    next: @Sendable (Request, MiddlewareContext) async throws -> Response
) async throws -> Response {
    do {
        return try await next(request, context)
    } catch {
        // 记录错误但不吞掉
        logger.error("Middleware error: \(error)")
        throw error
    }
}
```

### 3. 性能考虑

```swift
// 避免在中间件中执行重操作
public func handleRequest(...) async throws -> Response {
    // ❌ 不好
    let data = try await heavyOperation()

    // ✅ 更好
    Task.detached {
        await backgroundOperation()
    }

    return try await next(request, context)
}
```

### 4. 可配置性

```swift
public actor ConfigurableMiddleware: Middleware {
    private let config: Configuration

    public struct Configuration {
        let enabled: Bool
        let threshold: Int
        let timeout: TimeInterval
    }

    public init(config: Configuration) {
        self.config = config
    }
}
```

---

## 完整示例

### 构建完整的中间件链

```swift
// 创建中间件链
let chain = MiddlewareChain()

// 1. 认证（优先级10）
chain.use(AuthenticationMiddleware(
    authenticator: JWTAuthenticator(),
    excludePaths: ["/health", "/login"]
))

// 2. 限流（优先级20）
chain.use(RateLimitMiddleware(
    maxRequests: 100,
    window: 60
))

// 3. CORS（优先级50）
chain.use(CORSMiddleware(
    allowedOrigins: ["https://example.com"],
    allowedMethods: ["GET", "POST", "PUT", "DELETE"]
))

// 4. 日志（优先级100）
chain.use(LoggingMiddleware(logLevel: .info))

// 5. 缓存（优先级150）
chain.use(CacheMiddleware(cacheDuration: 300))

// 6. 压缩（优先级200）
chain.use(CompressionMiddleware(threshold: 1024))

// 执行请求
let context = MiddlewareContext()
let response = try await chain.execute(request, context: context)
```

### 使用插件

```swift
// 注册性能监控插件
let perfMonitor = PerformanceMonitorPlugin()
try await PluginManager.shared.register(perfMonitor)

// 注册追踪插件
let tracing = RequestTracingPlugin()
try await PluginManager.shared.register(tracing, config: [
    "sampleRate": 0.1  // 采样10%的请求
])

// 分发事件
await PluginManager.shared.dispatch(.requestStarted(request))

// 获取指标
let metrics = await perfMonitor.getMetrics()
```

---

## 总结

中间件和插件系统提供了：

1. **可扩展性**: 无需修改核心代码即可添加功能
2. **可组合性**: 中间件可以灵活组合
3. **关注点分离**: 横切关注点独立管理
4. **易于测试**: 每个中间件/插件可独立测试
5. **性能优化**: 基于优先级和Actor的高效执行

通过合理使用中间件和插件，可以构建灵活、可维护的应用架构。
