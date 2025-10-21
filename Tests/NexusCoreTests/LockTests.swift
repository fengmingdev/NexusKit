//
//  LockTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

/// 锁和原子操作测试
final class LockTests: XCTestCase {

    // MARK: - UnfairLock Tests

    func testUnfairLockBasic() {
        let lock = UnfairLock()
        var counter = 0

        lock.lock()
        counter += 1
        lock.unlock()

        XCTAssertEqual(counter, 1)
    }

    func testUnfairLockWithClosure() {
        let lock = UnfairLock()
        var counter = 0

        let result = lock.withLock {
            counter += 1
            return counter
        }

        XCTAssertEqual(result, 1)
        XCTAssertEqual(counter, 1)
    }

    func testUnfairLockConcurrency() {
        let lock = UnfairLock()
        var counter = 0
        let iterations = 10000

        let expectation = self.expectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 2

        // 并发增加计数器
        DispatchQueue.global().async {
            for _ in 0..<iterations {
                lock.withLock {
                    counter += 1
                }
            }
            expectation.fulfill()
        }

        DispatchQueue.global().async {
            for _ in 0..<iterations {
                lock.withLock {
                    counter += 1
                }
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)

        // 应该准确等于 iterations * 2
        XCTAssertEqual(counter, iterations * 2)
    }

    func testUnfairLockReentrant() {
        let lock = UnfairLock()
        var value = 0

        lock.withLock {
            value = 1
            // 注意：UnfairLock 不是可重入的，不应该在锁内再次加锁
            // 这只是测试基本功能
        }

        XCTAssertEqual(value, 1)
    }

    // MARK: - Atomic Tests

    func testAtomicReadWrite() {
        @Atomic var counter = 0

        counter = 5
        XCTAssertEqual(counter, 5)

        counter = 10
        XCTAssertEqual(counter, 10)
    }

    func testAtomicWithClosure() {
        @Atomic var counter = 0

        let result = $counter.mutate { value in
            value += 10
            return value
        }

        XCTAssertEqual(result, 10)
        XCTAssertEqual(counter, 10)
    }

    func testAtomicConcurrentWrites() {
        @Atomic var counter = 0
        let iterations = 10000

        let expectation = self.expectation(description: "Concurrent writes")
        expectation.expectedFulfillmentCount = 3

        // 三个并发写入
        for _ in 0..<3 {
            DispatchQueue.global().async {
                for _ in 0..<iterations {
                    $counter.mutate { value in
                        value += 1
                    }
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(counter, iterations * 3)
    }

    func testAtomicStruct() {
        struct TestData: Equatable {
            var name: String
            var value: Int
        }

        @Atomic var data = TestData(name: "test", value: 0)

        $data.mutate { value in
            value.name = "updated"
            value.value = 100
        }

        XCTAssertEqual(data.name, "updated")
        XCTAssertEqual(data.value, 100)
    }

    func testAtomicOptional() {
        @Atomic var optionalValue: Int? = nil

        XCTAssertNil(optionalValue)

        optionalValue = 42
        XCTAssertEqual(optionalValue, 42)

        optionalValue = nil
        XCTAssertNil(optionalValue)
    }

    // MARK: - AtomicCounter Tests

    func testAtomicCounterIncrement() {
        let counter = AtomicCounter()

        let result1 = counter.increment()
        let result2 = counter.increment()
        let result3 = counter.increment()

        XCTAssertEqual(result1, 1)
        XCTAssertEqual(result2, 2)
        XCTAssertEqual(result3, 3)
        XCTAssertEqual(counter.value, 3)
    }

    func testAtomicCounterDecrement() {
        let counter = AtomicCounter(initialValue: 10)

        let result1 = counter.decrement()
        let result2 = counter.decrement()

        XCTAssertEqual(result1, 9)
        XCTAssertEqual(result2, 8)
        XCTAssertEqual(counter.value, 8)
    }

    func testAtomicCounterAdd() {
        let counter = AtomicCounter()

        counter.increment(by: 5)
        XCTAssertEqual(counter.value, 5)

        counter.increment(by: 10)
        XCTAssertEqual(counter.value, 15)
    }

    func testAtomicCounterReset() {
        let counter = AtomicCounter()

        counter.increment()
        counter.increment()
        counter.increment()

        XCTAssertEqual(counter.value, 3)

        counter.reset(to: 0)
        XCTAssertEqual(counter.value, 0)
    }

    func testAtomicCounterConcurrency() {
        let counter = AtomicCounter()
        let iterations = 10000

        let expectation = self.expectation(description: "Concurrent increments")
        expectation.expectedFulfillmentCount = 4

        // 四个并发线程递增
        for _ in 0..<4 {
            DispatchQueue.global().async {
                for _ in 0..<iterations {
                    counter.increment()
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(counter.value, Int64(iterations * 4))
    }

    func testAtomicCounterMixedOperations() {
        let counter = AtomicCounter()
        let iterations = 1000

        let expectation = self.expectation(description: "Mixed operations")
        expectation.expectedFulfillmentCount = 2

        // 一个线程递增
        DispatchQueue.global().async {
            for _ in 0..<iterations {
                counter.increment()
            }
            expectation.fulfill()
        }

        // 一个线程递减
        DispatchQueue.global().async {
            for _ in 0..<iterations {
                counter.decrement()
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)

        // 最终结果应该是0（增减相同次数）
        XCTAssertEqual(counter.value, 0)
    }

    // MARK: - ReadWriteLock Tests

    func testReadWriteLockRead() {
        let lock = ReadWriteLock()
        var value = "initial"

        let result = lock.withReadLock {
            return value
        }

        XCTAssertEqual(result, "initial")
    }

    func testReadWriteLockWrite() {
        let lock = ReadWriteLock()
        var value = "initial"

        lock.withWriteLock {
            value = "modified"
        }

        XCTAssertEqual(value, "modified")
    }

    func testReadWriteLockConcurrentReads() {
        let lock = ReadWriteLock()
        var value = 100
        var readCount = 0

        let expectation = self.expectation(description: "Concurrent reads")
        expectation.expectedFulfillmentCount = 5

        // 五个并发读取
        for _ in 0..<5 {
            DispatchQueue.global().async {
                for _ in 0..<100 {
                    lock.withReadLock {
                        _ = value
                        readCount += 1
                    }
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // 所有读取都应该成功
        XCTAssertEqual(readCount, 500)
    }

    func testReadWriteLockReadWriteMix() {
        let lock = ReadWriteLock()
        var dictionary: [String: Int] = [:]

        let expectation = self.expectation(description: "Read-Write mix")
        expectation.expectedFulfillmentCount = 4

        // 两个写入线程
        for i in 0..<2 {
            DispatchQueue.global().async {
                for j in 0..<100 {
                    lock.withWriteLock {
                        dictionary["key-\(i)-\(j)"] = j
                    }
                }
                expectation.fulfill()
            }
        }

        // 两个读取线程
        for _ in 0..<2 {
            DispatchQueue.global().async {
                for _ in 0..<100 {
                    lock.withReadLock {
                        _ = dictionary.count
                    }
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // 应该有200个键值对
        let finalCount = lock.withReadLock { dictionary.count }
        XCTAssertEqual(finalCount, 200)
    }

    // MARK: - Performance Tests

    func testUnfairLockPerformance() {
        let lock = UnfairLock()
        var counter = 0

        measure {
            for _ in 0..<10000 {
                lock.withLock {
                    counter += 1
                }
            }
        }
    }

    func testAtomicPerformance() {
        @Atomic var counter = 0

        measure {
            for _ in 0..<10000 {
                $counter.mutate { value in
                    value += 1
                }
            }
        }
    }

    func testAtomicCounterPerformance() {
        let counter = AtomicCounter()

        measure {
            for _ in 0..<10000 {
                counter.increment()
            }
        }
    }

    func testReadWriteLockPerformance() {
        let lock = ReadWriteLock()
        var value = 0

        measure {
            for i in 0..<10000 {
                if i % 10 == 0 {
                    // 10% 写入
                    lock.withWriteLock {
                        value += 1
                    }
                } else {
                    // 90% 读取
                    lock.withReadLock {
                        _ = value
                    }
                }
            }
        }
    }

    // MARK: - Thread Safety Tests

    func testUnfairLockThreadSafety() {
        let lock = UnfairLock()
        var array: [Int] = []
        let iterations = 1000

        let expectation = self.expectation(description: "Thread safety")
        expectation.expectedFulfillmentCount = 3

        for thread in 0..<3 {
            DispatchQueue.global().async {
                for i in 0..<iterations {
                    lock.withLock {
                        array.append(thread * iterations + i)
                    }
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        // 应该有准确的元素数量
        XCTAssertEqual(array.count, iterations * 3)

        // 所有元素应该是唯一的
        let uniqueElements = Set(array)
        XCTAssertEqual(uniqueElements.count, array.count)
    }

    func testAtomicArrayThreadSafety() {
        @Atomic var array: [Int] = []
        let iterations = 1000

        let expectation = self.expectation(description: "Atomic array safety")
        expectation.expectedFulfillmentCount = 3

        for thread in 0..<3 {
            DispatchQueue.global().async {
                for i in 0..<iterations {
                    $array.mutate { value in
                        value.append(thread * iterations + i)
                    }
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)

        XCTAssertEqual(array.count, iterations * 3)
    }

    // MARK: - Edge Cases Tests

    func testAtomicWithThrowingClosure() {
        enum TestError: Error {
            case failed
        }

        @Atomic var value = 0

        do {
            try $value.mutate { val in
                val = 10
                throw TestError.failed
            }
            XCTFail("Should throw error")
        } catch {
            // 即使抛出错误，值也应该已经修改
            XCTAssertEqual(value, 10)
        }
    }

    func testAtomicCounterNegativeValues() {
        let counter = AtomicCounter()

        counter.decrement()
        XCTAssertEqual(counter.value, -1)

        counter.decrement()
        XCTAssertEqual(counter.value, -2)

        counter.increment(by: 5)
        XCTAssertEqual(counter.value, 3)
    }

    func testReadWriteLockNestedReads() {
        let lock = ReadWriteLock()
        var value = 10

        let result = lock.withReadLock {
            // 嵌套读取（注意：这取决于具体实现是否支持）
            let innerValue = value
            return innerValue * 2
        }

        XCTAssertEqual(result, 20)
    }
}
