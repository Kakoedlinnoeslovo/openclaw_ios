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

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const redis = new Redis(process.env.REDIS_URL);

const QUEUE_NAME = 'tasks';
const HISTORY_LIMIT = 50;

const IMAGE_MIME_TYPES = new Set([
  'image/jpeg', 'image/png', 'image/webp', 'image/gif',
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
    const { taskId, agentId, openclawAgentId, userId, input, fileIds, imageData } = job.data;
    console.log(`[worker] processing task=${taskId} agent=${openclawAgentId} files=${(fileIds || []).length}`);

    try {
      await pool.query("UPDATE tasks SET status = 'running' WHERE id = $1", [taskId]);
      publish(userId, { type: 'task:progress', task_id: taskId, content: '' });

      const fileContents = await loadFileContents(fileIds);
      const userContent = buildUserMessage(input, fileContents, imageData);

      const history = await loadConversationHistory(agentId, userId);
      const messages = [...history, { role: 'user', content: userContent }];

      let fullOutput = '';
      let currentToolCall = null;
      let lastUsage = null;

      for await (const chunk of chatCompletionStream({
        agentId: openclawAgentId,
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

      publish(userId, { type: 'task:complete', task_id: taskId, content: fullOutput });
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
