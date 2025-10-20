# NexusKit Test Servers

测试服务器集合，用于 NexusKit 单元测试和集成测试。

## 服务器列表

### 1. TCP 服务器 (tcp_server.js)
- **端口**: 8888
- **协议**: 二进制协议（NexusKit BinaryProtocol）
- **功能**:
  - 心跳响应
  - 消息回显
  - 协议头解析

### 2. TLS 服务器 (tls_server.js) ⭐ 新增
- **端口**: 8889
- **协议**: TLS/SSL + 二进制协议
- **功能**:
  - TLS 1.2/1.3 加密传输
  - 自签名证书（测试用）
  - 心跳响应
  - 消息回显

### 3. SOCKS5 代理服务器 (socks5_server.js) ⭐ 新增
- **端口**: 1080
- **协议**: SOCKS5 (RFC 1928)
- **功能**:
  - 无认证模式
  - 用户名/密码认证（可选）
  - IPv4/IPv6/域名支持
  - CONNECT 命令支持

### 4. WebSocket 服务器 (websocket_server.js)
- **端口**: 8080
- **协议**: WebSocket
- **功能**:
  - JSON 消息
  - Ping/Pong
  - 心跳

### 5. Socket.IO 服务器 (socketio_server.js)
- **端口**: 3000
- **协议**: Socket.IO
- **功能**:
  - 事件发送/接收
  - 房间管理
  - 请求-响应模式

## 使用方法

### 安装依赖

```bash
npm install
```

### 启动所有服务器

```bash
# 使用 npm
npm run all

# 或使用 shell 脚本
chmod +x start_all.sh
./start_all.sh
```

### 单独启动

```bash
# TCP 服务器
npm run tcp

# TLS 服务器
npm run tls

# SOCKS5 代理服务器
npm run socks5

# WebSocket 服务器
npm run ws

# Socket.IO 服务器
npm run io
```

### 集成测试专用

```bash
# 只启动集成测试需要的服务器 (TCP + TLS + SOCKS5)
npm run integration
```

## 测试

使用 telnet 测试 TCP 服务器：

```bash
telnet 127.0.0.1 8888
```

使用浏览器控制台测试 WebSocket：

```javascript
const ws = new WebSocket('ws://localhost:8080');
ws.onmessage = (e) => console.log(e.data);
ws.send(JSON.stringify({ type: 'ping' }));
```

使用浏览器测试 Socket.IO：

```html
<script src="https://cdn.socket.io/4.5.0/socket.io.min.js"></script>
<script>
  const socket = io('http://localhost:3000');
  socket.on('welcome', (data) => console.log(data));
</script>
```

## 协议说明

### TCP 二进制协议格式

```
+--------+--------+--------+--------+----------------+
| Version| Type   | Flags  |Reserved| Payload Length |
|  1byte |  1byte | 1byte  | 1byte  |    4 bytes     |
+--------+--------+--------+--------+----------------+
|                 Payload Data                       |
|                (variable length)                   |
+----------------------------------------------------+
```

**Type 类型**:
- `0x01` - Data (数据消息)
- `0x02` - Control (控制消息)
- `0x03` - Heartbeat (心跳)

**Flags**:
- `0x01` - Compressed (压缩)
- `0x02` - Encrypted (加密)

## 依赖

- `socket.io`: ^4.5.0
- `ws`: ^8.13.0
- `concurrently`: ^8.0.0

## 日志

所有服务器都会输出详细的日志信息，便于调试。

## 故障排查

### 端口已被占用

```bash
# 查看端口占用
lsof -i :8888
lsof -i :8080
lsof -i :3000

# 杀死占用进程
kill -9 <PID>
```

### 依赖安装失败

```bash
# 清除缓存
npm cache clean --force

# 重新安装
rm -rf node_modules
npm install
```
