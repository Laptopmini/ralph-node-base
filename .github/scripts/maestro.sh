#!/usr/bin/env bash

# ==============================================================================
# MAESTRO: Automate the entire process
# Usage: ./maestro.sh <Your feature request paragraph>
# ==============================================================================

# FIXME: Leverage custom --systemPrompt so that directives can be stronger in Ralph and Repair agents (look at gains from prompt caching through iterations)

# FIXME: Include current log output in the final review stage

set -euo pipefail

source .github/scripts/helpers/ask.sh
source .github/scripts/helpers/log.sh
source .github/scripts/agents/prompt.sh
source .github/scripts/summarizer.sh
source .github/scripts/helpers/notify.sh
source .github/scripts/review.sh

bash .github/scripts/helpers/greeting.sh

# Settings

LOCK_FILE=".maestro.lock"
LOG_FILE="/tmp/maestro.log"
LOG_FILE_BACKUP="maestro.log"
BLUEPRINT_FILE=".maestro.blueprint.md"
BLUEPRINT_LEVELS_FILE=".maestro.blueprint.levels"
PR_TSV_FILE=".maestro.pull-requests.tsv"
PR_SUMMARY_FILE=".maestro.summary.md"
FOLDER_FILE=".maestro.folder"

# Models

export PROJECT_MANAGER_MODEL="claude-opus-4-7" # Planning
export STAFF_DEVELOPER_MODEL="claude-opus-4-6" # Supervising
export SENIOR_DEVELOPER_MODEL="openrouter/deepseek/deepseek-v4-pro" # Backpressure
export JUNIOR_DEVELOPER_MODEL="minimax/MiniMax-M2.7" # Implementation
export INTERN_DEVELOPER_MODEL="google/gemma-4-26b-a4b" # Writing Pull Requests

# Variables

export REPO_SLUG=$(bash .github/scripts/helpers/repo-slug.sh)
export PR_SUMMARY_FILE
export BLUEPRINT_FILE

# Environment variables

MISSING_MINIMAX_API_KEY=false
MISSING_OPENROUTER_API_KEY=false

if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
    log INFO "Loaded .env file."

    if [[ -z "$MINIMAX_API_KEY" || "$MINIMAX_API_KEY" == "<insert-key-here>" ]]; then
        MISSING_MINIMAX_API_KEY=true
    fi

    if [[ -z "$OPENROUTER_API_KEY" || "$OPENROUTER_API_KEY" == "<insert-key-here>" ]]; then
        MISSING_OPENROUTER_API_KEY=true
    fi
