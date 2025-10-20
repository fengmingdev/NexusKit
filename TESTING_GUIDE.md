# NexusKit 测试指南

> 完整的测试运行和验证指南

---

## 📋 测试概览

### 测试结构

```
Tests/
├── TestHelpers/           # 测试辅助工具 (~850行)
│   ├── TestFixtures.swift      # 测试数据和常量
│   ├── TLSTestHelper.swift     # TLS测试辅助
│   └── TestUtils.swift         # 通用测试工具
│
├── IntegrationTests/      # 集成测试 (~2000行)
│   ├── TCPIntegrationTests.swift       # TCP连接测试
│   ├── HeartbeatIntegrationTests.swift # 心跳机制测试
│   ├── TLSIntegrationTests.swift       # TLS/SSL测试
│   └── SOCKS5IntegrationTests.swift    # SOCKS5代理测试
│
└── BenchmarkTests/        # 性能基准测试 (待创建)
    └── PerformanceBenchmarks.swift
```

### 测试统计

| 测试类型 | 文件数 | 测试用例 | 代码行数 | 状态 |
|---------|--------|---------|---------|------|
| 测试辅助 | 3 | - | ~850 | ✅ 完成 |
| 集成测试 | 4 | ~80 | ~2000 | ✅ 完成 |
| 基准测试 | 0 | 0 | 0 | ⏳ 待创建 |
| **总计** | **7** | **~80** | **~2850** | **70%** |

---

## 🚀 快速开始

### 1. 启动测试服务器

集成测试依赖Node.js测试服务器，运行测试前必须先启动：

```bash
cd TestServers

# 安装依赖（首次运行）
npm install

# 启动所有集成测试需要的服务器
npm run integration
```

这会启动3个服务器：
- **TCP服务器**: 127.0.0.1:8888
- **TLS服务器**: 127.0.0.1:8889 (带自签名证书)
- **SOCKS5代理**: 127.0.0.1:1080

### 2. 运行集成测试

在另一个终端窗口：

```bash
# 运行所有集成测试
swift test --filter IntegrationTests

# 运行特定测试类
swift test --filter TCPIntegrationTests
swift test --filter HeartbeatIntegrationTests
swift test --filter TLSIntegrationTests
swift test --filter SOCKS5IntegrationTests

# 运行单个测试用例
swift test --filter TCPIntegrationTests/testBasicConnection
```

### 3. 查看测试结果

测试输出示例：
```
Test Suite 'TCPIntegrationTests' started
 [✅ PASS] 基础TCP连接 (0.123s)
 [✅ PASS] 连接超时 (1.012s)
 [✅ PASS] 多次连接和断开 (0.856s)
 [✅ PASS] 发送和接收简单消息 (0.234s)
 ...
Test Suite 'TCPIntegrationTests' passed
```

---

## 📦 详细测试说明

### TCP集成测试 (TCPIntegrationTests)

**测试数量**: 约20个
**测试时间**: 约2-3分钟
**服务器依赖**: tcp_server.js (8888)

**测试场景**:

#### 基础连接
- `testBasicConnection` - 基础TCP连接
- `testConnectionTimeout` - 连接超时
- `testMultipleConnections` - 多次连接和断开

#### 消息收发
- `testSendAndReceiveSimpleMessage` - 简单消息
- `testSendLargeMessage` - 大消息（64KB）
- `testSendUnicodeMessage` - Unicode消息

#### 心跳
- `testHeartbeat` - 基础心跳
- `testMultipleHeartbeats` - 多次心跳

#### 并发
- `testConcurrentConnections` - 并发连接（10个）
- `testConcurrentMessages` - 并发消息（50条）

#### 性能
- `testConnectionSpeed` - 连接建立速度（目标 <500ms）
- `testMessageThroughput` - 消息吞吐量（目标 >10 QPS）

#### 稳定性
- `testLongLivedConnection` - 长时间连接（30秒）

#### 错误处理
- `testInvalidMessageFormat` - 无效消息格式
- `testSendAfterDisconnect` - 断开后发送

---

### 心跳集成测试 (HeartbeatIntegrationTests)

