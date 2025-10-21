//
//  BufferIntegrationTests.swift
//  NexusKit Integration Tests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit
@testable import NexusKit

/// 缓冲管理器集成测试
final class BufferIntegrationTests: XCTestCase {

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        let isRunning = await TestUtils.isTCPServerRunning()
        if !isRunning {
            throw XCTSkip("TCP测试服务器未运行")
        }
    }

    // MARK: - 基础缓冲测试

    /// 测试基础缓冲写入和读取
    func testBasicBufferReadWrite() async throws {
        TestUtils.printTestSeparator("测试基础缓冲写入和读取")

        let buffer = BufferManager()

        // 写入数据
        let testData = "Hello Buffer!".data(using: .utf8)!
        try buffer.write(testData)

        // 验证缓冲区大小
        XCTAssertEqual(buffer.availableBytes, testData.count, "可用字节数应该等于写入的数据大小")

        // 读取数据
        let readData = try buffer.read(length: testData.count)
        XCTAssertEqual(readData, testData, "读取的数据应该与写入的数据一致")

        // 验证缓冲区已清空
        XCTAssertEqual(buffer.availableBytes, 0, "读取后缓冲区应该为空")

        TestUtils.printTestResult("基础缓冲写入和读取", passed: true)
    }

    /// 测试部分读取
    func testPartialRead() async throws {
        TestUtils.printTestSeparator("测试部分读取")

        let buffer = BufferManager()

        let testData = "0123456789".data(using: .utf8)!
        try buffer.write(testData)

        // 读取前5个字节
        let firstPart = try buffer.read(length: 5)
        XCTAssertEqual(String(data: firstPart, encoding: .utf8), "01234")
        XCTAssertEqual(buffer.availableBytes, 5, "应该还有5个字节")

        // 读取剩余字节
        let secondPart = try buffer.read(length: 5)
        XCTAssertEqual(String(data: secondPart, encoding: .utf8), "56789")
        XCTAssertEqual(buffer.availableBytes, 0, "缓冲区应该已清空")

        TestUtils.printTestResult("部分读取", passed: true)
    }

    /// 测试Peek操作（不移除数据）
    func testPeekOperation() async throws {
        TestUtils.printTestSeparator("测试Peek操作")

        let buffer = BufferManager()

        let testData = "Peek Test".data(using: .utf8)!
        try buffer.write(testData)

        // Peek数据（不移除）
        let peekedData = try buffer.peek(length: 4)
        XCTAssertEqual(String(data: peekedData, encoding: .utf8), "Peek")

        // 验证缓冲区大小未变
        XCTAssertEqual(buffer.availableBytes, testData.count, "Peek不应该移除数据")

        // 再次Peek应该得到相同数据
        let peekedAgain = try buffer.peek(length: 4)
        XCTAssertEqual(peekedData, peekedAgain, "多次Peek应该得到相同数据")

        TestUtils.printTestResult("Peek操作", passed: true)
    }

    // MARK: - 大数据测试

    /// 测试大数据写入和读取
    func testLargeDataReadWrite() async throws {
        TestUtils.printTestSeparator("测试大数据写入和读取")

        let buffer = BufferManager()

        // 1MB数据
        let largeData = TestFixtures.randomData(length: 1024 * 1024)

        let (_, writeDuration) = await TestUtils.measureTime {
            try buffer.write(largeData)
        }

        print("  写入1MB: \(String(format: "%.3f", writeDuration))s")

        XCTAssertEqual(buffer.availableBytes, largeData.count)

        let (readData, readDuration) = await TestUtils.measureTime {
            try buffer.read(length: largeData.count)
        }

        print("  读取1MB: \(String(format: "%.3f", readDuration))s")

        XCTAssertEqual(readData, largeData, "读取的大数据应该与写入一致")

        TestUtils.printTestResult(
            "大数据读写(写:\(String(format: "%.3f", writeDuration))s, 读:\(String(format: "%.3f", readDuration))s)",
            passed: true
        )
    }

    /// 测试分块大数据写入
    func testChunkedLargeDataWrite() async throws {
        TestUtils.printTestSeparator("测试分块大数据写入")

        let buffer = BufferManager()

        let chunkSize = 64 * 1024 // 64KB
        let chunkCount = 16 // 总共1MB
        var totalData = Data()

        for _ in 0..<chunkCount {
            let chunk = TestFixtures.randomData(length: chunkSize)
            totalData.append(chunk)
            try buffer.write(chunk)
        }

        XCTAssertEqual(buffer.availableBytes, totalData.count, "缓冲区应该包含所有分块数据")

        let readData = try buffer.read(length: totalData.count)
        XCTAssertEqual(readData, totalData, "读取的数据应该与分块写入的数据一致")

        TestUtils.printTestResult("分块大数据写入", passed: true)
    }

    // MARK: - 并发测试

    /// 测试并发写入
    func testConcurrentWrites() async throws {
        TestUtils.printTestSeparator("测试并发写入")

        let buffer = BufferManager()
        let writeCount = 100
        var writtenData: [Data] = []

        // 并发写入
        try await TestUtils.runConcurrently(count: writeCount) {
            let data = TestFixtures.randomData(length: 100)
            try buffer.write(data)
            writtenData.append(data)
        }

        // 验证所有数据都被写入
        let totalSize = writtenData.reduce(0) { $0 + $1.count }
        XCTAssertEqual(buffer.availableBytes, totalSize, "缓冲区应该包含所有并发写入的数据")

        TestUtils.printTestResult("并发写入(\(writeCount)次)", passed: true)
    }

    /// 测试并发读写混合
    func testConcurrentReadWrite() async throws {
        TestUtils.printTestSeparator("测试并发读写混合")

        let buffer = BufferManager()

        // 预先写入一些数据
        let initialData = TestFixtures.randomData(length: 10 * 1024)
        try buffer.write(initialData)

        var readSuccessCount = 0
        var writeSuccessCount = 0
        let lock = NSLock()

        // 并发读写
        await withTaskGroup(of: Void.self) { group in
            // 读取任务
            for _ in 0..<20 {
                group.addTask {
                    do {
                        if buffer.availableBytes >= 100 {
                            _ = try buffer.read(length: 100)
                            lock.lock()
                            readSuccessCount += 1
                            lock.unlock()
                        }
                    } catch {
                        // 忽略错误（可能缓冲区为空）
                    }
                }
            }

            // 写入任务
            for _ in 0..<20 {
                group.addTask {
                    do {
                        let data = TestFixtures.randomData(length: 100)
                        try buffer.write(data)
                        lock.lock()
                        writeSuccessCount += 1
                        lock.unlock()
                    } catch {
                        // 忽略错误
                    }
                }
            }

            await group.waitForAll()
        }

        print("  读取成功: \(readSuccessCount)")
        print("  写入成功: \(writeSuccessCount)")

        XCTAssertGreaterThan(readSuccessCount, 0, "应该有读取成功")
        XCTAssertGreaterThan(writeSuccessCount, 0, "应该有写入成功")

        TestUtils.printTestResult(
            "并发读写混合(读:\(readSuccessCount), 写:\(writeSuccessCount))",
            passed: true
        )
    }

    // MARK: - 边界条件测试

    /// 测试空缓冲区读取
    func testReadFromEmptyBuffer() async throws {
        TestUtils.printTestSeparator("测试空缓冲区读取")

        let buffer = BufferManager()

        do {
            _ = try buffer.read(length: 10)
            XCTFail("从空缓冲区读取应该抛出错误")
        } catch {
            // 预期会抛出错误
            TestUtils.printTestResult("空缓冲区读取", passed: true)
        }
    }

    /// 测试读取超过可用字节
    func testReadMoreThanAvailable() async throws {
        TestUtils.printTestSeparator("测试读取超过可用字节")

        let buffer = BufferManager()

        let testData = "Short".data(using: .utf8)!
        try buffer.write(testData)

        do {
            _ = try buffer.read(length: 100)
            XCTFail("读取超过可用字节应该抛出错误")
        } catch {
            // 预期会抛出错误
            TestUtils.printTestResult("读取超过可用字节", passed: true)
        }
    }

    /// 测试零长度读写
    func testZeroLengthReadWrite() async throws {
        TestUtils.printTestSeparator("测试零长度读写")

        let buffer = BufferManager()

        // 写入空数据
        try buffer.write(Data())
        XCTAssertEqual(buffer.availableBytes, 0, "写入空数据后缓冲区应该为空")

        // 写入一些数据
        let testData = "Test".data(using: .utf8)!
        try buffer.write(testData)

        // 读取零长度
        let zeroData = try buffer.read(length: 0)
        XCTAssertEqual(zeroData.count, 0, "读取零长度应该返回空数据")
        XCTAssertEqual(buffer.availableBytes, testData.count, "读取零长度不应该消耗缓冲区")

        TestUtils.printTestResult("零长度读写", passed: true)
    }

    // MARK: - 内存管理测试

    /// 测试缓冲区清空
    func testBufferClear() async throws {
        TestUtils.printTestSeparator("测试缓冲区清空")

        let buffer = BufferManager()

        // 写入数据
        let testData = TestFixtures.randomData(length: 1024)
        try buffer.write(testData)

        XCTAssertEqual(buffer.availableBytes, 1024)

        // 清空缓冲区
        buffer.clear()

        XCTAssertEqual(buffer.availableBytes, 0, "清空后缓冲区应该为空")

        // 验证可以继续使用
        try buffer.write(testData)
        XCTAssertEqual(buffer.availableBytes, 1024, "清空后应该可以继续写入")

        TestUtils.printTestResult("缓冲区清空", passed: true)
    }

    /// 测试内存占用
    func testMemoryUsage() async throws {
        TestUtils.printTestSeparator("测试内存占用")

        let buffer = BufferManager()

        // 写入10MB数据
        let largeDataSize = 10 * 1024 * 1024
        let iterations = 10

        var peakMemory: UInt64 = 0

        for _ in 0..<iterations {
            let chunk = TestFixtures.randomData(length: largeDataSize / iterations)
            try buffer.write(chunk)

            let currentMemory = TestUtils.currentMemoryUsage()
            if currentMemory > peakMemory {
                peakMemory = currentMemory
            }
        }

        print("  峰值内存: \(String(format: "%.2f", Double(peakMemory) / 1024 / 1024)) MB")

        // 读取所有数据
        _ = try buffer.read(length: largeDataSize)

        let finalMemory = TestUtils.currentMemoryUsage()
        print("  读取后内存: \(String(format: "%.2f", Double(finalMemory) / 1024 / 1024)) MB")

        TestUtils.printTestResult("内存占用", passed: true)
    }

    // MARK: - 实际应用场景测试

    /// 测试TCP消息分包读取
    func testTCPMessageFraming() async throws {
        TestUtils.printTestSeparator("测试TCP消息分包读取")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 发送多条消息
        let messageCount = 10
        var sentMessages: [Data] = []

        for i in 0..<messageCount {
            let msg = TestFixtures.BinaryProtocolMessage(
                qid: UInt32(i + 1),
                fid: 1,
                body: "Message \(i)".data(using: .utf8)!
            ).encode()

            sentMessages.append(msg)
            try await connection.send(msg, timeout: 3.0)
        }

        // 接收所有响应
        var receivedCount = 0

        for _ in 0..<messageCount {
            let response = try await TestUtils.receiveMessage(
                connection: connection,
                timeout: 5.0
            )

            if !response.isEmpty {
                receivedCount += 1
            }
        }

        print("  发送: \(messageCount), 接收: \(receivedCount)")

        XCTAssertGreaterThanOrEqual(receivedCount, messageCount - 2, "应该接收到大部分消息")

        TestUtils.printTestResult("TCP消息分包读取", passed: true)
    }

    /// 测试流式数据处理
    func testStreamingDataProcessing() async throws {
        TestUtils.printTestSeparator("测试流式数据处理")

        let connection = try await TestUtils.createTestConnection()
        defer {
            Task {
                await connection.disconnect(reason: .clientInitiated)
            }
        }

        // 发送大量小消息
        let smallMessageCount = 100
        var successCount = 0

        let (_, duration) = await TestUtils.measureTime {
            for i in 0..<smallMessageCount {
                let msg = TestFixtures.BinaryProtocolMessage(
                    qid: UInt32(i + 1),
                    fid: 1,
                    body: "Stream \(i)".data(using: .utf8)!
                ).encode()

                do {
                    _ = try await TestUtils.sendAndReceiveMessage(
                        connection: connection,
                        message: msg,
                        timeout: 3.0
                    )
                    successCount += 1
                } catch {
                    // 忽略个别失败
                }
            }
        }

        let successRate = Double(successCount) / Double(smallMessageCount) * 100
        print("  成功率: \(String(format: "%.1f", successRate))%")
        print("  总耗时: \(String(format: "%.3f", duration))s")

        XCTAssertGreaterThan(successRate, 80.0, "成功率应该大于80%")

        TestUtils.printTestResult(
            "流式数据处理(\(successCount)/\(smallMessageCount))",
            passed: true,
            duration: duration
        )
    }

    // MARK: - 性能测试

    /// 测试缓冲区性能
    func testBufferPerformance() async throws {
        TestUtils.printTestSeparator("测试缓冲区性能")

        let buffer = BufferManager()
        let iterations = 10000
        let dataSize = 1024 // 1KB

        // 测试写入性能
        let (_, writeDuration) = await TestUtils.measureTime {
            for _ in 0..<iterations {
                let data = TestFixtures.randomData(length: dataSize)
                try buffer.write(data)
            }
        }

        let writeQPS = Double(iterations) / writeDuration
        print("  写入性能: \(String(format: "%.0f", writeQPS)) ops/s")

        // 测试读取性能
        let (_, readDuration) = await TestUtils.measureTime {
            for _ in 0..<iterations {
                _ = try buffer.read(length: dataSize)
            }
        }

        let readQPS = Double(iterations) / readDuration
        print("  读取性能: \(String(format: "%.0f", readQPS)) ops/s")

        XCTAssertGreaterThan(writeQPS, 10000, "写入性能应该大于10000 ops/s")
        XCTAssertGreaterThan(readQPS, 10000, "读取性能应该大于10000 ops/s")

        TestUtils.printTestResult(
            "缓冲区性能(写:\(String(format: "%.0f", writeQPS)), 读:\(String(format: "%.0f", readQPS)) ops/s)",
            passed: true
        )
    }
}
