#!/bin/bash

# ==============================================================================
# MAESTRO: Automate the entire process
# Usage: ./maestro.sh
# ==============================================================================

set -euo pipefail

# Settings
LOCK_FILE=".maestro.lock"
LOG_FILE="tmp/maestro.log"
BLUEPRINT_FILE=".maestro.blueprint.md"
ENGINE="claude" # FIXME: Use env variable `ENGINE` with default value `claude`

# Functions

prompt() { bash .github/scripts/prompt.sh "$@"; }

open_pull_requests() {
    read -n 1 -s -r -p "💬 Are you ready to review the Pull Request(s)? Press any key to open in browser..."
    open $(gh repo view --json url -q ".url + \"/pulls\"")
}

review_pull_requests() {
    # FIXME: Could have Claude do an initial review of the PRs to improve user's review/approval
    open_pull_requests
    read -n 1 -s -r -p "💬 Once all Pull Requests have been merged, press any key to continue..."

    local UNVERIFIED=true
    while $UNVERIFIED; do
        local ALL_MERGED=true
        while IFS= read -r LINE; do
            local PR_NUMBER=$(echo "$LINE" | sed 's/.*#\([0-9]*\)).*/\1/')
            
            if [ -z "$PR_NUMBER" ]; then
                # Unable to extract PR number from line
                ALL_MERGED=false
                break
            fi

            local state=$(gh pr view "$PR_NUMBER" --json state --jq '.state')
            
            if [ "$state" != "MERGED" ]; then
                ALL_MERGED=false
                break
            fi

            # FIXME: Remove hard-coded repo and leverage repo-slug.sh when this is its own script

            # Clean up the local branch
            local BRANCH_NAME=$(gh pr view "$PR_NUMBER" --repo Laptopmini/ralph-maestro-demo --json headRefName --jq '.headRefName')
            if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
                git branch -D "$BRANCH_NAME"
            fi
        done <<< "$1"

        if [ "$ALL_MERGED" = false ]; then
            read -n 1 -s -r -p "💬 Are you sure all Pull Requests have been merged? Press any key to continue when ready..."
        else
            UNVERIFIED=false
        fi
    done
}

cleanup() {
    local exit_code=$?
    rm -f "$LOCK_FILE" "$LOG_FILE"
    if [[ $exit_code -eq 0 ]]; then
        rm -f "$BLUEPRINT_FILE"
    fi
}

# ==============================================================================

if [ -e "$LOCK_FILE" ]; then
    echo "❌ Error: Maestro is already running! Exiting..."
    exit 1
fi

touch "$LOCK_FILE"
trap cleanup EXIT

if ! command -v $ENGINE &> /dev/null; then
    echo "❌ Error: $ENGINE CLI is not installed."
    exit 1
fi

if [ -z "$*" ]; then
    echo "❌ Error: No feature(s) request paragraph/description provided."
    echo "Usage: $0 [Your feature request paragraph]"
    exit 1
fi

# Capture all output to the log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "🟢 Beginning orchestration..."

TREE_LEVELS=""
FOLDER_NAME=""
FINAL_BLUEPRINT_FILE=""
MISSING_BLUEPRINT=true
while $MISSING_BLUEPRINT; do
    echo "⚪️ Generating implementation plan..."
    TREE_LEVELS=$(prompt "/blueprint $*" --model claude-opus-4-6)

    if [[ -z "$TREE_LEVELS" ]]; then
        echo "❌ Error: Blueprint agent returned no tree levels. Aborting."
        exit 1
    fi

    FOLDER_NAME="docs/$(head -1 "$BLUEPRINT_FILE" | sed 's/## Implementation Plan: //g' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"

    COUNTER=0
    BASE="$FOLDER_NAME"
    while [[ -e "$FOLDER_NAME" ]]; do
        COUNTER=$((COUNTER + 1))
        FOLDER_NAME="${BASE}-${COUNTER}"
    done

    mkdir -p "$FOLDER_NAME"

    FINAL_BLUEPRINT_FILE="$FOLDER_NAME/blueprint.md"
    mv "$BLUEPRINT_FILE" "$FINAL_BLUEPRINT_FILE"

    echo "⚪️ Created $FINAL_BLUEPRINT_FILE!"

    if command -v code &>/dev/null; then
        code "$FINAL_BLUEPRINT_FILE"
    fi

    read -p "💬 Does the blueprint look accurate to you to proceed with generating PRD(s) for it? (Y/n): " -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        MISSING_BLUEPRINT=false
    else
        rm -rf "$BLUEPRINT_FILE" "$FOLDER_NAME"
    fi
