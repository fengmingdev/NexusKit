//
//  AdaptiveCompression.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  自适应压缩策略

import Foundation

// MARK: - Adaptive Compression Strategy

/// 自适应压缩策略
public actor AdaptiveCompressionStrategy {

    /// 压缩策略类型
    public enum Strategy: Sendable {
        /// 始终压缩
        case always

        /// 从不压缩
        case never

        /// 自动选择（基于数据大小和类型）
        case auto

        /// 基于阈值
        case threshold(minSize: Int, minCompressionRatio: Double)

        /// 自定义策略
        case custom(@Sendable (Data) async -> Bool)
    }

    /// 压缩算法选择策略
    public enum AlgorithmSelection: Sendable {
        /// 固定算法
        case fixed(String)

        /// 基于数据大小
        case sizeBased

        /// 最快速度
        case fastestForSize

        /// 最佳压缩率
        case bestCompression

        /// 平衡速度和压缩率
        case balanced
    }

    // MARK: - Properties

    /// 压缩策略
    public let strategy: Strategy

    /// 算法选择策略
    public let algorithmSelection: AlgorithmSelection

    /// 最小数据大小（字节）
    public let minDataSize: Int

    /// 最小压缩率阈值
    public let minCompressionRatio: Double

    /// 可用的压缩算法
    private var algorithms: [String: any CompressionAlgorithm]

    /// 历史统计
    private var statistics: CompressionHistory

    // MARK: - Initialization

    public init(
        strategy: Strategy = .auto,
        algorithmSelection: AlgorithmSelection = .balanced,
        minDataSize: Int = 1024,
        minCompressionRatio: Double = 0.8
    ) {
        self.strategy = strategy
        self.algorithmSelection = algorithmSelection
        self.minDataSize = minDataSize
        self.minCompressionRatio = minCompressionRatio

        // 初始化默认算法
        self.algorithms = [
            "lz4": LZ4Compression(),
            "zlib": ZlibCompression(level: 6),
            "lzma": LZMACompression(),
            "none": NoCompression()
        ]

        self.statistics = CompressionHistory()
    }

    // MARK: - Algorithm Management

    /// 注册压缩算法
    public func registerAlgorithm(_ algorithm: any CompressionAlgorithm) {
        algorithms[algorithm.name] = algorithm
    }

    /// 获取压缩算法
    public func getAlgorithm(name: String) -> (any CompressionAlgorithm)? {
        algorithms[name]
    }

    // MARK: - Decision Making

    /// 决定是否应该压缩数据
    public func shouldCompress(_ data: Data) async -> Bool {
        switch strategy {
        case .always:
            return true

        case .never:
            return false

        case .auto:
            return await autoDecision(data)

        case .threshold(let minSize, let minRatio):
            guard data.count >= minSize else { return false }

            let algorithm = await selectAlgorithm(for: data)
            let estimatedRatio = algorithm.estimateCompressionRatio(for: data)
            return estimatedRatio <= minRatio

        case .custom(let predicate):
            return await predicate(data)
        }
    }

    /// 选择最佳压缩算法
    public func selectAlgorithm(for data: Data) async -> any CompressionAlgorithm {
        switch algorithmSelection {
        case .fixed(let name):
            return algorithms[name] ?? NoCompression()

        case .sizeBased:
            return selectBySizeAndPattern(data)

        case .fastestForSize:
            return selectFastestForSize(data)

        case .bestCompression:
            return algorithms["lzma"] ?? ZlibCompression()

        case .balanced:
            return selectBalanced(data)
        }
    }

    /// 自动决策是否压缩
    private func autoDecision(_ data: Data) async -> Bool {
        // 数据太小，不值得压缩
        guard data.count >= minDataSize else { return false }

        // 检查数据熵
        let entropy = calculateDataEntropy(data)

        // 高熵数据（接近随机）通常不可压缩
        if entropy > 7.5 {
            return false
        }

        // 估计压缩效果
        let algorithm = await selectAlgorithm(for: data)
        let estimatedRatio = algorithm.estimateCompressionRatio(for: data)

        return estimatedRatio <= minCompressionRatio
    }

    /// 基于数据大小和模式选择算法
    private func selectBySizeAndPattern(_ data: Data) -> any CompressionAlgorithm {
        let size = data.count
        let entropy = calculateDataEntropy(data)

        // 小数据使用快速算法
        if size < 4 * 1024 {
            return algorithms["lz4"] ?? LZ4Compression()
        }

        // 大数据且低熵（高可压缩性）使用 LZMA
        if size > 100 * 1024 && entropy < 5.0 {
            return algorithms["lzma"] ?? LZMACompression()
        }

        // 默认使用 Zlib（平衡）
        return algorithms["zlib"] ?? ZlibCompression()
    }

    /// 选择最快的算法
    private func selectFastestForSize(_ data: Data) -> any CompressionAlgorithm {
        let size = data.count

        // 小数据：LZ4 最快
        if size < 10 * 1024 {
            return algorithms["lz4"] ?? LZ4Compression()
        }

        // 中等数据：Zlib
        if size < 100 * 1024 {
            return algorithms["zlib"] ?? ZlibCompression()
        }

        // 大数据：LZ4（速度优先）
        return algorithms["lz4"] ?? LZ4Compression()
    }

    /// 选择平衡的算法
    private func selectBalanced(_ data: Data) -> any CompressionAlgorithm {
        let size = data.count
        let entropy = calculateDataEntropy(data)

        // 根据历史统计选择
        if let bestAlgorithm = statistics.getBestAlgorithm(for: size) {
            return algorithms[bestAlgorithm] ?? ZlibCompression()
        }

        // 高熵数据：使用快速算法或不压缩
        if entropy > 7.0 {
            return algorithms["lz4"] ?? LZ4Compression()
        }

        // 中等熵：Zlib
        if entropy > 5.0 {
            return algorithms["zlib"] ?? ZlibCompression()
        }

        // 低熵：LZMA（最高压缩率）
        return algorithms["lzma"] ?? LZMACompression()
    }

    // MARK: - Statistics

    /// 记录压缩统计
    public func recordStatistics(_ stats: CompressionStatistics, algorithm: String) {
        statistics.record(stats, algorithm: algorithm)
    }

    /// 获取历史统计
    public func getStatistics() -> CompressionHistorySummary {
        statistics.getSummary()
    }

    /// 重置统计
    public func resetStatistics() {
        statistics.reset()
    }
}

