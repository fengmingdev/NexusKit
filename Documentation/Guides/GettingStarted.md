# Getting Started with NexusKit

Welcome to NexusKit! This guide will help you get started with the modern socket framework for Swift.

## Installation

### Swift Package Manager (Recommended)

Add NexusKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/NexusKit.git", from: "1.0.0")
]
```

Then add the modules you need to your target dependencies:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "NexusTCP", package: "NexusKit"),
            // or
            .product(name: "NexusWebSocket", package: "NexusKit"),
            // or
            .product(name: "NexusIO", package: "NexusKit")
        ]
    )
]
```

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'NexusKit/TCP'        # For TCP support
pod 'NexusKit/WebSocket'  # For WebSocket support
pod 'NexusKit/IO'         # For Socket.IO support
pod 'NexusKit/All'        # For everything
```

Then run:

```bash
pod install
```

---

## Your First Connection

### TCP Connection

```swift
import NexusTCP

// Create a connection
let connection = try await NexusKit.shared
    .connection(to: .tcp(host: "192.168.1.100", port: 8888))
    .connect()

// Check connection state
print("Connected: \(await connection.state)")

// Send a message
struct Greeting: Codable {
    let message: String
}

try await connection.send(Greeting(message: "Hello, Server!"))

// Receive messages
for await response: Greeting in connection.on("greeting_response") {
    print("Server says: \(response.message)")
}
```

### WebSocket Connection

```swift
import NexusWebSocket

let ws = try await NexusKit.shared
    .connection(to: .webSocket(url: URL(string: "wss://echo.websocket.org")!))
    .connect()

// Send text message
try await ws.send(TextMessage(content: "Hello WebSocket!"))

// Receive messages
for await message: TextMessage in ws.on("message") {
    print("Received: \(message.content)")
}
```

### Socket.IO Connection

```swift
import NexusIO

let io = try await NexusKit.shared
    .connection(to: .socketIO(url: URL(string: "https://socketio-chat-example.com")!))
    .connect()

// Emit an event
try await io.emit("chat_message", data: ChatMessage(
    from: "Alice",
    content: "Hello everyone!"
))

// Listen for events
for await message: ChatMessage in io.on("new_message") {
    print("[\(message.from)]: \(message.content)")
}
```

---

## Configuration Options

### Heartbeat

Keep the connection alive with automatic heartbeats:

```swift
let connection = try await NexusKit.shared
    .connection(to: .tcp(host: "example.com", port: 8888))
    .heartbeat(interval: 30, timeout: 60)  // Send heartbeat every 30s, timeout after 60s
    .connect()
```

### Reconnection

Configure automatic reconnection:

```swift
let connection = try await NexusKit.shared
    .connection(to: .tcp(host: "example.com", port: 8888))
    .reconnection(.exponentialBackoff(
        initialDelay: 1.0,
        maxDelay: 60.0,
        maxAttempts: 10
    ))
    .connect()
```

### Timeouts

Set connection and read/write timeouts:

```swift
let connection = try await NexusKit.shared
    .connection(to: .tcp(host: "example.com", port: 8888))
    .timeout(30)  // 30 second timeout
    .connect()
```

### TLS/SSL

Enable secure connections:

```swift
let connection = try await NexusKit.shared
    .connection(to: .tcp(host: "secure.example.com", port: 8443))
    .enableTLS()  // Use default system certificates
    .connect()

// Or with custom certificate
let certificate = try TLSCertificate(path: "/path/to/cert.pem")
let connection = try await NexusKit.shared
    .connection(to: .tcp(host: "secure.example.com", port: 8443))
    .enableTLS(certificate: certificate)
    .connect()
```

---

## Working with Messages

### Type-Safe Messaging

Define your message types using `Codable`:

```swift
struct LoginRequest: Codable {
    let username: String
    let password: String
}

struct LoginResponse: Codable {
    let success: Bool
    let token: String?
    let error: String?
}

