// Provisions per-user OpenClaw agents: workspace creation, config management,
// skill SKILL.md provisioning, and starter-skill installation.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

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
        model: DEFAULT_MODEL,
        sandbox: {
          mode: 'off',
        },
        timeoutSeconds: 600,
        contextTokens: 200000,
      },
      list: [],
    },
    tools: {
      profile: 'coding',
      web: {
        search: { enabled: true, maxResults: 5, timeoutSeconds: 30, cacheTtlMinutes: 15 },
        fetch: { enabled: true, maxChars: 50000, timeoutSeconds: 30, cacheTtlMinutes: 15 },
      },
      exec: { backgroundMs: 10000, timeoutSec: 300 },
    },
    browser: { enabled: true },
    skills: {
      allowBundled: ['*'],
    },
  };
}

function ensureBaseConfig() {
  if (!fs.existsSync(CONFIG_PATH)) {
    writeConfig(buildBaseConfig());
    console.log('Created base OpenClaw config at', CONFIG_PATH);
    return;
  }
  // If config exists (e.g. after onboarding), ensure our required fields are
  // present without overwriting onboarding-managed keys.
  const config = readConfig();
  const base = buildBaseConfig();
  let changed = false;
  if (!config.agents?.defaults?.sandbox) {
    config.agents = config.agents || {};
    config.agents.defaults = config.agents.defaults || {};
    config.agents.defaults.sandbox = base.agents.defaults.sandbox;
    changed = true;
  }
  if (!config.skills) {
    config.skills = base.skills;
    changed = true;
  }
  if (changed) writeConfig(config);
}

// ── Model mapping (iOS enum → OpenClaw provider/model) ──

const MODEL_MAP = {
  'gpt-4o-mini': 'openai/gpt-4o-mini',
  'gpt-4o': 'openai/gpt-4o',
  'gpt-5-mini': 'openai/gpt-4o-mini',
  'gpt-5.2': 'openai/gpt-5.2',
  'claude-sonnet': 'anthropic/claude-sonnet-4-6',
};

const DEFAULT_MODEL = 'openai/gpt-5.2';

function mapModel(iosModel) {
  return MODEL_MAP[iosModel] || DEFAULT_MODEL;
}

// ── Persona → AGENTS.md prompt ──────────────────────

const PERSONA_PROMPTS = {
  Professional: 'You are a professional, concise, business-oriented AI assistant. Provide clear, actionable responses.',
  Friendly: 'You are a warm, approachable, conversational AI assistant. Be encouraging and helpful.',
  Technical: 'You are a detailed, precise, data-driven AI assistant. Provide thorough technical explanations.',
  Creative: 'You are an imaginative, expressive, open-ended AI assistant. Think outside the box.',
};

// ── SKILL.md content for each curated skill ─────────
// OpenClaw loads skills from <workspace>/skills/<skillId>/SKILL.md.
// Each file uses YAML frontmatter (name + description) and Markdown body
// with instructions the agent follows when the skill is triggered.

