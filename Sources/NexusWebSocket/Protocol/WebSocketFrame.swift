//
//  WebSocketFrame.swift
//  NexusWebSocket
//
//  Created by NexusKit on 2025-10-20.
//
//  WebSocket 帧解析器 - RFC 6455 完整实现

import Foundation

// MARK: - WebSocket Frame

/// WebSocket 帧结构
///
/// 符合 RFC 6455 规范的 WebSocket 数据帧。
///
/// ## 帧格式
///
/// ```
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-------+-+-------------+-------------------------------+
/// |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
/// |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
/// |N|V|V|V|       |S|             |   (if payload len==126/127)   |
/// | |1|2|3|       |K|             |                               |
/// +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
/// |     Extended payload length continued, if payload len == 127  |
/// + - - - - - - - - - - - - - - - +-------------------------------+
/// |                               |Masking-key, if MASK set to 1  |
/// +-------------------------------+-------------------------------+
/// | Masking-key (continued)       |          Payload Data         |
/// +-------------------------------- - - - - - - - - - - - - - - - +
/// :                     Payload Data continued ...                :
/// + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
/// |                     Payload Data continued ...                |
/// +---------------------------------------------------------------+
/// ```
public struct WebSocketFrame: Sendable {

    // MARK: - Properties

    /// FIN 位 - 是否为消息的最后一帧
    public let fin: Bool

    /// RSV1 位 - 保留位1（用于扩展）
    public let rsv1: Bool

    /// RSV2 位 - 保留位2（用于扩展）
    public let rsv2: Bool

    /// RSV3 位 - 保留位3（用于扩展）
    public let rsv3: Bool

    /// 操作码
    public let opcode: Opcode

    /// 是否使用掩码
    public let masked: Bool

    /// 掩码密钥（如果masked为true）
    public let maskKey: [UInt8]?

    /// 有效载荷数据
    public let payload: Data

    // MARK: - Opcode

    /// WebSocket 操作码
    public enum Opcode: UInt8, Sendable {
        /// 继续帧
        case continuation = 0x0

        /// 文本帧（UTF-8编码）
        case text = 0x1

        /// 二进制帧
        case binary = 0x2

        // 0x3-0x7 保留用于未来的非控制帧

        /// 连接关闭
        case close = 0x8

        /// Ping
        case ping = 0x9

        /// Pong
        case pong = 0xA

        // 0xB-0xF 保留用于未来的控制帧

        /// 是否为控制帧
        public var isControl: Bool {
            rawValue & 0x08 != 0
        }

        /// 是否为数据帧
        public var isData: Bool {
            !isControl
        }
    }

    // MARK: - Initialization

    /// 初始化 WebSocket 帧
    public init(
        fin: Bool = true,
        rsv1: Bool = false,
        rsv2: Bool = false,
        rsv3: Bool = false,
        opcode: Opcode,
        masked: Bool = false,
        maskKey: [UInt8]? = nil,
        payload: Data = Data()
    ) {
        self.fin = fin
        self.rsv1 = rsv1
        self.rsv2 = rsv2
        self.rsv3 = rsv3
        self.opcode = opcode
        self.masked = masked
        self.maskKey = maskKey
        self.payload = payload
    }

    // MARK: - Convenience Initializers

    /// 创建文本帧
    public static func text(_ text: String, masked: Bool = false) -> WebSocketFrame {
        let payload = text.data(using: .utf8) ?? Data()
        return WebSocketFrame(
            opcode: .text,
            masked: masked,
            maskKey: masked ? generateMaskKey() : nil,
            payload: payload
        )
    }

    /// 创建二进制帧
    public static func binary(_ data: Data, masked: Bool = false) -> WebSocketFrame {
        return WebSocketFrame(
            opcode: .binary,
            masked: masked,
            maskKey: masked ? generateMaskKey() : nil,
            payload: data
        )
    }

    /// 创建 Ping 帧
    public static func ping(_ data: Data = Data(), masked: Bool = false) -> WebSocketFrame {
        return WebSocketFrame(
            opcode: .ping,
            masked: masked,
            maskKey: masked ? generateMaskKey() : nil,
            payload: data
        )
    }

