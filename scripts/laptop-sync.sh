#!/usr/bin/env bash
# laptop-sync.sh — sync laptop dotfiles/env/projects with OVH Object Storage
# Runs from the laptop (NOT on the OVH instance).
#
# Usage:
#   ./laptop-sync.sh push [dotfiles|env|projects|all]   — push local files to S3
#   ./laptop-sync.sh pull [dotfiles|env|projects|all]   — pull files from S3 to local
#
# Requires:
#   - awscli installed: pip install awscli  (or: sudo pacman -S aws-cli)
#   - OVH_S3_ACCESS_KEY and OVH_S3_SECRET_KEY set in config.env

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"

DIRECTION="${1:-}"
SECTION="${2:-all}"

if [[ -z "$DIRECTION" ]]; then
  echo "Usage: ./laptop-sync.sh push|pull [dotfiles|env|projects|all]"
  exit 1
fi

# Validate credentials
if [[ -z "$OVH_S3_ACCESS_KEY" || "$OVH_S3_ACCESS_KEY" == "YOUR_ACCESS_KEY_HERE" ]]; then
  echo "ERROR: OVH_S3_ACCESS_KEY not configured in config.env"
  exit 1
fi
if [[ -z "$OVH_S3_SECRET_KEY" || "$OVH_S3_SECRET_KEY" == "YOUR_SECRET_KEY_HERE" ]]; then
  echo "ERROR: OVH_S3_SECRET_KEY not configured in config.env"
  exit 1
fi

export AWS_ACCESS_KEY_ID="$OVH_S3_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$OVH_S3_SECRET_KEY"
export AWS_DEFAULT_REGION="gra"

S3_BASE="s3://${OVH_STATE_BUCKET}"
EP="--endpoint-url ${OVH_S3_ENDPOINT}"

push_dotfiles() {
  echo "Pushing dotfiles → S3..."
  aws s3 sync ~/ "${S3_BASE}/dotfiles/" $EP \
    --exclude "*" \
    --include ".gitconfig" \
    --include ".bashrc" \
    --include ".zshrc" \
    --include ".ssh/config" \
    --include ".ssh/known_hosts" \
    --include ".ssh/authorized_keys" \
    --include ".claude/settings.json" \
    --include ".claude/CLAUDE.md" \
    --include ".claude/.credentials.json" \
    --include ".claude/rules/*" \
    --include ".claude/skills/*" \
    --include ".claude/commands/*" \
    --include ".claude/output-styles/*" \
    --include ".claude/agents/*" \
    --include ".claude/agent-memory/*" \
    --include ".claude/plugins/*" \
    --include ".claude/projects/*" \
    --delete
  echo "  dotfiles pushed."
}

pull_dotfiles() {
  echo "Pulling dotfiles ← S3..."
  aws s3 sync "${S3_BASE}/dotfiles/" ~/ $EP \
    --exclude ".ssh/id_*" \
    --exclude ".claude/cache/*" \
    --exclude ".claude/backups/*" \
    --exclude ".claude/history.jsonl" \
    --exclude ".claude/mcp-needs-auth-cache.json" \
    --exact-timestamps
  echo "  dotfiles pulled."
}

push_env() {
  echo "Pushing env → S3..."
  if [[ -d ~/env ]]; then
    aws s3 sync ~/env/ "${S3_BASE}/env/" $EP --delete
    echo "  env pushed."
  else
    echo "  ~/env/ not found — skipping"
  fi
}

pull_env() {
  echo "Pulling env ← S3..."
  mkdir -p ~/env
  aws s3 sync "${S3_BASE}/env/" ~/env/ $EP --exact-timestamps
  echo "  env pulled."
}

push_projects() {
  echo "Pushing projects → S3..."
  if [[ -d ~/projects ]]; then
    aws s3 sync ~/projects/ "${S3_BASE}/projects/" $EP --delete
    echo "  projects pushed."
  else
    echo "  ~/projects/ not found — skipping"
  fi
}

pull_projects() {
  echo "Pulling projects ← S3..."
  mkdir -p ~/projects
  aws s3 sync "${S3_BASE}/projects/" ~/projects/ $EP --exact-timestamps
  echo "  projects pulled."
}

case "$DIRECTION" in
  push)
    case "$SECTION" in
      dotfiles) push_dotfiles ;;
      env)      push_env ;;
      projects) push_projects ;;
      all)      push_dotfiles; push_env; push_projects ;;
      *) echo "Unknown section: $SECTION. Use: dotfiles|env|projects|all"; exit 1 ;;
    esac
    ;;
  pull)
    case "$SECTION" in
      dotfiles) pull_dotfiles ;;
      env)      pull_env ;;
      projects) pull_projects ;;
      all)      pull_dotfiles; pull_env; pull_projects ;;
      *) echo "Unknown section: $SECTION. Use: dotfiles|env|projects|all"; exit 1 ;;
    esac
    ;;
  *)
    echo "Usage: ./laptop-sync.sh push|pull [dotfiles|env|projects|all]"
    exit 1
    ;;
esac

echo "Done."