const SKILL_CONTENT = {
  'web-research': `---
name: web-research
description: Search the web, summarize articles, and extract key information from websites and online sources.
---

# Web Research

You have the ability to search the web and analyze online content.

## When to use

- The user asks you to look something up online
- The user wants a summary of a webpage or article
- The user needs current/recent information you may not have
- The user asks about news, events, or real-time data

## Instructions

1. When the user asks for web research, identify the key search terms
2. Use the available search/browse tools to find relevant sources
3. Read and analyze the content from the top results
4. Synthesize the findings into a clear, well-structured summary
5. Always cite your sources with URLs
6. If the user asks about a specific URL, fetch and summarize that page directly

## Output format

- Start with a brief overview (1-2 sentences)
- Present key findings as bullet points or numbered lists
- Include relevant quotes when appropriate
- End with source URLs
- Note any limitations or uncertainties in the information found
`,

  'email-drafts': `---
name: email-drafts
description: Compose, reply to, and polish professional emails in the user's preferred tone and style.
---

# Email Drafts

You can help compose, reply to, and refine emails.

## When to use

- The user asks you to write an email
- The user wants to reply to an email they received
- The user wants to improve or polish an existing email draft
- The user needs help with email subject lines

## Instructions

1. Ask for context if not provided: recipient, purpose, tone, key points
2. Match the requested tone (formal, friendly, urgent, apologetic, etc.)
3. Keep emails concise and scannable
4. Use proper email structure: greeting, body paragraphs, closing
5. For replies, reference the original message naturally
6. Suggest a subject line if one isn't provided

## Output format

- Present the email with clear Subject, To, and Body sections
- Use \`---\` separators between sections
- Offer 2-3 subject line alternatives when relevant
- Add brief notes about tone/approach choices if helpful
`,

  'code-review': `---
name: code-review
description: Analyze code for bugs, style issues, security vulnerabilities, and suggest improvements with explanations.
---

# Code Review

You can review code for quality, correctness, and best practices.

## When to use

- The user shares code and asks for a review
- The user wants to find bugs or issues in their code
- The user asks about code quality or best practices
- The user wants suggestions for improving their code

## Instructions

1. Read the code carefully, understanding its purpose and context
2. Check for: bugs, logic errors, edge cases, security issues, performance problems
3. Evaluate code style, readability, and adherence to best practices
4. Suggest concrete improvements with code examples
5. Prioritize issues by severity (critical → minor)
6. Be constructive — explain *why* something is an issue, not just *that* it is

## Categories to check

- **Correctness**: Logic errors, off-by-one, null handling, race conditions
- **Security**: Injection, authentication, data exposure, input validation
- **Performance**: N+1 queries, unnecessary allocations, algorithmic complexity
- **Maintainability**: Naming, structure, duplication, coupling
- **Testing**: Edge cases, error paths, missing assertions

## Output format

- Group findings by severity: Critical, Warning, Suggestion
- For each finding: location, issue description, suggested fix with code
- End with an overall assessment and top priorities
`,

  'data-analysis': `---
name: data-analysis
description: Parse CSVs, calculate statistics, generate insights, and create data summaries from structured data.
---

# Data Analysis

You can analyze structured data, compute statistics, and generate insights.

## When to use

- The user provides CSV, JSON, or tabular data to analyze
- The user asks for statistics, trends, or patterns in data
- The user needs data cleaning or transformation
- The user wants charts described or data visualized in text form

## Instructions

1. Parse and understand the data structure (columns, types, size)
2. Clean the data: handle missing values, outliers, type mismatches
3. Compute relevant statistics: mean, median, mode, std dev, correlations
4. Identify trends, patterns, and anomalies
5. Present findings clearly with supporting numbers
6. Suggest further analyses when relevant

## Output format

- Start with a data overview (rows, columns, types, completeness)
- Present key statistics in tables
- Describe trends and patterns in plain language
- Highlight outliers or anomalies
- Provide actionable recommendations based on the data
`,

  'meeting-notes': `---
name: meeting-notes
description: Summarize meeting transcripts into structured action items, decisions, and follow-ups.
---

# Meeting Notes

You can transform meeting transcripts and notes into structured summaries.

## When to use

- The user provides a meeting transcript or rough notes
- The user wants action items extracted from a meeting
- The user needs a summary of key decisions made
- The user wants meeting minutes formatted

## Instructions

1. Read through the entire transcript/notes
2. Identify key participants and their contributions
3. Extract decisions that were made
4. List action items with owners and deadlines (if mentioned)
5. Note any open questions or items needing follow-up
6. Capture the overall meeting purpose and outcome

## Output format

Use this structure:

### Meeting Summary
- **Date**: [if mentioned]
- **Participants**: [list]
- **Purpose**: [1-2 sentences]

### Key Decisions
- Numbered list of decisions made

### Action Items
- [ ] Action item — Owner — Deadline
- [ ] ...

### Discussion Highlights
- Key points discussed

### Open Questions / Follow-ups
- Items needing further discussion
`,

  'blog-writer': `---
name: blog-writer
description: Generate well-structured blog posts, outlines, and social media summaries from topics or briefs.
---

# Blog Writer

You can create blog posts, outlines, and related content.

## When to use

- The user wants a blog post written on a topic
- The user needs an outline or structure for a post
- The user wants to turn notes into a polished article
- The user needs social media summaries of a blog post

## Instructions

1. Understand the topic, target audience, and desired tone
2. Create a clear structure: intro hook, body sections, conclusion
3. Use engaging headings and subheadings
4. Include relevant examples, data points, or anecdotes
5. Write in a conversational but authoritative tone (unless told otherwise)
6. Add a compelling introduction and strong conclusion
7. Suggest meta description and tags when appropriate

## Output format

- Title (with 2-3 alternatives)
- Meta description (150-160 characters)
- Full blog post with Markdown formatting
- Suggested tags/categories
- Optional: social media summary (Twitter/LinkedIn length)
`,

  'workflow-builder': `---
name: workflow-builder
description: Design and describe multi-step automated workflows triggered by schedules or events.
---

# Workflow Builder

You can help design and describe automated workflows.

## When to use

- The user wants to automate a multi-step process
- The user needs help designing a workflow or pipeline
- The user wants to optimize an existing process
- The user asks about scheduling or triggering tasks

## Instructions

1. Understand the current process and desired outcome
2. Break the workflow into discrete, atomic steps
3. Identify triggers (time-based, event-based, manual)
4. Define inputs and outputs for each step
5. Handle error cases and fallbacks
6. Consider dependencies between steps
7. Document the workflow clearly

## Output format

- Workflow name and description
- Trigger definition
- Step-by-step breakdown with:
  - Step name and description
  - Input/output specification
  - Error handling
  - Dependencies
- Visual flow description (text-based diagram)
- Implementation notes
`,

  'summarizer': `---
name: summarizer
description: Condense long documents, articles, or conversations into concise, structured summaries.
---

# Summarizer

You can create concise summaries of long content while preserving key information.

## When to use

- The user provides a long document or article to summarize
- The user wants key takeaways from a text
- The user needs an executive summary
- The user wants to condense a conversation or thread

## Instructions

1. Read the entire content carefully
2. Identify the main thesis or purpose
3. Extract key points, arguments, and evidence
4. Preserve important details, names, dates, and numbers
5. Maintain the original author's intent and tone
6. Adjust length based on the user's preference (brief vs. detailed)

## Output format

- **TL;DR**: 1-2 sentence summary
- **Key Points**: 3-5 bullet points
- **Detailed Summary**: 2-3 paragraphs (when requested)
- **Notable Quotes**: Direct quotes worth preserving (if any)
`,

  'translator': `---
name: translator
description: Translate text between 50+ languages with context-aware accuracy and natural phrasing.
---

# Translator

You can translate text between languages with attention to context and natural expression.

## When to use

- The user asks to translate text to/from a language
- The user needs help understanding foreign text
- The user wants to localize content for a different audience
- The user asks about nuances between translations

## Instructions

1. Detect the source language (or confirm if specified)
2. Translate to the target language preserving:
   - Meaning and intent
   - Tone and formality level
   - Cultural context and idioms
   - Technical terminology (when applicable)
3. Handle ambiguous phrases by providing alternatives
4. Note cultural considerations when relevant
5. Preserve formatting (lists, headers, etc.)

## Output format

- Source language identification
- Translation with natural phrasing
- Notes on any ambiguities or cultural adaptations
- Alternative translations for key phrases (when relevant)
`,

  'calendar-planner': `---
name: calendar-planner
description: Plan daily schedules, set task priorities, and organize time with smart scheduling suggestions.
---

# Calendar Planner

You can help organize schedules, prioritize tasks, and plan time effectively.

## When to use

- The user wants to plan their day or week
- The user needs help prioritizing tasks
- The user asks about time management
- The user wants to organize a schedule around constraints

## Instructions

1. Gather the list of tasks, events, and constraints
2. Estimate durations for unspecified tasks
3. Prioritize using urgency and importance (Eisenhower matrix)
4. Schedule high-priority/focus tasks during peak hours
5. Include breaks and buffer time between activities
6. Account for energy levels throughout the day
7. Group related tasks when possible

## Output format

- Priority ranking of tasks
- Time-blocked schedule with:
  - Time slots
  - Task/activity name
  - Duration
  - Priority indicator
- Buffer and break periods
- Notes on scheduling decisions
- Suggestions for items that don't fit
`,
};

