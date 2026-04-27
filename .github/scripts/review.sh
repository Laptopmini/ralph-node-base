#!/usr/bin/env bash
# review.sh
#
# Provides the review_implementation() function.
# Usage:
#   source .github/scripts/review.sh
#   review_implementation <archive-folder>
#

review_implementation() {
    if [[ $# -ne 1 ]]; then
        log ERROR "Usage: review_implementation <archive-folder>"
        return 1
    fi

    local ARCHIVE_FOLDER="$1"

    # --- Step 1: Load the review prompt ---
    local REVIEW_PROMPT_BODY
    REVIEW_PROMPT_BODY=$(cat .github/prompts/review.md 2>/dev/null || echo "")
    if [[ -z "$REVIEW_PROMPT_BODY" ]]; then
        log ERROR "Review prompt missing at .github/prompts/review.md. Skipping review."
        return 1
    fi

    # --- Step 2: Gather context ---
    local BLUEPRINT_CONTEXT=""
    if [[ -s "${BLUEPRINT_FILE:-}" ]]; then
        BLUEPRINT_CONTEXT=$(cat "$BLUEPRINT_FILE")
    else
        log WARN "Blueprint file not found. Review will proceed without blueprint context."
    fi

    local LEDGER_CONTEXT=""
    if [[ -s ".agent-ledger.jsonl" ]]; then
        LEDGER_CONTEXT=$(cat .agent-ledger.jsonl)
    else
        LEDGER_CONTEXT="No ledger history available."
    fi

    # --- Step 3: Compose the full prompt ---
    local REVIEW_PROMPT="
$REVIEW_PROMPT_BODY

--- IMPLEMENTATION BLUEPRINT ---

$BLUEPRINT_CONTEXT

--- AGENT LEDGER (full history) ---

$LEDGER_CONTEXT

--- ARCHIVE FOLDER ---

$ARCHIVE_FOLDER
"

    # --- Step 4: Call the review agent ---
    log INFO "Running review agent..."

    set +e
    local REVIEW_OUTPUT
    REVIEW_OUTPUT=$(prompt "$REVIEW_PROMPT" \
        --allowedTools "Read,Edit,Write,Glob,Grep,Bash" \
        --disallowedTools "Bash(git:*),Bash(npm install*)" \
        --model "${SENIOR_DEVELOPER_MODEL:-claude-opus-4-6}")
    local REVIEW_EXIT=$?
    set -e

    if [[ $REVIEW_EXIT -ne 0 ]]; then
        log ERROR "Review agent failed (exit $REVIEW_EXIT). Skipping review."
        return 1
    fi

    # --- Step 5: Parse the structured output ---
    local VERDICT
    VERDICT=$(echo "$REVIEW_OUTPUT" | sed -n 's/.*<verdict>\(.*\)<\/verdict>.*/\1/p' | head -n1)

    local FIXED_ISSUES
    FIXED_ISSUES=$(echo "$REVIEW_OUTPUT" | awk '/<fixed-issues>/{flag=1; next} /<\/fixed-issues>/{flag=0} flag')

    local UNFIXED_ISSUES
    UNFIXED_ISSUES=$(echo "$REVIEW_OUTPUT" | awk '/<unfixed-issues>/{flag=1; next} /<\/unfixed-issues>/{flag=0} flag')

    local PROCESS_IMPROVEMENTS
    PROCESS_IMPROVEMENTS=$(echo "$REVIEW_OUTPUT" | awk '/<process-improvements>/{flag=1; next} /<\/process-improvements>/{flag=0} flag')

    log INFO "Review verdict: ${VERDICT:-(none)}"

    # --- Step 6: Save the review report ---
    mkdir -p "$ARCHIVE_FOLDER"
    local REPORT_FILE="$ARCHIVE_FOLDER/review-report.md"

    cat > "$REPORT_FILE" <<REPORT_EOF
# Review Report

**Verdict:** ${VERDICT:-unknown}

## Fixed Issues
${FIXED_ISSUES:-None.}

## Unfixed Issues (Require Human Attention)
${UNFIXED_ISSUES:-None.}

## Process Improvement Suggestions
${PROCESS_IMPROVEMENTS:-None.}
REPORT_EOF

    log INFO "Review report saved to $REPORT_FILE"

    # --- Step 7: Commit fixes if any were made ---
    if [[ "$VERDICT" == "fixes-applied" || "$VERDICT" == "needs-attention" ]]; then
        git add .
        git diff --cached --quiet || git commit -m "fix(ai): Review phase corrections"
    fi

    # --- Step 8: Handle verdict ---
    case "$VERDICT" in
        clean)
            log SUCCESS "Review complete. Implementation matches blueprint."
            ;;
        fixes-applied)
            log SUCCESS "Review complete. Minor fixes were applied and committed."
            ;;
        needs-attention)
            log WARN "Review found issues requiring human attention."
            log WARN "See $REPORT_FILE for details."
            notify "Maestro review found issues that need your attention. Check $REPORT_FILE."

            if command -v code &>/dev/null; then
                code "$REPORT_FILE"
            fi

            ask_continue "💬 Review report has unfixed issues. Press any key to continue with archiving, or Ctrl+C to abort..."
            ;;
        *)
            log WARN "Review returned unexpected verdict: ${VERDICT:-(empty)}. Continuing."
            ;;
    esac
}
