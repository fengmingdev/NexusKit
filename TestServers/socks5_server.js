const net = require('net');

// 配置
const PORT = 1080;
const HOST = '127.0.0.1';

// 测试用户名密码（如果启用认证）
const AUTH_ENABLED = false;
const USERNAME = 'testuser';
const PASSWORD = 'testpass';

// SOCKS5 常量
const SOCKS_VERSION = 0x05;
const AUTH_METHODS = {
    NO_AUTH: 0x00,
    USERNAME_PASSWORD: 0x02,
    NO_ACCEPTABLE: 0xFF
};
const CMD = {
    CONNECT: 0x01,
    BIND: 0x02,
    UDP_ASSOCIATE: 0x03
};
const ATYP = {
    IPV4: 0x01,
    DOMAIN: 0x03,
    IPV6: 0x04
};
const REP = {
    SUCCESS: 0x00,
    GENERAL_FAILURE: 0x01,
    CONNECTION_NOT_ALLOWED: 0x02,
    NETWORK_UNREACHABLE: 0x03,
    HOST_UNREACHABLE: 0x04,
    CONNECTION_REFUSED: 0x05,
    TTL_EXPIRED: 0x06,
    COMMAND_NOT_SUPPORTED: 0x07,
    ADDRESS_TYPE_NOT_SUPPORTED: 0x08
};

