#!/bin/bash
# startup.sh — cloud-init user-data script, runs on every boot
# Keeps the instance up-to-date regardless of snapshot age.
# S3 credentials are injected by start-session.sh at launch time (placeholders below).

# Update packages
apt-get update -q && apt-get upgrade -y -q && apt-get autoremove -y -q

# S3 credentials (injected by start-session.sh — never edit real values here)
OVH_S3_ACCESS_KEY="__OVH_S3_ACCESS_KEY__"
OVH_S3_SECRET_KEY="__OVH_S3_SECRET_KEY__"
OVH_STATE_BUCKET="__OVH_STATE_BUCKET__"
OVH_S3_ENDPOINT="__OVH_S3_ENDPOINT__"

# Skip sync if credentials were not injected
if [[ "$OVH_S3_ACCESS_KEY" == "__OVH_S3_ACCESS_KEY__" ]]; then
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
  || echo "startup: dotfiles sync failed or bucket empty — continuing"

echo "startup: syncing env from S3..."
sudo -H -u ubuntu mkdir -p /home/ubuntu/env
sudo -H -u ubuntu aws s3 sync "s3://${OVH_STATE_BUCKET}/env/" /home/ubuntu/env/ \
  --exact-timestamps \
  || echo "startup: env sync failed or bucket empty — continuing"

echo "startup: state sync complete."
