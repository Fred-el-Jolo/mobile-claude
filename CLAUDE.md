# Mobile Claude — Home-Hosted Architecture

> Run the AI agent on a Raspberry Pi at home, always on, reachable from mobile over **Tailscale**.
> Replaces the earlier OVH ephemeral-cloud approach (see git history on `main` if that's ever needed again).

> ⚠️ This doc is reconstructed from real shell history on the already-configured Pi. Two components —
> **moshi-hook** (getmoshi.app) and **pi** (pi.dev) — are described here by what the commands do
> (pairing, systemd service, auth config), not from vendor docs. Correct me if a role below is wrong.

---

## Problem Decomposition

| Layer | Question | Answer |
|---|---|---|
| **Compute** | Where does the agent run? | A Raspberry Pi at home — always on, no cold start |
| **Connectivity** | How does mobile reach it? | Tailscale (private mesh network) + `moshi-hook` remote-control bridge |
| **State** | What persists between sessions? | Everything, on the Pi's own disk — nothing ephemeral, nothing to sync |
| **Lifecycle** | How do sessions start/stop? | Nothing to start/stop — the agent bridge runs as a `systemd --user` service with lingering enabled, boots with the Pi |

The old OVH doc solved a problem this setup doesn't have: paying per-minute for compute and syncing state in and out of an ephemeral box. A Pi sitting at home removes that whole layer — the only real work is **getting to it securely from a phone**, which is what Tailscale + moshi-hook do.

---

## Architecture

```
[Phone]
   |
   |  Tailscale (private WireGuard mesh — MagicDNS hostname, no open ports)
   |
   ├── moshi-hook bridge ──→ paired mobile app session ──→ agent running in tmux on the Pi
   |        (primary path — no terminal app needed)
   |
   └── mosh / ssh (fallback) ──→ raw terminal on the Pi
                                       |
                                  [Raspberry Pi — jolo@]
                                       |
                                  tmux session (persistent, survives disconnects)
                                       |
                                  `pi` agent CLI  (~/.pi/agent/auth.json)
```

Two independent access paths, both riding on Tailscale:

1. **moshi-hook** — the primary path. A relay/bridge service, paired once via a pairing token, running as a persistent `systemd --user` service on the Pi. Lets a mobile app attach to and drive an agent session without a terminal emulator — the mobile equivalent of what the old doc called "Remote Control."
2. **mosh + ssh** — the fallback path, for when you want a raw shell. `mosh` survives network changes (WiFi ↔ mobile data) and sleep/wake better than plain SSH, at the cost of needing a real terminal app on the phone.

`tmux` sits underneath both: the actual agent process lives in a tmux session so it keeps running (and stays attachable) regardless of which access path connects to it, or whether anything is connected at all.

---

## Component Roles

| Component | Role | Source |
|---|---|---|
| **Tailscale** | Private mesh network — the Pi gets a stable MagicDNS hostname reachable from the phone with no port-forwarding or public exposure | `tailscale.com/install.sh` |
| **mosh** | Resilient terminal fallback for direct shell access | `apt install mosh` |
| **moshi-hook** | Remote-control bridge — pairs the Pi to a mobile app via token; runs as a `systemd --user` service | `getmoshi.app/install.sh` |
| **tmux** | Keeps the agent session alive and attachable across reconnects | `apt install tmux` |
| **git + ssh (ed25519)** | Repo access / identity for the agent's work | `ssh-keygen` |
| **nvm + Node.js** | Runtime the agent CLI depends on | `nvm-sh/nvm` installer |
| **pi** (agent CLI) | The AI agent itself; config/auth at `~/.pi/agent/auth.json` | `pi.dev/install.sh` |

---

## Setup Procedure (from scratch)

Run everything below as the Pi's normal user (`jolo` in this build), not root, except where `sudo` is called out.

### Phase 1 — Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --hostname=rpi-agent
```

Confirm the Pi shows up in the tailnet admin console, then confirm reachability from the phone's Tailscale app before doing anything else — every later step assumes this works.

### Phase 2 — mosh (terminal fallback)

```bash
sudo apt update
sudo apt install -y mosh
```

No config needed — `mosh <tailscale-hostname>` from the phone's SSH client works once the Pi's own SSH key auth is set up (Phase 4) and mosh's UDP range isn't blocked (irrelevant here since it all rides the Tailscale tunnel).

### Phase 3 — moshi-hook (remote-control bridge)

```bash
curl -fsSL https://getmoshi.app/install.sh | sh
moshi-hook pair --token <PAIRING_TOKEN>   # get a fresh token from the moshi mobile app/dashboard — don't reuse an old one
```

Run it as a persistent user service so it survives reboots and SSH logouts without needing an active login session:

```bash
mkdir -p ~/.config/systemd/user/
nano ~/.config/systemd/user/moshi-hook.service
```

```ini
[Unit]
Description=moshi-hook remote control bridge
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
ExecStart=%h/.local/bin/moshi-hook serve
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

> Adjust `ExecStart` to wherever the installer actually put the binary — check with `which moshi-hook`.

```bash
chmod 644 ~/.config/systemd/user/moshi-hook.service
systemctl --user daemon-reload
systemctl --user enable --now moshi-hook.service
loginctl enable-linger jolo     # critical: without this, the service dies the moment the SSH session that started it ends
systemctl --user status moshi-hook.service
```

Once it's confirmed running (`ps aux | grep moshi`, or the systemd status is `active (running)`), finish registration:

```bash
moshi-hook install
```

**Gotchas hit during the real setup (keep these in mind if it breaks again):**
- `systemctl --user` never takes `sudo` — running `sudo systemctl --user ...` silently targets root's user instance, not yours, and looks like it worked while doing nothing. If status looks wrong, check you didn't `sudo` it.
- A service file with wrong permissions (not `644`) gets silently skipped by systemd — `chmod 644` after every edit if `daemon-reload` doesn't pick up changes.
- `loginctl enable-linger <user>` is what makes the service outlive your SSH session — without it, everything looks fine while you're connected and dies the moment you disconnect.
- After any edit to the `.service` file: `systemctl --user daemon-reload` before `start`/`restart`, every time.

### Phase 4 — git & SSH identity

```bash
sudo apt install -y git
ssh-keygen -t ed25519 -C "guillaume.frederic@gmail.com"
cat ~/.ssh/id_ed25519.pub    # add to GitHub (or wherever repos live)
```

### Phase 5 — Node.js via nvm

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash
# reload shell, then:
nvm install node
node -v
```

### Phase 6 — agent CLI (`pi`)

```bash
curl -fsSL https://pi.dev/install.sh | sh
pi   # first run — follow prompts
```

Auth/config lives at `~/.pi/agent/auth.json` — edit directly if you need to rotate credentials:

```bash
nano ~/.pi/agent/auth.json
```

### Phase 7 — tmux persistent session

```bash
sudo apt install -y tmux
nano ~/.tmux.conf
```

Start the agent inside a named tmux session so it's always attachable via moshi-hook or a plain SSH+tmux fallback:

```bash
tmux new -s agent
pi
# detach with Ctrl-b d — the agent keeps running
```

---

## Daily Usage

1. Open Tailscale on the phone — confirm the Pi is reachable.
2. Open the moshi mobile app — it should reconnect to the already-running `moshi-hook` service and drop you into the `agent` tmux session.
3. Fallback if moshi-hook is misbehaving: SSH (or `mosh`) to the Pi's Tailscale hostname, `tmux attach -t agent`.
4. Push notifications arrive via moshi-hook when the agent stops or needs attention — no polling required.

Nothing to tear down at the end of a session — the Pi just keeps running.

---

## Security Model

- **No open ports** — everything rides the Tailscale tunnel; the Pi is not reachable from the public internet.
- **SSH key auth only**, no password auth.
- **moshi-hook pairing token** — treat it like a credential. The token used during initial setup was pasted in plaintext into a shell session that got logged; **rotate it** if that history is retained anywhere outside this machine.
- **`loginctl enable-linger`** keeps the bridge running without a logged-in session — verify this is scoped to the single `jolo` user, not broadened further.

---

## Project Files

```
~/dev/mobile-claude/
└── CLAUDE.md              ← this file
```
