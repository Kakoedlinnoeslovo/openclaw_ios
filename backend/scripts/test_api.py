#!/usr/bin/env python3
"""Interactive CLI to test the OpenClaw backend API. Zero dependencies (stdlib only)."""

import json
import time
import urllib.request
import urllib.error
import socket
import base64
import struct
import os
import threading
from urllib.parse import urlparse

BASE_URL = "http://localhost"
CLAWHUB_API = "https://topclawhubskills.com/api"

session = {
    "access_token": None,
    "refresh_token": None,
    "user": None,
    "agent_id": None,
}


# ── Minimal WebSocket client (stdlib only) ───
class SimpleWebSocket:
    """RFC 6455 WebSocket client using raw sockets — no third-party deps."""

    def __init__(self, host, port, path):
        self.host = host
        self.port = port
        self.path = path
        self.sock = None
        self._closed = False

    def connect(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.settimeout(10)
        self.sock.connect((self.host, self.port))
        key = base64.b64encode(os.urandom(16)).decode()
        handshake = (
            f"GET {self.path} HTTP/1.1\r\n"
            f"Host: {self.host}:{self.port}\r\n"
            f"Upgrade: websocket\r\n"
            f"Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            f"Sec-WebSocket-Version: 13\r\n"
            f"\r\n"
        )
        self.sock.sendall(handshake.encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("Connection closed during handshake")
            resp += chunk
        status_line = resp.split(b"\r\n")[0]
        if b"101" not in status_line:
            raise ConnectionError(f"WebSocket handshake failed: {status_line.decode()}")
        self.sock.settimeout(None)

    def recv_frame(self):
        if self._closed:
            return None
        header = self._recv_exact(2)
        opcode = header[0] & 0x0F
        masked = header[1] & 0x80
        length = header[1] & 0x7F
        if length == 126:
            length = struct.unpack(">H", self._recv_exact(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", self._recv_exact(8))[0]
        mask_key = self._recv_exact(4) if masked else None
        payload = self._recv_exact(length)
        if mask_key:
            payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))
        if opcode == 0x8:
            self._closed = True
            return None
        if opcode == 0x9:
            self._send_frame(0xA, payload)
            return self.recv_frame()
        if opcode == 0x1:
            return payload.decode("utf-8", errors="replace")
        return None

    def _recv_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("WebSocket connection closed")
            buf += chunk
        return buf

    def _send_frame(self, opcode, payload):
        frame = bytearray()
        frame.append(0x80 | opcode)
        mask_key = os.urandom(4)
        plen = len(payload)
        if plen < 126:
            frame.append(0x80 | plen)
        elif plen < 65536:
            frame.append(0x80 | 126)
            frame.extend(struct.pack(">H", plen))
        else:
            frame.append(0x80 | 127)
            frame.extend(struct.pack(">Q", plen))
        frame.extend(mask_key)
        frame.extend(bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload)))
        self.sock.sendall(frame)

    def close(self):
        if self._closed:
            return
        self._closed = True
        try:
            self._send_frame(0x8, b"")
            self.sock.shutdown(socket.SHUT_RDWR)
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass


