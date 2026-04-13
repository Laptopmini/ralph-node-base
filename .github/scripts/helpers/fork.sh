#!/usr/bin/env bash

# ==============================================================================
# FORK REPO: Create a fork of the current repo within your own organization,
# to be branched out as a starting point for further PRD-driven development.
# Usage: ./fork.sh <new-repo-name>
# ==============================================================================

set -euo pipefail

source .github/scripts/helpers/log.sh

if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <new-repo-name>" >&2
  exit 1
fi

NAME="$1"
NAMESPACE="Laptopmini"
UPSTREAM=$(git remote get-url origin)
BARE_CLONE="temp-repo-bare-clone"
NEW_REPO="https://github.com/$NAMESPACE/$NAME.git"

log INFO "Cloning $UPSTREAM as $NAME..."

# Navigate to parent directory
cd ..

# Create a bare clone of the upstream repo
git clone --bare "$UPSTREAM" "$BARE_CLONE"

# Create a new empty repo on GitHub
gh repo create "$NAMESPACE/$NAME" --public

# Avoid a race condition
sleep 3

# Mirror-push everything to the new repo
cd "$BARE_CLONE"
git push --mirror "$NEW_REPO"

# Remove the local bare clone
cd ..
rm -rf "$BARE_CLONE"

# Clone the "fork"
git clone "$NEW_REPO"

# Add the original repo as a remote
cd "$NAME"
git remote add upstream "$UPSTREAM"

# Set the package name
if command -v npm &>/dev/null && [ -f package.json ]; then
    npm pkg set name="$NAME" || true
fi

if command -v code &>/dev/null; then
  # Open the project in VS Code
  code .
fi

log SUCCESS "Done!"