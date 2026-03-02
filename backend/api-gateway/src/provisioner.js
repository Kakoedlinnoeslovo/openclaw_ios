// Provisions per-user OpenClaw agents: workspace creation, config management,
// and starter-skill installation.

const fs = require('fs');
const path = require('path');

const OC_HOME = process.env.OPENCLAW_HOME || '/openclaw-home';
const CONFIG_PATH = path.join(OC_HOME, 'openclaw.json');

// ── Config I/O ──────────────────────────────────────

function readConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  } catch {
    return buildBaseConfig();
  }
}

function writeConfig(config) {
  fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}

// ── Base config (written once on first boot) ────────

function buildBaseConfig() {
  return {
    gateway: {
      auth: { mode: 'token', token: process.env.OPENCLAW_GATEWAY_TOKEN },
      controlUi: { enabled: false },
      http: {
        endpoints: {
          chatCompletions: { enabled: true },
        },
      },
    },
    agents: {
      defaults: {
        model: 'openai/gpt-4o-mini',
        sandbox: { mode: 'off' },
      },
      list: [],
    },
    skills: {
      allowBundled: ['*'],
    },
  };
}

function ensureBaseConfig() {
  if (!fs.existsSync(CONFIG_PATH)) {
    writeConfig(buildBaseConfig());
    console.log('Created base OpenClaw config at', CONFIG_PATH);
  }
}

// ── Model mapping (iOS enum → OpenClaw provider/model) ──

const MODEL_MAP = {
  'gpt-4o-mini': 'openai/gpt-4o-mini',
  'gpt-4o': 'openai/gpt-4o',
  'claude-sonnet': 'anthropic/claude-sonnet-4-6',
};

function mapModel(iosModel) {
  return MODEL_MAP[iosModel] || 'openai/gpt-4o-mini';
}

// ── Persona → AGENTS.md prompt ──────────────────────

const PERSONA_PROMPTS = {
  Professional: 'You are a professional, concise, business-oriented AI assistant. Provide clear, actionable responses.',
  Friendly: 'You are a warm, approachable, conversational AI assistant. Be encouraging and helpful.',
  Technical: 'You are a detailed, precise, data-driven AI assistant. Provide thorough technical explanations.',
  Creative: 'You are an imaginative, expressive, open-ended AI assistant. Think outside the box.',
};

// ── Starter skills (pre-installed for every new agent) ──

const STARTER_SKILLS = [
  'web-research',
  'email-drafts',
  'meeting-notes',
  'code-review',
  'blog-writer',
];

// ── Provision a new agent ───────────────────────────

function openclawAgentId(userId, agentId) {
  return `u${userId.replace(/-/g, '').slice(0, 12)}-${agentId.replace(/-/g, '').slice(0, 12)}`;
}

function provisionAgent({ userId, agentId, name, persona, model }) {
  const ocAgentId = openclawAgentId(userId, agentId);

  // Workspace lives inside the shared OpenClaw home volume.
  // Paths below are as seen from inside the OpenClaw gateway container.
  const workspaceRel = `workspaces/${ocAgentId}`;
  const workspaceAbs = path.join(OC_HOME, workspaceRel);
  const gatewayWorkspace = `/home/node/.openclaw/${workspaceRel}`;

  fs.mkdirSync(path.join(workspaceAbs, 'skills'), { recursive: true });

  // Bootstrap workspace files
  const prompt = PERSONA_PROMPTS[persona] || PERSONA_PROMPTS.Professional;
  fs.writeFileSync(
    path.join(workspaceAbs, 'AGENTS.md'),
    `# ${name}\n\n${prompt}\n`
  );
  fs.writeFileSync(
    path.join(workspaceAbs, 'SOUL.md'),
    `# Soul\n\nI am ${name}, a personal AI assistant.\n`
  );

  // Create per-agent auth-profiles.json with platform API keys.
  // OpenClaw reads credentials from this file for each agent.
  const agentDir = path.join(OC_HOME, 'agents', ocAgentId, 'agent');
  fs.mkdirSync(agentDir, { recursive: true });

  const authProfiles = { profiles: {} };
  if (process.env.OPENAI_API_KEY) {
    authProfiles.profiles.openai = {
      provider: 'openai',
      type: 'api-key',
      api_key: process.env.OPENAI_API_KEY,
    };
  }
  if (process.env.ANTHROPIC_API_KEY) {
    authProfiles.profiles.anthropic = {
      provider: 'anthropic',
      type: 'api-key',
      api_key: process.env.ANTHROPIC_API_KEY,
    };
  }
  fs.writeFileSync(
    path.join(agentDir, 'auth-profiles.json'),
    JSON.stringify(authProfiles, null, 2),
  );

  // Add agent to OpenClaw config
  const config = readConfig();
  config.agents = config.agents || { defaults: {}, list: [] };
  config.agents.list = config.agents.list || [];
  config.agents.list = config.agents.list.filter(a => a.id !== ocAgentId);
  config.agents.list.push({
    id: ocAgentId,
    name,
    workspace: gatewayWorkspace,
    model: mapModel(model),
  });
  writeConfig(config);

  return { openclawAgentId: ocAgentId, workspacePath: workspaceAbs };
}

// ── Deprovision (delete agent entry, keep files for safety) ──

function deprovisionAgent(userId, agentId) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const config = readConfig();
  if (config.agents?.list) {
    config.agents.list = config.agents.list.filter(a => a.id !== ocAgentId);
    writeConfig(config);
  }
}

// ── Skill installation (symlink bundled skill into workspace) ──

function installSkill(userId, agentId, skillId) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const workspaceSkills = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills');
  fs.mkdirSync(workspaceSkills, { recursive: true });

  // Bundled skills live at /home/node/.openclaw/skills/<skillId> in the
  // OpenClaw image.  In our shared volume that's OC_HOME/skills/<skillId>.
  // If the bundled skill directory exists, create a symlink; otherwise we
  // rely on OpenClaw's global skill loading (allowBundled: true).
  const bundledSrc = path.join(OC_HOME, 'skills', skillId);
  const dest = path.join(workspaceSkills, skillId);

  if (fs.existsSync(bundledSrc) && !fs.existsSync(dest)) {
    try {
      fs.symlinkSync(bundledSrc, dest);
    } catch {
      // Symlink may fail in some Docker volume drivers — non-fatal.
    }
  }
}

function installStarterSkills(userId, agentId) {
  for (const skillId of STARTER_SKILLS) {
    installSkill(userId, agentId, skillId);
  }
}

module.exports = {
  ensureBaseConfig,
  provisionAgent,
  deprovisionAgent,
  installSkill,
  installStarterSkills,
  openclawAgentId,
  mapModel,
  STARTER_SKILLS,
};