**测试数量**: 约15个
**测试时间**: 约3-4分钟
**服务器依赖**: tcp_server.js (8888)

**测试场景**:

#### 基础心跳
- `testBasicHeartbeat` - 基础心跳发送（间隔2秒）
- `testHeartbeatResponse` - 心跳响应验证

#### 超时检测
- `testHeartbeatTimeout` - 心跳超时检测

#### 自适应心跳
- `testHeartbeatIntervalAdjustment` - 心跳间隔调整（1s/2s/5s）
- `testHeartbeatStatistics` - 心跳统计（成功率 >90%）

#### 双向心跳
- `testClientInitiatedHeartbeat` - 客户端主动心跳
- `testServerHeartbeatResponse` - 服务器心跳响应

#### 性能
- `testHeartbeatPerformanceOverhead` - 心跳性能开销（目标 <20%）
- `testHighFrequencyHeartbeat` - 高频心跳（100ms间隔）

#### 稳定性
- `testLongTermHeartbeatStability` - 长时间心跳稳定性（1分钟）

---

### TLS集成测试 (TLSIntegrationTests)

**测试数量**: 约15个
**测试时间**: 约3-4分钟
**服务器依赖**: tls_server.js (8889)

**测试场景**:

#### 基础TLS
- `testBasicTLSConnection` - 基础TLS连接（自签名）
- `testTLSVersionNegotiation` - TLS版本协商（1.2/1.3）

#### 证书
- `testCertificatePinning` - 证书固定（正确）
- `testInvalidCertificatePinning` - 证书固定（错误）

#### 密码套件
- `testModernCipherSuites` - 现代密码套件
- `testCompatibleCipherSuites` - 兼容密码套件

#### 消息收发
- `testTLSMessageSendReceive` - TLS加密消息
- `testTLSLargeMessageTransfer` - TLS大消息（128KB）

#### 心跳
- `testTLSHeartbeat` - TLS连接心跳

#### 性能
- `testTLSHandshakePerformance` - TLS握手性能（目标 <1s）
- `testTLSVsPlainPerformance` - TLS vs 非TLS对比（开销 <50%）

#### 稳定性
- `testTLSLongLivedConnection` - TLS长连接（30秒）

#### 并发
- `testTLSConcurrentConnections` - TLS并发连接（10个）

---

### SOCKS5集成测试 (SOCKS5IntegrationTests)

**测试数量**: 约15个
**测试时间**: 约4-5分钟
**服务器依赖**: socks5_server.js (1080) + tcp_server.js (8888)

**测试场景**:

#### 基础代理
- `testBasicSOCKS5Connection` - 无认证SOCKS5连接
- `testSOCKS5IPv4Address` - IPv4地址
- `testSOCKS5DomainName` - 域名

#### 消息收发
- `testSOCKS5MessageSendReceive` - SOCKS5消息收发
- `testSOCKS5LargeMessage` - SOCKS5大消息（64KB）

#### 心跳
- `testSOCKS5Heartbeat` - SOCKS5连接心跳
- `testSOCKS5MultipleHeartbeats` - 多次心跳

#### 性能
- `testSOCKS5ConnectionSpeed` - SOCKS5连接速度（目标 <2s）
- `testSOCKS5VsDirectPerformance` - SOCKS5 vs 直连对比（开销 <60%）

#### 稳定性
- `testSOCKS5LongLivedConnection` - SOCKS5长连接（30秒）

#### 并发
- `testSOCKS5ConcurrentConnections` - SOCKS5并发连接（5个）

#### 错误处理
- `testSOCKS5InvalidTarget` - 无效目标
- `testSOCKS5InvalidProxy` - 无效代理

#### 组合
- `testSOCKS5WithTLS` - SOCKS5 + TLS组合

---

## 🎯 测试成功标准

### 功能性
- ✅ 所有测试用例通过（~80个）
- ✅ 无崩溃或内存泄漏
- ✅ 错误处理正确

### 性能指标

