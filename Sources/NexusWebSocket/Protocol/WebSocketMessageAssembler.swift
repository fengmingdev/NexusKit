//
//  WebSocketMessageAssembler.swift
//  NexusWebSocket
//
//  Created by NexusKit on 2025-10-20.
//
//  WebSocket 消息组装器 - 处理分片消息

import Foundation

// MARK: - WebSocket Message

/// WebSocket 完整消息
public struct WebSocketMessage: Sendable {
    /// 消息类型
    public enum MessageType: Sendable {
        case text
        case binary
    }

    /// 消息类型
    public let type: MessageType

    /// 消息数据
    public let data: Data

    /// 是否为压缩消息
    public let compressed: Bool

    public init(type: MessageType, data: Data, compressed: Bool = false) {
        self.type = type
        self.data = data
        self.compressed = compressed
    }

    /// 转换为文本（如果是文本消息）
    public var text: String? {
        guard type == .text else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Message Assembler

/// WebSocket 消息组装器
///
/// 负责将分片的 WebSocket 帧组装成完整的消息。
///
/// ## 分片规则
///
/// 1. 数据帧可以分片，控制帧不能分片
/// 2. 第一个分片帧的 opcode 表示消息类型（TEXT 或 BINARY）
/// 3. 后续分片帧使用 CONTINUATION opcode
/// 4. 最后一个分片帧的 FIN 位为 1
/// 5. 控制帧可以穿插在分片消息之间
///
/// ## 示例
///
/// ```swift
/// let assembler = WebSocketMessageAssembler()
///
/// // 处理帧
/// for frame in frames {
///     if let message = try assembler.processFrame(frame) {
///         // 收到完整消息
///         print("Message: \(message.text ?? "")")
///     }
/// }
/// ```
public actor WebSocketMessageAssembler {

    // MARK: - Properties

    /// 当前正在组装的消息类型
    private var currentMessageType: WebSocketMessage.MessageType?

    /// 当前正在组装的分片数据
    private var fragments: [Data] = []

    /// 是否为压缩消息（RSV1）
    private var isCompressed: Bool = false

    /// 统计信息
    private var stats = Statistics()

    private struct Statistics {
        var totalMessages: Int = 0
        var fragmentedMessages: Int = 0
        var largestMessage: Int = 0
        var controlFrames: Int = 0
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Frame Processing

    /// 处理 WebSocket 帧
    ///
    /// - Parameter frame: WebSocket 帧
    /// - Returns: 如果组装完成，返回完整消息；否则返回 nil
    /// - Throws: 如果帧序列无效
    public func processFrame(_ frame: WebSocketFrame) throws -> WebSocketMessage? {
        // 处理控制帧
        if frame.opcode.isControl {
            stats.controlFrames += 1
            return try handleControlFrame(frame)
        }

        // 处理数据帧
        return try handleDataFrame(frame)
    }

    /// 重置组装器状态
    public func reset() {
        currentMessageType = nil
        fragments.removeAll()
        isCompressed = false
    }

    /// 获取统计信息
    public func getStatistics() -> (
        totalMessages: Int,
        fragmentedMessages: Int,
        largestMessage: Int,
        controlFrames: Int
    ) {
        (
            totalMessages: stats.totalMessages,
            fragmentedMessages: stats.fragmentedMessages,
            largestMessage: stats.largestMessage,
            controlFrames: stats.controlFrames
        )
    }

    // MARK: - Private Methods

    /// 处理控制帧
    private func handleControlFrame(_ frame: WebSocketFrame) throws -> WebSocketMessage? {
        // 控制帧不能分片
        guard frame.fin else {
            throw MessageAssemblerError.fragmentedControlFrame
        }

        // 控制帧立即返回（作为独立消息）
        switch frame.opcode {
        case .close:
            return WebSocketMessage(type: .binary, data: frame.payload)

        case .ping, .pong:
            // Ping/Pong 通常不作为消息返回，由连接层处理
            return nil

        default:
            // 未知控制帧
            return nil
        }
    }

    /// 处理数据帧
    private func handleDataFrame(_ frame: WebSocketFrame) throws -> WebSocketMessage? {
        switch frame.opcode {
        case .text, .binary:
            // 开始新消息
            guard currentMessageType == nil else {
                throw MessageAssemblerError.unexpectedDataFrame
            }

            currentMessageType = frame.opcode == .text ? .text : .binary
            isCompressed = frame.rsv1

            if frame.fin {
                // 单帧消息
                let message = createMessage(data: frame.payload)
                reset()
                stats.totalMessages += 1
                stats.largestMessage = max(stats.largestMessage, frame.payload.count)
                return message
            } else {
                // 开始分片消息
                fragments.append(frame.payload)
                return nil
            }

        case .continuation:
            // 继续分片消息
            guard currentMessageType != nil else {
                throw MessageAssemblerError.unexpectedContinuationFrame
            }

            fragments.append(frame.payload)

            if frame.fin {
                // 最后一个分片
                let combinedData = fragments.reduce(Data(), +)
                let message = createMessage(data: combinedData)
                reset()
                stats.totalMessages += 1
                stats.fragmentedMessages += 1
                stats.largestMessage = max(stats.largestMessage, combinedData.count)
                return message
            } else {
                // 还有更多分片
                return nil
            }

        default:
            throw MessageAssemblerError.invalidOpcode
        }
    }

    /// 创建消息
    private func createMessage(data: Data) -> WebSocketMessage {
        guard let type = currentMessageType else {
            return WebSocketMessage(type: .binary, data: data)
        }

        return WebSocketMessage(
            type: type,
            data: data,
            compressed: isCompressed
        )
    }
}

// MARK: - Message Fragmenter

/// WebSocket 消息分片器
///
/// 将大消息分割成多个帧。
public struct WebSocketMessageFragmenter {

    /// 分片大小（默认 32KB）
    public let fragmentSize: Int

    public init(fragmentSize: Int = 32 * 1024) {
        self.fragmentSize = fragmentSize
    }

    /// 将消息分片
    ///
    /// - Parameters:
    ///   - message: 要分片的消息
    ///   - masked: 是否使用掩码
    /// - Returns: 帧数组
    public func fragment(message: WebSocketMessage, masked: Bool = false) -> [WebSocketFrame] {
        guard message.data.count > fragmentSize else {
            // 消息足够小，不需要分片
            let opcode: WebSocketFrame.Opcode = message.type == .text ? .text : .binary
            return [WebSocketFrame(
                fin: true,
                rsv1: message.compressed,
                opcode: opcode,
                masked: masked,
                maskKey: masked ? generateMaskKey() : nil,
                payload: message.data
            )]
        }

        var frames: [WebSocketFrame] = []
        var offset = 0
        let totalSize = message.data.count

        while offset < totalSize {
            let chunkSize = min(fragmentSize, totalSize - offset)
            let chunk = message.data.subdata(in: offset..<offset + chunkSize)

            let isFirst = offset == 0
            let isLast = offset + chunkSize >= totalSize

            let opcode: WebSocketFrame.Opcode
            if isFirst {
                opcode = message.type == .text ? .text : .binary
            } else {
                opcode = .continuation
            }

            let frame = WebSocketFrame(
                fin: isLast,
                rsv1: isFirst && message.compressed,
                opcode: opcode,
                masked: masked,
                maskKey: masked ? generateMaskKey() : nil,
                payload: chunk
            )

            frames.append(frame)
            offset += chunkSize
        }

        return frames
    }

    private func generateMaskKey() -> [UInt8] {
        (0..<4).map { _ in UInt8.random(in: 0...255) }
    }
}

// MARK: - Message Assembler Error

/// 消息组装器错误
public enum MessageAssemblerError: Error, Sendable {
    /// 分片的控制帧
    case fragmentedControlFrame

    /// 意外的数据帧
    case unexpectedDataFrame

    /// 意外的继续帧
    case unexpectedContinuationFrame

    /// 无效的操作码
    case invalidOpcode

    /// 消息过大
    case messageTooBig(size: Int)
}

// MARK: - CustomStringConvertible

extension WebSocketMessage: CustomStringConvertible {
    public var description: String {
        let typeStr = type == .text ? "TEXT" : "BINARY"
        let compressedStr = compressed ? " (compressed)" : ""
        return "WebSocketMessage(\(typeStr), \(data.count) bytes\(compressedStr))"
    }
}