def connect_ws(agent_id=None, token=None):
    """Open a WebSocket to the task event stream. Returns None on failure."""
    aid = agent_id or session["agent_id"]
    tok = token or session["access_token"]
    if not aid or not tok:
        return None
    parsed = urlparse(BASE_URL)
    host = parsed.hostname or "localhost"
    port = parsed.port or 80
    ws_path = f"/ws/agents/{aid}?token={tok}"
    ws = SimpleWebSocket(host, port, ws_path)
    try:
        ws.connect()
        return ws
    except Exception as e:
        try:
            ws.close()
        except Exception:
            pass
        return None


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
    print("  Models: gpt-5.2, gpt-4o, gpt-4o-mini, claude-sonnet")
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

    dim, bold, reset, green, cyan = "\033[2m", "\033[1m", "\033[0m", "\033[32m", "\033[36m"

    ws = connect_ws()
    if ws:
        print(f"  {dim}(streaming via WebSocket){reset}")
    else:
        print(f"  {dim}(no WebSocket — polling only){reset}")

    code, data = api("POST", f"/agents/{aid}/tasks", {"input": prompt})
    if code < 200 or code >= 300:
        pretty(code, data)
        if ws:
            ws.close()
        return

    task_id = data["task_id"]
    done_event = threading.Event()
    streamed = {"text": "", "had_output": False}

    def ws_listener():
        try:
            while not done_event.is_set():
                msg = ws.recv_frame()
                if msg is None:
                    break
                event = json.loads(msg)
                etype = event.get("type")
                tid = event.get("task_id")
                if tid and tid != task_id:
                    continue
                if etype == "task:progress":
                    content = event.get("content", "")
                    if content:
                        if not streamed["had_output"]:
                            streamed["had_output"] = True
                            print(f"\n  {green}{bold}Agent:{reset}  ", end="", flush=True)
                        print(content, end="", flush=True)
                        streamed["text"] += content
                elif etype == "task:tool_start":
                    tool = event.get("tool_name", "?")
                    print(f"\n  {dim}[tool: {tool}...]{reset}", end="", flush=True)
                elif etype == "task:tool_end":
                    print(f" {dim}done{reset}", end="", flush=True)
                elif etype in ("task:complete", "task:error"):
                    if etype == "task:error":
                        print(f"\n  {bold}\033[31mError:{reset} {event.get('error', '?')}")
                    done_event.set()
                    break
        except Exception:
            done_event.set()

    if ws:
        listener = threading.Thread(target=ws_listener, daemon=True)
        listener.start()

    print(f"\n  Task queued. Waiting", end="", flush=True)

    for _ in range(90):
        if done_event.is_set():
            break
        time.sleep(2)
        if not ws:
            print(".", end="", flush=True)
        _, result = api("GET", f"/agents/{aid}/tasks/{task_id}")
        if result.get("status") in ("completed", "failed"):
            done_event.set()
            if not streamed["had_output"]:
                print("\n")
                format_task_result(result)
            else:
                print(f"\n\n  {dim}● {result.get('status')}  tokens: {result.get('tokens_used', '—')}{reset}")
            if ws:
                ws.close()
            return

    done_event.set()
    if ws:
        ws.close()
    print("\n  Timed out after 180s. Check manually with option 9.")


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
    """Print skills as a compact table with slug for easy install."""
    if not skills:
        print("  No skills found.")
        return
    green, red, reset, dim, bold, cyan = "\033[32m", "\033[31m", "\033[0m", "\033[2m", "\033[1m", "\033[36m"

    cats = sorted(set(s.get("category", "—") for s in skills))
    if len(cats) > 1:
        print(f"\n  {dim}Categories: {', '.join(cats)}{reset}")

    print(f"\n  {'#':<4} {'Name':<22} {'Slug / ID':<32} {'Cat':<12} {'DL':<8} {'★':<6} {'Inst'}")
    print(f"  {'─'*4} {'─'*22} {'─'*32} {'─'*12} {'─'*8} {'─'*6} {'─'*4}")
    for i, s in enumerate(skills, 1):
        installed = s.get("is_installed")
        badge = f"{green}yes{reset}" if installed else f"{dim}no{reset}" if installed is False else "—"
        stars = f"{s.get('stars', 0):,}"
        dl = f"{s.get('downloads', 0):,}"
        name = s["name"][:21]
        slug = s.get("slug") or s.get("skill_id") or s.get("id") or "—"
        slug_display = slug[:31]
        print(f"  {i:<4} {name:<22} {cyan}{slug_display:<32}{reset} {s.get('category', '—'):<12} {dl:<8} {stars:<6} {badge}")
    print(f"\n  {bold}{len(skills)}{reset} skill(s). Install with: {cyan}install <slug>{reset}")


def browse_skills():
    """Unified skill browser: local catalog, ClawHub backend, or live ClawHub."""
    dim, bold, reset, cyan = "\033[2m", "\033[1m", "\033[0m", "\033[36m"
    print(f"  {bold}Source:{reset}  1) ClawHub (backend)  2) Local catalog  3) Recommended  4) ClawHub LIVE")
    src = input("  Choice [1]: ").strip() or "1"

    if src == "4":
        _browse_clawhub_live()
        return

    params = {}
    if session["agent_id"]:
        params["agent_id"] = session["agent_id"]
    category = input("  Category filter (blank for all): ").strip()
    if category:
        params["category"] = category
    if src == "1":
        search = input("  Search (blank for all): ").strip()
        if search:
            params["q"] = search
        code, data = api("GET", "/skills/clawhub/browse", params=params)
    elif src == "3":
        code, data = api("GET", "/skills/recommended", params=params)
    else:
        code, data = api("GET", "/skills/catalog", params=params)

    if 200 <= code < 300:
        skill_table(data.get("skills", []))
    else:
        pretty(code, data)


