//
//  BufferPool.swift
//  NexusCore
//
//  Created by NexusKit on 2025-01-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import Foundation

/// Buffer pool manager with size-based tiers for efficient memory reuse
/// Reduces allocation overhead and improves performance through buffer pooling
public actor BufferPool {

    // MARK: - Configuration

    /// Pool configuration
    public struct Configuration {
        /// Maximum number of buffers per size tier
        public let maxBuffersPerTier: Int

        /// Size tiers in bytes (default: 256B, 1KB, 4KB, 16KB, 64KB, 256KB, 1MB)
        public let sizeTiers: [Int]

        /// Enable statistics tracking
        public let enableStatistics: Bool

        /// Maximum total pool size in bytes (0 = unlimited)
        public let maxPoolSize: Int

        /// Trim interval in seconds (0 = no auto-trim)
        public let trimInterval: TimeInterval

        public init(
            maxBuffersPerTier: Int = 32,
            sizeTiers: [Int] = [256, 1024, 4096, 16384, 65536, 262144, 1048576],
            enableStatistics: Bool = true,
            maxPoolSize: Int = 50 * 1024 * 1024, // 50MB default
            trimInterval: TimeInterval = 60.0
        ) {
            self.maxBuffersPerTier = maxBuffersPerTier
            self.sizeTiers = sizeTiers.sorted()
            self.enableStatistics = enableStatistics
            self.maxPoolSize = maxPoolSize
            self.trimInterval = trimInterval
        }

        public static let `default` = Configuration()
    }

    // MARK: - Pool Statistics

    /// Statistics for buffer pool
    public struct Statistics {
        public var totalAllocations: Int = 0
        public var totalDeallocations: Int = 0
        public var cacheHits: Int = 0
        public var cacheMisses: Int = 0
        public var currentPoolSize: Int = 0
        public var peakPoolSize: Int = 0
        public var totalBytesAllocated: Int = 0
        public var totalBytesReused: Int = 0

        public var hitRate: Double {
            let total = cacheHits + cacheMisses
            return total > 0 ? Double(cacheHits) / Double(total) : 0.0
        }

        public var averageBufferSize: Double {
            return totalAllocations > 0 ? Double(totalBytesAllocated) / Double(totalAllocations) : 0.0
        }
    }

    // MARK: - Pooled Buffer

    /// A buffer wrapper that returns to pool when released
    public final class PooledBuffer: @unchecked Sendable {
        private let data: Data
        private let pool: BufferPool
        private let tierIndex: Int
        private var isReturned: Bool = false
        private let lock = NSLock()

        fileprivate init(data: Data, pool: BufferPool, tierIndex: Int) {
            self.data = data
            self.pool = pool
            self.tierIndex = tierIndex
        }

        /// Get the underlying data (read-only)
        public var buffer: Data {
            lock.lock()
            defer { lock.unlock() }
            guard !isReturned else {
                fatalError("Attempting to access returned buffer")
            }
            return data
        }

        /// Get mutable data (creates a copy to maintain safety)
        public func mutableBuffer() -> Data {
            lock.lock()
            defer { lock.unlock() }
            guard !isReturned else {
                fatalError("Attempting to access returned buffer")
            }
            return data
        }

        /// Return buffer to pool
        public func release() {
            lock.lock()
            defer { lock.unlock() }

            guard !isReturned else { return }
            isReturned = true

            Task {
                await pool.returnBuffer(data, tierIndex: tierIndex)
            }
        }

        deinit {
            if !isReturned {
                let poolRef = pool
                let dataRef = data
                let tierRef = tierIndex
                Task {
                    await poolRef.returnBuffer(dataRef, tierIndex: tierRef)
                }
            }
        }
    }

    // MARK: - Properties

    private let configuration: Configuration
    private var pools: [[Data]] = []
    private var statistics: Statistics = Statistics()
    private var trimTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.pools = Array(repeating: [], count: configuration.sizeTiers.count)
    }

    /// Start the buffer pool (call after initialization if auto-trim is needed)
    public func start() {
        // Start auto-trim if configured
        if configuration.trimInterval > 0 {
            startAutoTrim()
        }
    }

    deinit {
        trimTask?.cancel()
    }

    // MARK: - Public Methods

    /// Acquire a buffer of the specified size
    /// - Parameter size: Required buffer size in bytes
    /// - Returns: A pooled buffer instance
    public func acquire(size: Int) -> PooledBuffer {
        let tierIndex = findTierIndex(for: size)
        let tierSize = configuration.sizeTiers[tierIndex]

        // Try to reuse from pool
        if !pools[tierIndex].isEmpty {
            let data = pools[tierIndex].removeLast()

            if configuration.enableStatistics {
                statistics.cacheHits += 1
                statistics.totalAllocations += 1
                statistics.currentPoolSize -= tierSize
                statistics.totalBytesReused += tierSize
            }

            return PooledBuffer(data: data, pool: self, tierIndex: tierIndex)
        }

        // Allocate new buffer
        let data = Data(count: tierSize)

        if configuration.enableStatistics {
            statistics.cacheMisses += 1
            statistics.totalAllocations += 1
            statistics.totalBytesAllocated += tierSize
        }

        return PooledBuffer(data: data, pool: self, tierIndex: tierIndex)
    }

    /// Return a buffer to the pool
    fileprivate func returnBuffer(_ data: Data, tierIndex: Int) {
        let tierSize = configuration.sizeTiers[tierIndex]

        // Check if we can add to pool
        guard pools[tierIndex].count < configuration.maxBuffersPerTier else {
            if configuration.enableStatistics {
                statistics.totalDeallocations += 1
            }
            return
        }

        // Check total pool size limit
        if configuration.maxPoolSize > 0 {
            let newSize = statistics.currentPoolSize + tierSize
            guard newSize <= configuration.maxPoolSize else {
                if configuration.enableStatistics {
                    statistics.totalDeallocations += 1
                }
                return
            }
        }

        // Return to pool
        pools[tierIndex].append(data)

        if configuration.enableStatistics {
            statistics.totalDeallocations += 1
            statistics.currentPoolSize += tierSize
            statistics.peakPoolSize = max(statistics.peakPoolSize, statistics.currentPoolSize)
        }
    }

    /// Get current statistics
    public func getStatistics() -> Statistics {
        return statistics
    }

    /// Reset statistics
    public func resetStatistics() {
        statistics = Statistics()
        statistics.currentPoolSize = pools.enumerated().reduce(0) { sum, item in
            let (index, pool) = item
            return sum + pool.count * configuration.sizeTiers[index]
        }
    }

    /// Trim pool to reduce memory usage
    /// - Parameter targetSize: Target pool size in bytes (0 = trim all)
    public func trim(targetSize: Int = 0) {
        var currentSize = statistics.currentPoolSize

        // Trim from largest to smallest tiers
        for tierIndex in (0..<pools.count).reversed() {
            guard currentSize > targetSize else { break }

            let tierSize = configuration.sizeTiers[tierIndex]
            while !pools[tierIndex].isEmpty && currentSize > targetSize {
                pools[tierIndex].removeLast()
                currentSize -= tierSize
            }
        }

        if configuration.enableStatistics {
            statistics.currentPoolSize = currentSize
        }
    }

    /// Clear all buffers from pool
    public func clear() {
        pools = Array(repeating: [], count: configuration.sizeTiers.count)
        if configuration.enableStatistics {
            statistics.currentPoolSize = 0
        }
    }

    // MARK: - Private Methods

    private func findTierIndex(for size: Int) -> Int {
        for (index, tierSize) in configuration.sizeTiers.enumerated() {
            if tierSize >= size {
                return index
            }
        }
        // Return largest tier if size exceeds all tiers
        return configuration.sizeTiers.count - 1
    }

    private func startAutoTrim() {
        trimTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                try? await Task.sleep(nanoseconds: UInt64(self.configuration.trimInterval * 1_000_000_000))

                // Trim to 50% of max pool size
                let targetSize = self.configuration.maxPoolSize > 0 ? self.configuration.maxPoolSize / 2 : 0
                await self.trim(targetSize: targetSize)
            }
        }
    }
}

// MARK: - Global Pool Instance

extension BufferPool {
    /// Shared global buffer pool instance
    public static let shared = BufferPool()
}
