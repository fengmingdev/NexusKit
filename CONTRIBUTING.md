# 贡献指南

感谢您对 NexusKit 的关注！我们欢迎任何形式的贡献。

## 📋 目录

- [行为准则](#行为准则)
- [如何贡献](#如何贡献)
- [开发流程](#开发流程)
- [代码规范](#代码规范)
- [提交规范](#提交规范)
- [测试要求](#测试要求)
- [文档要求](#文档要求)

## 行为准则

### 我们的承诺

为了营造一个开放和友好的环境，我们承诺：

- 使用友好和包容的语言
- 尊重不同的观点和经验
- 优雅地接受建设性批评
- 关注对社区最有利的事情
- 对其他社区成员表示同理心

### 不可接受的行为

- 使用性暗示的语言或图像
- 挑衅、侮辱或贬损的评论
- 公开或私下的骚扰
- 未经明确许可发布他人的私人信息
- 其他在专业环境中可被合理认为不当的行为

## 如何贡献

### 报告 Bug

如果您发现 bug，请：

1. **检查现有 Issue** - 确保问题尚未被报告
2. **创建新 Issue** - 使用 Bug 模板
3. **提供详细信息**：
   - 清晰的标题和描述
   - 复现步骤
   - 预期行为 vs 实际行为
   - 环境信息（Swift 版本、平台、NexusKit 版本）
   - 相关代码片段或日志
   - 截图（如适用）

**示例**：

```markdown
## 问题描述
TCP 连接在网络切换后无法自动重连

## 复现步骤
1. 建立 TCP 连接
2. 切换网络（WiFi -> 4G）
3. 观察连接状态

## 预期行为
连接应该自动重连

## 实际行为
连接永久断开，不尝试重连

## 环境
- NexusKit: v0.2.0
- Swift: 5.9
- Platform: iOS 17.0
- Device: iPhone 15 Pro
```

### 提出功能请求

1. **检查 ROADMAP.md** - 功能可能已在计划中
2. **创建 Feature Request Issue**
3. **详细描述**：
   - 功能的用例和价值
   - 期望的 API 设计
   - 可能的实现方式
   - 示例代码

### 提交代码

1. **Fork 仓库**
2. **创建功能分支**
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. **进行修改**
4. **提交更改**（遵循提交规范）
5. **推送到分支**
   ```bash
   git push origin feature/amazing-feature
   ```
6. **创建 Pull Request**

## 开发流程

### 环境设置

1. **克隆仓库**
   ```bash
   git clone https://github.com/fengmingdev/NexusKit.git
   cd NexusKit
   ```

2. **安装依赖**
   ```bash
   swift package resolve
   ```

3. **运行测试**
   ```bash
   swift test
   ```

4. **构建项目**
   ```bash
   swift build
   ```

### 开发循环

1. **创建分支** - 从 `dev` 分支创建功能分支
2. **编写代码** - 遵循代码规范
3. **添加测试** - 确保新功能有测试覆盖
4. **运行测试** - 确保所有测试通过
5. **更新文档** - 更新相关文档
6. **提交代码** - 使用规范的提交信息
7. **创建 PR** - 详细描述更改

### 分支策略

- `main` - 稳定版本，只接受来自 `dev` 的合并
- `dev` - 开发分支，功能开发的目标分支
- `feature/*` - 功能开发分支
- `bugfix/*` - Bug 修复分支
- `hotfix/*` - 紧急修复分支

## 代码规范

### Swift 风格

遵循 [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)：

#### 命名规范

```swift
// ✅ 好的命名
class TCPConnection: Connection {
    func connect() async throws
    var isConnected: Bool
    let configuration: ConnectionConfiguration
}

// ❌ 不好的命名
class tcp_conn {
    func conn() async throws
    var connected: Bool
    let cfg: Config
}
```

#### 文档注释

所有公共 API 必须有文档注释：

```swift
/// 建立连接
///
/// 启动连接过程。此方法会阻塞直到连接建立成功或失败。
///
/// ## 使用示例
///
/// ```swift
/// let connection = try await NexusKit.shared
///     .tcp(host: "example.com", port: 8080)
///     .connect()
/// ```
///
/// - Throws:
///   - `NexusError.connectionTimeout`: 连接超时
///   - `NexusError.connectionFailed`: 连接失败
public func connect() async throws {
    // 实现
}
```

#### 代码组织

使用 MARK 注释组织代码：

```swift
// MARK: - Properties

private let connection: NWConnection
private var state: ConnectionState

// MARK: - Initialization

public init(host: String, port: UInt16) {
    // ...
}

// MARK: - Connection Protocol

public func connect() async throws {
    // ...
}

// MARK: - Private Methods

private func setupConnection() {
    // ...
}
```

### 并发

- 优先使用 `async/await` 而非闭包
- 使用 `Actor` 保护可变状态
- 标记适当的类型为 `Sendable`
- 避免使用 `@unchecked Sendable`（除非必要）

```swift
// ✅ 好的并发代码
actor ConnectionPool {
    private var connections: [Connection] = []

    func acquire() async throws -> Connection {
        // 线程安全
    }
}

// ❌ 避免
class ConnectionPool {
    private var connections: [Connection] = []
    private let lock = NSLock()

    func acquire() -> Connection {
        lock.lock()
        defer { lock.unlock() }
        // 复杂且易出错
    }
}
```

### 错误处理

- 使用类型化错误（`NexusError`）
- 提供有意义的错误信息
- 在文档中说明可能抛出的错误

```swift
// ✅ 好的错误处理
public func send(_ data: Data) async throws {
    guard isConnected else {
        throw NexusError.notConnected
    }

    do {
        try await transport.send(data)
    } catch {
        throw NexusError.sendFailed(error)
    }
}
```

### 性能考虑

- 避免不必要的内存分配
- 使用 `withUnsafeBytes` 处理大数据
- 考虑使用 `@inlinable` 优化小方法
- 避免在热路径中使用日志

## 提交规范

使用 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

```
<type>(<scope>): <subject>

<body>

<footer>
```

### 类型（Type）

- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式（不影响功能）
- `refactor`: 重构
- `perf`: 性能优化
- `test`: 添加或修改测试
- `chore`: 构建或工具变更

### 示例

```
feat(tcp): add SOCKS5 proxy support

Implement SOCKS5 proxy for TCP connections. This allows users
to route connections through a SOCKS5 proxy server.

- Add ProxyConfiguration struct
- Implement SOCKS5 handshake
- Add proxy tests

Closes #123
```

```
fix(websocket): handle connection timeout correctly

Previously, WebSocket connections would hang indefinitely on timeout.
Now properly throws NexusError.connectionTimeout.

Fixes #456
```

## 测试要求

### 单元测试

每个新功能或 Bug 修复都必须包含测试：

```swift
final class ConnectionTests: XCTestCase {
    func testConnectSuccess() async throws {
        let connection = MockConnection()
        try await connection.connect()

        let state = await connection.state
        XCTAssertEqual(state, .connected)
    }

    func testConnectTimeout() async throws {
        let connection = MockConnection(simulateTimeout: true)

        await XCTAssertThrowsError(try await connection.connect()) { error in
            guard case NexusError.connectionTimeout = error else {
                XCTFail("Expected connectionTimeout error")
                return
            }
        }
    }
}
```

### 测试覆盖率

- **目标覆盖率**: 80%+
- **核心模块**: 90%+
- **关键路径**: 100%

运行测试并查看覆盖率：

```bash
swift test --enable-code-coverage
xcrun llvm-cov report .build/debug/NexusKitPackageTests.xctest/Contents/MacOS/NexusKitPackageTests \
    -instr-profile .build/debug/codecov/default.profdata
```

### 集成测试

复杂功能需要集成测试：

```swift
func testTCPWithMiddlewarePipeline() async throws {
    let connection = try await NexusKit.shared
        .tcp(host: "echo.server.com", port: 8080)
        .middleware(LoggingMiddleware())
        .middleware(CompressionMiddleware())
        .connect()

    let testData = "Hello, World!".data(using: .utf8)!
    try await connection.send(testData, timeout: 5)

    let received = try await connection.receive(timeout: 5)
    XCTAssertEqual(received, testData)
}
```

## 文档要求

### 代码文档

- 所有公共 API 必须有文档注释
- 使用 Swift-DocC 格式
- 包含使用示例
- 说明参数、返回值、错误

### README 更新

如果添加了新功能，更新 README.md：

- 添加到功能列表
- 更新使用示例
- 更新安装说明（如适用）

### ROADMAP 更新

完成功能后更新 ROADMAP.md：

- 将功能从"计划中"移到"已完成"
- 更新进度百分比

### 示例代码

复杂功能应该提供示例：

1. 在 `Examples/` 目录创建示例项目
2. 包含 README 说明
3. 提供多个用例

## Pull Request 流程

### 创建 PR

1. **确保分支最新**
   ```bash
   git checkout dev
   git pull origin dev
   git checkout your-branch
   git rebase dev
   ```

2. **运行所有检查**
   ```bash
   swift test
   swift build
   ```

3. **创建 PR** - 使用模板，填写：
   - 更改描述
   - 相关 Issue
   - 测试情况
   - 截图（如适用）

### PR 模板

```markdown
## 描述
简要描述这个 PR 做了什么

## 关联 Issue
Closes #123

## 更改类型
- [ ] Bug 修复
- [ ] 新功能
- [ ] 重构
- [ ] 文档更新
- [ ] 性能优化

## 测试
- [ ] 添加了单元测试
- [ ] 添加了集成测试
- [ ] 所有测试通过
- [ ] 代码覆盖率 >= 80%

## 文档
- [ ] 更新了 API 文档
- [ ] 更新了 README
- [ ] 添加了示例代码

## Checklist
- [ ] 代码遵循项目风格
- [ ] 通过所有 CI 检查
- [ ] 更新了 ROADMAP（如适用）
```

### Code Review

PR 将由维护者审查：

- 代码质量和风格
- 测试覆盖率
- 文档完整性
- 性能影响
- 向后兼容性

请耐心等待审查，并根据反馈进行修改。

## 发布流程

### 版本号

遵循 [语义化版本](https://semver.org/lang/zh-CN/)：

- **MAJOR**: 不兼容的 API 变更
- **MINOR**: 向后兼容的新功能
- **PATCH**: 向后兼容的Bug修复

### 发布清单

1. 更新版本号（`Package.swift`, `NexusKit.podspec`）
2. 更新 CHANGELOG.md
3. 运行完整测试套件
4. 创建 Git tag
5. 发布到 CocoaPods
6. 创建 GitHub Release

## 获取帮助

- 📖 **文档**: 查看 README 和 Wiki
- 💬 **讨论**: 使用 GitHub Discussions
- 🐛 **问题**: 创建 GitHub Issue
- 📧 **邮件**: (待添加)

## 致谢

感谢所有贡献者！您的贡献让 NexusKit 变得更好。

## 许可证

贡献的代码将在 [MIT License](LICENSE) 下发布。

---

**再次感谢您的贡献！** 🎉
