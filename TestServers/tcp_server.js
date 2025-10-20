const net = require('net');

// 配置
const PORT = 8888;
const HOST = '127.0.0.1';

// 创建服务器
const server = net.createServer((socket) => {
    console.log(`[TCP] 客户端连接: ${socket.remoteAddress}:${socket.remotePort}`);

    // 心跳计数
    let heartbeatCount = 0;

    // 接收数据
    socket.on('data', (data) => {
        console.log(`[TCP] 收到数据 (${data.length} bytes):`, data.toString('hex'));

        // 解析二进制协议 (NexusKit BinaryProtocol)
        // 格式: [4字节Len] + [20字节Header] + [Body]
        // Header: Tag(2) + Ver(2) + Tp(1) + Res(1) + Qid(4) + Fid(4) + Code(4) + Dh(2)
        if (data.length >= 24) {
            const len = data.readUInt32BE(0);            // 0-3: 长度 (Header+Body)
            const tag = data.readUInt16BE(4);            // 4-5: 协议标签
            const ver = data.readUInt16BE(6);            // 6-7: 版本
            const tp = data.readUInt8(8);                // 8: 类型标志
            const res = data.readUInt8(9);               // 9: 响应标志 (0=请求, 1=响应)
            const qid = data.readUInt32BE(10);           // 10-13: 请求ID
            const fid = data.readUInt32BE(14);           // 14-17: 功能ID
            const code = data.readUInt32BE(18);          // 18-21: 错误码
            const dh = data.readUInt16BE(22);            // 22-23: 保留字段

            console.log(`  Tag: 0x${tag.toString(16)}, Ver: ${ver}, Tp: ${tp}, Res: ${res}`);
            console.log(`  Qid: ${qid}, Fid: ${fid}, Code: ${code}, Dh: ${dh}`);
            console.log(`  Len: ${len} (应该是 Header(20) + Body(${len-20}))`);

            // 心跳响应 (Fid == 0xFFFF)
            if (fid === 0xFFFF) {
                heartbeatCount++;
                console.log(`  心跳 #${heartbeatCount}`);
                socket.write(data); // 回显心跳
                return;
            }

            // 普通消息回显
            if (res === 0) { // 请求
                const payload = data.slice(24, 4 + len);
                console.log(`  载荷长度: ${payload.length}, 内容: ${payload.toString('utf8')}`);
                
                // 构造响应: 修改 Res 标志为 1，设置 Code=200
                const response = Buffer.from(data);
                response.writeUInt8(1, 9);           // Res = 1 (响应)
                response.writeUInt32BE(200, 18);     // Code = 200 (OK)
                
                // 添加响应文本（可选）
                const responseText = Buffer.from(`Server received: ${payload.toString('utf8')}`);
                const newLen = 20 + responseText.length;
                const finalResponse = Buffer.alloc(4 + newLen);
                finalResponse.writeUInt32BE(newLen, 0);  // 更新长度
                response.copy(finalResponse, 4, 4, 24);  // 复制 Header
                responseText.copy(finalResponse, 24);    // 复制新 Body
                
                socket.write(finalResponse);
            }
        }
    });

    // 连接关闭
    socket.on('end', () => {
        console.log('[TCP] 客户端断开连接');
    });

    // 错误处理
    socket.on('error', (err) => {
        console.error('[TCP] 错误:', err.message);
    });

    // 发送欢迎消息
    const welcome = createBinaryMessage('Welcome to NexusKit Test Server!');
    socket.write(welcome);
});

// 启动服务器
server.listen(PORT, HOST, () => {
    console.log(`[TCP] 服务器启动在 ${HOST}:${PORT}`);
});

// 构造二进制消息
function createBinaryMessage(text) {
    const payload = Buffer.from(text, 'utf8');
    const len = 20 + payload.length;  // Header(20) + Body
    const message = Buffer.alloc(4 + len);
    
    // [4字节] Len
    message.writeUInt32BE(len, 0);
    
    // [20字节] Header
    message.writeUInt16BE(0x7A5A, 4);     // Tag
    message.writeUInt16BE(1, 6);          // Ver
    message.writeUInt8(0, 8);             // Tp
    message.writeUInt8(1, 9);             // Res (1=响应)
    message.writeUInt32BE(0, 10);         // Qid
    message.writeUInt32BE(0, 14);         // Fid
    message.writeUInt32BE(200, 18);       // Code (200=OK)
    message.writeUInt16BE(0, 22);         // Dh
    
    // Body
    payload.copy(message, 24);
    
    return message;
}

// 优雅关闭
process.on('SIGINT', () => {
    console.log('\n[TCP] 服务器关闭中...');
    server.close(() => {
        console.log('[TCP] 服务器已关闭');
        process.exit(0);
    });
});
