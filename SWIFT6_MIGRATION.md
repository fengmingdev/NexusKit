# Swift 6 迁移指南

## ✅ 迁移完成

**状态**: 已完成 Swift 6 并发安全迁移  
**日期**: 2025-10-17  
**版本**: Swift 5.7+ / Swift 6 兼容

### 成果

- ✅ 所有并发安全问题已修复
- ✅ 构建无警告、无错误
- ✅ 使用 `@Sendable` 标记确保线程安全
- ✅ Actor 隔离正确实现
- ✅ 代码质量优化完成

---

## 🚨 原问题描述（已解决）

### Actor 协议一致性问题

**问题描述**：
在 Swift 6 中，`TCPConnection` 和 `WebSocketConnection` 的 actor 实现无法满足 `Connection` 协议的要求。

**错误信息**：
```
error: type 'TCPConnection' does not conform to protocol 'Connection'
note: candidate has non-matching type '(ConnectionEvent, @escaping (Data) async -> Void) async -> ()'
note: protocol requires function 'on(_:handler:)' with type '(ConnectionEvent, @escaping (Data) async -> Void) async -> ()'
```

**根本原因**：
Swift 6 引入了严格的并发隔离检查。当 actor 实现协议的 `async` 方法时：
- 协议定义：`func on(_ event: ConnectionEvent, handler: @escaping (Data) async -> Void) async`
- Actor 实现：方法自动变为 actor-isolated，其类型签名在编译器看来与协议不同
- 即使语法相同，类型系统将它们视为不同类型

这是 Swift 6 的已知限制，源于 actor 隔离域的类型安全保证。

---

## 🛠️ 解决方案

### 方案 1：使用 Class + 手动同步（推荐）✅

**优点**：
- 完全兼容 Swift 6
- 性能可控
- 灵活的并发控制

**缺点**：
- 需要手动管理锁
- 代码略复杂

**实施步骤**：

1. 将 `public actor TCPConnection` 改为 `public final class TCPConnection`
2. 添加内部锁保护状态：
   ```swift
   private let lock = UnfairLock()
   private var _state: ConnectionState = .disconnected

   public var state: ConnectionState {
       get async {
           lock.withLock { _state }
       }
   }
   ```

3. 所有状态修改使用锁保护：
   ```swift
   private func updateState(_ newState: ConnectionState) {
       lock.withLock {
           _state = newState
       }
   }
   ```

4. `on()` 方法变为非隔离：
   ```swift
   public func on(_ event: ConnectionEvent, handler: @escaping (Data) async -> Void) async {
       lock.withLock {
           if eventHandlers[event] == nil {
               eventHandlers[event] = []
           }
           eventHandlers[event]?.append(handler)
       }
   }
   ```

**工作量**：中等（每个连接类约 50-100 行改动）

---

### 方案 2：协议扩展 + 内部实现 ✅ **已采用**

**优点**：
- 保持类为 `@unchecked Sendable`
- 类型安全
- API 变化最小

**实施结果**：

1. ✅ 修改协议 `_registerHandler` 签名添加 `@Sendable`：
   ```swift
   public protocol Connection {
       // ... 其他方法
       func _registerHandler(_ event: ConnectionEvent, handler: @escaping @Sendable (Data) async -> Void)
   }
   ```

2. ✅ 更新实现类的事件处理器类型：
   ```swift
   private var eventHandlers: [ConnectionEvent: [@Sendable (Data) async -> Void]] = [:]
   
   public func _registerHandler(_ event: ConnectionEvent, handler: @escaping @Sendable (Data) async -> Void) {
       lock.withLock {
           if eventHandlers[event] == nil {
               eventHandlers[event] = []
           }
           eventHandlers[event]?.append(handler)
       }
   }
   ```

3. ✅ 通过扩展提供公共 API：
   ```swift
   extension Connection {
       public func on(_ event: ConnectionEvent, handler: @escaping @Sendable (Data) async -> Void) {
           _registerHandler(event, handler: handler)
       }
   }
   ```

