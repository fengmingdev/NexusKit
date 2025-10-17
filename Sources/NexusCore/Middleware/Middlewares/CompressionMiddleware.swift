//
//  CompressionMiddleware.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation

// MARK: - Compression Middleware

/// 压缩中间件
///
/// 自动压缩和解压缩数据，减少网络传输量。
///
/// ## 功能特性
///
/// - 自动压缩大于阈值的数据
/// - GZIP 压缩算法
/// - 自动检测并解压缩
/// - 压缩统计
/// - 可配置压缩级别
///
/// ## 使用示例
///
/// ### 基础使用（默认配置）
/// ```swift
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(CompressionMiddleware())  // 默认 1KB 阈值
///     .connect()
/// ```
///
/// ### 自定义配置
/// ```swift
/// let compression = CompressionMiddleware(
///     threshold: 512,        // 512 字节阈值
///     algorithm: .gzip       // GZIP 算法
/// )
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(compression)
///     .connect()
/// ```
///
/// ## 性能优势
///
/// 对于文本数据，通常可以达到 60-80% 的压缩率：
/// - 原始大小: 10KB
/// - 压缩后: 2-4KB
/// - 节省: 60-80%
///
/// ## 注意事项
///
/// - 小数据（< 1KB）不压缩（压缩开销 > 节省）
/// - 已压缩的数据（图片、视频等）不应再压缩
/// - 压缩会增加 CPU 使用，需权衡
#if canImport(Compression)
import Compression

public struct CompressionMiddleware: Middleware {
    // MARK: - Properties

    public let name = "CompressionMiddleware"
    public let priority: Int

    /// 压缩算法
    private let algorithm: Algorithm

    /// 压缩阈值（字节）
    private let threshold: Int

    /// 是否记录统计信息
    private let enableStats: Bool

    /// 统计信息
    private let stats: CompressionStats

    // MARK: - Algorithm

    /// 压缩算法
    public enum Algorithm: Sendable {
        case gzip
        case lz4
        case lzma
        case zlib

        var compressionAlgorithm: compression_algorithm {
            switch self {
            case .gzip, .zlib:
                return COMPRESSION_ZLIB
            case .lz4:
                return COMPRESSION_LZ4
            case .lzma:
                return COMPRESSION_LZMA
            }
        }
    }

    // MARK: - Initialization

    /// 初始化压缩中间件
    /// - Parameters:
    ///   - threshold: 压缩阈值（字节），默认 1024（1KB）
    ///   - algorithm: 压缩算法，默认 `.gzip`
    ///   - enableStats: 是否启用统计，默认 `true`
    ///   - priority: 中间件优先级，默认 50
    public init(
        threshold: Int = 1024,
        algorithm: Algorithm = .gzip,
        enableStats: Bool = true,
        priority: Int = 50
    ) {
        self.threshold = threshold
        self.algorithm = algorithm
        self.enableStats = enableStats
        self.priority = priority
        self.stats = CompressionStats()
    }

    // MARK: - Middleware Protocol

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        // 小于阈值，不压缩
        guard data.count >= threshold else {
            return data
        }

