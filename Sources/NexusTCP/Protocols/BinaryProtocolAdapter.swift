//
//  BinaryProtocolAdapter.swift
//  NexusTCP
//
//  Created by NexusKit Contributors
//
//  基于现有 Socket 实现的二进制协议适配器
//  协议格式：[4字节长度][20字节Header][可变长度Body]
//

import Foundation
#if canImport(NexusCore)
import NexusCore
#endif

// MARK: - Binary Protocol Adapter

/// 二进制协议适配器
public final class BinaryProtocolAdapter: ProtocolAdapter, @unchecked Sendable {
    // MARK: - Properties

    /// 协议名称
    public let name: String = "BinaryProtocol"

    /// 协议标签（固定值 0x7A5A）
    private let protocolTag: UInt16 = 0x7A5A

    /// 协议版本
    private let protocolVersion: UInt16

    /// 请求映射表（用于请求-响应匹配）
    private let requestMap: RequestMap

    /// 是否启用压缩
    private let compressionEnabled: Bool

    /// 消息编码器
    private let encoder: MessageEncoder

    /// 消息解码器
    private let decoder: MessageDecoder

    // MARK: - Initialization

    public init(
        version: UInt16 = 1,
        compressionEnabled: Bool = true,
        encoder: MessageEncoder = ProtobufEncoder(),
        decoder: MessageDecoder = ProtobufDecoder()
    ) {
        self.protocolVersion = version
        self.compressionEnabled = compressionEnabled
        self.encoder = encoder
        self.decoder = decoder
        self.requestMap = RequestMap()
    }

    // MARK: - Protocol Adapter

    public func encode<T: Encodable>(_ message: T, context: EncodingContext) throws -> Data {
        // 1. 编码消息体
        var bodyData = try encoder.encode(message)

        // 2. 压缩（如果启用且数据足够大）
        var typeFlags: UInt8 = 0
        if compressionEnabled && bodyData.count > 1024 {
            #if canImport(Compression)
            if let compressed = try? bodyData.gzipped() {
                bodyData = compressed
                typeFlags |= 0x20 // 设置压缩标志位
            }
            #endif
        }

        // 3. 生成请求 ID
        let requestId = requestMap.generateRequestId()

        // 4. 获取功能 ID（从上下文元数据中解析）
        let functionId: UInt32
        if let fidString = context.metadata["functionId"],
           let fid = UInt32(fidString) {
            functionId = fid
        } else {
            functionId = 0
        }

        // 5. 构建完整消息 = [4字节Len] + [20字节Header] + [Body]
        // Header格式: Tag(2) + Ver(2) + Tp(1) + Res(1) + Qid(4) + Fid(4) + Code(4) + Dh(2)
        let totalLength = UInt32(20 + bodyData.count)  // Len = Header(20) + Body
        
        var result = Data()
        result.reserveCapacity(Int(totalLength) + 4)
        
        // [4字节] Len
        result.appendBigEndian(totalLength)
        
        // [20字节] Header
        result.appendBigEndian(protocolTag)           // 4-5: Tag (0x7A5A)
        result.appendBigEndian(protocolVersion)       // 6-7: Ver
        result.appendBigEndian(typeFlags)             // 8: Tp (类型标志)
        result.appendBigEndian(UInt8(0))              // 9: Res (0=请求, 1=响应)
        result.appendBigEndian(requestId)             // 10-13: Qid (请求ID)
        result.appendBigEndian(functionId)            // 14-17: Fid (功能ID)
        result.appendBigEndian(UInt32(0))             // 18-21: Code (错误码，请求时为0)
        result.appendBigEndian(UInt16(0))             // 22-23: Dh (保留字段)
        
        // Body
        result.append(bodyData)

        // 7. 注册请求（用于响应匹配）
        if let callback = context.metadata["callback"] as? (Data) async -> Void {
            requestMap.registerRequest(id: requestId, callback: callback)
        }

        return result
    }

