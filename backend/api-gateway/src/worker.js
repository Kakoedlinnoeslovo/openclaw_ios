// BullMQ task worker — picks jobs from the "tasks" queue, calls OpenClaw
// chat completions (streaming), writes results to PostgreSQL, and publishes
// progress/completion/tool events over Redis pub/sub for the WebSocket relay.

const fs = require('fs');
const path = require('path');
const { Worker } = require('bullmq');
const pg = require('pg');
const Redis = require('ioredis');
const { chatCompletionStream } = require('./openclaw-client');

let pdfParse;
try { pdfParse = require('pdf-parse'); } catch { pdfParse = null; }

const { setSkillCredentials, openclawAgentId, ensureWorkspaceReady } = require('./provisioner');

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const redis = new Redis(process.env.REDIS_URL);

const QUEUE_NAME = 'tasks';
const HISTORY_LIMIT = 50;

const OAUTH_PROVIDERS = {
  slack: {
    token_url: 'https://slack.com/api/oauth.v2.access',
    token_field: 'SLACK_BOT_TOKEN',
  },
  google: {
    token_url: 'https://oauth2.googleapis.com/token',
    token_field: 'GOOGLE_ACCESS_TOKEN',
  },
  notion: {
    token_url: 'https://api.notion.com/v1/oauth/token',
    token_field: 'NOTION_API_KEY',
  },
};

async function getOAuthClientCredentials(provider) {
  const envId = process.env[`${provider.toUpperCase()}_CLIENT_ID`];
  const envSecret = process.env[`${provider.toUpperCase()}_CLIENT_SECRET`];
  if (envId && envSecret) return { clientId: envId, clientSecret: envSecret };

  try {
    const { rows: [row] } = await pool.query(
      `SELECT value FROM app_config WHERE key = $1`,
      [`oauth_creds_${provider}`],
    );
    if (row?.value?.client_id && row?.value?.client_secret) {
      return { clientId: row.value.client_id, clientSecret: row.value.client_secret };
    }
  } catch { /* table may not exist */ }
  return null;
}

async function refreshOAuthTokensForAgent(agentId, userId) {
  const { rows: tokens } = await pool.query(
    `SELECT * FROM oauth_tokens WHERE agent_id = $1 AND user_id = $2
     AND expires_at IS NOT NULL AND expires_at < NOW() + INTERVAL '2 minutes'`,
    [agentId, userId],
  );

  for (const tokenRow of tokens) {
    if (!tokenRow.refresh_token) continue;
    const providerCfg = OAUTH_PROVIDERS[tokenRow.provider];
    if (!providerCfg) continue;

    try {
      const creds = await getOAuthClientCredentials(tokenRow.provider);
      if (!creds) continue;
      const { clientId, clientSecret } = creds;

      const tokenParams = new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: tokenRow.refresh_token,
        client_id: clientId,
        client_secret: clientSecret,
      });

      const resp = await fetch(providerCfg.token_url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: tokenParams.toString(),
      });

      if (!resp.ok) {
        console.warn(`[worker] oauth refresh failed for ${tokenRow.provider}:`, await resp.text());
        continue;
      }

      const body = await resp.json();
      const newAccessToken = body.access_token;
      const newRefreshToken = body.refresh_token || tokenRow.refresh_token;
      const expiresAt = body.expires_in
        ? new Date(Date.now() + body.expires_in * 1000)
        : null;

      await pool.query(
        `UPDATE oauth_tokens SET access_token = $1, refresh_token = $2, expires_at = $3, updated_at = NOW()
         WHERE id = $4`,
        [newAccessToken, newRefreshToken, expiresAt, tokenRow.id],
      );

      setSkillCredentials(userId, agentId, tokenRow.skill_id, {
        [providerCfg.token_field]: newAccessToken,
      });

      console.log(`[worker] refreshed ${tokenRow.provider} token for agent=${agentId}`);
    } catch (err) {
      console.warn(`[worker] oauth refresh error for ${tokenRow.provider}:`, err.message);
    }
  }
}

