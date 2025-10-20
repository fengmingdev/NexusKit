//
//  CompressionMiddleware.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  压缩中间件实现

import Foundation

// MARK: - Compression Middleware

/// 压缩中间件
///
/// 自动压缩和解压缩传输数据，支持多种压缩算法和自适应策略。
///
/// ## 功能特性
///
/// - 多种压缩算法 (LZ4, Zlib, LZMA)
/// - 自适应压缩策略
/// - 基于数据大小和熵的智能选择
/// - 压缩统计和监控
/// - 双向压缩支持
///
/// ## 使用示例
///
/// ### 基础使用
/// ```swift
/// let compression = CompressionMiddleware()
///
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .middleware(compression)
///     .connect()
/// ```
///
/// ### 自定义配置
/// ```swift
/// let compression = CompressionMiddleware(
///     profile: .highCompression,
///     compressOutgoing: true,
///     decompressIncoming: true
/// )
/// ```
public actor CompressionMiddleware: Middleware {

    // MARK: - Properties

    public let name = "CompressionMiddleware"
    public let priority = 40  // 在加密之前，日志之后

    /// 压缩策略
    private let strategy: AdaptiveCompressionStrategy

    /// 是否压缩出站数据
    public let compressOutgoing: Bool

    /// 是否解压缩入站数据
    public let decompressIncoming: Bool

    /// 压缩头部标记
    private let compressionMarker: UInt8 = 0xFF

    /// 统计信息
    private var stats: Statistics

    private struct Statistics {
        var totalOutgoingBytes: Int64 = 0
        var totalIncomingBytes: Int64 = 0
        var totalCompressedOutgoing: Int64 = 0
        var totalDecompressedIncoming: Int64 = 0
        var compressionCount: Int = 0
        var decompressionCount: Int = 0
        var compressionErrors: Int = 0
        var decompressionErrors: Int = 0
    }

    // MARK: - Initialization

    /// 初始化压缩中间件
    /// - Parameters:
    ///   - profile: 压缩配置文件
    ///   - compressOutgoing: 是否压缩出站数据
    ///   - decompressIncoming: 是否解压缩入站数据
    public init(
        profile: CompressionProfile = .balanced,
        compressOutgoing: Bool = true,
        decompressIncoming: Bool = true
    ) {
        self.strategy = AdaptiveCompressionStrategy(
            strategy: profile.strategy,
            algorithmSelection: profile.algorithmSelection,
            minDataSize: profile.minDataSize,
            minCompressionRatio: profile.minCompressionRatio
        )
        self.compressOutgoing = compressOutgoing
        self.decompressIncoming = decompressIncoming
        self.stats = Statistics()
    }

    /// 使用自定义策略初始化
    /// - Parameters:
    ///   - strategy: 自定义压缩策略
    ///   - compressOutgoing: 是否压缩出站数据
    ///   - decompressIncoming: 是否解压缩入站数据
    public init(
        strategy: AdaptiveCompressionStrategy,
        compressOutgoing: Bool = true,
        decompressIncoming: Bool = true
    ) {
        self.strategy = strategy
        self.compressOutgoing = compressOutgoing
        self.decompressIncoming = decompressIncoming
        self.stats = Statistics()
    }

    // MARK: - Middleware Protocol

    public func handleOutgoing(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard compressOutgoing else { return data }

        stats.totalOutgoingBytes += Int64(data.count)

        // 决定是否压缩
        let shouldCompress = await strategy.shouldCompress(data)
        guard shouldCompress else {
            await logDebug("跳过压缩: 数据大小=\(data.count), 不满足压缩条件")
            return data
        }

        // 选择算法
        let algorithm = await strategy.selectAlgorithm(for: data)

        do {
            let startTime = Date()
            let compressed = try algorithm.compress(data)
            let compressionTime = Date().timeIntervalSince(startTime)

            // 检查压缩是否有效（压缩后更小）
            guard compressed.count < data.count else {
                await logDebug("压缩无效: 原始=\(data.count), 压缩后=\(compressed.count)")
                return data
            }

            // 添加压缩头部（标记 + 算法名）
            var result = Data()
            result.append(compressionMarker)
            let algorithmName = algorithm.name.data(using: .utf8) ?? Data()
            result.append(UInt8(algorithmName.count))
            result.append(algorithmName)
            result.append(compressed)

            // 更新统计
            stats.totalCompressedOutgoing += Int64(result.count)
            stats.compressionCount += 1

            // 记录压缩统计
            let compressionStats = CompressionStatistics(
                originalSize: data.count,
                compressedSize: compressed.count,
                compressionTime: compressionTime
            )
            await strategy.recordStatistics(compressionStats, algorithm: algorithm.name)

            await logDebug(
                "压缩成功: \(algorithm.name), 原始=\(data.count), 压缩后=\(result.count), 节省=\(compressionStats.savedPercentage)%"
            )

            return result

        } catch {
            stats.compressionErrors += 1
            await logError("压缩失败: \(error)")
            return data  // 失败时返回原始数据
        }
    }

    public func handleIncoming(_ data: Data, context: MiddlewareContext) async throws -> Data {
        guard decompressIncoming else { return data }

        stats.totalIncomingBytes += Int64(data.count)

        // 检查是否为压缩数据
        guard data.count > 2, data[0] == compressionMarker else {
            return data  // 未压缩数据
        }

        do {
            // 解析头部
            let algorithmNameLength = Int(data[1])
            guard data.count > 2 + algorithmNameLength else {
                throw CompressionError.decompressionFailed("Invalid compression header")
            }

            let algorithmNameData = data[2..<(2 + algorithmNameLength)]
            guard let algorithmName = String(data: algorithmNameData, encoding: .utf8) else {
                throw CompressionError.decompressionFailed("Invalid algorithm name")
            }

            // 获取算法
            guard let algorithm = await strategy.getAlgorithm(name: algorithmName) else {
                throw CompressionError.unsupportedAlgorithm(algorithmName)
            }

            // 提取压缩数据
            let compressedData = data[(2 + algorithmNameLength)...]

            // 解压缩
            let startTime = Date()
            let decompressed = try algorithm.decompress(Data(compressedData))
            let decompressionTime = Date().timeIntervalSince(startTime)

            // 更新统计
            stats.totalDecompressedIncoming += Int64(decompressed.count)
            stats.decompressionCount += 1

            await logDebug(
                "解压缩成功: \(algorithmName), 压缩=\(compressedData.count), 解压缩后=\(decompressed.count), 时间=\(decompressionTime)s"
            )

            return decompressed

        } catch {
            stats.decompressionErrors += 1
            await logError("解压缩失败: \(error)")
            throw error
        }
    }

    // MARK: - Statistics

    /// 获取统计信息
    public func getStatistics() -> CompressionMiddlewareStatistics {
        CompressionMiddlewareStatistics(
            totalOutgoingBytes: stats.totalOutgoingBytes,
            totalIncomingBytes: stats.totalIncomingBytes,
            totalCompressedOutgoing: stats.totalCompressedOutgoing,
            totalDecompressedIncoming: stats.totalDecompressedIncoming,
            compressionCount: stats.compressionCount,
            decompressionCount: stats.decompressionCount,
            compressionErrors: stats.compressionErrors,
            decompressionErrors: stats.decompressionErrors
        )
    }

    /// 获取压缩历史统计
    public func getHistoryStatistics() async -> CompressionHistorySummary {
        await strategy.getStatistics()
    }

    /// 重置统计
    public func resetStatistics() async {
        stats = Statistics()
        await strategy.resetStatistics()
    }
}