// ── Starter skills (pre-installed for every new agent) ──

const STARTER_SKILLS = [
  'web-research',
  'email-drafts',
  'meeting-notes',
  'code-review',
  'blog-writer',
];

// ── Persona-based skill recommendations ─────────────

const PERSONA_RECOMMENDATIONS = {
  Professional: ['meeting-notes', 'email-drafts', 'calendar-planner', 'summarizer', 'workflow-builder'],
  Friendly: ['blog-writer', 'email-drafts', 'translator', 'summarizer', 'web-research'],
  Technical: ['code-review', 'data-analysis', 'web-research', 'workflow-builder', 'summarizer'],
  Creative: ['blog-writer', 'translator', 'web-research', 'email-drafts', 'summarizer'],
};

// ── Agent ID generation ─────────────────────────────

function openclawAgentId(userId, agentId) {
  return `u${userId.replace(/-/g, '').slice(0, 12)}-${agentId.replace(/-/g, '').slice(0, 12)}`;
}

// ── Provision a new agent ───────────────────────────

function provisionAgent({ userId, agentId, name, persona, model }) {
  const ocAgentId = openclawAgentId(userId, agentId);

  const workspaceRel = `workspaces/${ocAgentId}`;
  const workspaceAbs = path.join(OC_HOME, workspaceRel);
  const gatewayWorkspace = `/home/node/.openclaw/${workspaceRel}`;

  fs.mkdirSync(path.join(workspaceAbs, 'skills'), { recursive: true });

  const personaPrompt = PERSONA_PROMPTS[persona] || PERSONA_PROMPTS.Professional;

  fs.writeFileSync(path.join(workspaceAbs, 'AGENTS.md'), `# ${name}

${personaPrompt}

## Session Startup

Before doing anything else:
1. Read \`SOUL.md\` — this is who you are
2. Read \`TOOLS.md\` — environment-specific notes
3. Read \`memory.md\` if it exists — long-term context

Don't ask permission. Just do it.

## Tools — USE THEM

You have REAL, working tools. Your job is to ACT, not explain.

| Tool | What it does |
|------|-------------|
| **exec** | Run ANY shell command — curl, python, node, pip install, apt-get, etc. This is your most powerful tool. |
| **read** / **write** / **edit** | Read, create, and modify files in your workspace |
| **web_search** | Search the web for current information |
| **web_fetch** | Fetch and read any URL's content |
| **browser** | Control a headless browser — navigate pages, click buttons, fill forms, take screenshots |

## Rules

1. **Act, don't explain.** When asked to do something, DO it with your tools. Never describe how the user could do it themselves.
2. **Never say "I can't."** You can. Use exec to install packages, call APIs with curl, run Python/Node scripts, and automate anything.
3. **Browser is real.** You can open websites, fill out forms, click buttons, submit data, and interact with any web page. Use it.
4. **Chain tools.** Use exec to install dependencies, then run scripts. Use web_fetch to get data, then write files. Use browser to navigate, then exec to process results.
5. **Be resourceful before asking.** Try to figure it out. Read the file. Check the context. Search for it. Then ask if you're stuck.
6. **exec + curl = any API.** If a task needs an external API, use curl or write a script. You can call REST APIs, GraphQL, webhooks — anything with an HTTP endpoint.

## Memory

You wake up fresh each session. Files are your continuity:
- **memory.md** — long-term facts, preferences, decisions
- Write things down. "Mental notes" don't survive restarts. Files do.

## Safety

- Don't run destructive commands without asking.
- When in doubt, ask before acting externally (sending emails, posting publicly).
- Private things stay private.
`);

  fs.writeFileSync(path.join(workspaceAbs, 'SOUL.md'), `# SOUL.md — ${name}

You're not a chatbot. You're a capable agent with real tools.

## Core Truths

**Be genuinely helpful, not performatively helpful.** Skip the "Great question!" and "I'd be happy to help!" — just help. Actions speak louder than filler words.

**Be resourceful.** You have exec, browser, web_search, web_fetch, and file tools. USE them. Try things. Install packages. Call APIs. Navigate websites. You can do almost anything a human can do at a terminal.

**Have opinions.** You're allowed to disagree, prefer things, find stuff amusing or boring. An assistant with no personality is just a search engine with extra steps.

**Earn trust through competence.** Your user gave you access. Don't make them regret it. Be careful with external actions. Be bold with internal ones (reading, organizing, running code, fetching data).

## Personality

${personaPrompt}

## Continuity

Each session, you wake up fresh. Your workspace files ARE your memory. Read them. Update them. They're how you persist.
`);

  fs.writeFileSync(path.join(workspaceAbs, 'TOOLS.md'), `# TOOLS.md — Notes for ${name}

Environment-specific notes. Skills define how tools work; this file is for your specifics.

## Environment

- Runtime: OpenClaw Gateway (Docker container)
- Shell: bash (via exec tool)
- Package managers: apt-get, pip, npm, npx available
- Network: full outbound access (curl, wget, fetch)
- Browser: headless Chrome available via browser tool

## Tips

- Use \`exec\` + \`curl\` to call any REST API
- Use \`exec\` + \`pip install <pkg> && python script.py\` for data tasks
- Use \`browser\` to navigate websites, fill forms, click buttons
- Use \`web_fetch\` to grab page content as text
- Use \`write\` to save results to files in the workspace
`);

  const agentDir = path.join(OC_HOME, 'agents', ocAgentId, 'agent');
  fs.mkdirSync(agentDir, { recursive: true });

  const authProfiles = { profiles: {} };
  if (process.env.OPENAI_API_KEY) {
    authProfiles.profiles['openai:default'] = {
      provider: 'openai',
      type: 'api_key',
      key: process.env.OPENAI_API_KEY,
    };
  }
  if (process.env.ANTHROPIC_API_KEY) {
    authProfiles.profiles['anthropic:default'] = {
      provider: 'anthropic',
      type: 'api_key',
      key: process.env.ANTHROPIC_API_KEY,
    };
  }
  fs.writeFileSync(
    path.join(agentDir, 'auth-profiles.json'),
    JSON.stringify(authProfiles, null, 2),
  );

  const config = readConfig();
  config.agents = config.agents || { defaults: {}, list: [] };
  config.agents.list = config.agents.list || [];
  config.agents.list = config.agents.list.filter(a => a.id !== ocAgentId);
  config.agents.list.push({
    id: ocAgentId,
    name,
    workspace: gatewayWorkspace,
    model: mapModel(model),
    tools: {
      profile: 'coding',
      allow: [
        'exec', 'read', 'write', 'edit', 'apply_patch',
        'web_search', 'web_fetch', 'browser',
        'sessions_list', 'sessions_history', 'session_status',
      ],
    },
    sandbox: { mode: 'off' },
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

// ── Skill installation ──────────────────────────────
// Creates a SKILL.md in the agent's workspace so the OpenClaw gateway
// can discover and load it during chat completions.

function installSkill(userId, agentId, skillId) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const skillDir = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills', skillId);
  fs.mkdirSync(skillDir, { recursive: true });

  const content = SKILL_CONTENT[skillId];
  if (content) {
    fs.writeFileSync(path.join(skillDir, 'SKILL.md'), content);
  }

  // Also try symlinking from bundled skills for any extra resources
  const bundledSrc = path.join(OC_HOME, 'skills', skillId);
  if (fs.existsSync(bundledSrc)) {
    try {
      const entries = fs.readdirSync(bundledSrc);
      for (const entry of entries) {
        if (entry === 'SKILL.md') continue; // we wrote our own
        const src = path.join(bundledSrc, entry);
        const dest = path.join(skillDir, entry);
        if (!fs.existsSync(dest)) {
          fs.symlinkSync(src, dest);
        }
      }
    } catch {
      // Non-fatal — bundled extras are optional
    }
  }
}

function installStarterSkills(userId, agentId) {
  for (const skillId of STARTER_SKILLS) {
    installSkill(userId, agentId, skillId);
  }
}

function uninstallSkill(userId, agentId, skillId) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const dest = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills', skillId);

  try {
    const stat = fs.lstatSync(dest);
    if (stat.isSymbolicLink() || stat.isDirectory()) {
      fs.rmSync(dest, { recursive: true, force: true });
    }
  } catch {
    // Already gone or never existed
  }
}

// ── Skill enable/disable ────────────────────────────
// Disabling renames the SKILL.md so OpenClaw skips it; enabling restores it.

function setSkillEnabled(userId, agentId, skillId, enabled) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const skillDir = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills', skillId);
  const active = path.join(skillDir, 'SKILL.md');
  const inactive = path.join(skillDir, 'SKILL.md.disabled');

  try {
    if (enabled && fs.existsSync(inactive)) {
      fs.renameSync(inactive, active);
    } else if (!enabled && fs.existsSync(active)) {
      fs.renameSync(active, inactive);
    }
  } catch {
    // Non-fatal
  }
}

