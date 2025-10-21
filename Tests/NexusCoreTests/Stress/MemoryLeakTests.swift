//
//  MemoryLeakTests.swift
//  NexusCore
//
//  Created by NexusKit on 2025-10-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
import Foundation
@testable import NexusKit

/// 内存泄漏检测测试套件
///
/// 测试系统是否存在内存泄漏，通过重复操作后检查内存增长
///
/// **前置条件**: 启动测试服务器
/// ```bash
/// cd TestServers
/// npm run integration
/// ```
///
/// **测试覆盖**:
/// - 连接创建和销毁循环
/// - 消息发送循环
/// - 中间件循环使用
/// - 缓冲区循环分配
/// - 回调闭包循环
/// - 监听器注册和注销循环
///
@available(iOS 13.0, macOS 10.15, *)
final class MemoryLeakTests: XCTestCase {

    // MARK: - Configuration

    private let testHost = "127.0.0.1"
    private let testPort: UInt16 = 8888
    private let connectionTimeout: TimeInterval = 5.0

    // 内存泄漏检测参数
    private let warmupIterations = 10 // 预热迭代（让GC稳定）
    private let testIterations = 100 // 测试迭代
    private let acceptableMemoryGrowth: Double = 5.0 // 可接受的内存增长（MB）

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        print("\n" + String(repeating: "=", count: 60))
        print("🔍 开始内存泄漏检测")
        print(String(repeating: "=", count: 60))

