# Plan: Project Sync via S3

## Context

Sessions currently sync dotfiles and env to/from `mobile-claude-state` S3 but not project code. Users must re-clone every session. This adds project sync to the same bucket (`projects/` prefix), filtering out build artifacts and preserving git remotes via a sidecar `.git-meta.json` file. No unpushed-commit preservation — push before ending a session.

---

## Approach

**Same bucket, new prefix.** `s3://mobile-claude-state/projects/`. No new credentials, no new bucket.

**Working tree only.** `.git/` is excluded from sync. Each project with a git repo gets a `.git-meta.json` at its root before push:
```json
{"remote":"git@github.com:fred/ABC.git","branch":"main","lastCommit":"abc123"}
```
On restore, a loop checks for `.git-meta.json` + no `.git/` dir → `git init && git remote add origin <remote>`.

**Global blacklist (inline in every sync call):**
```
*/node_modules/*  */.venv/*  */venv/*  */vendor/*  */target/*
*/dist/*  */build/*  */.next/*  */__pycache__/*  */.git/*
*.log  *.tmp  *.pyc  *.class
```

**`--delete` on push, not on pull.** Push keeps S3 clean when projects are removed. Pull leaves local-only projects untouched.

---

## Files to Modify

### 1. `scripts/laptop-sync.sh` — lines 97–112

Replace `push_projects` (lines 97–105):
```bash
push_projects() {
  echo "Pushing projects → S3..."
  if [[ ! -d ~/projects ]]; then
    echo "  ~/projects/ not found — skipping"
    return
  fi
  for proj in ~/projects/*/; do
    [[ -d "$proj/.git" ]] || continue
    remote=$(git -C "$proj" remote get-url origin 2>/dev/null || true)
    branch=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    commit=$(git -C "$proj" rev-parse HEAD 2>/dev/null || true)
    printf '{"remote":"%s","branch":"%s","lastCommit":"%s"}\n' \
      "$remote" "$branch" "$commit" > "$proj/.git-meta.json"
  done
  aws s3 sync ~/projects/ "${S3_BASE}/projects/" $EP \
    --delete \
    --exclude "*/node_modules/*" --exclude "*/.venv/*" --exclude "*/venv/*" \
    --exclude "*/vendor/*" --exclude "*/target/*" --exclude "*/dist/*" \
    --exclude "*/build/*" --exclude "*/.next/*" --exclude "*/__pycache__/*" \
    --exclude "*/.git/*" --exclude "*.log" --exclude "*.tmp" \
    --exclude "*.pyc" --exclude "*.class"
  echo "  projects pushed."
}
```

Replace `pull_projects` (lines 107–112):
```bash
pull_projects() {
  echo "Pulling projects ← S3..."
  mkdir -p ~/projects
  aws s3 sync "${S3_BASE}/projects/" ~/projects/ $EP \
    --exact-timestamps \
    --exclude "*/node_modules/*" --exclude "*/.venv/*" --exclude "*/venv/*" \
    --exclude "*/vendor/*" --exclude "*/target/*" --exclude "*/dist/*" \
    --exclude "*/build/*" --exclude "*/.next/*" --exclude "*/__pycache__/*" \
    --exclude "*/.git/*" --exclude "*.log" --exclude "*.tmp" \
    --exclude "*.pyc" --exclude "*.class"
  for meta in ~/projects/*/.git-meta.json; do
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
```

---

### 2. `scripts/end-session.sh` — after line 66 (after the existing sync block)

Insert a **second SSH call** for projects immediately after the existing `ssh ... "..." || echo "WARNING"` line (line 66), still inside the `if ssh ... reachable; then` block:

