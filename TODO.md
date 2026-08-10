# TODO — RPi AI Host Hardening

## Backup (state lives only on the Pi's disk)

Data to protect is small: `~/.pi/agent/auth.json`, repos, dotfiles — a few GB, not media-scale. Budget tiers:

- **0€** — `rsync`/`restic` to a laptop/desktop you already own, over Tailscale, via cron. No spend, but only as safe as that machine.
- **~1-2€/month** — Backblaze B2 or rsync.net (smallest plan) + `restic`, encrypted and incremental. At this data size the bill is close to free. Off-site, so it survives theft/fire — a same-location NAS doesn't.
- **~40-60€ one-time** — USB HDD/SSD plugged into the Pi or another home device (can reuse the SSD from the USB-boot item below). Local-only backup, no off-site protection, but a real step up from nothing.
- **150-200€+** — entry NAS (e.g. Synology DS223j). **Not worth it for this alone** — a few GB of configs/repos doesn't justify a dedicated NAS. Only makes sense if you want one anyway for other stuff (photos, media).

**Recommendation:** skip the NAS. Backblaze B2/rsync.net + `restic` is the right <100€ spend — actually under 5€/year at this data volume — and it's the only option here that also survives something happening to the house, not just the SD card.

## Unattended security upgrades — ✅ DONE

`unattended-upgrades` installed; `/etc/apt/apt.conf.d/20auto-upgrades` has `Update-Package-Lists` and `Unattended-Upgrade` both at `"1"`; `apt-daily*.timer` active. Verified with `sudo unattended-upgrades --dry-run --debug`.

**Gotcha — the shipped origins-pattern is incomplete.** This box is **Debian Trixie (13) with a Raspberry Pi Foundation overlay**, not "Raspberry Pi OS Bullseye+" as the old text above assumed. The default `/etc/apt/apt.conf.d/50unattended-upgrades` only matches `origin=Debian`, so kernel/firmware updates from the Raspberry Pi Foundation repo (`archive.raspberrypi.com`) were being silently skipped ("Marking not allowed"). Fixed by adding one line to the `Origins-Pattern` block:

```
"origin=Raspberry Pi Foundation,label=Raspberry Pi Foundation";
```

Match on **origin/label, not `${distro_codename}`** — the RPi repo advertises archive `stable` while distro codename is `trixie`, so a codename match wouldn't fire. The Tailscale repo (`pkgs.tailscale.com`) is intentionally left excluded — don't auto-update the only remote-access path.

Backup of the pre-edit config: `/etc/apt/apt.conf.d/50unattended-upgrades.bak.20260810-195928`.

## USB SSD boot (Pi 4B)

- **Feasible**: yes, natively — Pi 4B has supported USB boot since the 2020 bootloader update; most units shipped since already have current firmware (check with `sudo rpi-eeprom-update`).
- **Budget**: ~35-60€ total — e.g. Crucial BX500 240GB SSD (~25€) + USB3 UASP enclosure (~12€), or an all-in-one USB3 external SSD (Crucial X6 / SanDisk, ~45-55€ for 500GB).
- **Steps**: flash Raspberry Pi OS straight to the SSD (Raspberry Pi Imager, pick the SSD as target) → `raspi-config` → Advanced → Boot Order → USB Boot → boot with the SD card removed. Also removes the SD-card-wear risk from long-running services.

## `tailscale up --ssh` — ✅ DONE

- On the Pi: `--ssh` is enabled on the tailscale node. (`rpi` below is a generic placeholder for the node's MagicDNS hostname — CLAUDE.md uses `rpi-agent`; treat both as placeholders, substitute the real hostname when you actually run the command.)
- From any device on your tailnet: `tailscale ssh jolo@rpi` — authenticates via Tailscale identity, no key exchange needed.
- Independent of moshi-hook: moshi-hook is the app-level bridge into the tmux session; `tailscale ssh` only replaces the key-based auth on the "mosh/ssh fallback" path. Keep the `ed25519` key regardless — `mosh` bootstraps over classic SSH and doesn't go through Tailscale's SSH layer.

## Temp / throttle alerting — ✅ DONE

Implemented as `~/bin/check-throttle.sh`, run every 15 min via the **user crontab** (`*/15 * * * * /home/jolo/bin/check-throttle.sh`). Decoupled from the agent — pure cron, no `curl`.

**Notification channel (corrected — the original webhook design above was wrong):** there is no public "moshi webhook". The real local notify primitive is piping a JSON hook payload to `moshi-hook pi-hook` — the exact same path the pi agent extension (`~/.pi/agent/extensions/moshi-hooks.ts`) uses. The running moshi-hook daemon holds the `host-secret` (in `~/.local/state/moshi/secrets.json`) and POSTs to `https://api.getmoshi.app/api/v1/hosts/<host-id>/events`. So **the script needs no secrets**; the stray `~/.config/moshi-hook/token.env` (a leftover one-time pairing token, superseded by `secrets.json`) has been removed. (`moshi-hook pi-hook` is the reusable recipe for *any* local script that wants to push a phone notification.)

**What it does:**
- Decodes `vcgencmd get_throttled` into named flags (under-voltage / arm-capped / throttled / soft-temp-limit — both "now" and "occurred since boot") and includes `measure_temp` + hostname in the message.
- On a non-zero bitmask → `⚠️ Pi throttled`; on return to `0x0` → `✅ Pi throttle cleared`.
- Spam-safe via `~/.local/state/check-throttle/state`: suppresses repeats within 6 h for an unchanged condition, re-alerts when the bitmask changes. Logs every run to `~/.local/state/check-throttle/check-throttle.log`.
- `check-throttle.sh --test` forces a notification to verify wiring.

Still **does not** catch a fully hung/crashed Pi — for that, a free Healthchecks.io "dead man's switch" (Pi pings it every N minutes; missed pings alert) is the standard lightweight add-on, and it can target the same `moshi-hook pi-hook` channel.

---

## Decided against (for context, not re-litigating)

- **`pi` process watchdog** — starting manually is fine, skipped.
- **UPS / battery backup** — power loss = Pi down, accepted risk.