// 创建 SOCKS5 代理服务器
const server = net.createServer((clientSocket) => {
    console.log(`[SOCKS5] 客户端连接: ${clientSocket.remoteAddress}:${clientSocket.remotePort}`);

    let targetSocket = null;
    let authState = 'greeting';

    // 接收客户端数据
    clientSocket.on('data', (data) => {
        if (authState === 'greeting') {
            handleGreeting(clientSocket, data);
        } else if (authState === 'auth') {
            handleAuth(clientSocket, data);
        } else if (authState === 'request') {
            handleRequest(clientSocket, data);
        } else if (authState === 'connected' && targetSocket) {
            // 转发数据到目标服务器
            targetSocket.write(data);
        }
    });

    // 处理握手：客户端发送认证方法
    function handleGreeting(socket, data) {
        // +----+----------+----------+
        // |VER | NMETHODS | METHODS  |
        // +----+----------+----------+
        // | 1  |    1     | 1 to 255 |
        // +----+----------+----------+
        if (data.length < 2) {
            console.log('[SOCKS5] 握手数据不完整');
            socket.end();
            return;
        }

        const version = data[0];
        const nmethods = data[1];
        const methods = data.slice(2, 2 + nmethods);

        console.log(`[SOCKS5] 版本: ${version}, 方法数: ${nmethods}, 方法: [${Array.from(methods).join(', ')}]`);

        if (version !== SOCKS_VERSION) {
            console.log('[SOCKS5] 不支持的SOCKS版本');
            socket.end();
            return;
        }

        // 选择认证方法
        let selectedMethod;
        if (AUTH_ENABLED) {
            if (methods.includes(AUTH_METHODS.USERNAME_PASSWORD)) {
                selectedMethod = AUTH_METHODS.USERNAME_PASSWORD;
                authState = 'auth';
            } else {
                selectedMethod = AUTH_METHODS.NO_ACCEPTABLE;
                socket.write(Buffer.from([SOCKS_VERSION, selectedMethod]));
                socket.end();
                return;
            }
        } else {
            selectedMethod = AUTH_METHODS.NO_AUTH;
            authState = 'request';
        }

        // 发送认证方法选择
        const response = Buffer.from([SOCKS_VERSION, selectedMethod]);
        socket.write(response);
        console.log(`[SOCKS5] 选择认证方法: ${selectedMethod === 0 ? 'NO_AUTH' : 'USERNAME_PASSWORD'}`);
    }

    // 处理用户名密码认证
    function handleAuth(socket, data) {
        // +----+------+----------+------+----------+
        // |VER | ULEN |  UNAME   | PLEN |  PASSWD  |
        // +----+------+----------+------+----------+
        // | 1  |  1   | 1 to 255 |  1   | 1 to 255 |
        // +----+------+----------+------+----------+
        if (data.length < 2) {
            socket.end();
            return;
        }

        const version = data[0];
        const ulen = data[1];
        const uname = data.slice(2, 2 + ulen).toString('utf8');
        const plen = data[2 + ulen];
        const passwd = data.slice(3 + ulen, 3 + ulen + plen).toString('utf8');

        console.log(`[SOCKS5] 认证: 用户名=${uname}, 密码=${passwd}`);

        // 验证用户名密码
        const success = (uname === USERNAME && passwd === PASSWORD);
        const response = Buffer.from([0x01, success ? 0x00 : 0x01]);
        socket.write(response);

        if (success) {
            console.log('[SOCKS5] 认证成功');
            authState = 'request';
        } else {
            console.log('[SOCKS5] 认证失败');
            socket.end();
        }
    }

    // 处理连接请求
    function handleRequest(socket, data) {
        // +----+-----+-------+------+----------+----------+
        // |VER | CMD |  RSV  | ATYP | DST.ADDR | DST.PORT |
        // +----+-----+-------+------+----------+----------+
        // | 1  |  1  | X'00' |  1   | Variable |    2     |
        // +----+-----+-------+------+----------+----------+
        if (data.length < 4) {
            socket.end();
            return;
        }

        const version = data[0];
        const cmd = data[1];
        const atyp = data[3];

        let targetHost;
        let targetPort;
        let offset;

        // 解析目标地址
        if (atyp === ATYP.IPV4) {
            // IPv4: 4 字节
            targetHost = `${data[4]}.${data[5]}.${data[6]}.${data[7]}`;
            targetPort = data.readUInt16BE(8);
            offset = 10;
        } else if (atyp === ATYP.DOMAIN) {
            // 域名: 1字节长度 + 域名
            const domainLen = data[4];
            targetHost = data.slice(5, 5 + domainLen).toString('utf8');
            targetPort = data.readUInt16BE(5 + domainLen);
            offset = 7 + domainLen;
        } else if (atyp === ATYP.IPV6) {
            // IPv6: 16 字节
            const ipv6 = [];
            for (let i = 0; i < 16; i += 2) {
                ipv6.push(data.readUInt16BE(4 + i).toString(16));
            }
            targetHost = ipv6.join(':');
            targetPort = data.readUInt16BE(20);
            offset = 22;
        } else {
            console.log(`[SOCKS5] 不支持的地址类型: ${atyp}`);
            sendReply(socket, REP.ADDRESS_TYPE_NOT_SUPPORTED);
            socket.end();
            return;
        }

        console.log(`[SOCKS5] 请求: CMD=${cmd}, ATYP=${atyp}, 目标=${targetHost}:${targetPort}`);

        // 只支持 CONNECT 命令
        if (cmd !== CMD.CONNECT) {
            console.log(`[SOCKS5] 不支持的命令: ${cmd}`);
            sendReply(socket, REP.COMMAND_NOT_SUPPORTED);
            socket.end();
            return;
        }

        // 连接到目标服务器
        targetSocket = net.createConnection(targetPort, targetHost, () => {
            console.log(`[SOCKS5] 已连接到目标: ${targetHost}:${targetPort}`);

            // 发送成功响应
            sendReply(socket, REP.SUCCESS, targetHost, targetPort, atyp);
            authState = 'connected';

            // 转发数据
            targetSocket.on('data', (data) => {
                socket.write(data);
            });

            targetSocket.on('end', () => {
                console.log('[SOCKS5] 目标服务器关闭连接');
                socket.end();
            });

            targetSocket.on('error', (err) => {
                console.error('[SOCKS5] 目标服务器错误:', err.message);
                socket.end();
            });
        });

        targetSocket.on('error', (err) => {
            console.error('[SOCKS5] 连接目标失败:', err.message);
            sendReply(socket, REP.CONNECTION_REFUSED);
            socket.end();
        });
    }

    // 发送响应
    function sendReply(socket, rep, boundAddr = '0.0.0.0', boundPort = 0, atyp = ATYP.IPV4) {
        const response = Buffer.alloc(10);
        response[0] = SOCKS_VERSION;
        response[1] = rep;
        response[2] = 0x00;
        response[3] = atyp;

        // BND.ADDR 和 BND.PORT（简化为 0.0.0.0:0）
        response.writeUInt32BE(0, 4);
        response.writeUInt16BE(0, 8);

        socket.write(response);
    }

    clientSocket.on('end', () => {
        console.log('[SOCKS5] 客户端断开连接');
        if (targetSocket) {
            targetSocket.end();
        }
    });

    clientSocket.on('error', (err) => {
        console.error('[SOCKS5] 客户端错误:', err.message);
        if (targetSocket) {
            targetSocket.destroy();
        }
    });
});

// 启动服务器
server.listen(PORT, HOST, () => {
    console.log(`[SOCKS5] 代理服务器启动在 ${HOST}:${PORT}`);
    console.log(`[SOCKS5] 认证: ${AUTH_ENABLED ? '启用 (用户名/密码)' : '禁用'}`);
    if (AUTH_ENABLED) {
        console.log(`[SOCKS5] 测试账号: ${USERNAME} / ${PASSWORD}`);
    }
});

// 优雅关闭
process.on('SIGINT', () => {
    console.log('\n[SOCKS5] 服务器关闭中...');
    server.close(() => {
        console.log('[SOCKS5] 服务器已关闭');
        process.exit(0);
    });
});
