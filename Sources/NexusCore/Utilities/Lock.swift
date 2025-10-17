//
//  Lock.swift
//  NexusCore
//
//  Created by NexusKit Contributors
//

import Foundation
import os.lock

// MARK: - Unfair Lock

/// 高性能自旋锁（基于 os_unfair_lock）
public final class UnfairLock: @unchecked Sendable {
    private var _lock = os_unfair_lock()

    public init() {}

    /// 锁定
    @inlinable
    public func lock() {
        os_unfair_lock_lock(&_lock)
    }

    /// 解锁
    @inlinable
    public func unlock() {
        os_unfair_lock_unlock(&_lock)
    }

    /// 尝试锁定
    /// - Returns: 是否成功锁定
    @inlinable
    public func tryLock() -> Bool {
        os_unfair_lock_trylock(&_lock)
    }

    /// 在锁保护下执行闭包
    /// - Parameter block: 要执行的闭包
    /// - Returns: 闭包的返回值
    @inlinable
    public func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }

    deinit {
        // 确保锁被释放
        os_unfair_lock_lock(&_lock)
        os_unfair_lock_unlock(&_lock)
    }
}

// MARK: - Atomic Value

/// 原子值包装器
@propertyWrapper
public struct Atomic<Value>: @unchecked Sendable {
    private let lock = UnfairLock()
    private var value: Value

    public init(wrappedValue: Value) {
        self.value = wrappedValue
    }

    public var wrappedValue: Value {
        get {
            lock.withLock { value }
        }
        set {
            lock.withLock { value = newValue }
        }
    }

    public var projectedValue: Atomic<Value> {
        self
    }

    /// 原子性地修改值
    /// - Parameter transform: 转换闭包
    /// - Returns: 新值
    @discardableResult
    public mutating func mutate<T>(_ transform: (inout Value) throws -> T) rethrows -> T {
        try lock.withLock {
            try transform(&value)
        }
    }

    /// 原子性地交换值
    /// - Parameter newValue: 新值
    /// - Returns: 旧值
    @discardableResult
    public mutating func exchange(_ newValue: Value) -> Value {
        lock.withLock {
            let oldValue = value
            value = newValue
            return oldValue
        }
    }

    /// 原子性地比较并交换
    /// - Parameters:
    ///   - expected: 期望的当前值
    ///   - newValue: 新值
    /// - Returns: 是否成功交换
    @discardableResult
    public mutating func compareAndExchange(expected: Value, newValue: Value) -> Bool where Value: Equatable {
        lock.withLock {
            guard value == expected else { return false }
            value = newValue
            return true
        }
    }
}

// MARK: - Atomic Counter

/// 原子计数器
public final class AtomicCounter: @unchecked Sendable {
    private let lock = UnfairLock()
    private var _value: Int64 = 0

    public init(initialValue: Int64 = 0) {
        _value = initialValue
    }

    /// 当前值
    public var value: Int64 {
        lock.withLock { _value }
    }

    /// 递增并返回新值
    /// - Parameter delta: 递增量（默认为 1）
    /// - Returns: 递增后的值
    @discardableResult
    public func increment(by delta: Int64 = 1) -> Int64 {
        lock.withLock {
            _value += delta
            return _value
        }
    }

    /// 递减并返回新值
    /// - Parameter delta: 递减量（默认为 1）
    /// - Returns: 递减后的值
    @discardableResult
    public func decrement(by delta: Int64 = 1) -> Int64 {
        lock.withLock {
            _value -= delta
            return _value
        }
    }

    /// 重置为指定值
    /// - Parameter value: 新值
    public func reset(to value: Int64 = 0) {
        lock.withLock {
            _value = value
        }
    }

    /// 比较并交换
    /// - Parameters:
    ///   - expected: 期望值
    ///   - newValue: 新值
    /// - Returns: 是否成功交换
    @discardableResult
    public func compareAndExchange(expected: Int64, newValue: Int64) -> Bool {
        lock.withLock {
            guard _value == expected else { return false }
            _value = newValue
            return true
        }
    }
}

// MARK: - Read-Write Lock

/// 读写锁（多读单写）
public final class ReadWriteLock: @unchecked Sendable {
    private var lock = pthread_rwlock_t()

    public init() {
        pthread_rwlock_init(&lock, nil)
    }

    deinit {
        pthread_rwlock_destroy(&lock)
    }

    /// 读锁定
    @inlinable
    public func readLock() {
        pthread_rwlock_rdlock(&lock)
    }

    /// 写锁定
    @inlinable
    public func writeLock() {
        pthread_rwlock_wrlock(&lock)
    }

    /// 解锁
    @inlinable
    public func unlock() {
        pthread_rwlock_unlock(&lock)
    }

    /// 在读锁保护下执行
    /// - Parameter block: 闭包
    /// - Returns: 闭包返回值
    @inlinable
    public func withReadLock<T>(_ block: () throws -> T) rethrows -> T {
        readLock()
        defer { unlock() }
        return try block()
    }

    /// 在写锁保护下执行
    /// - Parameter block: 闭包
    /// - Returns: 闭包返回值
    @inlinable
    public func withWriteLock<T>(_ block: () throws -> T) rethrows -> T {
        writeLock()
        defer { unlock() }
        return try block()
    }
}
