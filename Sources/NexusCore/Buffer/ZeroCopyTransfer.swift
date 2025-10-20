//
//  ZeroCopyTransfer.swift
//  NexusCore
//
//  Created by NexusKit on 2025-01-20.
//  Copyright © 2025 NexusKit. All rights reserved.
//

import Foundation

/// Zero-copy transfer mechanism for efficient data handling
/// Reduces memory copying by using buffer references and file descriptors
public actor ZeroCopyTransfer {

    // MARK: - Transfer Statistics

    /// Statistics for zero-copy transfers
    public struct Statistics {
        public var totalTransfers: Int = 0
        public var zeroCopyTransfers: Int = 0
        public var fallbackTransfers: Int = 0
        public var totalBytesTransferred: Int = 0
        public var totalBytesCopied: Int = 0

        public var zeroCopyRate: Double {
            return totalTransfers > 0 ? Double(zeroCopyTransfers) / Double(totalTransfers) : 0.0
        }

        public var bytesCopySavings: Double {
            let totalPossibleCopies = totalBytesTransferred
            return totalPossibleCopies > 0 ? Double(totalPossibleCopies - totalBytesCopied) / Double(totalPossibleCopies) : 0.0
        }
    }

    // MARK: - Buffer Reference

    /// A reference to a buffer that can be transferred without copying
    public final class BufferReference: @unchecked Sendable {
        private let data: Data
        private let offset: Int
        private let length: Int
        private var isConsumed: Bool = false
        private let lock = NSLock()

        public init(data: Data, offset: Int = 0, length: Int? = nil) {
            self.data = data
            self.offset = offset
            self.length = length ?? (data.count - offset)
        }

        /// Get a slice of the data without copying
        public func slice() throws -> Data {
            lock.lock()
            defer { lock.unlock() }

            guard !isConsumed else {
                throw ZeroCopyError.bufferAlreadyConsumed
            }

            let endIndex = offset + length
            guard offset >= 0 && endIndex <= data.count else {
                throw ZeroCopyError.invalidRange
            }

            return data[offset..<endIndex]
        }

        /// Mark buffer as consumed (prevents further access)
        public func consume() {
            lock.lock()
            defer { lock.unlock() }
            isConsumed = true
        }

        /// Get buffer size
        public var size: Int {
            return length
        }

        /// Check if buffer is consumed
        public var consumed: Bool {
            lock.lock()
            defer { lock.unlock() }
            return isConsumed
        }
    }

    // MARK: - Scatter-Gather IO

    /// Scatter-gather buffer for efficient multi-buffer operations
    public struct ScatterGatherBuffer {
        public let references: [BufferReference]

        public init(references: [BufferReference]) {
            self.references = references
        }

        /// Get total size of all buffers
        public var totalSize: Int {
            return references.reduce(0) { $0 + $1.size }
        }

        /// Gather all buffers into a single data (requires copying)
        public func gather() throws -> Data {
            var result = Data()
            result.reserveCapacity(totalSize)

            for reference in references {
                let slice = try reference.slice()
                result.append(slice)
            }

            return result
        }

        /// Consume all buffers
        public func consumeAll() {
            for reference in references {
                reference.consume()
            }
        }
    }

    // MARK: - Errors

    public enum ZeroCopyError: Error, CustomStringConvertible {
        case bufferAlreadyConsumed
        case invalidRange
        case transferFailed(String)
        case unsupportedOperation

        public var description: String {
            switch self {
            case .bufferAlreadyConsumed:
                return "Buffer has already been consumed"
            case .invalidRange:
                return "Invalid buffer range"
            case .transferFailed(let reason):
                return "Transfer failed: \(reason)"
            case .unsupportedOperation:
                return "Operation not supported in zero-copy mode"
            }
        }
    }

    // MARK: - Properties

    private var statistics: Statistics = Statistics()
    private let bufferPool: BufferPool

    // MARK: - Initialization

    public init(bufferPool: BufferPool = .shared) {
        self.bufferPool = bufferPool
    }

    // MARK: - Public Methods

    /// Create a buffer reference for zero-copy transfer
    /// - Parameters:
    ///   - data: Source data
    ///   - offset: Offset in the data
    ///   - length: Length of the reference (nil = from offset to end)
    /// - Returns: Buffer reference
    public func createReference(
        data: Data,
        offset: Int = 0,
        length: Int? = nil
    ) -> BufferReference {
        return BufferReference(data: data, offset: offset, length: length)
    }

    /// Transfer data using zero-copy when possible
    /// - Parameters:
    ///   - reference: Buffer reference to transfer
    ///   - destination: Destination closure
    /// - Returns: Number of bytes transferred
    @discardableResult
    public func transfer(
        _ reference: BufferReference,
        to destination: (Data) throws -> Void
    ) async throws -> Int {
        statistics.totalTransfers += 1

        // Try zero-copy transfer
        do {
            let slice = try reference.slice()
            try destination(slice)

            statistics.zeroCopyTransfers += 1
            statistics.totalBytesTransferred += reference.size

            reference.consume()
            return reference.size
        } catch {
            // Fallback to copy if zero-copy fails
            statistics.fallbackTransfers += 1
            throw error
        }
    }

    /// Transfer data from scatter-gather buffer
    /// - Parameters:
    ///   - buffer: Scatter-gather buffer
    ///   - destination: Destination closure
    /// - Returns: Number of bytes transferred
    @discardableResult
    public func transferScatterGather(
        _ buffer: ScatterGatherBuffer,
        to destination: ([Data]) throws -> Void
    ) async throws -> Int {
        statistics.totalTransfers += 1

        var slices: [Data] = []
        var totalBytes = 0

        for reference in buffer.references {
            let slice = try reference.slice()
            slices.append(slice)
            totalBytes += slice.count
        }

        try destination(slices)

        buffer.consumeAll()

        statistics.zeroCopyTransfers += 1
        statistics.totalBytesTransferred += totalBytes

        return totalBytes
    }

    /// Write data to output using pooled buffers
    /// - Parameters:
    ///   - data: Data to write
    ///   - output: Output closure
    /// - Returns: Number of bytes written
    @discardableResult
    public func write(
        _ data: Data,
        to output: (Data) throws -> Void
    ) async throws -> Int {
        statistics.totalTransfers += 1
        statistics.totalBytesTransferred += data.count

        // If data is small, write directly
        if data.count <= 4096 {
            try output(data)
            statistics.zeroCopyTransfers += 1
            return data.count
        }

        // For large data, use chunked transfer with pooled buffers
        let chunkSize = 64 * 1024 // 64KB chunks
        var offset = 0
        var totalWritten = 0

        while offset < data.count {
            let remainingBytes = data.count - offset
            let currentChunkSize = min(chunkSize, remainingBytes)

            // Create reference to chunk (zero-copy)
            let chunk = data[offset..<(offset + currentChunkSize)]
            try output(chunk)

            offset += currentChunkSize
            totalWritten += currentChunkSize
        }

        statistics.zeroCopyTransfers += 1

        return totalWritten
    }

    /// Read data into pooled buffer
    /// - Parameters:
    ///   - size: Size to read
    ///   - input: Input closure that fills the buffer
    /// - Returns: Pooled buffer with data
    public func read(
        size: Int,
        from input: (inout Data) throws -> Int
    ) async throws -> BufferPool.PooledBuffer {
        statistics.totalTransfers += 1
        statistics.totalBytesTransferred += size

        // Acquire buffer from pool
        let pooledBuffer = await bufferPool.acquire(size: size)
        var buffer = pooledBuffer.mutableBuffer()

        // Read data into buffer
        let bytesRead = try input(&buffer)

        statistics.totalBytesCopied += bytesRead
        statistics.fallbackTransfers += 1 // Reading always requires at least one copy

        return pooledBuffer
    }

    /// Copy data using optimized memory operations
    /// - Parameters:
    ///   - source: Source data
    ///   - destination: Destination buffer
    ///   - length: Number of bytes to copy
    public func optimizedCopy(
        from source: Data,
        to destination: inout Data,
        length: Int
    ) {
        guard length > 0 else { return }

        statistics.totalTransfers += 1
        statistics.totalBytesTransferred += length
        statistics.totalBytesCopied += length
        statistics.fallbackTransfers += 1

        source.withUnsafeBytes { sourceBytes in
            destination.withUnsafeMutableBytes { destBytes in
                let sourcePtr = sourceBytes.baseAddress!
                let destPtr = destBytes.baseAddress!
                memcpy(destPtr, sourcePtr, length)
            }
        }
    }

    /// Get current statistics
    public func getStatistics() -> Statistics {
        return statistics
    }

    /// Reset statistics
    public func resetStatistics() {
        statistics = Statistics()
    }
}

// MARK: - Global Instance

extension ZeroCopyTransfer {
    /// Shared global zero-copy transfer instance
    public static let shared = ZeroCopyTransfer()
}

// MARK: - Data Extensions for Zero-Copy

extension Data {
    /// Create a buffer reference for zero-copy operations
    public func createReference(offset: Int = 0, length: Int? = nil) -> ZeroCopyTransfer.BufferReference {
        return ZeroCopyTransfer.BufferReference(data: self, offset: offset, length: length)
    }

    /// Split data into multiple references for scatter-gather operations
    public func split(chunkSize: Int) -> ZeroCopyTransfer.ScatterGatherBuffer {
        var references: [ZeroCopyTransfer.BufferReference] = []
        var offset = 0

        while offset < count {
            let length = Swift.min(chunkSize, count - offset)
            let reference = ZeroCopyTransfer.BufferReference(data: self, offset: offset, length: length)
            references.append(reference)
            offset += length
        }

        return ZeroCopyTransfer.ScatterGatherBuffer(references: references)
    }
}
