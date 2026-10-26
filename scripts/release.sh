#!/usr/bin/env bash
set -euo pipefail

# Techuboard One-Command Release & Push Tool
# Fast, verified, and automated release pipeline.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMMIT_MSG="${1:-}"
if [ -z "$COMMIT_MSG" ]; then
  read -p "Enter commit message (e.g., 'feat: new sync improvements'): " COMMIT_MSG
fi

if [ -z "$COMMIT_MSG" ]; then
  echo "❌ Error: Commit message cannot be empty."
  exit 1
fi

echo "🚀 ============================================"
echo "   Techuboard Fast Release Pipeline"
echo "================================================"

# Step 1: Pre-push verification
echo ""
echo "▶ Step 1: Running local instant verification gate..."
./scripts/pre_push_check.sh

# Step 2: Git status and staging
echo ""
echo "▶ Step 2: Staging files..."
git add -A

# Check if there are changes to commit
if git diff --cached --quiet; then
  echo "ℹ️  No changes to commit. Working tree clean."
else
  echo "▶ Step 3: Committing changes..."
  git commit -m "$COMMIT_MSG"
fi

# Step 4: Detect current branch and remote
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
REMOTE="anzaar_remote"

# Fallback if anzaar_remote doesn't exist
if ! git remote | grep -q "^anzaar_remote$"; then
  REMOTE="$(git remote | head -n 1)"
fi

echo ""
echo "▶ Step 4: Pushing to $REMOTE ($BRANCH)..."
git push "$REMOTE" "$BRANCH"

echo ""
echo "================================================"
echo "🎉 SUCCESS: Changes pushed successfully!"
echo "   Branch: $BRANCH"
echo "   Remote: $REMOTE"
echo "   GitHub Actions: https://github.com/Anzaar-riajul/Anzaar-engine-1.0/actions"
echo "   Releases: https://github.com/Anzaar-riajul/Anzaar-engine-1.0/releases"
echo "================================================"
