# TODO — RPi AI Host Hardening

## Backup (state lives only on the Pi's disk)

Data to protect is small: `~/.pi/agent/auth.json`, repos, dotfiles — a few GB, not media-scale. Budget tiers:

- **0€** — `rsync`/`restic` to a laptop/desktop you already own, over Tailscale, via cron. No spend, but only as safe as that machine.
- **~1-2€/month** — Backblaze B2 or rsync.net (smallest plan) + `restic`, encrypted and incremental. At this data size the bill is close to free. Off-site, so it survives theft/fire — a same-location NAS doesn't.
- **~40-60€ one-time** — USB HDD/SSD plugged into the Pi or another home device (can reuse the SSD from the USB-boot item below). Local-only backup, no off-site protection, but a real step up from nothing.
- **150-200€+** — entry NAS (e.g. Synology DS223j). **Not worth it for this alone** — a few GB of configs/repos doesn't justify a dedicated NAS. Only makes sense if you want one anyway for other stuff (photos, media).

**Recommendation:** skip the NAS. Backblaze B2/rsync.net + `restic` is the right <100€ spend — actually under 5€/year at this data volume — and it's the only option here that also survives something happening to the house, not just the SD card.

## Unattended security upgrades

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades   # select "Yes"
```

Raspberry Pi OS (Bullseye+) already ships correct origins in `/etc/apt/apt.conf.d/50unattended-upgrades` — just confirm the file isn't empty after.

## USB SSD boot (Pi 4B)

- **Feasible**: yes, natively — Pi 4B has supported USB boot since the 2020 bootloader update; most units shipped since already have current firmware (check with `sudo rpi-eeprom-update`).
- **Budget**: ~35-60€ total — e.g. Crucial BX500 240GB SSD (~25€) + USB3 UASP enclosure (~12€), or an all-in-one USB3 external SSD (Crucial X6 / SanDisk, ~45-55€ for 500GB).
- **Steps**: flash Raspberry Pi OS straight to the SSD (Raspberry Pi Imager, pick the SSD as target) → `raspi-config` → Advanced → Boot Order → USB Boot → boot with the SD card removed. Also removes the SD-card-wear risk from long-running services.

## `tailscale up --ssh` — ✅ DONE

- On the Pi: add `--ssh` to the existing invocation — `sudo tailscale up --hostname=rpi-agent --ssh`.
- From any device on your tailnet: `tailscale ssh jolo@rpi-agent` — authenticates via Tailscale identity, no key exchange needed.
- Independent of moshi-hook: moshi-hook is the app-level bridge into the tmux session; `tailscale ssh` only replaces the key-based auth on the "mosh/ssh fallback" path. Keep the `ed25519` key regardless — `mosh` bootstraps over classic SSH and doesn't go through Tailscale's SSH layer.

## Temp / throttle alerting

No `ntfy` on the Pi at all anymore — route through the same moshi-hook webhook that already delivers agent notifications, via a plain system-level cron script (decoupled from Claude Code, just a curl call):

```bash
# ~/.config/moshi-hook/token.env — chmod 600, NOT committed to this repo
export MOSHI_TOKEN="your-api-token"
```

```bash
# /home/jolo/bin/check-throttle.sh, run every 15 min via cron
source ~/.config/moshi-hook/token.env
T=$(vcgencmd get_throttled)
[ "$T" != "throttled=0x0" ] && curl -s -X POST https://api.getmoshi.app/api/webhook \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$MOSHI_TOKEN\",\"title\":\"Pi throttled\",\"message\":\"$T\"}"
```

Catches thermal/undervoltage throttling. It won't catch a fully hung/crashed Pi though — if that ever matters, a free Healthchecks.io "dead man's switch" (Pi pings it every N minutes, missed pings trigger the alert) is the standard lightweight add-on; it can also target the same moshi webhook as its integration if you don't want a second notification channel.

---

## Decided against (for context, not re-litigating)

- **`pi` process watchdog** — starting manually is fine, skipped.
- **UPS / battery backup** — power loss = Pi down, accepted risk.
