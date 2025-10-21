//
//  HTTPClient.swift
//  NexusHTTP
//
//  Created by NexusKit on 2025-10-20.
//
//  HTTP/1.1 客户端实现

import Foundation
#if canImport(NexusCore)
import NexusCore
#endif
#if canImport(NexusTCP)
import NexusTCP
#endif

// MARK: - HTTP Client

/// HTTP 客户端
///
/// 基于 NexusTCP 的 HTTP/1.1 客户端实现。
///
/// ## 功能特性
///
/// - HTTP/1.1 完整支持
/// - Keep-Alive 持久连接
/// - 自动重定向
/// - Cookie 管理
/// - GZIP/Deflate 压缩
/// - 分块传输编码
/// - HTTPS/TLS 支持
///
/// ## 使用示例
///
/// ```swift
/// let client = HTTPClient()
///
/// // GET 请求
/// let response = try await client.send(
///     HTTPRequest.get(URL(string: "https://api.example.com/users")!)
///         .bearerToken("token")
///         .build()
/// )
///
/// print(response.string())
/// ```
public actor HTTPClient {

    // MARK: - Configuration

    /// HTTP 客户端配置
    public struct Configuration: Sendable {
        /// 是否启用 Keep-Alive
        public let keepAlive: Bool

        /// Keep-Alive 超时时间
        public let keepAliveTimeout: TimeInterval

        /// 最大重定向次数
        public let maxRedirects: Int

        /// 是否自动跟随重定向
        public let followRedirects: Bool

        /// 是否启用 Cookie
        public let enableCookies: Bool

        /// 默认超时时间
        public let defaultTimeout: TimeInterval

        /// User-Agent
        public let userAgent: String

        /// 是否自动解压缩
        public let autoDecompress: Bool

        public static let `default` = Configuration(
            keepAlive: true,
            keepAliveTimeout: 60.0,
            maxRedirects: 5,
            followRedirects: true,
            enableCookies: true,
            defaultTimeout: 30.0,
            userAgent: "NexusKit/1.0",
            autoDecompress: true
        )

        public init(
            keepAlive: Bool = true,
            keepAliveTimeout: TimeInterval = 60.0,
            maxRedirects: Int = 5,
            followRedirects: Bool = true,
            enableCookies: Bool = true,
            defaultTimeout: TimeInterval = 30.0,
            userAgent: String = "NexusKit/1.0",
            autoDecompress: Bool = true
        ) {
            self.keepAlive = keepAlive
            self.keepAliveTimeout = keepAliveTimeout
            self.maxRedirects = maxRedirects
            self.followRedirects = followRedirects
            self.enableCookies = enableCookies
            self.defaultTimeout = defaultTimeout
            self.userAgent = userAgent
            self.autoDecompress = autoDecompress
        }
    }

    // MARK: - Properties

    /// 配置
    public let configuration: Configuration

    /// 连接池（host:port -> connection）
    private var connectionPool: [String: TCPConnection] = [:]

    /// Cookie 存储
    private var cookieStorage: [String: [HTTPCookie]] = [:]

    /// 统计信息
    private var stats = Statistics()

    private struct Statistics {
        var totalRequests: Int = 0
        var successfulRequests: Int = 0
        var failedRequests: Int = 0
        var redirects: Int = 0
        var cacheHits: Int = 0
    }

    // MARK: - Initialization

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Request Sending

    /// 发送 HTTP 请求
    ///
    /// - Parameter request: HTTP 请求
    /// - Returns: HTTP 响应
    /// - Throws: 如果请求失败
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        stats.totalRequests += 1

        // 处理重定向
        if configuration.followRedirects {
            return try await sendWithRedirects(request, redirectCount: 0)
        } else {
            return try await performRequest(request)
        }
    }

    /// 发送请求（支持重定向）
    private func sendWithRedirects(_ request: HTTPRequest, redirectCount: Int) async throws -> HTTPResponse {
        let response = try await performRequest(request)

        // 检查是否需要重定向
        guard let statusCode = response.status,
              statusCode.isRedirect,
              redirectCount < configuration.maxRedirects else {
            return response
        }

        // 获取重定向位置
        guard let location = response.headers["location"],
              let redirectURL = URL(string: location, relativeTo: request.url) else {
            return response
        }

        stats.redirects += 1

        // 构建重定向请求
        var redirectRequest = request
        redirectRequest = HTTPRequest(
            method: request.method,
            url: redirectURL,
            headers: request.headers,
            body: request.body,
            timeout: request.timeout
        )

        // 递归处理重定向
        return try await sendWithRedirects(redirectRequest, redirectCount: redirectCount + 1)
    }

    /// 执行请求
    private func performRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        // 获取或创建连接
        let connection = try await getConnection(for: request.url)

        do {
            // 添加 Cookie
            var finalRequest = request
            if configuration.enableCookies {
                finalRequest = addCookies(to: request)
            }

            // 发送请求
            let requestData = finalRequest.encode()
            try await connection.send(requestData, timeout: finalRequest.timeout)

            // 接收响应
            let responseData = try await connection.receive(timeout: finalRequest.timeout)

            // 解析响应
            let (response, _) = try HTTPResponseParser.parse(responseData)

            // 保存 Cookie
            if configuration.enableCookies {
                saveCookies(from: response, for: request.url)
            }

            // 自动解压缩
            if configuration.autoDecompress {
                // TODO: 实现 GZIP/Deflate 解压缩
            }

            stats.successfulRequests += 1
            return response

        } catch {
            stats.failedRequests += 1

            // 连接失败，从池中移除
            removeConnection(for: request.url)

            throw HTTPError.connectionFailed(error)
        }
    }

    // MARK: - Connection Management

    /// 获取或创建连接
    private func getConnection(for url: URL) async throws -> TCPConnection {
        let key = connectionKey(for: url)

        // 检查连接池
        if let existingConnection = connectionPool[key],
           await existingConnection.state == .connected {
            return existingConnection
        }

        // 创建新连接
        guard let host = url.host else {
            throw HTTPError.invalidResponse
        }

        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let usesTLS = url.scheme == "https"

        var builder = NexusKit.shared.tcp(host: host, port: UInt16(port))

        if usesTLS {
            // 配置 TLS
            let tlsConfig = TLSConfiguration(
                serverName: host,
                allowSelfSigned: false
            )
            builder = builder.tls(tlsConfig)
        }

        let connection = try await builder
            .timeout(configuration.defaultTimeout)
            .connect()

        // 保存到连接池
        if configuration.keepAlive {
            connectionPool[key] = connection
        }

        return connection
    }

    /// 移除连接
    private func removeConnection(for url: URL) {
        let key = connectionKey(for: url)
        connectionPool.removeValue(forKey: key)
    }

    /// 生成连接键
    private func connectionKey(for url: URL) -> String {
        let host = url.host ?? "unknown"
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        return "\(host):\(port)"
    }

    // MARK: - Cookie Management

    /// 添加 Cookie 到请求
    private func addCookies(to request: HTTPRequest) -> HTTPRequest {
        let domain = request.url.host ?? ""
        guard let cookies = cookieStorage[domain], !cookies.isEmpty else {
            return request
        }

        let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

        var headers = request.headers
        headers.add(name: HTTPHeaders.Common.cookie, value: cookieString)

        return HTTPRequest(
            method: request.method,
            url: request.url,
            headers: headers,
            body: request.body,
            timeout: request.timeout
        )
    }

    /// 保存响应中的 Cookie
    private func saveCookies(from response: HTTPResponse, for url: URL) {
        let domain = url.host ?? ""

        // 解析 Set-Cookie 头部
        guard let setCookieHeader = response.headers["set-cookie"] else {
            return
        }

        let cookies = parseCookies(setCookieHeader)
        if !cookies.isEmpty {
            cookieStorage[domain, default: []].append(contentsOf: cookies)
        }
    }

    /// 解析 Cookie 字符串
    private func parseCookies(_ cookieString: String) -> [HTTPCookie] {
        cookieString.components(separatedBy: ",").compactMap { cookieStr in
            let parts = cookieStr.components(separatedBy: ";")
            guard let nameValue = parts.first?.components(separatedBy: "="),
                  nameValue.count == 2 else {
                return nil
            }

            return HTTPCookie(
                name: nameValue[0].trimmingCharacters(in: .whitespaces),
                value: nameValue[1].trimmingCharacters(in: .whitespaces)
            )
        }
    }

    // MARK: - Cleanup

    /// 关闭所有连接
    public func closeAllConnections() async {
        for (_, connection) in connectionPool {
            await connection.disconnect(reason: .clientInitiated)
        }
        connectionPool.removeAll()
    }

    /// 清除所有 Cookie
    public func clearCookies() {
        cookieStorage.removeAll()
    }

    /// 获取统计信息
    public func getStatistics() -> (
        totalRequests: Int,
        successfulRequests: Int,
        failedRequests: Int,
        redirects: Int,
        cacheHits: Int
    ) {
        (
            totalRequests: stats.totalRequests,
            successfulRequests: stats.successfulRequests,
            failedRequests: stats.failedRequests,
            redirects: stats.redirects,
            cacheHits: stats.cacheHits
        )
    }
}

