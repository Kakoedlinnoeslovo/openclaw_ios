# OpenClaw iOS

A native iOS app that puts self-hosted AI agents in your pocket. Built with SwiftUI, backed by a Dockerized [OpenClaw](https://github.com/AizelNetwork/openclaw) gateway that gives each user isolated agents, skills, and streaming task execution.

## Architecture

```
┌──────────────────────┐        HTTPS / WSS        ┌──────────────────────────┐
│    iOS App (SwiftUI) │ ◄────────────────────────► │  API Gateway (Express)   │
│                      │                            │  :3000                   │
│  • Onboarding        │                            ├──────────────────────────┤
│  • Agent management  │                            │  BullMQ Worker           │
│  • Skill browser     │                            │  (task processor)        │
│  • Chat-style tasks  │                            ├──────────────────────────┤
│  • Paywall (StoreKit)│                            │  OpenClaw Gateway        │
└──────────────────────┘                            │  :18789 (internal)       │
                                                    ├──────────────────────────┤
                                                    │  PostgreSQL 16 + Redis 7 │
                                                    └──────────────────────────┘
```

**How it works:** The iOS app talks to the API Gateway over REST + WebSocket. When a user submits a task, it's queued via BullMQ, picked up by the worker, and sent to the OpenClaw gateway's OpenAI-compatible chat completions API. Responses stream back to the phone in real time via Redis pub/sub and a WebSocket relay.

Each user gets an isolated OpenClaw agent with its own workspace, persona files (`AGENTS.md`, `SOUL.md`), and auth credentials. Starter skills are auto-installed on agent creation.

## Prerequisites

- **macOS / Linux** host
- **Docker Desktop** (or Docker Engine + Docker Compose v2)
- **Xcode 15+** (for the iOS app)
- At least one LLM API key (OpenAI or Anthropic)

## Quick Start

### 1. Start the backend

```bash
cd backend

# First time: generates secrets, builds images, starts everything
./setup.sh
```

Or manually:

```bash
cd backend
cp .env.example .env
# Edit .env — add your API keys
docker compose up -d
```

### 2. Add your LLM API key

Edit `backend/.env` and set at least one:

```
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

Then restart the services:

```bash
cd backend && docker compose up -d
```

### 3. Verify the backend

```bash
# Health check
curl http://localhost:3000/health
# → {"status":"ok","services":{"database":"healthy","openclaw_gateway":"healthy"}}

# Register a test user
curl -X POST http://localhost:3000/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"test1234","display_name":"Test"}'
```

### 4. Run the iOS app

Open `OpenClaw.xcodeproj` in Xcode, select a simulator, and run. The app connects to `http://localhost:3000` in debug mode.

## Project Structure

```
.
├── OpenClaw/                       # iOS app (SwiftUI + Swift 6)
│   ├── App/                        #   App entry point, ContentView
│   ├── Models/                     #   Agent, Skill, TaskItem, User, Subscription
│   ├── Services/                   #   APIClient, AuthService, AgentService, etc.
│   ├── Views/                      #   Onboarding, Home, Skills, Tasks, Paywall
│   └── Utilities/                  #   Constants, Keychain
│
├── backend/                        # Dockerized backend
│   ├── docker-compose.yml          #   7 services (caddy, api-gateway, worker,
│   │                               #   openclaw-gateway, config-init, postgres, redis)
│   ├── setup.sh                    #   One-command deployment
│   ├── .env.example                #   Configuration template
│   ├── Caddyfile                   #   Reverse proxy (auto-TLS in production)
│   ├── api-gateway/                #   Express.js API server
│   │   └── src/
│   │       ├── index.js            #     REST API + WebSocket relay
│   │       ├── openclaw-client.js  #     Bridge to OpenClaw HTTP API
│   │       ├── provisioner.js      #     Per-user agent workspace provisioning
│   │       ├── worker.js           #     BullMQ task processor
│   │       └── ws-relay.js         #     WebSocket relay for iOS streaming
│   ├── db/
│   │   └── init.sql                #   PostgreSQL schema (users, agents, tasks, etc.)
│   ├── openclaw/                   #   OpenClaw upstream (built locally)
│   └── openclaw-config/
│       └── openclaw.json           #   Base gateway configuration
│
└── ARCHITECTURE.md                 # Full product & architecture spec
```

## Backend Services


| Service              | Port             | Purpose                                       |
| -------------------- | ---------------- | --------------------------------------------- |
| **caddy**            | 80, 443          | Reverse proxy, automatic TLS (production)     |
| **api-gateway**      | 3000             | REST API + WebSocket relay for iOS            |
| **worker**           | —                | BullMQ task processor, calls OpenClaw         |
| **openclaw-gateway** | 18789 (internal) | OpenClaw AI engine, chat completions          |
| **postgres**         | 5432 (internal)  | Users, agents, tasks, subscriptions           |
| **redis**            | 6379 (internal)  | Job queue, pub/sub, session cache             |
| **config-init**      | —                | One-shot: seeds `openclaw.json` on first boot |


## API Endpoints

### Auth


| Method | Path             | Description                       |
| ------ | ---------------- | --------------------------------- |
| POST   | `/auth/register` | Create account (email + password) |
| POST   | `/auth/login`    | Sign in, get JWT tokens           |
| POST   | `/auth/apple`    | Sign in with Apple                |
| POST   | `/auth/refresh`  | Refresh access token              |


### Agents


| Method | Path          | Description                                                   |
| ------ | ------------- | ------------------------------------------------------------- |
| GET    | `/agents`     | List user's agents                                            |
| POST   | `/agents`     | Create agent (provisions OpenClaw workspace + starter skills) |
| PATCH  | `/agents/:id` | Update agent name/persona/model                               |
| DELETE | `/agents/:id` | Delete agent and deprovision                                  |


### Skills


| Method | Path                          | Description                                       |
| ------ | ----------------------------- | ------------------------------------------------- |
| GET    | `/skills/catalog`             | Browse curated skills (filter by category/search) |
| POST   | `/agents/:id/skills`          | Install skill to agent                            |
| DELETE | `/agents/:id/skills/:skillId` | Remove skill                                      |


### Tasks


| Method | Path                        | Description                     |
| ------ | --------------------------- | ------------------------------- |
| POST   | `/agents/:id/tasks`         | Submit task (queued via BullMQ) |
| GET    | `/agents/:id/tasks`         | List task history               |
| GET    | `/agents/:id/tasks/:taskId` | Get task result                 |


### WebSocket


| Path                                          | Description              |
| --------------------------------------------- | ------------------------ |
| `ws://host:3000/ws/agents/:agentId?token=JWT` | Real-time task streaming |


Events: `task:progress`, `task:complete`, `task:error`

### Other


| Method | Path                   | Description                         |
| ------ | ---------------------- | ----------------------------------- |
| GET    | `/health`              | Service health check                |
| GET    | `/usage`               | Usage stats (tasks, tokens, limits) |
| GET    | `/subscription`        | Current subscription tier           |
| POST   | `/subscription/verify` | Verify App Store receipt            |


## Subscription Tiers


| Feature     | Free        | Pro ($9.99/mo) |
| ----------- | ----------- | -------------- |
| Agents      | 1           | 5              |
| Daily tasks | 10          | 100            |
| Skills      | 7 curated   | All            |
| AI model    | GPT-4o Mini | GPT-4o, Claude |
| Tokens/day  | 50K         | 500K           |


## Common Operations

```bash
# View logs
docker compose -f backend/docker-compose.yml logs -f

# Restart after .env changes
cd backend && docker compose up -d

# Reset database (deletes all data)
cd backend && docker compose down
docker volume rm backend_postgres_data
docker compose up -d

# Reset OpenClaw config + workspaces
cd backend && docker compose down
docker volume rm backend_openclaw_home
docker compose up -d

# Shell into the OpenClaw gateway
cd backend && docker compose exec openclaw-gateway sh
```

## Production Deployment

1. Set `DOMAIN` in `.env` and update the `Caddyfile`:
  ```
   api.your-domain.com {
       reverse_proxy api-gateway:3000
   }
  ```
2. Update `OpenClaw/Utilities/Constants.swift`:
  ```swift
   static let apiBaseURL = "https://api.your-domain.com"
   static let wsBaseURL = "wss://api.your-domain.com/ws"
  ```
3. Generate strong secrets:
  ```bash
   openssl rand -hex 32  # for JWT_SECRET
   openssl rand -hex 32  # for OPENCLAW_GATEWAY_TOKEN
   openssl rand -hex 16  # for DB_PASSWORD
  ```
4. Deploy to a VPS (recommended: Hetzner CPX41 or DigitalOcean 8GB, ~$40-80/mo).

## Tech Stack


| Layer         | Technology                   |
| ------------- | ---------------------------- |
| iOS App       | SwiftUI, Swift 6, StoreKit 2 |
| Networking    | URLSession + async/await     |
| Backend API   | Express.js (Node.js 22)      |
| Task Queue    | BullMQ + Redis 7             |
| Database      | PostgreSQL 16 (RLS)          |
| AI Engine     | OpenClaw (self-hosted)       |
| Reverse Proxy | Caddy (auto-TLS)             |
| Containers    | Docker Compose               |


## License

Private. See ARCHITECTURE.md for the full product specification.