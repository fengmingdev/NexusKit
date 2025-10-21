# NexusKit Developer Guide

Complete guide for extending and contributing to NexusKit.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Architecture Overview](#architecture-overview)
3. [Protocol Development](#protocol-development)
4. [Middleware Development](#middleware-development)
5. [Codec Development](#codec-development)
6. [Testing Guidelines](#testing-guidelines)
7. [Contributing](#contributing)

---

## Getting Started

### Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/fengmingdev/NexusKit.git
   cd NexusKit
   ```

2. **Build the project:**
   ```bash
   swift build
   ```

3. **Run tests:**
   ```bash
   swift test
   ```

4. **Start test servers (for integration tests):**
   ```bash
   cd TestServers
   npm install
   npm start
   ```

### Project Structure

```
NexusKit/
├── Sources/
│   ├── NexusCore/          # Core abstractions and utilities
│   ├── NexusTCP/           # TCP protocol implementation
│   ├── NexusWebSocket/     # WebSocket protocol
│   ├── NexusIO/            # Socket.IO protocol
│   └── NexusHTTP/          # HTTP client
├── Tests/                  # Unit and integration tests
├── Docs/                   # API documentation
├── Documentation/          # Guides and examples
└── Examples/               # Sample applications
```

---

## Architecture Overview

### Core Abstractions

NexusKit is built on several core protocols:

#### Connection Protocol
```swift
protocol Connection: Actor {
    var id: String { get }
    var state: ConnectionState { get async }

    func connect() async throws
    func disconnect(reason: DisconnectReason) async
    func send(_ data: Data, timeout: TimeInterval?) async throws
    func receive(timeout: TimeInterval?) async throws -> Data
}
```

#### Endpoint
Represents connection targets:
```swift
enum Endpoint {
    case tcp(host: String, port: UInt16)
    case webSocket(url: URL)
    case socketIO(url: URL, namespace: String)
}
```

### Middleware Pipeline

Middleware intercepts and processes messages:

```swift
protocol Middleware: Sendable {
    func processOutgoing(
        _ data: Data,
        context: MiddlewareContext
    ) async throws -> Data

    func processIncoming(
        _ data: Data,
        context: MiddlewareContext
    ) async throws -> Data
}
```

---

## Protocol Development

### Creating a New Protocol

See [Docs/ProtocolDevelopmentGuide.md](./Docs/ProtocolDevelopmentGuide.md) for detailed instructions.

**Quick Overview:**

1. **Create Connection Factory:**
   ```swift
   public final class MyProtocolConnectionFactory: ConnectionFactory {
       public func createConnection(
           endpoint: Endpoint,
           configuration: ConnectionConfiguration
       ) async throws -> any Connection {
           // Implementation
       }
   }
   ```

2. **Implement Connection:**
   ```swift
   public final class MyProtocolConnection: Connection {
       // Implement Connection protocol
   }
   ```

3. **Register with NexusKit:**
   ```swift
   extension NexusKit {
       public func myProtocol(/* params */) -> ConnectionBuilder {
           // Return configured builder
       }
   }
   ```

### Protocol Adapter Pattern

For complex protocols, implement a `ProtocolAdapter`:

```swift
protocol ProtocolAdapter: Sendable {
    func encode<T: Encodable>(
        _ message: T,
        context: EncodingContext
    ) throws -> Data

    func decode<T: Decodable>(
        _ data: Data,
        as type: T.Type,
        context: DecodingContext
    ) throws -> T

    func handleIncoming(_ data: Data) async throws -> [ProtocolEvent]
}
```

---

## Middleware Development

### Creating Custom Middleware

See [Docs/MiddlewarePluginGuide.md](./Docs/MiddlewarePluginGuide.md) for detailed instructions.

**Basic Template:**

```swift
public struct MyMiddleware: Middleware {
    public init() {}

    public func processOutgoing(
        _ data: Data,
        context: MiddlewareContext
    ) async throws -> Data {
        // Transform outgoing data
        return data
    }

    public func processIncoming(
        _ data: Data,
        context: MiddlewareContext
    ) async throws -> Data {
        // Transform incoming data
        return data
    }
}
```

### Lifecycle Hooks

Implement lifecycle callbacks:

```swift
extension MyMiddleware {
    public func onConnect(connection: any Connection) async {
        // Called when connection establishes
    }

    public func onDisconnect(
        connection: any Connection,
        reason: DisconnectReason
    ) async {
        // Called when connection closes
    }

    public func onError(error: Error, context: MiddlewareContext) async {
        // Called on errors
    }
}
```

### Built-in Middlewares

NexusKit provides several middlewares:

- **Compression** - GZIP compression
- **RateLimit** - Token Bucket, Leaky Bucket, Sliding Window
- **Retry** - Exponential/Linear backoff
- **Cache** - LRU/TTL caching
- **CircuitBreaker** - Fault tolerance
- **Logging** - Request/response logging
- **Metrics** - Performance monitoring

---

## Codec Development

### Creating Custom Codecs

See [Docs/CodecDevelopmentGuide.md](./Docs/CodecDevelopmentGuide.md) for detailed instructions.

**Example - Custom Binary Protocol:**

```swift
public struct MyBinaryProtocol: ProtocolAdapter {
    public init() {}

    public func encode<T: Encodable>(
        _ message: T,
        context: EncodingContext
    ) throws -> Data {
        // Encode message to binary format
        var buffer = Data()
        // ... encoding logic
        return buffer
    }

    public func decode<T: Decodable>(
        _ data: Data,
        as type: T.Type,
        context: DecodingContext
    ) throws -> T {
        // Decode binary data to model
        // ... decoding logic
    }

    public func handleIncoming(_ data: Data) async throws -> [ProtocolEvent] {
        // Parse protocol events from raw data
        // ... parsing logic
    }
}
```

### Frame-based Protocols

For protocols with length-prefixed frames:

```swift
struct FrameHeader {
    let version: UInt8
    let type: UInt8
    let length: UInt32
}

func decodeFrame(_ data: Data) throws -> (header: FrameHeader, payload: Data) {
    // ... frame parsing
}
```

---

## Testing Guidelines

### Writing Unit Tests

```swift
import XCTest
@testable import NexusKit

final class MyFeatureTests: XCTestCase {
    func testBasicFunctionality() async throws {
        // Arrange
        let sut = MyFeature()

        // Act
        let result = try await sut.perform()

        // Assert
        XCTAssertEqual(result, expectedValue)
    }
}
```

### Integration Tests

For network protocols, use test servers:

```swift
func testTCPConnection() async throws {
    // Start test server
    guard await TestUtils.isTCPServerRunning() else {
        throw XCTSkip("Test server not running")
    }

    // Test connection
    let connection = try await TestUtils.createTestConnection()
    defer { await connection.disconnect(reason: .clientInitiated) }

    // Verify behavior
    // ...
}
```

### Test Coverage

Target coverage levels:
- **Unit Tests**: >90%
- **Integration Tests**: Key scenarios
- **Performance Tests**: Critical paths

Run coverage report:
```bash
swift test --enable-code-coverage
xcrun llvm-cov report .build/debug/NexusKitPackageTests.xctest/Contents/MacOS/NexusKitPackageTests
```

---

## Contributing

### Code Style

- Follow Swift API Design Guidelines
- Use meaningful variable/function names
- Add documentation comments for public APIs
- Keep functions focused and concise

### Documentation

All public APIs must include:
```swift
/// Brief description of the function.
///
/// Detailed explanation if needed.
///
/// - Parameters:
///   - param1: Description of param1
///   - param2: Description of param2
/// - Returns: Description of return value
/// - Throws: Description of possible errors
public func myFunction(param1: String, param2: Int) throws -> String {
    // ...
}
```

### Commit Messages

Follow conventional commits:
```
type(scope): subject

body

footer
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Examples:
```
feat(tcp): add connection pooling support
fix(websocket): resolve reconnection race condition
docs(readme): update installation instructions
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Update documentation
6. Submit pull request

See [CONTRIBUTING.md](./CONTRIBUTING.md) for detailed guidelines.

---

## Best Practices

### Swift 6 Concurrency

- Use `actor` for mutable shared state
- Mark closures as `@Sendable` when appropriate
- Avoid `@unchecked Sendable` unless necessary
- Use structured concurrency (`async let`, `TaskGroup`)

### Memory Management

- Use buffer pools for frequent allocations
- Implement zero-copy optimizations where possible
- Avoid retain cycles with `[weak self]` in closures
- Profile memory usage in performance tests

### Error Handling

- Use typed errors when possible
- Provide meaningful error messages
- Log errors with appropriate levels
- Implement graceful degradation

### Performance

- Benchmark critical paths
- Optimize hot loops
- Use lazy initialization where appropriate
- Profile with Instruments

---

## Resources

- [API Documentation](https://fengmingdev.github.io/NexusKit/)
- [GitHub Issues](https://github.com/fengmingdev/NexusKit/issues)
- [Discussion Forum](https://github.com/fengmingdev/NexusKit/discussions)
- [Changelog](./CHANGELOG.md)

---

## License

NexusKit is released under the MIT License. See [LICENSE](./LICENSE) for details.
