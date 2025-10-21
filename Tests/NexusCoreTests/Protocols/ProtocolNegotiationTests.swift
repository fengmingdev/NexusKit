//
//  ProtocolNegotiationTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusKit

final class ProtocolNegotiationTests: XCTestCase {
    
    // MARK: - Negotiation Tests
    
    func testNegotiateSuccess() async throws {
        // Given
        let localProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0", "2.0"]),
            ProtocolInfo(from: MessagePackProtocol(), supportedVersions: ["1.0"])
        ]
        
        let remoteProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0", "2.0"])
        ]
        
        let negotiator = ProtocolNegotiator(localProtocols: localProtocols)
        
        // When
        let result = await negotiator.negotiate(with: remoteProtocols)
        
        // Then
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.protocolInfo?.name, "JSON")
        XCTAssertEqual(result.version, "2.0") // 最高公共版本
    }
    
    func testNegotiateFailure() async throws {
        // Given
        let localProtocols = [
            ProtocolInfo(from: MessagePackProtocol(), supportedVersions: ["1.0"])
        ]
        
        let remoteProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"])
        ]
        
        let negotiator = ProtocolNegotiator(localProtocols: localProtocols)
        
        // When
        let result = await negotiator.negotiate(with: remoteProtocols)
        
        // Then
        XCTAssertFalse(result.isSuccess)
    }
    
    func testNegotiateWithPriority() async throws {
        // Given
        let localProtocols = [
            ProtocolInfo(from: JSONProtocol(priority: 10), supportedVersions: ["1.0"]),
            ProtocolInfo(from: MessagePackProtocol(priority: 20), supportedVersions: ["1.0"])
        ]
        
        let remoteProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"]),
            ProtocolInfo(from: MessagePackProtocol(), supportedVersions: ["1.0"])
        ]
        
        let negotiator = ProtocolNegotiator(
            localProtocols: localProtocols,
            selectionStrategy: .highestPriority
        )
        
        // When
        let result = await negotiator.negotiate(with: remoteProtocols)
        
        // Then
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.protocolInfo?.name, "MessagePack") // 更高优先级
    }
    
    func testNegotiateWithMostCapabilities() async throws {
        // Given
        let localProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"]),
            ProtocolInfo(from: MessagePackProtocol(), supportedVersions: ["1.0"])
        ]
        
        let remoteProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"]),
            ProtocolInfo(from: MessagePackProtocol(), supportedVersions: ["1.0"])
        ]
        
        let negotiator = ProtocolNegotiator(
            localProtocols: localProtocols,
            selectionStrategy: .mostCapabilities
        )
        
        // When
        let result = await negotiator.negotiate(with: remoteProtocols)
        
        // Then
        XCTAssertTrue(result.isSuccess)
        // MessagePack 有更多能力
        XCTAssertEqual(result.protocolInfo?.name, "MessagePack")
    }
    
    func testNegotiationCallback() async throws {
        // Given
        let localProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"])
        ]
        
        let remoteProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"])
        ]
        
        let negotiator = ProtocolNegotiator(localProtocols: localProtocols)
        
        let expectation = XCTestExpectation(description: "Negotiation callback")
        
        // When
        await negotiator.onNegotiation { result in
            XCTAssertTrue(result.isSuccess)
            expectation.fulfill()
        }
        
        _ = await negotiator.negotiate(with: remoteProtocols)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testNegotiationStatistics() async throws {
        // Given
        let localProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"])
        ]
        
        let remoteProtocols = [
            ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"])
        ]
        
        let negotiator = ProtocolNegotiator(localProtocols: localProtocols)
        
        // When
        _ = await negotiator.negotiate(with: remoteProtocols)
        _ = await negotiator.negotiate(with: remoteProtocols)
        
        let stats = await negotiator.getStatistics()
        
        // Then
        XCTAssertEqual(stats.attemptCount, 2)
        XCTAssertEqual(stats.successCount, 2)
        XCTAssertEqual(stats.failureCount, 0)
        XCTAssertEqual(stats.successRate, 1.0)
    }
    
    // MARK: - Protocol Switcher Tests
    
    func testSwitchProtocol() async throws {
        // Given
        let initialProtocol = ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"])
        let newProtocol = ProtocolInfo(from: MessagePackProtocol(), supportedVersions: ["1.0"])
        
        let switcher = ProtocolSwitcher(
            initialProtocol: initialProtocol,
            minSwitchInterval: 0.1
        )
        
        // When
        let success = try await switcher.switchTo(newProtocol)
        
        // Then
        XCTAssertTrue(success)
        let current = await switcher.getCurrentProtocol()
        XCTAssertEqual(current.name, "MessagePack")
    }
    
    func testSwitchTooFrequent() async throws {
        // Given
        let initialProtocol = ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"])
        let newProtocol = ProtocolInfo(from: MessagePackProtocol(), supportedVersions: ["1.0"])
        
        let switcher = ProtocolSwitcher(
            initialProtocol: initialProtocol,
            minSwitchInterval: 1.0
        )
        
        // When
        _ = try await switcher.switchTo(newProtocol)
        
        // Then
        do {
            _ = try await switcher.switchTo(initialProtocol)
            XCTFail("Should throw error")
        } catch ProtocolSwitchError.switchTooFrequent {
            // Expected
        }
    }
    
    func testSwitchHistory() async throws {
        // Given
        let proto1 = ProtocolInfo(from: JSONProtocol(), supportedVersions: ["1.0"])
        let proto2 = ProtocolInfo(from: MessagePackProtocol(), supportedVersions: ["1.0"])
        
        let switcher = ProtocolSwitcher(
            initialProtocol: proto1,
            minSwitchInterval: 0.1
        )
        
        // When
        _ = try await switcher.switchTo(proto2)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        _ = try await switcher.switchTo(proto1)
        
        let history = await switcher.getSwitchHistory()
        
        // Then
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].from.name, "JSON")
        XCTAssertEqual(history[0].to.name, "MessagePack")
        XCTAssertEqual(history[1].from.name, "MessagePack")
        XCTAssertEqual(history[1].to.name, "JSON")
    }
}
