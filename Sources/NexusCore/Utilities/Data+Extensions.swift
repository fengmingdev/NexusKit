//
//  Data+Extensions.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
#if canImport(Compression)
import Compression
#endif

// MARK: - Data Extensions

public extension Data {
    // MARK: - Big Endian Integer Appending

    /// 追加大端序 UInt32
    mutating func appendBigEndian(_ value: UInt32) {
        var bigEndian = value.bigEndian
        append(Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size))
    }

    /// 追加大端序 UInt16
    mutating func appendBigEndian(_ value: UInt16) {
        var bigEndian = value.bigEndian
        append(Data(bytes: &bigEndian, count: MemoryLayout<UInt16>.size))
    }

    /// 追加大端序 UInt8
    mutating func appendBigEndian(_ value: UInt8) {
        append(value)
    }

    /// 追加大端序 UInt64
    mutating func appendBigEndian(_ value: UInt64) {
        var bigEndian = value.bigEndian
        append(Data(bytes: &bigEndian, count: MemoryLayout<UInt64>.size))
    }

    // MARK: - Big Endian Integer Reading

    /// 读取大端序整数（泛型版本）
    /// - Parameter offset: 偏移量
    /// - Returns: 读取的值
    /// - Throws: 如果数据不足则抛出错误
    func readBigEndian<T: FixedWidthInteger>(at offset: Int) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= count else {
            throw NexusError.invalidMessageFormat(reason: "Data too short to read \(T.self) at offset \(offset)")
        }

        return try withUnsafeBytes { bufferPtr -> T in
            guard let bytes = bufferPtr.baseAddress?.advanced(by: offset) else {
                throw NexusError.invalidMessageFormat(reason: "Failed to get bytes pointer")
            }
            let value = bytes.loadUnaligned(as: T.self)
            return T(bigEndian: value)
        }
    }

    /// 读取大端序 UInt32
    /// - Parameter offset: 偏移量
    /// - Returns: 读取的值
    func readBigEndianUInt32(at offset: Int) -> UInt32? {
        guard offset + MemoryLayout<UInt32>.size <= count else { return nil }

        return withUnsafeBytes { bufferPtr in
            guard let bytes = bufferPtr.baseAddress?.advanced(by: offset) else { return nil }
            let value = bytes.loadUnaligned(as: UInt32.self)
            return UInt32(bigEndian: value)
        }
    }

    /// 读取大端序 UInt16
    /// - Parameter offset: 偏移量
    /// - Returns: 读取的值
    func readBigEndianUInt16(at offset: Int) -> UInt16? {
        guard offset + MemoryLayout<UInt16>.size <= count else { return nil }

        return withUnsafeBytes { bufferPtr in
            guard let bytes = bufferPtr.baseAddress?.advanced(by: offset) else { return nil }
            let value = bytes.loadUnaligned(as: UInt16.self)
            return UInt16(bigEndian: value)
        }
    }

    /// 读取大端序 UInt8
    /// - Parameter offset: 偏移量
    /// - Returns: 读取的值
    func readBigEndianUInt8(at offset: Int) -> UInt8? {
        guard offset < count else { return nil }
        return self[offset]
    }

    /// 读取大端序 UInt64
    /// - Parameter offset: 偏移量
    /// - Returns: 读取的值
    func readBigEndianUInt64(at offset: Int) -> UInt64? {
        guard offset + MemoryLayout<UInt64>.size <= count else { return nil }

        return withUnsafeBytes { bufferPtr in
            guard let bytes = bufferPtr.baseAddress?.advanced(by: offset) else { return nil }
            let value = bytes.loadUnaligned(as: UInt64.self)
            return UInt64(bigEndian: value)
        }
    }

    // MARK: - Hex String

    /// 转换为十六进制字符串
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// 从十六进制字符串创建 Data
    /// - Parameter hexString: 十六进制字符串
    /// - Throws: 如果字符串格式无效则抛出错误
    init(hexString: String) throws {
        let cleanedString = hexString.replacingOccurrences(of: " ", with: "")
        guard cleanedString.count % 2 == 0 else {
            throw NexusError.invalidMessageFormat(reason: "Hex string must have even length")
        }

        var data = Data(capacity: cleanedString.count / 2)

        var index = cleanedString.startIndex
        while index < cleanedString.endIndex {
            let nextIndex = cleanedString.index(index, offsetBy: 2)
            let byteString = cleanedString[index..<nextIndex]

            guard let byte = UInt8(byteString, radix: 16) else {
                throw NexusError.invalidMessageFormat(reason: "Invalid hex character in string")
            }
            data.append(byte)

            index = nextIndex
        }

        self = data
    }

    // MARK: - Compression (requires Compression framework)

    #if canImport(Compression)
    /// GZIP 压缩
    /// - Returns: 压缩后的数据
    /// - Throws: 压缩失败
    func gzipped() throws -> Data {
        try compressed(using: COMPRESSION_ZLIB)
    }

    /// GZIP 压缩（别名）
    /// - Returns: 压缩后的数据
    /// - Throws: 压缩失败
    func gzipCompressed() throws -> Data {
        try gzipped()
    }

    /// GZIP 解压缩
    /// - Returns: 解压后的数据
    /// - Throws: 解压失败
    func gunzipped() throws -> Data {
        try decompressed(using: COMPRESSION_ZLIB)
    }

    /// GZIP 解压缩（别名）
    /// - Returns: 解压后的数据
    /// - Throws: 解压失败
    func gzipDecompressed() throws -> Data {
        try gunzipped()
    }

    /// 使用指定算法压缩
    private func compressed(using algorithm: compression_algorithm) throws -> Data {
        let bufferSize = count
        var compressedData = Data(count: bufferSize)

        let compressedSize = compressedData.withUnsafeMutableBytes { destBuffer -> Int in
            self.withUnsafeBytes { sourceBuffer -> Int in
                guard let dest = destBuffer.baseAddress,
                      let source = sourceBuffer.baseAddress else {
                    return 0
                }

                return compression_encode_buffer(
                    dest,
                    bufferSize,
                    source,
                    count,
                    nil,
                    algorithm
                )
            }
        }

        guard compressedSize > 0 else {
            throw NexusError.custom(message: "Compression failed", underlyingError: nil)
        }

        compressedData.count = compressedSize
        return compressedData
    }

    /// 使用指定算法解压缩
    private func decompressed(using algorithm: compression_algorithm) throws -> Data {
        let bufferSize = count * 4 // 假设解压后最多4倍大小
        var decompressedData = Data(count: bufferSize)

        let decompressedSize = decompressedData.withUnsafeMutableBytes { destBuffer -> Int in
            self.withUnsafeBytes { sourceBuffer -> Int in
                guard let dest = destBuffer.baseAddress,
                      let source = sourceBuffer.baseAddress else {
                    return 0
                }

                return compression_decode_buffer(
                    dest,
                    bufferSize,
                    source,
                    count,
                    nil,
                    algorithm
                )
            }
        }

        guard decompressedSize > 0 else {
            throw NexusError.custom(message: "Decompression failed", underlyingError: nil)
        }

        decompressedData.count = decompressedSize
        return decompressedData
    }
    #endif

    // MARK: - Safe Subdata

    /// 安全地获取子数据（不会越界）
    /// - Parameter range: 范围
    /// - Returns: 子数据
    func safeSubdata(in range: Range<Int>) -> Data {
        let safeLower = Swift.max(0, range.lowerBound)
        let safeUpper = Swift.min(count, range.upperBound)
        let safeRange = safeLower..<safeUpper
        guard !safeRange.isEmpty else { return Data() }
        return subdata(in: safeRange)
    }

    // MARK: - UTF-8 String

    /// 转换为 UTF-8 字符串
    var utf8String: String? {
        String(data: self, encoding: .utf8)
    }
}

// MARK: - String Extensions for Data

public extension String {
    /// 转换为 UTF-8 Data
    var utf8Data: Data {
        Data(utf8)
    }
}

// MARK: - UInt Extensions for Data

public extension UInt32 {
    /// 转换为大端序 Data
    var bigEndianData: Data {
        var bigEndian = self.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
    }
}

public extension UInt16 {
    /// 转换为大端序 Data
    var bigEndianData: Data {
        var bigEndian = self.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt16>.size)
    }
}

public extension UInt8 {
    /// 转换为 Data
    var data: Data {
        Data([self])
    }
}

public extension UInt64 {
    /// 转换为大端序 Data
    var bigEndianData: Data {
        var bigEndian = self.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt64>.size)
    }
}