| 指标 | 目标 | 实际 | 状态 |
|------|------|------|------|
| TCP连接速度 | <500ms | 待测试 | ⏳ |
| 消息吞吐量 | >10 QPS | 待测试 | ⏳ |
| 心跳成功率 | >90% | 待测试 | ⏳ |
| 心跳性能开销 | <20% | 待测试 | ⏳ |
| TLS握手速度 | <1s | 待测试 | ⏳ |
| TLS性能开销 | <50% | 待测试 | ⏳ |
| SOCKS5连接速度 | <2s | 待测试 | ⏳ |
| SOCKS5性能开销 | <60% | 待测试 | ⏳ |

### 稳定性
- ✅ 长连接30秒成功率 >90%
- ✅ 并发连接无竞态条件
- ✅ 内存占用稳定

---

## 🛠️ 故障排查

### 测试服务器未运行

**错误**: `XCTSkip: TCP测试服务器未运行`

**解决方案**:
```bash
cd TestServers
npm run integration
```

### 端口被占用

**错误**: `EADDRINUSE: address already in use`

**解决方案**:
```bash
# 查看端口占用
lsof -i:8888 -i:8889 -i:1080

# 杀死占用进程
kill -9 <PID>
```

### 测试超时

**原因**: 网络延迟或服务器响应慢

**解决方案**:
- 检查服务器日志
- 增加测试超时时间
- 检查系统资源占用

### 证书错误

**错误**: TLS证书验证失败

**解决方案**:
```bash
# 重新生成证书
cd TestServers/certs
openssl req -x509 -newkey rsa:2048 -keyout server-key.pem -out server-cert.pem -days 365 -nodes -subj "/CN=localhost/O=NexusKit Test/C=US"
```

---

## 📊 测试报告

### 生成测试报告

```bash
# 生成详细报告
swift test --filter IntegrationTests 2>&1 | tee test-report.txt

# 统计测试结果
grep -E "(PASS|FAIL)" test-report.txt | wc -l
```

### 代码覆盖率

```bash
# 生成覆盖率报告
swift test --enable-code-coverage

# 查看覆盖率
xcrun llvm-cov report .build/debug/NexusKitPackageTests.xctest/Contents/MacOS/NexusKitPackageTests \
  -instr-profile .build/debug/codecov/default.profdata
```

---

## 🔄 持续集成

### GitHub Actions配置

```yaml
name: Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install test server dependencies
        run: |
          cd TestServers
          npm install

      - name: Start test servers
        run: |
          cd TestServers
          npm run integration &
          sleep 5

      - name: Run integration tests
        run: swift test --filter IntegrationTests

      - name: Stop test servers
        if: always()
        run: pkill -f "node.*server.js" || true
```

---

## 📝 最佳实践

### 编写测试

1. **使用TestUtils辅助函数**
   ```swift
   let connection = try await TestUtils.createTestConnection()
   ```

2. **使用TestFixtures测试数据**
   ```swift
   let message = TestFixtures.dataMessage
   ```

3. **使用异步断言**
   ```swift
   try await XCTAsyncAssertTrue(
       await connection.state == .connected
   )
   ```

4. **清理资源**
   ```swift
   defer {
       Task {
           await connection.disconnect(reason: .clientInitiated)
       }
   }
   ```

### 测试命名

- 使用描述性名称: `testBasicConnection` ✅
- 避免模糊名称: `test1` ❌
- 包含测试目标: `testHeartbeatTimeout` ✅

### 测试隔离

- 每个测试独立运行
- 不依赖其他测试的状态
- 清理所有资源

---

## 🎯 下一步

### 待创建测试

- [ ] BufferIntegrationTests - 缓冲管理测试
- [ ] NetworkMonitoringTests - 网络监控测试
- [ ] EndToEndTests - 端到端测试
- [ ] PerformanceBenchmarks - 性能基准测试

### 优化方向

- [ ] 提高测试覆盖率（目标 >85%）
- [ ] 减少测试执行时间
- [ ] 添加压力测试
- [ ] 添加内存泄漏检测

---

**维护者**: NexusKit Contributors
**最后更新**: 2025-10-20
**版本**: v1.0 - Phase 2 集成测试完成
