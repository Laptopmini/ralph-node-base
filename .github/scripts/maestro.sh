#!/usr/bin/env bash

# ==============================================================================
# MAESTRO: Automate the entire process
# Usage: ./maestro.sh <Your feature request paragraph>
# ==============================================================================

set -euo pipefail

# Settings

LOCK_FILE=".maestro.lock"
LOG_FILE="/tmp/maestro.log"
LOG_FILE_BACKUP="maestro.log"
BLUEPRINT_FILE=".maestro.blueprint.md"
BLUEPRINT_LEVELS_FILE=".maestro.blueprint.levels"
SLICE_FILE=".maestro.level.md"
PR_TSV_FILE=".maestro.pull-requests.tsv"
REPO_SLUG=$(bash .github/scripts/repo-slug.sh)

# Functions

prompt() { bash .github/scripts/prompt.sh "$@"; }

summarizer() { prompt "/summarizer $*" --allowedTools "Read,Bash(git diff:*),Bash(gh pr create:*),Bash(gh pr view:*)" --model qwen/qwen3.5-35b-a3b; }

ask_continue() { read -n 1 -s -r -p "$*"$'\n' < /dev/tty; }

view_pull_requests() {
    ask_continue "💬 Are you ready to review the Pull Request(s)? Press any key to open in browser..."
    local url
    url=$(gh repo view "$REPO_SLUG" --json url -q ".url + \"/pulls\"")
    if command -v xdg-open &>/dev/null; then
        xdg-open "$url"
    elif command -v open &>/dev/null; then
        open "$url"
    elif command -v start &>/dev/null; then
        start "$url"
    else
        echo "🟠 Could not detect a browser opener. Visit: $url"
    fi
}


review_pull_requests() {
    # FIXME: Could have Claude do an initial review of the PRs to improve user's review/approval
    view_pull_requests
    ask_continue "💬 Once all Pull Requests have been merged, press any key to continue..."

    # Switch back to the development branch
    git checkout maestro

    local UNVERIFIED=true
    while $UNVERIFIED; do
        local ALL_MERGED=true
        while IFS=$'\t' read -r _BASE_BRANCH_NAME PR_NUMBER; do
            if [ -z "$PR_NUMBER" ]; then
                # Unable to extract PR number from line
                ALL_MERGED=false
                break
            fi

            local STATE
            STATE=$(gh pr view "$PR_NUMBER" -R "$REPO_SLUG" --json state --jq '.state')
            if [ "$STATE" != "MERGED" ]; then
                ALL_MERGED=false
                break
            fi

            # Clean up the local branch
            HEAD_BRANCH_NAME=$(gh pr view "$PR_NUMBER" -R "$REPO_SLUG" --json headRefName --jq .headRefName)
            if [ -n "$HEAD_BRANCH_NAME" ] && git show-ref --verify --quiet "refs/heads/$HEAD_BRANCH_NAME"; then
                git branch -D "$HEAD_BRANCH_NAME"
            fi
        done <<< "$1"

        if [ "$ALL_MERGED" = false ]; then
            ask_continue "💬 Are you sure all Pull Requests have been merged? Press any key to continue when ready..."
        else
            UNVERIFIED=false
        fi
    done

    # Make sure the latest content merged is available
    git pull origin maestro
}

cleanup() {
    local exit_code=$?
    rm -f "$LOCK_FILE" "$LOG_FILE" "$PR_TSV_FILE"
    if [[ $exit_code -eq 0 ]]; then
        rm -f "$BLUEPRINT_FILE" "$BLUEPRINT_LEVELS_FILE" "$SLICE_FILE"
    fi
}

# Main

if [ -e "$LOCK_FILE" ]; then
    echo "❌ Error: Maestro is already running! Exiting..."
    exit 1
fi

touch "$LOCK_FILE"
trap cleanup EXIT
trap 'exit 130' INT HUP TERM

