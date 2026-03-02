#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=".env"

# ── Generate .env if missing ─────────────────────────
if [ ! -f "$ENV_FILE" ]; then
  echo "Creating $ENV_FILE from .env.example …"
  cp .env.example "$ENV_FILE"

  # Auto-generate secrets
  DB_PASSWORD=$(openssl rand -hex 16)
  JWT_SECRET=$(openssl rand -hex 32)
  GATEWAY_TOKEN=$(openssl rand -hex 32)

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/changeme_db_password/$DB_PASSWORD/" "$ENV_FILE"
    sed -i '' "s/changeme_jwt_secret/$JWT_SECRET/" "$ENV_FILE"
    sed -i '' "s/changeme_gateway_token/$GATEWAY_TOKEN/" "$ENV_FILE"
  else
    sed -i "s/changeme_db_password/$DB_PASSWORD/" "$ENV_FILE"
    sed -i "s/changeme_jwt_secret/$JWT_SECRET/" "$ENV_FILE"
    sed -i "s/changeme_gateway_token/$GATEWAY_TOKEN/" "$ENV_FILE"
  fi

  echo "Generated secrets in $ENV_FILE"
  echo ""
  echo "  ⚠  Add your LLM API keys to $ENV_FILE before starting:"
  echo "     OPENAI_API_KEY=sk-..."
  echo "     ANTHROPIC_API_KEY=sk-ant-..."
  echo ""
fi

# ── Pull / build images ──────────────────────────────
echo "Pulling base images …"
docker compose pull postgres redis caddy 2>/dev/null || true

echo "Building OpenClaw gateway (first build takes a few minutes) …"
docker compose build openclaw-gateway

echo "Building API gateway …"
docker compose build api-gateway

# ── Start everything ─────────────────────────────────
echo "Starting services …"
docker compose up -d

echo ""
echo "All services started.  Endpoints:"
echo "  API Gateway:      http://localhost:3000"
echo "  WebSocket:        ws://localhost:3000/ws/agents/:agentId"
echo "  Health check:     http://localhost:3000/health"
echo ""
echo "Logs:  docker compose logs -f"