// MARK: - Compression History

/// 压缩历史记录
private struct CompressionHistory {

    /// 历史记录条目
    struct Entry {
        let timestamp: Date
        let originalSize: Int
        let compressedSize: Int
        let algorithm: String
        let compressionTime: TimeInterval
    }

    private var entries: [Entry] = []
    private var algorithmStats: [String: AlgorithmStats] = [:]

    /// 算法统计
    struct AlgorithmStats {
        var totalCompressions: Int = 0
        var totalOriginalSize: Int64 = 0
        var totalCompressedSize: Int64 = 0
        var totalTime: TimeInterval = 0

        var averageCompressionRatio: Double {
            guard totalOriginalSize > 0 else { return 1.0 }
            return Double(totalCompressedSize) / Double(totalOriginalSize)
        }

        var averageSpeed: Double {
            guard totalTime > 0 else { return 0.0 }
            return Double(totalOriginalSize) / totalTime / 1_048_576.0  // MB/s
        }
    }

    /// 记录统计
    mutating func record(_ stats: CompressionStatistics, algorithm: String) {
        let entry = Entry(
            timestamp: Date(),
            originalSize: stats.originalSize,
            compressedSize: stats.compressedSize,
            algorithm: algorithm,
            compressionTime: stats.compressionTime
        )

        entries.append(entry)

        // 限制历史记录数量
        if entries.count > 1000 {
            entries.removeFirst(entries.count - 1000)
        }

        // 更新算法统计
        var algorithmStat = algorithmStats[algorithm] ?? AlgorithmStats()
        algorithmStat.totalCompressions += 1
        algorithmStat.totalOriginalSize += Int64(stats.originalSize)
        algorithmStat.totalCompressedSize += Int64(stats.compressedSize)
        algorithmStat.totalTime += stats.compressionTime
        algorithmStats[algorithm] = algorithmStat
    }

