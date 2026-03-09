#!/usr/bin/env python3
"""Interactive CLI to test the OpenClaw backend API. Zero dependencies (stdlib only)."""

import json
import time
import urllib.request
import urllib.error

BASE_URL = "http://localhost"
CLAWHUB_API = "https://topclawhubskills.com/api"

session = {
    "access_token": None,
    "refresh_token": None,
    "user": None,
    "agent_id": None,
}


def api(method, path, body=None, params=None):
    url = f"{BASE_URL}{path}"
    if params:
        qs = "&".join(f"{k}={v}" for k, v in params.items() if v)
        if qs:
            url += f"?{qs}"

    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if session["access_token"]:
        req.add_header("Authorization", f"Bearer {session['access_token']}")

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
        return 0, {"error": "Connection refused. Is the backend running? (docker compose up)"}


def pretty(status, data):
    color = "\033[32m" if 200 <= status < 300 else "\033[31m" if status >= 400 else "\033[33m"
    reset = "\033[0m"
    if status:
        print(f"  {color}HTTP {status}{reset}")
    print(json.dumps(data, indent=2))
    return data


def save_tokens(data):
    if "tokens" in data:
        session["access_token"] = data["tokens"]["access_token"]
        session["refresh_token"] = data["tokens"]["refresh_token"]
        session["user"] = data.get("user")
        print(f"\n  Logged in as: {session['user']['email']}")
    elif "access_token" in data:
        session["access_token"] = data["access_token"]
        session["refresh_token"] = data["refresh_token"]
        print("\n  Token refreshed.")


# ── Auth ─────────────────────────────────────

def register():
    email = input("  Email [test@openclaw.dev]: ").strip() or "test@openclaw.dev"
    password = input("  Password [password123]: ").strip() or "password123"
    name = input("  Display name [Test User]: ").strip() or "Test User"
    code, data = api("POST", "/auth/register", {
        "email": email, "password": password, "display_name": name,
    })
    pretty(code, data)
    if 200 <= code < 300:
        save_tokens(data)


def login():
    email = input("  Email [test@openclaw.dev]: ").strip() or "test@openclaw.dev"
    password = input("  Password [password123]: ").strip() or "password123"
    code, data = api("POST", "/auth/login", {"email": email, "password": password})
    pretty(code, data)
    if 200 <= code < 300:
        save_tokens(data)


def refresh_token():
    if not session["refresh_token"]:
        print("  No refresh token. Login first.")
        return
    code, data = api("POST", "/auth/refresh", {"refresh_token": session["refresh_token"]})
    pretty(code, data)
    if 200 <= code < 300:
        save_tokens(data)


# ── Agents ───────────────────────────────────

def list_agents():
    code, data = api("GET", "/agents")
    pretty(code, data)
    agents = data.get("agents", [])
    if agents:
        session["agent_id"] = agents[0]["id"]
        print(f"\n  Active agent set to: {session['agent_id']}")


def create_agent():
    name = input("  Agent name [My Assistant]: ").strip() or "My Assistant"
    print("  Personas: Professional, Friendly, Technical, Creative")
    persona = input("  Persona [Professional]: ").strip() or "Professional"
    print("  Models: gpt-5.2, gpt-5.4, gpt-5-mini, gpt-4o, claude-sonnet")
    model = input("  Model [gpt-5.2]: ").strip() or "gpt-5.2"
    code, data = api("POST", "/agents", {"name": name, "persona": persona, "model": model})
    pretty(code, data)
    if 200 <= code < 300:
        session["agent_id"] = data["id"]
        print(f"\n  Agent created: {session['agent_id']}")


def update_agent():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected. List or create one first.")
        return
    print(f"  Updating agent {aid[:8]}...")
    name = input("  New name (blank to skip): ").strip() or None
    persona = input("  New persona (blank to skip): ").strip() or None
    model = input("  New model (blank to skip): ").strip() or None
    body = {k: v for k, v in {"name": name, "persona": persona, "model": model}.items() if v}
    if not body:
        print("  Nothing to update.")
        return
    code, data = api("PATCH", f"/agents/{aid}", body)
    pretty(code, data)


def delete_agent():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    if input(f"  Delete agent {aid[:8]}...? (y/N): ").strip().lower() != "y":
        return
    code, data = api("DELETE", f"/agents/{aid}")
    pretty(code, data)
    if 200 <= code < 300:
        session["agent_id"] = None
        print("  Agent deleted.")


# ── Tasks ────────────────────────────────────

