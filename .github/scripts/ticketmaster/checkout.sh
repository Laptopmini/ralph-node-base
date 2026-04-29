#!/usr/bin/env bash
set -euo pipefail

source .github/scripts/helpers/log.sh

# Check if a ticket number was provided
if [ -z "$1" ]; then
  log ERROR "Ticket Number is required."
  log ERROR "Usage: $0 <ticket-number>"
  exit 1
fi

TICKET="$1"
DEV_BRANCH="maestro"
TICKET_BRANCH="prd-${TICKET}"

# Helper function to check if a branch exists locally
has_local_branch() {
    git rev-parse --verify --quiet "$1" > /dev/null 2>&1
}

# Helper function to check if a branch exists on remote
has_remote_branch() {
    git ls-remote --exit-code origin "refs/heads/$1" > /dev/null 2>&1
}

# Helper function to create a branch if it doesn't exist locally or remotely
checkout_branch() {
    local branch_name="$1"
    
    local local_exists=false
    local remote_exists=false
    has_local_branch "$branch_name" && local_exists=true
    has_remote_branch "$branch_name" && remote_exists=true

    if $local_exists && $remote_exists; then
        git checkout "$branch_name" || { log ERROR "Failed to checkout $branch_name (local)"; exit 1; }
        git pull origin "$branch_name" || { log ERROR "Failed to pull from origin/$branch_name"; exit 1; }
    elif $local_exists; then
        log INFO "Local branch $branch_name exists but remote is gone. Recreating from $(git branch --show-current)."
        git branch -D "$branch_name" || { log ERROR "Failed to delete stale local branch $branch_name"; exit 1; }
        git checkout -b "$branch_name" || { log ERROR "Failed to recreate $branch_name"; exit 1; }
        git push -u origin "$branch_name" || { log ERROR "Failed to push origin/$branch_name"; exit 1; }
    elif $remote_exists; then
        git checkout -b "$branch_name" origin/"$branch_name" || { log ERROR "Failed to checkout $branch_name (remote)"; exit 1; }
    else
        git checkout -b "$branch_name" || { log ERROR "Failed to checkout $branch_name (new branch)"; exit 1; }
        git push -u origin "$branch_name" || { log ERROR "Failed to push origin/$branch_name"; exit 1; }
        log INFO "Created branch $branch_name"
    fi
}

# Checkout main
git checkout main || { log ERROR "Failed to checkout main"; exit 1; }

# Fetch all branches and prune deleted ones
git fetch origin --prune || true

# Pull main
git pull origin main || true

# Create/checkout meaestro branch
checkout_branch "$DEV_BRANCH"

# Create/checkout workflow branch
checkout_branch "$TICKET_BRANCH"

log INFO "Now performing within branch $(git branch --show-current)"