    public func decode<T: Decodable>(_ data: Data, as type: T.Type, context: DecodingContext) throws -> T {
        // 1. 解析 Header
        let header = try parseHeader(from: data)

        // 2. 提取 Body
        guard data.count >= 24 + header.bodyLength else {
            throw NexusError.invalidMessageFormat(reason: "Incomplete body")
        }

        var bodyData = data.subdata(in: 24..<(24 + header.bodyLength))

        // 3. 解压缩（如果有压缩标志）
        if header.isCompressed {
            #if canImport(Compression)
            bodyData = try bodyData.gunzipped()
            #else
            throw NexusError.custom(message: "Compression not supported", underlyingError: nil)
            #endif
        }

        // 4. 解码消息
        return try decoder.decode(type, from: bodyData)
    }

    public func handleIncoming(_ data: Data) async throws -> [ProtocolEvent] {
        // 1. 解析 Header
        let header = try parseHeader(from: data)

        // 2. 提取 Body
        guard data.count >= 24 + header.bodyLength else {
            throw NexusError.invalidMessageFormat(reason: "Incomplete body")
        }

        var bodyData = data.subdata(in: 24..<(24 + header.bodyLength))

        // 3. 解压缩
        if header.isCompressed {
            #if canImport(Compression)
            bodyData = try bodyData.gunzipped()
            #endif
        }

        // 4. 判断消息类型
        var events: [ProtocolEvent] = []

        if header.isResponse {
            // 响应消息：匹配请求并调用回调
            if let callback = requestMap.popRequest(id: header.requestId) {
                await callback(bodyData)
            }
            events.append(.response(id: "\(header.requestId)", data: bodyData))

        } else if header.isHeartbeat {
            // 心跳消息
            events.append(.control(type: .heartbeat, data: bodyData))

        } else {
            // 通知消息（服务器主动推送）
            events.append(.notification(event: "\(header.functionId)", data: bodyData))
        }

        return events
    }

    // MARK: - Heartbeat

    public func createHeartbeat() async throws -> Data {
        // 构建空心跳消息：[4字节Len] + [20字节Header]
        let totalLength: UInt32 = 20 // Header长度，无Body
        
        var result = Data()
        result.reserveCapacity(24)
        
        // [4字节] Len
        result.appendBigEndian(totalLength)
        
        // [20字节] Header
        result.appendBigEndian(protocolTag)          // 4-5: Tag (0x7A5A)
        result.appendBigEndian(protocolVersion)      // 6-7: Ver
        result.appendBigEndian(UInt8(0x01))          // 8: Tp (idle标志)
        result.appendBigEndian(UInt8(0))             // 9: Res (0=请求)
        result.appendBigEndian(UInt32(0))            // 10-13: Qid
        result.appendBigEndian(UInt32(0xFFFF))       // 14-17: Fid (心跳标记)
        result.appendBigEndian(UInt32(0))            // 18-21: Code
        result.appendBigEndian(UInt16(0))            // 22-23: Dh

        return result
    }

    // MARK: - Private Methods

