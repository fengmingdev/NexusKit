//
//  ZeroCopyBenchmarks.swift
//  NexusCoreTests
//
//  Created by NexusKit on 2025-01-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import XCTest
@testable import NexusCore

/// Performance benchmarks for zero-copy optimization
/// Target: Reduce memory copying by 70%+ and improve throughput by 50%+
final class ZeroCopyBenchmarks: XCTestCase {

    // MARK: - Test Configuration

    private struct BenchmarkTargets {
        // Buffer Pool Targets
        static let poolHitRate: Double = 0.80 // 80% cache hit rate
        static let poolAllocationTime: TimeInterval = 0.0001 // 100μs per allocation

        // Zero-Copy Targets
        static let copySavingsRate: Double = 0.70 // 70% copy savings
        static let zeroCopyRate: Double = 0.90 // 90% operations use zero-copy

        // Performance Targets
        static let throughputImprovement: Double = 1.5 // 50% improvement (1.5x)
        static let latencyReduction: Double = 0.70 // 30% reduction (0.7x)

        // Memory Targets
        static let memoryReduction: Double = 0.50 // 50% memory reduction
        static let maxMemoryGrowth: Double = 10.0 // 10MB max growth
    }

    // MARK: - Buffer Pool Benchmarks

    func testBufferPoolAllocationPerformance() async throws {
        let pool = BufferPool(configuration: .init(
            maxBuffersPerTier: 50,
            enableStatistics: true
        ))

        let iterations = 1000
        let bufferSize = 4096 // 4KB

        let startTime = Date()

        for _ in 0..<iterations {
            let buffer = await pool.acquire(size: bufferSize)
            buffer.release()
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        let avgTime = elapsedTime / Double(iterations)

        print("\n=== Buffer Pool Allocation Performance ===")
        print("Total iterations: \(iterations)")
        print("Total time: \(String(format: "%.3f", elapsedTime))s")
        print("Average time per allocation: \(String(format: "%.6f", avgTime))s")
        print("Target: <\(String(format: "%.6f", BenchmarkTargets.poolAllocationTime))s")

        XCTAssertLessThan(avgTime, BenchmarkTargets.poolAllocationTime,
                         "Allocation time exceeds target")
    }

    func testBufferPoolCacheHitRate() async throws {
        let pool = BufferPool(configuration: .init(
            maxBuffersPerTier: 50,
            enableStatistics: true
        ))

        let iterations = 500
        let bufferSize = 4096

        // Warmup: create and return buffers
        var buffers: [BufferPool.PooledBuffer] = []
        for _ in 0..<20 {
            let buffer = await pool.acquire(size: bufferSize)
            buffers.append(buffer)
        }
        for buffer in buffers {
            buffer.release()
        }
        buffers.removeAll()

        // Wait for returns to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Reset statistics after warmup
        await pool.resetStatistics()

        // Test: acquire and release buffers
        for _ in 0..<iterations {
            let buffer = await pool.acquire(size: bufferSize)
            buffer.release()
        }

        // Wait for returns
        try await Task.sleep(nanoseconds: 100_000_000)

        let stats = await pool.getStatistics()
        let hitRate = stats.hitRate

        print("\n=== Buffer Pool Cache Hit Rate ===")
        print("Total allocations: \(stats.totalAllocations)")
        print("Cache hits: \(stats.cacheHits)")
        print("Cache misses: \(stats.cacheMisses)")
        print("Hit rate: \(String(format: "%.2f%%", hitRate * 100))")
        print("Target: >\(String(format: "%.2f%%", BenchmarkTargets.poolHitRate * 100))")

        XCTAssertGreaterThan(hitRate, BenchmarkTargets.poolHitRate,
                            "Cache hit rate below target")
    }

    func testBufferPoolMemoryEfficiency() async throws {
        let pool = BufferPool(configuration: .init(
            maxBuffersPerTier: 100,
            maxPoolSize: 20 * 1024 * 1024, // 20MB
            enableStatistics: true
        ))

        let bufferSizes = [256, 1024, 4096, 16384, 65536] // Various sizes
        let iterations = 200

        for _ in 0..<iterations {
            let size = bufferSizes.randomElement()!
            let buffer = await pool.acquire(size: size)
            buffer.release()
        }

        // Wait for returns
        try await Task.sleep(nanoseconds: 100_000_000)

        let stats = await pool.getStatistics()

        print("\n=== Buffer Pool Memory Efficiency ===")
        print("Total bytes allocated: \(stats.totalBytesAllocated / 1024)KB")
        print("Total bytes reused: \(stats.totalBytesReused / 1024)KB")
        print("Current pool size: \(stats.currentPoolSize / 1024)KB")
        print("Peak pool size: \(stats.peakPoolSize / 1024)KB")
        print("Average buffer size: \(String(format: "%.0f", stats.averageBufferSize))B")

        XCTAssertLessThanOrEqual(stats.currentPoolSize, 20 * 1024 * 1024,
                                "Pool size exceeds limit")
    }

    func testBufferPoolConcurrency() async throws {
        let pool = BufferPool(configuration: .init(
            maxBuffersPerTier: 100,
            enableStatistics: true
        ))

        let concurrentTasks = 20
        let iterationsPerTask = 50
        let bufferSize = 8192

        let startTime = Date()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<concurrentTasks {
                group.addTask {
                    for _ in 0..<iterationsPerTask {
                        let buffer = await pool.acquire(size: bufferSize)
                        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                        buffer.release()
                    }
                }
            }
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        let stats = await pool.getStatistics()

        print("\n=== Buffer Pool Concurrency ===")
        print("Concurrent tasks: \(concurrentTasks)")
        print("Iterations per task: \(iterationsPerTask)")
        print("Total allocations: \(stats.totalAllocations)")
        print("Total time: \(String(format: "%.3f", elapsedTime))s")
        print("Cache hit rate: \(String(format: "%.2f%%", stats.hitRate * 100))")

        XCTAssertEqual(stats.totalAllocations, concurrentTasks * iterationsPerTask,
                      "Allocation count mismatch")
    }

    // MARK: - Zero-Copy Transfer Benchmarks

    func testZeroCopyTransferRate() async throws {
        let transfer = ZeroCopyTransfer()

        let iterations = 1000
        let dataSize = 4096

        for _ in 0..<iterations {
            let data = Data(count: dataSize)
            let reference = await transfer.createReference(data: data)

            try await transfer.transfer(reference) { transferredData in
                // Simulate processing
                _ = transferredData.count
            }
        }

        let stats = await transfer.getStatistics()

        print("\n=== Zero-Copy Transfer Rate ===")
        print("Total transfers: \(stats.totalTransfers)")
        print("Zero-copy transfers: \(stats.zeroCopyTransfers)")
        print("Fallback transfers: \(stats.fallbackTransfers)")
        print("Zero-copy rate: \(String(format: "%.2f%%", stats.zeroCopyRate * 100))")
        print("Target: >\(String(format: "%.2f%%", BenchmarkTargets.zeroCopyRate * 100))")

        XCTAssertGreaterThan(stats.zeroCopyRate, BenchmarkTargets.zeroCopyRate,
                            "Zero-copy rate below target")
    }

    func testZeroCopySavingsRate() async throws {
        let transfer = ZeroCopyTransfer()

        let iterations = 500
        let dataSize = 16384 // 16KB

        for _ in 0..<iterations {
            let data = Data(count: dataSize)

            try await transfer.write(data) { chunk in
                // Simulate sending
                _ = chunk.count
            }
        }

        let stats = await transfer.getStatistics()
        let savingsRate = stats.bytesCopySavings

        print("\n=== Zero-Copy Savings Rate ===")
        print("Total bytes transferred: \(stats.totalBytesTransferred / 1024)KB")
        print("Total bytes copied: \(stats.totalBytesCopied / 1024)KB")
        print("Bytes saved: \((stats.totalBytesTransferred - stats.totalBytesCopied) / 1024)KB")
        print("Savings rate: \(String(format: "%.2f%%", savingsRate * 100))")
        print("Target: >\(String(format: "%.2f%%", BenchmarkTargets.copySavingsRate * 100))")

        XCTAssertGreaterThan(savingsRate, BenchmarkTargets.copySavingsRate,
                            "Copy savings below target")
    }

    func testScatterGatherPerformance() async throws {
        let transfer = ZeroCopyTransfer()

        let iterations = 200
        let chunkCount = 10
        let chunkSize = 4096

        let startTime = Date()

        for _ in 0..<iterations {
            // Create scatter-gather buffer
            var references: [ZeroCopyTransfer.BufferReference] = []
            for _ in 0..<chunkCount {
                let data = Data(count: chunkSize)
                let reference = await transfer.createReference(data: data)
                references.append(reference)
            }

            let sgBuffer = ZeroCopyTransfer.ScatterGatherBuffer(references: references)

            try await transfer.transferScatterGather(sgBuffer) { chunks in
                // Simulate processing chunks
                _ = chunks.reduce(0) { $0 + $1.count }
            }
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        let totalBytes = iterations * chunkCount * chunkSize
        let throughput = Double(totalBytes) / elapsedTime / 1024.0 / 1024.0 // MB/s

        print("\n=== Scatter-Gather Performance ===")
        print("Iterations: \(iterations)")
        print("Chunks per iteration: \(chunkCount)")
        print("Total data: \(totalBytes / 1024 / 1024)MB")
        print("Total time: \(String(format: "%.3f", elapsedTime))s")
        print("Throughput: \(String(format: "%.2f", throughput))MB/s")

        let stats = await transfer.getStatistics()
        XCTAssertGreaterThan(stats.zeroCopyRate, 0.80, "Low zero-copy rate for scatter-gather")
    }

    // MARK: - Performance Comparison Benchmarks

    func testThroughputComparison() async throws {
        let iterations = 500
        let dataSize = 32768 // 32KB

        // Baseline: Traditional copy
        let baselineStart = Date()
        for _ in 0..<iterations {
            let data = Data(count: dataSize)
            var copy = Data()
            copy.append(data)
            _ = copy.count
        }
        let baselineTime = Date().timeIntervalSince(baselineStart)

        // Zero-copy approach
        let transfer = ZeroCopyTransfer()
        let zeroCopyStart = Date()
        for _ in 0..<iterations {
            let data = Data(count: dataSize)
            try await transfer.write(data) { chunk in
                _ = chunk.count
            }
        }
        let zeroCopyTime = Date().timeIntervalSince(zeroCopyStart)

        let improvement = baselineTime / zeroCopyTime
        let totalBytes = iterations * dataSize
        let baselineThroughput = Double(totalBytes) / baselineTime / 1024.0 / 1024.0
        let zeroCopyThroughput = Double(totalBytes) / zeroCopyTime / 1024.0 / 1024.0

        print("\n=== Throughput Comparison ===")
        print("Data size per iteration: \(dataSize / 1024)KB")
        print("Total iterations: \(iterations)")
        print("\nBaseline (Traditional Copy):")
        print("  Time: \(String(format: "%.3f", baselineTime))s")
        print("  Throughput: \(String(format: "%.2f", baselineThroughput))MB/s")
        print("\nZero-Copy:")
        print("  Time: \(String(format: "%.3f", zeroCopyTime))s")
        print("  Throughput: \(String(format: "%.2f", zeroCopyThroughput))MB/s")
        print("\nImprovement: \(String(format: "%.2f", improvement))x (\(String(format: "%.1f", (improvement - 1) * 100))% faster)")
        print("Target: >\(String(format: "%.2f", BenchmarkTargets.throughputImprovement))x")

        XCTAssertGreaterThan(improvement, BenchmarkTargets.throughputImprovement,
                            "Throughput improvement below target")
    }

    func testLatencyComparison() async throws {
        let iterations = 1000
        let dataSize = 8192 // 8KB

        // Baseline: Traditional copy
        var baselineLatencies: [TimeInterval] = []
        for _ in 0..<iterations {
            let start = Date()
            let data = Data(count: dataSize)
            var copy = Data()
            copy.append(data)
            _ = copy.count
            baselineLatencies.append(Date().timeIntervalSince(start))
        }

        // Zero-copy approach
        let transfer = ZeroCopyTransfer()
        var zeroCopyLatencies: [TimeInterval] = []
        for _ in 0..<iterations {
            let start = Date()
            let data = Data(count: dataSize)
            try await transfer.write(data) { chunk in
                _ = chunk.count
            }
            zeroCopyLatencies.append(Date().timeIntervalSince(start))
        }

        let baselineAvg = baselineLatencies.reduce(0, +) / Double(baselineLatencies.count)
        let zeroCopyAvg = zeroCopyLatencies.reduce(0, +) / Double(zeroCopyLatencies.count)
        let reduction = zeroCopyAvg / baselineAvg

        print("\n=== Latency Comparison ===")
        print("Iterations: \(iterations)")
        print("\nBaseline (Traditional Copy):")
        print("  Average latency: \(String(format: "%.6f", baselineAvg))s")
        print("\nZero-Copy:")
        print("  Average latency: \(String(format: "%.6f", zeroCopyAvg))s")
        print("\nReduction: \(String(format: "%.2f", reduction))x (\(String(format: "%.1f", (1 - reduction) * 100))% faster)")
        print("Target: <\(String(format: "%.2f", BenchmarkTargets.latencyReduction))x")

        XCTAssertLessThan(reduction, BenchmarkTargets.latencyReduction,
                         "Latency reduction below target")
    }

    func testMemoryUsageComparison() async throws {
        let iterations = 500
        let dataSize = 65536 // 64KB

        let baselineMemoryStart = getMemoryUsage()

        // Baseline: Traditional copy (creates many temporary copies)
        var dataArrayBaseline: [Data] = []
        for _ in 0..<iterations {
            let data = Data(count: dataSize)
            var copy = Data()
            copy.append(data)
            dataArrayBaseline.append(copy)
        }

        let baselineMemoryEnd = getMemoryUsage()
        let baselineMemoryUsed = baselineMemoryEnd - baselineMemoryStart

        // Clear baseline data
        dataArrayBaseline.removeAll()

        // Force GC
        for _ in 1...3 {
            autoreleasepool {
                _ = (0..<10000).map { $0 }
            }
        }
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        let zeroCopyMemoryStart = getMemoryUsage()

        // Zero-copy approach with buffer pool
        let pool = BufferPool()
        var buffersZeroCopy: [BufferPool.PooledBuffer] = []
        for _ in 0..<iterations {
            let buffer = await pool.acquire(size: dataSize)
            buffersZeroCopy.append(buffer)
        }

        let zeroCopyMemoryEnd = getMemoryUsage()
        let zeroCopyMemoryUsed = zeroCopyMemoryEnd - zeroCopyMemoryStart

        // Cleanup
        for buffer in buffersZeroCopy {
            buffer.release()
        }

        let memoryReduction = zeroCopyMemoryUsed / baselineMemoryUsed

        print("\n=== Memory Usage Comparison ===")
        print("Iterations: \(iterations)")
        print("Data size per iteration: \(dataSize / 1024)KB")
        print("\nBaseline (Traditional Copy):")
        print("  Memory used: \(String(format: "%.2f", baselineMemoryUsed))MB")
        print("\nZero-Copy with Pool:")
        print("  Memory used: \(String(format: "%.2f", zeroCopyMemoryUsed))MB")
        print("\nReduction: \(String(format: "%.2f", memoryReduction))x (\(String(format: "%.1f", (1 - memoryReduction) * 100))% less)")
        print("Target: <\(String(format: "%.2f", BenchmarkTargets.memoryReduction))x")

        XCTAssertLessThan(memoryReduction, BenchmarkTargets.memoryReduction,
                         "Memory reduction below target")
    }

    // MARK: - Integration Benchmarks

    func testLargeDataTransferOptimization() async throws {
        let transfer = ZeroCopyTransfer()
        let dataSize = 10 * 1024 * 1024 // 10MB
        let data = Data(count: dataSize)

        let startTime = Date()

        try await transfer.write(data) { chunk in
            // Simulate network send
            _ = chunk.count
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        let throughput = Double(dataSize) / elapsedTime / 1024.0 / 1024.0 // MB/s

        print("\n=== Large Data Transfer Optimization ===")
        print("Data size: \(dataSize / 1024 / 1024)MB")
        print("Transfer time: \(String(format: "%.3f", elapsedTime))s")
        print("Throughput: \(String(format: "%.2f", throughput))MB/s")

        let stats = await transfer.getStatistics()
        print("Zero-copy rate: \(String(format: "%.2f%%", stats.zeroCopyRate * 100))")

        XCTAssertGreaterThan(throughput, 100.0, "Throughput too low for large transfer")
    }

    func testBufferPoolWithZeroCopyIntegration() async throws {
        let pool = BufferPool()
        let transfer = ZeroCopyTransfer(bufferPool: pool)

        let iterations = 200
        let bufferSize = 16384 // 16KB

        for _ in 0..<iterations {
            let buffer = await pool.acquire(size: bufferSize)
            let data = buffer.buffer

            try await transfer.write(data) { chunk in
                _ = chunk.count
            }

            buffer.release()
        }

        let poolStats = await pool.getStatistics()
        let transferStats = await transfer.getStatistics()

        print("\n=== Buffer Pool + Zero-Copy Integration ===")
        print("Iterations: \(iterations)")
        print("\nBuffer Pool:")
        print("  Hit rate: \(String(format: "%.2f%%", poolStats.hitRate * 100))")
        print("  Total allocations: \(poolStats.totalAllocations)")
        print("\nZero-Copy Transfer:")
        print("  Zero-copy rate: \(String(format: "%.2f%%", transferStats.zeroCopyRate * 100))")
        print("  Bytes saved: \((transferStats.totalBytesTransferred - transferStats.totalBytesCopied) / 1024)KB")

        XCTAssertGreaterThan(poolStats.hitRate, 0.70, "Pool hit rate too low")
        XCTAssertGreaterThan(transferStats.zeroCopyRate, 0.80, "Zero-copy rate too low")
    }

    // MARK: - Helper Methods

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
            return Double(info.resident_size) / 1024.0 / 1024.0 // MB
        } else {
            return 0.0
        }
    }
}
