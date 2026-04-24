#!/usr/bin/env bash

# ==============================================================================
# MAESTRO: Automate the entire process
# Usage: ./maestro.sh <Your feature request paragraph>
# ==============================================================================

set -euo pipefail

source .github/scripts/helpers/log.sh
source .github/scripts/agents/prompt.sh
source .github/scripts/summarizer.sh
source .github/scripts/helpers/notify.sh

# FIXME: Ticketmaster seems to be escaping \" rather than just using them

# FIXME: Blueprint show have tasks with more description. Sometimes they feel a little short and could be interpreted in a different way.

# Settings

LOCK_FILE=".maestro.lock"
LOG_FILE="/tmp/maestro.log"
LOG_FILE_BACKUP="maestro.log"
BLUEPRINT_FILE=".maestro.blueprint.md"
BLUEPRINT_LEVELS_FILE=".maestro.blueprint.levels"
PR_TSV_FILE=".maestro.pull-requests.tsv"
PR_SUMMARY_FILE=".maestro.summary.md"

# Models

export PROJECT_MANAGER_MODEL="claude-opus-4-7" # Planning
export STAFF_DEVELOPER_MODEL="claude-opus-4-6" # Backpressure
export SENIOR_DEVELOPER_MODEL="qwen/qwen3.5-35b-a3b" # Ticket Breakdown
export MIDLEVEL_DEVELOPER_MODEL="google/gemma-4-26b-a4b" # PR Descriptions
export JUNIOR_DEVELOPER_MODEL="minimax/MiniMax-M2.7" # Implementation

# Variables

export REPO_SLUG=$(bash .github/scripts/helpers/repo-slug.sh)
export PR_SUMMARY_FILE

# Environment variables

MISSING_MINIMAX_API_KEY=false

if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    log INFO "Loaded .env file."

    if [[ -z "$MINIMAX_API_KEY" || "$MINIMAX_API_KEY" == "<insert-key-here>" ]]; then
        MISSING_MINIMAX_API_KEY=true
    fi
