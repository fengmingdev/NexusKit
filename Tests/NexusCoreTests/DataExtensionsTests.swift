//
//  DataExtensionsTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore

/// Data 扩展测试
final class DataExtensionsTests: XCTestCase {

    // MARK: - Big-Endian Integer Tests

    func testAppendUInt8() {
        var data = Data()
        data.appendBigEndian(UInt8(0x42))

        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0], 0x42)
    }

    func testAppendUInt16() {
        var data = Data()
        data.appendBigEndian(UInt16(0x1234))

        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0], 0x12)
        XCTAssertEqual(data[1], 0x34)
    }

    func testAppendUInt32() {
        var data = Data()
        data.appendBigEndian(UInt32(0x12345678))

        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(data[0], 0x12)
        XCTAssertEqual(data[1], 0x34)
        XCTAssertEqual(data[2], 0x56)
        XCTAssertEqual(data[3], 0x78)
    }

    func testAppendUInt64() {
        var data = Data()
        data.appendBigEndian(UInt64(0x123456789ABCDEF0))

        XCTAssertEqual(data.count, 8)
        XCTAssertEqual(data[0], 0x12)
        XCTAssertEqual(data[1], 0x34)
        XCTAssertEqual(data[2], 0x56)
        XCTAssertEqual(data[3], 0x78)
        XCTAssertEqual(data[4], 0x9A)
        XCTAssertEqual(data[5], 0xBC)
        XCTAssertEqual(data[6], 0xDE)
        XCTAssertEqual(data[7], 0xF0)
    }

    func testReadUInt8() throws {
        let data = Data([0x42])
        let value: UInt8 = try data.readBigEndian(at: 0)

        XCTAssertEqual(value, 0x42)
    }

    func testReadUInt16() throws {
        let data = Data([0x12, 0x34])
        let value: UInt16 = try data.readBigEndian(at: 0)

        XCTAssertEqual(value, 0x1234)
    }

    func testReadUInt32() throws {
        let data = Data([0x12, 0x34, 0x56, 0x78])
        let value: UInt32 = try data.readBigEndian(at: 0)

        XCTAssertEqual(value, 0x12345678)
    }

    func testReadUInt64() throws {
        let data = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
        let value: UInt64 = try data.readBigEndian(at: 0)

        XCTAssertEqual(value, 0x123456789ABCDEF0)
    }

    func testReadAtOffset() throws {
        let data = Data([0xFF, 0xFF, 0x12, 0x34, 0xFF, 0xFF])
        let value: UInt16 = try data.readBigEndian(at: 2)

        XCTAssertEqual(value, 0x1234)
    }

    func testReadOutOfBounds() {
        let data = Data([0x12, 0x34])

        XCTAssertThrowsError(try data.readBigEndian(at: 2) as UInt16) { error in
            guard case NexusError.invalidMessageFormat = error else {
                XCTFail("Expected invalidMessageFormat error")
                return
            }
        }
    }

    func testRoundTrip() throws {
        var data = Data()
        let original: UInt32 = 0xDEADBEEF

        data.appendBigEndian(original)
        let decoded: UInt32 = try data.readBigEndian(at: 0)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Hex String Tests

    func testToHexString() {
        let data = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
        let hex = data.hexString

        XCTAssertEqual(hex, "0123456789abcdef")
    }

    func testEmptyDataToHex() {
        let data = Data()
        let hex = data.hexString

        XCTAssertEqual(hex, "")
    }

    func testSingleByteToHex() {
        let data = Data([0xFF])
        let hex = data.hexString

        XCTAssertEqual(hex, "ff")
    }

    func testFromHexString() throws {
        let hex = "0123456789abcdef"
        let data = try Data(hexString: hex)

        XCTAssertEqual(data, Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]))
    }

    func testFromHexStringUppercase() throws {
        let hex = "DEADBEEF"
        let data = try Data(hexString: hex)

        XCTAssertEqual(data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testFromHexStringMixedCase() throws {
        let hex = "DeAdBeEf"
        let data = try Data(hexString: hex)

        XCTAssertEqual(data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testFromInvalidHexString() {
        let invalidHex = "GHIJKL"

        XCTAssertThrowsError(try Data(hexString: invalidHex)) { error in
            guard case NexusError.invalidMessageFormat = error else {
                XCTFail("Expected invalidMessageFormat error")
                return
            }
        }
    }

    func testFromOddLengthHexString() {
        let oddHex = "123"

        XCTAssertThrowsError(try Data(hexString: oddHex)) { error in
            guard case NexusError.invalidMessageFormat = error else {
                XCTFail("Expected invalidMessageFormat error")
                return
            }
        }
    }

    func testHexRoundTrip() throws {
        let original = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
        let hex = original.hexString
        let decoded = try Data(hexString: hex)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - GZIP Compression Tests

    func testGZipCompression() throws {
        let original = "Hello, World! This is a test string for GZIP compression.".data(using: .utf8)!
        let compressed = try original.gzipCompressed()

        // 压缩后的数据应该不同
        XCTAssertNotEqual(compressed, original)

        // 压缩后的数据应该以 GZIP 魔数开头 (0x1f 0x8b)
        XCTAssertEqual(compressed[0], 0x1f)
        XCTAssertEqual(compressed[1], 0x8b)
    }

    func testGZipDecompression() throws {
        let original = "Hello, World! This is a test string for GZIP compression.".data(using: .utf8)!
        let compressed = try original.gzipCompressed()
        let decompressed = try compressed.gzipDecompressed()

        XCTAssertEqual(decompressed, original)
    }

    func testGZipCompressionRatio() throws {
        // 重复的数据应该有很好的压缩率
        let original = String(repeating: "A", count: 1000).data(using: .utf8)!
        let compressed = try original.gzipCompressed()

        // 压缩后应该显著小于原始数据
        XCTAssertLessThan(compressed.count, original.count / 10)
    }

    func testGZipEmptyData() throws {
        let empty = Data()
        let compressed = try empty.gzipCompressed()
        let decompressed = try compressed.gzipDecompressed()

        XCTAssertEqual(decompressed, empty)
    }

    func testGZipLargeData() throws {
        // 测试大数据压缩
        let original = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 1000).data(using: .utf8)!
        let compressed = try original.gzipCompressed()
        let decompressed = try compressed.gzipDecompressed()

        XCTAssertEqual(decompressed, original)
        XCTAssertLessThan(compressed.count, original.count)
    }

    func testGZipInvalidData() {
        let invalid = Data([0x00, 0x01, 0x02, 0x03])

        XCTAssertThrowsError(try invalid.gzipDecompressed()) { error in
            // 应该抛出解压错误
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Safe Subdata Tests

    func testSafeSubdata() {
        let data = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])
        let subdata = data.safeSubdata(in: 2..<5)

        XCTAssertEqual(subdata, Data([0x02, 0x03, 0x04]))
    }

    func testSafeSubdataFullRange() {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        let subdata = data.safeSubdata(in: 0..<4)

        XCTAssertEqual(subdata, data)
    }

    func testSafeSubdataEmptyRange() {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        let subdata = data.safeSubdata(in: 2..<2)

        XCTAssertEqual(subdata, Data())
    }

    func testSafeSubdataOutOfBounds() {
        let data = Data([0x00, 0x01, 0x02, 0x03])

        // 开始位置超出范围
        let subdata1 = data.safeSubdata(in: 10..<15)
        XCTAssertEqual(subdata1, Data())

        // 结束位置超出范围（应该被截断）
        let subdata2 = data.safeSubdata(in: 2..<10)
        XCTAssertEqual(subdata2, Data([0x02, 0x03]))
    }

    func testSafeSubdataInvalidRange() {
        let data = Data([0x00, 0x01, 0x02, 0x03])

        // 开始位置大于结束位置
        let subdata = data.safeSubdata(in: 3..<1)
        XCTAssertEqual(subdata, Data())
    }

    func testSafeSubdataEmptyData() {
        let data = Data()
        let subdata = data.safeSubdata(in: 0..<5)

        XCTAssertEqual(subdata, Data())
    }

    // MARK: - Combined Operations Tests

    func testCombinedOperations() throws {
        var data = Data()

        // 添加多个整数
        data.appendBigEndian(UInt32(0x12345678))
        data.appendBigEndian(UInt16(0xABCD))
        data.appendBigEndian(UInt8(0xEF))

        // 读取它们
        let value1: UInt32 = try data.readBigEndian(at: 0)
        let value2: UInt16 = try data.readBigEndian(at: 4)
        let value3: UInt8 = try data.readBigEndian(at: 6)

        XCTAssertEqual(value1, 0x12345678)
        XCTAssertEqual(value2, 0xABCD)
        XCTAssertEqual(value3, 0xEF)

        // 转换为十六进制
        let hex = data.hexString
        XCTAssertEqual(hex, "12345678abcdef")
    }

    func testCompressionWithIntegers() throws {
        var data = Data()

        // 添加重复的数据
        for _ in 0..<100 {
            data.appendBigEndian(UInt32(0xDEADBEEF))
        }

        let compressed = try data.gzipCompressed()

        // 应该有很好的压缩率
        XCTAssertLessThan(compressed.count, data.count / 10)

        // 解压缩验证
        let decompressed = try compressed.gzipDecompressed()
        XCTAssertEqual(decompressed, data)
    }

    // MARK: - Performance Tests

    func testBigEndianPerformance() {
        var data = Data()

        measure {
            for i in 0..<10000 {
                data.appendBigEndian(UInt32(i))
            }
        }
    }

    func testHexStringPerformance() {
        let data = Data(count: 10000)

        measure {
            _ = data.hexString
        }
    }

    func testGZipCompressionPerformance() throws {
        let data = String(repeating: "Performance test data. ", count: 1000).data(using: .utf8)!

        measure {
            _ = try? data.gzipCompressed()
        }
    }

    // MARK: - Edge Cases Tests

    func testMaxUInt64() throws {
        var data = Data()
        let max = UInt64.max

        data.appendBigEndian(max)
        let decoded: UInt64 = try data.readBigEndian(at: 0)

        XCTAssertEqual(decoded, max)
    }

    func testMinValues() throws {
        var data = Data()

        data.appendBigEndian(UInt8.min)
        data.appendBigEndian(UInt16.min)
        data.appendBigEndian(UInt32.min)
        data.appendBigEndian(UInt64.min)

        let v1: UInt8 = try data.readBigEndian(at: 0)
        let v2: UInt16 = try data.readBigEndian(at: 1)
        let v3: UInt32 = try data.readBigEndian(at: 3)
        let v4: UInt64 = try data.readBigEndian(at: 7)

        XCTAssertEqual(v1, 0)
        XCTAssertEqual(v2, 0)
        XCTAssertEqual(v3, 0)
        XCTAssertEqual(v4, 0)
    }

    func testVeryLargeData() throws {
        // 测试非常大的数据（10MB）
        let size = 10 * 1024 * 1024
        let largeData = Data(repeating: 0x42, count: size)

        let compressed = try largeData.gzipCompressed()
        let decompressed = try compressed.gzipDecompressed()

        XCTAssertEqual(decompressed.count, size)
        XCTAssertLessThan(compressed.count, size / 100) // 应该有极好的压缩率
    }
}