const IMAGE_MIME_TYPES = new Set([
  'image/jpeg', 'image/png', 'image/webp', 'image/gif',
]);

const BINARY_MIME_TYPES = new Set([
  'image/heic', 'image/heif',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]);

function publish(userId, event) {
  redis.publish(`task:${userId}`, JSON.stringify(event));
}

async function loadConversationHistory(agentId, userId) {
  const { rows } = await pool.query(
    `SELECT input, output, status FROM tasks
     WHERE agent_id = $1 AND user_id = $2 AND status = 'completed' AND output IS NOT NULL
     ORDER BY created_at DESC LIMIT $3`,
    [agentId, userId, HISTORY_LIMIT],
  );

  const messages = [];
  for (const row of rows.reverse()) {
    messages.push({ role: 'user', content: row.input });
    messages.push({ role: 'assistant', content: row.output });
  }
  return messages;
}

async function loadFileContents(fileIds) {
  if (!fileIds || fileIds.length === 0) return [];

  const { rows } = await pool.query(
    'SELECT id, filename, mime_type, storage_path FROM files WHERE id = ANY($1)',
    [fileIds],
  );

  const results = [];
  for (const file of rows) {
    try {
      if (!fs.existsSync(file.storage_path)) continue;

      if (IMAGE_MIME_TYPES.has(file.mime_type)) {
        const buf = fs.readFileSync(file.storage_path);
        const b64 = buf.toString('base64');
        results.push({
          type: 'image',
          filename: file.filename,
          mimeType: file.mime_type,
          dataUrl: `data:${file.mime_type};base64,${b64}`,
        });
      } else if (BINARY_MIME_TYPES.has(file.mime_type)) {
        results.push({
          type: 'text',
          filename: file.filename,
          content: `[Binary file: ${file.filename} (${file.mime_type}) — content extraction not supported for this format]`,
        });
      } else if (file.mime_type === 'application/pdf') {
        if (pdfParse) {
          const buf = fs.readFileSync(file.storage_path);
          const parsed = await pdfParse(buf);
          results.push({
            type: 'text',
            filename: file.filename,
            content: parsed.text,
          });
        } else {
          results.push({
            type: 'text',
            filename: file.filename,
            content: `[PDF file: ${file.filename} — pdf-parse not installed, content not available]`,
          });
        }
      } else {
        const text = fs.readFileSync(file.storage_path, 'utf-8');
        results.push({
          type: 'text',
          filename: file.filename,
          content: text,
        });
      }
    } catch (err) {
      console.error(`[worker] failed to read file ${file.id}:`, err.message);
      results.push({
        type: 'text',
        filename: file.filename,
        content: `[Could not read file: ${file.filename}]`,
      });
    }
  }
  return results;
}

function buildUserMessage(input, fileContents, imageData) {
  const hasImages = fileContents.some(f => f.type === 'image') || imageData;
  const textFiles = fileContents.filter(f => f.type === 'text');
  const imageFiles = fileContents.filter(f => f.type === 'image');

  if (!hasImages && textFiles.length === 0) {
    return input;
  }

  let textPrefix = '';
  if (textFiles.length > 0) {
    const fileSections = textFiles.map(f =>
      `--- File: ${f.filename} ---\n${f.content}\n--- End of ${f.filename} ---`
    ).join('\n\n');
    textPrefix = fileSections + '\n\n';
  }

  if (!hasImages) {
    return textPrefix + input;
  }

  // Vision-capable: use content array format
  const contentParts = [];

  if (textPrefix) {
    contentParts.push({ type: 'text', text: textPrefix + input });
  } else {
    contentParts.push({ type: 'text', text: input });
  }

  for (const img of imageFiles) {
    contentParts.push({
      type: 'image_url',
      image_url: { url: img.dataUrl, detail: 'auto' },
    });
  }

  if (imageData) {
    const mimeGuess = imageData.startsWith('/9j/') ? 'image/jpeg' : 'image/png';
    contentParts.push({
      type: 'image_url',
      image_url: { url: `data:${mimeGuess};base64,${imageData}`, detail: 'auto' },
    });
  }

  return contentParts;
}