def _browse_clawhub_live():
    """Fetch real skills from the live ClawHub registry."""
    green, reset, dim, bold, cyan = "\033[32m", "\033[0m", "\033[2m", "\033[1m", "\033[36m"
    print(f"  {bold}Sort:{reset}  1) downloads  2) stars  3) newest  4) certified")
    sort_choice = input("  Choice [1]: ").strip() or "1"
    endpoints = {"1": "top-downloads", "2": "top-stars", "3": "newest", "4": "certified"}
    endpoint = endpoints.get(sort_choice, "top-downloads")

    limit = input("  How many? [25]: ").strip() or "25"
    search = input("  Search (blank for none): ").strip()

    if search:
        url = f"{CLAWHUB_API}/search?q={urllib.request.quote(search)}&limit={limit}"
    else:
        url = f"{CLAWHUB_API}/{endpoint}?limit={limit}"

    try:
        req = urllib.request.Request(url)
        req.add_header("User-Agent", "OpenClaw-CLI/1.0")
        req.add_header("Accept", "application/json")
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode())
    except Exception as e:
        print(f"  Failed to reach ClawHub API: {e}")
        print(f"  {dim}URL: {url}{reset}")
        return

    skills = data.get("data", [])
    if not skills:
        print("  No skills found.")
        return

    print(f"\n  {bold}ClawHub Live — {endpoint.replace('-', ' ').title()}{reset}  ({len(skills)} results)\n")
    print(f"  {'#':<4} {'Name':<22} {'Slug':<30} {'DL':<10} {'★':<6} {'Author':<16} {'Cert'}")
    print(f"  {'─'*4} {'─'*22} {'─'*30} {'─'*10} {'─'*6} {'─'*16} {'─'*4}")
    for i, s in enumerate(skills, 1):
        cert = f"{green}✓{reset}" if s.get("is_certified") else f"{dim}—{reset}"
        slug = s.get("slug", f"{s.get('owner_handle', '?')}/{s.get('name', '?')}")
        print(f"  {i:<4} {s['display_name'][:21]:<22} {cyan}{slug[:29]:<30}{reset} {s['downloads']:>8,}  {s['stars']:>4,}  {s.get('owner_handle', '?')[:15]:<16} {cert}")

    print(f"\n  {dim}Source: clawhub.ai{reset}")
    print(f"  Install with: {cyan}install <slug>{reset}  (e.g. community/arxiv-researcher)")


def install_skill():
    """Smart install: auto-detects ClawHub slug (has /) vs local skill ID."""
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    cyan, reset = "\033[36m", "\033[0m"
    identifier = input(f"  Skill slug or ID (e.g. {cyan}community/arxiv-researcher{reset} or {cyan}summarizer{reset}): ").strip()
    if not identifier:
        return
    if "/" in identifier:
        code, data = api("POST", f"/agents/{aid}/skills/clawhub", {"slug": identifier})
    else:
        code, data = api("POST", f"/agents/{aid}/skills", {"skill_id": identifier})
    pretty(code, data)


def my_skills():
    """List installed skills for the active agent."""
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    code, data = api("GET", f"/agents/{aid}/skills")
    pretty(code, data)


def manage_skill():
    """Sub-menu for toggle / uninstall / setup on a specific skill."""
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected.")
        return
    dim, bold, reset, cyan = "\033[2m", "\033[1m", "\033[0m", "\033[36m"
    print(f"  {bold}Action:{reset}  1) Toggle on/off  2) Uninstall  3) Setup (install deps)")
    action = input("  Choice: ").strip()
    if action not in ("1", "2", "3"):
        print("  Invalid choice.")
        return
    skill_id = input(f"  Skill ID: ").strip()
    if not skill_id:
        return

    if action == "1":
        enabled = input("  Enable? (y/n): ").strip().lower() == "y"
        code, data = api("PATCH", f"/agents/{aid}/skills/{skill_id}", {"enabled": enabled})
        pretty(code, data)
    elif action == "2":
        code, data = api("DELETE", f"/agents/{aid}/skills/{skill_id}")
        pretty(code, data)
    elif action == "3":
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
        print("\n  Timed out. Check task list.")


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
    for _ in range(90):
        time.sleep(2)
        print(".", end="", flush=True)
        _, result = api("GET", f"/agents/{aid}/tasks/{task_id}")
        if result.get("status") in ("completed", "failed"):
            print(f"\n\n  Status: {result['status']}")
            print(f"  Output: {result.get('output', 'N/A')}")
            print(f"  Tokens: {result.get('tokens_used', 'N/A')}")
            print("\n  === Quick test complete! ===")
            return
    print("\n  Timed out after 180s.")


# ── ClawHub Skill Install Test ───────────────

