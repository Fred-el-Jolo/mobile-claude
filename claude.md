# Mobile Claude — Architecture Plan

> Launch Claude Code sessions from mobile phone, no always-on home machine.
> Cloud provider: **OVH Public Cloud**

---

## Problem Decomposition (First Principles)

The problem has 4 independent layers:

| Layer | Question | Answer |
|---|---|---|
| **Compute** | Where does Claude Code run? | Remote Linux container/VM |
| **Connectivity** | How does mobile reach compute? | SSH (launch only) + Claude Remote Control |
| **State** | What persists between sessions? | Dotfiles, API keys, projects |
| **Lifecycle** | How do sessions start/stop? | Script: create → SSH launch claude → RC → sync → destroy |

**Key insight from First Principles analysis:**
The assumption "cloud terminal = full VM" introduces unnecessary cold-start latency. Claude Code needs only 2GB RAM, a bash shell, and network access. OVH's smallest instance (d2-2) satisfies this at €0.0119/hr — and cold start can be reduced to 30–60s using a pre-baked snapshot image.

---

## Architecture Options

### Option A — OVH Ephemeral Instance (RECOMMENDED)

**How it works:**
1. Run `./start-session.sh [session-name]` (from any machine or mobile trigger)
2. OVH d2-2 instance created from pre-baked snapshot (~30–60s)
3. Cloud-init restores state from OVH Object Storage
4. Script SSHs in and runs `echo 'y' | claude --name '<session-name>'`
5. Scan QR or open Claude mobile app → connect via Remote Control
6. Work entirely from Claude mobile app — no terminal emulator needed
7. On exit: state synced to Object Storage → instance deleted via API

**Specs (d2-2):**
- 1 vCPU, 2 GB RAM, 25 GB NVMe SSD
- 100 Mbps network, 15 regions available
- Price: **€0.0119/hr** (~€0.71/month for 2hr/day of sessions)

**Pros:**
- True pay-per-use — no idle cost
- Full Linux environment, Claude Code works perfectly
- OVH REST API + OpenStack CLI for full programmatic control
- EU-based (GDPR, data sovereignty)
- Pre-baked snapshot means fast cold start

**Cons:**
- 30–60s cold start (reduced with snapshot, not eliminated)
- Requires a small automation script for lifecycle management
- OVH API key management needed

---

### Option B — OVH VPS Persistent (Always-On Baseline)

**How it works:** Just an always-on VPS. SSH in anytime.

- Price: **€6.49/month** (VPS-1: 4 vCPU, 8 GB RAM, 75 GB SSD)
- Cold start: **0s** — it's always running
- **Verdict:** Contradicts the no-always-on constraint. Simple but wasteful.

---

### Option C — GitHub Codespaces (Non-OVH Comparison)

**How it works:** GitHub-managed cloud dev environment with browser terminal.

- Price: **~$0.18/hr** (2-core machine) — ~15x more expensive than OVH d2-2
- Cold start: **20–30s** (fast, uses pre-warmed containers)
- Mobile UX: browser terminal (works, but no Mosh — depends on network stability)
- **Verdict:** Easiest setup, but 15x more expensive per hour. No OVH integration.

---

### Option D — Mobile Claude API Client (No Terminal)

**How it works:** Use Claude's API directly from a mobile app — no terminal at all.

- Price: **$0 infra** (just API token costs)
- Cold start: **0s**
- **Verdict:** No Claude *Code* (file editing, tools, MCP). Only conversational Claude.
  Use as fallback for quick questions, not primary dev workflow.

---

### Option E — OVH Ephemeral + Pre-Baked Snapshot (RECOMMENDED VARIANT)

Same as Option A but with a maintained custom OVH image:

- Claude Code pre-installed
- Node.js, git, common tools pre-installed
- Dotfiles baked in as defaults (secrets still pulled from Object Storage at runtime)
- Cold start: **~30s** instead of 90–120s

**This is the ideal production form of the recommendation.**

---

## Comparison Table

| Approach | Cost/Month* | Cold Start | Mobile UX | Maintenance | Always-On? |
|---|---|---|---|---|---|
| **OVH d2-2 Ephemeral** ✅ | ~€0.71 | 60–120s | Claude RC app ✓ | Low | No |
| **OVH d2-2 + Snapshot** ✅✅ | ~€0.71 + €0.02 img | **30–60s** | Claude RC app ✓ | Medium | No |
| OVH VPS (always-on) | €6.49 | 0s | Claude RC app ✓ | Low | **YES** |
| GitHub Codespaces | ~$7–15 | 20–30s | Browser | None | No |
| Mobile API client | ~$0 infra | 0s | Native app | None | No |

