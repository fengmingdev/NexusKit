//
//  BufferManager.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Buffer Manager

/// 缓冲区管理器
/// 提供零拷贝、增量解析、自动清理的高性能缓冲区
public actor BufferManager {

    // MARK: - Properties

    /// 内部缓冲区
    private var buffer: Data

    /// 读取索引(已处理数据的位置)
    private var readIndex: Int = 0

    /// 最大缓冲区大小(默认10MB)
    private let maxSize: Int

    /// 自动压缩阈值(当已处理数据超过此值时触发压缩)
    private let compactionThreshold: Int

    /// 当前可读数据长度
    public var availableBytes: Int {
        buffer.count - readIndex
    }

    /// 缓冲区使用率
    public var usageRatio: Double {
        guard maxSize > 0 else { return 0 }
        return Double(buffer.count) / Double(maxSize)
    }

    // MARK: - Initialization

    public init(
        initialCapacity: Int = 8192,
        maxSize: Int = 10 * 1024 * 1024,
        compactionThreshold: Int = 5 * 1024 * 1024
    ) {
        self.buffer = Data(capacity: initialCapacity)
        self.maxSize = maxSize
        self.compactionThreshold = compactionThreshold
    }

    // MARK: - Write Operations

    /// 追加数据到缓冲区
    public func append(_ data: Data) throws {
        // 检查容量限制
        let newSize = buffer.count + data.count
        guard newSize <= maxSize else {
            throw NexusError.bufferOverflow
        }

        buffer.append(data)

        // 检查是否需要压缩
        if readIndex > compactionThreshold {
            compact()
        }
    }

    /// 批量追加
    public func append(contentsOf dataArray: [Data]) throws {
        let totalSize = dataArray.reduce(0) { $0 + $1.count }
        guard buffer.count + totalSize <= maxSize else {
            throw NexusError.bufferOverflow
        }

        for data in dataArray {
            buffer.append(data)
        }

        if readIndex > compactionThreshold {
            compact()
        }
    }

    // MARK: - Read Operations

    /// 读取指定长度的数据(零拷贝,返回子数据范围)
    public func read(length: Int) -> Data? {
        guard availableBytes >= length else {
            return nil
        }

        let range = readIndex..<(readIndex + length)
        let data = buffer.subdata(in: range)
        readIndex += length

        return data
    }

    /// 窥视数据(不移动读取索引)
    public func peek(length: Int) -> Data? {
        guard availableBytes >= length else {
            return nil
        }

        let range = readIndex..<(readIndex + length)
        return buffer.subdata(in: range)
    }

    /// 读取所有可用数据
    public func readAll() -> Data {
        let data = buffer.subdata(in: readIndex..<buffer.count)
        readIndex = buffer.count
        return data
    }

    /// 跳过指定数量的字节
    public func skip(_ count: Int) {
        readIndex = min(readIndex + count, buffer.count)
    }

    // MARK: - Advanced Read Operations

    /// 使用零拷贝方式读取数据
    /// - Parameter length: 要读取的长度
    /// - Returns: 指向缓冲区的不安全指针
    public func withUnsafeBytes<R>(
        length: Int,
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) rethrows -> R? {
        guard availableBytes >= length else {
            return nil
        }

        let range = readIndex..<(readIndex + length)
        return try buffer[range].withUnsafeBytes(body)
    }

    /// 查找特定模式
    public func findPattern(_ pattern: Data) -> Int? {
        let searchRange = readIndex..<buffer.count
        guard let range = buffer[searchRange].range(of: pattern) else {
            return nil
        }

        return range.lowerBound - readIndex
    }

    /// 读取直到找到分隔符
    public func readUntil(delimiter: Data) -> Data? {
        guard let offset = findPattern(delimiter) else {
            return nil
        }

        let data = read(length: offset)
        skip(delimiter.count) // 跳过分隔符
        return data
    }

    // MARK: - Buffer Management

    /// 压缩缓冲区(移除已读数据)
    public func compact() {
        guard readIndex > 0 else { return }

        let unreadData = buffer.subdata(in: readIndex..<buffer.count)
        buffer = unreadData
        readIndex = 0

        print("[BufferManager] 缓冲区已压缩, 释放 \(readIndex) 字节")
    }

    /// 清空缓冲区
    public func clear() {
        buffer.removeAll(keepingCapacity: true)
        readIndex = 0
    }

    /// 重置缓冲区(释放所有内存)
    public func reset() {
        buffer.removeAll(keepingCapacity: false)
        readIndex = 0
    }

    // MARK: - Statistics

    /// 缓冲区统计信息
    public struct Statistics: Sendable {
        public let totalSize: Int
        public let readIndex: Int
        public let availableBytes: Int
        public let usageRatio: Double
        public let isCompactionNeeded: Bool
    }

    /// 获取统计信息
    public func statistics() -> Statistics {
        Statistics(
            totalSize: buffer.count,
            readIndex: readIndex,
            availableBytes: availableBytes,
            usageRatio: usageRatio,
            isCompactionNeeded: readIndex > compactionThreshold
        )
    }
}

// MARK: - Message Parser Protocol

/// 消息解析器协议
public protocol MessageParser: Sendable {
    associatedtype Message: Sendable

    /// 尝试从缓冲区解析消息
    /// - Parameter buffer: 缓冲区管理器
    /// - Returns: 解析的消息,如果数据不足则返回nil
    func parse(from buffer: BufferManager) async throws -> Message?
}

// MARK: - Buffer Manager Extensions

extension BufferManager {

    /// 使用解析器解析所有可用消息
    public func parseMessages<P: MessageParser>(
        using parser: P
    ) async throws -> [P.Message] {
        var messages: [P.Message] = []

        while let message = try await parser.parse(from: self) {
            messages.append(message)
        }

        return messages
    }

    /// 异步迭代解析消息
    public func messages<P: MessageParser>(
        using parser: P
    ) -> AsyncThrowingStream<P.Message, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    while let message = try await parser.parse(from: self) {
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