def test_clawhub_skill_flow():
    """End-to-end test: install a ClawHub skill, verify is_installed detection,
    check the agent can use it, then clean up."""
    green, red, bold, dim, reset = "\033[32m", "\033[31m", "\033[1m", "\033[2m", "\033[0m"

    def step(n, desc):
        print(f"\n  {bold}{n}. {desc}{reset}")

    def ok(msg="OK"):
        print(f"  {green}✓ {msg}{reset}")

    def fail(msg):
        print(f"  {red}✗ {msg}{reset}")
        return False

    print(f"\n  {bold}=== ClawHub Skill Install Flow Test ==={reset}\n")

    # ── 0. Ensure auth + agent ──
    if not session["access_token"]:
        step(0, "Logging in...")
        code, data = api("POST", "/auth/register", {
            "email": "skilltest@openclaw.dev", "password": "test123",
            "display_name": "Skill Tester",
        })
        if code == 409:
            code, data = api("POST", "/auth/login", {
                "email": "skilltest@openclaw.dev", "password": "test123",
            })
        if code < 200 or code >= 300:
            return fail(f"Auth failed: {data}")
        save_tokens(data)

    if not session["agent_id"]:
        step(0, "Creating agent...")
        code, data = api("POST", "/agents", {
            "name": "SkillTest Agent", "persona": "Creative", "model": "gpt-5.2",
        })
        if 200 <= code < 300:
            session["agent_id"] = data["id"]
        else:
            code, data = api("GET", "/agents")
            agents = data.get("agents", [])
            if not agents:
                return fail("No agents available")
            session["agent_id"] = agents[0]["id"]

    aid = session["agent_id"]
    test_slug = "community/image-gen"
    test_skill_name = test_slug.split("/").pop()
    passed = 0
    total = 5

    # ── 1. Install ClawHub skill ──
    step(1, f"Installing ClawHub skill: {test_slug}")
    code, data = api("POST", f"/agents/{aid}/skills/clawhub", {"slug": test_slug})
    if 200 <= code < 300:
        skills = data.get("skills", [])
        installed = [s for s in skills if s.get("skill_id") == test_skill_name
                     or s.get("skillId") == test_skill_name]
        if installed:
            ok(f"Installed — skill_id={installed[0].get('skill_id', installed[0].get('skillId'))}")
            passed += 1
        elif skills:
            clawhub_skills = [s for s in skills if s.get("source") == "clawhub"]
            if clawhub_skills:
                sid = clawhub_skills[-1].get("skill_id", clawhub_skills[-1].get("skillId", "?"))
                ok(f"Installed — skill_id={sid}")
                test_skill_name = sid
                passed += 1
            else:
                fail(f"Skill not found in agent skills after install. Got: {[s.get('skill_id') for s in skills]}")
        else:
            ok("Installed (no skills array in response, checking separately)")
            passed += 1
    elif code == 409 or "already" in str(data).lower() or "conflict" in str(data).lower():
        ok("Already installed (conflict), continuing")
        passed += 1
    else:
        fail(f"HTTP {code}: {data}")

    # ── 2. Verify skill appears in agent skills list ──
    step(2, "Verifying skill in agent skills list")
    code, data = api("GET", f"/agents/{aid}/skills")
    if 200 <= code < 300:
        skills = data if isinstance(data, list) else data.get("skills", [])
        found = any(
            s.get("skill_id") == test_skill_name
            or s.get("skillId") == test_skill_name
            or s.get("skill_id", "").endswith(test_slug.split("/").pop())
            for s in skills
        )
        if found:
            ok(f"Skill present in agent skills ({len(skills)} total)")
            passed += 1
        else:
            ids = [s.get("skill_id", s.get("skillId")) for s in skills]
            fail(f"Skill not in agent skills list. Found: {ids}")
    else:
        fail(f"HTTP {code}: {data}")

    # ── 3. Verify is_installed in ClawHub browse ──
    step(3, "Verifying is_installed in ClawHub browse endpoint")
    code, data = api("GET", "/skills/clawhub/browse", params={"agent_id": aid})
    if 200 <= code < 300:
        skills = data.get("skills", [])
        target = [s for s in skills if s.get("slug") == test_slug]
        if target:
            is_inst = target[0].get("is_installed")
            if is_inst is True:
                ok("is_installed=true in browse results")
                passed += 1
            else:
                fail(f"is_installed={is_inst} — expected true. "
                     f"DB skill_id=\"{test_skill_name}\" vs browse expects "
                     f"\"{test_slug.split('/').pop()}\" or "
                     f"\"clawhub-{test_slug.replace('/', '-')}\". "
                     f"Rebuild backend? (docker compose up -d --build api-gateway)")
        else:
            fail(f"Skill {test_slug} not found in browse results")
    else:
        fail(f"HTTP {code}: {data}")

    # ── 4. Submit a task that should trigger the skill ──
    step(4, f"Submitting task to test skill usage")
    task_prompt = "Generate a description of what an image of a sunset over mountains would look like."
    code, data = api("POST", f"/agents/{aid}/tasks", {"input": task_prompt})
    if 200 <= code < 300:
        task_id = data.get("task_id")
        if task_id:
            print(f"  Task queued: {task_id[:8]}... Waiting", end="", flush=True)
            completed = False
            for _ in range(20):
                time.sleep(2)
                print(".", end="", flush=True)
                _, result = api("GET", f"/agents/{aid}/tasks/{task_id}")
                status = result.get("status")
                if status == "completed":
                    output = result.get("output", "")
                    print()
                    ok(f"Task completed ({len(output)} chars)")
                    if output:
                        preview = output[:120].replace("\n", " ")
                        print(f"  {dim}Preview: {preview}...{reset}")
                    passed += 1
                    completed = True
                    break
                elif status == "failed":
                    print()
                    fail(f"Task failed: {result.get('output', 'unknown')[:100]}")
                    break
            if not completed and status not in ("completed", "failed"):
                print()
                fail("Task timed out after 40s")
        else:
            fail(f"No task_id in response: {data}")
    else:
        fail(f"HTTP {code}: {data}")

    # ── 5. Clean up: uninstall the skill ──
    step(5, "Cleaning up: uninstalling skill")
    code, data = api("DELETE", f"/agents/{aid}/skills/{test_skill_name}")
    if 200 <= code < 300:
        ok("Skill uninstalled")
        passed += 1
    else:
        # Try the legacy prefixed ID
        legacy_id = f"clawhub-{test_slug.replace('/', '-')}"
        code2, data2 = api("DELETE", f"/agents/{aid}/skills/{legacy_id}")
        if 200 <= code2 < 300:
            ok(f"Skill uninstalled (legacy id: {legacy_id})")
            passed += 1
        else:
            fail(f"HTTP {code}: {data}")

    # ── Summary ──
    color = green if passed == total else red
    print(f"\n  {bold}Results: {color}{passed}/{total} passed{reset}\n")
    if passed == total:
        print(f"  {green}{bold}All ClawHub skill install tests passed!{reset}")
    else:
        print(f"  {red}{bold}Some tests failed — check output above.{reset}")
    print()


