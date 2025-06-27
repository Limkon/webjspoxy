// 引入必要的 Node.js 模块
const http = require('http'); // HTTP 服务器模块，用于创建 HTTP 服务器
const fs = require('fs'); // 文件系统模块，用于读取 index.html 等文件
const net = require('net'); // 网络连接模块，用于代理的 TCP 连接
const { Buffer } = require('buffer'); // Buffer 模块，用于处理二进制数据
const { WebSocket, createWebSocketStream } = require('ws'); // WebSocket 模块，用于 VLESS 代理
const axios = require('axios'); // 用于定时请求

// 环境变量配置
const UUID = process.env.UUID || '0058c4cc-82a2-4cd0-92ed-fe8286d261d2'; // VLESS 用户的 UUID
const DOMAIN = process.env.DOMAIN || 'appname-accountname.ladeapp.com'; // 域名
const SUB_PATH = process.env.SUB_PATH || 'sub'; // 订阅路径
const NAME = process.env.NAME || 'Lade'; // 节点名称
const PORT = process.env.PORT || 5768; // 服务端口

const ISP = 'cloudflare'; // 固定 ISP 标识

// 创建 HTTP 服务器
const httpServer = http.createServer((req, res) => {
  if (req.url === '/') {
    fs.readFile('index.html', (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('Not Found\n');
        console.error('读取 index.html 失败:', err.message);
        return;
      }
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(data);
    });
  } else if (req.url === `/${SUB_PATH}`) {
    const vlessURL = `vless://${UUID}@${DOMAIN}:${PORT}?encryption=none&security=none&type=ws&host=${DOMAIN}&path=%2Fed%3D2560#${NAME}-${ISP}`;
    const base64Content = Buffer.from(vlessURL).toString('base64');
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(base64Content + '\n');
  } else {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found\n');
  }
});

// 创建 WebSocket 服务器
const wss = new WebSocket.Server({ server: httpServer });
const uuid = UUID.replace(/-/g, "");

wss.on('connection', ws => {
  ws.once('message', msg => {
    const [VERSION] = msg;
    const id = msg.slice(1, 17);
    if (!id.every((v, i) => v == parseInt(uuid.substr(i * 2, 2), 16))) {
      console.error('UUID 验证失败');
      return;
    }

    let i = msg.slice(17, 18).readUInt8() + 19;
    const port = msg.slice(i, i += 2).readUInt16BE(0);
    const ATYP = msg.slice(i, i += 1).readUInt8();
    const host = ATYP == 1
      ? msg.slice(i, i += 4).join('.')
      : (ATYP == 2
        ? new TextDecoder().decode(msg.slice(i + 1, i += 1 + msg.slice(i, i + 1).readUInt8()))
        : (ATYP == 3
          ? msg.slice(i, i += 16).reduce((s, b, i, a) => (i % 2 ? s.concat(a.slice(i - 1, i + 1)) : s), [])
              .map(b => b.readUInt16BE(0).toString(16)).join(':')
          : ''));

    ws.send(new Uint8Array([VERSION, 0]));
    const duplex = createWebSocketStream(ws);

    net.connect({ host, port }, function () {
      this.write(msg.slice(i));
      duplex.on('error', () => {}).pipe(this).on('error', () => {}).pipe(duplex);
    }).on('error', (err) => {
      console.error(`TCP 连接错误: ${host}:${port}`, err.message);
    });
  }).on('error', (err) => {
    console.error('WebSocket 错误:', err.message);
  });
});

// 启动 HTTP 服务器并监听在 0.0.0.0 上
httpServer.listen(PORT, '0.0.0.0', () => {
  console.log(`✅ 服务器运行在 http://0.0.0.0:${PORT}`);
  console.log(`🌐 访问首页: http://${DOMAIN}:${PORT}/`);
  console.log(`📡 获取 VLESS 配置: http://${DOMAIN}:${PORT}/${SUB_PATH}`);
});

// 定时保持活跃请求（每 15 分钟）
setInterval(async () => {
  try {
    await axios.get(`http://${DOMAIN}:${PORT}/`);
    console.log('⏱️ 定时任务：已发送保持活跃请求');
  } catch (err) {
    console.error('⛔ 定时任务失败:', err.message);
  }
}, 15 * 60 * 1000);
