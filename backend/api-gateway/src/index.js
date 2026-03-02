const express = require('express');
const http = require('http');
const pg = require('pg');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const { Queue } = require('bullmq');
const Redis = require('ioredis');

const { healthCheck: ocHealthCheck } = require('./openclaw-client');
const { ensureBaseConfig, provisionAgent, deprovisionAgent, installStarterSkills, openclawAgentId } = require('./provisioner');
const { createWSRelay } = require('./ws-relay');

// Swift's .iso8601 decoder rejects fractional seconds — strip them.
pg.types.setTypeParser(1184, (val) =>
  new Date(val).toISOString().replace(/\.\d{3}Z$/, 'Z'),
);

const app = express();
app.use(express.json());

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';
const TASK_QUEUE = 'tasks';

const taskQueue = new Queue(TASK_QUEUE, {
  connection: new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: null }),
});

// Write base OpenClaw config on first boot
ensureBaseConfig();

// ──────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────

function generateTokens(userId) {
  const accessToken = jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '1h' });
  const refreshToken = crypto.randomUUID();
  return { access_token: accessToken, refresh_token: refreshToken, expires_in: 3600 };
}

async function storeRefreshToken(userId, token) {
  const hash = crypto.createHash('sha256').update(token).digest('hex');
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await pool.query(
    'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
    [userId, hash, expiresAt],
  );
}

function formatUser(row) {
  return {
    id: row.id,
    email: row.email,
    display_name: row.display_name,
    avatar_url: row.avatar_url || null,
    tier: row.tier,
    created_at: row.created_at,
  };
}

async function agentWithSkills(agentId) {
  const {
    rows: [agent],
  } = await pool.query('SELECT * FROM agents WHERE id = $1', [agentId]);
  if (!agent) return null;

  const { rows: skills } = await pool.query(
    'SELECT id, skill_id, name, icon, installed_at FROM agent_skills WHERE agent_id = $1 ORDER BY installed_at',
    [agentId],
  );

  return {
    id: agent.id,
    name: agent.name,
    persona: agent.persona,
    model: agent.model,
    skills,
    is_active: agent.is_active,
    openclaw_agent_id: agent.openclaw_agent_id,
    created_at: agent.created_at,
  };
}

// Tier-based limits
const TIER_LIMITS = {
  free:  { agents: 1,  dailyTasks: 10,  skills: 5,   tokens: 50_000  },
  pro:   { agents: 5,  dailyTasks: 100, skills: 50,  tokens: 500_000 },
  team:  { agents: 20, dailyTasks: -1,  skills: -1,  tokens: -1      },
};

async function getUserTier(userId) {
  const { rows: [user] } = await pool.query('SELECT tier FROM users WHERE id = $1', [userId]);
  return user?.tier || 'free';
}

// ──────────────────────────────────────────────
// Auth middleware
// ──────────────────────────────────────────────