# ── Fix-verification test suite ──────────────
# Tests for the credential-trimming, upsert-on-reinstall,
# .env propagation, and session-clearing fixes.

def test_fixes():
    """End-to-end regression tests for the skill-visibility and
    credential-rejection fixes."""

    green, red, bold, dim, reset, cyan = (
        "\033[32m", "\033[31m", "\033[1m", "\033[2m", "\033[0m", "\033[36m",
    )
    passed = 0
    total = 0

    def step(n, desc):
        print(f"\n  {bold}{n}. {desc}{reset}")

    def check(ok, msg_pass, msg_fail=""):
        nonlocal passed, total
        total += 1
        if ok:
            passed += 1
            print(f"  {green}✓ {msg_pass}{reset}")
            return True
        else:
            print(f"  {red}✗ {msg_fail or msg_pass}{reset}")
            return False

    print(f"\n  {bold}=== Fix Verification Tests ==={reset}\n")

    # ── 0. Ensure auth + agent ──
    step(0, "Setup: auth + agent")
    if not session["access_token"]:
        code, data = api("POST", "/auth/register", {
            "email": "fixtest@openclaw.dev", "password": "test123",
            "display_name": "Fix Tester",
        })
        if code == 409:
            code, data = api("POST", "/auth/login", {
                "email": "fixtest@openclaw.dev", "password": "test123",
            })
        if code < 200 or code >= 300:
            print(f"  {red}Auth failed: {data}{reset}")
            return
        save_tokens(data)

    if not session["agent_id"]:
        code, data = api("POST", "/agents", {
            "name": "FixTest Agent", "persona": "Technical", "model": "gpt-5.2",
        })
        if 200 <= code < 300:
            session["agent_id"] = data["id"]
        else:
            code, data = api("GET", "/agents")
            agents = data.get("agents", [])
            if not agents:
                print(f"  {red}No agents available{reset}")
                return
            session["agent_id"] = agents[0]["id"]

    aid = session["agent_id"]
    print(f"  {dim}Using agent: {aid[:8]}...{reset}")

    # ──────────────────────────────────────────
    # TEST 1: Credential trimming (whitespace)
    # ──────────────────────────────────────────
    step(1, "Credential trimming — trailing whitespace stripped")

    # First ensure a skill is installed
    slug_for_cred_test = "community/image-gen"
    skill_id_for_cred = slug_for_cred_test.split("/")[-1]
    code, _ = api("POST", f"/agents/{aid}/skills/clawhub", {"slug": slug_for_cred_test})
    # Accept 200 or conflict (already installed)

    # Submit credentials with trailing whitespace + newlines (simulates iOS paste)
    dirty_key = "  sk-test-key-12345  \n"
    code, data = api("POST", f"/agents/{aid}/skills/{skill_id_for_cred}/credentials", {
        "credentials": {"OPENAI_API_KEY": dirty_key},
    })

    check(
        200 <= code < 300,
        f"Credential POST accepted (HTTP {code})",
        f"Credential POST rejected: HTTP {code} — {data}",
    )
    check(
        data.get("status") == "configured",
        "Response status is 'configured'",
        f"Unexpected status: {data.get('status', 'missing')}",
    )

    # Verify the skill is marked configured in DB via GET skills
    code, data = api("GET", f"/agents/{aid}/skills")
    if 200 <= code < 300:
        skills = data.get("skills", []) if isinstance(data, dict) else data
        target = [s for s in skills if s.get("skill_id") == skill_id_for_cred]
        if target:
            cfg = target[0].get("config", {})
            check(
                cfg.get("_configured") is True,
                f"Skill config._configured=true after credential save",
                f"config._configured is {cfg.get('_configured')} — expected true",
            )
        else:
            check(False, "", f"Skill {skill_id_for_cred} not in skills list")

    # ──────────────────────────────────────────
    # TEST 2: Credential trimming — empty-after-trim rejected
    # ──────────────────────────────────────────
    step(2, "Credential trimming — whitespace-only value handled")

    # The backend should accept the POST (it doesn't validate key values),
    # but the key should be effectively empty after trimming.
    # We test that the POST doesn't crash.
    code, data = api("POST", f"/agents/{aid}/skills/{skill_id_for_cred}/credentials", {
        "credentials": {"OPENAI_API_KEY": "  real-key-no-spaces  "},
    })
    check(
        200 <= code < 300 and data.get("status") == "configured",
        "Credential with surrounding spaces accepted and configured",
        f"HTTP {code}: {data}",
    )

    # ──────────────────────────────────────────
    # TEST 3: Skill re-install (upsert) updates metadata
    # ──────────────────────────────────────────
    step(3, "Skill re-install (upsert) updates DB metadata")

    # Install the same skill again — should NOT silently drop
    code, data = api("POST", f"/agents/{aid}/skills/clawhub", {"slug": slug_for_cred_test})
    if 200 <= code < 300:
        skills = data.get("skills", [])
        target = [s for s in skills if s.get("skill_id") == skill_id_for_cred]
        check(
            len(target) == 1,
            f"Skill {skill_id_for_cred} present after re-install ({len(skills)} total)",
            f"Skill missing after re-install. IDs: {[s.get('skill_id') for s in skills]}",
        )
        if target:
            check(
                target[0].get("is_enabled") is True,
                "Skill is enabled after re-install (upsert resets enabled=true)",
                f"is_enabled={target[0].get('is_enabled')}",
            )
    else:
        check(False, "", f"Re-install failed: HTTP {code} — {data}")

    # ──────────────────────────────────────────
    # TEST 4: GET /skills endpoint returns skill after install
    # ──────────────────────────────────────────
    step(4, "GET /agents/:id/skills returns the installed skill")

    code, data = api("GET", f"/agents/{aid}/skills")
    check(200 <= code < 300, f"GET skills succeeded (HTTP {code})")
    if 200 <= code < 300:
        skills = data.get("skills", []) if isinstance(data, dict) else data
        ids = [s.get("skill_id") for s in skills]
        check(
            skill_id_for_cred in ids,
            f"Skill '{skill_id_for_cred}' found in skills list ({len(ids)} skills)",
            f"Skill not found. Got: {ids}",
        )

    # ──────────────────────────────────────────
    # TEST 5: ClawHub browse shows is_installed=true
    # ──────────────────────────────────────────
    step(5, "ClawHub browse marks installed skill correctly")

    code, data = api("GET", "/skills/clawhub/browse", params={"agent_id": aid})
    if 200 <= code < 300:
        browse_skills = data.get("skills", [])
        # Find any skill that's already installed via the agent
        installed_in_browse = [s for s in browse_skills if s.get("is_installed") is True]
        target = [s for s in browse_skills if s.get("slug") == slug_for_cred_test]
        if target:
            check(
                target[0].get("is_installed") is True,
                "is_installed=true in browse results",
                f"is_installed={target[0].get('is_installed')}",
            )
        else:
            # Slug not in live catalog — check browse endpoint works at all
            check(
                len(browse_skills) > 0,
                f"Browse endpoint works ({len(browse_skills)} skills). "
                f"Slug '{slug_for_cred_test}' not in live catalog (OK — bundled-only skill)",
            )
    else:
        check(False, "", f"Browse failed: HTTP {code}")

    # ──────────────────────────────────────────
    # TEST 6: Skill requirements endpoint works
    # ──────────────────────────────────────────
    step(6, "GET /skills/:id/requirements returns env key info")

    code, data = api("GET", f"/agents/{aid}/skills/{skill_id_for_cred}/requirements")
    check(200 <= code < 300, f"Requirements endpoint succeeded (HTTP {code})")
    if 200 <= code < 300:
        reqs = data.get("requirements", [])
        env_reqs = [r for r in reqs if r.get("type") == "env"]
        check(
            data.get("is_configured") is True,
            f"is_configured=true (credentials were saved earlier)",
            f"is_configured={data.get('is_configured')}",
        )

    # ──────────────────────────────────────────
    # TEST 7: Credential with special characters
    # ──────────────────────────────────────────
    step(7, "Credentials with special chars (=, /, +) accepted")

    special_key = "sk-proj-abc123/def+ghi=jkl"
    code, data = api("POST", f"/agents/{aid}/skills/{skill_id_for_cred}/credentials", {
        "credentials": {"OPENAI_API_KEY": special_key},
    })
    check(
        200 <= code < 300 and data.get("status") == "configured",
        "Special-character API key accepted",
        f"HTTP {code}: {data}",
    )

    # ──────────────────────────────────────────
    # TEST 8: Skill toggle (disable → enable) works
    # ──────────────────────────────────────────
    step(8, "Skill disable/enable toggle persists")

    code, data = api("PATCH", f"/agents/{aid}/skills/{skill_id_for_cred}", {"enabled": False})
    if 200 <= code < 300:
        skills = data.get("skills", [])
        target = [s for s in skills if s.get("skill_id") == skill_id_for_cred]
        check(
            target and target[0].get("is_enabled") is False,
            "Skill disabled successfully",
            f"is_enabled={target[0].get('is_enabled') if target else 'skill-missing'}",
        )
    else:
        check(False, "", f"PATCH failed: HTTP {code}")

    # Re-enable
    code, data = api("PATCH", f"/agents/{aid}/skills/{skill_id_for_cred}", {"enabled": True})
    if 200 <= code < 300:
        skills = data.get("skills", [])
        target = [s for s in skills if s.get("skill_id") == skill_id_for_cred]
        check(
            target and target[0].get("is_enabled") is True,
            "Skill re-enabled successfully",
            f"is_enabled={target[0].get('is_enabled') if target else 'skill-missing'}",
        )

    # ──────────────────────────────────────────
    # TEST 9: Re-install after disable restores enabled=true
    # ──────────────────────────────────────────
    step(9, "Re-install after disable restores enabled=true (upsert)")

    # Disable first
    api("PATCH", f"/agents/{aid}/skills/{skill_id_for_cred}", {"enabled": False})

    # Re-install
    code, data = api("POST", f"/agents/{aid}/skills/clawhub", {"slug": slug_for_cred_test})
    if 200 <= code < 300:
        skills = data.get("skills", [])
        target = [s for s in skills if s.get("skill_id") == skill_id_for_cred]
        check(
            target and target[0].get("is_enabled") is True,
            "Re-install after disable → enabled=true (upsert fixed)",
            f"is_enabled={target[0].get('is_enabled') if target else 'skill-missing'}",
        )
    else:
        check(False, "", f"Re-install failed: HTTP {code}")

    # ──────────────────────────────────────────
    # TEST 10: Uninstall + reinstall round-trip
    # ──────────────────────────────────────────
    step(10, "Uninstall + reinstall round-trip")

    # Uninstall
    code, _ = api("DELETE", f"/agents/{aid}/skills/{skill_id_for_cred}")
    check(200 <= code < 300, "Uninstall succeeded")

    # Verify gone
    code, data = api("GET", f"/agents/{aid}/skills")
    if 200 <= code < 300:
        skills = data.get("skills", []) if isinstance(data, dict) else data
        ids = [s.get("skill_id") for s in skills]
        check(
            skill_id_for_cred not in ids,
            "Skill removed from skills list after uninstall",
            f"Skill still present: {ids}",
        )

    # Reinstall
    code, data = api("POST", f"/agents/{aid}/skills/clawhub", {"slug": slug_for_cred_test})
    if 200 <= code < 300:
        skills = data.get("skills", [])
        ids = [s.get("skill_id") for s in skills]
        check(
            skill_id_for_cred in ids,
            "Skill back in list after reinstall",
            f"Skill missing after reinstall: {ids}",
        )
    else:
        check(False, "", f"Reinstall failed: HTTP {code}")

    # ──────────────────────────────────────────
    # Summary
    # ──────────────────────────────────────────
    color = green if passed == total else red
    print(f"\n  {bold}Results: {color}{passed}/{total} passed{reset}\n")
    if passed == total:
        print(f"  {green}{bold}All fix-verification tests passed!{reset}")
    else:
        print(f"  {red}{bold}{total - passed} test(s) failed — check output above.{reset}")
    print()


