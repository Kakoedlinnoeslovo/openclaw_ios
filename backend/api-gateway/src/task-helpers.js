const pg = require('pg');
const { setSkillCredentials } = require('./provisioner');

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

const HISTORY_LIMIT = 50;

const OAUTH_PROVIDERS = {
  slack: {
    token_url: 'https://slack.com/api/oauth.v2.access',
    token_field: 'SLACK_BOT_TOKEN',
  },
  google: {
    token_url: 'https://oauth2.googleapis.com/token',
    token_field: 'GOOGLE_ACCESS_TOKEN',
  },
  notion: {
    token_url: 'https://api.notion.com/v1/oauth/token',
    token_field: 'NOTION_API_KEY',
  },
};

async function getOAuthClientCredentials(provider) {
  const envId = process.env[`${provider.toUpperCase()}_CLIENT_ID`];
  const envSecret = process.env[`${provider.toUpperCase()}_CLIENT_SECRET`];
  if (envId && envSecret) return { clientId: envId, clientSecret: envSecret };

  try {
    const { rows: [row] } = await pool.query(
      `SELECT value FROM app_config WHERE key = $1`,
      [`oauth_creds_${provider}`],
    );
    if (row?.value?.client_id && row?.value?.client_secret) {
      return { clientId: row.value.client_id, clientSecret: row.value.client_secret };
    }
  } catch { /* table may not exist */ }
  return null;
}

async function refreshOAuthTokensForAgent(agentId, userId) {
  const { rows: tokens } = await pool.query(
    `SELECT * FROM oauth_tokens WHERE agent_id = $1 AND user_id = $2
     AND expires_at IS NOT NULL AND expires_at < NOW() + INTERVAL '2 minutes'`,
    [agentId, userId],
  );

  for (const tokenRow of tokens) {
    if (!tokenRow.refresh_token) continue;
    const providerCfg = OAUTH_PROVIDERS[tokenRow.provider];
    if (!providerCfg) continue;

    try {
      const creds = await getOAuthClientCredentials(tokenRow.provider);
      if (!creds) continue;
      const { clientId, clientSecret } = creds;

      const tokenParams = new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: tokenRow.refresh_token,
        client_id: clientId,
        client_secret: clientSecret,
      });

      const resp = await fetch(providerCfg.token_url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: tokenParams.toString(),
      });

      if (!resp.ok) {
        console.warn(`[task-helpers] oauth refresh failed for ${tokenRow.provider}:`, await resp.text());
        continue;
      }

      const body = await resp.json();
      const newAccessToken = body.access_token;
      const newRefreshToken = body.refresh_token || tokenRow.refresh_token;
      const expiresAt = body.expires_in
        ? new Date(Date.now() + body.expires_in * 1000)
        : null;

      await pool.query(
        `UPDATE oauth_tokens SET access_token = $1, refresh_token = $2, expires_at = $3, updated_at = NOW()
         WHERE id = $4`,
        [newAccessToken, newRefreshToken, expiresAt, tokenRow.id],
      );

      setSkillCredentials(userId, agentId, tokenRow.skill_id, {
        [providerCfg.token_field]: newAccessToken,
      });

      console.log(`[task-helpers] refreshed ${tokenRow.provider} token for agent=${agentId}`);
    } catch (err) {
      console.warn(`[task-helpers] oauth refresh error for ${tokenRow.provider}:`, err.message);
    }
  }
}

async function loadConversationHistory(agentId, userId) {
  const { rows } = await pool.query(
    `SELECT input, output, status FROM tasks
     WHERE agent_id = $1 AND user_id = $2 AND status = 'completed' AND output IS NOT NULL
     ORDER BY created_at DESC LIMIT $3`,
    [agentId, userId, HISTORY_LIMIT],
  );

  const messages = [];
  for (const row of rows.reverse()) {
    messages.push({ role: 'user', content: row.input });
    messages.push({ role: 'assistant', content: row.output });
  }
  return messages;
}

module.exports = {
  OAUTH_PROVIDERS,
  getOAuthClientCredentials,
  refreshOAuthTokensForAgent,
  loadConversationHistory,
};
