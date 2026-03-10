#!/usr/bin/env node
// Real-time CLI test: connects WebSocket, submits a task, streams output live.
// Uses Node.js native WebSocket (v22+).

const API = 'http://localhost:3000';
const AGENT_ID = process.argv[2] || '';
const PROMPT = process.argv.slice(3).join(' ') || 'Say hello in 3 languages';

async function main() {
  console.log('\x1b[90m── Logging in...\x1b[0m');
  const loginRes = await fetch(`${API}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'test@example.com', password: 'test1234' }),
  });
  if (!loginRes.ok) { console.error('Login failed:', await loginRes.text()); process.exit(1); }
  const { tokens } = await loginRes.json();
  const token = tokens.access_token;
  console.log('\x1b[32m✓ Logged in\x1b[0m');

  let agentId = AGENT_ID;
  if (!agentId) {
    const agentsRes = await fetch(`${API}/agents`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const { agents } = await agentsRes.json();
    if (!agents.length) { console.error('No agents. Create one first.'); process.exit(1); }
    agentId = agents[0].id;
    console.log(`\x1b[90m── Agent: ${agents[0].name} (${agentId})\x1b[0m`);
  }

  const wsUrl = `ws://localhost:3000/ws/agents/${agentId}?token=${token}`;
  const ws = new WebSocket(wsUrl);

  ws.addEventListener('open', () => {
    console.log('\x1b[32m✓ WebSocket connected\x1b[0m\n');
  });

  ws.addEventListener('message', (evt) => {
    const event = JSON.parse(evt.data);
    switch (event.type) {
      case 'connected':
        console.log(`\x1b[36m[ws] connected to agent ${event.agent_id}\x1b[0m`);
        break;
      case 'task:progress':
        process.stdout.write(event.content);
        break;
      case 'task:tool_start':
        console.log(`\n\x1b[33m⚙  tool: ${event.tool_name}\x1b[0m`);
        break;
      case 'task:tool_end':
        console.log(`\x1b[33m✓  tool done: ${event.tool_name}\x1b[0m`);
        break;
      case 'task:complete':
        console.log('\n\n\x1b[32m── Task complete ──\x1b[0m');
        ws.close();
        break;
      case 'task:error':
        console.error(`\n\x1b[31m✗ Error: ${event.error}\x1b[0m`);
        ws.close();
        break;
      default:
        console.log(`\x1b[90m[ws] ${JSON.stringify(event)}\x1b[0m`);
    }
  });

  ws.addEventListener('close', () => process.exit(0));
  ws.addEventListener('error', (e) => { console.error('WS error:', e.message); process.exit(1); });

  // Wait for open
  await new Promise((resolve) => ws.addEventListener('open', resolve, { once: true }));
  await new Promise((r) => setTimeout(r, 300));

  console.log(`\x1b[90m── Prompt: "${PROMPT}"\x1b[0m\n`);

  const taskRes = await fetch(`${API}/agents/${agentId}/tasks`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ input: PROMPT }),
  });
  const task = await taskRes.json();
  console.log(`\x1b[90m── Task ${task.task_id} queued ──\x1b[0m\n`);
}

main().catch((err) => { console.error(err); process.exit(1); });