done

REPO_SLUG=$(bash .github/scripts/repo-slug.sh)

echo "⚪️ Proceeding through implementation tree levels..."
while IFS= read -r LEVEL; do
    echo "⚪️ [$LEVEL] Generating PRD(s)..."
    BRANCHES=$(prompt "/ticketmaster $FINAL_BLUEPRINT_FILE $LEVEL" --model claude-sonnet-4-6)
    if [[ -z "$BRANCHES" ]]; then
        echo "❌ Error: Ticketmaster agent returned no branches for level [$LEVEL]. Aborting."
        exit 1
    else
        echo "⚪️ Finished creating branches and PRDs for current level."
    fi

    review_pull_requests "$BRANCHES"

    echo "⚪️ [$LEVEL] Generating backpressure..."
    BACKPRESSURE_BRANCHES=""
    while IFS= read -r LINE; do
        BASE_BRANCH_NAME="${LINE%% (*}"
        BACKPRESSURE_BRANCH_NAME="$BASE_BRANCH_NAME-backpressure"

        # Fail-fast: if any backpressure loop fails, abort the entire run
        git checkout "$BASE_BRANCH_NAME" && git pull
        git checkout -b "$BACKPRESSURE_BRANCH_NAME"
        npm i && npm run backpressure
        git add .
        git diff --cached --quiet || git commit -m "chore(ai): Backpressure"
        git push -u origin "$BACKPRESSURE_BRANCH_NAME"

        BS_OUTPUT=$(prompt "/summarizer $REPO_SLUG $BACKPRESSURE_BRANCH_NAME $BASE_BRANCH_NAME" --model claude-haiku-4-5)
        [ -n "$BACKPRESSURE_BRANCHES" ] && BACKPRESSURE_BRANCHES+=$'\n'
        BACKPRESSURE_BRANCHES+="$BS_OUTPUT"

        echo "⚪️ [$LEVEL] Generated backpressure for \"$BASE_BRANCH_NAME\"."
    done <<< "$BRANCHES"

    if [[ -z "$BACKPRESSURE_BRANCHES" ]]; then
        echo "❌ Error: No backpressure branches were generated for level [$LEVEL]. Aborting."
        exit 1
    fi

    review_pull_requests "$BACKPRESSURE_BRANCHES"

    echo "⚪️ [$LEVEL] Proceeding with implementation..."
    IMPLEMENTATION_BRANCHES=""
    while IFS= read -r LINE; do
        BASE_BRANCH_NAME="${LINE%% (*}"

        # Fail-fast: if any ralph loop fails, abort the entire run
        git checkout "$BASE_BRANCH_NAME" && git pull
        npm i && npm run ralph
        git add .
        git diff --cached --quiet || git commit -m "chore(ai): Update Ralph log"
        git push -u origin "$BASE_BRANCH_NAME"

        BS_OUTPUT=$(prompt "/summarizer $REPO_SLUG $BASE_BRANCH_NAME maestro" --model claude-haiku-4-5)
        [ -n "$IMPLEMENTATION_BRANCHES" ] && IMPLEMENTATION_BRANCHES+=$'\n'
        IMPLEMENTATION_BRANCHES+="$BS_OUTPUT"

        echo "⚪️ [$LEVEL] Implementation for \"$BASE_BRANCH_NAME\" completed."
    done <<< "$BACKPRESSURE_BRANCHES"

    if [[ -z "$IMPLEMENTATION_BRANCHES" ]]; then
        echo "❌ Error: No implementation branches were generated for level [$LEVEL]. Aborting."
        exit 1
    fi

    review_pull_requests "$IMPLEMENTATION_BRANCHES"
done <<< "$TREE_LEVELS"
echo "⚪️ Completed implementation plan!"

# ---

# FIXME: Update CLAUDE.md

# FIXME: Update README.md

# ---

echo "⚪️ Committing log and opening final PR..."
git checkout maestro && git pull
mv "$LOG_FILE" "$FOLDER_NAME/maestro.log"
git add .
git commit -m "chore(ai): Add Maestro log"
git push -u origin maestro

# FIXME: Summarizer needs to accept branches not using `prd-1` format, and determin another commit slug for it
# either `feat(<ticket-number>)` or `feat(ai)`

prompt "/summarizer $REPO_SLUG maestro main" --model claude-haiku-4-5

open_pull_requests

echo "⚪️ Switching back to main..."
git checkout main

echo "✅ Done!"