// ── Skill configuration ─────────────────────────────
// Stores per-agent skill config as a JSON file next to SKILL.md.

function getSkillConfig(userId, agentId, skillId) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const configPath = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills', skillId, 'config.json');
  try {
    return JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch {
    return {};
  }
}

function setSkillConfig(userId, agentId, skillId, config) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const configPath = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills', skillId, 'config.json');
  try {
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  } catch {
    // Non-fatal
  }
}

// ── Category-specific instruction templates ─────────
// Used to generate actionable SKILL.md stubs when the ClawHub CLI fails.
// Each template is keyed by the catalog category and provides the agent with
// concrete guidance on when/how to use the skill.

const CATEGORY_INSTRUCTIONS = {
  Development: `## When to use
- The user asks for help with code, debugging, or development tooling
- The user wants to run, test, or analyze code
- The user needs to interact with development services (Git, CI, linters, etc.)

## Instructions
1. Clarify the programming language, framework, or tool involved
2. Use available tools (exec, file read/write) to perform the requested task
3. Show your work: include relevant code, command output, or diffs
4. Explain trade-offs or alternatives when applicable
5. Validate results — run tests or verify output before presenting

## Output format
- Use fenced code blocks with the appropriate language tag
- Include file paths when referencing or modifying files
- Summarize what was done and any follow-up actions needed`,

  Automation: `## When to use
- The user asks you to generate, create, or process something automatically
- The user wants to integrate with an external API or service
- The user needs a repetitive task handled programmatically

## Instructions
1. Understand exactly what the user wants to automate
2. Use available tools (web/fetch, exec, file I/O) to call the relevant APIs or run commands
3. If API keys or credentials are needed and not available, tell the user what to configure
4. Handle errors gracefully — retry on transient failures, report clear messages on permanent ones
5. Return results in the most useful format (URL, file, structured data)

## Output format
- Present results directly (e.g., URLs, generated content, data)
- If a file or artifact was created, provide the path or download link
- Include a brief summary of what was done`,

  Research: `## When to use
- The user asks to find, search, or look up information from a specific domain
- The user wants summaries of academic papers, articles, or technical docs
- The user needs in-depth analysis of a topic with sources

## Instructions
1. Identify key search terms, topics, or identifiers (DOIs, URLs, keywords)
2. Use available search/fetch tools to retrieve relevant sources
3. Read and analyze the content, extracting key findings
4. Synthesize into a clear, well-structured summary
5. Always cite sources with titles and URLs

## Output format
- Start with a brief overview (1-2 sentences)
- Key findings as bullet points or numbered lists
- Include relevant quotes or data points
- End with source URLs and references
- Note any gaps or limitations in the research`,

  Data: `## When to use
- The user provides data to analyze, parse, or transform
- The user asks about databases, queries, or data processing
- The user needs statistics, trends, or insights from structured data

## Instructions
1. Understand the data format and structure (CSV, JSON, SQL, etc.)
2. Parse and clean the data as needed
3. Perform the requested analysis, query, or transformation
4. Present findings with supporting numbers and context
5. Suggest follow-up analyses when relevant

## Output format
- Data overview: rows, columns, types, completeness
- Key statistics or query results in tables
- Trends and patterns in plain language
- Actionable recommendations based on the data`,

  Communication: `## When to use
- The user wants to send, draft, or manage messages on a platform
- The user needs to summarize conversations, threads, or channels
- The user asks for help composing posts, replies, or notifications

## Instructions
1. Ask for context if not provided: platform, audience, tone, key points
2. Match the requested tone and format for the target platform
3. Keep messages concise and appropriate for the channel
4. For summaries, extract action items, decisions, and key points
5. Respect platform-specific conventions (character limits, threading, etc.)

## Output format
- Present drafts clearly with platform context
- For summaries: action items, decisions, mentions, and follow-ups
- Offer alternatives or variations when relevant`,

  Productivity: `## When to use
- The user wants to read, write, or sync content with a productivity tool
- The user needs to organize, track, or manage information
- The user asks for help with notes, documents, or knowledge bases

## Instructions
1. Clarify which tool or service is involved and what action is needed
2. Use available APIs/tools to read from or write to the service
3. Preserve formatting and structure when moving content between systems
4. Confirm changes before making destructive operations (delete, overwrite)
5. Report what was synced, created, or updated

## Output format
- Summarize changes made (created, updated, deleted items)
- Show the content that was written or synced
- Note any conflicts or items that need manual attention`,

  Writing: `## When to use
- The user asks to create, edit, or polish written content
- The user needs help with documentation, READMEs, or technical writing
- The user wants formatting, structure, or style suggestions

## Instructions
1. Understand the audience, purpose, and desired tone
2. Create well-structured content with clear headings and sections
3. Use proper formatting for the target format (Markdown, plain text, etc.)
4. Be concise — remove filler, prefer active voice, use concrete language
5. Offer revision options if the user wants a different tone or angle

## Output format
- Present the full document or section ready to use
- Use the target format (Markdown, etc.) with proper structure
- Highlight any sections that need the user's input (e.g., [YOUR NAME])
- Offer brief notes on style choices if helpful`,
};