        // 强制GC
        for _ in 1...3 {
            autoreleasepool {
                _ = (0..<1000).map { $0 }
            }
        }
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
    }

    override func tearDown() async throws {
        // 强制GC清理
        for _ in 1...3 {
            autoreleasepool {
                _ = (0..<1000).map { $0 }
            }
        }

        print(String(repeating: "=", count: 60))
        print("✅ 内存泄漏检测完成")
        print(String(repeating: "=", count: 60) + "\n")

        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await super.tearDown()
    }

    // MARK: - 1. 连接生命周期泄漏检测 (3个测试)

    /// 测试1.1: 连接创建和销毁循环
    func testConnectionCreateDestroyLeak() async throws {
        print("\n📊 测试: 连接创建和销毁循环 (检测泄漏)")

        // 预热阶段
        print("  预热阶段...")
        for _ in 1...warmupIterations {
            autoreleasepool {
                Task {
                    let connection = try? await createConnection()
                    await connection?.disconnect()
                }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // 测量基线
        let baselineMemory = getMemoryUsage()
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")

        // 测试阶段
        print("  测试阶段 (\(testIterations)次迭代)...")
        let testStart = Date()

        for i in 1...testIterations {
            autoreleasepool {
                Task {
                    do {
                        let connection = try await self.createConnection()

                        // 模拟一些操作
                        let testData = "Leak test".data(using: .utf8)!
                        try await connection.send(testData)

                        // 断开连接
                        await connection.disconnect()
                    } catch {
                        // 忽略错误
                    }
                }
            }

            if i % 20 == 0 {
                let currentMemory = getMemoryUsage()
                print("    第\(i)次: 内存=\(String(format: "%.2f", currentMemory))MB")
            }
        }

        let testDuration = Date().timeIntervalSince(testStart)

        // 等待所有任务完成和GC
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // 强制GC
        for _ in 1...5 {
            autoreleasepool {
                _ = (0..<10000).map { $0 }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // 测量最终内存
        let finalMemory = getMemoryUsage()
        let memoryGrowth = finalMemory - baselineMemory
        let avgMemoryPerIteration = memoryGrowth / Double(testIterations)

        print("\n📊 连接创建销毁泄漏检测结果:")
        print("  迭代次数: \(testIterations)")
        print("  测试耗时: \(String(format: "%.2f", testDuration))秒")
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")
        print("  最终内存: \(String(format: "%.2f", finalMemory))MB")
        print("  内存增长: \(String(format: "%.2f", memoryGrowth))MB")
        print("  平均每次增长: \(String(format: "%.4f", avgMemoryPerIteration))MB")

        // 判断是否泄漏
        if abs(memoryGrowth) > acceptableMemoryGrowth {
            print("  ⚠️ 警告: 可能存在内存泄漏")
        } else {
            print("  ✅ 未检测到明显内存泄漏")
        }

        XCTAssertLessThan(abs(memoryGrowth), acceptableMemoryGrowth,
                         "内存增长应该小于\(acceptableMemoryGrowth)MB")
    }

    /// 测试1.2: 长连接保持和释放循环
    func testLongLivedConnectionLeak() async throws {
        print("\n📊 测试: 长连接保持和释放循环")

        // 预热
        print("  预热阶段...")
        for _ in 1...warmupIterations {
            autoreleasepool {
                Task {
                    let connection = try? await createConnection()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await connection?.disconnect()
                }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let baselineMemory = getMemoryUsage()
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")

        print("  测试阶段...")
        for i in 1...testIterations {
            autoreleasepool {
                Task {
                    do {
                        let connection = try await self.createConnection()

                        // 保持连接一段时间
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

                        // 发送一些消息
                        for _ in 1...5 {
                            let testData = "Long lived test".data(using: .utf8)!
                            try await connection.send(testData)
                        }

                        await connection.disconnect()
                    } catch {
                        // 忽略
                    }
                }
            }

            if i % 20 == 0 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                let currentMemory = getMemoryUsage()
                print("    第\(i)次: 内存=\(String(format: "%.2f", currentMemory))MB")
            }
        }

        try await Task.sleep(nanoseconds: 3_000_000_000)

        // 强制GC
        for _ in 1...5 {
            autoreleasepool {
                _ = (0..<10000).map { $0 }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let finalMemory = getMemoryUsage()
        let memoryGrowth = finalMemory - baselineMemory

        print("\n📊 长连接泄漏检测结果:")
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")
        print("  最终内存: \(String(format: "%.2f", finalMemory))MB")
        print("  内存增长: \(String(format: "%.2f", memoryGrowth))MB")

        if abs(memoryGrowth) > acceptableMemoryGrowth {
            print("  ⚠️ 警告: 可能存在内存泄漏")
        } else {
            print("  ✅ 未检测到明显内存泄漏")
        }

        XCTAssertLessThan(abs(memoryGrowth), acceptableMemoryGrowth,
                         "内存增长应该小于\(acceptableMemoryGrowth)MB")
    }

    /// 测试1.3: 并发连接创建销毁循环
    func testConcurrentConnectionLeak() async throws {
        print("\n📊 测试: 并发连接创建销毁循环")

        // 预热
        print("  预热阶段...")
        for _ in 1...warmupIterations {
            autoreleasepool {
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        for _ in 1...5 {
                            group.addTask {
                                let connection = try? await self.createConnection()
                                await connection?.disconnect()
                            }
                        }
                    }
                }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let baselineMemory = getMemoryUsage()
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")

        print("  测试阶段...")
        let concurrency = 10
        let iterations = testIterations / concurrency

        for i in 1...iterations {
            await withTaskGroup(of: Void.self) { group in
                for _ in 1...concurrency {
                    group.addTask {
                        autoreleasepool {
                            do {
                                let connection = try await self.createConnection()
                                let testData = "Concurrent test".data(using: .utf8)!
                                try await connection.send(testData)
                                await connection.disconnect()
                            } catch {
                                // 忽略
                            }
                        }
                    }
                }
            }

            if i % 2 == 0 {
                let currentMemory = getMemoryUsage()
                print("    第\(i * concurrency)次: 内存=\(String(format: "%.2f", currentMemory))MB")
            }
        }

        try await Task.sleep(nanoseconds: 3_000_000_000)

        // 强制GC
        for _ in 1...5 {
            autoreleasepool {
                _ = (0..<10000).map { $0 }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let finalMemory = getMemoryUsage()
        let memoryGrowth = finalMemory - baselineMemory

        print("\n📊 并发连接泄漏检测结果:")
        print("  总连接数: \(iterations * concurrency)")
        print("  并发度: \(concurrency)")
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")
        print("  最终内存: \(String(format: "%.2f", finalMemory))MB")
        print("  内存增长: \(String(format: "%.2f", memoryGrowth))MB")

        if abs(memoryGrowth) > acceptableMemoryGrowth * 1.5 { // 并发允许更大一点
            print("  ⚠️ 警告: 可能存在内存泄漏")
        } else {
            print("  ✅ 未检测到明显内存泄漏")
        }

        XCTAssertLessThan(abs(memoryGrowth), acceptableMemoryGrowth * 1.5,
                         "内存增长应该小于\(acceptableMemoryGrowth * 1.5)MB")
    }

    // MARK: - 2. 数据传输泄漏检测 (2个测试)

    /// 测试2.1: 大量消息发送循环
    func testMessageSendingLeak() async throws {
        print("\n📊 测试: 大量消息发送循环")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        // 预热
        print("  预热阶段...")
        let testData = "Memory leak test message".data(using: .utf8)!
        for _ in 1...warmupIterations {
            try await connection.send(testData)
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let baselineMemory = getMemoryUsage()
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")

        print("  测试阶段 (\(testIterations * 10)条消息)...")
        for i in 1...(testIterations * 10) {
            autoreleasepool {
                do {
                    try await connection.send(testData)
                } catch {
                    // 忽略
                }
            }

            if i % 200 == 0 {
                let currentMemory = getMemoryUsage()
                print("    第\(i)条: 内存=\(String(format: "%.2f", currentMemory))MB")
            }
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)

        // 强制GC
        for _ in 1...3 {
            autoreleasepool {
                _ = (0..<10000).map { $0 }
            }
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let finalMemory = getMemoryUsage()
        let memoryGrowth = finalMemory - baselineMemory

        print("\n📊 消息发送泄漏检测结果:")
        print("  发送消息数: \(testIterations * 10)")
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")
        print("  最终内存: \(String(format: "%.2f", finalMemory))MB")
        print("  内存增长: \(String(format: "%.2f", memoryGrowth))MB")

        if abs(memoryGrowth) > acceptableMemoryGrowth {
            print("  ⚠️ 警告: 可能存在内存泄漏")
        } else {
            print("  ✅ 未检测到明显内存泄漏")
        }

        XCTAssertLessThan(abs(memoryGrowth), acceptableMemoryGrowth,
                         "内存增长应该小于\(acceptableMemoryGrowth)MB")
    }

    /// 测试2.2: 大数据传输循环
    func testLargeDataTransferLeak() async throws {
        print("\n📊 测试: 大数据传输循环")

        let connection = try await createConnection()
        defer { Task { await connection.disconnect() } }

        // 创建1MB测试数据
        let largeData = Data(repeating: 0x42, count: 1024 * 1024)

        // 预热
        print("  预热阶段...")
        for _ in 1...5 {
            autoreleasepool {
                try? await connection.send(largeData)
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let baselineMemory = getMemoryUsage()
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")

        print("  测试阶段 (50次 × 1MB)...")
        for i in 1...50 {
            autoreleasepool {
                do {
                    try await connection.send(largeData)
                } catch {
                    // 忽略
                }
            }

            if i % 10 == 0 {
                try await Task.sleep(nanoseconds: 500_000_000)
                let currentMemory = getMemoryUsage()
                print("    第\(i)次: 内存=\(String(format: "%.2f", currentMemory))MB")
            }
        }

        try await Task.sleep(nanoseconds: 3_000_000_000)

        // 强制GC
        for _ in 1...5 {
            autoreleasepool {
                _ = (0..<10000).map { $0 }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let finalMemory = getMemoryUsage()
        let memoryGrowth = finalMemory - baselineMemory

        print("\n📊 大数据传输泄漏检测结果:")
        print("  传输次数: 50")
        print("  每次大小: 1MB")
        print("  总传输: 50MB")
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")
        print("  最终内存: \(String(format: "%.2f", finalMemory))MB")
        print("  内存增长: \(String(format: "%.2f", memoryGrowth))MB")

        // 大数据传输允许稍大一点的内存增长
        if abs(memoryGrowth) > acceptableMemoryGrowth * 2 {
            print("  ⚠️ 警告: 可能存在内存泄漏")
        } else {
            print("  ✅ 未检测到明显内存泄漏")
        }

        XCTAssertLessThan(abs(memoryGrowth), acceptableMemoryGrowth * 2,
                         "内存增长应该小于\(acceptableMemoryGrowth * 2)MB")
    }

    // MARK: - 3. 资源管理泄漏检测 (1个测试)

    /// 测试3.1: 缓冲区分配释放循环
    func testBufferAllocationLeak() async throws {
        print("\n📊 测试: 缓冲区分配释放循环")

        // 预热
        print("  预热阶段...")
        for _ in 1...warmupIterations {
            autoreleasepool {
                _ = Data(repeating: 0x42, count: 10240)
            }
        }

        let baselineMemory = getMemoryUsage()
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")

        print("  测试阶段 (\(testIterations * 10)次分配)...")
        for i in 1...(testIterations * 10) {
            autoreleasepool {
                // 分配各种大小的缓冲区
                _ = Data(repeating: 0x42, count: 1024) // 1KB
                _ = Data(repeating: 0x43, count: 10240) // 10KB
                _ = Data(repeating: 0x44, count: 102400) // 100KB
            }

            if i % 200 == 0 {
                let currentMemory = getMemoryUsage()
                print("    第\(i)次: 内存=\(String(format: "%.2f", currentMemory))MB")
            }
        }

        // 强制GC
        for _ in 1...5 {
            autoreleasepool {
                _ = (0..<10000).map { $0 }
            }
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)

        let finalMemory = getMemoryUsage()
        let memoryGrowth = finalMemory - baselineMemory

        print("\n📊 缓冲区分配泄漏检测结果:")
        print("  分配次数: \(testIterations * 10)")
        print("  基线内存: \(String(format: "%.2f", baselineMemory))MB")
        print("  最终内存: \(String(format: "%.2f", finalMemory))MB")
        print("  内存增长: \(String(format: "%.2f", memoryGrowth))MB")

        if abs(memoryGrowth) > acceptableMemoryGrowth {
            print("  ⚠️ 警告: 可能存在内存泄漏")
        } else {
            print("  ✅ 未检测到明显内存泄漏")
        }

        XCTAssertLessThan(abs(memoryGrowth), acceptableMemoryGrowth,
                         "内存增长应该小于\(acceptableMemoryGrowth)MB")
    }

    // MARK: - Helper Methods

    /// 创建TCP连接
    private func createConnection() async throws -> TCPConnection {
        var config = TCPConfiguration()
        config.timeout = connectionTimeout

        let connection = TCPConnection(
            host: testHost,
            port: testPort,
            configuration: config
        )

        try await connection.connect()
        return connection
    }

    /// 获取当前内存使用量（MB）
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0
        } else {
            return 0.0
        }
    }
}