// MARK: - Compression Middleware Statistics

/// 压缩中间件统计信息
public struct CompressionMiddlewareStatistics: Sendable {
    /// 总出站字节数（压缩前）
    public let totalOutgoingBytes: Int64

    /// 总入站字节数（压缩后）
    public let totalIncomingBytes: Int64

    /// 总压缩后出站字节数
    public let totalCompressedOutgoing: Int64

    /// 总解压缩后入站字节数
    public let totalDecompressedIncoming: Int64

    /// 压缩次数
    public let compressionCount: Int

    /// 解压缩次数
    public let decompressionCount: Int

    /// 压缩错误次数
    public let compressionErrors: Int

    /// 解压缩错误次数
    public let decompressionErrors: Int

    /// 平均出站压缩率
    public var averageOutgoingCompressionRatio: Double {
        guard totalOutgoingBytes > 0 else { return 1.0 }
        return Double(totalCompressedOutgoing) / Double(totalOutgoingBytes)
    }

    /// 出站节省的字节数
    public var outgoingSavedBytes: Int64 {
        totalOutgoingBytes - totalCompressedOutgoing
    }

    /// 出站节省的百分比
    public var outgoingSavedPercentage: Double {
        (1.0 - averageOutgoingCompressionRatio) * 100.0
    }

    public init(
        totalOutgoingBytes: Int64,
        totalIncomingBytes: Int64,
        totalCompressedOutgoing: Int64,
        totalDecompressedIncoming: Int64,
        compressionCount: Int,
        decompressionCount: Int,
        compressionErrors: Int,
        decompressionErrors: Int
    ) {
        self.totalOutgoingBytes = totalOutgoingBytes
        self.totalIncomingBytes = totalIncomingBytes
        self.totalCompressedOutgoing = totalCompressedOutgoing
        self.totalDecompressedIncoming = totalDecompressedIncoming
        self.compressionCount = compressionCount
        self.decompressionCount = decompressionCount
        self.compressionErrors = compressionErrors
        self.decompressionErrors = decompressionErrors
    }
}

// MARK: - Convenience Initializers

extension CompressionMiddleware {

    /// 创建高速压缩中间件
    public static func highSpeed() -> CompressionMiddleware {
        CompressionMiddleware(profile: .highSpeed)
    }

    /// 创建平衡压缩中间件
    public static func balanced() -> CompressionMiddleware {
        CompressionMiddleware(profile: .balanced)
    }

    /// 创建高压缩率中间件
    public static func highCompression() -> CompressionMiddleware {
        CompressionMiddleware(profile: .highCompression)
    }

    /// 创建禁用压缩的中间件
    public static func disabled() -> CompressionMiddleware {
        CompressionMiddleware(profile: .disabled)
    }
}