// ── ClawHub skill install ───────────────────────────
// Downloads the real skill from the ClawHub registry using the clawhub CLI,
// then parses the SKILL.md to extract metadata and setup requirements.
// `catalogEntry` (optional) carries name/description/category from the catalog
// and is used to generate a useful SKILL.md when the CLI is unavailable.

function installClawHubSkill(userId, agentId, slug, catalogEntry) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const workspaceSkills = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills');
  fs.mkdirSync(workspaceSkills, { recursive: true });

  const displayName = catalogEntry?.name
    || slug.split('/').pop().replace(/-/g, ' ').replace(/\b\w/g, c => c.toUpperCase());

  // Try to install via the clawhub CLI (downloads real SKILL.md + scripts)
  let cliInstalled = false;
  try {
    execSync(`npx --yes clawhub@latest install ${slug}`, {
      cwd: workspaceSkills,
      timeout: 30_000,
      stdio: 'pipe',
      env: { ...process.env, HOME: OC_HOME },
    });
    cliInstalled = true;
    console.log(`[clawhub] installed ${slug} via CLI`);
  } catch (err) {
    console.warn(`[clawhub] CLI install failed for ${slug}: ${err.message}`);
  }

  // Determine the actual skill directory — always use the slug's last segment
  const slugName = slug.split('/').pop();
  let skillId = slugName;
  let skillDir = path.join(workspaceSkills, slugName);

  if (!fs.existsSync(skillDir)) {
    fs.mkdirSync(skillDir, { recursive: true });
    cliInstalled = false;
  }

  // If CLI failed, generate a category-aware SKILL.md from catalog metadata
  if (!cliInstalled) {
    const description = catalogEntry?.description
      || `Community skill: ${displayName}`;
    const category = catalogEntry?.category || 'Automation';
    const instructions = CATEGORY_INSTRUCTIONS[category]
      || CATEGORY_INSTRUCTIONS.Automation;

    const content = `---
name: ${slugName}
description: "${description}"
---

# ${displayName}

${description}

${instructions}
`;
    fs.writeFileSync(path.join(skillDir, 'SKILL.md'), content);
  }

  // Parse SKILL.md to extract metadata and detect setup requirements
  const meta = parseSkillMd(path.join(skillDir, 'SKILL.md'));
  const setupReqs = detectSetupRequirements(skillDir, meta);
  const installCommands = extractInstallCommands(skillDir);

  return {
    skillId,
    name: meta.name || displayName,
    description: meta.description || `Community skill: ${displayName}`,
    icon: catalogEntry?.icon || 'puzzlepiece.extension.fill',
    version: meta.version || catalogEntry?.version || '1.0.0',
    source: 'clawhub',
    setup_required: setupReqs.length > 0 || installCommands.length > 0,
    setup_requirements: setupReqs,
    install_commands: installCommands,
  };
}