def format_task_result(result):
    """Display a task result in a human-readable chat format."""
    green, red, cyan, bold, dim, reset = (
        "\033[32m", "\033[31m", "\033[36m", "\033[1m", "\033[2m", "\033[0m",
    )
    status = result.get("status", "?")
    status_color = green if status == "completed" else red

    print(f"  {dim}{'─' * 50}{reset}")
    print(f"  {cyan}{bold}You:{reset}  {result.get('input', '—')}")
    print()
    if status == "completed" and result.get("output"):
        print(f"  {green}{bold}Agent:{reset}  {result['output']}")
    elif status == "failed":
        print(f"  {red}{bold}Failed:{reset}  {result.get('output', 'Unknown error')}")
    else:
        print(f"  {dim}No output{reset}")
    print()
    tokens = result.get("tokens_used")
    elapsed = ""
    if result.get("created_at") and result.get("completed_at"):
        try:
            t0 = time.strptime(result["created_at"][:19], "%Y-%m-%dT%H:%M:%S")
            t1 = time.strptime(result["completed_at"][:19], "%Y-%m-%dT%H:%M:%S")
            secs = int(time.mktime(t1) - time.mktime(t0))
            elapsed = f"  {dim}⏱ {secs}s{reset}"
        except Exception:
            pass
    print(f"  {status_color}● {status}{reset}"
          f"  {dim}tokens: {tokens or '—'}{reset}"
          f"{elapsed}")
    print(f"  {dim}{'─' * 50}{reset}")


def submit_task():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected. List or create one first.")
        return
    prompt = input("  Task input: ").strip()
    if not prompt:
        print("  Empty input, skipping.")
        return
    code, data = api("POST", f"/agents/{aid}/tasks", {"input": prompt})
    if code < 200 or code >= 300:
        pretty(code, data)
        return

    task_id = data["task_id"]
    print(f"\n  Task queued. Waiting", end="", flush=True)

    for _ in range(30):
        time.sleep(2)
        print(".", end="", flush=True)
        _, result = api("GET", f"/agents/{aid}/tasks/{task_id}")
        if result.get("status") in ("completed", "failed"):
            print("\n")
            format_task_result(result)
            return

    print("\n  Timed out. Check manually with option 9.")


def list_tasks():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    code, data = api("GET", f"/agents/{aid}/tasks")
    pretty(code, data)


def clear_history():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    if input(f"  Clear all conversation history for agent {aid[:8]}...? (y/N): ").strip().lower() != "y":
        return
    code, data = api("DELETE", f"/agents/{aid}/tasks")
    pretty(code, data)
    if 200 <= code < 300:
        print(f"  Cleared {data.get('deleted', 0)} task(s). Agent starts fresh.")


# ── Skills ───────────────────────────────────

def skill_table(skills):
    """Print skills as a compact table."""
    if not skills:
        print("  No skills found.")
        return
    green, red, reset, dim = "\033[32m", "\033[31m", "\033[0m", "\033[2m"
    print(f"\n  {'#':<4} {'Name':<22} {'Category':<15} {'Author':<16} {'Stars':<8} {'Installed'}")
    print(f"  {'─'*4} {'─'*22} {'─'*15} {'─'*16} {'─'*8} {'─'*9}")
    for i, s in enumerate(skills, 1):
        installed = s.get("is_installed")
        badge = f"{green}yes{reset}" if installed else f"{dim}no{reset}" if installed is False else "—"
        stars = f"{s.get('stars', 0):,}"
        print(f"  {i:<4} {s['name']:<22} {s.get('category', '—'):<15} {s.get('author', '—'):<16} {stars:<8} {badge}")
    print(f"\n  {len(skills)} skill(s). Use the slug/id to install.")


def browse_catalog():
    params = {}
    if session["agent_id"]:
        params["agent_id"] = session["agent_id"]
    category = input("  Filter by category (blank for all): ").strip()
    if category:
        params["category"] = category
    code, data = api("GET", "/skills/catalog", params=params)
    if 200 <= code < 300:
        skill_table(data.get("skills", []))
    else:
        pretty(code, data)


def browse_clawhub():
    params = {}
    if session["agent_id"]:
        params["agent_id"] = session["agent_id"]
    code, data = api("GET", "/skills/clawhub/browse", params=params)
    if 200 <= code < 300:
        skill_table(data.get("skills", []))
    else:
        pretty(code, data)