if [ ! -s "$BLUEPRINT_FILE" ] || [ ! -s "$BLUEPRINT_LEVELS_FILE" ]; then
    if [ -z "$*" ]; then
        echo "❌ Error: No feature(s) request paragraph/description provided."
        echo "Usage: $0 [Your feature request paragraph]"
        exit 1
    fi
fi

# Move the log file backup to the main log file if it exists
if [[ -s "${LOG_FILE_BACKUP:-}" ]]; then
    mv -f "$LOG_FILE_BACKUP" "$LOG_FILE"
else
    rm -f "$LOG_FILE_BACKUP"
fi
# Capture all output to the log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "🟢 Beginning orchestration..."

TREE_LEVELS=""
FOLDER_NAME=""
MISSING_BLUEPRINT=true
REUSING_EXISTING_PLAN=false
while $MISSING_BLUEPRINT; do
    if [[ -s "$BLUEPRINT_FILE" ]] && [[ -s "$BLUEPRINT_LEVELS_FILE" ]]; then
        echo "⚪️ Re-using existing implementation plan..."
        TREE_LEVELS=$(cat "$BLUEPRINT_LEVELS_FILE")

        if [[ -z "$TREE_LEVELS" ]]; then
            echo "❌ Error: Tree levels file is empty. You should regenerate the plan or define one. Aborting."
            exit 1
        fi
        REUSING_EXISTING_PLAN=true
    else
        echo "⚪️ Generating implementation plan..."
        TREE_LEVELS=$(prompt "/blueprint $*" --allowedTools "Read,Glob,Grep,Write" --model opus)

        if [[ -z "$TREE_LEVELS" ]]; then
            echo "🟠 Blueprint agent returned no tree levels. Retrying in 5s..."
            sleep 5
            continue
        fi
        echo "$TREE_LEVELS" > "$BLUEPRINT_LEVELS_FILE"
    fi

    if command -v code &>/dev/null; then
        code "$BLUEPRINT_FILE"
    else
        echo "⚪️ Using implementation plan from $BLUEPRINT_FILE."
    fi

    # Capture the log file in case the user quits the program here to execute later
    cp -f "$LOG_FILE" "$LOG_FILE_BACKUP"
    read -p "💬 Do you wish to proceed with the implementation plan? (Y/n): " -r confirm < /dev/tty
    rm -f "$LOG_FILE_BACKUP"
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        MISSING_BLUEPRINT=false
    else
        rm -f "$BLUEPRINT_FILE" "$BLUEPRINT_LEVELS_FILE"

        if [ -z "$*" ] && ! $REUSING_EXISTING_PLAN; then
            echo "❌ Error: User declined existing plan, but no feature(s) request paragraph/description provided."
            echo "Usage: $0 [Your feature request paragraph]"
            exit 1
        fi

        echo "⚪️ User did not approve plan, trying again..."
        continue
    fi

    FIRST_LINE=$(head -1 "$BLUEPRINT_FILE")
    if [[ "$FIRST_LINE" =~ ^##\ Implementation\ Plan:\ .+ ]]; then
        EXTRACTED_NAME=$(echo "$FIRST_LINE" | sed 's/## Implementation Plan: //g' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    else
        EXTRACTED_NAME="new-feature"
        echo "🟠 Could not parse blueprint name from header. Defaulting to '$EXTRACTED_NAME'."
    fi
    FOLDER_NAME="docs/$EXTRACTED_NAME"

    COUNTER=0
    BASE="$FOLDER_NAME"
    while [[ -e "$FOLDER_NAME" ]]; do
        COUNTER=$((COUNTER + 1))
        FOLDER_NAME="${BASE}-${COUNTER}"
    done

    mkdir -p "$FOLDER_NAME"
    echo "⚪️ Created \"$FOLDER_NAME\"!"
done

if [[ ! -s "$BLUEPRINT_FILE" ]]; then
    echo "❌ Error: An issue occurred while preparing the implementation plan and its related files. Aborting."
    exit 1
fi

echo "⚪️ Proceeding through implementation tree levels..."
LEVEL_INDEX=0
while IFS= read -r LEVEL; do
    echo "⚪️ Beginning level \"$LEVEL\"..."
    LEVEL_INDEX=$((LEVEL_INDEX + 1))
    SLICED="$SLICE_FILE"
    echo "⚪️ Slicing plan into \"$SLICED\"..."
    bash .github/scripts/slice-plan.sh "$BLUEPRINT_FILE" "$LEVEL" "$SLICED"
    if [ ! -s "$SLICED" ]; then
        echo "❌ Error: Sliced plan '$SLICED' is missing or empty. Aborting."
        exit 1
    fi

    echo "⚪️ Generating PRD(s)..."
    rm -f "$PR_TSV_FILE"
    prompt "/ticketmaster \"$SLICED\"" --allowedTools "Read,Write,Bash,Glob,Grep" --model qwen/qwen3.5-35b-a3b || true

    mv -f "$SLICED" "$FOLDER_NAME/plan-level-$LEVEL_INDEX.md"

    EXPECTED_COUNT=$(echo "$LEVEL" | tr ',' '\n' | grep -c .)

    BRANCHES=""
    if [[ -s "$PR_TSV_FILE" ]]; then
        BRANCHES=$(grep $'\t' "$PR_TSV_FILE" || true)
    fi

    ACTUAL_COUNT=0
    [[ -n "$BRANCHES" ]] && ACTUAL_COUNT=$(echo "$BRANCHES" | grep -c .)

    if [[ "$ACTUAL_COUNT" != "$EXPECTED_COUNT" ]]; then
        echo "🟠 Ticketmaster recorded $ACTUAL_COUNT/$EXPECTED_COUNT PR(s) in $PR_TSV_FILE. Reconstructing from gh pr list..."
        BRANCHES=""
        for TICKET_NUM in $(echo "$LEVEL" | tr ',' '\n' | grep .); do
            HEAD="prd-${TICKET_NUM}-requirements"
            PR_NUMBER=$(gh pr list -R "$REPO_SLUG" --head "$HEAD" --state all --json number --jq '.[0].number' 2>/dev/null || true)
            if [[ -z "$PR_NUMBER" ]]; then
                echo "❌ Error: Could not find a PR for head branch \"$HEAD\". Aborting."
                exit 1
            fi
            [[ -n "$BRANCHES" ]] && BRANCHES+=$'\n'
            BRANCHES+="prd-${TICKET_NUM}"$'\t'"$PR_NUMBER"
        done
        ACTUAL_COUNT=$(echo "$BRANCHES" | grep -c .)
    fi

    if [[ -z "$BRANCHES" ]] || [[ "$ACTUAL_COUNT" != "$EXPECTED_COUNT" ]]; then
        echo "❌ Error: Ticketmaster returned $ACTUAL_COUNT branch(es) for level \"$LEVEL\" but $EXPECTED_COUNT were expected. Aborting."
        exit 1
    fi

    echo "⚪️ Finished creating branches and PRDs for current level."

    review_pull_requests "$BRANCHES"

    echo "⚪️ Generating backpressure..."
    rm -f "$PR_TSV_FILE"
    while IFS=$'\t' read -r BASE_BRANCH_NAME _PR_NUMBER; do
        BACKPRESSURE_BRANCH_NAME="$BASE_BRANCH_NAME-backpressure"

        # Fail-fast: if any backpressure loop fails, abort the entire run
        git checkout "$BASE_BRANCH_NAME" && git pull
        git checkout -b "$BACKPRESSURE_BRANCH_NAME"
        npm i && npm run backpressure
        git add .
        git diff --cached --quiet || git commit -m "chore(ai): Backpressure"
        git push -u origin "$BACKPRESSURE_BRANCH_NAME"

        summarizer "$REPO_SLUG" "$BACKPRESSURE_BRANCH_NAME" "$BASE_BRANCH_NAME"

        echo "⚪️ Generated backpressure for \"$BASE_BRANCH_NAME\"."
    done <<< "$BRANCHES"

    BACKPRESSURE_BRANCHES=""                                                                                                                                                  
    if [[ -s "$PR_TSV_FILE" ]]; then
        BACKPRESSURE_BRANCHES=$(grep $'\t' "$PR_TSV_FILE" || true)                                                                                                            
    fi                                                                                                                                                                                                                                                                                                                            
                                                                                                                                                                            
    if [[ -z "$BACKPRESSURE_BRANCHES" ]]; then                                                                                                                                
        echo "❌ Error: No backpressure branches were generated for level \"$LEVEL\". Aborting."
        exit 1                                                                                                                                                                
    fi

    EXPECTED_BP_COUNT=$(echo "$BRANCHES" | grep -c .)                                                                                                                         
    ACTUAL_BP_COUNT=$(echo "$BACKPRESSURE_BRANCHES" | grep -c .)                                                                                                              
    if [[ "$ACTUAL_BP_COUNT" != "$EXPECTED_BP_COUNT" ]]; then                                                                                                                 
        echo "❌ Error: Generated $ACTUAL_BP_COUNT backpressure branch(es) for level \"$LEVEL\" but $EXPECTED_BP_COUNT were expected. Aborting."                              
        exit 1                                                                                                                                                                
    fi

    review_pull_requests "$BACKPRESSURE_BRANCHES"

    echo "⚪️ Proceeding with implementation..."
    rm -f "$PR_TSV_FILE"
    while IFS=$'\t' read -r BASE_BRANCH_NAME _PR_NUMBER; do
        # Fail-fast: if any ralph loop fails, abort the entire run
        git checkout "$BASE_BRANCH_NAME" && git pull
        npm i && npm run ralph -- "$FOLDER_NAME"
        git add .
        git diff --cached --quiet || git commit -m "chore(ai): Update Ralph log"
        git push -u origin "$BASE_BRANCH_NAME"

        summarizer "$REPO_SLUG" "$BASE_BRANCH_NAME" maestro

        echo "⚪️ Implementation for \"$BASE_BRANCH_NAME\" completed."
    done <<< "$BACKPRESSURE_BRANCHES"

    IMPLEMENTATION_BRANCHES=""                                                                                                                                                
    if [[ -s "$PR_TSV_FILE" ]]; then
        IMPLEMENTATION_BRANCHES=$(grep $'\t' "$PR_TSV_FILE" || true)                                                                                                          
    fi                                                                                                                                                                        
                                                                                                                                                                            
    if [[ -z "$IMPLEMENTATION_BRANCHES" ]]; then                                                                                                                              
        echo "❌ Error: No implementation branches were generated for level \"$LEVEL\". Aborting."
        exit 1                                                                                                                                                                
    fi

    EXPECTED_IMPL_COUNT=$(echo "$BACKPRESSURE_BRANCHES" | grep -c .)                                                                                                          
    ACTUAL_IMPL_COUNT=$(echo "$IMPLEMENTATION_BRANCHES" | grep -c .)                                                                                                          
    if [[ "$ACTUAL_IMPL_COUNT" != "$EXPECTED_IMPL_COUNT" ]]; then                                                                                                             
        echo "❌ Error: Generated $ACTUAL_IMPL_COUNT implementation branch(es) for level \"$LEVEL\" but $EXPECTED_IMPL_COUNT were expected. Aborting."                        
        exit 1                                                                                                                                                                
    fi

    review_pull_requests "$IMPLEMENTATION_BRANCHES"
done <<< "$TREE_LEVELS"

echo "⚪️ Completed implementation plan. Archiving plan and log..."
mv -f "$BLUEPRINT_FILE" "$FOLDER_NAME/plan.md"
mv -f "$BLUEPRINT_LEVELS_FILE" "$FOLDER_NAME/plan.levels"
mv -f "$LOG_FILE" "$FOLDER_NAME/maestro.log"
git add .
git commit -m "chore(ai): Add Maestro log"
git push -u origin maestro

echo "⚪️ Opening final PR..."
summarizer "$REPO_SLUG" maestro main
view_pull_requests

echo "⚪️ Switching back to main..."
git checkout main

echo "✅ Done!"