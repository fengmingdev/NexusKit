//
//  CompressionAlgorithm.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//
//  压缩算法实现

import Foundation
import Compression

// MARK: - Compression Algorithm

/// 压缩算法协议
public protocol CompressionAlgorithm: Sendable {
    /// 算法名称
    var name: String { get }

    /// 压缩数据
    func compress(_ data: Data) throws -> Data

    /// 解压缩数据
    func decompress(_ data: Data) throws -> Data

    /// 估计压缩率
    func estimateCompressionRatio(for data: Data) -> Double
}

// MARK: - Compression Error

/// 压缩错误
public enum CompressionError: Error, Sendable {
    /// 压缩失败
    case compressionFailed(String)

    /// 解压缩失败
    case decompressionFailed(String)

    /// 不支持的算法
    case unsupportedAlgorithm(String)

    /// 数据过小（不值得压缩）
    case dataTooSmall(Int)

    /// 压缩后数据更大
    case compressionIneffective(original: Int, compressed: Int)
}

// MARK: - Zlib Compression

/// Zlib 压缩算法
public struct ZlibCompression: CompressionAlgorithm {
    public let name = "zlib"

    /// 压缩级别 (0-9)
    public let level: Int

    public init(level: Int = 6) {
        self.level = max(0, min(9, level))
    }

    public func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        let bufferSize = max(data.count, 32 * 1024)
        var compressedData = Data(count: bufferSize)

        let result = data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Int in
            compressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                guard let sourceAddress = sourcePtr.baseAddress,
                      let destAddress = destPtr.baseAddress else {
                    return 0
                }

                return compression_encode_buffer(
                    destAddress,
                    bufferSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else {
            throw CompressionError.compressionFailed("Zlib compression failed")
        }

        compressedData.count = result
        return compressedData
    }

    public func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        // 估计解压缩后的大小（假设压缩率为 50%）
        let bufferSize = max(data.count * 4, 32 * 1024)
        var decompressedData = Data(count: bufferSize)

        let result = data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Int in
            decompressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                guard let sourceAddress = sourcePtr.baseAddress,
                      let destAddress = destPtr.baseAddress else {
                    return 0
                }

                return compression_decode_buffer(
                    destAddress,
                    bufferSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else {
            throw CompressionError.decompressionFailed("Zlib decompression failed")
        }

        decompressedData.count = result
        return decompressedData
    }

    public func estimateCompressionRatio(for data: Data) -> Double {
        // 文本数据通常有更好的压缩率
        let entropy = calculateEntropy(data)

        // 熵越低，压缩率越高
        // 熵范围: 0.0 (完全重复) - 8.0 (完全随机)
        let compressionRatio = 1.0 - (entropy / 8.0) * 0.7
        return max(0.1, min(0.9, compressionRatio))
    }
}

// MARK: - LZ4 Compression

/// LZ4 压缩算法（快速压缩）
public struct LZ4Compression: CompressionAlgorithm {
    public let name = "lz4"

    public init() {}

    public func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        let bufferSize = max(data.count, 32 * 1024)
        var compressedData = Data(count: bufferSize)

        let result = data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Int in
            compressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                guard let sourceAddress = sourcePtr.baseAddress,
                      let destAddress = destPtr.baseAddress else {
                    return 0
                }

                return compression_encode_buffer(
                    destAddress,
                    bufferSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_LZ4
                )
            }
        }

        guard result > 0 else {
            throw CompressionError.compressionFailed("LZ4 compression failed")
        }

        compressedData.count = result
        return compressedData
    }

    public func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        let bufferSize = max(data.count * 4, 32 * 1024)
        var decompressedData = Data(count: bufferSize)

        let result = data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Int in
            decompressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                guard let sourceAddress = sourcePtr.baseAddress,
                      let destAddress = destPtr.baseAddress else {
                    return 0
                }

                return compression_decode_buffer(
                    destAddress,
                    bufferSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_LZ4
                )
            }
        }

        guard result > 0 else {
            throw CompressionError.decompressionFailed("LZ4 decompression failed")
        }

        decompressedData.count = result
        return decompressedData
    }

    public func estimateCompressionRatio(for data: Data) -> Double {
        // LZ4 压缩率通常低于 Zlib，但速度更快
        let entropy = calculateEntropy(data)
        let compressionRatio = 1.0 - (entropy / 8.0) * 0.5
        return max(0.2, min(0.8, compressionRatio))
    }
}

// MARK: - LZMA Compression

/// LZMA 压缩算法（高压缩率）
public struct LZMACompression: CompressionAlgorithm {
    public let name = "lzma"

    public init() {}

    public func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        let bufferSize = max(data.count, 32 * 1024)
        var compressedData = Data(count: bufferSize)

        let result = data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Int in
            compressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                guard let sourceAddress = sourcePtr.baseAddress,
                      let destAddress = destPtr.baseAddress else {
                    return 0
                }

