//
//  HTTPResponse.swift
//  NexusHTTP
//
//  Created by NexusKit on 2025-10-20.
//
//  HTTP 响应结构

import Foundation

// MARK: - HTTP Status Code

/// HTTP 状态码
public enum HTTPStatusCode: Int, Sendable {
    // 1xx Informational
    case `continue` = 100
    case switchingProtocols = 101

    // 2xx Success
    case ok = 200
    case created = 201
    case accepted = 202
    case noContent = 204

    // 3xx Redirection
    case movedPermanently = 301
    case found = 302
    case seeOther = 303
    case notModified = 304
    case temporaryRedirect = 307
    case permanentRedirect = 308

    // 4xx Client Error
    case badRequest = 400
    case unauthorized = 401
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case requestTimeout = 408
    case conflict = 409
    case gone = 410
    case payloadTooLarge = 413
    case tooManyRequests = 429

    // 5xx Server Error
    case internalServerError = 500
    case notImplemented = 501
    case badGateway = 502
    case serviceUnavailable = 503
    case gatewayTimeout = 504

    /// 是否为成功状态码
    public var isSuccess: Bool {
        (200..<300).contains(rawValue)
    }

    /// 是否为重定向状态码
    public var isRedirect: Bool {
        (300..<400).contains(rawValue)
    }

    /// 是否为客户端错误
    public var isClientError: Bool {
        (400..<500).contains(rawValue)
    }

    /// 是否为服务器错误
    public var isServerError: Bool {
        (500..<600).contains(rawValue)
    }
}

// MARK: - HTTP Response

/// HTTP 响应
public struct HTTPResponse: Sendable {

    /// HTTP 版本
    public let version: String

    /// 状态码
    public let statusCode: Int

    /// 状态描述
    public let statusMessage: String

    /// 响应头
    public let headers: HTTPHeaders

    /// 响应体
    public let body: Data

    public init(
        version: String = "HTTP/1.1",
        statusCode: Int,
        statusMessage: String = "",
        headers: HTTPHeaders = HTTPHeaders(),
        body: Data = Data()
    ) {
        self.version = version
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.headers = headers
        self.body = body
    }

    /// 获取状态码枚举
    public var status: HTTPStatusCode? {
        HTTPStatusCode(rawValue: statusCode)
    }

    /// 是否成功
    public var isSuccess: Bool {
        status?.isSuccess ?? false
    }

    /// Content-Type
    public var contentType: String? {
        headers[HTTPHeaders.Common.contentType]
    }

    /// Content-Length
    public var contentLength: Int? {
        headers[HTTPHeaders.Common.contentLength].flatMap { Int($0) }
    }

    // MARK: - Body Decoding

    /// 解析为字符串
    public func string(encoding: String.Encoding = .utf8) -> String? {
        String(data: body, encoding: encoding)
    }

    /// 解析为 JSON
    public func json<T: Decodable>(as type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: body)
    }

    /// 解析为 JSON 对象
    public func jsonObject() throws -> Any {
        try JSONSerialization.jsonObject(with: body)
    }
}

// MARK: - Response Parser

/// HTTP 响应解析器
public struct HTTPResponseParser {

    /// 解析 HTTP 响应
    ///
    /// - Parameter data: 响应数据
    /// - Returns: 解析后的响应和消耗的字节数
    /// - Throws: 如果响应格式无效
    public static func parse(_ data: Data) throws -> (response: HTTPResponse, bytesConsumed: Int) {
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw HTTPError.invalidResponse
        }

        // 分割头部和正文
        let headerEndMarker = "\r\n\r\n"
        guard let headerEndRange = responseString.range(of: headerEndMarker) else {
            throw HTTPError.incompleteResponse
        }

        let headerSection = String(responseString[..<headerEndRange.lowerBound])
        let lines = headerSection.components(separatedBy: "\r\n")

        guard !lines.isEmpty else {
            throw HTTPError.invalidResponse
        }

        // 解析状态行
        let statusLine = lines[0]
        let statusComponents = statusLine.components(separatedBy: " ")
        guard statusComponents.count >= 3 else {
            throw HTTPError.invalidStatusLine
        }

        let version = statusComponents[0]
        guard let statusCode = Int(statusComponents[1]) else {
            throw HTTPError.invalidStatusCode
        }
        let statusMessage = statusComponents.dropFirst(2).joined(separator: " ")

