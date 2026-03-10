const express = require('express');
const http = require('http');
const fs = require('fs');
const path = require('path');
const pg = require('pg');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const multer = require('multer');
const { Queue } = require('bullmq');
const Redis = require('ioredis');

const { healthCheck: ocHealthCheck } = require('./openclaw-client');
const {
  ensureBaseConfig, provisionAgent, deprovisionAgent,
  installSkill, uninstallSkill, installStarterSkills,
  setSkillEnabled, getSkillConfig, setSkillConfig,
  installClawHubSkill, setSkillCredentials, extractInstallCommands,
  openclawAgentId, PERSONA_RECOMMENDATIONS, VALID_MODELS,
} = require('./provisioner');
const { createWSRelay } = require('./ws-relay');

// Swift's .iso8601 decoder rejects fractional seconds — strip them.
pg.types.setTypeParser(1184, (val) =>
  new Date(val).toISOString().replace(/\.\d{3}Z$/, 'Z'),
);

const app = express();
app.use(express.json({ limit: '30mb' }));

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret';
const TASK_QUEUE = 'tasks';

const taskQueue = new Queue(TASK_QUEUE, {
  connection: new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: null }),
});

ensureBaseConfig();

const UPLOADS_ROOT = path.join(process.env.OPENCLAW_HOME || '/openclaw-home', 'uploads');
fs.mkdirSync(UPLOADS_ROOT, { recursive: true });

const MAX_FILE_SIZE = 25 * 1024 * 1024; // 25 MB
const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp', 'image/gif',
  'application/pdf',
  'text/csv', 'text/plain', 'text/markdown', 'text/html',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/json', 'application/xml',
]);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_FILE_SIZE },
  fileFilter: (_req, file, cb) => {
    if (ALLOWED_MIME_TYPES.has(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new multer.MulterError('LIMIT_UNEXPECTED_FILE', `Unsupported file type: ${file.mimetype}`));
    }
  },
});

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
    `SELECT id, skill_id, name, icon, version, enabled, source, config, installed_at
     FROM agent_skills WHERE agent_id = $1 ORDER BY installed_at`,
    [agentId],
  );

  return {
    id: agent.id,
    name: agent.name,
    persona: agent.persona,
    model: agent.model,
    skills: skills.map(s => ({
      id: s.id,
      skill_id: s.skill_id,
      name: s.name,
      icon: s.icon,
      version: s.version,
      is_enabled: s.enabled,
      source: s.source,
      config: s.config || {},
      installed_at: s.installed_at,
    })),
    is_active: agent.is_active,
    openclaw_agent_id: agent.openclaw_agent_id,
    created_at: agent.created_at,
  };
}

