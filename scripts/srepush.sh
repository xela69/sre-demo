#!/bin/bash
set -euo pipefail

# ── Config ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BRANCH=""
COMMIT_MSG="${1:-"Updates $(date '+%Y-%m-%d %H:%M')"}"

# ── Navigate to repo root ──
if [[ -d "$REPO_DIR" ]]; then
  cd "$REPO_DIR"
elif git rev-parse --show-toplevel >/dev/null 2>&1; then
  cd "$(git rev-parse --show-toplevel)"
else
  echo "ERROR: Not in a git repo and REPO_DIR not found." >&2
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "═══════════════════════════════════════"
echo "  Repo:   $(basename "$PWD")"
echo "  Branch: $BRANCH"
echo "═══════════════════════════════════════"

# ── Step 1: Stash any local changes so pull/rebase works cleanly ──
has_changes=false
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n $(git ls-files --others --exclude-standard) ]]; then
  has_changes=true
  echo "📦 Stashing local changes..."
  git stash push -u -m "gitpush-auto-stash"
fi

# ── Step 2: Pull latest from GitHub (source of truth) ──
echo "⬇️  Pulling latest from origin/$BRANCH..."
if ! git pull --rebase origin "$BRANCH"; then
  echo "❌ Rebase conflict detected. Aborting rebase and restoring your changes."
  git rebase --abort
  if [[ "$has_changes" == true ]]; then
    git stash pop
  fi
  echo "Fix conflicts manually, then re-run this script."
  exit 1
fi

# ── Step 3: Restore stashed local changes ──
if [[ "$has_changes" == true ]]; then
  echo "📦 Restoring local changes..."
  if ! git stash pop; then
    echo "⚠️  Stash pop had conflicts. Resolve them, then commit and push manually."
    exit 1
  fi
fi

# ── Step 4: Stage and commit local changes ──
git add -A

if git diff --cached --quiet; then
  echo "✅ No local changes to commit. Already up to date."
else
  echo "📝 Committing: $COMMIT_MSG"
  git commit -m "$COMMIT_MSG"
fi

# ── Step 5: Push to GitHub ──
echo "⬆️  Pushing to origin/$BRANCH..."
git push origin "$BRANCH"

echo ""
echo "✅ Done. GitHub is in sync."