    /// 获取最佳算法
    func getBestAlgorithm(for dataSize: Int) -> String? {
        // 基于历史数据选择表现最好的算法
        guard !algorithmStats.isEmpty else { return nil }

        // 对于相似大小的数据，选择压缩率最好的算法
        let bestAlgorithm = algorithmStats.min { a, b in
            a.value.averageCompressionRatio < b.value.averageCompressionRatio
        }

        return bestAlgorithm?.key
    }

    /// 获取摘要
    func getSummary() -> CompressionHistorySummary {
        CompressionHistorySummary(
            totalCompressions: entries.count,
            algorithmStats: algorithmStats.mapValues { stats in
                AlgorithmSummary(
                    compressions: stats.totalCompressions,
                    averageRatio: stats.averageCompressionRatio,
                    averageSpeed: stats.averageSpeed
                )
            }
        )
    }

    /// 重置统计
    mutating func reset() {
        entries.removeAll()
        algorithmStats.removeAll()
    }
}

// MARK: - Compression History Summary

/// 压缩历史摘要
public struct CompressionHistorySummary: Sendable {
    /// 总压缩次数
    public let totalCompressions: Int

    /// 各算法统计
    public let algorithmStats: [String: AlgorithmSummary]
}

/// 算法摘要
public struct AlgorithmSummary: Sendable {
    /// 压缩次数
    public let compressions: Int

    /// 平均压缩率
    public let averageRatio: Double

    /// 平均速度 (MB/s)
    public let averageSpeed: Double
}

// MARK: - Helper Functions

/// 计算数据熵
private func calculateDataEntropy(_ data: Data) -> Double {
    guard !data.isEmpty else { return 0.0 }

    var frequencies = [UInt8: Int]()
    for byte in data {
        frequencies[byte, default: 0] += 1
    }

    let dataCount = Double(data.count)
    var entropy = 0.0

    for count in frequencies.values {
        let probability = Double(count) / dataCount
        entropy -= probability * log2(probability)
    }

    return entropy
}

// MARK: - Compression Profile

/// 压缩配置文件
public struct CompressionProfile: Sendable {

    /// 预定义配置
    public static let highSpeed = CompressionProfile(
        strategy: .threshold(minSize: 2048, minCompressionRatio: 0.9),
        algorithmSelection: .fastestForSize
    )

    public static let balanced = CompressionProfile(
        strategy: .auto,
        algorithmSelection: .balanced
    )

    public static let highCompression = CompressionProfile(
        strategy: .threshold(minSize: 512, minCompressionRatio: 0.95),
        algorithmSelection: .bestCompression
    )

    public static let disabled = CompressionProfile(
        strategy: .never,
        algorithmSelection: .fixed("none")
    )

    public let strategy: AdaptiveCompressionStrategy.Strategy
    public let algorithmSelection: AdaptiveCompressionStrategy.AlgorithmSelection
    public let minDataSize: Int
    public let minCompressionRatio: Double

    public init(
        strategy: AdaptiveCompressionStrategy.Strategy,
        algorithmSelection: AdaptiveCompressionStrategy.AlgorithmSelection,
        minDataSize: Int = 1024,
        minCompressionRatio: Double = 0.8
    ) {
        self.strategy = strategy
        self.algorithmSelection = algorithmSelection
        self.minDataSize = minDataSize
        self.minCompressionRatio = minCompressionRatio
    }
}
