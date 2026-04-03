#!/usr/bin/env bash
# end-session.sh — Sync state and destroy the current OVH instance
# Runs from Termux or desktop (NOT on the instance).
#
# Usage:
#   ./end-session.sh              — uses .current_instance_id saved by start-session.sh
#   ./end-session.sh <instance-id>  — explicit instance ID
#
# Requires:
#   - openstack CLI in PATH
#   - ~/openrc.sh sourced
#   - scripts/config.env sourced

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"

# Resolve instance ID
if [[ -n "$1" ]]; then
  INSTANCE_ID="$1"
elif [[ -f "$SCRIPT_DIR/.current_instance_id" ]]; then
  INSTANCE_ID=$(cat "$SCRIPT_DIR/.current_instance_id")
  IP=$(cat "$SCRIPT_DIR/.current_instance_ip" 2>/dev/null || true)
else
  echo "ERROR: No instance ID provided and no .current_instance_id found."
  echo "Usage: ./end-session.sh [instance-id]"
  exit 1
fi

# Get IP if not already loaded
if [[ -z "$IP" ]]; then
  IP=$(openstack server show "$INSTANCE_ID" -f value -c addresses | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi

echo "Ending session: $INSTANCE_ID ($IP)"
echo ""

# Sync state from instance to Object Storage
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$OVH_SSH_USER@$IP" true 2>/dev/null; then
  echo "Syncing state to Object Storage..."
  ssh -o StrictHostKeyChecking=no "$OVH_SSH_USER@$IP" "
    aws s3 sync ~/ s3://${OVH_STATE_BUCKET}/dotfiles/ \
      --exclude '*' \
      --include '.gitconfig' \
      --include '.bashrc' \
      --include '.zshrc' \
      --include '.ssh/config' \
      --include '.ssh/known_hosts' \
      --include '.ssh/authorized_keys' \
      --include '.claude/settings.json' \
      --include '.claude/CLAUDE.md' \
      --include '.claude/.credentials.json' \
      --include '.claude/rules/*' \
      --include '.claude/skills/*' \
      --include '.claude/commands/*' \
      --include '.claude/output-styles/*' \
      --include '.claude/agents/*' \
      --include '.claude/agent-memory/*' \
      --include '.claude/plugins/*' \
      --include '.claude/projects/*' \
      --quiet
    aws s3 sync ~/env/ s3://${OVH_STATE_BUCKET}/env/ \
      --quiet
  " || echo "  WARNING: State sync failed — instance will still be deleted"
  echo "  State synced."
else
  echo "  Instance unreachable — skipping state sync"
fi

# Delete instance
echo "Deleting instance..."
openstack server delete "$INSTANCE_ID" --wait
echo "Instance deleted."

# Clean up local state files
rm -f "$SCRIPT_DIR/.current_instance_id" "$SCRIPT_DIR/.current_instance_ip"

echo ""
echo "Session ended."