                return compression_encode_buffer(
                    destAddress,
                    bufferSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_LZMA
                )
            }
        }

        guard result > 0 else {
            throw CompressionError.compressionFailed("LZMA compression failed")
        }

        compressedData.count = result
        return compressedData
    }

    public func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        let bufferSize = max(data.count * 4, 32 * 1024)
        var decompressedData = Data(count: bufferSize)

        let result = data.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Int in
            decompressedData.withUnsafeMutableBytes { (destPtr: UnsafeMutableRawBufferPointer) -> Int in
                guard let sourceAddress = sourcePtr.baseAddress,
                      let destAddress = destPtr.baseAddress else {
                    return 0
                }

                return compression_decode_buffer(
                    destAddress,
                    bufferSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_LZMA
                )
            }
        }

        guard result > 0 else {
            throw CompressionError.decompressionFailed("LZMA decompression failed")
        }

        decompressedData.count = result
        return decompressedData
    }

    public func estimateCompressionRatio(for data: Data) -> Double {
        // LZMA 通常有最高的压缩率
        let entropy = calculateEntropy(data)
        let compressionRatio = 1.0 - (entropy / 8.0) * 0.8
        return max(0.1, min(0.9, compressionRatio))
    }
}

// MARK: - No Compression

/// 无压缩（直通）
public struct NoCompression: CompressionAlgorithm {
    public let name = "none"

    public init() {}

    public func compress(_ data: Data) throws -> Data {
        return data
    }

    public func decompress(_ data: Data) throws -> Data {
        return data
    }

    public func estimateCompressionRatio(for data: Data) -> Double {
        return 1.0  // 无压缩
    }
}

// MARK: - Helper Functions

/// 计算数据熵（信息熵）
private func calculateEntropy(_ data: Data) -> Double {
    guard !data.isEmpty else { return 0.0 }

    // 统计字节频率
    var frequencies = [UInt8: Int]()
    for byte in data {
        frequencies[byte, default: 0] += 1
    }

    // 计算熵
    let dataCount = Double(data.count)
    var entropy = 0.0

    for count in frequencies.values {
        let probability = Double(count) / dataCount
        entropy -= probability * log2(probability)
    }

    return entropy
}

// MARK: - Compression Statistics

/// 压缩统计信息
public struct CompressionStatistics: Sendable {
    /// 原始数据大小
    public let originalSize: Int

    /// 压缩后大小
    public let compressedSize: Int

    /// 压缩率 (0.0 - 1.0)
    public var compressionRatio: Double {
        guard originalSize > 0 else { return 0.0 }
        return Double(compressedSize) / Double(originalSize)
    }

    /// 节省的字节数
    public var savedBytes: Int {
        originalSize - compressedSize
    }

    /// 节省的百分比
    public var savedPercentage: Double {
        (1.0 - compressionRatio) * 100.0
    }

    /// 压缩时间（秒）
    public let compressionTime: TimeInterval

    /// 解压缩时间（秒）
    public var decompressionTime: TimeInterval?

    /// 压缩速度（MB/s）
    public var compressionSpeed: Double {
        guard compressionTime > 0 else { return 0.0 }
        return Double(originalSize) / compressionTime / 1_048_576.0
    }

    public init(
        originalSize: Int,
        compressedSize: Int,
        compressionTime: TimeInterval,
        decompressionTime: TimeInterval? = nil
    ) {
        self.originalSize = originalSize
        self.compressedSize = compressedSize
        self.compressionTime = compressionTime
        self.decompressionTime = decompressionTime
    }
}

// MARK: - Compression Benchmark

/// 压缩性能基准测试
public struct CompressionBenchmark {

    /// 测试数据类型
    public enum DataType: Sendable {
        case text           // 文本数据
        case json           // JSON 数据
        case binary         // 二进制数据
        case random         // 随机数据
    }

    /// 基准测试单个算法
    public static func benchmark(
        algorithm: any CompressionAlgorithm,
        dataSize: Int,
        dataType: DataType = .text
    ) throws -> CompressionStatistics {
        let testData = generateTestData(size: dataSize, type: dataType)

        // 压缩测试
        let compressStart = Date()
        let compressed = try algorithm.compress(testData)
        let compressTime = Date().timeIntervalSince(compressStart)

        // 解压缩测试
        let decompressStart = Date()
        _ = try algorithm.decompress(compressed)
        let decompressTime = Date().timeIntervalSince(decompressStart)

        return CompressionStatistics(
            originalSize: testData.count,
            compressedSize: compressed.count,
            compressionTime: compressTime,
            decompressionTime: decompressTime
        )
    }

    /// 生成测试数据
    private static func generateTestData(size: Int, type: DataType) -> Data {
        var data = Data(capacity: size)

        switch type {
        case .text:
            // 重复文本模式（高可压缩性）
            let pattern = "The quick brown fox jumps over the lazy dog. "
            let patternData = pattern.data(using: .utf8)!
            while data.count < size {
                data.append(patternData)
            }

        case .json:
            // JSON 格式数据
            let jsonPattern = "{\"name\":\"user\",\"age\":25,\"email\":\"user@example.com\"}"
            let patternData = jsonPattern.data(using: .utf8)!
            while data.count < size {
                data.append(patternData)
            }

        case .binary:
            // 低熵二进制数据
            for _ in 0..<size {
                data.append(UInt8(Int.random(in: 0...16)))
            }

        case .random:
            // 高熵随机数据（低可压缩性）
            for _ in 0..<size {
                data.append(UInt8.random(in: 0...255))
            }
        }

        if data.count > size {
            data = data.prefix(size)
        }

        return data
    }
}
