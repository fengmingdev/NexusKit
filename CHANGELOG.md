# Changelog

All notable changes to NexusKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-10-21

### Added
- **Swift 6 Strict Concurrency Support** - Full actor isolation and data race safety
- **TCP Protocol** - High-performance TCP client with connection pooling
- **WebSocket Protocol** - RFC 6455 compliant WebSocket implementation
- **Socket.IO Protocol** - Full Socket.IO v4 client support
- **TLS/SSL Support** - Secure connections with certificate pinning
- **SOCKS5 Proxy** - Proxy support for all protocols
- **HTTP Client** - Basic HTTP/HTTPS client functionality
- **Middleware System** - 15 built-in interceptors and 5 core middlewares
  - Compression (GZIP)
  - Rate limiting (Token Bucket, Leaky Bucket, Sliding Window)
  - Retry policies (Exponential backoff, Linear backoff)
  - Circuit breaker pattern
  - Caching with LRU/TTL strategies
- **Reconnection Strategies** - Automatic reconnection with configurable policies
- **Zero-Copy Optimization** - Buffer pooling for reduced memory usage
- **Monitoring & Diagnostics**
  - Performance metrics
  - Network diagnostics
  - OpenTelemetry compatible tracing
  - Real-time connection monitoring
- **Comprehensive Testing** - 501+ test cases with >90% code coverage
- **CocoaPods Support** - Published to CocoaPods trunk
- **Swift Package Manager Support** - Full SPM integration

### Technical Details
- **Platforms**: iOS 13.0+, macOS 10.15+
- **Swift Version**: 6.0
- **Concurrency**: Full async/await and actor isolation
- **Architecture**: Modular design with separate modules for each protocol

### Performance
- TCP Connection: <300ms (P99 <500ms)
- Message Throughput: >15 QPS
- TLS Handshake: <1s
- Concurrent Connections: 1000+
- Long Connection Stability: >95%

### Documentation
- Getting Started Guide
- API Documentation
- Migration Guide (from Socket.IO/CocoaAsyncSocket)
- Protocol Development Guide
- Middleware Plugin Guide
- Codec Development Guide

---

## [Unreleased]

### Planned for 1.1.0
- HTTP GZIP/Deflate decompression support
- Enhanced TLS certificate validation diagnostics
- Performance monitoring export formats (CSV, Prometheus)
- Dynamic connection state reporting

### Future Enhancements
- Socket.IO Codable type support
- Distributed tracing header propagation
- WebSocket compression extensions
- HTTP/2 support

---

## Release Notes

### v1.0.0 - Production Ready Release

NexusKit 1.0.0 is a production-ready, enterprise-grade Swift networking library that combines the best features of popular networking libraries (CocoaAsyncSocket, socket.io-client-swift) with modern Swift concurrency.

**Key Highlights:**
- ✅ Swift 6 strict concurrency compliance
- ✅ Zero-copy optimization for memory efficiency
- ✅ Comprehensive middleware system
- ✅ Enterprise-grade monitoring and diagnostics
- ✅ Extensive test coverage (501+ tests)
- ✅ Full documentation and examples

**Installation:**

**CocoaPods:**
```ruby
pod 'NexusKit', '~> 1.0.0'
```

**Swift Package Manager:**
```swift
dependencies: [
    .package(url: "https://github.com/fengmingdev/NexusKit.git", from: "1.0.0")
]
```

**Links:**
- [GitHub Repository](https://github.com/fengmingdev/NexusKit)
- [CocoaPods](https://cocoapods.org/pods/NexusKit)
- [Documentation](https://github.com/fengmingdev/NexusKit/tree/main/Documentation)
- [Migration Guide](https://github.com/fengmingdev/NexusKit/blob/main/MIGRATION_GUIDE.md)

---

[1.0.0]: https://github.com/fengmingdev/NexusKit/releases/tag/1.0.0