// Send request and wait for response
let response: LoginResponse = try await connection.request(
    LoginRequest(username: "user123", password: "pass456"),
    timeout: 10
)

if response.success {
    print("Logged in! Token: \(response.token!)")
} else {
    print("Login failed: \(response.error!)")
}
```

### One-Way Messages

For messages that don't need a response:

```swift
struct Notification: Codable {
    let title: String
    let body: String
}

try await connection.emit("notify", data: Notification(
    title: "New Message",
    body: "You have a new message!"
))
```

### Subscribing to Events

Listen for server events:

```swift
// Subscribe to a specific event
for await update: StatusUpdate in connection.on("status_update") {
    print("Status: \(update.message)")
}

// Multiple event streams can run concurrently
async let messages = listenForMessages(connection)
async let notifications = listenForNotifications(connection)

await (messages, notifications)

func listenForMessages(_ conn: Connection) async {
    for await msg: ChatMessage in conn.on("chat") {
        print("Chat: \(msg.content)")
    }
}

func listenForNotifications(_ conn: Connection) async {
    for await notif: Notification in conn.on("notification") {
        print("Notification: \(notif.title)")
    }
}
```

---

## Connection State Management

### Monitoring State

```swift
// Get current state
let state = await connection.state
print("Current state: \(state)")

// Listen for state changes
for await newState in connection.stateStream {
    switch newState {
    case .disconnected:
        print("Disconnected")
    case .connecting:
        print("Connecting...")
    case .connected:
        print("Connected!")
    case .reconnecting(let attempt):
        print("Reconnecting (attempt \(attempt))...")
    case .disconnecting:
        print("Disconnecting...")
    }
}
```

### Lifecycle Hooks

```swift
connection.hooks.onConnected = {
    print("✅ Connection established")
}

connection.hooks.onDisconnected = { reason in
    print("❌ Disconnected: \(reason)")
}

connection.hooks.onReconnecting = { attempt in
    print("🔄 Reconnecting... (attempt \(attempt))")
}

connection.hooks.onError = { error in
    print("⚠️ Error: \(error)")
}
```

---

## Error Handling

NexusKit uses Swift's native error handling:

```swift
do {
    let connection = try await NexusKit.shared
        .connection(to: .tcp(host: "example.com", port: 8888))
        .connect()

    try await connection.send(message)

} catch NexusError.connectionTimeout {
    print("Connection timed out")
} catch NexusError.authenticationFailed {
    print("Authentication failed")
} catch NexusError.networkUnreachable {
    print("Network is unreachable")
} catch {
    print("Unexpected error: \(error)")
}
```

---

## Disconnection

### Graceful Disconnect

```swift
// Disconnect gracefully
await connection.disconnect(reason: .clientInitiated)
```

### Automatic Cleanup

Connections are automatically cleaned up when deallocated:

```swift
func performTask() async {
    let connection = try await NexusKit.shared
        .connection(to: endpoint)
        .connect()

    // Use connection...

    // Connection is automatically disconnected when function returns
}
```

---

## Next Steps

- [Advanced Usage](AdvancedUsage.md) - Learn about middleware, connection pools, and custom protocols
- [Custom Protocols](../Protocols/CustomProtocol.md) - Implement your own protocol adapters
- [Middleware Guide](../Middleware/MiddlewareDevelopment.md) - Create custom middleware
- [API Reference](https://yourorg.github.io/NexusKit) - Complete API documentation

---

## Examples

Check out the [Examples](../../Examples) directory for complete, runnable examples:

- [BasicTCP](../../Examples/BasicTCP) - Simple TCP client
- [ChatApp](../../Examples/ChatApp) - Socket.IO chat application
- [BinaryProtocol](../../Examples/BinaryProtocol) - Custom binary protocol
- [WebSocketDemo](../../Examples/WebSocketDemo) - WebSocket client

---

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/yourorg/NexusKit/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourorg/NexusKit/discussions)
- **Documentation**: [API Reference](https://yourorg.github.io/NexusKit)

Happy coding with NexusKit! 🚀