        // 尝试压缩
        do {
            let compressed = try compress(data)

            // 记录统计
            if enableStats {
                await stats.record(
                    original: data.count,
                    compressed: compressed.count,
                    direction: .outgoing
                )
            }

            // 如果压缩后更大，返回原数据
            if compressed.count >= data.count {
                return data
            }

            return compressed

        } catch {
            // 压缩失败，返回原数据
            return data
        }
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        // 尝试解压缩
        do {
            let decompressed = try decompress(data)

            // 记录统计
            if enableStats {
                await stats.record(
                    original: decompressed.count,
                    compressed: data.count,
                    direction: .incoming
                )
            }

            return decompressed

        } catch {
            // 解压失败，可能不是压缩数据，返回原数据
            return data
        }
    }

    public func onDisconnect(connection: any Connection, reason: DisconnectReason) async {
        if enableStats {
            let summary = await stats.summary()
            print("📊 [Compression Stats] \(connection.id)")
            print("   Outgoing: \(summary.totalOutgoingOriginal) → \(summary.totalOutgoingCompressed) bytes (节省 \(summary.outgoingSavingsPercent)%)")
            print("   Incoming: \(summary.totalIncomingOriginal) → \(summary.totalIncomingCompressed) bytes (节省 \(summary.incomingSavingsPercent)%)")
        }
    }

    // MARK: - Compression

    private func compress(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Data in
            guard let sourcePtr = sourceBuffer.baseAddress else {
                throw NexusError.custom(message: "Invalid source buffer", underlyingError: nil)
            }

            let destSize = data.count
            var destBuffer = Data(count: destSize)

            let compressedSize = destBuffer.withUnsafeMutableBytes { (destBuffer: UnsafeMutableRawBufferPointer) -> Int in
                guard let destPtr = destBuffer.baseAddress else { return 0 }

                return compression_encode_buffer(
                    destPtr,
                    destSize,
                    sourcePtr,
                    data.count,
                    nil,
                    algorithm.compressionAlgorithm
                )
            }

            guard compressedSize > 0 else {
                throw NexusError.custom(message: "Compression failed", underlyingError: nil)
            }

            destBuffer.count = compressedSize
            return destBuffer
        }
    }

    private func decompress(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Data in
            guard let sourcePtr = sourceBuffer.baseAddress else {
                throw NexusError.custom(message: "Invalid source buffer", underlyingError: nil)
            }

            // 假设解压后最多 10 倍大小
            let destSize = data.count * 10
            var destBuffer = Data(count: destSize)

            let decompressedSize = destBuffer.withUnsafeMutableBytes { (destBuffer: UnsafeMutableRawBufferPointer) -> Int in
                guard let destPtr = destBuffer.baseAddress else { return 0 }

                return compression_decode_buffer(
                    destPtr,
                    destSize,
                    sourcePtr,
                    data.count,
                    nil,
                    algorithm.compressionAlgorithm
                )
            }

            guard decompressedSize > 0 else {
                throw NexusError.custom(message: "Decompression failed", underlyingError: nil)
            }

            destBuffer.count = decompressedSize
            return destBuffer
        }
    }
}

// MARK: - Compression Stats

/// 压缩统计信息
actor CompressionStats {
    private var totalOutgoingOriginal: Int64 = 0
    private var totalOutgoingCompressed: Int64 = 0
    private var totalIncomingOriginal: Int64 = 0
    private var totalIncomingCompressed: Int64 = 0

    func record(original: Int, compressed: Int, direction: Direction) {
        switch direction {
        case .outgoing:
            totalOutgoingOriginal += Int64(original)
            totalOutgoingCompressed += Int64(compressed)
        case .incoming:
            totalIncomingOriginal += Int64(original)
            totalIncomingCompressed += Int64(compressed)
        }
    }

    func summary() -> Summary {
        let outgoingSavings = totalOutgoingOriginal > 0
            ? Int((1.0 - Double(totalOutgoingCompressed) / Double(totalOutgoingOriginal)) * 100)
            : 0

        let incomingSavings = totalIncomingOriginal > 0
            ? Int((1.0 - Double(totalIncomingCompressed) / Double(totalIncomingOriginal)) * 100)
            : 0

        return Summary(
            totalOutgoingOriginal: totalOutgoingOriginal,
            totalOutgoingCompressed: totalOutgoingCompressed,
            totalIncomingOriginal: totalIncomingOriginal,
            totalIncomingCompressed: totalIncomingCompressed,
            outgoingSavingsPercent: outgoingSavings,
            incomingSavingsPercent: incomingSavings
        )
    }

    enum Direction {
        case outgoing
        case incoming
    }

    struct Summary {
        let totalOutgoingOriginal: Int64
        let totalOutgoingCompressed: Int64
        let totalIncomingOriginal: Int64
        let totalIncomingCompressed: Int64
        let outgoingSavingsPercent: Int
        let incomingSavingsPercent: Int
    }
}

#else

// 不支持压缩的平台的占位实现
public struct CompressionMiddleware: Middleware {
    public let name = "CompressionMiddleware"
    public let priority = 50

    public init(threshold: Int = 1024, algorithm: Algorithm = .gzip, enableStats: Bool = true, priority: Int = 50) {
        print("⚠️ Compression is not available on this platform")
    }

    public enum Algorithm: Sendable {
        case gzip
        case lz4
        case lzma
        case zlib
    }

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        data
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        data
    }
}

#endif