const worker = new Worker(
  QUEUE_NAME,
  async (job) => {
    const { taskId, agentId, openclawAgentId: ocAgentId, userId, input, fileIds, imageData } = job.data;
    console.log(`[worker] processing task=${taskId} agent=${ocAgentId} files=${(fileIds || []).length}`);

    try {
      await pool.query("UPDATE tasks SET status = 'running' WHERE id = $1", [taskId]);
      publish(userId, { type: 'task:progress', task_id: taskId, content: '' });

      // Patch workspace AGENTS.md + .env for agents created before the fix
      ensureWorkspaceReady(ocAgentId);

      await refreshOAuthTokensForAgent(agentId, userId);

      const fileContents = await loadFileContents(fileIds);
      const userContent = buildUserMessage(input, fileContents, imageData);

      const history = await loadConversationHistory(agentId, userId);
      const messages = [...history, { role: 'user', content: userContent }];

      let fullOutput = '';
      let currentToolCall = null;
      let lastUsage = null;

      for await (const chunk of chatCompletionStream({
        agentId: ocAgentId,
        messages,
        userId,
      })) {
        if (chunk.usage) lastUsage = chunk.usage;

        const choice = chunk.choices?.[0];
        if (!choice) continue;

        const delta = choice.delta || {};

        if (delta.content) {
          fullOutput += delta.content;
          publish(userId, { type: 'task:progress', task_id: taskId, content: delta.content });
        }

        if (delta.tool_calls) {
          for (const tc of delta.tool_calls) {
            if (tc.function?.name) {
              currentToolCall = {
                id: tc.id || currentToolCall?.id,
                name: tc.function.name,
                arguments: tc.function.arguments || '',
              };
              publish(userId, {
                type: 'task:tool_start',
                task_id: taskId,
                tool_name: tc.function.name,
                tool_call_id: tc.id,
              });
            } else if (tc.function?.arguments && currentToolCall) {
              currentToolCall.arguments += tc.function.arguments;
            }
          }
        }

        if (choice.finish_reason === 'tool_calls' && currentToolCall) {
          publish(userId, {
            type: 'task:tool_end',
            task_id: taskId,
            tool_name: currentToolCall.name,
            tool_call_id: currentToolCall.id,
          });
          currentToolCall = null;
        }
      }

      const tokensUsed = lastUsage?.total_tokens
        || Math.ceil((input.length + fullOutput.length) / 4);

      await pool.query(
        `UPDATE tasks SET status='completed', output=$1, tokens_used=$2, completed_at=NOW()
         WHERE id=$3`,
        [fullOutput, tokensUsed, taskId],
      );

      await pool.query(
        `INSERT INTO usage_daily (user_id, date, tasks_count, tokens_used)
         VALUES ($1, CURRENT_DATE, 1, $2)
         ON CONFLICT (user_id, date)
         DO UPDATE SET tasks_count = usage_daily.tasks_count + 1,
                       tokens_used = usage_daily.tokens_used + $2`,
        [userId, tokensUsed],
      );

      publish(userId, { type: 'task:complete', task_id: taskId });
      return { taskId, status: 'completed' };
    } catch (err) {
      console.error(`[worker] task=${taskId} failed:`, err.message);

      await pool.query(
        "UPDATE tasks SET status='failed', output=$1, completed_at=NOW() WHERE id=$2",
        [err.message, taskId],
      );

      publish(userId, { type: 'task:error', task_id: taskId, error: err.message });
      throw err;
    }
  },
  {
    connection: new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: null }),
    concurrency: 5,
    limiter: { max: 20, duration: 60_000 },
  },
);

worker.on('completed', (job) => console.log(`[worker] done task=${job.data.taskId}`));
worker.on('failed', (job, err) => console.error(`[worker] fail task=${job?.data?.taskId}:`, err.message));

console.log('[worker] Task worker started — waiting for jobs');