        // 解析头部
        var headers = HTTPHeaders()
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            if let separatorIndex = line.firstIndex(of: ":") {
                let name = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
                headers.add(name: name, value: value)
            }
        }

        // 计算头部长度（包括 \r\n\r\n）
        let headerEndIndex = responseString.distance(from: responseString.startIndex, to: headerEndRange.upperBound)
        let headerBytes = headerEndIndex

        // 解析正文
        var body = Data()
        var totalBytesConsumed = headerBytes

        // 检查 Content-Length
        if let contentLengthStr = headers[HTTPHeaders.Common.contentLength],
           let contentLength = Int(contentLengthStr) {
            // 使用 Content-Length
            let bodyStartIndex = data.index(data.startIndex, offsetBy: headerBytes)
            let bodyEndIndex = data.index(bodyStartIndex, offsetBy: contentLength, limitedBy: data.endIndex) ?? data.endIndex

            guard data.distance(from: bodyStartIndex, to: bodyEndIndex) == contentLength else {
                throw HTTPError.incompleteResponse
            }

            body = data.subdata(in: bodyStartIndex..<bodyEndIndex)
            totalBytesConsumed += contentLength
        } else if let transferEncoding = headers[HTTPHeaders.Common.transferEncoding],
                  transferEncoding.lowercased().contains("chunked") {
            // Chunked 传输编码
            let bodyStartIndex = data.index(data.startIndex, offsetBy: headerBytes)
            let (chunkedBody, chunkedBytes) = try parseChunkedBody(data.suffix(from: bodyStartIndex))
            body = chunkedBody
            totalBytesConsumed += chunkedBytes
        } else {
            // 无 Content-Length，读取剩余所有数据
            let bodyStartIndex = data.index(data.startIndex, offsetBy: headerBytes)
            body = data.suffix(from: bodyStartIndex)
            totalBytesConsumed = data.count
        }

        let response = HTTPResponse(
            version: version,
            statusCode: statusCode,
            statusMessage: statusMessage,
            headers: headers,
            body: body
        )

        return (response, totalBytesConsumed)
    }

    /// 解析 Chunked 传输编码的正文
    private static func parseChunkedBody(_ data: Data) throws -> (body: Data, bytesConsumed: Int) {
        guard let dataString = String(data: data, encoding: .utf8) else {
            throw HTTPError.invalidChunkedEncoding
        }

        var body = Data()
        var offset = 0
        let lines = dataString.components(separatedBy: "\r\n")
        var lineIndex = 0

        while lineIndex < lines.count {
            let chunkSizeLine = lines[lineIndex]
            lineIndex += 1
            offset += chunkSizeLine.utf8.count + 2 // +2 for \r\n

            // 解析块大小（十六进制）
            guard let chunkSize = Int(chunkSizeLine, radix: 16) else {
                throw HTTPError.invalidChunkedEncoding
            }

            // 块大小为 0 表示结束
            if chunkSize == 0 {
                offset += 2 // 最后的 \r\n
                break
            }

            // 读取块数据
            guard lineIndex < lines.count else {
                throw HTTPError.incompleteResponse
            }

            let chunkDataStartIndex = data.index(data.startIndex, offsetBy: offset)
            let chunkDataEndIndex = data.index(chunkDataStartIndex, offsetBy: chunkSize, limitedBy: data.endIndex) ?? data.endIndex

            body.append(data.subdata(in: chunkDataStartIndex..<chunkDataEndIndex))
            offset += chunkSize + 2 // +2 for \r\n after chunk data
            lineIndex += 1
        }

        return (body, offset)
    }
}

// MARK: - HTTP Error

/// HTTP 错误
public enum HTTPError: Error, Sendable {
    /// 无效的响应
    case invalidResponse

    /// 不完整的响应
    case incompleteResponse

    /// 无效的状态行
    case invalidStatusLine

    /// 无效的状态码
    case invalidStatusCode

    /// 无效的 Chunked 编码
    case invalidChunkedEncoding

    /// HTTP 错误状态码
    case httpError(statusCode: Int, message: String)

    /// 连接失败
    case connectionFailed(Error)

    /// 超时
    case timeout
}

// MARK: - CustomStringConvertible

extension HTTPResponse: CustomStringConvertible {
    public var description: String {
        "\(version) \(statusCode) \(statusMessage)"
    }
}

extension HTTPStatusCode: CustomStringConvertible {
    public var description: String {
        "\(rawValue)"
    }
}
