#!/usr/bin/env python3
"""Simulates the exact iOS client API contract to verify the backend
handles Swift's snake_case encoding/decoding correctly.

The iOS APIClient uses:
  - keyEncodingStrategy = .convertToSnakeCase  (struct keys → snake_case)
  - keyDecodingStrategy = .convertFromSnakeCase (snake_case → camelCase)
  - dateDecodingStrategy = .iso8601

This script replicates the exact JSON payloads the iOS app sends and
verifies the responses decode into the expected Swift struct shapes.
"""

import json
import sys
import time
import urllib.request
import urllib.error

BASE_URL = "http://localhost"
GREEN, RED, BOLD, DIM, RESET = "\033[32m", "\033[31m", "\033[1m", "\033[2m", "\033[0m"

passed = 0
total = 0
token = None
agent_id = None


def api(method, path, body=None):
    url = f"{BASE_URL}{path}"
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"error": raw}
    except urllib.error.URLError:
        return 0, {"error": "Connection refused"}


def check(ok, msg):
    global passed, total
    total += 1
    if ok:
        passed += 1
        print(f"  {GREEN}✓ {msg}{RESET}")
    else:
        print(f"  {RED}✗ {msg}{RESET}")
    return ok


def step(desc):
    print(f"\n  {BOLD}{desc}{RESET}")


# ─────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────

print(f"\n{BOLD}═══ iOS API Contract Test ═══{RESET}\n")

step("Auth — iOS sends snake_case body")
code, data = api("POST", "/auth/register", {
    "email": "ios_contract_test@openclaw.dev",
    "password": "test123",
    "display_name": "iOS Tester",
})
if code == 409:
    code, data = api("POST", "/auth/login", {
        "email": "ios_contract_test@openclaw.dev",
        "password": "test123",
    })

check(200 <= code < 300, f"Auth succeeded (HTTP {code})")

tokens = data.get("tokens", data)
token = tokens.get("access_token")
check(token is not None, "access_token present in response")
check("refresh_token" in tokens, "refresh_token present in response")

# ─────────────────────────────────────────────
# Agent creation — iOS sends snake_case
# ─────────────────────────────────────────────

step("Agent creation — iOS encodes CreateAgentRequest with convertToSnakeCase")

# Swift's CreateAgentRequest: { name, persona, model }
# convertToSnakeCase doesn't change these (already lowercase)
code, data = api("POST", "/agents", {
    "name": "iOS Contract Agent",
    "persona": "Technical",
    "model": "gpt-5.2",
})

if code == 403:
    code, data = api("GET", "/agents")
    agents = data.get("agents", [])
    if agents:
        agent_id = agents[0]["id"]
        data = agents[0]
        code = 200

if 200 <= code < 300:
    agent_id = data.get("id", agent_id)

check(200 <= code < 300, f"Agent created/found (HTTP {code})")

# iOS decodes Agent struct with convertFromSnakeCase:
#   id, name, persona, model, skills, isActive, createdAt
check("id" in data, "Response has 'id' field")
check("name" in data, "Response has 'name' field")
check("persona" in data, "Response has 'persona' field")
check("model" in data, "Response has 'model' field")
check("skills" in data, "Response has 'skills' array")
# These are snake_case from backend → Swift decodes as camelCase
check("is_active" in data, "Response has 'is_active' → Swift: isActive")
check("created_at" in data, "Response has 'created_at' → Swift: createdAt")

# Verify skills array shape (InstalledSkill)
skills = data.get("skills", [])
if skills:
    s = skills[0]
    check("skill_id" in s, "Skill has 'skill_id' → Swift: skillId")
    check("is_enabled" in s, "Skill has 'is_enabled' → Swift: isEnabled")
    check("installed_at" in s, "Skill has 'installed_at' → Swift: installedAt")
    check("source" in s, "Skill has 'source' field")
    check("config" in s, "Skill has 'config' field")
else:
    print(f"  {DIM}(no skills to check field names){RESET}")

# ─────────────────────────────────────────────
# ClawHub install — iOS sends { slug } and decodes ClawHubInstallResponse
# ─────────────────────────────────────────────

step("ClawHub install — ClawHubInstallResponse decoding")

# iOS AgentService.installClawHubSkill sends: { "slug": "community/image-gen" }
code, data = api("POST", f"/agents/{agent_id}/skills/clawhub", {
    "slug": "community/image-gen",
})

check(200 <= code < 300, f"ClawHub install succeeded (HTTP {code})")

# ClawHubInstallResponse tries to decode 'agent' nested key first,
# then falls back to decoding Agent from root.
# Backend spreads agent at root, so the fallback path fires.
check("id" in data, "Root has Agent 'id' (fallback decode path)")
check("skills" in data, "Root has Agent 'skills' array")

# Additional ClawHub fields — Swift decodes these via CodingKeys
check("setup_required" in data, "Has 'setup_required' → Swift: setupRequired")
check("setup_requirements" in data, "Has 'setup_requirements' → Swift: setupRequirements")

# Verify the installed skill appears in the skills list
skills = data.get("skills", [])
installed_ids = [s.get("skill_id") for s in skills]
check("image-gen" in installed_ids, f"'image-gen' in returned skills list")