    /// 创建 Pong 帧
    public static func pong(_ data: Data = Data(), masked: Bool = false) -> WebSocketFrame {
        return WebSocketFrame(
            opcode: .pong,
            masked: masked,
            maskKey: masked ? generateMaskKey() : nil,
            payload: data
        )
    }

    /// 创建 Close 帧
    public static func close(
        code: CloseCode = .normal,
        reason: String? = nil,
        masked: Bool = false
    ) -> WebSocketFrame {
        var payload = Data()

        // 添加关闭码（2字节，大端序）
        payload.append(UInt8((code.rawValue >> 8) & 0xFF))
        payload.append(UInt8(code.rawValue & 0xFF))

        // 添加关闭原因（UTF-8编码）
        if let reason = reason, let reasonData = reason.data(using: .utf8) {
            payload.append(reasonData)
        }

        return WebSocketFrame(
            opcode: .close,
            masked: masked,
            maskKey: masked ? generateMaskKey() : nil,
            payload: payload
        )
    }

    // MARK: - Close Code

    /// WebSocket 关闭码
    public enum CloseCode: UInt16, Sendable {
        /// 正常关闭
        case normal = 1000

        /// 服务器关闭
        case goingAway = 1001

        /// 协议错误
        case protocolError = 1002

        /// 不支持的数据类型
        case unsupportedData = 1003

        /// 保留
        case reserved = 1004

        /// 无状态码
        case noStatusReceived = 1005

        /// 异常关闭
        case abnormalClosure = 1006

        /// 无效数据
        case invalidFramePayloadData = 1007

        /// 策略违规
        case policyViolation = 1008

        /// 消息过大
        case messageTooBig = 1009

        /// 缺少扩展
        case mandatoryExtension = 1010

        /// 内部服务器错误
        case internalServerError = 1011

        /// TLS 握手失败
        case tlsHandshake = 1015
    }
}

// MARK: - Frame Encoding

extension WebSocketFrame {

    /// 编码为字节数据
    public func encode() throws -> Data {
        var data = Data()

        // 第一个字节：FIN + RSV + Opcode
        var byte0: UInt8 = opcode.rawValue
        if fin { byte0 |= 0x80 }
        if rsv1 { byte0 |= 0x40 }
        if rsv2 { byte0 |= 0x20 }
        if rsv3 { byte0 |= 0x10 }
        data.append(byte0)

        // 第二个字节：MASK + Payload Length
        let payloadLength = payload.count
        var byte1: UInt8 = 0
        if masked { byte1 |= 0x80 }

        if payloadLength < 126 {
            byte1 |= UInt8(payloadLength)
            data.append(byte1)
        } else if payloadLength <= 0xFFFF {
            byte1 |= 126
            data.append(byte1)
            // 扩展长度（16位，大端序）
            data.append(UInt8((payloadLength >> 8) & 0xFF))
            data.append(UInt8(payloadLength & 0xFF))
        } else {
            byte1 |= 127
            data.append(byte1)
            // 扩展长度（64位，大端序）
            data.append(UInt8((payloadLength >> 56) & 0xFF))
            data.append(UInt8((payloadLength >> 48) & 0xFF))
            data.append(UInt8((payloadLength >> 40) & 0xFF))
            data.append(UInt8((payloadLength >> 32) & 0xFF))
            data.append(UInt8((payloadLength >> 24) & 0xFF))
            data.append(UInt8((payloadLength >> 16) & 0xFF))
            data.append(UInt8((payloadLength >> 8) & 0xFF))
            data.append(UInt8(payloadLength & 0xFF))
        }

        // 掩码密钥（如果需要）
        if masked {
            guard let maskKey = maskKey, maskKey.count == 4 else {
                throw WebSocketError.invalidMaskKey
            }
            data.append(contentsOf: maskKey)
        }

        // 有效载荷（如果需要掩码则进行掩码处理）
        if masked, let maskKey = maskKey {
            let maskedPayload = Self.applyMask(payload, maskKey: maskKey)
            data.append(maskedPayload)
        } else {
            data.append(payload)
        }

        return data
    }

