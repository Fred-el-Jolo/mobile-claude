#!/bin/bash
# startup.sh — cloud-init user-data script, runs on every boot
# Keeps the instance up-to-date regardless of snapshot age.
# S3 credentials are injected by start-session.sh at launch time (placeholders below).

set -x  # trace every command to cloud-init-output.log

# Update packages
apt-get update -q && apt-get upgrade -y -q && apt-get autoremove -y -q

# Credentials (injected by start-session.sh — never edit real values here)
OVH_S3_ACCESS_KEY="__OVH_S3_ACCESS_KEY__"
OVH_S3_SECRET_KEY="__OVH_S3_SECRET_KEY__"
OVH_STATE_BUCKET="__OVH_STATE_BUCKET__"
OVH_S3_ENDPOINT="__OVH_S3_ENDPOINT__"
TS_AUTHKEY="__TS_AUTHKEY__"

# Skip sync if credentials were not injected (guard uses prefix pattern, not the placeholder itself)
if [[ "$OVH_S3_ACCESS_KEY" == __* ]]; then
  echo "startup: S3 credentials not injected — skipping state sync"
  exit 0
fi

# Write AWS credentials for ubuntu user
# -H flag ensures HOME is set to /home/ubuntu so aws finds the credentials file
mkdir -p /home/ubuntu/.aws
cat > /home/ubuntu/.aws/credentials <<EOF
[default]
aws_access_key_id = ${OVH_S3_ACCESS_KEY}
aws_secret_access_key = ${OVH_S3_SECRET_KEY}
EOF
cat > /home/ubuntu/.aws/config <<EOF
[default]
region = gra
endpoint_url = ${OVH_S3_ENDPOINT}
EOF
chown -R ubuntu:ubuntu /home/ubuntu/.aws
chmod 600 /home/ubuntu/.aws/credentials

# Sync state from OVH Object Storage (graceful — don't fail if bucket is empty or first session)
echo "startup: syncing dotfiles from S3..."
sudo -H -u ubuntu aws s3 sync "s3://${OVH_STATE_BUCKET}/dotfiles/" /home/ubuntu/ \
  --exact-timestamps \
  --exclude ".ssh/id_*" \
  --exclude ".claude/cache/*" \
  --exclude ".claude/backups/*" \
  --exclude ".claude/history.jsonl" \
  --exclude ".claude/mcp-needs-auth-cache.json" \
  || echo "startup: dotfiles sync failed or bucket empty — continuing"

echo "startup: syncing env from S3..."
sudo -H -u ubuntu mkdir -p /home/ubuntu/env
sudo -H -u ubuntu aws s3 sync "s3://${OVH_STATE_BUCKET}/env/" /home/ubuntu/env/ \
  --exact-timestamps \
  || echo "startup: env sync failed or bucket empty — continuing"

echo "startup: syncing projects from S3..."
sudo -H -u ubuntu mkdir -p /home/ubuntu/Projects
sudo -H -u ubuntu aws s3 sync "s3://${OVH_STATE_BUCKET}/Projects/" /home/ubuntu/Projects/ --exact-timestamps \
  --exclude "*/node_modules/*" --exclude "*/.venv/*" --exclude "*/venv/*" \
  --exclude "*/vendor/*" --exclude "*/target/*" --exclude "*/dist/*" \
  --exclude "*/build/*" --exclude "*/.next/*" --exclude "*/__pycache__/*" \
  --exclude "*/.git/*" --exclude "*.log" --exclude "*.tmp" \
  --exclude "*.pyc" --exclude "*.class" \
  || echo "startup: projects sync failed or bucket empty — continuing"

for meta in /home/ubuntu/Projects/*/.git-meta.json; do
  [ -f "$meta" ] || continue
  proj=$(dirname "$meta")
  [ -d "$proj/.git" ] && continue
  remote=$(python3 -c "import json; d=json.load(open('$meta')); print(d['remote'])" 2>/dev/null || true)
  branch=$(python3 -c "import json; d=json.load(open('$meta')); print(d['branch'])" 2>/dev/null || true)
  [ -z "$remote" ] && continue
  echo "startup: re-initializing git in $(basename "$proj")"
  sudo -H -u ubuntu git -C "$proj" init -q
  sudo -H -u ubuntu git -C "$proj" remote add origin "$remote"
  if sudo -H -u ubuntu git -C "$proj" fetch --quiet origin 2>/dev/null; then
    [ -n "$branch" ] && sudo -H -u ubuntu git -C "$proj" update-ref "refs/heads/$branch" "refs/remotes/origin/$branch" 2>/dev/null || true
  else
    [ -n "$branch" ] && sudo -H -u ubuntu git -C "$proj" checkout -q -b "$branch" 2>/dev/null || true
  fi
done

echo "startup: state sync complete."

# Join Tailscale (enables ntfy notifications via private network)
if [[ "$TS_AUTHKEY" != __* ]]; then
  echo "startup: joining Tailscale..."
  if ! command -v tailscale &>/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
  fi
  tailscale up --authkey="$TS_AUTHKEY" --hostname=ovh-claude
  echo "startup: Tailscale connected."
else
  echo "startup: TS_AUTHKEY not injected — skipping Tailscale"
fi
