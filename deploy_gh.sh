#!/usr/bin/env bash
set -e

# GH-enabled deploy script for crypto-ideias-docs
# Requirements:
#   - git
#   - GitHub CLI (gh) authenticated: gh auth login
#
# Usage:
#   ./deploy_gh.sh "docs: update"
# If no message is provided, a timestamped message is used.

MSG="${1:-docs: deploy $(date -u +'%Y-%m-%d %H:%M:%S UTC')}"
REPO_NAME="${REPO_NAME:-crypto-ideias-docs}"
VISIBILITY="${VISIBILITY:-public}"  # public|private
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# Ensure directory is a git repo
if [ ! -d .git ]; then
  echo "Initializing git repository..."
  git init
  git checkout -b "$DEFAULT_BRANCH" 2>/dev/null || git branch -M "$DEFAULT_BRANCH"
fi

# Check if origin exists, otherwise create repo with gh
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "No 'origin' remote found. Attempting to create repo with gh..."
  if ! command -v gh >/dev/null 2>&1; then
    echo "❌ GitHub CLI (gh) not found. Install from https://cli.github.com/ or use deploy.sh"
    exit 1
  fi

  # Get user
  GH_USER="$(gh api user --jq '.login')"
  if [ -z "$GH_USER" ]; then
    echo "❌ Not authenticated. Run: gh auth login"
    exit 1
  fi

  # Create repo if it does not exist
  if gh repo view "$GH_USER/$REPO_NAME" >/dev/null 2>&1; then
    echo "ℹ️ Repo $GH_USER/$REPO_NAME already exists. Adding remote..."
  else
    echo "🚀 Creating repo: $GH_USER/$REPO_NAME ($VISIBILITY)"
    gh repo create "$GH_USER/$REPO_NAME" --"$VISIBILITY" --source=. --disable-issues --disable-wiki --confirm || {
      echo "❌ Failed to create repo with gh"; exit 1; }
  fi

  git remote add origin "https://github.com/$GH_USER/$REPO_NAME.git" 2>/dev/null || true
fi

# Add & commit
git add -A
if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "$MSG"
fi

# Push
git push -u origin "$DEFAULT_BRANCH"

# Enable GitHub Pages via API (if permissions allow)
echo "Attempting to enable GitHub Pages (root on main)..."
GH_REPO="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s/\.git$//')"
OWNER="${GH_REPO%%/*}"
NAME="${GH_REPO##*/}"

# Set pages source to main branch root (API v3)
gh api -X PUT "repos/$OWNER/$NAME/pages" -F build_type=legacy 2>/dev/null || true
gh api -X POST "repos/$OWNER/$NAME/pages/builds" 2>/dev/null || true

PAGES_URL="https://${OWNER}.github.io/${NAME}/"

echo ""
echo "✅ Deploy completed."
echo "🌐 GitHub Pages (aguarde ~1–2 min): $PAGES_URL"
echo "🔗 Política: ${PAGES_URL}politica.html"
echo "🔗 Termos:   ${PAGES_URL}termos.html"
