// WebSocket relay — iOS clients connect here and receive real-time task
// progress/completion events streamed from the BullMQ worker via Redis pub/sub.

const { WebSocketServer } = require('ws');
const jwt = require('jsonwebtoken');
const Redis = require('ioredis');

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';

function createWSRelay(server) {
  const wss = new WebSocketServer({ noServer: true });

  // Handle HTTP upgrade manually so we can parse the path.
  server.on('upgrade', (req, socket, head) => {
    // Only handle /ws/agents/:agentId (matches iOS WebSocketManager.swift)
    if (!req.url?.startsWith('/ws/')) {
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit('connection', ws, req);
    });
  });

  wss.on('connection', (ws, req) => {
    const url = new URL(req.url, 'http://localhost');
    const token = url.searchParams.get('token');
    const agentId = req.url.match(/\/ws\/agents\/([^/?]+)/)?.[1];

    if (!token) {
      ws.close(4001, 'Missing token');
      return;
    }

    let userId;
    try {
      userId = jwt.verify(token, JWT_SECRET).sub;
    } catch {
      ws.close(4001, 'Invalid token');
      return;
    }

    // Per-client Redis subscriber for this user's task events.
    const sub = new Redis(process.env.REDIS_URL);
    const channel = `task:${userId}`;

    sub.subscribe(channel);
    sub.on('message', (_ch, message) => {
      if (ws.readyState === ws.OPEN) ws.send(message);
    });

    ws.on('close', () => { sub.unsubscribe(); sub.disconnect(); });
    ws.on('error', () => { sub.unsubscribe(); sub.disconnect(); });

    ws.send(JSON.stringify({ type: 'connected', agent_id: agentId }));
  });

  return wss;
}

module.exports = { createWSRelay };
