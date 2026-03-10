# OpenClaw iOS — Architecture & Product Specification

## 1. System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS App (SwiftUI)                        │
│  ┌───────────┐ ┌──────────┐ ┌──────────┐ ┌───────────────────┐ │
│  │ Onboarding│ │  Agents  │ │  Skills  │ │  Task Execution   │ │
│  └─────┬─────┘ └────┬─────┘ └────┬─────┘ └────────┬──────────┘ │
│        └─────────────┴────────────┴────────────────┘            │
│                          │ HTTPS / WSS                          │
└──────────────────────────┼──────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                     API Gateway (Express)                        │
│  ┌──────────┐ ┌────────────┐ ┌───────────┐ ┌────────────────┐  │
│  │ Auth/JWT │ │ Rate Limit │ │ Billing   │ │ Usage Metering │  │
│  └────┬─────┘ └─────┬──────┘ └─────┬─────┘ └───────┬────────┘  │
│       └──────────────┴──────────────┴───────────────┘           │
│                          │                                       │
│  ┌───────────────────────┴───────────────────────────────────┐  │
│  │              Tenant Router / Session Manager              │  │
│  └───────────────────────┬───────────────────────────────────┘  │
└──────────────────────────┼──────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌──────────────────────┐  ┌──────────────────────────┐
│  OpenClaw Gateway    │  │   PostgreSQL + Redis     │
│  (Node.js :18789)    │  │                          │
│  ┌────────────────┐  │  │  • Users & subscriptions │
│  │ Agent Runtime  │  │  │  • Agent configs         │
│  │ (per-tenant)   │  │  │  • Usage logs            │
│  ├────────────────┤  │  │  • Session cache (Redis) │
│  │ Skill Manager  │  │  └──────────────────────────┘
│  ├────────────────┤  │
│  │ Memory Store   │  │
│  ├────────────────┤  │
│  │ LLM Providers  │  │
│  └────────────────┘  │
└──────────────────────┘
```

---

## 2. Cloud Infrastructure Layout

### Deployment Target: Single VPS (MVP) → Kubernetes (V2)

**MVP (Month 1–3)**
- Single VPS (Hetzner CPX41 or DigitalOcean Premium 8GB)
- Docker Compose orchestration
- Caddy reverse proxy with automatic TLS
- PostgreSQL 16 + Redis 7 in containers
- OpenClaw Gateway in container
- API Gateway (Express) in container
- Cost: ~$40–80/month

**V2 (Month 4+)**
- Kubernetes (k3s or managed K8s)
- Horizontal pod autoscaling for API Gateway
- Per-user OpenClaw agent isolation via namespaces
- Object storage (S3/R2) for skill artifacts
- CDN for static assets

### Container Architecture (MVP)

```
docker-compose.yml
├── caddy              (reverse proxy, TLS termination)
├── config-init        (one-shot: seeds openclaw.json)
├── onboard            (one-shot: runs openclaw onboard)
├── api-gateway        (Express app, port 3000)
├── worker             (BullMQ job processor)
├── openclaw-gateway   (OpenClaw engine, port 18789)
├── postgres           (database, port 5432)
└── redis              (cache/queue, port 6379)
```

---

## 3. Multi-User OpenClaw Deployment

OpenClaw natively supports multiple agents on a single Gateway via workspace
isolation. For a consumer app:

### Isolation Model

| Layer           | Strategy                                         |
|-----------------|--------------------------------------------------|
| Agent Config    | Per-user workspace directory (`/data/users/{id}`) |
| Memory          | Isolated memory files per user                   |
| Skills          | Shared skill binaries, per-user config           |
| LLM Keys        | Platform-owned keys, usage metered per user      |
| Execution       | Lane Queue pattern (serial per-session)          |
| Network         | All traffic routed through API Gateway (no direct access) |

### Agent Lifecycle

1. User creates agent → API Gateway writes config to OpenClaw workspace
2. Agent activated → OpenClaw loads agent runtime with user's skill set
3. Task submitted → Queued via BullMQ, executed in user's lane
4. Results streamed → WebSocket relay from OpenClaw → API Gateway → iOS app

---

## 4. Skill Installation Mechanism

### Flow

```
User taps "Add Skill" → Browse curated catalog → Tap "Install"
        │
        ▼
API Gateway → clawhub CLI (server-side) → Download skill package
        │
        ▼
Security scan (allowlist check + sandboxed test run)
        │
        ▼
