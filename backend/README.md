# OpenClaw iOS Backend

Multi-user backend for the OpenClaw iOS app. Wraps a real OpenClaw gateway with user auth, agent provisioning, skill management, task queuing, and real-time WebSocket streaming.

## Architecture

```
iOS App
  │
  ▼
┌─────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Caddy      │────▶│  API Gateway     │────▶│  OpenClaw Gateway│
│  :80 / :443  │     │  (Express :3000) │     │  (internal :18789)
└─────────────┘     └──────┬───────────┘     └──────────────────┘
                           │                    Real LLM engine:
                    ┌──────┴───────┐            exec, browser,
                    │              │            web_search, files
                 ┌──▼──┐     ┌────▼───┐
                 │Redis│     │Postgres│
                 │:6379│     │ :5432  │
                 └──┬──┘     └────────┘
                    │
               ┌────▼────┐
               │  Worker  │
               │ (BullMQ) │
               └──────────┘
```

### Services


| Service              | Role                                                                                  |
| -------------------- | ------------------------------------------------------------------------------------- |
| **caddy**            | Reverse proxy (HTTP/HTTPS)                                                            |
| **api-gateway**      | Express REST API — auth, agents, skills, tasks                                        |
| **worker**           | BullMQ consumer — runs tasks via OpenClaw streaming chat completions                  |
| **openclaw-gateway** | Real OpenClaw engine — LLM + tools (exec, browser, web_search, web_fetch, read/write) |
| **onboard**          | One-shot init — runs `openclaw onboard` to set up auth profiles and model config      |
| **config-init**      | Seeds `openclaw.json` on first boot                                                   |
| **postgres**         | User data, agents, skills, tasks, subscriptions                                       |
| **redis**            | BullMQ task queue + pub/sub for real-time WebSocket events                            |


## Quick Start

### Prerequisites

- Docker & Docker Compose
- An OpenAI API key (or Anthropic)

### 1. Setup

```bash
./setup.sh
```

This will:

- Generate `.env` with random secrets (if not present)
- Build all Docker images (first build takes a few minutes for the OpenClaw gateway)
- Start all services
- Run automatic onboarding

### 2. Add your API key

Edit `.env` and set your LLM provider key:

```bash
OPENAI_API_KEY=sk-proj-...
# or
ANTHROPIC_API_KEY=sk-ant-...
```

Then restart:

```bash
docker compose up -d
```

### 3. Verify

```bash
curl http://localhost:3000/health
# → {"status":"ok","services":{"database":"healthy","openclaw_gateway":"healthy"}}
```

## Startup Order

```
config-init ──▶ openclaw-gateway (healthy) ──▶ onboard ──▶ api-gateway + worker
                postgres (healthy) ──────────────────────▶ ↗
                redis (healthy) ────────────────────────▶ ↗
```

The `onboard` service runs `openclaw onboard --non-interactive` once to set up gateway-level auth profiles and model configuration. On subsequent restarts it detects the `"wizard"` key in the config and skips instantly.

## API Reference

### Auth


| Method | Endpoint         | Description                  |
| ------ | ---------------- | ---------------------------- |
| POST   | `/auth/register` | Register with email/password |
| POST   | `/auth/login`    | Login, get JWT tokens        |
| POST   | `/auth/apple`    | Sign in with Apple           |
| POST   | `/auth/refresh`  | Refresh access token         |


**Register / Login request:**

```json
curl -X POST http://localhost/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "secret",
    "display_name": "User Name"
  }'

curl -X POST http://localhost/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "user@example.com",
    "password": "secret"
  }'

```

**Response:**

```json
{
  "user": { "id": "uuid", "email": "...", "display_name": "...", "tier": "free" },
  "tokens": { "access_token": "jwt...", "refresh_token": "uuid", "expires_in": 3600 }
}
```

All endpoints below require `Authorization: Bearer <access_token>`.

### Agents


| Method | Endpoint      | Description                                                          |
| ------ | ------------- | -------------------------------------------------------------------- |
| GET    | `/agents`     | List user's agents                                                   |
| POST   | `/agents`     | Create agent (auto-provisions in OpenClaw + installs starter skills) |
| PATCH  | `/agents/:id` | Update agent name/persona/model                                      |
| DELETE | `/agents/:id` | Delete agent                                                         |


**Create agent:**

```json
curl -X POST http://localhost/agents \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{ "name": "My Assistant", "persona": "Professional", "model": "gpt-5.2" }'
```





Available personas: `Professional`, `Friendly`, `Technical`, `Creative`

Available models: `gpt-5.2` (default), `gpt-5.4`, `gpt-5-mini`, `gpt-4o`, `gpt-4o-mini`, `claude-sonnet`

### Tasks


| Method | Endpoint                         | Description                       |
| ------ | -------------------------------- | --------------------------------- |
| POST   | `/agents/:agentId/tasks`         | Submit a task (queued via BullMQ) |
| GET    | `/agents/:agentId/tasks`         | List task history                 |
| GET    | `/agents/:agentId/tasks/:taskId` | Get task result                   |


**Submit task:**

```json
{ "input": "What's the weather in London?" }
```

**Response:**

```json
{ "task_id": "uuid", "status": "queued" }
```

