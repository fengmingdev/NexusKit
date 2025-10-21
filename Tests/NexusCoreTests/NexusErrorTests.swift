//
//  NexusErrorTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

/// 错误类型测试
final class NexusErrorTests: XCTestCase {

    // MARK: - Error Creation Tests

    func testConnectionErrors() {
        let timeout = NexusError.connectionTimeout
        let unreachable = NexusError.networkUnreachable
        let alreadyExists = NexusError.connectionAlreadyExists(id: "conn-1")

        XCTAssertNotNil(timeout)
        XCTAssertNotNil(unreachable)
        XCTAssertNotNil(alreadyExists)
    }

    func testAuthenticationErrors() {
        let authFailed = NexusError.authenticationFailed(reason: "Invalid credentials")
        let requestTimeout = NexusError.requestTimeout

        XCTAssertNotNil(authFailed)
        XCTAssertNotNil(requestTimeout)
    }

    func testSendReceiveErrors() {
        let sendFailed = NexusError.sendFailed(NSError(domain: "test", code: 1))
        let requestTimeout = NexusError.requestTimeout
        let receiveFailed = NexusError.receiveFailed(NSError(domain: "test", code: 2))

        XCTAssertNotNil(sendFailed)
        XCTAssertNotNil(requestTimeout)
        XCTAssertNotNil(receiveFailed)
    }

    // MARK: - Error Equality Tests

    func testErrorEquality() {
        let error1 = NexusError.connectionTimeout
        let error2 = NexusError.connectionTimeout
        let error3 = NexusError.networkUnreachable

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testErrorEqualityWithReason() {
        let error1 = NexusError.authenticationFailed(reason: "Network error")
        let error2 = NexusError.authenticationFailed(reason: "Network error")
        let error3 = NexusError.authenticationFailed(reason: "Different error")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - LocalizedError Tests

    func testErrorDescriptions() {
        let timeout = NexusError.connectionTimeout
        XCTAssertFalse(timeout.errorDescription?.isEmpty ?? true)

        let authFailed = NexusError.authenticationFailed(reason: "Invalid token")
        XCTAssertTrue(authFailed.errorDescription?.contains("Invalid token") ?? false)
    }

    func testFailureReasons() {
        let invalidState = NexusError.invalidStateTransition(
            from: "disconnected",
            to: "connected"
        )
        XCTAssertNotNil(invalidState.failureReason)
    }

    // MARK: - State Transition Error Tests

    func testInvalidStateTransitionError() {
        let error = NexusError.invalidStateTransition(
            from: "disconnected",
            to: "connected"
        )

        switch error {
        case .invalidStateTransition(let from, let to):
            XCTAssertEqual(from, "disconnected")
            XCTAssertEqual(to, "connected")
        default:
            XCTFail("Expected invalidStateTransition error")
        }
    }

    // MARK: - Middleware Error Tests

    func testMiddlewareError() {
        let underlyingError = NSError(domain: "test", code: 1)
        let error = NexusError.middlewareError(
            name: "TestMiddleware",
            error: underlyingError
        )

        switch error {
        case .middlewareError(let name, let err):
            XCTAssertEqual(name, "TestMiddleware")
            XCTAssertNotNil(err)
        default:
            XCTFail("Expected middlewareError")
        }
    }

    // MARK: - Custom Error Tests

    func testCustomError() {
        let underlyingError = NSError(domain: "test", code: 42)
        let error = NexusError.custom(
            message: "Custom error message",
            underlyingError: underlyingError
        )

        switch error {
        case .custom(let message, let underlying):
            XCTAssertEqual(message, "Custom error message")
            XCTAssertNotNil(underlying)
            XCTAssertEqual((underlying as? NSError)?.code, 42)
        default:
            XCTFail("Expected custom error")
        }
    }

    // MARK: - Resource Errors Tests

    func testResourceErrors() {
        let exhausted = NexusError.resourceExhausted
        let outOfMemory = NexusError.outOfMemory

        XCTAssertNotNil(exhausted)
        XCTAssertNotNil(outOfMemory)
    }

    // MARK: - Protocol Errors Tests

    func testProtocolErrors() {
        let invalidFormat = NexusError.invalidMessageFormat(reason: "Missing header")
        let unsupportedVersion = NexusError.unsupportedProtocolVersion(version: "2.0")
        let testError = NSError(domain: "test", code: 1)
        let encodingFailed = NexusError.encodingFailed(testError)

        XCTAssertNotNil(invalidFormat)
        XCTAssertNotNil(unsupportedVersion)
        XCTAssertNotNil(encodingFailed)
    }

    // MARK: - Error Code Tests

    func testErrorCodes() {
        // 确保所有错误都有唯一的代码
        let errors: [NexusError] = [
            .connectionTimeout,
            .connectionClosed,
            .authenticationFailed(reason: "test"),
            .invalidMessageFormat(reason: "test")
        ]

        // 这里可以添加错误代码的验证逻辑
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
    }
}
