#!/usr/bin/env bash
# Create a snapshot of an OpenStack instance
# Usage: ./snapshot-instance.sh <instance-name-or-id> <snapshot-name>
set -euo pipefail

INSTANCE="${1:?Usage: $0 <instance-name-or-id> <snapshot-name>}"
SNAPSHOT_NAME="${2:?Usage: $0 <instance-name-or-id> <snapshot-name>}"

echo "Creating snapshot '$SNAPSHOT_NAME' from instance '$INSTANCE'..."
openstack server image create --name "$SNAPSHOT_NAME" "$INSTANCE"
echo "Done. Snapshot list:"
openstack image list --format table -c ID -c Name -c Status | grep "$SNAPSHOT_NAME" || true