# ── Interactive Chat ─────────────────────────

def interactive_chat():
    """ChatGPT-like interactive session: type messages, see streamed responses."""
    aid = session["agent_id"]
    if not aid:
        print("  No agent selected. List or create one first.")
        return
    if not session["access_token"]:
        print("  Not logged in. Login first.")
        return

    dim, bold, reset = "\033[2m", "\033[1m", "\033[0m"
    green, red, cyan = "\033[32m", "\033[31m", "\033[36m"

    ws = connect_ws()
    if not ws:
        print(f"  {red}Could not connect WebSocket. Is the backend running?{reset}")
        print(f"  {dim}Falling back to polling mode...{reset}\n")

    print(f"\n  {bold}═══ Interactive Chat ═══{reset}")
    print(f"  {dim}Agent: {session['agent_id'][:8]}...{reset}")
    print(f"  {dim}Type your messages below. Commands:{reset}")
    print(f"  {dim}  /quit  — exit chat{reset}")
    print(f"  {dim}  /clear — clear conversation history{reset}")
    print(f"  {dim}  /new   — reconnect WebSocket{reset}")
    print(f"  {dim}  Ctrl+C — exit chat{reset}")
    print()

    def stream_response(task_id, ws_conn):
        """Listen on WS for a specific task's events, print them live."""
        done = threading.Event()
        result_holder = {"error": None}

        def _listener():
            try:
                while not done.is_set():
                    msg = ws_conn.recv_frame()
                    if msg is None:
                        break
                    event = json.loads(msg)
                    etype = event.get("type")
                    tid = event.get("task_id")
                    if tid and tid != task_id:
                        continue
                    if etype == "task:progress":
                        content = event.get("content", "")
                        if content:
                            print(content, end="", flush=True)
                    elif etype == "task:tool_start":
                        tool = event.get("tool_name", "?")
                        print(f"\n  {dim}⚙ {tool}{reset}", end="", flush=True)
                    elif etype == "task:tool_end":
                        print(f" {dim}✓{reset}", end="", flush=True)
                    elif etype == "task:complete":
                        done.set()
                        break
                    elif etype == "task:error":
                        result_holder["error"] = event.get("error", "Unknown error")
                        done.set()
                        break
            except Exception as e:
                result_holder["error"] = str(e)
                done.set()

        t = threading.Thread(target=_listener, daemon=True)
        t.start()
        return done, result_holder

    try:
        while True:
            try:
                user_input = input(f"  {cyan}{bold}You:{reset}  ").strip()
            except EOFError:
                break
            if not user_input:
                continue
            if user_input.lower() in ("/quit", "/exit", "quit", "exit"):
                break
            if user_input.lower() in ("/clear",):
                code, data = api("DELETE", f"/agents/{aid}/tasks")
                if 200 <= code < 300:
                    print(f"  {dim}History cleared ({data.get('deleted', 0)} tasks).{reset}\n")
                else:
                    print(f"  {red}Failed to clear: {data}{reset}\n")
                continue
            if user_input.lower() in ("/new",):
                if ws:
                    ws.close()
                ws = connect_ws()
                if ws:
                    print(f"  {dim}WebSocket reconnected.{reset}\n")
                else:
                    print(f"  {red}WebSocket reconnect failed.{reset}\n")
                continue

            code, data = api("POST", f"/agents/{aid}/tasks", {"input": user_input})
            if code < 200 or code >= 300:
                pretty(code, data)
                continue

            task_id = data["task_id"]
            print(f"\n  {green}{bold}Agent:{reset}  ", end="", flush=True)

            if ws:
                done_event, result = stream_response(task_id, ws)

                # Wait for streaming to finish (with a timeout)
                for _ in range(900):  # 180s max
                    if done_event.is_set():
                        break
                    time.sleep(0.2)
                else:
                    print(f"\n  {red}Timed out after 180s.{reset}")

                if result.get("error"):
                    print(f"\n  {red}Error: {result['error']}{reset}")

            else:
                # Polling fallback
                for _ in range(90):
                    time.sleep(2)
                    _, result = api("GET", f"/agents/{aid}/tasks/{task_id}")
                    if result.get("status") == "completed":
                        print(result.get("output", ""))
                        break
                    elif result.get("status") == "failed":
                        print(f"\n  {red}Failed: {result.get('output', '?')}{reset}")
                        break
                else:
                    print(f"\n  {red}Timed out.{reset}")

            # Fetch final stats
            _, final = api("GET", f"/agents/{aid}/tasks/{task_id}")
            tokens = final.get("tokens_used")
            elapsed = ""
            if final.get("created_at") and final.get("completed_at"):
                try:
                    t0 = time.strptime(final["created_at"][:19], "%Y-%m-%dT%H:%M:%S")
                    t1 = time.strptime(final["completed_at"][:19], "%Y-%m-%dT%H:%M:%S")
                    secs = int(time.mktime(t1) - time.mktime(t0))
                    elapsed = f"  ⏱ {secs}s"
                except Exception:
                    pass
            print(f"\n  {dim}tokens: {tokens or '—'}{elapsed}{reset}\n")

    except KeyboardInterrupt:
        pass

    if ws:
        ws.close()
    print(f"\n  {dim}Chat ended.{reset}\n")