function authenticate(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer '))
    return res.status(401).json({ error: 'Unauthorized' });

  try {
    const payload = jwt.verify(header.slice(7), JWT_SECRET);
    req.userId = payload.sub;
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

// ──────────────────────────────────────────────
// Auth routes
// ──────────────────────────────────────────────

app.post('/auth/register', async (req, res) => {
  try {
    const { email, password, display_name } = req.body;
    if (!email || !password || !display_name)
      return res.status(400).json({ error: 'Missing fields' });

    const hash = await bcrypt.hash(password, 10);
    const { rows } = await pool.query(
      `INSERT INTO users (email, password_hash, display_name)
       VALUES ($1, $2, $3) RETURNING *`,
      [email, hash, display_name],
    );
    const user = formatUser(rows[0]);
    const tokens = generateTokens(user.id);
    await storeRefreshToken(user.id, tokens.refresh_token);
    res.status(201).json({ user, tokens });
  } catch (err) {
    if (err.code === '23505')
      return res.status(409).json({ error: 'Email already registered' });
    console.error('register:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/auth/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    const { rows } = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
    if (!rows.length) return res.status(401).json({ error: 'Invalid credentials' });

    const valid = await bcrypt.compare(password, rows[0].password_hash);
    if (!valid) return res.status(401).json({ error: 'Invalid credentials' });

    const user = formatUser(rows[0]);
    const tokens = generateTokens(user.id);
    await storeRefreshToken(user.id, tokens.refresh_token);
    res.json({ user, tokens });
  } catch (err) {
    console.error('login:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/auth/apple', async (req, res) => {
  try {
    const { identity_token, full_name } = req.body;
    if (!identity_token) return res.status(400).json({ error: 'Missing identity token' });

    const appleUserId = crypto
      .createHash('sha256')
      .update(identity_token)
      .digest('hex')
      .slice(0, 44);

    let { rows } = await pool.query('SELECT * FROM users WHERE apple_user_id = $1', [appleUserId]);

    if (!rows.length) {
      const name = full_name || 'Apple User';
      const email = `${appleUserId.slice(0, 8)}@privaterelay.appleid.com`;
      ({ rows } = await pool.query(
        `INSERT INTO users (email, display_name, apple_user_id)
         VALUES ($1, $2, $3) RETURNING *`,
        [email, name, appleUserId],
      ));
    }

    const user = formatUser(rows[0]);
    const tokens = generateTokens(user.id);
    await storeRefreshToken(user.id, tokens.refresh_token);
    res.json({ user, tokens });
  } catch (err) {
    console.error('apple auth:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/auth/refresh', async (req, res) => {
  try {
    const { refresh_token } = req.body;
    if (!refresh_token) return res.status(400).json({ error: 'Missing refresh token' });

    const hash = crypto.createHash('sha256').update(refresh_token).digest('hex');
    const { rows } = await pool.query(
      'DELETE FROM refresh_tokens WHERE token_hash = $1 AND expires_at > NOW() RETURNING user_id',
      [hash],
    );
    if (!rows.length) return res.status(401).json({ error: 'Invalid refresh token' });

    const tokens = generateTokens(rows[0].user_id);
    await storeRefreshToken(rows[0].user_id, tokens.refresh_token);
    res.json(tokens);
  } catch (err) {
    console.error('refresh:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ──────────────────────────────────────────────
// Agent routes (with OpenClaw provisioning)
// ──────────────────────────────────────────────

app.get('/agents', authenticate, async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id FROM agents WHERE user_id = $1 ORDER BY created_at',
      [req.userId],
    );
    const agents = await Promise.all(rows.map((r) => agentWithSkills(r.id)));
    res.json({ agents });
  } catch (err) {
    console.error('get agents:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/agents', authenticate, async (req, res) => {
  try {
    const tier = await getUserTier(req.userId);
    const limits = TIER_LIMITS[tier];

    // Enforce agent limit
    const { rows: existing } = await pool.query(
      'SELECT COUNT(*)::int AS cnt FROM agents WHERE user_id = $1',
      [req.userId],
    );
    if (limits.agents > 0 && existing[0].cnt >= limits.agents) {
      return res.status(403).json({ error: `Agent limit reached (${limits.agents}). Upgrade to create more.` });
    }

    const { name, persona, model } = req.body;

    // 1) Insert into our DB
    const { rows } = await pool.query(
      `INSERT INTO agents (user_id, name, persona, model)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [req.userId, name, persona || 'Professional', model || 'gpt-4o-mini'],
    );
    const dbAgent = rows[0];

    // 2) Provision in OpenClaw (workspace + config entry)
    const { openclawAgentId: ocId, workspacePath } = provisionAgent({
      userId: req.userId,
      agentId: dbAgent.id,
      name,
      persona: persona || 'Professional',
      model: model || 'gpt-4o-mini',
    });

    // 3) Store the OpenClaw agent ID back in our DB
    await pool.query(
      'UPDATE agents SET openclaw_agent_id = $1, workspace_path = $2 WHERE id = $3',
      [ocId, workspacePath, dbAgent.id],
    );

    // 4) Install starter skills
    installStarterSkills(req.userId, dbAgent.id);
    for (const skill of CURATED_SKILLS.filter((s) => !s.requires_pro)) {
      await pool.query(
        `INSERT INTO agent_skills (agent_id, skill_id, name, icon, version)
         VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING`,
        [dbAgent.id, skill.id, skill.name, skill.icon, skill.version],
      );
    }

    const agent = await agentWithSkills(dbAgent.id);
    res.status(201).json(agent);
  } catch (err) {
    console.error('create agent:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.patch('/agents/:id', authenticate, async (req, res) => {
  try {
    const { name, persona, model } = req.body;
    const sets = [];
    const vals = [];
    let i = 1;

    if (name !== undefined) { sets.push(`name = $${i++}`); vals.push(name); }
    if (persona !== undefined) { sets.push(`persona = $${i++}`); vals.push(persona); }
    if (model !== undefined) { sets.push(`model = $${i++}`); vals.push(model); }
    if (!sets.length) return res.status(400).json({ error: 'Nothing to update' });

    sets.push('updated_at = NOW()');
    vals.push(req.params.id, req.userId);

    await pool.query(
      `UPDATE agents SET ${sets.join(', ')} WHERE id = $${i++} AND user_id = $${i}`,
      vals,
    );

    const agent = await agentWithSkills(req.params.id);
    if (!agent) return res.status(404).json({ error: 'Agent not found' });
    res.json(agent);
  } catch (err) {
    console.error('update agent:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.delete('/agents/:id', authenticate, async (req, res) => {
  try {
    const { rows: [agent] } = await pool.query(
      'SELECT * FROM agents WHERE id = $1 AND user_id = $2',
      [req.params.id, req.userId],
    );
    if (agent) deprovisionAgent(req.userId, agent.id);

    await pool.query('DELETE FROM agents WHERE id = $1 AND user_id = $2', [
      req.params.id,
      req.userId,
    ]);
    res.json({});
  } catch (err) {
    console.error('delete agent:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ──────────────────────────────────────────────
// Agent skills
// ──────────────────────────────────────────────

app.post('/agents/:agentId/skills', authenticate, async (req, res) => {
  try {
    const { skill_id } = req.body;
    const skill = CURATED_SKILLS.find((s) => s.id === skill_id);
    if (!skill) return res.status(404).json({ error: 'Skill not found' });

    // Check tier for pro-only skills
    if (skill.requires_pro) {
      const tier = await getUserTier(req.userId);
      if (tier === 'free') {
        return res.status(403).json({ error: 'This skill requires a Pro subscription' });
      }
    }

    await pool.query(
      `INSERT INTO agent_skills (agent_id, skill_id, name, icon, version)
       VALUES ($1, $2, $3, $4, $5) ON CONFLICT DO NOTHING`,
      [req.params.agentId, skill_id, skill.name, skill.icon, skill.version],
    );
    const agent = await agentWithSkills(req.params.agentId);
    res.json(agent);
  } catch (err) {
    console.error('install skill:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.delete('/agents/:agentId/skills/:skillId', authenticate, async (req, res) => {
  try {
    await pool.query(
      'DELETE FROM agent_skills WHERE agent_id = $1 AND skill_id = $2',
      [req.params.agentId, req.params.skillId],
    );
    res.json({});
  } catch (err) {
    console.error('remove skill:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ──────────────────────────────────────────────
// Tasks (real OpenClaw execution via BullMQ)
// ──────────────────────────────────────────────

app.get('/agents/:agentId/tasks', authenticate, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT id, agent_id, input, output, status, tokens_used, created_at, completed_at
       FROM tasks WHERE agent_id = $1 AND user_id = $2 ORDER BY created_at DESC`,
      [req.params.agentId, req.userId],
    );
    res.json({ tasks: rows });
  } catch (err) {
    console.error('get tasks:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/agents/:agentId/tasks', authenticate, async (req, res) => {
  try {
    const { input } = req.body;
    if (!input) return res.status(400).json({ error: 'Missing input' });

    // Rate limiting by tier
    const tier = await getUserTier(req.userId);
    const limits = TIER_LIMITS[tier];
    if (limits.dailyTasks > 0) {
      const { rows: [usage] } = await pool.query(
        `SELECT COALESCE(tasks_count, 0)::int AS cnt
         FROM usage_daily WHERE user_id = $1 AND date = CURRENT_DATE`,
        [req.userId],
      );
      if ((usage?.cnt || 0) >= limits.dailyTasks) {
        return res.status(429).json({ error: `Daily task limit reached (${limits.dailyTasks}). Try again tomorrow or upgrade.` });
      }
    }

    // Resolve OpenClaw agent ID
    const { rows: [agent] } = await pool.query(
      'SELECT openclaw_agent_id FROM agents WHERE id = $1 AND user_id = $2',
      [req.params.agentId, req.userId],
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    const ocAgentId = agent.openclaw_agent_id || openclawAgentId(req.userId, req.params.agentId);

    // Insert task row
    const { rows } = await pool.query(
      `INSERT INTO tasks (agent_id, user_id, input, status)
       VALUES ($1, $2, $3, 'queued') RETURNING id, status`,
      [req.params.agentId, req.userId, input],
    );
    const taskId = rows[0].id;

    // Enqueue for the BullMQ worker
    await taskQueue.add('run', {
      taskId,
      agentId: req.params.agentId,
      openclawAgentId: ocAgentId,
      userId: req.userId,
      input,
    });

    res.status(201).json({ task_id: taskId, status: 'queued' });
  } catch (err) {
    console.error('submit task:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/agents/:agentId/tasks/:taskId', authenticate, async (req, res) => {
  try {
    const { rows } = await pool.query(
      `SELECT id, agent_id, input, output, status, tokens_used, created_at, completed_at
       FROM tasks WHERE id = $1 AND agent_id = $2 AND user_id = $3`,
      [req.params.taskId, req.params.agentId, req.userId],
    );
    if (!rows.length) return res.status(404).json({ error: 'Task not found' });
    res.json(rows[0]);
  } catch (err) {
    console.error('get task:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ──────────────────────────────────────────────
// Skills catalog
// ──────────────────────────────────────────────

const CURATED_SKILLS = [
  {
    id: 'web-research',
    name: 'Web Research',
    description: 'Search the web, summarize articles, and extract key information from websites.',
    icon: 'globe',
    author: 'OpenClaw',
    category: 'Research',
    downloads: 15230,
    stars: 4521,
    version: '1.2.0',
    is_curated: true,
    requires_pro: false,
    permissions: ['internet'],
  },
  {
    id: 'email-drafts',
    name: 'Email Drafts',
    description: 'Compose, reply to, and polish professional emails in your preferred tone.',
    icon: 'envelope.fill',
    author: 'OpenClaw',
    category: 'Communication',
    downloads: 12800,
    stars: 3890,
    version: '1.1.0',
    is_curated: true,
    requires_pro: false,
    permissions: [],
  },
  {
    id: 'code-review',
    name: 'Code Review',
    description: 'Analyze code for bugs, style issues, and suggest improvements with explanations.',
    icon: 'chevron.left.forwardslash.chevron.right',
    author: 'OpenClaw',
    category: 'Development',
    downloads: 9450,
    stars: 3200,
    version: '2.0.1',
    is_curated: true,
    requires_pro: false,
    permissions: [],
  },
  {
    id: 'data-analysis',
    name: 'Data Analysis',
    description: 'Parse CSVs, calculate statistics, and generate insights from structured data.',
    icon: 'chart.bar.fill',
    author: 'OpenClaw',
    category: 'Data',
    downloads: 7600,
    stars: 2100,
    version: '1.0.3',
    is_curated: true,
    requires_pro: true,
    permissions: ['files'],
  },
  {
    id: 'meeting-notes',
    name: 'Meeting Notes',
    description: 'Summarize meeting transcripts into action items, decisions, and follow-ups.',
    icon: 'list.clipboard.fill',
    author: 'OpenClaw',
    category: 'Productivity',
    downloads: 11200,
    stars: 3750,
    version: '1.3.0',
    is_curated: true,
    requires_pro: false,
    permissions: [],
  },
  {
    id: 'blog-writer',
    name: 'Blog Writer',
    description: 'Generate well-structured blog posts, outlines, and social media summaries.',
    icon: 'doc.richtext.fill',
    author: 'Community',
    category: 'Writing',
    downloads: 6300,
    stars: 1850,
    version: '1.0.0',
    is_curated: false,
    requires_pro: false,
    permissions: [],
  },
  {
    id: 'workflow-builder',
    name: 'Workflow Builder',
    description: 'Create multi-step automated workflows triggered by schedules or events.',
    icon: 'arrow.triangle.branch',
    author: 'OpenClaw',
    category: 'Automation',
    downloads: 4100,
    stars: 1200,
    version: '0.9.0',
    is_curated: true,
    requires_pro: true,
    permissions: ['internet', 'files'],
  },
  {
    id: 'summarizer',
    name: 'Summarizer',
    description: 'Condense long documents, articles, or conversations into concise summaries.',
    icon: 'doc.text.magnifyingglass',
    author: 'OpenClaw',
    category: 'Productivity',
    downloads: 8900,
    stars: 2800,
    version: '1.4.0',
    is_curated: true,
    requires_pro: false,
    permissions: [],
  },
  {
    id: 'translator',
    name: 'Translator',
    description: 'Translate text between 50+ languages with context-aware accuracy.',
    icon: 'character.bubble.fill',
    author: 'OpenClaw',
    category: 'Communication',
    downloads: 7200,
    stars: 2400,
    version: '1.1.0',
    is_curated: true,
    requires_pro: false,
    permissions: [],
  },
  {
    id: 'calendar-planner',
    name: 'Calendar Planner',
    description: 'Plan your day, set reminders, and organize tasks with smart scheduling.',
    icon: 'calendar',
    author: 'Community',
    category: 'Productivity',
    downloads: 5400,
    stars: 1600,
    version: '1.0.0',
    is_curated: false,
    requires_pro: true,
    permissions: ['calendar'],
  },
];

const SKILL_CATEGORIES = [
  'Productivity', 'Research', 'Writing', 'Data',
  'Communication', 'Automation', 'Development',
];

app.get('/skills/catalog', authenticate, (req, res) => {
  let filtered = CURATED_SKILLS;
  const { category, q } = req.query;

  if (category) filtered = filtered.filter((s) => s.category === category);
  if (q) {
    const lower = q.toLowerCase();
    filtered = filtered.filter(
      (s) => s.name.toLowerCase().includes(lower) || s.description.toLowerCase().includes(lower),
    );
  }

  res.json({ skills: filtered, categories: SKILL_CATEGORIES, total_count: filtered.length });
});

app.get('/skills/:id', authenticate, (req, res) => {
  const skill = CURATED_SKILLS.find((s) => s.id === req.params.id);
  if (!skill) return res.status(404).json({ error: 'Skill not found' });
  res.json(skill);
});

// ──────────────────────────────────────────────
// Subscription
// ──────────────────────────────────────────────

app.get('/subscription', authenticate, async (req, res) => {
  try {
    const { rows: [sub] } = await pool.query(
      'SELECT * FROM subscriptions WHERE user_id = $1',
      [req.userId],
    );
    res.json({
      tier: sub?.tier || 'free',
      expires_at: sub?.expires_at || null,
      is_active: sub?.is_active || false,
      product_id: sub?.product_id || null,
    });
  } catch (err) {
    console.error('subscription:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/subscription/verify', authenticate, async (req, res) => {
  try {
    const { receipt_data, product_id } = req.body;
    // TODO: Verify receipt with Apple's App Store Server API.
    // For now, just record it.
    await pool.query(
      `INSERT INTO subscriptions (user_id, product_id, tier, is_active, expires_at)
       VALUES ($1, $2, 'pro', true, NOW() + INTERVAL '30 days')
       ON CONFLICT (user_id)
       DO UPDATE SET product_id = $2, tier = 'pro', is_active = true,
                     expires_at = NOW() + INTERVAL '30 days', updated_at = NOW()`,
      [req.userId, product_id],
    );
    await pool.query("UPDATE users SET tier = 'pro' WHERE id = $1", [req.userId]);
    res.json({ status: 'verified', tier: 'pro' });
  } catch (err) {
    console.error('verify subscription:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ──────────────────────────────────────────────
// Usage
// ──────────────────────────────────────────────

app.get('/usage', authenticate, async (req, res) => {
  try {
    const tier = await getUserTier(req.userId);
    const limits = TIER_LIMITS[tier];

    const {
      rows: [usage],
    } = await pool.query(
      `SELECT COALESCE(tasks_count, 0) as tasks_count, COALESCE(tokens_used, 0) as tokens_used
       FROM usage_daily WHERE user_id = $1 AND date = CURRENT_DATE`,
      [req.userId],
    );

    const {
      rows: [counts],
    } = await pool.query(
      `SELECT
         (SELECT COUNT(*) FROM agents WHERE user_id = $1)::int AS agent_count,
         (SELECT COUNT(*) FROM agent_skills AS s JOIN agents AS a ON a.id = s.agent_id WHERE a.user_id = $1)::int AS skill_count`,
      [req.userId],
    );

    res.json({
      tasks_today: usage?.tasks_count ?? 0,
      tasks_limit: limits.dailyTasks,
      tokens_used: usage?.tokens_used ?? 0,
      tokens_limit: limits.tokens,
      agent_count: counts?.agent_count ?? 0,
      agent_limit: limits.agents,
      skill_count: counts?.skill_count ?? 0,
      skill_limit: limits.skills,
    });
  } catch (err) {
    console.error('usage:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ──────────────────────────────────────────────
// Health
// ──────────────────────────────────────────────

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    const ocUp = await ocHealthCheck();
    res.json({
      status: 'ok',
      services: {
        database: 'healthy',
        openclaw_gateway: ocUp ? 'healthy' : 'degraded',
      },
    });
  } catch {
    res.status(503).json({ status: 'unhealthy' });
  }
});

// ──────────────────────────────────────────────
// Start server + WebSocket relay
// ──────────────────────────────────────────────

const PORT = process.env.PORT || 3000;
const server = http.createServer(app);
createWSRelay(server);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`API Gateway listening on :${PORT}`);
  console.log(`WebSocket relay available at ws://0.0.0.0:${PORT}/ws/agents/:agentId`);
});