// Tier-based limits
const TIER_LIMITS = {
  free:  { agents: -1, dailyTasks: -1, skills: -1, tokens: -1 },
  pro:   { agents: -1, dailyTasks: -1, skills: -1, tokens: -1 },
  team:  { agents: -1, dailyTasks: -1, skills: -1, tokens: -1 },
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

// Verify the agent belongs to the authenticated user
async function verifyAgentOwnership(req, res, next) {
  const agentId = req.params.agentId || req.params.id;
  if (!agentId) return res.status(400).json({ error: 'Missing agent ID' });

  const { rows } = await pool.query(
    'SELECT id FROM agents WHERE id = $1 AND user_id = $2',
    [agentId, req.userId],
  );
  if (!rows.length) return res.status(404).json({ error: 'Agent not found' });
  next();
}

// ──────────────────────────────────────────────
// Auth routes
// ──────────────────────────────────────────────

app.post('/auth/register', async (req, res) => {
  try {
    const { email, display_name, password } = req.body;
    if (!email || !password)
      return res.status(400).json({ error: 'Email and password are required' });

    const name = display_name || email.split('@')[0];
    const hash = await bcrypt.hash(password, 10);
    const { rows } = await pool.query(
      `INSERT INTO users (email, password_hash, display_name)
       VALUES ($1, $2, $3) RETURNING *`,
      [email, hash, name],
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
    if (!email || !password)
      return res.status(400).json({ error: 'Email and password are required' });

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

    const { rows: existing } = await pool.query(
      'SELECT COUNT(*)::int AS cnt FROM agents WHERE user_id = $1',
      [req.userId],
    );
    if (limits.agents > 0 && existing[0].cnt >= limits.agents) {
      return res.status(403).json({ error: `Agent limit reached (${limits.agents}). Upgrade to create more.` });
    }

    const { name, persona, model } = req.body;
    const chosenModel = model || 'gpt-5.2';
    if (!VALID_MODELS.includes(chosenModel)) {
      return res.status(400).json({
        error: `Unknown model "${chosenModel}". Valid models: ${VALID_MODELS.join(', ')}`,
      });
    }

    const { rows } = await pool.query(
      `INSERT INTO agents (user_id, name, persona, model)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [req.userId, name, persona || 'Professional', chosenModel],
    );
    const dbAgent = rows[0];

    const { openclawAgentId: ocId, workspacePath } = provisionAgent({
      userId: req.userId,
      agentId: dbAgent.id,
      name,
      persona: persona || 'Professional',
      model: model || 'gpt-5.2',
    });

    await pool.query(
      'UPDATE agents SET openclaw_agent_id = $1, workspace_path = $2 WHERE id = $3',
      [ocId, workspacePath, dbAgent.id],
    );

    // Install starter skills (filesystem + DB)
    installStarterSkills(req.userId, dbAgent.id);
    for (const skill of CURATED_SKILLS.filter((s) => !s.requires_pro)) {
      await pool.query(
        `INSERT INTO agent_skills (agent_id, skill_id, name, icon, version, enabled, source)
         VALUES ($1, $2, $3, $4, $5, true, 'curated') ON CONFLICT DO NOTHING`,
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
// Agent skills (with ownership + limit checks)
// ──────────────────────────────────────────────

// List skills for an agent
app.get('/agents/:agentId/skills', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    const { rows: skills } = await pool.query(
      `SELECT id, skill_id, name, icon, version, enabled, source, config, installed_at
       FROM agent_skills WHERE agent_id = $1 ORDER BY installed_at`,
      [req.params.agentId],
    );
    res.json({
      skills: skills.map(s => ({
        id: s.id,
        skill_id: s.skill_id,
        name: s.name,
        icon: s.icon,
        version: s.version,
        is_enabled: s.enabled,
        source: s.source,
        config: s.config || {},
        installed_at: s.installed_at,
      })),
    });
  } catch (err) {
    console.error('list agent skills:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Install a curated skill
app.post('/agents/:agentId/skills', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    const { skill_id } = req.body;
    const skill = CURATED_SKILLS.find((s) => s.id === skill_id);
    if (!skill) return res.status(404).json({ error: 'Skill not found in catalog' });

    // Check tier for pro-only skills
    if (skill.requires_pro) {
      const tier = await getUserTier(req.userId);
      if (tier === 'free') {
        return res.status(403).json({ error: 'This skill requires a Pro subscription' });
      }
    }

    // Enforce skill count limit
    const tier = await getUserTier(req.userId);
    const limits = TIER_LIMITS[tier];
    if (limits.skills > 0) {
      const { rows: [{ cnt }] } = await pool.query(
        'SELECT COUNT(*)::int AS cnt FROM agent_skills WHERE agent_id = $1',
        [req.params.agentId],
      );
      if (cnt >= limits.skills) {
        return res.status(403).json({
          error: `Skill limit reached (${limits.skills}). Upgrade to install more.`,
        });
      }
    }

    // Write SKILL.md into the agent's workspace
    installSkill(req.userId, req.params.agentId, skill_id);

    await pool.query(
      `INSERT INTO agent_skills (agent_id, skill_id, name, icon, version, enabled, source)
       VALUES ($1, $2, $3, $4, $5, true, 'curated') ON CONFLICT DO NOTHING`,
      [req.params.agentId, skill_id, skill.name, skill.icon, skill.version],
    );
    const agent = await agentWithSkills(req.params.agentId);
    res.json(agent);
  } catch (err) {
    console.error('install skill:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Install a ClawHub community skill
app.post('/agents/:agentId/skills/clawhub', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    const { slug } = req.body;
    if (!slug) return res.status(400).json({ error: 'Missing skill slug' });

    // Enforce skill count limit
    const tier = await getUserTier(req.userId);
    const limits = TIER_LIMITS[tier];
    if (limits.skills > 0) {
      const { rows: [{ cnt }] } = await pool.query(
        'SELECT COUNT(*)::int AS cnt FROM agent_skills WHERE agent_id = $1',
        [req.params.agentId],
      );
      if (cnt >= limits.skills) {
        return res.status(403).json({
          error: `Skill limit reached (${limits.skills}). Upgrade to install more.`,
        });
      }
    }

    // Look up catalog metadata so the provisioner can generate a useful SKILL.md.
    // Check exact slug, then aliases, then fall back to matching on the skill
    // name (last slug segment) so alternate prefixes resolve.
    const catalogEntry = CLAWHUB_SKILLS.find(s => s.slug === slug)
      || CLAWHUB_SKILLS.find(s => s.aliases?.includes(slug))
      || CLAWHUB_SKILLS.find(s => s.slug.split('/').pop() === slug.split('/').pop())
      || null;

    // Download + provision the ClawHub skill via CLI
    const result = installClawHubSkill(req.userId, req.params.agentId, slug, catalogEntry);

    await pool.query(
      `INSERT INTO agent_skills (agent_id, skill_id, name, icon, version, enabled, source)
       VALUES ($1, $2, $3, $4, $5, true, $6) ON CONFLICT DO NOTHING`,
      [req.params.agentId, result.skillId, result.name, result.icon, result.version, result.source],
    );

    // Auto-install CLI dependencies if the skill needs them
    let setupTaskId = null;
    if (result.install_commands?.length) {
      const { rows: [agentRow] } = await pool.query(
        'SELECT openclaw_agent_id FROM agents WHERE id = $1',
        [req.params.agentId],
      );
      const ocAgentId = agentRow?.openclaw_agent_id
        || openclawAgentId(req.userId, req.params.agentId);

      const cmds = result.install_commands.map(c => `- \`${c}\``).join('\n');
      const setupInput = [
        `[SYSTEM] A new skill "${result.name}" was just installed.`,
        `Install its required CLI dependencies by running these commands:`,
        cmds,
        ``,
        `Run each command using exec. Do NOT ask for confirmation.`,
        `If brew is not available, try the npm equivalent.`,
        `After installing, verify the tool works by running it with --help or --version.`,
        `Reply with a short summary of what was installed and whether it succeeded.`,
      ].join('\n');

      const { rows: [setupTask] } = await pool.query(
        `INSERT INTO tasks (agent_id, user_id, input, status)
         VALUES ($1, $2, $3, 'queued') RETURNING id`,
        [req.params.agentId, req.userId, setupInput],
      );
      setupTaskId = setupTask.id;

      await taskQueue.add('run', {
        taskId: setupTaskId,
        agentId: req.params.agentId,
        openclawAgentId: ocAgentId,
        userId: req.userId,
        input: setupInput,
      });

      console.log(`[setup] queued dependency install for ${slug} → task ${setupTaskId}`);
    }

    const agent = await agentWithSkills(req.params.agentId);

    const response = {
      ...agent,
      setup_required: result.setup_required || false,
      setup_requirements: result.setup_requirements || [],
      setup_task_id: setupTaskId,
    };

    if (result.fallback_used === 'generic') {
      response.install_warning = `The ClawHub CLI could not download "${slug}". A generic skill stub was installed. The skill may have limited functionality.`;
    } else if (result.fallback_used === 'bundled') {
      response.install_note = `Installed using bundled skill content for "${result.skillId}".`;
    }

    res.json(response);
  } catch (err) {
    console.error('install clawhub skill:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Enable/disable a skill or update its config
app.patch('/agents/:agentId/skills/:skillId', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    const { enabled, config } = req.body;

    // Verify skill belongs to this agent
    const { rows: [existing] } = await pool.query(
      'SELECT id, skill_id FROM agent_skills WHERE agent_id = $1 AND skill_id = $2',
      [req.params.agentId, req.params.skillId],
    );
    if (!existing) return res.status(404).json({ error: 'Skill not installed on this agent' });

    if (enabled !== undefined) {
      await pool.query(
        'UPDATE agent_skills SET enabled = $1 WHERE agent_id = $2 AND skill_id = $3',
        [enabled, req.params.agentId, req.params.skillId],
      );
      setSkillEnabled(req.userId, req.params.agentId, req.params.skillId, enabled);
    }

    if (config !== undefined) {
      await pool.query(
        'UPDATE agent_skills SET config = $1 WHERE agent_id = $2 AND skill_id = $3',
        [JSON.stringify(config), req.params.agentId, req.params.skillId],
      );
      setSkillConfig(req.userId, req.params.agentId, req.params.skillId, config);
    }

    const agent = await agentWithSkills(req.params.agentId);
    res.json(agent);
  } catch (err) {
    console.error('update skill:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Set credentials for a skill that requires external service configuration
app.post('/agents/:agentId/skills/:skillId/credentials', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    const { credentials } = req.body;
    if (!credentials || typeof credentials !== 'object') {
      return res.status(400).json({ error: 'Missing credentials object' });
    }

    const { rows: [existing] } = await pool.query(
      'SELECT id FROM agent_skills WHERE agent_id = $1 AND skill_id = $2',
      [req.params.agentId, req.params.skillId],
    );
    if (!existing) return res.status(404).json({ error: 'Skill not installed on this agent' });

    // Inject credentials into the agent's OpenClaw environment
    setSkillCredentials(req.userId, req.params.agentId, req.params.skillId, credentials);

    // Mark skill as configured in DB
    await pool.query(
      `UPDATE agent_skills SET config = config || $1 WHERE agent_id = $2 AND skill_id = $3`,
      [JSON.stringify({ _configured: true }), req.params.agentId, req.params.skillId],
    );

    res.json({ status: 'configured' });
  } catch (err) {
    console.error('set skill credentials:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Manually trigger dependency setup for an already-installed skill
app.post('/agents/:agentId/skills/:skillId/setup', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    const { rows: [existing] } = await pool.query(
      'SELECT id, skill_id FROM agent_skills WHERE agent_id = $1 AND skill_id = $2',
      [req.params.agentId, req.params.skillId],
    );
    if (!existing) return res.status(404).json({ error: 'Skill not installed on this agent' });

    const OC_HOME = process.env.OPENCLAW_HOME || '/openclaw-home';
    const ocId = openclawAgentId(req.userId, req.params.agentId);
    const skillDir = require('path').join(OC_HOME, 'workspaces', ocId, 'skills', req.params.skillId);

    const commands = extractInstallCommands(skillDir);
    if (!commands.length) {
      return res.json({ status: 'no_setup_needed', message: 'No install commands found in SKILL.md' });
    }

    const { rows: [agentRow] } = await pool.query(
      'SELECT openclaw_agent_id FROM agents WHERE id = $1',
      [req.params.agentId],
    );
    const ocAgentId = agentRow?.openclaw_agent_id || ocId;

    const cmds = commands.map(c => `- \`${c}\``).join('\n');
    const setupInput = [
      `[SYSTEM] Install dependencies for skill "${req.params.skillId}":`,
      cmds,
      ``,
      `Run each command using exec. Do NOT ask for confirmation.`,
      `If brew is not available, try the npm equivalent.`,
      `After installing, verify the tool works with --help or --version.`,
      `Reply with a short summary of what was installed.`,
    ].join('\n');

    const { rows: [task] } = await pool.query(
      `INSERT INTO tasks (agent_id, user_id, input, status)
       VALUES ($1, $2, $3, 'queued') RETURNING id`,
      [req.params.agentId, req.userId, setupInput],
    );

    await taskQueue.add('run', {
      taskId: task.id,
      agentId: req.params.agentId,
      openclawAgentId: ocAgentId,
      userId: req.userId,
      input: setupInput,
    });

    res.json({ status: 'setup_queued', setup_task_id: task.id, install_commands: commands });
  } catch (err) {
    console.error('skill setup:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Uninstall a skill
app.delete('/agents/:agentId/skills/:skillId', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    uninstallSkill(req.userId, req.params.agentId, req.params.skillId);

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
      `SELECT id, agent_id, input, output, status, tokens_used, file_ids, created_at, completed_at
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
    const { input, image_data, web_search, file_ids } = req.body;
    if (!input) return res.status(400).json({ error: 'Missing input' });

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

    const { rows: [agent] } = await pool.query(
      'SELECT openclaw_agent_id FROM agents WHERE id = $1 AND user_id = $2',
      [req.params.agentId, req.userId],
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    const ocAgentId = agent.openclaw_agent_id || openclawAgentId(req.userId, req.params.agentId);

    let validFileIds = [];
    if (Array.isArray(file_ids) && file_ids.length > 0) {
      const { rows: ownedFiles } = await pool.query(
        'SELECT id FROM files WHERE id = ANY($1) AND user_id = $2',
        [file_ids, req.userId],
      );
      validFileIds = ownedFiles.map(f => f.id);
    }

    let taskInput = input;
    if (web_search) {
      taskInput = `[WEB_SEARCH] ${input}`;
    }

    const { rows } = await pool.query(
      `INSERT INTO tasks (agent_id, user_id, input, status, file_ids)
       VALUES ($1, $2, $3, 'queued', $4) RETURNING id, status`,
      [req.params.agentId, req.userId, taskInput, validFileIds],
    );
    const taskId = rows[0].id;

    if (validFileIds.length > 0) {
      await pool.query(
        'UPDATE files SET task_id = $1 WHERE id = ANY($2)',
        [taskId, validFileIds],
      );
    }

    const jobData = {
      taskId,
      agentId: req.params.agentId,
      openclawAgentId: ocAgentId,
      userId: req.userId,
      input: taskInput,
    };
    if (validFileIds.length > 0) {
      jobData.fileIds = validFileIds;
    }
    if (image_data) {
      jobData.imageData = image_data;
    }
    if (web_search) {
      jobData.webSearch = true;
    }

    await taskQueue.add('run', jobData);

    res.status(201).json({ task_id: taskId, status: 'queued' });
  } catch (err) {
    console.error('submit task:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.delete('/agents/:agentId/tasks', authenticate, async (req, res) => {
  try {
    const { rows: [agent] } = await pool.query(
      'SELECT id FROM agents WHERE id = $1 AND user_id = $2',
      [req.params.agentId, req.userId],
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    const { rowCount } = await pool.query(
      "DELETE FROM tasks WHERE agent_id = $1 AND user_id = $2 AND status NOT IN ('queued', 'running')",
      [req.params.agentId, req.userId],
    );
    res.json({ deleted: rowCount });
  } catch (err) {
    console.error('clear tasks:', err);
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
    requires_pro: false,
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
    requires_pro: false,
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
    requires_pro: false,
    permissions: ['calendar'],
  },
];

const SKILL_CATEGORIES = [
  'Productivity', 'Research', 'Writing', 'Data',
  'Communication', 'Automation', 'Development',
  'AI/ML', 'Utility', 'Web', 'Science',
  'Media', 'Social', 'Finance', 'Location', 'Business',
];

// ClawHub community skills – browsable natively from the iOS app.
// Sourced from https://clawhub.ai/skills?sort=downloads&nonSuspicious=true
// and cross-referenced with bundled skills in backend/openclaw/skills/.
const CLAWHUB_SKILLS = [
  // ── Featured / Partner skills ────────────────────────
  {
    slug: 'openinterpreter/open-interpreter',
    name: 'Open Interpreter',
    description: 'Run code locally in Python, JavaScript, and Shell. Execute tasks on your machine through natural language.',
    icon: 'terminal.fill',
    author: 'Open Interpreter',
    category: 'Development',
    downloads: 32400,
    stars: 51000,
    version: '0.3.7',
  },
  {
    slug: 'crewai/crewai-tools',
    name: 'CrewAI Tools',
    description: 'A toolkit of pre-built tools for web scraping, file operations, and API integrations.',
    icon: 'wrench.and.screwdriver.fill',
    author: 'CrewAI',
    category: 'Automation',
    downloads: 18200,
    stars: 19500,
    version: '0.9.0',
  },

  // ── Top ClawHub skills by downloads (nonSuspicious) ──
  {
    slug: 'community/wacli',
    name: 'Wacli',
    description: 'Versatile CLI tool for command-line operations, scripting, and terminal automation.',
    icon: 'apple.terminal.fill',
    author: 'Community',
    category: 'Utility',
    downloads: 16415,
    stars: 37,
    version: '1.0.0',
  },
  {
    slug: 'community/byterover',
    name: 'ByteRover',
    description: 'Multi-purpose task handler for diverse automation and data processing needs.',
    icon: 'cpu.fill',
    author: 'Community',
    category: 'Utility',
    downloads: 16004,
    stars: 36,
    version: '1.0.0',
  },
  {
    slug: 'community/gog',
    name: 'Gog',
    description: 'Google Workspace integration — search, docs, sheets, and calendar from your agent.',
    icon: 'globe.americas.fill',
    author: 'Community',
    category: 'Development',
    downloads: 14313,
    stars: 48,
    version: '1.0.0',
  },
  {
    slug: 'community/image-gen',
    aliases: ['wells1137/image-gen'],
    name: 'Image Generator',
    description: 'Generate images from text prompts using Stable Diffusion and DALL-E APIs.',
    icon: 'photo.artframe',
    author: 'Community',
    category: 'Media',
    downloads: 15800,
    stars: 6400,
    version: '1.2.0',
  },
  {
    slug: 'community/slack-assistant',
    name: 'Slack Assistant',
    description: 'Send messages, summarize channels, and respond to threads in Slack workspaces.',
    icon: 'bubble.left.and.bubble.right.fill',
    author: 'Community',
    category: 'Social',
    downloads: 14500,
    stars: 5200,
    version: '1.3.0',
  },
  {
    slug: 'community/github-issues',
    name: 'GitHub Issues',
    description: 'Create, search, and manage GitHub issues. Triage bugs and track feature requests.',
    icon: 'ladybug.fill',
    author: 'Community',
    category: 'Development',
    downloads: 12300,
    stars: 4100,
    version: '1.2.0',
  },
  {
    slug: 'community/agent-browser',
    name: 'Agent Browser',
    description: 'Browser automation for web interactions — scraping, form filling, and page navigation.',
    icon: 'safari.fill',
    author: 'Community',
    category: 'Web',
    downloads: 11836,
    stars: 43,
    version: '1.0.0',
  },
  {
    slug: 'community/pdf-reader',
    name: 'PDF Reader',
    description: 'Extract text, tables, and images from PDF documents for analysis and summarization.',
    icon: 'doc.text.fill',
    author: 'Community',
    category: 'Data',
    downloads: 11200,
    stars: 3800,
    version: '1.0.1',
  },
  {
    slug: 'community/summarize',
    name: 'Summarize',
    description: 'Intelligent text summarization — condense long documents, articles, and conversations.',
    icon: 'doc.text.magnifyingglass',
    author: 'Community',
    category: 'Productivity',
    downloads: 10956,
    stars: 28,
    version: '1.0.0',
  },
  {
    slug: 'community/github',
    name: 'GitHub',
    description: 'Repository and workflow management — PRs, commits, actions, and code review.',
    icon: 'chevron.left.forwardslash.chevron.right',
    author: 'Community',
    category: 'Development',
    downloads: 10611,
    stars: 15,
    version: '1.0.0',
  },
  {
    slug: 'community/sonoscli',
    name: 'Sonoscli',
    description: 'Control Sonos speakers — play, pause, group, and manage your audio system via CLI.',
    icon: 'hifispeaker.fill',
    author: 'Community',
    category: 'Media',
    downloads: 10304,
    stars: 6,
    version: '1.0.0',
  },
  {
    slug: 'community/sql-assistant',
    name: 'SQL Assistant',
    description: 'Generate, explain, and optimize SQL queries. Connect to PostgreSQL, MySQL, and SQLite.',
    icon: 'cylinder.split.1x2.fill',
    author: 'Community',
    category: 'Data',
    downloads: 10400,
    stars: 3600,
    version: '1.1.0',
  },
  {
    slug: 'community/notion-sync',
    name: 'Notion Sync',
    description: 'Read and write Notion pages and databases. Keep your knowledge base up to date.',
    icon: 'doc.on.doc.fill',
    author: 'Community',
    category: 'Productivity',
    downloads: 9800,
    stars: 2900,
    version: '1.0.3',
  },
  {
    slug: 'community/weather',
    name: 'Weather',
    description: 'Real-time weather information and forecasts for any location worldwide.',
    icon: 'cloud.sun.fill',
    author: 'Community',
    category: 'Location',
    downloads: 9002,
    stars: 13,
    version: '1.0.0',
  },
  {
    slug: 'community/unit-test-writer',
    name: 'Unit Test Writer',
    description: 'Automatically generate unit tests for Python, JavaScript, and TypeScript code.',
    icon: 'checkmark.diamond.fill',
    author: 'Community',
    category: 'Development',
    downloads: 8900,
    stars: 3100,
    version: '1.0.2',
  },
  {
    slug: 'community/humanize-ai-text',
    name: 'Humanize AI Text',
    description: 'Transform AI-generated text to sound more natural and human-like. Reduce robotic tone.',
    icon: 'person.text.rectangle.fill',
    author: 'Community',
    category: 'Writing',
    downloads: 8771,
    stars: 20,
    version: '1.0.0',
  },
  {
    slug: 'community/arxiv-researcher',
    name: 'arXiv Researcher',
    description: 'Search and summarize academic papers from arXiv. Find relevant research by topic or keyword.',
    icon: 'book.pages.fill',
    author: 'Community',
    category: 'Research',
    downloads: 8700,
    stars: 3200,
    version: '1.1.0',
  },
  {
    slug: 'community/tavily-web-search',
    name: 'Tavily Web Search',
    description: 'Advanced web search powered by Tavily for accurate, real-time search results and scraping.',
    icon: 'magnifyingglass',
    author: 'Community',
    category: 'Web',
    downloads: 8142,
    stars: 10,
    version: '1.0.0',
  },
  {
    slug: 'community/bird',
    name: 'Bird',
    description: 'General-purpose utility for file operations, text processing, and everyday tasks.',
    icon: 'bird.fill',
    author: 'Community',
    category: 'Utility',
    downloads: 7767,
    stars: 27,
    version: '1.0.0',
  },
  {
    slug: 'community/social-poster',
    name: 'Social Media Poster',
    description: 'Draft and schedule posts for Twitter/X, LinkedIn, and Mastodon with AI-generated captions.',
    icon: 'megaphone.fill',
    author: 'Community',
    category: 'Social',
    downloads: 7600,
    stars: 2100,
    version: '0.8.0',
  },
  {
    slug: 'community/find-skills',
    name: 'Find Skills',
    description: 'Discover and manage ClawHub skills — search, filter, and install from the registry.',
    icon: 'magnifyingglass.circle.fill',
    author: 'Community',
    category: 'Utility',
    downloads: 7077,
    stars: 15,
    version: '1.0.0',
  },
  {
    slug: 'community/proactive-agent',
    name: 'Proactive Agent',
    description: 'Proactive task execution framework — anticipates needs and acts autonomously on schedule.',
    icon: 'bolt.circle.fill',
    author: 'Community',
    category: 'AI/ML',
    downloads: 7010,
    stars: 49,
    version: '1.0.0',
  },
  {
    slug: 'community/markdown-writer',
    name: 'Markdown Writer',
    description: 'Create polished Markdown documents, READMEs, and documentation with formatting helpers.',
    icon: 'text.document.fill',
    author: 'Community',
    category: 'Writing',
    downloads: 6200,
    stars: 1800,
    version: '1.0.0',
  },
  {
    slug: 'community/obsidian',
    name: 'Obsidian',
    description: 'Obsidian knowledge base integration — manage notes, backlinks, and knowledge graphs.',
    icon: 'note.text',
    author: 'Community',
    category: 'Productivity',
    downloads: 5791,
    stars: 12,
    version: '1.0.0',
  },
  {
    slug: 'community/nano-banana-pro',
    name: 'Nano Banana Pro',
    description: 'Advanced text processing and document analysis for professional content editing.',
    icon: 'doc.richtext.fill',
    author: 'Community',
    category: 'Productivity',
    downloads: 5704,
    stars: 20,
    version: '1.0.0',
  },

  // ── Media & Audio ────────────────────────────────────
  {
    slug: 'community/youtube-factory',
    name: 'YouTube Factory',
    description: 'YouTube channel management — video processing, metadata, and content automation.',
    icon: 'play.rectangle.fill',
    author: 'Community',
    category: 'Media',
    downloads: 4200,
    stars: 18,
    version: '1.0.0',
  },
  {
    slug: 'community/openai-whisper',
    name: 'OpenAI Whisper',
    description: 'Speech-to-text transcription using OpenAI Whisper. Transcribe audio and video files.',
    icon: 'waveform.circle.fill',
    author: 'Community',
    category: 'Media',
    downloads: 3800,
    stars: 22,
    version: '1.0.0',
  },
  {
    slug: 'community/video-frames',
    name: 'Video Frames',
    description: 'Extract frames from video files for analysis, thumbnails, and visual processing.',
    icon: 'film.stack.fill',
    author: 'Community',
    category: 'Media',
    downloads: 2900,
    stars: 8,
    version: '1.0.0',
  },
  {
    slug: 'community/spotify-player',
    name: 'Spotify Player',
    description: 'Control Spotify playback — play, pause, search, and manage playlists via your agent.',
    icon: 'music.note.list',
    author: 'Community',
    category: 'Media',
    downloads: 3100,
    stars: 14,
    version: '1.0.0',
  },
  {
    slug: 'community/youtube-watcher',
    name: 'YouTube Watcher',
    description: 'Monitor YouTube channels for new content. Get notifications on new uploads.',
    icon: 'play.tv.fill',
    author: 'Community',
    category: 'Media',
    downloads: 2700,
    stars: 27,
    version: '1.0.0',
  },

  // ── Web & Search ─────────────────────────────────────
  {
    slug: 'community/google-search',
    name: 'Google Search',
    description: 'Search Google directly from your agent. Get web results, images, and news.',
    icon: 'globe.desk',
    author: 'Community',
    category: 'Web',
    downloads: 4500,
    stars: 12,
    version: '1.0.0',
  },
  {
    slug: 'community/web-scraper',
    name: 'Web Scraper',
    description: 'Extract structured data from websites. CSS selectors, pagination, and data export.',
    icon: 'network',
    author: 'Community',
    category: 'Web',
    downloads: 3200,
    stars: 9,
    version: '1.0.0',
  },
  {
    slug: 'community/http-client',
    name: 'HTTP Client',
    description: 'Make HTTP requests to APIs and web services. REST, GraphQL, and webhook support.',
    icon: 'arrow.up.arrow.down.circle.fill',
    author: 'Community',
    category: 'Web',
    downloads: 2800,
    stars: 7,
    version: '1.0.0',
  },

  // ── Social & Communication ───────────────────────────
  {
    slug: 'community/twitter-bot',
    name: 'Twitter/X Bot',
    description: 'Automate Twitter/X posting, engagement, and thread creation.',
    icon: 'at.circle.fill',
    author: 'Community',
    category: 'Social',
    downloads: 4100,
    stars: 19,
    version: '1.0.0',
  },
  {
    slug: 'community/discord-manager',
    name: 'Discord Manager',
    description: 'Discord server management — moderate, automate, and interact with channels and users.',
    icon: 'gamecontroller.fill',
    author: 'Community',
    category: 'Social',
    downloads: 3600,
    stars: 15,
    version: '1.0.0',
  },
  {
    slug: 'community/telegram-bot',
    name: 'Telegram Bot',
    description: 'Build and manage Telegram bots — send messages, handle commands, and inline queries.',
    icon: 'paperplane.fill',
    author: 'Community',
    category: 'Social',
    downloads: 3200,
    stars: 11,
    version: '1.0.0',
  },
  {
    slug: 'community/slack-integration',
    name: 'Slack Integration',
    description: 'Deep Slack workspace integration — channels, threads, reactions, and app commands.',
    icon: 'number.circle.fill',
    author: 'Community',
    category: 'Social',
    downloads: 2900,
    stars: 10,
    version: '1.0.0',
  },

  // ── AI/ML ────────────────────────────────────────────
  {
    slug: 'community/humanizer',
    name: 'Humanizer',
    description: 'Make AI-generated text more natural and human-like. Improve readability and engagement.',
    icon: 'person.crop.circle.badge.checkmark',
    author: 'Community',
    category: 'AI/ML',
    downloads: 3800,
    stars: 28,
    version: '1.0.0',
  },
  {
    slug: 'community/home-assistant',
    name: 'Home Assistant',
    description: 'Smart home integration — control lights, switches, sensors, and automations.',
    icon: 'house.fill',
    author: 'Community',
    category: 'AI/ML',
    downloads: 3400,
    stars: 28,
    version: '1.0.0',
  },
  {
    slug: 'community/ai-model-router',
    name: 'AI Model Router',
    description: 'Intelligently route requests to the optimal AI model based on cost and capability.',
    icon: 'arrow.triangle.branch',
    author: 'Community',
    category: 'AI/ML',
    downloads: 3100,
    stars: 24,
    version: '1.0.0',
  },
  {
    slug: 'community/prompt-engineer',
    name: 'Prompt Engineer',
    description: 'Advanced prompt optimization — craft better prompts for higher quality AI outputs.',
    icon: 'text.cursor',
    author: 'Community',
    category: 'AI/ML',
    downloads: 2800,
    stars: 22,
    version: '1.0.0',
  },
  {
    slug: 'community/coding-agent',
    name: 'Coding Agent',
    description: 'Autonomous coding assistant — write, debug, refactor, and review code across languages.',
    icon: 'curlybraces',
    author: 'Community',
    category: 'AI/ML',
    downloads: 4500,
    stars: 35,
    version: '1.0.0',
  },

  // ── Finance ──────────────────────────────────────────
  {
    slug: 'community/stock-analysis',
    name: 'Stock Analysis',
    description: 'Comprehensive stock market analysis — equity research, charts, and fundamental data.',
    icon: 'chart.line.uptrend.xyaxis',
    author: 'Community',
    category: 'Finance',
    downloads: 2400,
    stars: 8,
    version: '1.0.0',
  },
  {
    slug: 'community/crypto-cog',
    name: 'Crypto Cog',
    description: 'Cryptocurrency research and trading signals — price tracking, analysis, and alerts.',
    icon: 'bitcoinsign.circle.fill',
    author: 'Community',
    category: 'Finance',
    downloads: 2100,
    stars: 6,
    version: '1.0.0',
  },
  {
    slug: 'community/fin-cog',
    name: 'Fin Cog',
    description: 'Financial data analysis and modeling — revenue, expenses, and investment metrics.',
    icon: 'dollarsign.circle.fill',
    author: 'Community',
    category: 'Finance',
    downloads: 1800,
    stars: 5,
    version: '1.0.0',
  },
  {
    slug: 'community/portfolio-manager',
    name: 'Portfolio Manager',
    description: 'Track and rebalance investment portfolios. Asset allocation and performance analytics.',
    icon: 'chart.pie.fill',
    author: 'Community',
    category: 'Finance',
    downloads: 1500,
    stars: 4,
    version: '1.0.0',
  },

  // ── Location ─────────────────────────────────────────
  {
    slug: 'community/goplaces',
    name: 'GoPlaces',
    description: 'Location-based services — find places, get directions, and explore points of interest.',
    icon: 'map.fill',
    author: 'Community',
    category: 'Location',
    downloads: 3200,
    stars: 10,
    version: '1.0.0',
  },

  // ── Productivity & Notes ─────────────────────────────
  {
    slug: 'community/apple-notes',
    name: 'Apple Notes',
    description: 'Read and write Apple Notes. Search, create, and organize notes from your agent.',
    icon: 'note.text',
    author: 'Community',
    category: 'Productivity',
    downloads: 2800,
    stars: 9,
    version: '1.0.0',
  },
  {
    slug: 'community/apple-reminders',
    name: 'Apple Reminders',
    description: 'Manage Apple Reminders — create, complete, and organize tasks and lists.',
    icon: 'checklist',
    author: 'Community',
    category: 'Productivity',
    downloads: 2500,
    stars: 8,
    version: '1.0.0',
  },
  {
    slug: 'community/trello',
    name: 'Trello',
    description: 'Trello board management — cards, lists, labels, and team collaboration.',
    icon: 'square.grid.2x2.fill',
    author: 'Community',
    category: 'Productivity',
    downloads: 2400,
    stars: 7,
    version: '1.0.0',
  },
  {
    slug: 'community/things-mac',
    name: 'Things',
    description: 'Things 3 task manager integration — projects, areas, and GTD workflows on Mac.',
    icon: 'checkmark.circle',
    author: 'Community',
    category: 'Productivity',
    downloads: 2200,
    stars: 11,
    version: '1.0.0',
  },
  {
    slug: 'community/model-usage',
    name: 'Model Usage',
    description: 'Track and optimize AI model usage and costs. Monitor API consumption and budgets.',
    icon: 'gauge.with.dots.needle.bottom.50percent',
    author: 'Community',
    category: 'Productivity',
    downloads: 1800,
    stars: 5,
    version: '1.0.0',
  },

  // ── Data & Science ───────────────────────────────────
  {
    slug: 'community/nano-pdf',
    name: 'Nano PDF',
    description: 'Lightweight PDF processing — extract, merge, split, and convert PDF documents.',
    icon: 'doc.fill',
    author: 'Community',
    category: 'Data',
    downloads: 2600,
    stars: 7,
    version: '1.0.0',
  },

  // ── Utility & System ─────────────────────────────────
  {
    slug: 'community/1password',
    name: '1Password',
    description: 'Securely access 1Password vaults — read secrets, passwords, and secure notes.',
    icon: 'lock.shield.fill',
    author: 'Community',
    category: 'Utility',
    downloads: 2400,
    stars: 12,
    version: '1.0.0',
  },
  {
    slug: 'community/openhue',
    name: 'OpenHue',
    description: 'Philips Hue smart lighting control — scenes, colors, and room automation.',
    icon: 'lightbulb.fill',
    author: 'Community',
    category: 'Utility',
    downloads: 1800,
    stars: 6,
    version: '1.0.0',
  },
  {
    slug: 'community/camsnap',
    name: 'CamSnap',
    description: 'Capture photos and screenshots from connected cameras and displays.',
    icon: 'camera.fill',
    author: 'Community',
    category: 'Utility',
    downloads: 1500,
    stars: 5,
    version: '1.0.0',
  },

  // ── Business ─────────────────────────────────────────
  {
    slug: 'community/blogwatcher',
    name: 'Blog Watcher',
    description: 'Monitor blogs and RSS feeds for new content. Track competitors and industry news.',
    icon: 'newspaper.fill',
    author: 'Community',
    category: 'Business',
    downloads: 1900,
    stars: 6,
    version: '1.0.0',
  },
];

app.get('/skills/clawhub/browse', authenticate, async (req, res) => {
  try {
    const { category, q, agent_id } = req.query;
    let filtered = CLAWHUB_SKILLS;

    if (category) filtered = filtered.filter(s => s.category === category);
    if (q) {
      const lower = q.toLowerCase();
      filtered = filtered.filter(
        s => s.name.toLowerCase().includes(lower)
          || s.description.toLowerCase().includes(lower)
          || s.slug.toLowerCase().includes(lower)
          || s.aliases?.some(a => a.toLowerCase().includes(lower)),
      );
    }

    let installedSlugs = new Set();
    if (agent_id) {
      const { rows } = await pool.query(
        "SELECT skill_id FROM agent_skills WHERE agent_id = $1 AND source = 'clawhub'",
        [agent_id],
      );
      installedSlugs = new Set(rows.map(r => r.skill_id));
    }

    const skills = filtered.map(s => ({
      id: s.slug,
      slug: s.slug,
      ...s,
      is_curated: false,
      requires_pro: false,
      permissions: [],
      source: 'clawhub',
      is_installed: agent_id
        ? (installedSlugs.has(s.slug.split('/').pop())
           || installedSlugs.has(`clawhub-${s.slug.replace(/\//g, '-')}`))
        : undefined,
    }));

    res.json({ skills, total_count: skills.length });
  } catch (err) {
    console.error('clawhub browse:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Catalog with optional installed-status per agent
app.get('/skills/catalog', authenticate, async (req, res) => {
  try {
    let filtered = CURATED_SKILLS;
    const { category, q, agent_id } = req.query;

    if (category) filtered = filtered.filter((s) => s.category === category);
    if (q) {
      const lower = q.toLowerCase();
      filtered = filtered.filter(
        (s) => s.name.toLowerCase().includes(lower) || s.description.toLowerCase().includes(lower),
      );
    }

    // If an agent_id is provided, annotate each skill with installed status
    let installedIds = new Set();
    if (agent_id) {
      const { rows } = await pool.query(
        'SELECT skill_id FROM agent_skills WHERE agent_id = $1',
        [agent_id],
      );
      installedIds = new Set(rows.map(r => r.skill_id));
    }

    const skills = filtered.map(s => ({
      ...s,
      is_installed: agent_id ? installedIds.has(s.id) : undefined,
    }));

    res.json({ skills, categories: SKILL_CATEGORIES, total_count: skills.length });
  } catch (err) {
    console.error('skills catalog:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Recommended skills based on agent persona (must be before :id route)
app.get('/skills/recommended', authenticate, async (req, res) => {
  try {
    const { agent_id } = req.query;
    let persona = 'Professional';

    if (agent_id) {
      const { rows: [agent] } = await pool.query(
        'SELECT persona FROM agents WHERE id = $1 AND user_id = $2',
        [agent_id, req.userId],
      );
      if (agent) persona = agent.persona;
    }

    const recommendedIds = PERSONA_RECOMMENDATIONS[persona] || PERSONA_RECOMMENDATIONS.Professional;

    let installedIds = new Set();
    if (agent_id) {
      const { rows } = await pool.query(
        'SELECT skill_id FROM agent_skills WHERE agent_id = $1',
        [agent_id],
      );
      installedIds = new Set(rows.map(r => r.skill_id));
    }

    const recommended = recommendedIds
      .filter(id => !installedIds.has(id))
      .map(id => CURATED_SKILLS.find(s => s.id === id))
      .filter(Boolean);

    res.json({ skills: recommended, persona });
  } catch (err) {
    console.error('recommended skills:', err);
    res.status(500).json({ error: 'Internal error' });
  }
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
// Files
// ──────────────────────────────────────────────

app.post('/files/upload', authenticate, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file provided' });

    const fileId = crypto.randomUUID();
    const userDir = path.join(UPLOADS_ROOT, req.userId, fileId);
    fs.mkdirSync(userDir, { recursive: true });

    const safeName = req.file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    const filePath = path.join(userDir, safeName);
    fs.writeFileSync(filePath, req.file.buffer);

    await pool.query(
      `INSERT INTO files (id, user_id, filename, mime_type, size_bytes, storage_path, source)
       VALUES ($1, $2, $3, $4, $5, $6, 'upload')`,
      [fileId, req.userId, req.file.originalname, req.file.mimetype, req.file.size, filePath],
    );

    res.status(201).json({
      file_id: fileId,
      filename: req.file.originalname,
      mime_type: req.file.mimetype,
      size_bytes: req.file.size,
    });
  } catch (err) {
    if (err instanceof multer.MulterError) {
      return res.status(400).json({ error: err.message });
    }
    console.error('file upload:', err);
    res.status(500).json({ error: 'Upload failed' });
  }
});

app.get('/files/:fileId', authenticate, async (req, res) => {
  try {
    const { rows: [file] } = await pool.query(
      'SELECT id, filename, mime_type, size_bytes, source, created_at FROM files WHERE id = $1 AND user_id = $2',
      [req.params.fileId, req.userId],
    );
    if (!file) return res.status(404).json({ error: 'File not found' });
    res.json(file);
  } catch (err) {
    console.error('get file:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/files/:fileId/download', authenticate, async (req, res) => {
  try {
    const { rows: [file] } = await pool.query(
      'SELECT filename, mime_type, storage_path FROM files WHERE id = $1 AND user_id = $2',
      [req.params.fileId, req.userId],
    );
    if (!file) return res.status(404).json({ error: 'File not found' });

    if (!fs.existsSync(file.storage_path)) {
      return res.status(404).json({ error: 'File data missing' });
    }

    res.setHeader('Content-Type', file.mime_type);
    res.setHeader('Content-Disposition', `attachment; filename="${encodeURIComponent(file.filename)}"`);
    fs.createReadStream(file.storage_path).pipe(res);
  } catch (err) {
    console.error('download file:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.delete('/files/:fileId', authenticate, async (req, res) => {
  try {
    const { rows: [file] } = await pool.query(
      'SELECT storage_path FROM files WHERE id = $1 AND user_id = $2',
      [req.params.fileId, req.userId],
    );
    if (!file) return res.status(404).json({ error: 'File not found' });

    const dir = path.dirname(file.storage_path);
    fs.rmSync(dir, { recursive: true, force: true });

    await pool.query('DELETE FROM files WHERE id = $1', [req.params.fileId]);
    res.json({ deleted: true });
  } catch (err) {
    console.error('delete file:', err);
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
