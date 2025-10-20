//
//  HTTPRequest.swift
//  NexusHTTP
//
//  Created by NexusKit on 2025-10-20.
//
//  HTTP 请求结构

import Foundation

// MARK: - HTTP Method

/// HTTP 方法
public enum HTTPMethod: String, Sendable {
    case GET
    case POST
    case PUT
    case DELETE
    case HEAD
    case OPTIONS
    case PATCH
    case TRACE
    case CONNECT
}

// MARK: - HTTP Headers

/// HTTP 头部
public struct HTTPHeaders: Sendable {
    private var headers: [String: String]

    public init(_ headers: [String: String] = [:]) {
        self.headers = headers
    }

    /// 获取头部值
    public subscript(name: String) -> String? {
        get { headers[name.lowercased()] }
        set { headers[name.lowercased()] = newValue }
    }

    /// 添加头部
    public mutating func add(name: String, value: String) {
        headers[name.lowercased()] = value
    }

    /// 移除头部
    public mutating func remove(name: String) {
        headers.removeValue(forKey: name.lowercased())
    }

    /// 所有头部
    public var all: [String: String] {
        headers
    }

    /// 常用头部
    public struct Common {
        public static let accept = "accept"
        public static let acceptEncoding = "accept-encoding"
        public static let authorization = "authorization"
        public static let cacheControl = "cache-control"
        public static let connection = "connection"
        public static let contentType = "content-type"
        public static let contentLength = "content-length"
        public static let cookie = "cookie"
        public static let host = "host"
        public static let userAgent = "user-agent"
        public static let transferEncoding = "transfer-encoding"
    }
}

// MARK: - HTTP Request

/// HTTP 请求
public struct HTTPRequest: Sendable {

    /// HTTP 方法
    public let method: HTTPMethod

    /// 请求 URL
    public let url: URL

    /// HTTP 版本
    public let version: String

    /// 请求头
    public var headers: HTTPHeaders

    /// 请求体
    public let body: Data?

    /// 超时时间
    public let timeout: TimeInterval

    public init(
        method: HTTPMethod,
        url: URL,
        version: String = "HTTP/1.1",
        headers: HTTPHeaders = HTTPHeaders(),
        body: Data? = nil,
        timeout: TimeInterval = 30.0
    ) {
        self.method = method
        self.url = url
        self.version = version
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    // MARK: - Request Building

    /// 编码为字节数据
    public func encode() -> Data {
        var data = Data()

        // 请求行
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let requestLine = "\(method.rawValue) \(path)\(query) \(version)\r\n"
        data.append(requestLine.data(using: .utf8) ?? Data())

        // 头部
        for (name, value) in headers.all {
            let headerLine = "\(name): \(value)\r\n"
            data.append(headerLine.data(using: .utf8) ?? Data())
        }

        // 空行（标记头部结束）
        data.append("\r\n".data(using: .utf8) ?? Data())

        // 请求体
        if let body = body {
            data.append(body)
        }

        return data
    }
}

// MARK: - Request Builder

/// HTTP 请求构建器
public final class HTTPRequestBuilder {
    private var method: HTTPMethod = .GET
    private var url: URL
    private var headers = HTTPHeaders()
    private var body: Data?
    private var queryParameters: [String: String] = [:]
    private var timeout: TimeInterval = 30.0

    public init(url: URL) {
        self.url = url
    }

    /// 设置 HTTP 方法
    @discardableResult
    public func method(_ method: HTTPMethod) -> Self {
        self.method = method
        return self
    }

    /// 添加头部
    @discardableResult
    public func header(name: String, value: String) -> Self {
        headers.add(name: name, value: value)
        return self
    }

    /// 批量添加头部
    @discardableResult
    public func headers(_ headers: [String: String]) -> Self {
        for (name, value) in headers {
            self.headers.add(name: name, value: value)
        }
        return self
    }

    /// 设置 Content-Type
    @discardableResult
    public func contentType(_ contentType: String) -> Self {
        header(name: HTTPHeaders.Common.contentType, value: contentType)
        return self
    }

    /// 设置 Authorization
    @discardableResult
    public func authorization(_ token: String) -> Self {
        header(name: HTTPHeaders.Common.authorization, value: token)
        return self
    }

