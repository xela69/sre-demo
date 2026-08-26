#!/bin/bash
set -euo pipefail

# ── Config ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
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

BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -z "$BRANCH" ]]; then
  BRANCH="main"
fi

echo "═══════════════════════════════════════"
echo "  Repo:   $(basename "$PWD")"
echo "  Branch: $BRANCH"
echo "═══════════════════════════════════════"

# ── Step 1: Stash local changes so rebase works cleanly ──
has_changes=false
if ! git diff --quiet || ! git diff --cached --quiet || [[ -n $(git ls-files --others --exclude-standard) ]]; then
  has_changes=true
  echo "📦 Stashing local changes..."
  git stash push -u -m "gitpush-auto-stash"
fi

# ── Step 2: Fetch first, then sync local branch from GitHub ──
echo "⬇️  Fetching latest from origin..."
git fetch --prune origin

HAS_HEAD=false
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  HAS_HEAD=true
fi

if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  if [[ "$HAS_HEAD" == true ]]; then
    REMOTE_AHEAD_COUNT=$(git rev-list --count "HEAD..origin/$BRANCH")
    if [[ "$REMOTE_AHEAD_COUNT" -gt 0 ]]; then
      echo "🔄 Remote has $REMOTE_AHEAD_COUNT new commit(s). Rebasing local $BRANCH..."
      if ! git rebase "origin/$BRANCH"; then
        echo "❌ Rebase conflict detected. Aborting rebase and restoring your changes."
        git rebase --abort || true
        if [[ "$has_changes" == true ]]; then
          git stash pop
        fi
        echo "Fix conflicts manually, then re-run this script."
        exit 1
      fi
    else
      echo "✅ No new commits on origin/$BRANCH."
    fi
  else
    echo "ℹ️  No local commits yet. Checking out origin/$BRANCH..."
    git checkout -B "$BRANCH" "origin/$BRANCH"
  fi
else
  echo "ℹ️  origin/$BRANCH does not exist yet. Will push when local updates exist."
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
  echo "✅ No local file changes to commit."
else
  echo "📝 Committing: $COMMIT_MSG"
  git commit -m "$COMMIT_MSG"
fi

# ── Step 5: Push only if local branch is ahead ──
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "✅ Nothing to push (no local commits yet)."
  exit 0
fi

echo "⬆️  Checking whether local branch is ahead of remote..."
if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
  AHEAD_COUNT=$(git rev-list --count "@{u}..HEAD")
  if [[ "$AHEAD_COUNT" -gt 0 ]]; then
    echo "⬆️  Pushing $AHEAD_COUNT commit(s) to origin/$BRANCH..."
    git push
  else
    echo "✅ Nothing to push. Local is in sync with remote."
  fi
else
  echo "⬆️  No upstream set. Pushing and setting upstream to origin/$BRANCH..."
  git push -u origin "$BRANCH"
fi

echo ""
echo "✅ Done. GitHub is in sync."