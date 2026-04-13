#!/usr/bin/env bash

# ==============================================================================
# RALPH LOOP: The test-gated, autonomous AI development cycle
# Usage: ./ralph.sh <ARCHIVE_FOLDER>
# ==============================================================================

set -euo pipefail

source .github/scripts/helpers/log.sh
source .github/scripts/agents/prompt.sh

# Settings

LOCK_FILE=".ralph.lock"
MAX_LOOPS=10

# Main

if [ -e "$LOCK_FILE" ]; then
    log ERROR "Ralph Loop is already running! Exiting..."
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

if [[ -z "${1:-}" ]]; then
    log ERROR "ARCHIVE_FOLDER argument is required."
    log ERROR "Usage: $0 <ARCHIVE_FOLDER>"
    exit 1
fi
ARCHIVE_FOLDER="$1"
shift

if [ ! -f PRD.md ]; then
    log ERROR "PRD.md not found."
    exit 1
fi

log WARN "Starting Ralph Loop for at most $MAX_LOOPS iterations..."

ERROR_FEEDBACK=""
LOOP_COUNTER=0

while true; do
    log INFO "------------------------- Iteration $((LOOP_COUNTER + 1))/$MAX_LOOPS -------------------------"
    log INFO "Parsing Active Task & Target Test..."

    CURRENT_TASK=$(grep -m 1 "^\s*- \[ \]" PRD.md || true)

    if [ -z "$CURRENT_TASK" ]; then
        log SUCCESS "🎉 No incomplete tasks found in PRD.md. Cleaning up..."

        rm -rf MEMORY.md

        PRD_TITLE=$(head -1 PRD.md | sed -E 's/^#+ (PRD: )?//')
        PRD_FILENAME=$(echo "$PRD_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed -E 's/-+/-/g' | sed -E 's/^-|-$//g')

        ARCHIVE_PATH="$ARCHIVE_FOLDER/PRD.$PRD_FILENAME.md"

        COUNTER=1
        while [[ -f $ARCHIVE_PATH ]]; do
            ARCHIVE_PATH="$ARCHIVE_FOLDER/PRD.$PRD_FILENAME.$COUNTER.md"
            ((COUNTER++))
        done

        log INFO "Archiving PRD to $ARCHIVE_PATH..."
        mkdir -p "$ARCHIVE_FOLDER"
        mv PRD.md "$ARCHIVE_PATH"

        git add .
        git commit -m "chore(ai): Archived PRD & Cleanup"
        break
    fi

    if [[ "$LOOP_COUNTER" -ge "$MAX_LOOPS" ]]; then
        log ERROR "⚠️ Max loops reached!"
        exit 1
    fi

    LOOP_COUNTER=$((LOOP_COUNTER+1))

    log INFO "Active Task:
    $CURRENT_TASK"

    TARGETED_TEST=$(echo "$CURRENT_TASK" | sed -n 's/.*`\[test: \(.*\)\]`.*/\1/p')

    if [ -z "$TARGETED_TEST" ]; then
        log WARN "No targeted test found for this task. Defaulting to full suite."
        TARGETED_TEST="npm test"
    else
        log INFO "Targeted Backpressure Found: $TARGETED_TEST"
    fi

    log INFO "Assembling Context Window..."

    RALPH_PROMPT=$(cat .github/prompts/ralph.md 2>/dev/null || echo "You are an autonomous developer.")
    LEDGER_CONTEXT=$(tail -n 5 .agent-ledger.jsonl 2>/dev/null || echo "No history.")
    MEMORY_CONTEXT=$(cat MEMORY.md 2>/dev/null || echo "Scratchpad empty.")
    PRD_CONTENT=$(cat PRD.md)

    AGENT_PROMPT="
$RALPH_PROMPT${ERROR_FEEDBACK:+$'\n'}$ERROR_FEEDBACK

--- ARCHITECTURAL HISTORY (Last 5 Entries) ---

$LEDGER_CONTEXT

--- YOUR PREVIOUS NOTES (MEMORY.md) ---

$MEMORY_CONTEXT

--- YOUR CURRENT TASK (PRD.md) ---

$PRD_CONTENT
"

    ERROR_FEEDBACK=""

    set +e
    OUTPUT=$(prompt "$AGENT_PROMPT" \
        --allowedTools "Read,Edit,Write,Glob,Grep,Bash" \
        --model qwen/qwen3.5-35b-a3b)
    PROMPT_EXIT=$?
    set -e

    case $PROMPT_EXIT in
        0)
            ;;  # Prompt succeeded
        2)
            log WARN "Rate limit hit. Waiting 1 hour..."
            sleep 3600
            LOOP_COUNTER=$((LOOP_COUNTER - 1))
            continue
            ;;
        *)
            log WARN "Engine failed (exit $PROMPT_EXIT). Retrying in 5s..."
            sleep 5
            continue
            ;;
    esac

    log INFO "Agent finished. Extracting proposed state updates..."
    PROPOSED_MEMORY=$(echo "$OUTPUT" | awk '/<memory>/{flag=1; next} /<\/memory>/{flag=0} flag')
    PROPOSED_LEDGER=$(echo "$OUTPUT" | awk '/<ledger>/{flag=1; next} /<\/ledger>/{flag=0} flag')

    log INFO "Running Validation: $TARGETED_TEST"
    ALLOWED_PREFIXES=("npm test" "npx jest" "npx playwright" "npx tsc" "npx biome" "bash scripts/")
    ALLOWED=false
    for prefix in "${ALLOWED_PREFIXES[@]}"; do
        if [[ "$TARGETED_TEST" == "$prefix"* ]]; then
            ALLOWED=true
            break
        fi
    done

    if [[ "$ALLOWED" != "true" ]]; then
        log ERROR "Blocked test command: '$TARGETED_TEST'"
        log ERROR "   Only commands starting with: ${ALLOWED_PREFIXES[*]} are permitted."
        log ERROR "   Fix the [test: ...] annotation in PRD.md and re-run."
        exit 1
    fi
    set +e
    TEST_OUTPUT=$(eval "$TARGETED_TEST" 2>&1)
    TEST_EXIT_CODE=$?
    set -e

    if [ $TEST_EXIT_CODE -eq 0 ]; then
        log SUCCESS "Task passed! Continuing..."
        CURRENT_TASK_LABEL="Iteration $((LOOP_COUNTER + 1))"
        
        if [ -n "$PROPOSED_MEMORY" ]; then
            echo "$PROPOSED_MEMORY" > MEMORY.md
            log INFO "Memory Updated:\n$PROPOSED_MEMORY"
        fi

        if [ -n "$PROPOSED_LEDGER" ]; then
            PROPOSED_LEDGER=$(printf '%s' "$PROPOSED_LEDGER" | tr -d '\n')
            CURRENT_TASK_LABEL=$(printf '%s' "$PROPOSED_LEDGER" | sed -nE 's/.*"task"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')
            if [ -s .agent-ledger.jsonl ] && [ -n "$(tail -c1 .agent-ledger.jsonl)" ]; then
                echo >> .agent-ledger.jsonl
            fi
            echo "$PROPOSED_LEDGER" >> .agent-ledger.jsonl
            log INFO "Ledger Entry Added:\n$PROPOSED_LEDGER"
        fi

        awk -v task="$CURRENT_TASK" '{
            if (!done && $0 == task) {
                sub(/- \[ \]/, "- [x]")
                done = 1
            }
            print
        }' PRD.md > PRD.md.tmp && mv PRD.md.tmp PRD.md
        
        git add .
        git commit -m "chore(ai): $CURRENT_TASK_LABEL" 
    else
        log ERROR "Validation failed. The agent must try again."
        log INFO "Test Output:\n$TEST_OUTPUT"

        ERROR_FEEDBACK="
        YOUR LAST ATTEMPT FAILED!
        You tried to complete the task, but the validation test failed.
        
        Test Command: $TARGETED_TEST
        Exit Code: $TEST_EXIT_CODE
        
        Test Output / Error Logs:
        $TEST_OUTPUT
        
        Please analyze the error, fix the code, and try again.
        "

        echo "Retrying in 5 seconds... (Ctrl+C to abort)"
        sleep 5
    fi

    log INFO "Looping..."
done

log INFO "👋 Ralph Loop ended!"
