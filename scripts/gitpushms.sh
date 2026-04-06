#!/bin/bash
set -euo pipefail

# Always operate from the repo root at this fixed location -- WSL env
REPO_DIR='/mnt/c/Users/arnoldparada/OneDrive - Microsoft/github/demo-avm'

if [ ! -d "$REPO_DIR" ]; then
  echo "ERROR: Repo directory not found: $REPO_DIR" >&2
  exit 1
fi

cd "$REPO_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: Not a git repository: $REPO_DIR" >&2
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

# 1) Stash any local changes so pull --rebase can run cleanly
STASHED=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Stashing local changes..."
  git stash push -m "auto-stash before pull"
  STASHED=true
fi

# 2) Pull latest from GitHub (source of truth)
echo "Pulling latest changes from origin/$BRANCH..."
git pull --rebase origin "$BRANCH"

# 3) Restore stashed changes
if [ "$STASHED" = true ]; then
  echo "Restoring local changes..."
  git stash pop
fi

# 4) Stage and commit local changes (if any)
git add -A

if git diff --cached --quiet; then
  echo "No local changes to commit."
else
  COMMIT_MSG=${1:-"Updates to Commit"}
  git commit -m "$COMMIT_MSG"
fi

# 5) Push local updates to GitHub
echo "Pushing to origin/$BRANCH..."
git push origin "$BRANCH"

echo "Done."