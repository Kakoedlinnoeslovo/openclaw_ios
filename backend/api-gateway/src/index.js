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

const { healthCheck: ocHealthCheck, chatCompletionSync } = require('./openclaw-client');
const {
  ensureBaseConfig, provisionAgent, deprovisionAgent, updateAgentConfig,
  installSkill, uninstallSkill, installStarterSkills,
  setSkillEnabled, getSkillConfig, setSkillConfig,
  installClawHubSkill, setSkillCredentials, extractInstallCommands,
  detectSetupRequirements, parseSkillMd,
  openclawAgentId, ensureAgentsMdPatched, ensureWorkspaceReady,
  getInstalledSkillIds,
  PERSONA_RECOMMENDATIONS, VALID_MODELS,
} = require('./provisioner');
const { createWSRelay } = require('./ws-relay');
const { refreshOAuthTokensForAgent, loadConversationHistory } = require('./task-helpers');

// Swift's .iso8601 decoder rejects fractional seconds — strip them.
pg.types.setTypeParser(1184, (val) =>
  new Date(val).toISOString().replace(/\.\d{3}Z$/, 'Z'),
);

// ──────────────────────────────────────────────
// OAuth provider configuration
// ──────────────────────────────────────────────

const OAUTH_REDIRECT_BASE = process.env.OAUTH_REDIRECT_BASE || 'http://localhost:3000';

const OAUTH_PROVIDER_DEFAULTS = {
  slack: {
    authorize_url: 'https://slack.com/oauth/v2/authorize',
    token_url: 'https://slack.com/api/oauth.v2.access',
    scopes: 'channels:read,channels:history,chat:write,users:read,groups:read,im:read',
    skill_ids: ['slack-assistant', 'slack-integration',
                'clawhub-community-slack-assistant', 'clawhub-community-slack-integration'],
    token_field: 'SLACK_BOT_TOKEN',
    env_client_id: 'SLACK_CLIENT_ID',
    env_client_secret: 'SLACK_CLIENT_SECRET',
    extract_token: (body) => ({
      access_token: body.access_token || body.authed_user?.access_token,
      refresh_token: body.refresh_token || null,
      scope: body.scope,
      extra: { team: body.team, bot_user_id: body.bot_user_id },
    }),
  },
  google: {
    authorize_url: 'https://accounts.google.com/o/oauth2/v2/auth',
    token_url: 'https://oauth2.googleapis.com/token',
    scopes: 'https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/drive.readonly',
    extra_params: { access_type: 'offline', prompt: 'consent' },
    skill_ids: ['gog', 'clawhub-community-gog', 'calendar-planner'],
    token_field: 'GOOGLE_ACCESS_TOKEN',
    env_client_id: 'GOOGLE_CLIENT_ID',
    env_client_secret: 'GOOGLE_CLIENT_SECRET',
    extract_token: (body) => ({
      access_token: body.access_token,
      refresh_token: body.refresh_token || null,
      expires_in: body.expires_in,
      scope: body.scope,
    }),
  },
  notion: {
    authorize_url: 'https://api.notion.com/v1/oauth/authorize',
    token_url: 'https://api.notion.com/v1/oauth/token',
    scopes: '',
    auth_method: 'basic',
    owner_type: 'user',
    skill_ids: ['notion-sync', 'clawhub-community-notion-sync'],
    token_field: 'NOTION_API_KEY',
    env_client_id: 'NOTION_CLIENT_ID',
    env_client_secret: 'NOTION_CLIENT_SECRET',
    extract_token: (body) => ({
      access_token: body.access_token,
      refresh_token: null,
      extra: { workspace_id: body.workspace_id, workspace_name: body.workspace_name },
    }),
  },
};

// In-memory cache of DB-stored OAuth credentials; refreshed on save.
let _dbOAuthConfig = {};

async function loadOAuthConfigFromDB() {
  try {
    const { rows } = await pool.query(
      `SELECT key, value FROM app_config WHERE key LIKE 'oauth_creds_%'`,
    );
    const cfg = {};
    for (const row of rows) {
      const provider = row.key.replace('oauth_creds_', '');
      cfg[provider] = row.value;
    }
    _dbOAuthConfig = cfg;
  } catch {
    // table might not exist yet during first startup
  }
}

function getOAuthProvider(name) {
  const defaults = OAUTH_PROVIDER_DEFAULTS[name];
  if (!defaults) return null;
  const dbCreds = _dbOAuthConfig[name] || {};
  return {
    ...defaults,
    client_id: dbCreds.client_id || process.env[defaults.env_client_id],
    client_secret: dbCreds.client_secret || process.env[defaults.env_client_secret],
  };
}

// Backwards-compatible object for oauthProviderForSkill lookups
const OAUTH_PROVIDERS = new Proxy(OAUTH_PROVIDER_DEFAULTS, {
  get(target, prop) {
    if (typeof prop === 'string' && prop in target) return getOAuthProvider(prop);
    return Reflect.get(target, prop);
  },
});

function oauthProviderForSkill(skillId) {
  for (const [name, cfg] of Object.entries(OAUTH_PROVIDERS)) {
    if (cfg.skill_ids.some(id => skillId.includes(id))) return name;
  }
  return null;
}

const app = express();
app.disable('etag');
app.use(express.json({ limit: '30mb' }));

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET) {
  console.error('FATAL: JWT_SECRET environment variable is required');
  process.exit(1);
}
const TASK_QUEUE = 'tasks';

const taskQueue = new Queue(TASK_QUEUE, {
  connection: new Redis(process.env.REDIS_URL, { maxRetriesPerRequest: null }),
});

const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');

ensureBaseConfig();