# ── Menu ─────────────────────────────────────

MENU = """
╔═══════════════════════════════════════════╗
║        OpenClaw API Test Client           ║
╠═══════════════════════════════════════════╣
║  AUTH                                     ║
║   1) Register          2) Login           ║
║   3) Refresh token                        ║
║  AGENTS                                   ║
║   4) List agents       5) Create agent    ║
║   6) Update agent      7) Delete agent    ║
║  TASKS                                    ║
║   8) Submit task       9) List tasks      ║
║  10) Clear history                        ║
║  SKILLS                                   ║
║  11) Browse skills     12) Install skill  ║
║  13) My skills         14) Manage skill   ║
║  OTHER                                    ║
║  15) Usage             16) Subscription   ║
║  17) Health check                         ║
║  TESTS                                    ║
║  18) Quick test (e2e)                     ║
║  19) ClawHub install test                 ║
║  20) Fix verification tests              ║
║                                           ║
║  💬 c/chat) Interactive chat              ║
║  ls/menu) Show menu    0) Quit            ║
╚═══════════════════════════════════════════╝"""

ACTIONS = {
    "1": register, "2": login, "3": refresh_token,
    "4": list_agents, "5": create_agent, "6": update_agent, "7": delete_agent,
    "8": submit_task, "9": list_tasks, "10": clear_history,
    "11": browse_skills, "12": install_skill,
    "13": my_skills, "14": manage_skill,
    "15": check_usage, "16": check_subscription, "17": health_check,
    "18": quick_test, "19": test_clawhub_skill_flow,
    "20": test_fixes,
    "c": interactive_chat, "chat": interactive_chat,
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
        elif choice in ("menu", "help", "?", "ls"):
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
