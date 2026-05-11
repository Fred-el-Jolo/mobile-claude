#!/usr/bin/env bash
# laptop-sync.sh — sync laptop dotfiles/env/Projects with OVH Object Storage
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
    --include ".claude/Projects/*" \
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
  if [[ ! -d ~/Projects ]]; then
    echo "  ~/Projects/ not found — skipping"
    return
  fi
  for proj in ~/Projects/*/; do
    [[ -d "$proj/.git" ]] || continue
    remote=$(git -C "$proj" config --get remote.origin.url 2>/dev/null || echo "")
    branch=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    lastCommit=$(git -C "$proj" rev-parse HEAD 2>/dev/null || echo "")
    printf '{"remote":"%s","branch":"%s","lastCommit":"%s"}\n' "$remote" "$branch" "$lastCommit" > "$proj/.git-meta.json"
  done
  aws s3 sync ~/Projects/ "${S3_BASE}/Projects/" $EP --delete \
    --exclude "*/node_modules/*" --exclude "*/.venv/*" --exclude "*/venv/*" \
    --exclude "*/vendor/*" --exclude "*/target/*" --exclude "*/dist/*" \
    --exclude "*/build/*" --exclude "*/.next/*" --exclude "*/__pycache__/*" \
    --exclude "*/.git/*" --exclude "*.log" --exclude "*.tmp" \
    --exclude "*.pyc" --exclude "*.class"
  echo "  projects pushed."
}

pull_projects() {
  echo "Pulling projects ← S3..."
  mkdir -p ~/Projects
  aws s3 sync "${S3_BASE}/Projects/" ~/Projects/ $EP --exact-timestamps \
    --exclude "*/node_modules/*" --exclude "*/.venv/*" --exclude "*/venv/*" \
    --exclude "*/vendor/*" --exclude "*/target/*" --exclude "*/dist/*" \
    --exclude "*/build/*" --exclude "*/.next/*" --exclude "*/__pycache__/*" \
    --exclude "*/.git/*" --exclude "*.log" --exclude "*.tmp" \
    --exclude "*.pyc" --exclude "*.class"
  for meta in ~/Projects/*/.git-meta.json; do
    [[ -f "$meta" ]] || continue
    proj=$(dirname "$meta")
    [[ -d "$proj/.git" ]] && continue
    remote=$(python3 -c "import json; d=json.load(open('$meta')); print(d['remote'])" 2>/dev/null || true)
    branch=$(python3 -c "import json; d=json.load(open('$meta')); print(d['branch'])" 2>/dev/null || true)
    [[ -z "$remote" ]] && continue
    git -C "$proj" init -q
    git -C "$proj" remote add origin "$remote"
    [[ -n "$branch" ]] && git -C "$proj" checkout -q -b "$branch" 2>/dev/null || true
    echo "  Re-initialized git in $(basename "$proj")"
  done
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