*Estimate: 2hr/day of active sessions, 20 working days/month

---

## Recommended Architecture

**OVH Public Cloud d2-2 + OVH Object Storage + Pre-Baked Snapshot + Claude Remote Control**

### Why this wins:
1. **€0.0119/hr** — cheapest viable compute for Claude Code on any major cloud
2. **No idle cost** — instance only exists during your session
3. **OVH API** gives full programmatic control (create, start, stop, delete)
4. **Object Storage S3** at €0.007/GB/month for state — pennies for dotfiles
5. **Claude Remote Control** (Pro+Max) — no terminal emulator needed on mobile; Claude mobile app is the interface
6. **EU-based** — no US data exposure

### Architecture Diagram

```
[Android / iOS]
   |
   | start-session.sh [session-name]
   | → OVH API → Create d2-2 instance from snapshot
   |                    |
   |              cloud-init runs:
   |              - Pull ~/.claude from OVH Object Storage
   |              - Pull API keys from OVH Object Storage
   |
   | SSH (one-time, launch only)
   |————————————————————→ [d2-2 instance]
   |                           |
   |                      echo 'y' | claude --name '<session-name>'
   |                           |
   |                      Claude RC bridge (Anthropic encrypted relay)
   |                           |
   | Claude mobile app ←———————┘
   |    (all work done here, no terminal needed)
   |
   On session end (from mobile app or end-session.sh):
   - Sync state → OVH Object Storage
   - Self-delete via OVH API
```

---

## State Persistence Strategy

Everything that needs to survive between sessions lives in **OVH Object Storage S3**.

### What to persist:
```
s3://mobile-claude-state/
├── dotfiles/
│   ├── .gitconfig
│   ├── .claude/           ← Claude Code config, conversations
│   ├── .bashrc / .zshrc
│   └── .ssh/
│       └── id_rsa.pub     ← Public key only (private stays on phone)
├── env/
│   └── secrets.env.enc    ← Encrypted env vars (ANTHROPIC_API_KEY, etc.)
└── projects/              ← Optional: small project state (or use git repos)
```

### Sync commands (in cloud-init / session teardown):
```bash
# Restore (on instance start)
aws s3 sync s3://mobile-claude-state/dotfiles/ ~/  --exact-timestamps

# Save (on session end)
aws s3 sync ~/ s3://mobile-claude-state/dotfiles/ \
  --exclude "*" \
  --include ".gitconfig" \
  --include ".claude/*" \
  --include ".bashrc"
```

---

## Lifecycle Automation

### Session Start

```bash
# Usage: ./start-session.sh [session-name]
# SESSION_NAME defaults to "mobile-claude" if omitted
./start-session.sh my-work-session
```

The script:
1. Creates d2-2 instance from snapshot
2. Waits for SSH to become available
3. SSHs in and runs `echo 'y' | claude --name '<session-name>'`
4. Claude prints a QR code / connect link → open Claude mobile app to take over

See `scripts/start-session.sh` for the full implementation.

### Session End (runs inside the instance)

```bash
#!/bin/bash
# end-session.sh — run before disconnecting

# Sync state to Object Storage
aws s3 sync ~/.claude/ s3://mobile-claude-state/dotfiles/.claude/
aws s3 sync ~/ s3://mobile-claude-state/dotfiles/ \
  --exclude "*" --include ".gitconfig" --include ".bashrc" --include ".zshrc"

# Self-destruct
INSTANCE_ID=$(curl -s http://169.254.169.254/openstack/latest/meta_data.json | python3 -c "import sys,json; print(json.load(sys.stdin)['uuid'])")
openstack server delete $INSTANCE_ID
echo "Instance deleted. Session complete."
```

### Auto-Destroy Failsafe (OVH Workflow Management)

Use OVH Workflow Management (free) to schedule a hard-kill after 4 hours:
- Prevents runaway billing if you forget to run end-session.sh
- Set via OVH Console or API when creating the instance

---

## Mobile Client Setup

### Recommended: Claude Mobile App + Remote Control (Pro/Max plan)

Claude Code's **Remote Control** feature bridges the cloud instance directly to the Claude iOS/Android app. No terminal emulator needed on mobile.