def browse_clawhub_live():
    """Fetch real skills from the live ClawHub registry."""
    print("  Sort by: 1) downloads  2) stars  3) newest  4) certified")
    sort_choice = input("  Choice [1]: ").strip() or "1"
    endpoints = {"1": "top-downloads", "2": "top-stars", "3": "newest", "4": "certified"}
    endpoint = endpoints.get(sort_choice, "top-downloads")

    limit = input("  How many? [25]: ").strip() or "25"
    search = input("  Search term (blank for none): ").strip()

    if search:
        url = f"{CLAWHUB_API}/search?q={urllib.request.quote(search)}&limit={limit}"
    else:
        url = f"{CLAWHUB_API}/{endpoint}?limit={limit}"

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
    except Exception as e:
        print(f"  Failed to reach ClawHub API: {e}")
        return

    skills = data.get("data", [])
    if not skills:
        print("  No skills found.")
        return

    green, reset, dim, bold = "\033[32m", "\033[0m", "\033[2m", "\033[1m"
    print(f"\n  {bold}ClawHub Live — {endpoint.replace('-', ' ').title()}{reset}  ({len(skills)} results)\n")
    print(f"  {'#':<4} {'Name':<26} {'Downloads':<12} {'Stars':<8} {'Author':<18} {'Certified'}")
    print(f"  {'─'*4} {'─'*26} {'─'*12} {'─'*8} {'─'*18} {'─'*9}")
    for i, s in enumerate(skills, 1):
        cert = f"{green}✓{reset}" if s.get("is_certified") else f"{dim}—{reset}"
        print(f"  {i:<4} {s['display_name'][:25]:<26} {s['downloads']:>10,}  {s['stars']:>6,}  {s.get('owner_handle', '?'):<18} {cert}")

    print(f"\n  {dim}Source: clawhub.ai{reset}")
    print(f"  To install, use option 14 with the slug (e.g. community/arxiv-researcher)")


def recommended_skills():
    params = {}
    if session["agent_id"]:
        params["agent_id"] = session["agent_id"]
    code, data = api("GET", "/skills/recommended", params=params)
    if 200 <= code < 300:
        skill_table(data.get("skills", []))
    else:
        pretty(code, data)


def install_skill():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    skill_id = input("  Skill ID (e.g. web-research, summarizer): ").strip()
    if not skill_id:
        return
    code, data = api("POST", f"/agents/{aid}/skills", {"skill_id": skill_id})
    pretty(code, data)


def install_clawhub_skill():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    slug = input("  ClawHub slug (e.g. community/arxiv-researcher): ").strip()
    if not slug:
        return
    code, data = api("POST", f"/agents/{aid}/skills/clawhub", {"slug": slug})
    pretty(code, data)


def list_agent_skills():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    code, data = api("GET", f"/agents/{aid}/skills")
    pretty(code, data)


def toggle_skill():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    skill_id = input("  Skill ID to toggle: ").strip()
    if not skill_id:
        return
    enabled = input("  Enable? (y/n): ").strip().lower() == "y"
    code, data = api("PATCH", f"/agents/{aid}/skills/{skill_id}", {"enabled": enabled})
    pretty(code, data)


def setup_skill():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    skill_id = input("  Skill ID to setup (install dependencies): ").strip()
    if not skill_id:
        return
    code, data = api("POST", f"/agents/{aid}/skills/{skill_id}/setup")
    if code < 200 or code >= 300:
        pretty(code, data)
        return

    if data.get("status") == "no_setup_needed":
        print("  No install commands found in SKILL.md.")
        return

    cmds = data.get("install_commands", [])
    print(f"  Setup queued. Installing: {', '.join(cmds)}")
    task_id = data.get("setup_task_id")
    if not task_id:
        return

    print("  Waiting for setup", end="", flush=True)
    for _ in range(30):
        time.sleep(2)
        print(".", end="", flush=True)
        _, result = api("GET", f"/agents/{aid}/tasks/{task_id}")
        if result.get("status") in ("completed", "failed"):
            print("\n")
            format_task_result(result)
            return
    print("\n  Timed out. Check task list (option 9).")


def uninstall_skill():
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    skill_id = input("  Skill ID to remove: ").strip()
    if not skill_id:
        return
    code, data = api("DELETE", f"/agents/{aid}/skills/{skill_id}")
    pretty(code, data)


# ── Subscription & Usage ─────────────────────

def check_usage():
    code, data = api("GET", "/usage")
    pretty(code, data)


def check_subscription():
    code, data = api("GET", "/subscription")
    pretty(code, data)


def health_check():
    code, data = api("GET", "/health")
    pretty(code, data)


# ── Quick Test (full flow) ───────────────────