Install to user's agent workspace → Update agent config
```

### Safety Layer

- **Curated catalog**: Only pre-vetted skills shown to free users
- **Community skills**: Available to Pro users with warning badge
- **Blocklist**: Skills flagged in ClawHavoc incident permanently blocked
- **Sandboxing**: Skills run in restricted environment (no raw shell, no network egress except allowlisted domains)
- **Permission model**: Each skill declares required permissions; user must approve

---

## 5. API Communication

The API Gateway exposes REST endpoints for auth, agents, skills, tasks, subscriptions, and usage, plus a WebSocket path for real-time task streaming. See [backend/README.md](backend/README.md) for the full API reference with curl examples.

---

## 6. Security Model

### Authentication
- JWT with short-lived access tokens (15 min) + refresh tokens (30 days)
- App Store receipt validation for subscription status
- Device fingerprinting for abuse prevention

### Authorization
- RBAC: Free users get restricted skill set + lower rate limits
- Each API call checks subscription tier before execution
- Agent actions sandboxed to user's workspace

### Data Isolation
- User data in PostgreSQL with row-level security (RLS)
- Agent workspaces on filesystem with UNIX permission isolation
- No cross-user data access possible at any layer

### Network Security
- All traffic over TLS 1.3
- API Gateway is the only public-facing service
- OpenClaw Gateway bound to localhost only
- Redis and PostgreSQL not exposed externally

---

## 7. Subscription Model

### Tiers

| Feature                  | Free          | Pro ($9.99/mo)    | Team ($24.99/mo)  |
|--------------------------|---------------|-------------------|--------------------|
| Agents                   | 1             | 5                 | 20                 |
| Tasks per day            | 10            | 100               | Unlimited          |
| Skills                   | 5 curated     | All curated + community | All + custom  |
| LLM model                | GPT-4o-mini   | GPT-4o / Claude   | All models         |
| Memory                   | 7-day         | 90-day            | Unlimited          |
| Priority execution       | No            | Yes               | Yes                |
| Task history             | 24 hours      | 30 days           | Unlimited          |
| Support                  | Community     | Email             | Priority           |

### Compute Management

- Each task metered by LLM tokens consumed + execution time
- Free tier: capped at ~50K tokens/day
- Pro tier: capped at ~500K tokens/day
- Overages: task queued until next day or user upgrades
- Server-side enforcement via BullMQ rate limiter

### Revenue Projection (conservative)

- 1,000 free users, 100 Pro ($999/mo), 10 Team ($250/mo) = ~$1,250/mo
- Infrastructure cost at this scale: ~$150/mo
- Gross margin: ~88%

---

## 8. Risk Analysis

### Security Risks
| Risk | Severity | Mitigation |
|------|----------|------------|
| Malicious skills (ClawHavoc) | Critical | Curated catalog, sandboxing, blocklist |
| JWT token theft | High | Short expiry, device binding, refresh rotation |
| Prompt injection | High | Input sanitization, output filtering |
| Data leakage between users | Critical | RLS, filesystem isolation, audit logging |

### Operational Risks
| Risk | Severity | Mitigation |
|------|----------|------------|
| Server overload | High | Per-user rate limits, BullMQ concurrency caps |
| Cost explosion (LLM) | High | Hard token caps per tier, spending alerts |
| OpenClaw upstream breaking changes | Medium | Pin versions, integration tests |
| Single point of failure | Medium | Daily backups, health checks, failover plan |

### App Store Compliance Risks
| Risk | Severity | Mitigation |
|------|----------|------------|
| Rejection for "app within an app" | High | Position as "AI assistant" not "app builder" |
| IAP requirement for subscriptions | Critical | Use StoreKit 2 exclusively, no external payment |
| Content moderation | High | Output filtering, report mechanism, ToS |
| Privacy (App Tracking Transparency) | Medium | Minimal data collection, clear privacy labels |

---

## 9. Technical Stack

See [README.md](README.md) for the current tech stack summary.

---

## 10. MVP vs V2 Scope

### MVP (8–10 weeks)
- [ ] User registration / login (email + Apple Sign In)
- [ ] Create 1 agent with name, persona, and model selection
- [ ] Browse and install from 20 curated skills
- [ ] Text-based task submission and response viewing
- [ ] Free tier with basic rate limiting
- [ ] StoreKit 2 paywall for Pro tier
- [ ] Basic usage dashboard

### V2 (Month 4–6)
- [ ] Multiple agents with switching
- [ ] Skill discovery with search and categories
- [ ] Real-time streaming task output (WebSocket)
- [ ] Agent memory and conversation history
- [ ] Team tier with shared agents
- [ ] Push notifications for completed tasks
- [ ] Widgets for quick task execution
- [ ] Siri Shortcuts integration
- [ ] Agent templates ("Marketing Assistant", "Research Bot", etc.)

---

## 11. UX Flow Summary

### Onboarding (3 screens)
1. **Welcome** — "Your AI agents, in your pocket" + value props
2. **Sign Up** — Apple Sign In (primary) + email fallback
3. **First Agent** — Name it, pick a persona, done

### Home Screen
- Active agent card with status indicator
- Quick task input bar at bottom
- Recent tasks list
- "Add Skill" shortcut

### Agent Creation (bottom sheet)
1. Name your agent
2. Choose personality (dropdown: Professional, Friendly, Technical, Creative)
3. Select AI model (Free: GPT-4o-mini shown, others locked with Pro badge)
4. Tap "Create"

### Skill Browser
- Grid of skill cards with icon, name, one-line description
- Categories: Productivity, Research, Writing, Data, Communication
- Tap to see detail → "Install" button
- Installed skills shown with checkmark

### Task Execution
- Chat-like interface
- Type task in natural language
- Response streams in with typing indicator
- Results rendered as formatted cards
- Option to "Run Again" or "Edit & Retry"

### Paywall
- Triggered on: 2nd agent creation, 11th daily task, community skill install
- Shows comparison table (Free vs Pro)
- Apple Pay / subscription button
- "Restore Purchases" link