else
    MODEL_VARS=(
        "PROJECT_MANAGER_MODEL"
        "STAFF_DEVELOPER_MODEL"
        "SENIOR_DEVELOPER_MODEL"
        "MIDLEVEL_DEVELOPER_MODEL"
        "JUNIOR_DEVELOPER_MODEL"
    )

    for var_name in "${MODEL_VARS[@]}"; do
        value="${!var_name}"

        if [[ "$value" == minimax/* ]]; then
            MISSING_MINIMAX_API_KEY=true
            break
        fi
    done
    log INFO "No .env file found."
fi

if [[ "$MISSING_MINIMAX_API_KEY" == "true" ]]; then
    log ERROR "Missing MINIMAX_API_KEY in .env file. Please set it to your API key."
    exit 1
fi

# Functions

ask_continue() { read -n 1 -s -r -p "$*"$'\n' < /dev/tty; }

view_pull_requests() {
    notify "Maestro is asking you to review the Pull Request(s)."
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
        log WARN "Could not detect a browser opener. Visit: $url"
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
    rm -f "$LOCK_FILE" "$LOG_FILE" "$PR_TSV_FILE" "$PR_SUMMARY_FILE"
    if [[ $exit_code -eq 0 ]]; then
        rm -f "$BLUEPRINT_FILE" "$BLUEPRINT_LEVELS_FILE"
    else
        notify "Maestro encountered an error. Please review the logs for more information."
    fi
}

# Main

if [ -e "$LOCK_FILE" ]; then
    log ERROR "Maestro is already running! Exiting..."
    exit 1
fi

touch "$LOCK_FILE"
trap cleanup EXIT
trap 'exit 130' INT HUP TERM

if [ ! -s "$BLUEPRINT_FILE" ] || [ ! -s "$BLUEPRINT_LEVELS_FILE" ]; then
    if [ -z "$*" ]; then
        log ERROR "No feature(s) request paragraph/description provided."
        log ERROR "Usage: $0 [Your feature request paragraph]"
        exit 1
    fi
fi

if [[ -z "$REPO_SLUG" ]]; then
    log ERROR "Failed to retrieve REPO_SLUG."
    return 1
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

log INFO "Beginning orchestration..."

TREE_LEVELS=""
FOLDER_NAME=""
MISSING_BLUEPRINT=true
REUSING_EXISTING_PLAN=false
while $MISSING_BLUEPRINT; do
    if [[ -s "$BLUEPRINT_FILE" ]] && [[ -s "$BLUEPRINT_LEVELS_FILE" ]]; then
        log INFO "Re-using existing implementation plan..."
        TREE_LEVELS=$(cat "$BLUEPRINT_LEVELS_FILE")

        if [[ -z "$TREE_LEVELS" ]]; then
            log ERROR "Tree levels file is empty. You should regenerate the plan or define one. Aborting."
            exit 1
        fi
        REUSING_EXISTING_PLAN=true
    else
        log INFO "Generating implementation plan..."
        # FIXME: Change this into a pure prompt rather than a skill
        TREE_LEVELS=$(prompt "/blueprint $*" --allowedTools "Read,Glob,Grep,Write($BLUEPRINT_FILE),Edit($BLUEPRINT_FILE),Agent" --model "$PROJECT_MANAGER_MODEL")

        # FIXME: Should tree levels be written by the skill using a script to avoid divergence?

        if [[ -z "$TREE_LEVELS" ]]; then
            log WARN "Blueprint agent returned no tree levels. Retrying in 5s..."
            sleep 5
            continue
        fi
        echo "$TREE_LEVELS" > "$BLUEPRINT_LEVELS_FILE"
    fi

    if command -v code &>/dev/null; then
        code "$BLUEPRINT_FILE"
    else
        log INFO "Using implementation plan from $BLUEPRINT_FILE."
    fi

    if ! $REUSING_EXISTING_PLAN; then
        notify "Maestro is ready to execute the implementation plan."
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
            log ERROR "User declined existing plan, but no feature(s) request paragraph/description provided."
            log ERROR "Usage: $0 [Your feature request paragraph]"
            exit 1
        fi

        log WARN "User did not approve plan, trying again..."
        continue
    fi

    FIRST_LINE=$(head -1 "$BLUEPRINT_FILE")
    if [[ "$FIRST_LINE" =~ ^##\ Implementation\ Plan:\ .+ ]]; then
        EXTRACTED_NAME=$(echo "$FIRST_LINE" | sed 's/## Implementation Plan: //g' | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
    else
        EXTRACTED_NAME="new-feature"
        log WARN "Could not parse blueprint name from header. Defaulting to '$EXTRACTED_NAME'."
    fi
    FOLDER_NAME="docs/$EXTRACTED_NAME"

    COUNTER=0
    BASE="$FOLDER_NAME"
    while [[ -e "$FOLDER_NAME" ]]; do
        COUNTER=$((COUNTER + 1))
        FOLDER_NAME="${BASE}-${COUNTER}"
    done

    log INFO "Using $FOLDER_NAME as archive destination."
done

if [[ ! -s "$BLUEPRINT_FILE" ]]; then
    log ERROR "An issue occurred while preparing the implementation plan and its related files. Aborting."
    exit 1
fi

log INFO "Proceeding through implementation tree levels..."
LEVEL_INDEX=0
while IFS= read -r LEVEL <&3; do
    log INFO "Beginning level \"$LEVEL\"..."
    LEVEL_INDEX=$((LEVEL_INDEX + 1))

    log INFO "Generating PRD(s)..."
    rm -f "$PR_TSV_FILE"
    for TICKET_NUM in $(echo "$LEVEL" | tr ',' '\n' | grep .); do
        bash .github/scripts/ticketmaster/checkout.sh "$TICKET_NUM"

        TICKETMASTER_PROMPT=$(bash .github/scripts/ticketmaster/get-prompt.sh "$BLUEPRINT_FILE" "$TICKET_NUM")
        prompt "$TICKETMASTER_PROMPT" --allowedTools "Write(PRD.md),Edit(PRD.md)" --model "$SENIOR_DEVELOPER_MODEL" || true

        mkdir -p "$FOLDER_NAME"
        log INFO "Backing up prompt to \"$FOLDER_NAME..."

        TICKET_TITLE=$(awk -v n="$TICKET_NUM" '$0 ~ "^#### Ticket " n ":" { sub(/^#### Ticket [0-9]+: */, ""); print; exit }' "$BLUEPRINT_FILE")
        echo "$TICKETMASTER_PROMPT" > "$FOLDER_NAME/ticketmaster-$TICKET_NUM.md"

        bash .github/scripts/ticketmaster/push-changes.sh "$TICKET_NUM" "$TICKET_TITLE"
    done

    EXPECTED_COUNT=$(echo "$LEVEL" | tr ',' '\n' | grep -c .)

    BRANCHES=""
    if [[ -s "$PR_TSV_FILE" ]]; then
        BRANCHES=$(grep $'\t' "$PR_TSV_FILE" || true)
    fi

    ACTUAL_COUNT=0
    [[ -n "$BRANCHES" ]] && ACTUAL_COUNT=$(echo "$BRANCHES" | grep -c .)

    if [[ "$ACTUAL_COUNT" != "$EXPECTED_COUNT" ]]; then
        log WARN "Ticketmaster recorded $ACTUAL_COUNT/$EXPECTED_COUNT PR(s) in $PR_TSV_FILE. Reconstructing from gh pr list..."
        BRANCHES=""
        for TICKET_NUM in $(echo "$LEVEL" | tr ',' '\n' | grep .); do
            HEAD="prd-${TICKET_NUM}-requirements"
            if ! git ls-remote --exit-code --heads origin "$HEAD" >/dev/null 2>&1; then
                log ERROR "Head branch \"$HEAD\" does not exist on origin. Ticketmaster failed to create it. Aborting."
                exit 1
            fi              
            PR_NUMBER=$(gh pr list -R "$REPO_SLUG" --head "$HEAD" --state open --json number --jq '.[0].number' 2>/dev/null || true)
            if [[ -z "$PR_NUMBER" ]]; then
                log ERROR "No open PR found for head branch \"$HEAD\". Aborting."
                exit 1
            fi
            [[ -n "$BRANCHES" ]] && BRANCHES+=$'\n'
            BRANCHES+="prd-${TICKET_NUM}"$'\t'"$PR_NUMBER"
        done
        ACTUAL_COUNT=$(echo "$BRANCHES" | grep -c .)
    fi

    if [[ -z "$BRANCHES" ]] || [[ "$ACTUAL_COUNT" != "$EXPECTED_COUNT" ]]; then
        log ERROR "Ticketmaster returned $ACTUAL_COUNT branch(es) for level \"$LEVEL\" but $EXPECTED_COUNT were expected. Aborting."
        exit 1
    fi

    log SUCCESS "Finished creating branches and PRDs for current level!"

    review_pull_requests "$BRANCHES"

    log INFO "Generating backpressure..."
    rm -f "$PR_TSV_FILE"
    while IFS=$'\t' read -r BASE_BRANCH_NAME _PR_NUMBER <&3; do
        BACKPRESSURE_BRANCH_NAME="$BASE_BRANCH_NAME-backpressure"

        # Fail-fast: if any backpressure loop fails, abort the entire run
        git checkout "$BASE_BRANCH_NAME" && git pull
        git checkout -b "$BACKPRESSURE_BRANCH_NAME"
        npm i && npm run backpressure
        git add .
        git diff --cached --quiet || git commit -m "feat(ai): Backpressure for $BASE_BRANCH_NAME"
        git push -u origin "$BACKPRESSURE_BRANCH_NAME"

        summarizer "$BACKPRESSURE_BRANCH_NAME" "$BASE_BRANCH_NAME"

        log SUCCESS "Generated backpressure for \"$BASE_BRANCH_NAME\"!"
    done 3<<< "$BRANCHES"

    BACKPRESSURE_BRANCHES=""
    if [[ -s "$PR_TSV_FILE" ]]; then
        BACKPRESSURE_BRANCHES=$(grep $'\t' "$PR_TSV_FILE" || true)
    fi

    if [[ -z "$BACKPRESSURE_BRANCHES" ]]; then
        log ERROR "No backpressure branches were generated for level \"$LEVEL\". Aborting."
        exit 1
    fi

    EXPECTED_BP_COUNT=$(echo "$BRANCHES" | grep -c .)
    ACTUAL_BP_COUNT=$(echo "$BACKPRESSURE_BRANCHES" | grep -c .)
    if [[ "$ACTUAL_BP_COUNT" != "$EXPECTED_BP_COUNT" ]]; then
        log ERROR "Generated $ACTUAL_BP_COUNT backpressure branch(es) for level \"$LEVEL\" but $EXPECTED_BP_COUNT were expected. Aborting."
        exit 1
    fi

    review_pull_requests "$BACKPRESSURE_BRANCHES"

    log INFO "Proceeding with implementation..."
    rm -f "$PR_TSV_FILE"
    while IFS=$'\t' read -r BASE_BRANCH_NAME _PR_NUMBER <&3; do
        # Fail-fast: if any ralph loop fails, abort the entire run
        git checkout "$BASE_BRANCH_NAME" && git pull
        npm i && npm run ralph -- "$FOLDER_NAME"
        git push -u origin "$BASE_BRANCH_NAME"

        summarizer "$BASE_BRANCH_NAME" maestro

        log SUCCESS "Finished implementation for \"$BASE_BRANCH_NAME\"!"
    done 3<<< "$BACKPRESSURE_BRANCHES"

    IMPLEMENTATION_BRANCHES=""
    if [[ -s "$PR_TSV_FILE" ]]; then
        IMPLEMENTATION_BRANCHES=$(grep $'\t' "$PR_TSV_FILE" || true)
    fi

    if [[ -z "$IMPLEMENTATION_BRANCHES" ]]; then
        log ERROR "No implementation branches were generated for level \"$LEVEL\". Aborting."
        exit 1
    fi

    EXPECTED_IMPL_COUNT=$(echo "$BACKPRESSURE_BRANCHES" | grep -c .)
    ACTUAL_IMPL_COUNT=$(echo "$IMPLEMENTATION_BRANCHES" | grep -c .)
    if [[ "$ACTUAL_IMPL_COUNT" != "$EXPECTED_IMPL_COUNT" ]]; then
        log ERROR "Generated $ACTUAL_IMPL_COUNT implementation branch(es) for level \"$LEVEL\" but $EXPECTED_IMPL_COUNT were expected. Aborting."
        exit 1
    fi

    review_pull_requests "$IMPLEMENTATION_BRANCHES"
done 3<<< "$TREE_LEVELS"

log INFO "Archiving plan and log..."
mv -f "$BLUEPRINT_FILE" "$FOLDER_NAME/plan.md"
mv -f "$BLUEPRINT_LEVELS_FILE" "$FOLDER_NAME/plan.levels"
mv -f "$LOG_FILE" "$FOLDER_NAME/maestro.log"
git add .
git commit -m "chore(ai): Add Maestro log for $FOLDER_NAME"
git push -u origin maestro

# FIXME: Check if implementation is according to original plan, if there are any broken tests, update them or create new ones, leverage both jest and playwright

log INFO "Opening final PR..."
summarizer maestro main
view_pull_requests

log INFO "Switching back to main..."
git checkout main

log SUCCESS "Done! Your requested implementation is ready to be reviewed and merged!"