// Bridge to the OpenClaw Gateway HTTP API (OpenAI-compatible chat completions)

const GATEWAY_URL = process.env.OPENCLAW_GATEWAY_URL || 'http://openclaw-gateway:18789';
const GATEWAY_TOKEN = process.env.OPENCLAW_GATEWAY_TOKEN;

async function chatCompletion({ agentId, messages, userId, stream = false }) {
  const url = `${GATEWAY_URL}/v1/chat/completions`;

  const body = JSON.stringify({
    model: `openclaw:${agentId}`,
    messages,
    user: userId,
    stream,
  });

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${GATEWAY_TOKEN}`,
      'Content-Type': 'application/json',
      'x-openclaw-agent-id': agentId,
    },
    body,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OpenClaw ${res.status}: ${text}`);
  }

  return res;
}

async function chatCompletionSync({ agentId, messages, userId }) {
  const res = await chatCompletion({ agentId, messages, userId, stream: false });
  return res.json();
}

async function* chatCompletionStream({ agentId, messages, userId }) {
  const res = await chatCompletion({ agentId, messages, userId, stream: true });

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop();

    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      const data = line.slice(6).trim();
      if (data === '[DONE]') return;
      try {
        yield JSON.parse(data);
      } catch {
        // skip malformed SSE chunks
      }
    }
  }
}

async function healthCheck() {
  try {
    const res = await fetch(`${GATEWAY_URL}/healthz`);
    return res.ok;
  } catch {
    return false;
  }
}

module.exports = { chatCompletion, chatCompletionSync, chatCompletionStream, healthCheck };