else
    MODEL_VARS=(
        "PROJECT_MANAGER_MODEL"
        "STAFF_DEVELOPER_MODEL"
        "SENIOR_DEVELOPER_MODEL"
        "JUNIOR_DEVELOPER_MODEL"
        "INTERN_DEVELOPER_MODEL"
    )

    for var_name in "${MODEL_VARS[@]}"; do
        value="${!var_name}"

        if [[ "$value" == minimax/* ]]; then
            MISSING_MINIMAX_API_KEY=true
            break
        elif [[ "$value" == openrouter/* ]]; then
            MISSING_OPENROUTER_API_KEY=true
            break
        fi
    done
    log INFO "No .env file found."
fi

if [[ "$MISSING_MINIMAX_API_KEY" == "true" ]]; then
    log ERROR "Missing MINIMAX_API_KEY in .env file. Please set it to your API key."
    exit 1
fi

if [[ "$MISSING_OPENROUTER_API_KEY" == "true" ]]; then
    log ERROR "Missing OPENROUTER_API_KEY in .env file. Please set it to your API key."
    exit 1
fi

# Functions

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
    rm -f "$LOCK_FILE" "$LOG_FILE" "$LOG_FILE_BACKUP" "$PR_TSV_FILE" "$PR_SUMMARY_FILE" ".maestro.screenshot.png"
    if [[ $exit_code -eq 0 ]]; then
        rm -f "$BLUEPRINT_FILE" "$BLUEPRINT_LEVELS_FILE" "$FOLDER_FILE"
    elif [[ $exit_code -ne 130 ]]; then
        notify "Maestro encountered an error. Please review the logs for more information." 2>/dev/null || true
    fi
}

# Main

if [ -e "$LOCK_FILE" ]; then
    log ERROR "Maestro is already running! Exiting..."
    exit 1
fi

trap cleanup EXIT
trap 'exit 130' INT HUP TERM
touch "$LOCK_FILE"

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
        rm -f "$FOLDER_FILE"
        BLUEPRINT_PROMPT_BODY=$(cat .github/prompts/blueprint.md 2>/dev/null || echo "")
        if [[ -z "$BLUEPRINT_PROMPT_BODY" ]]; then
            log ERROR "Blueprint prompt missing at .github/prompts/blueprint.md. Aborting."
            exit 1
        fi

        STYLE_CONTEXT=""
        FEATURE_URL=$(echo "$*" | grep -oiE 'https?://[^ ]+' | head -1 || true)
        if [[ -n "$FEATURE_URL" ]]; then
            log INFO "Analyzing reference URL: $FEATURE_URL"
            set +e
            STYLE_JSON=$(node .github/scripts/helpers/analyze_style.js "$FEATURE_URL" 2>&1)
            STYLE_EXIT=$?
            set -e

            if [[ $STYLE_EXIT -ne 0 ]]; then
                log WARN "Style analysis failed (exit $STYLE_EXIT) for $FEATURE_URL — skipping visual reference."
                log WARN "$STYLE_JSON"
            elif [[ -n "$STYLE_JSON" ]]; then
                STYLE_CONTEXT="
--- VISUAL REFERENCE ---

The feature request references a URL. A style analysis tool was run against it.

Screenshot saved to: .maestro.screenshot.png (use the Read tool to view it)

Extracted styles:
$STYLE_JSON

Use these extracted values as the basis for Design Intent tokens (colors, fonts, etc.) rather than inventing values. The screenshot shows the actual visual appearance — read it to understand layout, spacing, and visual motifs.

"
            fi
        fi

        BLUEPRINT_PROMPT="$BLUEPRINT_PROMPT_BODY
$STYLE_CONTEXT
--- HUMAN FEATURE REQUEST ---

$*
"
        prompt "$BLUEPRINT_PROMPT" \
            --allowedTools "Read,Glob,Grep,Write($BLUEPRINT_FILE),Edit($BLUEPRINT_FILE),Write($BLUEPRINT_LEVELS_FILE),Edit($BLUEPRINT_LEVELS_FILE),Agent" \
            --model "$PROJECT_MANAGER_MODEL"

        if [[ ! -s "$BLUEPRINT_FILE" || ! -s "$BLUEPRINT_LEVELS_FILE" ]]; then
            log WARN "Blueprint agent did not produce both artifacts. Retrying in 5s..."
            rm -f "$BLUEPRINT_FILE" "$BLUEPRINT_LEVELS_FILE"
            sleep 5
            continue
        fi
        TREE_LEVELS=$(cat "$BLUEPRINT_LEVELS_FILE")
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
        rm -f "$BLUEPRINT_FILE" "$BLUEPRINT_LEVELS_FILE" "$FOLDER_FILE"

        if [ -z "$*" ] && ! $REUSING_EXISTING_PLAN; then
            log ERROR "User declined existing plan, but no feature(s) request paragraph/description provided."
            log ERROR "Usage: $0 [Your feature request paragraph]"
            exit 1
        fi

        log WARN "User did not approve plan, trying again..."
        continue
    fi

    if [[ -s "$FOLDER_FILE" ]]; then
        FOLDER_NAME=$(cat "$FOLDER_FILE")
        log INFO "Resuming with archive destination: $FOLDER_NAME"
    else
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

        echo "$FOLDER_NAME" > "$FOLDER_FILE"
        mkdir -p "$FOLDER_NAME"
        cp "$BLUEPRINT_LEVELS_FILE" "$FOLDER_NAME/plan.levels"
        log INFO "Using $FOLDER_NAME as archive destination."
    fi
done

if [[ ! -s "$BLUEPRINT_FILE" ]]; then
    log ERROR "An issue occurred while preparing the implementation plan and its related files. Aborting."
    exit 1
fi

log INFO "Proceeding through implementation tree levels..."
while IFS= read -r LEVEL <&3; do
    log INFO "Beginning level \"$LEVEL\"..."
    BRANCHES=""

    log INFO "Generating PRD(s)..."
    for TICKET_NUM in $(echo "$LEVEL" | tr ',' '\n' | grep .); do
        bash .github/scripts/ticketmaster/checkout.sh "$TICKET_NUM"
        bash .github/scripts/ticketmaster/generate-prd.sh "$BLUEPRINT_FILE" "$TICKET_NUM"

        PRD_BRANCH="prd-$TICKET_NUM"
        if ! git ls-remote --exit-code --heads origin "$PRD_BRANCH" >/dev/null 2>&1; then
            log ERROR "PRD branch \"$PRD_BRANCH\" does not exist on origin. Ticketmaster failed to create it. Aborting."
            exit 1
        fi

        if ! git cat-file -e "$PRD_BRANCH:PRD.md" >/dev/null 2>&1; then
            log ERROR "PRD.md does not exist in branch '$BRANCH'. Aborting." >&2
            exit 1
        fi

        BRANCHES+="$PRD_BRANCH"$'\n'
    done
    log SUCCESS "Finished creating branches and PRDs for current level!"

    log INFO "Generating backpressure..."
    rm -f "$PR_TSV_FILE"
    while read -r BASE_BRANCH_NAME <&3; do
        BACKPRESSURE_BRANCH_NAME="$BASE_BRANCH_NAME-backpressure"

        git checkout "$BASE_BRANCH_NAME" && git pull
        git checkout -b "$BACKPRESSURE_BRANCH_NAME"
        npm i && npm run backpressure
        git add .
        git diff --cached --quiet || git commit -m "feat(ai): Backpressure for $BASE_BRANCH_NAME"
        git push -u origin "$BACKPRESSURE_BRANCH_NAME"

        summarizer "$BACKPRESSURE_BRANCH_NAME" "$BASE_BRANCH_NAME"

        log SUCCESS "Generated backpressure for \"$BASE_BRANCH_NAME\"!"
    done 3<<< "${BRANCHES%$'\n'}"

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
        git checkout "$BASE_BRANCH_NAME" && git pull

        export MAESTRO_TICKET_NUM="${BASE_BRANCH_NAME#prd-}"
        npm i && npm run ralph -- "$FOLDER_NAME"
        git push -u origin "$BASE_BRANCH_NAME"

        summarizer "$BASE_BRANCH_NAME" maestro

        log SUCCESS "Finished implementation for \"$BASE_BRANCH_NAME\"!"
    done 3<<< "$BACKPRESSURE_BRANCHES"
    unset MAESTRO_TICKET_NUM

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

    tail -n +2 "$BLUEPRINT_LEVELS_FILE" > "$BLUEPRINT_LEVELS_FILE.tmp"
    mv -f "$BLUEPRINT_LEVELS_FILE.tmp" "$BLUEPRINT_LEVELS_FILE"
    log SUCCESS "Completed implementation level \"$LEVEL\"!"
done 3<<< "$TREE_LEVELS"

log INFO "Running implementation review..."
review_implementation "$FOLDER_NAME"

log INFO "Archiving plan and log..."
mv -f "$BLUEPRINT_FILE" "$FOLDER_NAME/plan.md"
mv -f "$LOG_FILE" "$FOLDER_NAME/maestro.log"
git add .
git commit -m "chore(ai): Add Maestro log for $FOLDER_NAME"
git push -u origin maestro

log INFO "Opening final PR..."
summarizer maestro main
view_pull_requests

log SUCCESS "Done! Your requested implementation is ready to be reviewed and merged!"