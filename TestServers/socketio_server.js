const { Server } = require('socket.io');

const PORT = 3000;
const io = new Server(PORT, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

console.log(`[Socket.IO] 服务器启动在 http://localhost:${PORT}`);

io.on('connection', (socket) => {
    console.log(`[Socket.IO] 客户端连接: ${socket.id}`);

    // 欢迎消息
    socket.emit('welcome', {
        message: 'Connected to Socket.IO Test Server',
        clientId: socket.id,
        timestamp: Date.now()
    });

    // 聊天消息
    socket.on('chat', (data) => {
        console.log('[Socket.IO] 聊天消息:', data);
        io.emit('chat', {
            from: socket.id,
            message: data.message,
            timestamp: Date.now()
        });
    });

    // 请求-响应模式
    socket.on('request', (data, callback) => {
        console.log('[Socket.IO] 收到请求:', data);
        callback({
            success: true,
            data: { echo: data },
            timestamp: Date.now()
        });
    });

    // 命名空间
    socket.on('join_room', (room) => {
        socket.join(room);
        console.log(`[Socket.IO] ${socket.id} 加入房间: ${room}`);
        socket.to(room).emit('user_joined', {
            userId: socket.id,
            room: room
        });
    });

    // 断开连接
    socket.on('disconnect', (reason) => {
        console.log(`[Socket.IO] 客户端断开: ${socket.id}, 原因: ${reason}`);
    });

    // 自定义事件
    socket.on('custom_event', (data) => {
        console.log('[Socket.IO] 自定义事件:', data);
        socket.emit('custom_response', { received: true, data });
    });
});
