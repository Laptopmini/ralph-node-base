#!/usr/bin/env bash
# summarizer.sh
#
# Provides the summarizer() function.
# Usage:
#   source .github/scripts/summarizer.sh
#   summarizer <head-branch> <base-branch>
#

summarizer() {
    if [[ $# -ne 2 ]]; then
        log ERROR "Usage: summarizer <head-branch> <base-branch>"
        return 1
    fi

    local HEAD_BRANCH="$1"
    local BASE_BRANCH="$2"

    # --- Step 1: Extract ticket number from head branch ---
    local TICKET_NUM=""
    if [[ "$HEAD_BRANCH" =~ prd-([0-9]+) ]]; then
        TICKET_NUM="${BASH_REMATCH[1]}"
    fi

    local COMMIT_PREFIX="feat(ai)"
    if [[ -n "$TICKET_NUM" ]]; then
        COMMIT_PREFIX="feat(${TICKET_NUM})"
    fi

    # --- Step 2: Generate the diff ---
    local DIFF_OUTPUT
    DIFF_OUTPUT=$(git diff "${BASE_BRANCH}..${HEAD_BRANCH}")
    if [[ -z "$DIFF_OUTPUT" ]]; then
        log ERROR "git diff produced no output for ${BASE_BRANCH}..${HEAD_BRANCH}"
        return 1
    fi

    # --- Step 3: Build prompt from template ---
    local TEMPLATE_FILE=".github/prompts/summarizer.md"
    if [[ ! -s "$TEMPLATE_FILE" ]]; then
        log ERROR "Prompt template '$TEMPLATE_FILE' does not exist or is empty."
        return 1
    fi

    local TEMPLATE
    TEMPLATE=$(cat "$TEMPLATE_FILE")

    # Render placeholders with awk gsub.
    # The diff is appended raw after the template to avoid
    # awk special-character corruption (& and \ in code diffs).
    local RENDERED
    RENDERED=$(awk \
        -v head_branch="$HEAD_BRANCH" \
        -v base_branch="$BASE_BRANCH" \
        -v commit_prefix="$COMMIT_PREFIX" \
    '{
        line = $0
        gsub(/\{\{HEAD_BRANCH\}\}/, head_branch, line)
        gsub(/\{\{BASE_BRANCH\}\}/, base_branch, line)
        gsub(/\{\{COMMIT_PREFIX\}\}/, commit_prefix, line)
        print line
    }' <<< "$TEMPLATE")

    # Append the raw diff after the "## Diff" heading (blank line for markdown)
    RENDERED="${RENDERED}

${DIFF_OUTPUT}"

    # --- Step 4: Execute via prompt() ---
    prompt "$RENDERED" --allowedTools "Write" --model qwen/qwen3.5-35b-a3b

    # --- Step 5: Extract title and prepare PR body ---
    local BODY_FILE=".maestro.summary.md"
    if [[ ! -s "$BODY_FILE" ]]; then
        log ERROR "Agent did not produce $BODY_FILE"
        return 1
    fi

    # Title is on line 1 as "# feat(N): Title" — extract without the leading #
    local PR_TITLE
    PR_TITLE=$(head -1 "$BODY_FILE" | sed 's/^#\+ *//')
    if [[ -z "$PR_TITLE" ]]; then
        log ERROR "Could not extract PR title from $BODY_FILE"
        return 1
    fi

    # Strip the title line and any leading blank lines from the body
    tail -n +2 "$BODY_FILE" | sed '/./,$!d' > "${BODY_FILE}.tmp"
    mv "${BODY_FILE}.tmp" "$BODY_FILE"

    # --- Step 6: Open PR ---
    local REPO_SLUG="${REPO_SLUG:-$(bash .github/scripts/helpers/repo-slug.sh)}"

    local PR_URL
    PR_URL=$(gh pr create \
        --repo "$REPO_SLUG" \
        --head "$HEAD_BRANCH" \
        --base "$BASE_BRANCH" \
        --title "$PR_TITLE" \
        --body-file "$BODY_FILE")

    local PR_NUMBER
    PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')

    rm -f "$BODY_FILE"

    printf '%s\t%s\n' "$BASE_BRANCH" "$PR_NUMBER" >> .maestro.pull-requests.tsv

    log INFO "Opened PR #${PR_NUMBER}: ${PR_TITLE}"
}