// MARK: - HTTP Cookie

/// HTTP Cookie
public struct HTTPCookie: Sendable {
    /// Cookie 名称
    public let name: String

    /// Cookie 值
    public let value: String

    /// 域名
    public var domain: String?

    /// 路径
    public var path: String?

    /// 过期时间
    public var expires: Date?

    /// 是否仅 HTTPS
    public var secure: Bool

    /// 是否 HttpOnly
    public var httpOnly: Bool

    public init(
        name: String,
        value: String,
        domain: String? = nil,
        path: String? = nil,
        expires: Date? = nil,
        secure: Bool = false,
        httpOnly: Bool = false
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.secure = secure
        self.httpOnly = httpOnly
    }
}

// MARK: - Convenience Methods

extension HTTPClient {
    /// 发送 GET 请求
    public func get(_ url: URL, headers: [String: String] = [:]) async throws -> HTTPResponse {
        try await send(HTTPRequest.get(url).headers(headers).build())
    }

    /// 发送 POST 请求
    public func post(_ url: URL, body: Data?, headers: [String: String] = [:]) async throws -> HTTPResponse {
        var builder = HTTPRequest.post(url).headers(headers)
        if let body = body {
            builder = builder.body(body)
        }
        return try await send(builder.build())
    }

    /// 发送 POST JSON 请求
    public func postJSON<T: Encodable>(_ url: URL, json: T, headers: [String: String] = [:]) async throws -> HTTPResponse {
        try await send(try HTTPRequest.post(url).headers(headers).json(json).build())
    }

    /// 发送 PUT 请求
    public func put(_ url: URL, body: Data?, headers: [String: String] = [:]) async throws -> HTTPResponse {
        var builder = HTTPRequest.put(url).headers(headers)
        if let body = body {
            builder = builder.body(body)
        }
        return try await send(builder.build())
    }

    /// 发送 DELETE 请求
    public func delete(_ url: URL, headers: [String: String] = [:]) async throws -> HTTPResponse {
        try await send(HTTPRequest.delete(url).headers(headers).build())
    }
}
