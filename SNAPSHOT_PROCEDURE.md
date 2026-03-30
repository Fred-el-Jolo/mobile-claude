# Snapshot Creation Procedure

How to create a pre-baked OVH snapshot image with Claude Code ready to go.
Run this whenever Claude Code is updated or you want to bake in new tools.

---

## Required OpenStack Roles

Your OpenStack user needs ALL of these roles (set in OVH Console → Public Cloud → Users & Roles):

| Role | Why |
|---|---|
| `Network Security Operator` | Create security groups and rules |
| `Compute Operator` | Create instances and trigger snapshot |
| `Image Operator` | Save and manage the snapshot image |
| `ObjectStore Operator` | Manage the object storage |

---

## Prerequisites — Security group rules

The security group needs a UDP rule for Mosh (in addition to the SSH TCP rule already set up):

```fish
. .venv/bin/activate.fish && source ~/openrc.sh
openstack security group rule create mobile-claude-sg --protocol udp --dst-port 60000:61000 --remote-ip 0.0.0.0/0
```

---

## Step 1 — Launch a base instance

```fish
. .venv/bin/activate.fish && source ~/openrc.sh
openstack server create --flavor c6e9b74f-c419-426c-b24c-85aa0ce73495 --image cfcebaa7-d15c-47d0-98d1-84520a023202 --key-name mobile-claude-key --security-group mobile-claude-sg --network bcf59eb2-9d83-41cc-b4f5-0435ed594833 --wait mobile-claude-base
```

Get the IP:
```fish
openstack server show mobile-claude-base -f value -c addresses
```

---

## Step 2 — Install and configure on the instance

SSH in:
```bash
ssh ubuntu@<IP>
```

Install Claude Code and mosh:
```bash
curl -fsSL https://claude.ai/install.sh | bash
sudo apt-get install -y mosh
```

Authenticate Claude Code (follow the OAuth URL it prints):
```bash
claude
```

Verify:
```bash
claude --version && echo "y" | claude -p "say hi in 3 words"
```

Exit the instance:
```bash
exit
```

---

## Step 3 — Create the snapshot

```fish
openstack server image create --name mobile-claude-snapshot --wait mobile-claude-base
```

Note the snapshot ID from the output (`id` field). Update `scripts/config.env`:
```
OVH_SNAPSHOT_ID="<new-id>"
```

---

## Step 4 — Delete the base instance

```fish
openstack server delete mobile-claude-base --wait
```

---

## Step 5 — Verify the snapshot

```fish
openstack server create --flavor c6e9b74f-c419-426c-b24c-85aa0ce73495 --image <snapshot-id> --key-name mobile-claude-key --security-group mobile-claude-sg --network bcf59eb2-9d83-41cc-b4f5-0435ed594833 --wait mobile-claude-verify
```

SSH in and test:
```bash
ssh ubuntu@<IP>
claude --version && echo "y" | claude -p "say hi"
exit
```

Delete the verify instance:
```fish
openstack server delete mobile-claude-verify --wait
```

---

## Current Snapshot

| Field | Value |
|---|---|
| Name | `mobile-claude-snapshot` |
| ID | `41b96eed-cfd2-4f04-b083-d46e14827671` |
| Base image | Ubuntu 24.04 |
| Created | 2026-03-30 |
| Claude Code | 2.1.87 |
