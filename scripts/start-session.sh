#!/usr/bin/env bash
# start-session.sh — Launch an OVH ephemeral instance and connect to it
# Runs from Termux or desktop.
#
# Usage:
#   ./start-session.sh ssh [session-name]   — open Mosh shell (default mode)
#   ./start-session.sh rc  [session-name]   — launch Claude Remote Control (scan QR in Claude mobile app)
#
# Requires:
#   - openstack CLI in PATH (Termux: pkg install python && pip install python-openstackclient)
#   - mosh in PATH (Termux: pkg install mosh)
#   - ~/openrc.sh sourced (OpenStack credentials)
#   - scripts/config.env sourced (instance config)

set -e

MODE="${1:-ssh}"
SESSION_NAME="${2:-mobile-claude}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load config
source "$SCRIPT_DIR/config.env"

# Validate
if [[ -z "$OS_AUTH_URL" ]]; then
  echo "ERROR: OpenStack credentials not loaded. Run: source ~/openrc.sh"
  exit 1
fi

INSTANCE_NAME="mobile-claude-$(date +%s)"

echo "Starting session: $INSTANCE_NAME (mode: $MODE)"
echo ""

# Generate startup script with S3 credentials injected
STARTUP_TMP=$(mktemp "${TMPDIR:-/tmp}/startup-XXXXXX.sh")
sed \
  -e "s|__OVH_S3_ACCESS_KEY__|${OVH_S3_ACCESS_KEY}|g" \
  -e "s|__OVH_S3_SECRET_KEY__|${OVH_S3_SECRET_KEY}|g" \
  -e "s|__OVH_STATE_BUCKET__|${OVH_STATE_BUCKET}|g" \
  -e "s|__OVH_S3_ENDPOINT__|${OVH_S3_ENDPOINT}|g" \
  "$SCRIPT_DIR/startup.sh" > "$STARTUP_TMP"

# Create instance from snapshot
echo "Creating instance from snapshot..."
INSTANCE_ID=$(openstack server create \
  --flavor "$OVH_FLAVOR_ID" \
  --image "$OVH_SNAPSHOT_ID" \
  --key-name "$OVH_SSH_KEY_NAME" \
  --security-group "$OVH_SECURITY_GROUP" \
  --network "$OVH_NETWORK_ID" \
  --user-data "$STARTUP_TMP" \
  --wait \
  -f value -c id \
  "$INSTANCE_NAME")

# Clean up credential-bearing temp script
rm -f "$STARTUP_TMP"

echo "Instance created: $INSTANCE_ID"

# Get IPv4
IP=$(openstack server show "$INSTANCE_ID" -f value -c addresses | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "IP: $IP"

# Save instance info for end-session.sh
echo "$INSTANCE_ID" > "$SCRIPT_DIR/.current_instance_id"
echo "$IP" > "$SCRIPT_DIR/.current_instance_ip"

# Wait for SSH
echo "Waiting for SSH..."
for i in $(seq 1 30); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 "$OVH_SSH_USER@$IP" true 2>/dev/null; then
    break
  fi
  sleep 3
done

echo ""
echo "════════════════════════════════════"
echo "  Instance: $INSTANCE_NAME"
echo "  ID:       $INSTANCE_ID"
echo "  IP:       $IP"
echo "  Mode:     $MODE"
if [[ "$MODE" == "rc" ]]; then
  echo "  Session:  $SESSION_NAME"
  echo "  -> Scan QR code in Claude mobile app"
fi
echo "  To end:   ./end-session.sh"
echo "════════════════════════════════════"
echo ""

# Connect
if [[ "$MODE" == "rc" ]]; then
  # Run Claude directly inside Mosh — QR code appears here, then switch to Claude mobile app
  # Mosh maintains terminal state across reconnects; QR code stays visible after network changes
  mosh "$OVH_SSH_USER@$IP" -- bash -c "echo 'y' | claude --name '$SESSION_NAME'"
else
  # Mosh shell — resilient to mobile network changes and sleep
  mosh "$OVH_SSH_USER@$IP"
fi