def quick_test():
    """Register/login, create agent, submit task, wait for result."""
    print("\n  === Quick Test: full end-to-end flow ===\n")

    email = "quicktest@openclaw.dev"
    password = "test123"

    print("  1. Registering (or logging in)...")
    code, data = api("POST", "/auth/register", {
        "email": email, "password": password, "display_name": "Quick Test",
    })
    if code == 409:
        code, data = api("POST", "/auth/login", {"email": email, "password": password})
    if code < 200 or code >= 300:
        print(f"  Auth failed: {data}")
        return
    save_tokens(data)
    print(f"  OK - logged in as {email}\n")

    print("  2. Creating agent...")
    code, data = api("POST", "/agents", {
        "name": "QuickTest Agent", "persona": "Professional", "model": "gpt-5.2",
    })
    if 200 <= code < 300:
        session["agent_id"] = data["id"]
        skills = data.get("skills", [])
        print(f"  OK - agent {data['id'][:8]}... with {len(skills)} skills\n")
    else:
        print(f"  Agent creation returned {code}, trying to use existing...")
        code, data = api("GET", "/agents")
        agents = data.get("agents", [])
        if not agents:
            print("  No agents available. Aborting.")
            return
        session["agent_id"] = agents[0]["id"]
        print(f"  Using existing agent: {session['agent_id'][:8]}...\n")

    aid = session["agent_id"]

    print("  3. Submitting task: 'What is the capital of France?'")
    code, data = api("POST", f"/agents/{aid}/tasks", {"input": "What is the capital of France?"})
    if code < 200 or code >= 300:
        print(f"  Failed: {data}")
        return
    task_id = data["task_id"]
    print(f"  OK - task {task_id[:8]}... queued\n")

    print("  4. Waiting for result", end="", flush=True)
    for _ in range(30):
        time.sleep(2)
        print(".", end="", flush=True)
        _, result = api("GET", f"/agents/{aid}/tasks/{task_id}")
        if result.get("status") in ("completed", "failed"):
            print(f"\n\n  Status: {result['status']}")
            print(f"  Output: {result.get('output', 'N/A')}")
            print(f"  Tokens: {result.get('tokens_used', 'N/A')}")
            print("\n  === Quick test complete! ===")
            return
    print("\n  Timed out after 60s.")


# ── Menu ─────────────────────────────────────

MENU = """
╔══════════════════════════════════════════════════╗
║            OpenClaw API Test Client              ║
╠══════════════════════════════════════════════════╣
║  AUTH                                            ║
║   1) Register              2) Login              ║
║   3) Refresh token                               ║
║  AGENTS                                          ║
║   4) List agents           5) Create agent       ║
║   6) Update agent          7) Delete agent       ║
║  TASKS                                           ║
║   8) Submit task           9) List tasks         ║
║  22) Clear history (reset conversation)          ║
║  SKILLS (local backend)                          ║
║  10) Browse catalog       11) Browse ClawHub     ║
║  12) Recommended skills                          ║
║  13) Install skill        14) Install ClawHub    ║
║  15) List agent skills                           ║
║  16) Toggle skill         17) Uninstall skill    ║
║  23) Setup skill (install CLI dependencies)      ║
║  SKILLS (live clawhub.ai)                        ║
║  21) Browse ClawHub LIVE (all skills)            ║
║  OTHER                                           ║
║  18) Usage                19) Subscription       ║
║  20) Health check                                ║
║                                                  ║
║  99) Quick test (full end-to-end flow)           ║
║   0) Quit                                        ║
╚══════════════════════════════════════════════════╝"""

ACTIONS = {
    "1": register, "2": login, "3": refresh_token,
    "4": list_agents, "5": create_agent, "6": update_agent, "7": delete_agent,
    "8": submit_task, "9": list_tasks,
    "10": browse_catalog, "11": browse_clawhub, "12": recommended_skills,
    "13": install_skill, "14": install_clawhub_skill,
    "15": list_agent_skills, "16": toggle_skill, "17": uninstall_skill,
    "18": check_usage, "19": check_subscription, "20": health_check,
    "21": browse_clawhub_live,
    "22": clear_history,
    "23": setup_skill,
    "99": quick_test,
}


def main():
    print(MENU)
    while True:
        parts = []
        if session["user"]:
            parts.append(f"user: {session['user']['email']}")
        if session["agent_id"]:
            parts.append(f"agent: {session['agent_id'][:8]}...")
        status = " | ".join(parts)
        prompt = f"\n\033[36m[openclaw{' | ' + status if status else ''}]\033[0m> "

        try:
            choice = input(prompt).strip()
        except (EOFError, KeyboardInterrupt):
            print("\nBye!")
            break

        if choice == "0":
            print("Bye!")
            break
        elif choice in ("menu", "help", "?"):
            print(MENU)
        elif choice in ACTIONS:
            try:
                ACTIONS[choice]()
            except KeyboardInterrupt:
                print("\n  Cancelled.")
            except Exception as e:
                print(f"  Error: {e}")
        else:
            print("  Invalid choice. Type 'menu' to see options.")


if __name__ == "__main__":
    main()
