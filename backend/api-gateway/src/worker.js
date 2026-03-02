// BullMQ task worker — picks jobs from the "tasks" queue, calls OpenClaw
// chat completions (streaming), writes results to PostgreSQL, and publishes
// progress/completion events over Redis pub/sub for the WebSocket relay.

const { Worker } = require('bullmq');
const pg = require('pg');
const Redis = require('ioredis');
const { chatCompletionStream } = require('./openclaw-client');

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const redis = new Redis(process.env.REDIS_URL);

const QUEUE_NAME = 'tasks';

function publish(userId, event) {
  redis.publish(`task:${userId}`, JSON.stringify(event));
}

const worker = new Worker(
  QUEUE_NAME,
  async (job) => {
    const { taskId, openclawAgentId, userId, input } = job.data;
    console.log(`[worker] processing task=${taskId} agent=${openclawAgentId}`);

    try {
      await pool.query("UPDATE tasks SET status = 'running' WHERE id = $1", [taskId]);
      publish(userId, { type: 'task:progress', task_id: taskId, content: '' });

      const messages = [{ role: 'user', content: input }];
      let fullOutput = '';

      for await (const chunk of chatCompletionStream({
        agentId: openclawAgentId,
        messages,
        userId,
      })) {
        const delta = chunk.choices?.[0]?.delta?.content || '';
        if (delta) {
          fullOutput += delta;
          publish(userId, { type: 'task:progress', task_id: taskId, content: delta });
        }
      }

      const tokensUsed = Math.ceil((input.length + fullOutput.length) / 4);

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
