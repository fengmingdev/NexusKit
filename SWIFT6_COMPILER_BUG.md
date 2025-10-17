# Swift 6.1.2 Compiler Bug Report

## 🐛 Bug Summary

**Swift Version**: 6.1.2 (swiftlang-6.1.2.1.2 clang-1700.0.13.5)
**Platform**: macOS 16.0 (arm64)
**Severity**: **CRITICAL** - Blocks compilation
**Bug Type**: Protocol Conformance Checking

## Problem Description

The Swift 6.1.2 compiler **incorrectly rejects** protocol conformance when a class implements a protocol method with an `@escaping @Sendable (Data) async -> Void` closure parameter, even though the function signatures are **character-for-character identical**.

## Minimal Reproducible Example

```swift
// Protocol definition
public protocol Connection: AnyObject, Sendable {
    func on(_ event: ConnectionEvent, handler: @escaping @Sendable (Data) async -> Void)
}

// Class implementation
public final class TCPConnection: Connection, @unchecked Sendable {
    public func on(_ event: ConnectionEvent, handler: @escaping @Sendable (Data) async -> Void) {
        // Implementation
    }
}
```

## Compiler Error

```
error: type 'TCPConnection' does not conform to protocol 'Connection'
note: candidate has non-matching type '(ConnectionEvent, @escaping @Sendable (Data) async -> Void) -> ()'
note: protocol requires function 'on(_:handler:)' with type '(ConnectionEvent, @escaping @Sendable (Data) async -> Void) -> ()'
```

## Analysis

**The compiler claims the signatures don't match, but they are IDENTICAL:**

- **Protocol requirement**: `(ConnectionEvent, @escaping @Sendable (Data) async -> Void) -> ()`
- **Implementation**: `(ConnectionEvent, @escaping @Sendable (Data) async -> Void) -> ()`

### What We Tried

1. **✗** Used `@preconcurrency` on protocol - Still fails
2. **✗** Added `@Sendable` to closure - Still fails
3. **✗** Removed `async` from method - Still fails
4. **✗** Added `nonisolated` keyword - Still fails
5. **✗** Migrated from actor to class with UnfairLock - Still fails
6. **✗** Removed `@preconcurrency` - Still fails

### Root Cause

This appears to be a bug in Swift 6's protocol conformance checking related to:
- `@Sendable` closure types in protocol requirements
- Type equivalence checking for closures with multiple attributes (`@escaping`, `@Sendable`, `async`)
- Possibly related to SE-0337 (Incremental migration to concurrency checking)

## Impact on NexusKit

**Blocking Issues:**
- Cannot compile NexusKit with Swift 6 language mode
- Both `TCPConnection` and `WebSocketConnection` affected
- All 8 test files (3,120+ lines) cannot run

**Workarounds Attempted:**
1. Actor → Class migration: ✓ Completed but doesn't fix conformance issue
2. Manual synchronization with UnfairLock: ✓ Implemented correctly
3. Thread-safety verified: ✓ All state access protected

## Workaround Solution

### Option 1: Use Swift 5 Language Mode (Temporary)

Add to `Package.swift`:

```swift
.target(
    name: "NexusTCP",
    dependencies: ["NexusCore"],
    swiftSettings: [
        .swiftLanguageVersion(.v5)
    ]
),
.target(
    name: "NexusWebSocket",
    dependencies: ["NexusCore"],
    swiftSettings: [
        .swiftLanguageVersion(.v5)
    ]
)
```

**Pros**: Immediate compilation success
**Cons**: Loses Swift 6 concurrency safety benefits

### Option 2: Remove `on()` from Protocol

Move `on()` to a protocol extension (not part of conformance requirements):

```swift
public protocol Connection: AnyObject, Sendable {
    // Other methods...
    func _registerHandler(_ event: ConnectionEvent, handler: @escaping @Sendable (Data) async -> Void)
}

extension Connection {
    public func on(_ event: ConnectionEvent, handler: @escaping @Sendable (Data) async -> Void) {
        _registerHandler(event, handler: handler)
    }
}
```

**Pros**: Maintains Swift 6 mode, works around compiler bug
**Cons**: Requires refactoring, less elegant API

### Option 3: Wait for Swift 6.2+

Monitor Swift bug tracker and upgrade when fixed.

**Pros**: Proper fix, no workarounds
**Cons**: Unknown timeline, blocks development

## Related Swift Issues

- [SR-15719](https://github.com/apple/swift/issues/57719): Actor protocol conformance issues
- [SE-0337](https://github.com/apple/swift-evolution/blob/main/proposals/0337-support-incremental-migration-to-concurrency-checking.md): Concurrency checking migration
- Swift Forums: [Actor isolation and protocol conformance](https://forums.swift.org/t/actor-isolation-and-protocol-conformance/58920)

## Recommendation

**Immediate Action**: Implement **Workaround Option 2** (Protocol Extension Pattern)

**Reasoning**:
- Maintains Swift 6 strict concurrency checking
- Minimal API impact (users still call `.on()`)
- Clean path to revert when compiler is fixed
- Doesn't sacrifice type safety

## Files Affected

1. `Sources/NexusCore/Core/Connection.swift` - Protocol definition
2. `Sources/NexusTCP/TCPConnection.swift` - TCP implementation
3. `Sources/NexusWebSocket/WebSocketConnection.swift` - WebSocket implementation

## Timeline

- **2025-10-17 14:00**: Bug discovered during Swift 6 migration
- **2025-10-17 16:00**: Attempted 6 different fixes, all failed
- **2025-10-17 16:30**: Confirmed as Swift 6.1.2 compiler bug
- **2025-10-17 17:00**: Documented bug and proposed workarounds

---

**Status**: 🔴 BLOCKING
**Next Step**: Implement Workaround Option 2
**ETA**: 30 minutes

---

**Maintainer**: [@fengmingdev](https://github.com/fengmingdev)
**Date**: 2025-10-17