    private func parseHeader(from data: Data) throws -> BinaryHeader {
        guard data.count >= 24 else {
            throw NexusError.invalidMessageFormat(reason: "Header too short")
        }

        // 读取 Header 字段（大端序）
        // 格式: [4字节Len] + [Tag(2) + Ver(2) + Tp(1) + Res(1) + Qid(4) + Fid(4) + Code(4) + Dh(2)]
        
        guard let length = data.readBigEndianUInt32(at: 0) else {
            throw NexusError.invalidMessageFormat(reason: "Invalid length field")
        }

        guard let tag = data.readBigEndianUInt16(at: 4) else {
            throw NexusError.invalidMessageFormat(reason: "Invalid tag field")
        }

        guard tag == protocolTag else {
            throw NexusError.invalidMessageFormat(reason: "Invalid protocol tag: \(tag)")
        }

        guard let version = data.readBigEndianUInt16(at: 6) else {
            throw NexusError.invalidMessageFormat(reason: "Invalid version field")
        }

        guard let typeFlags = data.readBigEndianUInt8(at: 8) else {
            throw NexusError.invalidMessageFormat(reason: "Invalid type field")
        }

        guard let responseFlag = data.readBigEndianUInt8(at: 9) else {
            throw NexusError.invalidMessageFormat(reason: "Invalid response flag")
        }

        guard let requestId = data.readBigEndianUInt32(at: 10) else {
            throw NexusError.invalidMessageFormat(reason: "Invalid request ID")
        }

        guard let functionId = data.readBigEndianUInt32(at: 14) else {
            throw NexusError.invalidMessageFormat(reason: "Invalid function ID")
        }

        guard let responseCode = data.readBigEndianUInt32(at: 18) else {
            throw NexusError.invalidMessageFormat(reason: "Invalid response code")
        }
        
        // Dh (保留字段) at 22-23, 我们可以选择读取或忽略
        // let dh = data.readBigEndianUInt16(at: 22)

        let bodyLength = Int(length) - 20

        return BinaryHeader(
            length: length,
            tag: tag,
            version: version,
            typeFlags: typeFlags,
            responseFlag: responseFlag,
            requestId: requestId,
            functionId: functionId,
            responseCode: responseCode,
            bodyLength: bodyLength
        )
    }
}

// MARK: - Binary Header

/// 二进制协议 Header
struct BinaryHeader {
    let length: UInt32
    let tag: UInt16
    let version: UInt16
    let typeFlags: UInt8
    let responseFlag: UInt8
    let requestId: UInt32
    let functionId: UInt32
    let responseCode: UInt32
    let bodyLength: Int

    var isCompressed: Bool {
        typeFlags & 0x20 != 0
    }

    var isIdle: Bool {
        typeFlags & 0x01 != 0
    }

    var isResponse: Bool {
        responseFlag == 1
    }

    var isHeartbeat: Bool {
        functionId == 0xFFFF
    }
}

// MARK: - Request Map

/// 请求映射表（线程安全）
private final class RequestMap: @unchecked Sendable {
    private let lock = UnfairLock()
    private var nextRequestId: UInt32 = 1
    private var requests: [UInt32: (Data) async -> Void] = [:]

    func generateRequestId() -> UInt32 {
        lock.withLock {
            let id = nextRequestId
            nextRequestId = nextRequestId &+ 1 // 溢出后从 0 开始
            return id
        }
    }

    func registerRequest(id: UInt32, callback: @escaping (Data) async -> Void) {
        lock.withLock {
            requests[id] = callback
        }
    }

    func popRequest(id: UInt32) -> ((Data) async -> Void)? {
        lock.withLock {
            requests.removeValue(forKey: id)
        }
    }
}

// MARK: - Message Encoder/Decoder Protocols

/// 消息编码器协议
public protocol MessageEncoder: Sendable {
    func encode<T: Encodable>(_ message: T) throws -> Data
}

/// 消息解码器协议
public protocol MessageDecoder: Sendable {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

// MARK: - Protobuf Encoder/Decoder

/// Protobuf 编码器
public struct ProtobufEncoder: MessageEncoder {
    public init() {}

    public func encode<T: Encodable>(_ message: T) throws -> Data {
        // 需要实际的 Protobuf 编码实现
        // 这里提供占位实现
        let encoder = JSONEncoder()
        return try encoder.encode(message)
    }
}

/// Protobuf 解码器
public struct ProtobufDecoder: MessageDecoder {
    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        // 需要实际的 Protobuf 解码实现
        // 这里提供占位实现
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
}

// MARK: - JSON Encoder/Decoder

/// JSON 编码器（用于测试）
public struct JSONMessageEncoder: MessageEncoder {
    private let encoder = JSONEncoder()

    public init() {}

    public func encode<T: Encodable>(_ message: T) throws -> Data {
        try encoder.encode(message)
    }
}

/// JSON 解码器（用于测试）
public struct JSONMessageDecoder: MessageDecoder {
    private let decoder = JSONDecoder()

    public init() {}

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
