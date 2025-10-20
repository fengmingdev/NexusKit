const WebSocket = require('ws');

const PORT = 8080;
const wss = new WebSocket.Server({ port: PORT });

console.log(`[WebSocket] 服务器启动在 ws://localhost:${PORT}`);

wss.on('connection', (ws, req) => {
    console.log(`[WebSocket] 新连接来自: ${req.socket.remoteAddress}`);

    // 发送欢迎消息
    ws.send(JSON.stringify({
        type: 'welcome',
        message: 'Connected to NexusKit WebSocket Test Server',
        timestamp: Date.now()
    }));

    // 接收消息
    ws.on('message', (data) => {
        console.log('[WebSocket] 收到消息:', data.toString());

        try {
            const message = JSON.parse(data.toString());

            // 心跳响应
            if (message.type === 'ping') {
                ws.send(JSON.stringify({
                    type: 'pong',
                    timestamp: Date.now()
                }));
                return;
            }

            // 回显消息
            ws.send(JSON.stringify({
                type: 'echo',
                originalMessage: message,
                timestamp: Date.now()
            }));
        } catch (e) {
            console.error('[WebSocket] 解析错误:', e.message);
        }
    });

    // 连接关闭
    ws.on('close', () => {
        console.log('[WebSocket] 连接关闭');
    });

    // 错误处理
    ws.on('error', (err) => {
        console.error('[WebSocket] 错误:', err.message);
    });

    // 定期心跳
    const heartbeat = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) {
            ws.send(JSON.stringify({
                type: 'server_heartbeat',
                timestamp: Date.now()
            }));
        }
    }, 30000); // 30秒

    ws.on('close', () => clearInterval(heartbeat));
});