# ─────────────────────────────────────────────
# Credential save — iOS sends { credentials: { KEY: VALUE } }
# ─────────────────────────────────────────────

step("Credential save — iOS sends CredBody with convertToSnakeCase")

# Swift struct CredBody: { credentials: [String: String] }
# convertToSnakeCase: credentials → credentials (no change)
# The INNER dict keys (OPENAI_API_KEY) are NOT affected by key strategy
dirty_key = "  AIzaSyBX_test_key_with_spaces  \n"
code, data = api("POST", f"/agents/{agent_id}/skills/image-gen/credentials", {
    "credentials": {"OPENAI_API_KEY": dirty_key},
})

check(200 <= code < 300, f"Credential save succeeded (HTTP {code})")
check(data.get("status") == "configured", "Response: status='configured'")

# ─────────────────────────────────────────────
# Verify _configured persists through re-install
# ─────────────────────────────────────────────

step("Config merge — _configured survives re-install")

code, data = api("POST", f"/agents/{agent_id}/skills/clawhub", {"slug": "community/image-gen"})
check(200 <= code < 300, "Re-install succeeded")

skills = data.get("skills", [])
target = [s for s in skills if s.get("skill_id") == "image-gen"]
if target:
    cfg = target[0].get("config", {})
    check(
        cfg.get("_configured") is True,
        "_configured=true survives re-install (JSONB merge)",
    )
else:
    check(False, "Skill not found after re-install")

# ─────────────────────────────────────────────
# Task submit — iOS sends TaskSubmitRequest
# ─────────────────────────────────────────────

step("Task submit — iOS sends TaskSubmitRequest with convertToSnakeCase")

# Swift TaskSubmitRequest: { input, imageData?, webSearch?, fileIds? }
# convertToSnakeCase: imageData → image_data, webSearch → web_search, fileIds → file_ids
code, data = api("POST", f"/agents/{agent_id}/tasks", {
    "input": "Say hello in one word",
    "image_data": None,
    "web_search": False,
    "file_ids": None,
})

check(200 <= code < 300, f"Task submitted (HTTP {code})")

# iOS decodes TaskSubmitResponse: { taskId, status }
# Backend returns: { task_id, status }
check("task_id" in data, "Response has 'task_id' → Swift: taskId")
check("status" in data, "Response has 'status' field")

task_id = data.get("task_id")

# Wait for completion
if task_id:
    print(f"  {DIM}Waiting for task...", end="", flush=True)
    for _ in range(25):
        time.sleep(2)
        print(".", end="", flush=True)
        _, result = api("GET", f"/agents/{agent_id}/tasks/{task_id}")
        if result.get("status") in ("completed", "failed"):
            print(f"{RESET}")
            check(
                result.get("status") == "completed",
                f"Task completed: {result.get('output', '')[:60]}",
            )
            # Verify task response shape
            check("agent_id" in result, "'agent_id' → Swift: agentId")
            check("created_at" in result, "'created_at' → Swift: createdAt")
            check("tokens_used" in result, "'tokens_used' → Swift: tokensUsed")
            break
    else:
        print(f"{RESET}")
        check(False, "Task timed out after 50s")

# ─────────────────────────────────────────────
# Skills list — verify shape
# ─────────────────────────────────────────────

step("Skills list — iOS decodes SkillsResponse { skills: [InstalledSkill] }")

code, data = api("GET", f"/agents/{agent_id}/skills")
check(200 <= code < 300, "GET skills succeeded")
check("skills" in data, "Response has 'skills' key")
skills = data.get("skills", [])
if skills:
    s = skills[0]
    required_fields = ["id", "skill_id", "name", "icon", "version", "is_enabled", "source", "installed_at"]
    for field in required_fields:
        check(field in s, f"Skill has '{field}'")

# ─────────────────────────────────────────────
# Skill requirements — verify shape
# ─────────────────────────────────────────────

step("Skill requirements — iOS decodes SkillRequirementsResponse")

code, data = api("GET", f"/agents/{agent_id}/skills/image-gen/requirements")
check(200 <= code < 300, "Requirements endpoint succeeded")
# Swift SkillRequirementsResponse: { skillId, source, requirements, installCommands, isConfigured }
check("skill_id" in data, "'skill_id' → Swift: skillId")
check("requirements" in data, "'requirements' array present")
check("install_commands" in data, "'install_commands' → Swift: installCommands")
check("is_configured" in data, "'is_configured' → Swift: isConfigured")

# ─────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────

api("DELETE", f"/agents/{agent_id}/skills/image-gen")

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────

color = GREEN if passed == total else RED
print(f"\n{BOLD}Results: {color}{passed}/{total} passed{RESET}\n")
if passed == total:
    print(f"{GREEN}{BOLD}iOS API contract fully verified!{RESET}")
    print(f"{DIM}All field names match Swift's convertFromSnakeCase expectations.{RESET}")
else:
    print(f"{RED}{BOLD}{total - passed} contract violation(s) found.{RESET}")
print()

sys.exit(0 if passed == total else 1)
