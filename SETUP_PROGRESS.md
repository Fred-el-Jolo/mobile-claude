# OVH OpenStack Setup — Progress Log

## Environment

- OpenStack CLI installed via venv in `/home/jolo/dev/mobile-claude/`
- **Activate venv before any openstack command:**
  ```fish
  . .venv/bin/activate.fish
  ```

---

## Phase 1 — Foundation ✅ DONE (steps 1–5)

1. ✅ OVH Public Cloud project created
2. ✅ OpenStack user created, RC file downloaded and sourced
3. ✅ SSH key added to OVH project
4. ✅ (pending) Object Storage S3 bucket: `mobile-claude-state`
5. ✅ OpenStack CLI installed and venv working

---

## Phase 1 — Step 6: Security Group (IN PROGRESS)

**Error encountered:**
```
ForbiddenException: 403, rule:create_security_group is disallowed by policy
```

**Root cause:** OpenStack user is missing the `Network Operator` role.

**Fix:**
1. Go to console.ovhcloud.com → Public Cloud project
2. Left sidebar → **Users & Roles**
3. Click **"..."** on your OpenStack user → **Edit roles**
4. Add **`Network Operator`** role → Save
5. Re-download the RC file and re-source it:
   ```fish
   . .venv/bin/activate.fish
   source ~/openrc.sh
   ```
6. Retry:
   ```bash
   openstack security group create mobile-claude-sg --description "SSH only"
   openstack security group rule create mobile-claude-sg \
     --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0
   ```

**Alternative (skip role fix):** Use the existing `default` security group:
```bash
openstack security group list
openstack security group rule create default \
  --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0
# Then use --security-group default when launching the server
```

---

## Phase 3 — Snapshot ✅ DONE

- Snapshot: `mobile-claude-snapshot` (ID: `41b96eed-cfd2-4f04-b083-d46e14827671`)
- Verified: boots clean, Claude Code 2.1.87 works immediately
- See `SNAPSHOT_PROCEDURE.md` for how to rebuild it

## Phase 4 — Lifecycle Scripts ✅ DONE

- `scripts/start-session.sh ssh` — SSH mode (direct shell)
- `scripts/start-session.sh rc [name]` — Remote Control mode (Claude mobile app)
- `scripts/end-session.sh` — sync state + delete instance
- `scripts/config.env` — all instance IDs and config baked in
- `TERMUX_SETUP.md` — Android Termux setup guide

## Phase 5 — Object Storage (TODO)

Once security group is ready:

```bash
# Find image and flavor
openstack image list | grep -i ubuntu
openstack flavor list | grep d2-2

# Launch d2-2 instance
openstack server create \
  --flavor d2-2 \
  --image "Ubuntu 24.04" \
  --key-name mobile-claude-key \
  --security-group mobile-claude-sg \
  --wait \
  mobile-claude-test

# Get IP and SSH in
openstack server show mobile-claude-test -f value -c addresses
ssh ubuntu@<IP>
```
