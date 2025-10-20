const tls = require('tls');
const fs = require('fs');
const path = require('path');

// 配置
const PORT = 8889;
const HOST = '127.0.0.1';

// TLS 选项
const options = {
    key: fs.readFileSync(path.join(__dirname, 'certs', 'server-key.pem')),
    cert: fs.readFileSync(path.join(__dirname, 'certs', 'server-cert.pem')),
    // 允许自签名证书（测试环境）
    rejectUnauthorized: false
};

// 创建 TLS 服务器
const server = tls.createServer(options, (socket) => {
    console.log(`[TLS] 客户端连接: ${socket.remoteAddress}:${socket.remotePort}`);
    console.log(`[TLS] 加密协议: ${socket.getProtocol()}`);
    console.log(`[TLS] 密码套件: ${socket.getCipher().name}`);

    // 心跳计数
    let heartbeatCount = 0;

    // 接收数据
    socket.on('data', (data) => {
        console.log(`[TLS] 收到数据 (${data.length} bytes):`, data.toString('hex').substring(0, 100));

        // 解析二进制协议 (NexusKit BinaryProtocol)
        if (data.length >= 24) {
            const len = data.readUInt32BE(0);
            const tag = data.readUInt16BE(4);
            const ver = data.readUInt16BE(6);
            const tp = data.readUInt8(8);
            const res = data.readUInt8(9);
            const qid = data.readUInt32BE(10);
            const fid = data.readUInt32BE(14);
            const code = data.readUInt32BE(18);

            console.log(`  Tag: 0x${tag.toString(16)}, Ver: ${ver}, Tp: ${tp}, Res: ${res}`);
            console.log(`  Qid: ${qid}, Fid: ${fid}, Code: ${code}`);

            // 心跳响应 (Fid == 0xFFFF)
            if (fid === 0xFFFF) {
                heartbeatCount++;
                console.log(`  心跳 #${heartbeatCount}`);
                socket.write(data); // 回显心跳
                return;
            }

            // 普通消息回显
            if (res === 0) {
                const payload = data.slice(24, 4 + len);
                console.log(`  载荷: ${payload.toString('utf8')}`);

                // 构造响应
                const response = Buffer.from(data);
                response.writeUInt8(1, 9);           // Res = 1
                response.writeUInt32BE(200, 18);     // Code = 200

                const responseText = Buffer.from(`TLS Server received: ${payload.toString('utf8')}`);
                const newLen = 20 + responseText.length;
                const finalResponse = Buffer.alloc(4 + newLen);
                finalResponse.writeUInt32BE(newLen, 0);
                response.copy(finalResponse, 4, 4, 24);
                responseText.copy(finalResponse, 24);

                socket.write(finalResponse);
            }
        }
    });

    socket.on('end', () => {
        console.log('[TLS] 客户端断开连接');
    });

    socket.on('error', (err) => {
        console.error('[TLS] 错误:', err.message);
    });

    // 发送欢迎消息
    const welcome = createBinaryMessage('Welcome to NexusKit TLS Test Server!');
    socket.write(welcome);
});

// 启动服务器
server.listen(PORT, HOST, () => {
    console.log(`[TLS] 服务器启动在 ${HOST}:${PORT}`);
    console.log(`[TLS] 使用 TLS 1.2/1.3`);
});

// 构造二进制消息
function createBinaryMessage(text) {
    const payload = Buffer.from(text, 'utf8');
    const len = 20 + payload.length;
    const message = Buffer.alloc(4 + len);

    message.writeUInt32BE(len, 0);
    message.writeUInt16BE(0x7A5A, 4);     // Tag
    message.writeUInt16BE(1, 6);          // Ver
    message.writeUInt8(0, 8);             // Tp
    message.writeUInt8(1, 9);             // Res
    message.writeUInt32BE(0, 10);         // Qid
    message.writeUInt32BE(0, 14);         // Fid
    message.writeUInt32BE(200, 18);       // Code
    message.writeUInt16BE(0, 22);         // Dh
    payload.copy(message, 24);

    return message;
}

// 优雅关闭
process.on('SIGINT', () => {
    console.log('\n[TLS] 服务器关闭中...');
    server.close(() => {
        console.log('[TLS] 服务器已关闭');
        process.exit(0);
    });
});