async function ensureSchema() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`
      CREATE TABLE IF NOT EXISTS files (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        task_id UUID REFERENCES tasks(id) ON DELETE SET NULL,
        filename VARCHAR(255) NOT NULL,
        mime_type VARCHAR(100) NOT NULL,
        size_bytes BIGINT NOT NULL,
        storage_path TEXT NOT NULL,
        source VARCHAR(20) NOT NULL DEFAULT 'upload',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_files_user ON files(user_id);
      CREATE INDEX IF NOT EXISTS idx_files_task ON files(task_id);

      CREATE TABLE IF NOT EXISTS oauth_states (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
        skill_id VARCHAR(255) NOT NULL,
        provider VARCHAR(50) NOT NULL,
        state VARCHAR(255) UNIQUE NOT NULL,
        code_verifier VARCHAR(255),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '10 minutes'
      );
      CREATE INDEX IF NOT EXISTS idx_oauth_states_state ON oauth_states(state);

      CREATE TABLE IF NOT EXISTS oauth_tokens (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        agent_id UUID NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
        skill_id VARCHAR(255) NOT NULL,
        provider VARCHAR(50) NOT NULL,
        access_token TEXT NOT NULL,
        refresh_token TEXT,
        token_type VARCHAR(50) DEFAULT 'Bearer',
        scope TEXT,
        expires_at TIMESTAMPTZ,
        extra JSONB DEFAULT '{}',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE(agent_id, skill_id, provider)
      );
      CREATE INDEX IF NOT EXISTS idx_oauth_tokens_agent_skill ON oauth_tokens(agent_id, skill_id);

      CREATE TABLE IF NOT EXISTS app_config (
        key VARCHAR(255) PRIMARY KEY,
        value JSONB NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);

    const migrations = [
      { table: 'tasks',        column: 'file_ids',    sql: "ALTER TABLE tasks ADD COLUMN file_ids UUID[] DEFAULT '{}'" },
      { table: 'agent_skills', column: 'enabled',     sql: 'ALTER TABLE agent_skills ADD COLUMN enabled BOOLEAN NOT NULL DEFAULT true' },
      { table: 'agent_skills', column: 'source',      sql: "ALTER TABLE agent_skills ADD COLUMN source VARCHAR(20) NOT NULL DEFAULT 'curated'" },
      { table: 'agent_skills', column: 'config',      sql: "ALTER TABLE agent_skills ADD COLUMN config JSONB DEFAULT '{}'" },
      { table: 'oauth_states', column: 'connect_all', sql: 'ALTER TABLE oauth_states ADD COLUMN connect_all BOOLEAN NOT NULL DEFAULT FALSE' },
    ];
    for (const m of migrations) {
      const { rows } = await client.query(
        `SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2`,
        [m.table, m.column],
      );
      if (rows.length === 0) await client.query(m.sql);
    }

    await client.query('COMMIT');
    console.log('Schema migrations applied successfully');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Schema migration failed:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

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
  // Keep at most 10 active refresh tokens per user (remove oldest beyond that)
  await pool.query(
    `DELETE FROM refresh_tokens WHERE id IN (
       SELECT id FROM refresh_tokens WHERE user_id = $1
       ORDER BY created_at DESC OFFSET 10
     )`,
    [userId],
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

// Clear ALL OpenClaw session state so the gateway re-discovers skills and
// reloads env vars on the next chat completion request.  Previous version
// only removed .jsonl files; the gateway can cache session state in other
// formats, so we nuke the entire sessions directory.
function clearAgentSessions(userId, agentId) {
  const ocId = openclawAgentId(userId, agentId);
  const OC_HOME = process.env.OPENCLAW_HOME || '/openclaw-home';
  const sessionsDir = path.join(OC_HOME, 'agents', ocId, 'sessions');
  try {
    if (fs.existsSync(sessionsDir)) {
      const before = fs.readdirSync(sessionsDir).length;
      fs.rmSync(sessionsDir, { recursive: true, force: true });
      fs.mkdirSync(sessionsDir, { recursive: true });
      console.log(`[sessions] cleared ${before} file(s) for ${ocId}`);
    } else {
      console.log(`[sessions] no sessions dir for ${ocId} — nothing to clear`);
    }
  } catch (err) {
    console.warn('[sessions] clear failed for', ocId, err.message);
  }
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

// Simple in-memory rate limiter (per-IP sliding window)
function rateLimit({ windowMs = 60_000, max = 30, message = 'Too many requests, try again later' } = {}) {
  const hits = new Map();
  const sweep = setInterval(() => hits.clear(), windowMs);
  if (sweep.unref) sweep.unref();
  return (req, res, next) => {
    const key = req.ip || req.socket.remoteAddress;
    const count = (hits.get(key) || 0) + 1;
    hits.set(key, count);
    if (count > max) return res.status(429).json({ error: message });
    next();
  };
}

const authLimiter = rateLimit({ windowMs: 60_000, max: 20, message: 'Too many auth attempts, try again later' });

// Admin authorization — only allow configured admin users or the first registered user
const ADMIN_USER_IDS = process.env.ADMIN_USER_IDS
  ? process.env.ADMIN_USER_IDS.split(',').map(s => s.trim()).filter(Boolean)
  : [];

async function authenticateAdmin(req, res, next) {
  if (ADMIN_USER_IDS.length > 0) {
    if (!ADMIN_USER_IDS.includes(req.userId)) {
      return res.status(403).json({ error: 'Admin access required' });
    }
    return next();
  }
  const { rows: [first] } = await pool.query(
    'SELECT id FROM users ORDER BY created_at ASC LIMIT 1',
  );
  if (!first || first.id !== req.userId) {
    return res.status(403).json({ error: 'Admin access required' });
  }
  next();
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

app.post('/auth/register', authLimiter, async (req, res) => {
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

app.post('/auth/login', authLimiter, async (req, res) => {
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

// Apple JWKS cache for identity token verification
let _appleJWKS = null;
let _appleJWKSFetchedAt = 0;
const APPLE_JWKS_TTL = 60 * 60 * 1000; // 1 hour

async function getApplePublicKey(kid) {
  if (!_appleJWKS || Date.now() - _appleJWKSFetchedAt > APPLE_JWKS_TTL) {
    const resp = await fetch('https://appleid.apple.com/auth/keys', {
      signal: AbortSignal.timeout(10_000),
    });
    if (!resp.ok) throw new Error(`Failed to fetch Apple JWKS: ${resp.status}`);
    _appleJWKS = await resp.json();
    _appleJWKSFetchedAt = Date.now();
  }
  const key = _appleJWKS.keys.find(k => k.kid === kid);
  if (!key) throw new Error(`Apple public key not found for kid: ${kid}`);
  return crypto.createPublicKey({ key, format: 'jwk' });
}

app.post('/auth/apple', authLimiter, async (req, res) => {
  try {
    const { identity_token, full_name } = req.body;
    if (!identity_token) return res.status(400).json({ error: 'Missing identity token' });

    // Decode header to get the key ID
    const headerB64 = identity_token.split('.')[0];
    if (!headerB64) return res.status(400).json({ error: 'Malformed identity token' });

    let header;
    try {
      header = JSON.parse(Buffer.from(headerB64, 'base64url').toString());
    } catch {
      return res.status(400).json({ error: 'Malformed identity token header' });
    }

    // Fetch Apple's public key and verify the JWT
    const publicKey = await getApplePublicKey(header.kid);
    let payload;
    try {
      payload = jwt.verify(identity_token, publicKey, {
        algorithms: ['RS256'],
        issuer: 'https://appleid.apple.com',
      });
    } catch (verifyErr) {
      console.warn('apple token verification failed:', verifyErr.message);
      return res.status(401).json({ error: 'Invalid identity token' });
    }

    const appleUserId = payload.sub;
    if (!appleUserId) return res.status(401).json({ error: 'Token missing subject' });

    let { rows } = await pool.query('SELECT * FROM users WHERE apple_user_id = $1', [appleUserId]);

    if (!rows.length) {
      const name = full_name || 'Apple User';
      const email = payload.email || `${appleUserId.slice(0, 8)}@privaterelay.appleid.com`;
      try {
        ({ rows } = await pool.query(
          `INSERT INTO users (email, display_name, apple_user_id)
           VALUES ($1, $2, $3) RETURNING *`,
          [email, name, appleUserId],
        ));
      } catch (insertErr) {
        if (insertErr.code === '23505' && insertErr.constraint?.includes('email')) {
          ({ rows } = await pool.query(
            `UPDATE users SET apple_user_id = $1, display_name = COALESCE(NULLIF($2, 'Apple User'), display_name)
             WHERE email = $3 AND apple_user_id IS NULL RETURNING *`,
            [appleUserId, name, email],
          ));
          if (!rows.length) {
            return res.status(409).json({ error: 'Email already linked to a different Apple account' });
          }
        } else {
          throw insertErr;
        }
      }
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

app.post('/auth/refresh', authLimiter, async (req, res) => {
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
    if (model !== undefined) {
      if (!VALID_MODELS.includes(model)) {
        return res.status(400).json({
          error: `Unknown model "${model}". Valid models: ${VALID_MODELS.join(', ')}`,
        });
      }
      sets.push(`model = $${i++}`);
      vals.push(model);
    }
    if (!sets.length) return res.status(400).json({ error: 'Nothing to update' });

    sets.push('updated_at = NOW()');
    vals.push(req.params.id, req.userId);

    await pool.query(
      `UPDATE agents SET ${sets.join(', ')} WHERE id = $${i++} AND user_id = $${i}`,
      vals,
    );

    const agent = await agentWithSkills(req.params.id);
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    // Propagate changes to OpenClaw gateway config and workspace files
    if (name !== undefined || persona !== undefined || model !== undefined) {
      try {
        updateAgentConfig(req.userId, req.params.id, {
          name: agent.name,
          persona: agent.persona,
          model: agent.model,
        });
        if (persona !== undefined || model !== undefined) {
          clearAgentSessions(req.userId, req.params.id);
        }
      } catch (configErr) {
        console.warn('failed to propagate agent config update:', configErr.message);
      }
    }

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
    clearAgentSessions(req.userId, req.params.agentId);

    // Detect setup requirements for the curated skill (env vars, bin tools)
    const OC_HOME = process.env.OPENCLAW_HOME || '/openclaw-home';
    const ocId = openclawAgentId(req.userId, req.params.agentId);
    const skillDir = path.join(OC_HOME, 'workspaces', ocId, 'skills', skill_id);
    const meta = parseSkillMd(path.join(skillDir, 'SKILL.md'));
    const setupReqs = detectSetupRequirements(skillDir, meta);
    const envKeys = setupReqs.filter(r => r.type === 'env').map(r => r.key).join(',');
    const initialConfig = envKeys ? { _env_keys: envKeys } : {};

    await pool.query(
      `INSERT INTO agent_skills (agent_id, skill_id, name, icon, version, enabled, source, config)
       VALUES ($1, $2, $3, $4, $5, true, 'curated', $6) ON CONFLICT DO NOTHING`,
      [req.params.agentId, skill_id, skill.name, skill.icon, skill.version, JSON.stringify(initialConfig)],
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
    clearAgentSessions(req.userId, req.params.agentId);

    const OC_HOME_CHECK = process.env.OPENCLAW_HOME || '/openclaw-home';
    const ocIdCheck = openclawAgentId(req.userId, req.params.agentId);
    const skillMdPath = path.join(OC_HOME_CHECK, 'workspaces', ocIdCheck, 'skills', result.skillId, 'SKILL.md');
    console.log(`[install] slug=${slug} skillId=${result.skillId} skillMdExists=${fs.existsSync(skillMdPath)} fallback=${result.fallback_used || 'none'}`);

    // Persist env-key names alongside the skill row so the iOS "Configure"
    // sheet can offer the correct input fields after installation.
    const envKeys = (result.setup_requirements || [])
      .filter(r => r.type === 'env')
      .map(r => r.key)
      .join(',');
    const initialConfig = envKeys ? { _env_keys: envKeys } : {};

    await pool.query(
      `INSERT INTO agent_skills (agent_id, skill_id, name, icon, version, enabled, source, config)
       VALUES ($1, $2, $3, $4, $5, true, $6, $7)
       ON CONFLICT (agent_id, skill_id) DO UPDATE SET
         name = EXCLUDED.name, icon = EXCLUDED.icon, version = EXCLUDED.version,
         source = EXCLUDED.source, config = agent_skills.config || EXCLUDED.config,
         enabled = true`,
      [req.params.agentId, result.skillId, result.name, result.icon, result.version, result.source, JSON.stringify(initialConfig)],
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

    let skillsChanged = false;

    if (enabled !== undefined) {
      await pool.query(
        'UPDATE agent_skills SET enabled = $1 WHERE agent_id = $2 AND skill_id = $3',
        [enabled, req.params.agentId, req.params.skillId],
      );
      setSkillEnabled(req.userId, req.params.agentId, req.params.skillId, enabled);
      skillsChanged = true;
    }

    if (config !== undefined) {
      await pool.query(
        'UPDATE agent_skills SET config = $1 WHERE agent_id = $2 AND skill_id = $3',
        [JSON.stringify(config), req.params.agentId, req.params.skillId],
      );
      setSkillConfig(req.userId, req.params.agentId, req.params.skillId, config);
    }

    if (skillsChanged) clearAgentSessions(req.userId, req.params.agentId);

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

    // Trim whitespace/newlines from credential values (iOS paste often includes trailing whitespace)
    const trimmed = Object.fromEntries(
      Object.entries(credentials).map(([k, v]) => [k, typeof v === 'string' ? v.trim() : v]),
    );

    const credKeys = Object.keys(trimmed);
    const hadWhitespace = credKeys.some(k => credentials[k] !== trimmed[k]);
    console.log(`[creds] agent=${req.params.agentId} skill=${req.params.skillId} keys=[${credKeys}] trimmedWhitespace=${hadWhitespace}`);

    // Inject credentials into the agent's OpenClaw environment
    setSkillCredentials(req.userId, req.params.agentId, req.params.skillId, trimmed);

    // Patch AGENTS.md for pre-fix agents so the agent knows to `source .env`
    const ocId = openclawAgentId(req.userId, req.params.agentId);
    ensureAgentsMdPatched(ocId);

    clearAgentSessions(req.userId, req.params.agentId);

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

// Get setup requirements for an installed skill (works for any source)
app.get('/agents/:agentId/skills/:skillId/requirements', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    const { rows: [existing] } = await pool.query(
      'SELECT id, skill_id, source, config FROM agent_skills WHERE agent_id = $1 AND skill_id = $2',
      [req.params.agentId, req.params.skillId],
    );
    if (!existing) return res.status(404).json({ error: 'Skill not installed on this agent' });

    const OC_HOME = process.env.OPENCLAW_HOME || '/openclaw-home';
    const ocId = openclawAgentId(req.userId, req.params.agentId);
    const skillDir = path.join(OC_HOME, 'workspaces', ocId, 'skills', req.params.skillId);

    let requirements = [];
    let installCommands = [];
    if (fs.existsSync(skillDir)) {
      const meta = parseSkillMd(path.join(skillDir, 'SKILL.md'));
      requirements = detectSetupRequirements(skillDir, meta);
      installCommands = extractInstallCommands(skillDir);
    }

    const isConfigured = existing.config?._configured === true;

    res.json({
      skill_id: existing.skill_id,
      source: existing.source,
      requirements,
      install_commands: installCommands,
      is_configured: isConfigured,
    });
  } catch (err) {
    console.error('skill requirements:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Uninstall a skill
app.delete('/agents/:agentId/skills/:skillId', authenticate, verifyAgentOwnership, async (req, res) => {
  try {
    uninstallSkill(req.userId, req.params.agentId, req.params.skillId);
    clearAgentSessions(req.userId, req.params.agentId);

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

app.get('/agents/:agentId/tasks', authenticate, verifyAgentOwnership, async (req, res) => {
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
      'SELECT id, openclaw_agent_id FROM agents WHERE id = $1 AND user_id = $2',
      [req.params.agentId, req.userId],
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    const { rowCount } = await pool.query(
      "DELETE FROM tasks WHERE agent_id = $1 AND user_id = $2 AND status NOT IN ('queued', 'running')",
      [req.params.agentId, req.userId],
    );

    clearAgentSessions(req.userId, req.params.agentId);

    res.json({ deleted: rowCount });
  } catch (err) {
    console.error('clear tasks:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.get('/agents/:agentId/tasks/:taskId', authenticate, verifyAgentOwnership, async (req, res) => {
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

// ── Live ClawHub proxy helpers ────────────────────────
const CLAWHUB_API = 'https://topclawhubskills.com/api';
const CLAWHUB_CACHE_TTL = 5 * 60 * 1000; // 5 min
const _clawhubCache = new Map();

const CLAWHUB_SLUG_META = Object.fromEntries(
  CLAWHUB_SKILLS.map(s => [s.slug.split('/').pop(), s]),
);

const CATEGORY_ICONS = {
  Productivity: 'checkmark.circle.fill', Research: 'magnifyingglass.circle.fill',
  Writing: 'pencil.circle.fill', Data: 'chart.bar.fill',
  Communication: 'message.circle.fill', Automation: 'gearshape.2.fill',
  Development: 'chevron.left.forwardslash.chevron.right', 'AI/ML': 'brain',
  Utility: 'wrench.fill', Web: 'globe', Science: 'flask.fill',
  Media: 'play.rectangle.fill', Social: 'person.2.fill',
  Finance: 'chart.line.uptrend.xyaxis', Location: 'location.fill',
  Business: 'briefcase.fill',
};

const CATEGORY_KEYWORDS = [
  [/\b(github|git\b|code|debug|refactor|compiler|IDE|linter|docker|deploy|CI\/CD|CLI|terminal|sdk|api)\b/i, 'Development'],
  [/\b(slack|discord|telegram|twitter|social|post(?:ing|er)|mastodon)\b/i, 'Social'],
  [/\b(video|audio|music|photo|camera|youtube|spotify|media|transcri|podcast|stream)\b/i, 'Media'],
  [/\b(search|scrape|browse|web|http|html|url|crawl)\b/i, 'Web'],
  [/\b(stock|crypto|financ|trading|invest|portfolio|bitcoin)\b/i, 'Finance'],
  [/\b(note|todo|task|calendar|remind|productiv|obsidian|notion|trello)\b/i, 'Productivity'],
  [/\b(pdf|csv|data|sql|database|analytics)\b/i, 'Data'],
  [/\b(write|blog|markdown|document|essay)\b/i, 'Writing'],
  [/\b(automat|workflow|schedule|cron|pipeline)\b/i, 'Automation'],
  [/\b(weather|location|map|gps|place|geograph)\b/i, 'Location'],
  [/\b(research|paper|arxiv|academic|scholar)\b/i, 'Research'],
  [/\b(business|crm|lead|sales)\b/i, 'Business'],
  [/\b(ai\b|llm|prompt|neural|machine.learn|model.select|model.rout)\b/i, 'AI/ML'],
];

function inferCategory(text) {
  for (const [re, cat] of CATEGORY_KEYWORDS) {
    if (re.test(text)) return cat;
  }
  return 'Utility';
}

async function fetchClawHub(endpoint) {
  const cached = _clawhubCache.get(endpoint);
  if (cached && Date.now() - cached.ts < CLAWHUB_CACHE_TTL) return cached.data;

  const resp = await fetch(`${CLAWHUB_API}${endpoint}`, {
    headers: { 'User-Agent': 'OpenClaw-Backend/1.0', Accept: 'application/json' },
    signal: AbortSignal.timeout(10_000),
  });
  if (!resp.ok) throw new Error(`ClawHub API ${resp.status}`);
  const json = await resp.json();
  const data = json.data || [];
  _clawhubCache.set(endpoint, { data, ts: Date.now() });
  return data;
}

function mapLiveSkill(s) {
  const shortSlug = s.slug;
  const known = CLAWHUB_SLUG_META[shortSlug];
  const text = `${s.display_name} ${s.summary || ''}`;
  const category = known?.category || inferCategory(text);
  return {
    slug: known?.slug || `${s.owner_handle}/${s.slug}`,
    name: known?.name || s.display_name || s.slug,
    description: known?.description || s.summary || '',
    icon: known?.icon || CATEGORY_ICONS[category] || 'puzzlepiece.fill',
    author: known?.author || s.owner_handle || 'Community',
    category,
    downloads: s.downloads ?? 0,
    stars: s.stars ?? 0,
    version: known?.version || '1.0.0',
    clawhub_url: s.clawhub_url || null,
    is_certified: s.is_certified || false,
  };
}

app.get('/skills/clawhub/browse', authenticate, async (req, res) => {
  try {
    const { category, q, agent_id } = req.query;

    if (agent_id) {
      const { rows: ownerCheck } = await pool.query(
        'SELECT id FROM agents WHERE id = $1 AND user_id = $2', [agent_id, req.userId],
      );
      if (!ownerCheck.length) return res.status(404).json({ error: 'Agent not found' });
    }

    let skills;
    let source = 'live';

    try {
      const endpoint = q
        ? `/search?q=${encodeURIComponent(q)}&limit=100`
        : '/top-downloads?limit=100';
      const raw = await fetchClawHub(endpoint);
      skills = raw.filter(s => !s.is_deleted).map(mapLiveSkill);
    } catch (err) {
      console.warn('ClawHub live fetch failed, using fallback:', err.message);
      skills = CLAWHUB_SKILLS.map(s => ({ ...s }));
      source = 'fallback';
    }

    if (category) skills = skills.filter(s => s.category === category);
    if (q && source === 'fallback') {
      const lower = q.toLowerCase();
      skills = skills.filter(
        s => s.name.toLowerCase().includes(lower)
          || s.description.toLowerCase().includes(lower)
          || s.slug.toLowerCase().includes(lower),
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

    const result = skills.map(s => ({
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

    res.json({ skills: result, total_count: result.length, source });
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

    if (agent_id) {
      const { rows: ownerCheck } = await pool.query(
        'SELECT id FROM agents WHERE id = $1 AND user_id = $2', [agent_id, req.userId],
      );
      if (!ownerCheck.length) return res.status(404).json({ error: 'Agent not found' });
    }

    if (category) filtered = filtered.filter((s) => s.category === category);
    if (q) {
      const lower = q.toLowerCase();
      filtered = filtered.filter(
        (s) => s.name.toLowerCase().includes(lower) || s.description.toLowerCase().includes(lower),
      );
    }

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
    if (!receipt_data || !product_id) {
      return res.status(400).json({ error: 'Missing receipt_data or product_id' });
    }

    // Validate receipt with Apple's App Store Server API (v2)
    // https://developer.apple.com/documentation/appstoreserverapi
    const APPLE_SHARED_SECRET = process.env.APPLE_SHARED_SECRET;
    if (!APPLE_SHARED_SECRET) {
      console.error('APPLE_SHARED_SECRET not configured — cannot verify receipts');
      return res.status(503).json({ error: 'Receipt verification not configured' });
    }

    const verifyUrl = process.env.NODE_ENV === 'production'
      ? 'https://buy.itunes.apple.com/verifyReceipt'
      : 'https://sandbox.itunes.apple.com/verifyReceipt';

    const appleRes = await fetch(verifyUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        'receipt-data': receipt_data,
        password: APPLE_SHARED_SECRET,
        'exclude-old-transactions': true,
      }),
      signal: AbortSignal.timeout(15_000),
    });

    const appleBody = await appleRes.json();

    if (appleBody.status !== 0) {
      console.warn('apple receipt verification failed, status:', appleBody.status);
      if (appleBody.status === 21007) {
        return res.status(400).json({ error: 'Sandbox receipt sent to production — retry in sandbox mode' });
      }
      return res.status(400).json({ error: 'Invalid receipt' });
    }

    const latestInfo = appleBody.latest_receipt_info?.[0];
    if (!latestInfo) {
      return res.status(400).json({ error: 'No subscription found in receipt' });
    }

    const expiresMs = parseInt(latestInfo.expires_date_ms, 10);
    const expiresAt = new Date(expiresMs);
    const isActive = expiresAt > new Date();

    await pool.query(
      `INSERT INTO subscriptions (user_id, product_id, tier, is_active, expires_at)
       VALUES ($1, $2, 'pro', $3, $4)
       ON CONFLICT (user_id)
       DO UPDATE SET product_id = $2, tier = 'pro', is_active = $3,
                     expires_at = $4, updated_at = NOW()`,
      [req.userId, product_id, isActive, expiresAt],
    );
    if (isActive) {
      await pool.query("UPDATE users SET tier = 'pro' WHERE id = $1", [req.userId]);
    }
    res.json({ status: 'verified', tier: isActive ? 'pro' : 'free', expires_at: expiresAt });
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
// OAuth config (set credentials from app)
// ──────────────────────────────────────────────

app.get('/admin/oauth-config', authenticate, authenticateAdmin, async (req, res) => {
  try {
    const providers = {};
    for (const name of Object.keys(OAUTH_PROVIDER_DEFAULTS)) {
      const p = getOAuthProvider(name);
      providers[name] = {
        configured: !!(p.client_id && p.client_secret),
        has_client_id: !!p.client_id,
        has_client_secret: !!p.client_secret,
      };
    }
    res.json({ providers, redirect_base: OAUTH_REDIRECT_BASE });
  } catch (err) {
    console.error('get oauth config:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/admin/oauth-config', authenticate, authenticateAdmin, async (req, res) => {
  try {
    const { provider, client_id, client_secret } = req.body;
    if (!provider || !OAUTH_PROVIDER_DEFAULTS[provider]) {
      return res.status(400).json({ error: 'Invalid provider' });
    }
    if (!client_id || !client_secret) {
      return res.status(400).json({ error: 'Both client_id and client_secret are required' });
    }

    await pool.query(
      `INSERT INTO app_config (key, value, updated_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (key)
       DO UPDATE SET value = $2, updated_at = NOW()`,
      [`oauth_creds_${provider}`, JSON.stringify({ client_id, client_secret })],
    );

    await loadOAuthConfigFromDB();

    const p = getOAuthProvider(provider);
    res.json({
      ok: true,
      provider,
      configured: !!(p.client_id && p.client_secret),
    });
  } catch (err) {
    console.error('set oauth config:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ──────────────────────────────────────────────
// OAuth flows (Slack, Google, Notion)
// ──────────────────────────────────────────────

// Step 1: iOS app opens this URL in ASWebAuthenticationSession.
// Generates a state param, stores it, and redirects to the provider's auth page.
app.get('/oauth/:provider/authorize', authenticate, async (req, res) => {
  try {
    const { provider } = req.params;
    const { agent_id, skill_id, connect_all } = req.query;

    const cfg = OAUTH_PROVIDERS[provider];
    if (!cfg) return res.status(400).json({ error: `Unknown OAuth provider: ${provider}` });
    if (!cfg.client_id) return res.status(422).json({ error: 'oauth_not_configured', provider });
    if (!agent_id || !skill_id) return res.status(400).json({ error: 'Missing agent_id or skill_id' });

    const { rows: [agentRow] } = await pool.query(
      'SELECT id FROM agents WHERE id = $1 AND user_id = $2',
      [agent_id, req.userId],
    );
    if (!agentRow) return res.status(404).json({ error: 'Agent not found' });

    const state = crypto.randomUUID();
    const codeVerifier = crypto.randomBytes(32).toString('base64url');
    const connectAll = connect_all === 'true';

    await pool.query(
      `INSERT INTO oauth_states (user_id, agent_id, skill_id, provider, state, code_verifier, connect_all)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [req.userId, agent_id, skill_id, provider, state, codeVerifier, connectAll],
    );

    const redirectUri = `${OAUTH_REDIRECT_BASE}/oauth/${provider}/callback`;
    const params = new URLSearchParams({
      client_id: cfg.client_id,
      redirect_uri: redirectUri,
      response_type: 'code',
      state,
    });

    if (cfg.scopes) {
      params.set('scope', cfg.scopes);
    }

    if (cfg.extra_params) {
      for (const [k, v] of Object.entries(cfg.extra_params)) {
        params.set(k, v);
      }
    }

    if (provider === 'notion') {
      params.set('owner', 'user');
    }

    const authUrl = `${cfg.authorize_url}?${params.toString()}`;
    res.json({ auth_url: authUrl, state });
  } catch (err) {
    console.error('oauth authorize:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Step 2: Provider redirects here after user grants permission.
// Exchanges the code for tokens, stores them, and redirects to the app.
app.get('/oauth/:provider/callback', async (req, res) => {
  try {
    const { provider } = req.params;
    const { code, state, error: oauthError } = req.query;

    if (oauthError) {
      return res.redirect(`openclaw://oauth/error?provider=${provider}&error=${encodeURIComponent(oauthError)}`);
    }

    if (!code || !state) {
      return res.redirect(`openclaw://oauth/error?provider=${provider}&error=missing_code_or_state`);
    }

    const cfg = OAUTH_PROVIDERS[provider];
    if (!cfg) {
      return res.redirect(`openclaw://oauth/error?provider=${provider}&error=unknown_provider`);
    }

    // Validate state and retrieve context
    const { rows: [oauthState] } = await pool.query(
      `DELETE FROM oauth_states WHERE state = $1 AND provider = $2 AND expires_at > NOW() RETURNING *`,
      [state, provider],
    );
    if (!oauthState) {
      return res.redirect(`openclaw://oauth/error?provider=${provider}&error=invalid_or_expired_state`);
    }

    const { user_id: userId, agent_id: agentId, skill_id: skillId, connect_all: connectAll } = oauthState;
    const redirectUri = `${OAUTH_REDIRECT_BASE}/oauth/${provider}/callback`;

    // Exchange code for tokens
    const tokenParams = new URLSearchParams({
      code,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code',
    });

    if (cfg.auth_method !== 'basic') {
      tokenParams.set('client_id', cfg.client_id);
      tokenParams.set('client_secret', cfg.client_secret);
    }

    const headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
    if (cfg.auth_method === 'basic') {
      const basicAuth = Buffer.from(`${cfg.client_id}:${cfg.client_secret}`).toString('base64');
      headers['Authorization'] = `Basic ${basicAuth}`;
    }

    // Notion expects JSON body
    let tokenResponse;
    if (provider === 'notion') {
      tokenResponse = await fetch(cfg.token_url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Basic ${Buffer.from(`${cfg.client_id}:${cfg.client_secret}`).toString('base64')}`,
          'Notion-Version': '2022-06-28',
        },
        body: JSON.stringify({
          grant_type: 'authorization_code',
          code,
          redirect_uri: redirectUri,
        }),
      });
    } else {
      tokenResponse = await fetch(cfg.token_url, {
        method: 'POST',
        headers,
        body: tokenParams.toString(),
      });
    }

    const tokenBody = await tokenResponse.json();

    if (!tokenResponse.ok) {
      console.error(`oauth token exchange failed for ${provider}:`, tokenBody);
      return res.redirect(`openclaw://oauth/error?provider=${provider}&error=token_exchange_failed`);
    }

    const extracted = cfg.extract_token(tokenBody);
    if (!extracted.access_token) {
      console.error(`no access_token in ${provider} response:`, tokenBody);
      return res.redirect(`openclaw://oauth/error?provider=${provider}&error=no_access_token`);
    }

    const expiresAt = extracted.expires_in
      ? new Date(Date.now() + extracted.expires_in * 1000)
      : null;

    // Store in oauth_tokens table
    await pool.query(
      `INSERT INTO oauth_tokens (user_id, agent_id, skill_id, provider, access_token, refresh_token, scope, expires_at, extra)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       ON CONFLICT (agent_id, skill_id, provider)
       DO UPDATE SET access_token = $5, refresh_token = COALESCE($6, oauth_tokens.refresh_token),
                     scope = $7, expires_at = $8, extra = $9, updated_at = NOW()`,
      [userId, agentId, skillId, provider, extracted.access_token,
       extracted.refresh_token, extracted.scope || null, expiresAt,
       JSON.stringify(extracted.extra || {})],
    );

    // Inject token into skill credentials so the agent can use it immediately
    const credentials = { [cfg.token_field]: extracted.access_token };
    setSkillCredentials(userId, agentId, skillId, credentials);

    // Mark skill as configured
    await pool.query(
      `UPDATE agent_skills SET config = config || $1 WHERE agent_id = $2 AND skill_id = $3`,
      [JSON.stringify({ _configured: true, _oauth_provider: provider }), agentId, skillId],
    );

    // Propagate token to all agents with matching skills when connect_all is set
    if (connectAll && cfg.skill_ids) {
      const { rows: otherSkills } = await pool.query(
        `SELECT a.id AS agent_id, s.skill_id
         FROM agents a
         JOIN agent_skills s ON s.agent_id = a.id
         WHERE a.user_id = $1
           AND s.skill_id = ANY($2)
           AND NOT (a.id = $3 AND s.skill_id = $4)`,
        [userId, cfg.skill_ids, agentId, skillId],
      );

      for (const row of otherSkills) {
        await pool.query(
          `INSERT INTO oauth_tokens (user_id, agent_id, skill_id, provider, access_token, refresh_token, scope, expires_at, extra)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           ON CONFLICT (agent_id, skill_id, provider)
           DO UPDATE SET access_token = $5, refresh_token = COALESCE($6, oauth_tokens.refresh_token),
                         scope = $7, expires_at = $8, extra = $9, updated_at = NOW()`,
          [userId, row.agent_id, row.skill_id, provider, extracted.access_token,
           extracted.refresh_token, extracted.scope || null, expiresAt,
           JSON.stringify(extracted.extra || {})],
        );
        setSkillCredentials(userId, row.agent_id, row.skill_id, credentials);
        await pool.query(
          `UPDATE agent_skills SET config = config || $1 WHERE agent_id = $2 AND skill_id = $3`,
          [JSON.stringify({ _configured: true, _oauth_provider: provider }), row.agent_id, row.skill_id],
        );
      }

      console.log(`[oauth] ${provider} connected for ALL agents (${otherSkills.length + 1} skills) user=${userId}`);
    } else {
      console.log(`[oauth] ${provider} connected for agent=${agentId} skill=${skillId}`);
    }

    res.redirect(`openclaw://oauth/success?provider=${provider}&skill_id=${encodeURIComponent(skillId)}&connect_all=${connectAll ? 'true' : 'false'}`);
  } catch (err) {
    console.error('oauth callback:', err);
    const { provider } = req.params;
    res.redirect(`openclaw://oauth/error?provider=${provider}&error=internal_error`);
  }
});

// Refresh an expired OAuth token
app.post('/oauth/:provider/refresh', authenticate, async (req, res) => {
  try {
    const { provider } = req.params;
    const { agent_id, skill_id } = req.body;

    const cfg = OAUTH_PROVIDERS[provider];
    if (!cfg) return res.status(400).json({ error: `Unknown OAuth provider: ${provider}` });

    const { rows: [tokenRow] } = await pool.query(
      `SELECT * FROM oauth_tokens WHERE agent_id = $1 AND skill_id = $2 AND provider = $3 AND user_id = $4`,
      [agent_id, skill_id, provider, req.userId],
    );
    if (!tokenRow) return res.status(404).json({ error: 'No OAuth tokens found for this skill' });
    if (!tokenRow.refresh_token) return res.status(400).json({ error: 'No refresh token available — user must re-authorize' });

    const tokenParams = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: tokenRow.refresh_token,
      client_id: cfg.client_id,
      client_secret: cfg.client_secret,
    });

    const tokenResponse = await fetch(cfg.token_url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: tokenParams.toString(),
    });

    const tokenBody = await tokenResponse.json();
    if (!tokenResponse.ok) {
      console.error(`oauth refresh failed for ${provider}:`, tokenBody);
      return res.status(502).json({ error: 'Token refresh failed — user may need to re-authorize' });
    }

    const newAccessToken = tokenBody.access_token;
    const newRefreshToken = tokenBody.refresh_token || tokenRow.refresh_token;
    const expiresAt = tokenBody.expires_in
      ? new Date(Date.now() + tokenBody.expires_in * 1000)
      : null;

    await pool.query(
      `UPDATE oauth_tokens SET access_token = $1, refresh_token = $2, expires_at = $3, updated_at = NOW()
       WHERE agent_id = $4 AND skill_id = $5 AND provider = $6`,
      [newAccessToken, newRefreshToken, expiresAt, agent_id, skill_id, provider],
    );

    // Re-inject updated token
    setSkillCredentials(req.userId, agent_id, skill_id, { [cfg.token_field]: newAccessToken });

    res.json({ status: 'refreshed', expires_at: expiresAt });
  } catch (err) {
    console.error('oauth refresh:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Check OAuth connection status for a skill
app.get('/oauth/status', authenticate, async (req, res) => {
  try {
    const { agent_id, skill_id } = req.query;
    if (!agent_id || !skill_id) return res.status(400).json({ error: 'Missing agent_id or skill_id' });

    const { rows: [tokenRow] } = await pool.query(
      `SELECT provider, scope, expires_at, extra, created_at, updated_at
       FROM oauth_tokens WHERE agent_id = $1 AND skill_id = $2 AND user_id = $3`,
      [agent_id, skill_id, req.userId],
    );

    if (!tokenRow) {
      const provider = oauthProviderForSkill(skill_id);
      return res.json({ connected: false, provider, has_oauth: !!provider });
    }

    const isExpired = tokenRow.expires_at && new Date(tokenRow.expires_at) < new Date();
    res.json({
      connected: !isExpired,
      provider: tokenRow.provider,
      has_oauth: true,
      scope: tokenRow.scope,
      expires_at: tokenRow.expires_at,
      connected_at: tokenRow.created_at,
      needs_refresh: isExpired,
      extra: tokenRow.extra,
    });
  } catch (err) {
    console.error('oauth status:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Global OAuth status: is the provider connected for any agent?
app.get('/oauth/:provider/status-global', authenticate, async (req, res) => {
  try {
    const { provider } = req.params;
    const cfg = OAUTH_PROVIDERS[provider];
    if (!cfg) return res.status(400).json({ error: `Unknown OAuth provider: ${provider}` });

    const { rows: eligibleSkills } = await pool.query(
      `SELECT a.id AS agent_id, a.name AS agent_name, s.skill_id
       FROM agents a
       JOIN agent_skills s ON s.agent_id = a.id
       WHERE a.user_id = $1 AND s.skill_id = ANY($2)`,
      [req.userId, cfg.skill_ids || []],
    );

    if (eligibleSkills.length === 0) {
      return res.json({ connected: false, has_eligible_skills: false, connected_count: 0, total_count: 0, agents: [] });
    }

    const { rows: connectedTokens } = await pool.query(
      `SELECT agent_id, skill_id, expires_at FROM oauth_tokens
       WHERE user_id = $1 AND provider = $2`,
      [req.userId, provider],
    );

    const connectedSet = new Set(connectedTokens.map(t => `${t.agent_id}:${t.skill_id}`));
    const anyExpired = connectedTokens.some(t => t.expires_at && new Date(t.expires_at) < new Date());

    const agents = eligibleSkills.map(s => ({
      agent_id: s.agent_id,
      agent_name: s.agent_name,
      skill_id: s.skill_id,
      connected: connectedSet.has(`${s.agent_id}:${s.skill_id}`),
    }));

    const connectedCount = agents.filter(a => a.connected).length;

    res.json({
      connected: connectedCount > 0,
      has_eligible_skills: true,
      connected_count: connectedCount,
      total_count: eligibleSkills.length,
      needs_refresh: anyExpired,
      agents,
    });
  } catch (err) {
    console.error('oauth status-global:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// ──────────────────────────────────────────────
// Voice – OpenAI Realtime API session creation
// ──────────────────────────────────────────────

const VOICE_PERSONA_INSTRUCTIONS = {
  Professional: 'You are a professional, business-oriented AI assistant. Be clear, concise, and action-oriented.',
  Friendly: 'You are a warm, approachable AI assistant. Be conversational and encouraging.',
  Technical: 'You are a technical AI assistant. Be detailed, precise, and data-driven.',
  Creative: 'You are a creative AI assistant. Be imaginative, expressive, and open to new ideas.',
};

app.post('/voice/session', authenticate, async (req, res) => {
  const agentId = req.body.agentId || req.body.agent_id;
  if (!agentId) return res.status(400).json({ error: 'agentId is required' });

  try {
    const { rows: [agent] } = await pool.query(
      'SELECT id, name, persona, openclaw_agent_id FROM agents WHERE id = $1 AND user_id = $2',
      [agentId, req.userId],
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    const openaiKey = process.env.OPENAI_API_KEY;
    if (!openaiKey) return res.status(503).json({ error: 'Voice not configured' });

    const ocAgentId = agent.openclaw_agent_id || openclawAgentId(req.userId, agentId);
    const OC_HOME = process.env.OPENCLAW_HOME || '/openclaw-home';

    // 1. Load agent's AGENTS.md for identity/persona context
    let agentIdentity = '';
    try {
      const agentsMdPath = path.join(OC_HOME, 'workspaces', ocAgentId, 'AGENTS.md');
      if (fs.existsSync(agentsMdPath)) {
        const raw = fs.readFileSync(agentsMdPath, 'utf8');
        // Extract just the identity/persona section (first ~800 chars) to stay concise
        const truncated = raw.length > 800 ? raw.slice(0, 800) + '\n...' : raw;
        agentIdentity = truncated;
      }
    } catch (err) {
      console.warn('[voice session] failed to read AGENTS.md:', err.message);
    }

    // 2. Load installed skills from DB + workspace
    const { rows: skills } = await pool.query(
      `SELECT skill_id, name, icon, enabled FROM agent_skills WHERE agent_id = $1 AND enabled = true ORDER BY installed_at`,
      [agentId],
    );
    let skillDescriptions = [];
    for (const skill of skills) {
      try {
        const skillMdPath = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills', skill.skill_id, 'SKILL.md');
        if (fs.existsSync(skillMdPath)) {
          const meta = parseSkillMd(skillMdPath);
          skillDescriptions.push({
            id: skill.skill_id,
            name: meta.name || skill.name || skill.skill_id,
            description: meta.description || '',
          });
        } else {
          skillDescriptions.push({
            id: skill.skill_id,
            name: skill.name || skill.skill_id,
            description: '',
          });
        }
      } catch {
        skillDescriptions.push({ id: skill.skill_id, name: skill.name || skill.skill_id, description: '' });
      }
    }

    // 3. Load conversation history (last 5 exchanges for summary)
    const history = await loadConversationHistory(agentId, req.userId);
    const recentHistory = history.slice(-10); // last 5 exchanges (user+assistant pairs)
    let conversationSummary = '';
    if (recentHistory.length > 0) {
      const summaryParts = [];
      for (let i = 0; i < recentHistory.length; i += 2) {
        const userMsg = recentHistory[i]?.content;
        const asstMsg = recentHistory[i + 1]?.content;
        if (userMsg && asstMsg) {
          const userSnippet = typeof userMsg === 'string' ? userMsg.slice(0, 150) : '[complex message]';
          const asstSnippet = typeof asstMsg === 'string' ? asstMsg.slice(0, 150) : '[complex response]';
          summaryParts.push(`User: ${userSnippet}${userMsg.length > 150 ? '...' : ''}\nAssistant: ${asstSnippet}${asstMsg.length > 150 ? '...' : ''}`);
        }
      }
      if (summaryParts.length > 0) {
        conversationSummary = `\n\nRECENT CONVERSATION CONTEXT:\n${summaryParts.join('\n---\n')}`;
      }
    }

    // 4. Build rich instructions
    const basePrompt = VOICE_PERSONA_INSTRUCTIONS[agent.persona] || VOICE_PERSONA_INSTRUCTIONS.Professional;

    let skillsSection = '';
    if (skillDescriptions.length > 0) {
      const skillList = skillDescriptions.map(s =>
        `- ${s.name}: ${s.description || 'No description'}`
      ).join('\n');
      skillsSection = `\n\nYOUR INSTALLED CAPABILITIES:\n${skillList}\nUse the corresponding tool or run_task to invoke any of these capabilities.`;
    }

    const identitySection = agentIdentity
      ? `\n\nAGENT IDENTITY & INSTRUCTIONS:\n${agentIdentity}`
      : '';

    const instructions = `${basePrompt}

You are speaking in a real-time voice conversation. Keep responses concise — aim for 2-3 sentences unless asked for detail.${identitySection}${skillsSection}${conversationSummary}

CRITICAL TOOL USAGE: You have tools available. You MUST use them whenever:
- The user asks for current/recent information (news, weather, prices, events)
- The user asks you to search, look up, or find something
- The user asks you to perform any action (send email, check calendar, query data, etc.)
- You are unsure about facts or need to verify something
- The user mentions anything that requires real-time data or an installed skill

You DO have internet access through your tools. NEVER say you cannot access the internet or search the web. Instead, call the appropriate tool with a clear description. After the result comes back, summarize it naturally in speech.`;

    // 5. Build tool definitions: per-skill tools + general run_task
    const tools = [];

    // Register per-skill tools (up to 8 to stay under Realtime API limits)
    for (const skill of skillDescriptions.slice(0, 8)) {
      const toolName = `skill_${skill.id.replace(/[^a-zA-Z0-9_]/g, '_').slice(0, 40)}`;
      tools.push({
        type: 'function',
        name: toolName,
        description: `Use the "${skill.name}" skill. ${skill.description || `Invoke the ${skill.name} capability.`}`,
        parameters: {
          type: 'object',
          properties: {
            task_description: {
              type: 'string',
              description: `Describe what you want the ${skill.name} skill to do, including all relevant details`,
            },
          },
          required: ['task_description'],
        },
      });
    }

    // Always include general run_task as fallback
    tools.push({
      type: 'function',
      name: 'run_task',
      description: 'Run a general task using the AI agent with full tool access (web search, code execution, file operations, etc.). Use this for anything not covered by a specific skill tool, or when you need multiple capabilities combined.',
      parameters: {
        type: 'object',
        properties: {
          task_description: {
            type: 'string',
            description: 'Clear description of what to do, including all relevant details from the conversation',
          },
        },
        required: ['task_description'],
      },
    });

    // 6. Create OpenAI Realtime session
    const response = await fetch('https://api.openai.com/v1/realtime/sessions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-realtime-preview',
        voice: 'alloy',
        instructions,
        tools,
        input_audio_transcription: { model: 'whisper-1' },
        turn_detection: { type: 'server_vad', threshold: 0.6, prefix_padding_ms: 500, silence_duration_ms: 1200 },
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      console.error('OpenAI realtime session error:', response.status, body);
      return res.status(502).json({ error: 'Failed to create voice session' });
    }

    const data = await response.json();

    // 7. Build conversation items for iOS to inject via conversation.item.create
    const conversationItems = [];
    const injectHistory = history.slice(-10); // last 5 exchanges
    for (let i = 0; i < injectHistory.length; i += 2) {
      const userMsg = injectHistory[i];
      const asstMsg = injectHistory[i + 1];
      if (userMsg && asstMsg) {
        const userText = typeof userMsg.content === 'string'
          ? userMsg.content.slice(0, 300) : '[complex message]';
        const asstText = typeof asstMsg.content === 'string'
          ? asstMsg.content.slice(0, 300) : '[complex response]';
        conversationItems.push(
          { role: 'user', text: userText },
          { role: 'assistant', text: asstText },
        );
      }
    }

    // 8. Store session state in Redis for text/voice continuity
    const sessionKey = `voice_session:${req.userId}:${agentId}`;
    const sessionState = {
      userId: req.userId,
      agentId,
      ocAgentId,
      startedAt: Date.now(),
      skills: skillDescriptions.map(s => s.name),
      model: data.model,
    };
    await redis.set(sessionKey, JSON.stringify(sessionState), 'EX', 1800); // 30 min TTL

    console.log(`[voice session] created for agent=${ocAgentId} skills=${skillDescriptions.length} historyItems=${conversationItems.length}`);

    res.json({
      token: data.client_secret.value,
      expiresAt: data.client_secret.expires_at,
      model: data.model,
      conversationItems,
      skills: skillDescriptions.map(s => ({ id: s.id, name: s.name })),
    });
  } catch (err) {
    console.error('voice session:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/voice/tool-call', authenticate, async (req, res) => {
  const agentId = req.body.agentId || req.body.agent_id;
  const taskDescription = req.body.taskDescription || req.body.task_description;
  const skillName = req.body.skillName || req.body.skill_name;

  if (!agentId || !taskDescription) {
    return res.status(400).json({ error: 'agentId and taskDescription are required' });
  }

  try {
    const { rows: [agent] } = await pool.query(
      'SELECT id, user_id, openclaw_agent_id FROM agents WHERE id = $1 AND user_id = $2',
      [agentId, req.userId],
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    const ocAgentId = agent.openclaw_agent_id || openclawAgentId(req.userId, agentId);

    console.log(`[voice tool-call] agent=${ocAgentId} skill=${skillName || 'general'} task="${taskDescription.slice(0, 100)}"`);

    ensureWorkspaceReady(ocAgentId);
    await refreshOAuthTokensForAgent(agentId, req.userId);

    const OC_HOME = process.env.OPENCLAW_HOME || '/openclaw-home';
    let systemPrompt = 'You are handling a voice assistant request. Use your available tools to fulfill the request. Provide a clear, concise text result.';
    try {
      const agentsMdPath = path.join(OC_HOME, 'workspaces', ocAgentId, 'AGENTS.md');
      if (fs.existsSync(agentsMdPath)) {
        const agentsMd = fs.readFileSync(agentsMdPath, 'utf8');
        systemPrompt = agentsMd + '\n\nIMPORTANT: This request comes from a voice conversation. Provide a clear, concise text result that can be spoken aloud. Do NOT say you cannot access the internet — you have web search available.';
      }
    } catch (err) {
      console.warn('[voice tool-call] failed to read AGENTS.md:', err.message);
    }

    // If a specific skill was invoked, prepend skill context to the task
    let enrichedTask = taskDescription;
    if (skillName) {
      enrichedTask = `[Using skill: ${skillName}] ${taskDescription}`;
    }

    const history = await loadConversationHistory(agentId, req.userId);
    const messages = [
      { role: 'system', content: systemPrompt },
      ...history,
      { role: 'user', content: enrichedTask },
    ];

    const response = await chatCompletionSync({
      agentId: ocAgentId,
      messages,
      userId: req.userId,
    });

    const choice = response.choices?.[0];
    const content = choice?.message?.content;

    console.log(`[voice tool-call] result length=${content?.length || 0} finish=${choice?.finish_reason}`);

    const result = content || 'The task completed but produced no text output.';
    const trimmedResult = result.slice(0, 4000);

    const inputLabel = skillName ? `🎙️🔧 [${skillName}] ${taskDescription}` : `🎙️ ${taskDescription}`;
    await pool.query(
      `INSERT INTO tasks (agent_id, user_id, input, output, status, completed_at)
       VALUES ($1, $2, $3, $4, 'completed', NOW())`,
      [agentId, req.userId, inputLabel, trimmedResult],
    );

    // Update Redis session state with last tool call info
    try {
      const sessionKey = `voice_session:${req.userId}:${agentId}`;
      const existing = await redis.get(sessionKey);
      if (existing) {
        const state = JSON.parse(existing);
        state.lastToolCall = { skill: skillName || 'run_task', at: Date.now() };
        state.toolCallCount = (state.toolCallCount || 0) + 1;
        await redis.set(sessionKey, JSON.stringify(state), 'EX', 1800);
      }
    } catch { /* non-fatal */ }

    res.json({ result: trimmedResult });
  } catch (err) {
    console.error('voice tool-call error:', err.message || err);
    res.status(500).json({ result: 'Sorry, the task failed to execute. Please try again.' });
  }
});

app.post('/voice/transcript', authenticate, async (req, res) => {
  const agentId = req.body.agentId || req.body.agent_id;
  const turns = req.body.turns;

  if (!agentId || !Array.isArray(turns) || turns.length === 0) {
    return res.status(400).json({ error: 'agentId and turns array are required' });
  }

  try {
    const { rows: [agent] } = await pool.query(
      'SELECT id FROM agents WHERE id = $1 AND user_id = $2',
      [agentId, req.userId],
    );
    if (!agent) return res.status(404).json({ error: 'Agent not found' });

    let saved = 0;
    for (const turn of turns) {
      const userText = turn.userText || turn.user_text || '';
      const agentText = turn.agentText || turn.agent_text || '';
      if (!userText && !agentText) continue;

      const input = userText || '[Voice conversation]';
      const output = agentText || '[No response]';

      await pool.query(
        `INSERT INTO tasks (agent_id, user_id, input, output, status, completed_at)
         VALUES ($1, $2, $3, $4, 'completed', NOW())`,
        [agentId, req.userId, `🎙️ ${input}`, output],
      );
      saved++;
    }

    // Clear the voice session state in Redis now that session ended
    try {
      await redis.del(`voice_session:${req.userId}:${agentId}`);
    } catch { /* non-fatal */ }

    res.json({ saved });
  } catch (err) {
    console.error('voice transcript:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

// Voice session state — allows text mode to detect active voice sessions
app.get('/voice/session-state/:agentId', authenticate, async (req, res) => {
  try {
    const sessionKey = `voice_session:${req.userId}:${req.params.agentId}`;
    const state = await redis.get(sessionKey);
    if (!state) return res.json({ active: false });
    res.json({ active: true, ...JSON.parse(state) });
  } catch (err) {
    console.error('voice session-state:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

app.post('/voice/usage', authenticate, async (req, res) => {
  const { durationSeconds } = req.body;
  if (!durationSeconds || durationSeconds < 0) {
    return res.status(400).json({ error: 'durationSeconds is required' });
  }

  const capped = Math.min(Math.round(durationSeconds), 3600);

  try {
    await pool.query(
      `INSERT INTO usage_daily (user_id, date, voice_seconds)
       VALUES ($1, CURRENT_DATE, $2)
       ON CONFLICT (user_id, date)
       DO UPDATE SET voice_seconds = usage_daily.voice_seconds + $2`,
      [req.userId, capped],
    );
    res.json({ recorded: capped });
  } catch (err) {
    console.error('voice usage:', err);
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

// Periodic cleanup of expired rows (runs every hour)
async function cleanupExpired() {
  try {
    const { rowCount: states } = await pool.query(
      'DELETE FROM oauth_states WHERE expires_at < NOW()',
    );
    const { rowCount: tokens } = await pool.query(
      'DELETE FROM refresh_tokens WHERE expires_at < NOW()',
    );
    if (states || tokens) {
      console.log(`[cleanup] removed ${states} expired oauth_states, ${tokens} expired refresh_tokens`);
    }
  } catch (err) {
    console.warn('[cleanup] error:', err.message);
  }
}

ensureSchema().then(async () => {
  await loadOAuthConfigFromDB();
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`API Gateway listening on :${PORT}`);
    console.log(`WebSocket relay available at ws://0.0.0.0:${PORT}/ws/agents/:agentId`);
  });

  cleanupExpired();
  const cleanupInterval = setInterval(cleanupExpired, 60 * 60 * 1000);
  if (cleanupInterval.unref) cleanupInterval.unref();
});