    /// Bearer Token 认证
    @discardableResult
    public func bearerToken(_ token: String) -> Self {
        authorization("Bearer \(token)")
        return self
    }

    /// Basic 认证
    @discardableResult
    public func basicAuth(username: String, password: String) -> Self {
        let credentials = "\(username):\(password)"
        if let data = credentials.data(using: .utf8) {
            let base64 = data.base64EncodedString()
            authorization("Basic \(base64)")
        }
        return self
    }

    /// 添加查询参数
    @discardableResult
    public func query(name: String, value: String) -> Self {
        queryParameters[name] = value
        return self
    }

    /// 批量添加查询参数
    @discardableResult
    public func query(_ parameters: [String: String]) -> Self {
        queryParameters.merge(parameters) { _, new in new }
        return self
    }

    /// 设置请求体（Data）
    @discardableResult
    public func body(_ data: Data) -> Self {
        self.body = data
        return self
    }

    /// 设置请求体（String）
    @discardableResult
    public func body(_ string: String) -> Self {
        self.body = string.data(using: .utf8)
        return self
    }

    /// 设置请求体（JSON Encodable）
    @discardableResult
    public func json<T: Encodable>(_ value: T) throws -> Self {
        let encoder = JSONEncoder()
        self.body = try encoder.encode(value)
        contentType("application/json")
        return self
    }

    /// 设置请求体（表单）
    @discardableResult
    public func form(_ parameters: [String: String]) -> Self {
        let formString = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        body = formString.data(using: .utf8)
        contentType("application/x-www-form-urlencoded")
        return self
    }

    /// 设置超时
    @discardableResult
    public func timeout(_ timeout: TimeInterval) -> Self {
        self.timeout = timeout
        return self
    }

    /// 构建请求
    public func build() -> HTTPRequest {
        // 添加查询参数到 URL
        var finalURL = url
        if !queryParameters.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems ?? []
            for (name, value) in queryParameters {
                queryItems.append(URLQueryItem(name: name, value: value))
            }
            components?.queryItems = queryItems
            finalURL = components?.url ?? url
        }

        // 添加默认头部
        var finalHeaders = headers

        // Host 头部
        if finalHeaders[HTTPHeaders.Common.host] == nil {
            if let host = url.host {
                let port = url.port.map { ":\($0)" } ?? ""
                finalHeaders.add(name: HTTPHeaders.Common.host, value: "\(host)\(port)")
            }
        }

        // Content-Length 头部
        if let body = body, finalHeaders[HTTPHeaders.Common.contentLength] == nil {
            finalHeaders.add(name: HTTPHeaders.Common.contentLength, value: "\(body.count)")
        }

        // User-Agent 头部
        if finalHeaders[HTTPHeaders.Common.userAgent] == nil {
            finalHeaders.add(name: HTTPHeaders.Common.userAgent, value: "NexusKit/1.0")
        }

        return HTTPRequest(
            method: method,
            url: finalURL,
            headers: finalHeaders,
            body: body,
            timeout: timeout
        )
    }
}

// MARK: - Convenience Extensions

extension HTTPRequest {
    /// 创建 GET 请求
    public static func get(_ url: URL) -> HTTPRequestBuilder {
        HTTPRequestBuilder(url: url).method(.GET)
    }

    /// 创建 POST 请求
    public static func post(_ url: URL) -> HTTPRequestBuilder {
        HTTPRequestBuilder(url: url).method(.POST)
    }

    /// 创建 PUT 请求
    public static func put(_ url: URL) -> HTTPRequestBuilder {
        HTTPRequestBuilder(url: url).method(.PUT)
    }

    /// 创建 DELETE 请求
    public static func delete(_ url: URL) -> HTTPRequestBuilder {
        HTTPRequestBuilder(url: url).method(.DELETE)
    }

    /// 创建 PATCH 请求
    public static func patch(_ url: URL) -> HTTPRequestBuilder {
        HTTPRequestBuilder(url: url).method(.PATCH)
    }
}

// MARK: - CustomStringConvertible

extension HTTPRequest: CustomStringConvertible {
    public var description: String {
        "\(method.rawValue) \(url.absoluteString)"
    }
}

extension HTTPHeaders: CustomStringConvertible {
    public var description: String {
        headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }
}
