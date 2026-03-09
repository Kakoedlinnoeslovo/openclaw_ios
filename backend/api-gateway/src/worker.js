// BullMQ task worker — picks jobs from the "tasks" queue, calls OpenClaw
// chat completions (streaming), writes results to PostgreSQL, and publishes
// progress/completion/tool events over Redis pub/sub for the WebSocket relay.

const { Worker } = require('bullmq');
const pg = require('pg');
const Redis = require('ioredis');
const { chatCompletionStream } = require('./openclaw-client');

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const redis = new Redis(process.env.REDIS_URL);

const QUEUE_NAME = 'tasks';
const HISTORY_LIMIT = 50;

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

const worker = new Worker(
  QUEUE_NAME,
  async (job) => {
    const { taskId, agentId, openclawAgentId, userId, input } = job.data;
    console.log(`[worker] processing task=${taskId} agent=${openclawAgentId}`);

    try {
      await pool.query("UPDATE tasks SET status = 'running' WHERE id = $1", [taskId]);
      publish(userId, { type: 'task:progress', task_id: taskId, content: '' });

      const history = await loadConversationHistory(agentId, userId);
      const messages = [...history, { role: 'user', content: input }];

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
