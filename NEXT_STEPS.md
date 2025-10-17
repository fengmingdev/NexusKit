# NexusKit 下一步计划

## 📅 更新时间：2025-10-17

---

## 🚨 P0 - 紧急任务（本周完成）

### 1. 修复 Swift 6 Actor 隔离问题
**优先级**: 🔴 P0（阻塞编译）
**预计时间**: 2-3 小时
**负责人**: @fengmingdev

**任务清单**:
- [ ] 重构 `TCPConnection` 从 actor 到 class
  - [ ] 添加 `private let lock = UnfairLock()`
  - [ ] 保护所有状态访问 (`_state`, `eventHandlers`, etc.)
  - [ ] 更新所有方法使用锁
  - [ ] 测试并发安全性
- [ ] 重构 `WebSocketConnection` 从 actor 到 class
  - [ ] 同上步骤
  - [ ] 特别注意 pingTimer 的线程安全
- [ ] 验证编译成功
- [ ] 运行完整测试套件
- [ ] 性能基准测试（确保没有性能退化）

**验收标准**:
- ✅ `swift build` 成功，无错误
- ✅ 所有测试通过
- ✅ 性能与 actor 版本相当（<5% 差异）

---

## 🔥 P1 - 高优先级（本月完成）

### 2. 完成测试覆盖
**优先级**: 🟠 P1
**预计时间**: 3-4 小时

**任务清单**:
- [ ] WebSocket 模块测试
  - [ ] WebSocketConnectionTests（类似 TCPConnectionTests）
  - [ ] Ping/Pong 机制测试
  - [ ] 文本/二进制消息测试
  - [ ] 子协议测试
  - [ ] 自定义头部测试
- [ ] 中间件集成测试
  - [ ] 多个中间件组合测试
  - [ ] 中间件优先级测试
  - [ ] 条件中间件测试
- [ ] 运行测试覆盖率分析
  - [ ] 目标：80% 代码覆盖率
  - [ ] 生成覆盖率报告

**验收标准**:
- ✅ 测试覆盖率 ≥ 80%
- ✅ 所有核心功能有测试
- ✅ 边界情况和错误路径有测试

---

### 3. 性能优化和基准测试
**优先级**: 🟠 P1
**预计时间**: 2-3 小时

**任务清单**:
- [ ] 创建性能基准测试套件
  - [ ] 连接建立延迟
  - [ ] 消息吞吐量
  - [ ] 内存占用
  - [ ] CPU 使用率
- [ ] 识别性能瓶颈
- [ ] 优化关键路径
  - [ ] 零拷贝优化
  - [ ] 缓冲区复用
  - [ ] 锁竞争减少
- [ ] 生成性能报告

**目标指标**:
- 连接延迟: < 50ms
- 消息吞吐量: > 50,000 msg/s
- 内存占用: < 5MB (100 连接)
- CPU 使用: < 2% (空闲)

---

## 🎯 立即行动（今天）

### 修复 Actor 隔离问题 - 详细步骤

#### 步骤 1: TCPConnection 重构 (1.5 小时)

```swift
// 1. 修改类声明
- public actor TCPConnection: @preconcurrency Connection {
+ public final class TCPConnection: Connection, @unchecked Sendable {

// 2. 添加锁
+ private let lock = UnfairLock()

// 3. 保护状态访问
- private var _state: ConnectionState = .disconnected
+ private var _state: ConnectionState = .disconnected  // 保持不变

public var state: ConnectionState {
    get async {
-       _state
+       lock.withLock { _state }
    }
}

// 4. 保护所有写操作
private func updateState(_ newState: ConnectionState) {
    lock.withLock {
        _state = newState
    }
}

// 5. 保护 eventHandlers
public func on(_ event: ConnectionEvent, handler: @escaping (Data) async -> Void) async {
    lock.withLock {
        if eventHandlers[event] == nil {
            eventHandlers[event] = []
        }
        eventHandlers[event]?.append(handler)
    }
}
```

#### 步骤 2: WebSocketConnection 重构 (1.5 小时)
- 同样的步骤
- 额外注意 pingTimer 的线程安全

#### 步骤 3: 验证 (1 小时)
```bash
swift build                      # 应该成功
swift test                        # 所有测试应通过
swift test --enable-code-coverage # 生成覆盖率
```

---

## 📊 本周目标（2025-10-17 - 2025-10-23）

- [x] 完成 TCP 模块测试（1,320+ 行）
- [x] 创建 Swift 6 迁移指南
- [ ] 修复 actor 隔离问题 ← **今天完成**
- [ ] 运行完整测试套件
- [ ] 生成覆盖率报告

---

## 📈 里程碑

### v0.2.0（目标：2025-10-31）
- [x] WebSocket 完整支持
- [x] 核心模块测试
- [x] TCP 模块测试
- [ ] 修复编译问题 ← **当前焦点**
- [ ] 80% 测试覆盖率
- [ ] 性能基准

### v0.3.0（目标：2025-11-30）
- [ ] Socket.IO 支持
- [ ] 连接池
- [ ] 高级中间件

### v1.0.0（目标：2025-12-31）
- [ ] 生产级稳定性
- [ ] 完整文档
- [ ] 企业级支持

---

**维护者**: [@fengmingdev](https://github.com/fengmingdev)
**最后更新**: 2025-10-17
