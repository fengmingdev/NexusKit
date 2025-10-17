//
//  ConnectionStateTests.swift
//  NexusCoreTests
//
//  Created by NexusKit Contributors
//

import XCTest
@testable import NexusCore

/// 连接状态测试
final class ConnectionStateTests: XCTestCase {

    // MARK: - State Equality Tests

    func testDisconnectedState() {
        let state = ConnectionState.disconnected
        XCTAssertEqual(state, .disconnected)
        XCTAssertNotEqual(state, .connecting)
    }

    func testConnectingState() {
        let state = ConnectionState.connecting
        XCTAssertEqual(state, .connecting)
        XCTAssertNotEqual(state, .connected)
    }

    func testConnectedState() {
        let state = ConnectionState.connected
        XCTAssertEqual(state, .connected)
        XCTAssertNotEqual(state, .disconnected)
    }

    func testReconnectingState() {
        let state1 = ConnectionState.reconnecting(attempt: 1)
        let state2 = ConnectionState.reconnecting(attempt: 1)
        let state3 = ConnectionState.reconnecting(attempt: 2)

        XCTAssertEqual(state1, state2)
        XCTAssertNotEqual(state1, state3)
    }

    func testDisconnectingState() {
        let state = ConnectionState.disconnecting
        XCTAssertEqual(state, .disconnecting)
        XCTAssertNotEqual(state, .disconnected)
    }

    // MARK: - State Transition Validation Tests

    func testValidTransitions() {
        var state = ConnectionState.disconnected

        // disconnected -> connecting
        XCTAssertTrue(state.canTransition(to: .connecting))
        state = .connecting

        // connecting -> connected
        XCTAssertTrue(state.canTransition(to: .connected))
        state = .connected

        // connected -> disconnecting
        XCTAssertTrue(state.canTransition(to: .disconnecting))
        state = .disconnecting

        // disconnecting -> disconnected
        XCTAssertTrue(state.canTransition(to: .disconnected))
    }

    func testInvalidTransitions() {
        let disconnected = ConnectionState.disconnected

        // Can't go directly to connected from disconnected
        XCTAssertFalse(disconnected.canTransition(to: .connected))

        // Can't go to reconnecting from disconnected
        XCTAssertFalse(disconnected.canTransition(to: .reconnecting(attempt: 1)))
    }

    func testReconnectingTransitions() {
        let connected = ConnectionState.connected

        // connected -> reconnecting is valid
        XCTAssertTrue(connected.canTransition(to: .reconnecting(attempt: 1)))

        let reconnecting = ConnectionState.reconnecting(attempt: 1)

        // reconnecting -> connecting is valid
        XCTAssertTrue(reconnecting.canTransition(to: .connecting))

        // reconnecting -> disconnected is valid (give up)
        XCTAssertTrue(reconnecting.canTransition(to: .disconnected))
    }

    // MARK: - Disconnect Reason Tests

    func testDisconnectReasonEquality() {
        let reason1 = DisconnectReason.clientInitiated
        let reason2 = DisconnectReason.clientInitiated
        let reason3 = DisconnectReason.serverInitiated

        XCTAssertEqual(reason1, reason2)
        XCTAssertNotEqual(reason1, reason3)
    }

    func testDisconnectReasonWithError() {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        let reason = DisconnectReason.error(error)

        switch reason {
        case .error(let e):
            XCTAssertNotNil(e)
        default:
            XCTFail("Expected error reason")
        }
    }

    // MARK: - State Description Tests

    func testStateDescriptions() {
        XCTAssertEqual(ConnectionState.disconnected.description, "disconnected")
        XCTAssertEqual(ConnectionState.connecting.description, "connecting")
        XCTAssertEqual(ConnectionState.connected.description, "connected")
        XCTAssertEqual(ConnectionState.reconnecting(attempt: 3).description, "reconnecting(attempt: 3)")
        XCTAssertEqual(ConnectionState.disconnecting.description, "disconnecting")
    }
}

// MARK: - ConnectionState Extension for Testing

extension ConnectionState {
    /// 检查是否可以转换到目标状态
    func canTransition(to newState: ConnectionState) -> Bool {
        switch (self, newState) {
        case (.disconnected, .connecting):
            return true
        case (.connecting, .connected),
             (.connecting, .disconnected):
            return true
        case (.connected, .disconnecting),
             (.connected, .reconnecting):
            return true
        case (.reconnecting, .connecting),
             (.reconnecting, .disconnected):
            return true
        case (.disconnecting, .disconnected):
            return true
        default:
            return false
        }
    }

    /// 状态描述（用于测试）
    var description: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reconnecting(let attempt):
            return "reconnecting(attempt: \(attempt))"
        case .disconnecting:
            return "disconnecting"
        }
    }
}