**工作量**：小（已完成，共修改 6 个文件）

---

### 方案 3：等待 Swift 编译器改进

**优点**：
- 无需修改代码
- 保持 actor 优势

**缺点**：
- 时间不确定
- 可能需要等待 Swift 7+

**当前状态**：
- Swift 6.1.2 仍存在此问题
- 已在 Swift 论坛报告：[Actor protocol conformance with async methods](https://forums.swift.org/t/actor-protocol-conformance-with-async-methods)

---

## 📋 实施记录

### ✅ 已完成的工作

采用 **方案 2**：协议扩展 + `@Sendable` 标记

**优先级**：P0（阻塞编译）- 已完成

**步骤**：
1. ✅ 创建本文档记录问题
2. ✅ 修复 `MetricsMiddleware.swift` 的 actor 并发问题
   - ✅ 将 `reportTimer` 初始化移到 `startReporting()` 方法
   - ✅ 标记 `printReport()` 和 `printFinalReport()` 为 async
3. ✅ 更新 `Connection.swift` 协议定义
   - ✅ 在 `_registerHandler` 中添加 `@Sendable` 标记
4. ✅ 重构 `TCPConnection.swift`
   - ✅ 更新 `eventHandlers` 类型为 Sendable 兼容
   - ✅ 实现 `@Sendable` 版本的 `_registerHandler`
5. ✅ 重构 `WebSocketConnection.swift`
   - ✅ 同上步骤
6. ✅ 代码质量优化
   - ✅ 修复 `EncryptionMiddleware.swift` 未使用变量警告
   - ✅ 重构 `ConnectionManager.swift` 消除死代码警告
7. ✅ 验证构建
   - ✅ `swift build` - 无警告无错误
8. ✅ 更新文档

**实际时间**：约 2 小时

**修改文件**：
- `Sources/NexusCore/Middleware/Middlewares/MetricsMiddleware.swift`
- `Sources/NexusCore/Core/Connection.swift`
- `Sources/NexusTCP/TCPConnection.swift`
- `Sources/NexusWebSocket/WebSocketConnection.swift`
- `Sources/NexusCore/Middleware/Middlewares/EncryptionMiddleware.swift`
- `Sources/NexusCore/Core/ConnectionManager.swift`

---

### 长期
关注 **方案 3**：Swift 编译器改进

**优先级**：P2（监控）

**行动**：
- 跟踪 Swift Evolution 提案
- 升级到新版本 Swift 时测试
- 如果支持改进，回退到 actor 实现

---

## 🔍 相关资源

### Swift 论坛讨论
- [Actor isolation and protocol conformance](https://forums.swift.org/t/actor-isolation-and-protocol-conformance/58920)
- [Protocol requirements cannot be satisfied by actor methods](https://forums.swift.org/t/protocol-requirements-cannot-be-satisfied-by-actor-methods/59234)

### Swift Evolution 提案
- [SE-0306: Actors](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)
- [SE-0337: Incremental migration to concurrency checking](https://github.com/apple/swift-evolution/blob/main/proposals/0337-support-incremental-migration-to-concurrency-checking.md)

### Apple 文档
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Actors and Data Race Safety](https://developer.apple.com/documentation/swift/actors)

---

## 📝 变更日志

### 2025-10-17
- 🆕 创建文档
- 🔍 识别 Swift 6 actor 一致性问题
- 📋 制定三种解决方案
- ✅ 完成 Swift 6 并发安全迁移
- ✅ 修复所有编译警告和错误
- ✅ 代码质量优化
- ✅ 构建验证通过（无警告无错误）
- 📚 更新迁移文档

---

## 💡 贡献

如果你有更好的解决方案或发现 Swift 编译器已修复此问题，请：
1. 提交 Issue 或 PR
2. 在 Swift 论坛分享经验
3. 更新本文档

---

**维护者**: [@fengmingdev](https://github.com/fengmingdev)
**最后更新**: 2025-10-17