```bash
  # Sync projects (separate call — uses bash -s to support shell loop for git-meta)
  ssh -o StrictHostKeyChecking=no "$OVH_SSH_USER@$IP" bash -s -- "$OVH_STATE_BUCKET" << 'ENDSYNC'
STATE_BUCKET="$1"
if [[ -d ~/projects ]]; then
  for proj in ~/projects/*/; do
    [[ -d "$proj/.git" ]] || continue
    remote=$(git -C "$proj" remote get-url origin 2>/dev/null || true)
    branch=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    commit=$(git -C "$proj" rev-parse HEAD 2>/dev/null || true)
    printf '{"remote":"%s","branch":"%s","lastCommit":"%s"}\n' \
      "$remote" "$branch" "$commit" > "$proj/.git-meta.json"
  done
  aws s3 sync ~/projects/ "s3://${STATE_BUCKET}/projects/" \
    --delete \
    --exclude "*/node_modules/*" --exclude "*/.venv/*" --exclude "*/venv/*" \
    --exclude "*/vendor/*" --exclude "*/target/*" --exclude "*/dist/*" \
    --exclude "*/build/*" --exclude "*/.next/*" --exclude "*/__pycache__/*" \
    --exclude "*/.git/*" --exclude "*.log" --exclude "*.tmp" \
    --exclude "*.pyc" --exclude "*.class" \
    --quiet
fi
ENDSYNC
  echo "  Projects synced."
```

The existing dotfiles/env sync block is **not touched** — safer blast radius.

---

### 3. `scripts/startup.sh` — insert between lines 54 and 56

Insert after `|| echo "startup: env sync failed..."` (line 54), before `echo "startup: state sync complete."` (line 56):

```bash
echo "startup: syncing projects from S3..."
sudo -H -u ubuntu mkdir -p /home/ubuntu/projects
sudo -H -u ubuntu aws s3 sync "s3://${OVH_STATE_BUCKET}/projects/" /home/ubuntu/projects/ \
  --exact-timestamps \
  --exclude "*/node_modules/*" --exclude "*/.venv/*" --exclude "*/venv/*" \
  --exclude "*/vendor/*" --exclude "*/target/*" --exclude "*/dist/*" \
  --exclude "*/build/*" --exclude "*/.next/*" --exclude "*/__pycache__/*" \
  --exclude "*/.git/*" --exclude "*.log" --exclude "*.tmp" \
  --exclude "*.pyc" --exclude "*.class" \
  || echo "startup: projects sync failed or bucket empty — continuing"

for meta in /home/ubuntu/projects/*/.git-meta.json; do
  [ -f "$meta" ] || continue
  proj=$(dirname "$meta")
  [ -d "$proj/.git" ] && continue
  remote=$(python3 -c "import json; d=json.load(open('$meta')); print(d['remote'])" 2>/dev/null || true)
  branch=$(python3 -c "import json; d=json.load(open('$meta')); print(d['branch'])" 2>/dev/null || true)
  [ -z "$remote" ] && continue
  echo "startup: re-initializing git in $(basename "$proj")"
  sudo -H -u ubuntu git -C "$proj" init -q
  sudo -H -u ubuntu git -C "$proj" remote add origin "$remote"
  [ -n "$branch" ] && sudo -H -u ubuntu git -C "$proj" checkout -q -b "$branch" 2>/dev/null || true
done
```

---

## Edge Cases Handled

| Case | Handling |
|------|----------|
| No `~/projects/` dir | Guard in `push_projects`, `|| continue` in loops |
| Project with no git remote | `remote` is empty, loop skips git-init via `[[ -z "$remote" ]]` |
| Project already has `.git/` on restore | `[[ -d "$proj/.git" ]] && continue` |
| S3 bucket empty on first session | `|| echo "... — continuing"` prevents exit |
| `.git-meta.json` not in exclude list | Correct — it's at project root, not inside `.git/` |

---

## Verification

1. On laptop: `./laptop-sync.sh push projects` → check S3 `projects/` prefix has files, no `node_modules/`, `.git-meta.json` present per project
2. Boot fresh instance → `ls ~/projects/` and `git remote -v` in each project — remotes should be set
3. Edit a file on instance, run `./end-session.sh` → check S3 updated, instance deleted
4. `./laptop-sync.sh pull projects` on laptop → verify changes arrived
5. Spot-check S3 object count/size (should be small — no deps or git objects)