    /// 从字节数据解码
    public static func decode(from data: Data) throws -> (frame: WebSocketFrame, bytesConsumed: Int) {
        guard data.count >= 2 else {
            throw WebSocketError.incompleteFrame
        }

        var offset = 0

        // 第一个字节：FIN + RSV + Opcode
        let byte0 = data[offset]
        offset += 1

        let fin = (byte0 & 0x80) != 0
        let rsv1 = (byte0 & 0x40) != 0
        let rsv2 = (byte0 & 0x20) != 0
        let rsv3 = (byte0 & 0x10) != 0

        guard let opcode = Opcode(rawValue: byte0 & 0x0F) else {
            throw WebSocketError.invalidOpcode(byte0 & 0x0F)
        }

        // 第二个字节：MASK + Payload Length
        let byte1 = data[offset]
        offset += 1

        let masked = (byte1 & 0x80) != 0
        var payloadLength = Int(byte1 & 0x7F)

        // 扩展长度
        if payloadLength == 126 {
            guard data.count >= offset + 2 else {
                throw WebSocketError.incompleteFrame
            }
            payloadLength = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2
        } else if payloadLength == 127 {
            guard data.count >= offset + 8 else {
                throw WebSocketError.incompleteFrame
            }
            payloadLength = 0
            for i in 0..<8 {
                payloadLength = (payloadLength << 8) | Int(data[offset + i])
            }
            offset += 8
        }

        // 掩码密钥
        var maskKey: [UInt8]?
        if masked {
            guard data.count >= offset + 4 else {
                throw WebSocketError.incompleteFrame
            }
            maskKey = Array(data[offset..<offset + 4])
            offset += 4
        }

        // 有效载荷
        guard data.count >= offset + payloadLength else {
            throw WebSocketError.incompleteFrame
        }

        var payload = Data(data[offset..<offset + payloadLength])
        offset += payloadLength

        // 取消掩码
        if masked, let maskKey = maskKey {
            payload = Self.applyMask(payload, maskKey: maskKey)
        }

        // 验证控制帧
        if opcode.isControl {
            // 控制帧不能分片
            guard fin else {
                throw WebSocketError.fragmentedControlFrame
            }

            // 控制帧载荷不能超过125字节
            guard payloadLength <= 125 else {
                throw WebSocketError.controlFrameTooLarge
            }
        }

        let frame = WebSocketFrame(
            fin: fin,
            rsv1: rsv1,
            rsv2: rsv2,
            rsv3: rsv3,
            opcode: opcode,
            masked: masked,
            maskKey: maskKey,
            payload: payload
        )

        return (frame, offset)
    }
}

// MARK: - Masking

extension WebSocketFrame {

    /// 生成随机掩码密钥
    private static func generateMaskKey() -> [UInt8] {
        var key = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 {
            key[i] = UInt8.random(in: 0...255)
        }
        return key
    }

    /// 应用/取消掩码
    private static func applyMask(_ data: Data, maskKey: [UInt8]) -> Data {
        guard maskKey.count == 4 else { return data }

        var result = Data(capacity: data.count)
        for (i, byte) in data.enumerated() {
            result.append(byte ^ maskKey[i % 4])
        }
        return result
    }
}

// MARK: - WebSocket Error

/// WebSocket 错误
public enum WebSocketError: Error, Sendable {
    /// 不完整的帧
    case incompleteFrame

    /// 无效的操作码
    case invalidOpcode(UInt8)

    /// 无效的掩码密钥
    case invalidMaskKey

    /// 控制帧过大
    case controlFrameTooLarge

    /// 控制帧分片
    case fragmentedControlFrame

    /// 无效的 UTF-8 文本
    case invalidUTF8Text

    /// 无效的关闭码
    case invalidCloseCode
}

// MARK: - CustomStringConvertible

extension WebSocketFrame: CustomStringConvertible {
    public var description: String {
        var parts: [String] = []
        parts.append("FIN=\(fin ? 1 : 0)")
        if rsv1 { parts.append("RSV1") }
        if rsv2 { parts.append("RSV2") }
        if rsv3 { parts.append("RSV3") }
        parts.append("opcode=\(opcode)")
        parts.append("masked=\(masked)")
        parts.append("payload=\(payload.count)bytes")
        return "WebSocketFrame(\(parts.joined(separator: ", ")))"
    }
}

extension WebSocketFrame.Opcode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .continuation: return "CONTINUATION"
        case .text: return "TEXT"
        case .binary: return "BINARY"
        case .close: return "CLOSE"
        case .ping: return "PING"
        case .pong: return "PONG"
        }
    }
}