**Task result (after completion):**

```json
{
  "id": "uuid",
  "status": "completed",
  "input": "What's the weather in London?",
  "output": "London right now: 8°C, partly cloudy.",
  "tokens_used": 42
}
```

### Real-Time Streaming (WebSocket)

Connect to get live task progress:

```
ws://localhost:3000/ws/agents/:agentId?token=<jwt>
```

**Events received:**


| Event             | Description                                      |
| ----------------- | ------------------------------------------------ |
| `connected`       | WebSocket established                            |
| `task:progress`   | Streaming text chunk (token by token)            |
| `task:tool_start` | Agent started using a tool (exec, browser, etc.) |
| `task:tool_end`   | Tool call finished                               |
| `task:complete`   | Task finished, full output available             |
| `task:error`      | Task failed                                      |


### Skills


| Method | Endpoint                           | Description                       |
| ------ | ---------------------------------- | --------------------------------- |
| GET    | `/skills/catalog`                  | Browse curated skill catalog      |
| GET    | `/skills/recommended`              | Persona-based recommendations     |
| GET    | `/skills/clawhub/browse`           | Browse ClawHub community skills   |
| GET    | `/agents/:agentId/skills`          | List installed skills             |
| POST   | `/agents/:agentId/skills`          | Install curated skill             |
| POST   | `/agents/:agentId/skills/clawhub`  | Install ClawHub skill             |
| PATCH  | `/agents/:agentId/skills/:skillId` | Enable/disable or configure skill |
| DELETE | `/agents/:agentId/skills/:skillId` | Uninstall skill                   |


### Subscription & Usage


| Method | Endpoint               | Description                   |
| ------ | ---------------------- | ----------------------------- |
| GET    | `/subscription`        | Get current subscription tier |
| POST   | `/subscription/verify` | Verify App Store receipt      |
| GET    | `/usage`               | Get daily usage stats         |


## Testing from CLI

A test script is included for real-time streaming from the terminal:

```bash
# Auto-picks first agent, default prompt
node test-realtime.js

# Custom prompt
node test-realtime.js "" "What's the weather in London?"

# Specific agent + prompt
node test-realtime.js <agent-uuid> "Find 3 Italian restaurants near Canary Wharf"
```

The script logs in as `test@example.com`, connects the WebSocket, submits a task, and streams the response live.

## Agent Capabilities

Each agent runs inside the OpenClaw gateway with real tools:


| Tool                    | What it does                                                  |
| ----------------------- | ------------------------------------------------------------- |
| **exec**                | Run any shell command — curl, python, node, pip install, etc. |
| **read / write / edit** | File operations in the agent's workspace                      |
| **web_search**          | Search the web (requires `BRAVE_API_KEY`)                     |
| **web_fetch**           | Fetch and read any URL                                        |
| **browser**             | Headless Chrome — navigate, click, fill forms, screenshot     |


The default model is **GPT-5.2** which proactively uses tools without needing explicit instructions.

## Environment Variables


| Variable                 | Required | Description                                      |
| ------------------------ | -------- | ------------------------------------------------ |
| `DB_PASSWORD`            | Yes      | PostgreSQL password (auto-generated by setup.sh) |
| `JWT_SECRET`             | Yes      | JWT signing secret (auto-generated)              |
| `OPENCLAW_GATEWAY_TOKEN` | Yes      | Token for API↔Gateway auth (auto-generated)      |
| `OPENAI_API_KEY`         | Yes*     | OpenAI API key                                   |
| `ANTHROPIC_API_KEY`      | No       | Anthropic API key (alternative to OpenAI)        |
| `BRAVE_API_KEY`          | No       | Enables web_search tool                          |


 At least one LLM provider key is required.

## Common Operations

```bash
# Start everything
docker compose up -d

# Rebuild after code changes
docker compose up --build -d

# View logs
docker compose logs -f                    # all services
docker compose logs -f worker             # just the worker
docker compose logs -f openclaw-gateway   # just the gateway

# Check service health
docker compose ps

# Stop everything
docker compose down

# Full reset (wipes all data)
docker compose down -v

# Clean up stuck tasks
docker compose exec postgres psql -U openclaw \
  -c "UPDATE tasks SET status='failed', output='Cancelled', completed_at=NOW() WHERE status IN ('queued','running');"
docker compose restart worker
```

## Project Structure

```
backend/
├── api-gateway/
│   └── src/
│       ├── index.js          # Express API — auth, agents, skills, tasks
│       ├── worker.js         # BullMQ task worker — streams OpenClaw completions
│       ├── provisioner.js    # Agent/skill provisioning into OpenClaw gateway
│       ├── openclaw-client.js # OpenClaw chat completions client (streaming + sync)
│       └── ws-relay.js       # WebSocket relay — Redis pub/sub → iOS clients
├── db/
│   └── init.sql              # PostgreSQL schema
├── openclaw/                 # OpenClaw gateway (git submodule)
├── openclaw-config/
│   └── openclaw.json         # Seed config for the gateway
├── docker-compose.yml
├── Caddyfile
├── setup.sh
├── test-realtime.js          # CLI test script for real-time streaming
└── .env                      # Secrets (not committed)
```