**How it works:**
- `start-session.sh` SSHs into the VM and launches `claude --name '<session-name>'`
- `echo 'y'` auto-confirms the RC session prompt
- Claude displays a QR code / deep link → open in Claude mobile app
- All further work (chat, tool calls, file edits) happens in the app
- The SSH connection on the host machine stays open to keep Claude Code running (or use tmux/screen to detach)

**Resilience:** RC uses an HTTP/WebSocket bridge through Anthropic's relay — survives IP changes, mobile sleep, and WiFi↔4G switches natively.

### SSH client (needed only to launch sessions)

Any SSH client works for the one-time launch step:
- **Termius** (iOS/Android) — clean UI, free tier sufficient for launch-only use
- **Termux** (Android) — full terminal if you ever need direct shell access
- From a laptop/desktop — `./start-session.sh` handles everything automatically

---

## Implementation Steps

### Phase 1 — Foundation (1–2 hours)

1. **Create OVH Public Cloud project** at console.ovhcloud.com
2. **Generate OVH API credentials** (Application Key + Secret + Consumer Key)
3. **Add SSH key** to OVH project (use the public key from your phone)
4. **Create Object Storage S3 bucket**: `mobile-claude-state`
5. **Install OpenStack CLI** via venv: `python -m venv .venv && pip install python-openstackclient`
   - **Init venv before every openstack command:** `. .venv/bin/activate.fish`
6. **Verify API access**: `openstack server list` (should return empty list)

### Phase 2 — First Ephemeral Instance (30 min)

1. Launch a d2-2 instance manually from OVH console
2. SSH in: `ssh ubuntu@<ip>`
3. Install Claude Code: `npm install -g @anthropic-ai/claude-code` (or per current docs)
4. Configure: set ANTHROPIC_API_KEY, run `claude` once to verify
5. Set up state sync scripts (from the Architecture section above)
6. Test Object Storage sync: `aws s3 ls s3://mobile-claude-state/`

### Phase 3 — Snapshot Creation (15 min)

1. From OVH console, create a snapshot of the configured instance
2. Note the snapshot ID
3. Delete the manual instance
4. Test: launch new d2-2 from snapshot, verify Claude Code works immediately

### Phase 4 — Mobile Client Setup (15 min)

1. Ensure Claude mobile app is installed (iOS or Android) on a Pro or Max plan account
2. Install any SSH client for the one-time launch step (Termius recommended for mobile)
3. Run `./start-session.sh test-session` — script will SSH in and launch Claude with RC
4. Scan the QR code / tap the deep link in the Claude mobile app
5. Verify you can send messages and see tool calls executing on the VM

### Phase 5 — Lifecycle Automation (1 hour)

1. Create `start-session.sh` and `end-session.sh` from templates above
2. Configure OVH Workflow Management: auto-kill after 4 hours
3. (Optional) HTTP Shortcuts / Tasker → webhook → trigger start-session.sh remotely
4. Test full cycle: start → work → end → verify instance deleted

---

## Cost Estimate

| Item | Rate | Monthly (2hr/day, 20 days) |
|---|---|---|
| OVH d2-2 compute | €0.0119/hr | **€0.48** |
| OVH Object Storage | €0.007/GB/mo | **~€0.01** (100MB state) |
| OVH snapshot storage | ~€0.01/GB/mo | **~€0.25** (25GB image) |
| Claude Remote Control | included in Pro/Max | **€0** |
| **Total** | | **~€0.75/month** |

Compare: GitHub Codespaces for same usage ≈ $7–15/month.

---

## Security Model

- **SSH key auth only** — no password auth on instances
- **API keys encrypted** in Object Storage (use `age` or `gpg` encryption)
- **Firewall**: OVH Security Groups — allow SSH TCP/22 + Mosh UDP/60000-61000; RC uses outbound HTTPS/WSS (no inbound ports needed)
- **Ephemeral instances** — no persistent attack surface
- **Private key stays on phone** — never transmitted to cloud

---

## Project Files

```
~/dev/mobile-claude/
├── ARCHITECTURE.md          ← This file
├── scripts/
│   ├── start-session.sh     ← Create instance + connect
│   ├── end-session.sh       ← Sync state + destroy instance
│   └── setup-instance.sh    ← cloud-init bootstrap script
├── cloud-init/
│   └── init.yaml            ← OVH cloud-init config
└── terraform/               ← Optional: IaC for full automation
    └── main.tf
```