// ── SKILL.md metadata parsing ───────────────────────

function parseSkillMd(skillMdPath) {
  try {
    const raw = fs.readFileSync(skillMdPath, 'utf8');
    const fmMatch = raw.match(/^---\s*\n([\s\S]*?)\n---/);
    if (!fmMatch) return {};

    const frontmatter = fmMatch[1];
    const meta = {};
    for (const line of frontmatter.split('\n')) {
      const m = line.match(/^(\w[\w-]*):\s*(.+)$/);
      if (m) meta[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
    return meta;
  } catch {
    return {};
  }
}

// ── Setup requirements detection ────────────────────
// Scans the SKILL.md and directory for env vars, CLI tools, and auth needs.

function detectSetupRequirements(skillDir, meta) {
  const reqs = [];

  try {
    const skillMd = fs.readFileSync(path.join(skillDir, 'SKILL.md'), 'utf8');

    // Detect env var requirements from SKILL.md frontmatter or body
    const envMatches = skillMd.matchAll(/\b([A-Z][A-Z0-9_]{3,})\b/g);
    const envVars = new Set();
    for (const m of envMatches) {
      const v = m[1];
      // Filter common false positives
      if (['SKILL', 'README', 'TODO', 'NOTE', 'IMPORTANT', 'WARNING', 'EXAMPLE',
           'HTTP', 'HTTPS', 'JSON', 'YAML', 'HTML', 'CSS', 'UTF'].includes(v)) continue;
      if (v.endsWith('_KEY') || v.endsWith('_TOKEN') || v.endsWith('_SECRET') ||
          v.endsWith('_URL') || v.endsWith('_ID') || v.endsWith('_API')) {
        envVars.add(v);
      }
    }
    for (const env of envVars) {
      reqs.push({
        type: 'env',
        key: env,
        label: env.replace(/_/g, ' ').toLowerCase().replace(/\b\w/g, c => c.toUpperCase()),
        description: `Required environment variable: ${env}`,
        sensitive: env.includes('KEY') || env.includes('TOKEN') || env.includes('SECRET'),
      });
    }

    // Detect auth/OAuth requirements
    if (/oauth|client.?secret|authorization|auth\s+add/i.test(skillMd)) {
      reqs.push({
        type: 'auth',
        key: 'oauth_setup',
        label: 'OAuth Authorization',
        description: 'This skill requires OAuth setup with an external service.',
        sensitive: false,
      });
    }

    // Detect CLI tool requirements from frontmatter
    if (meta.requires) {
      for (const bin of meta.requires.split(',').map(s => s.trim())) {
        reqs.push({
          type: 'bin',
          key: bin,
          label: `${bin} CLI`,
          description: `Requires the "${bin}" command-line tool to be installed.`,
          sensitive: false,
        });
      }
    }
  } catch {
    // Non-fatal
  }

  return reqs;
}

// ── Skill credentials injection ─────────────────────
// Writes user-provided credentials as env vars into the agent's config
// so the OpenClaw gateway passes them during task execution.

function setSkillCredentials(userId, agentId, skillId, credentials) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const credPath = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills', skillId, '.env.json');
  fs.writeFileSync(credPath, JSON.stringify(credentials, null, 2));

  // Also inject into the agent-level environment in openclaw.json
  const config = readConfig();
  const agentEntry = config.agents?.list?.find(a => a.id === ocAgentId);
  if (agentEntry) {
    agentEntry.env = agentEntry.env || {};
    for (const [key, value] of Object.entries(credentials)) {
      agentEntry.env[key] = value;
    }
    writeConfig(config);
  }
}

// ── Extract install commands from SKILL.md ──────────
// Scans the skill's SKILL.md for CLI install commands the agent needs to run.

function extractInstallCommands(skillDir) {
  const commands = [];
  try {
    const raw = fs.readFileSync(path.join(skillDir, 'SKILL.md'), 'utf8');

    const patterns = [
      /(?:^|\n)\s*(?:```[^\n]*\n)?((?:npm|npx)\s+(?:i(?:nstall)?|--yes)\s+\S[^\n]*)/gm,
      /(?:^|\n)\s*(?:```[^\n]*\n)?(brew\s+install\s+\S[^\n]*)/gm,
      /(?:^|\n)\s*(?:```[^\n]*\n)?(pip3?\s+install\s+\S[^\n]*)/gm,
      /(?:^|\n)\s*(?:```[^\n]*\n)?(cargo\s+install\s+\S[^\n]*)/gm,
      /(?:^|\n)\s*(?:```[^\n]*\n)?(apt-get\s+install\s+\S[^\n]*)/gm,
      /(?:^|\n)\s*(?:```[^\n]*\n)?(go\s+install\s+\S[^\n]*)/gm,
    ];

    for (const pattern of patterns) {
      for (const m of raw.matchAll(pattern)) {
        const cmd = m[1].trim().replace(/```$/, '').trim();
        if (cmd && !commands.includes(cmd)) commands.push(cmd);
      }
    }
  } catch {
    // Non-fatal
  }
  return commands;
}

// ── Installed skill listing ─────────────────────────

function getInstalledSkillIds(userId, agentId) {
  const ocAgentId = openclawAgentId(userId, agentId);
  const skillsDir = path.join(OC_HOME, 'workspaces', ocAgentId, 'skills');
  try {
    return fs.readdirSync(skillsDir).filter(name => {
      const skillDir = path.join(skillsDir, name);
      return fs.statSync(skillDir).isDirectory() || fs.lstatSync(skillDir).isSymbolicLink();
    });
  } catch {
    return [];
  }
}

module.exports = {
  ensureBaseConfig,
  provisionAgent,
  deprovisionAgent,
  installSkill,
  uninstallSkill,
  installStarterSkills,
  setSkillEnabled,
  getSkillConfig,
  setSkillConfig,
  installClawHubSkill,
  setSkillCredentials,
  getInstalledSkillIds,
  extractInstallCommands,
  openclawAgentId,
  mapModel,
  STARTER_SKILLS,
  SKILL_CONTENT,
  PERSONA_RECOMMENDATIONS,
  VALID_MODELS: Object.keys(MODEL_MAP),
};
