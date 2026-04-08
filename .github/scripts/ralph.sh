#!/usr/bin/env bash

# ==============================================================================
# RALPH LOOP: The test-gated, autonomous AI development cycle
# Usage: ./ralph.sh <ARCHIVE_FOLDER>
# ==============================================================================

set -euo pipefail

# Settings

LOCK_FILE=".ralph.lock"
MAX_LOOPS=10

# Functions

prompt() { bash .github/scripts/prompt.sh "$@"; }

# Main

if [ -e "$LOCK_FILE" ]; then
    echo "❌ Error: Ralph Loop is already running! Exiting..."
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

if [[ -z "${1:-}" ]]; then
    echo "❌ Error: ARCHIVE_FOLDER argument is required."
    echo "Usage: $0 <ARCHIVE_FOLDER>"
    exit 1
fi
ARCHIVE_FOLDER="$1"
shift

if [ ! -f PRD.md ]; then
    echo "❌ Error: PRD.md not found."
    exit 1
fi

echo "🟢 Starting Ralph Loop for at most $MAX_LOOPS iterations..."

ERROR_FEEDBACK=""
LOOP_COUNTER=0

while true; do
    echo "------------------------- Iteration $((LOOP_COUNTER + 1))/$MAX_LOOPS -------------------------"
    echo "Parsing Active Task & Target Test..."

    CURRENT_TASK=$(grep -m 1 "^\s*- \[ \]" PRD.md || true)

    if [ -z "$CURRENT_TASK" ]; then
        echo "🎉 No incomplete tasks found in PRD.md. Cleaning up..."

        rm -rf MEMORY.md

        PRD_TITLE=$(head -1 PRD.md | sed -E 's/^#+ (PRD: )?//')
        PRD_FILENAME=$(echo "$PRD_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed -E 's/-+/-/g' | sed -E 's/^-|-$//g')

        ARCHIVE_PATH="$ARCHIVE_FOLDER/PRD.$PRD_FILENAME.md"

        COUNTER=1
        while [[ -f $ARCHIVE_PATH ]]; do
            ARCHIVE_PATH="$ARCHIVE_FOLDER/PRD.$PRD_FILENAME.$COUNTER.md"
            ((COUNTER++))
        done

        echo "Archiving PRD to $ARCHIVE_PATH..."
        mkdir -p "$ARCHIVE_FOLDER"
        mv PRD.md "$ARCHIVE_PATH"

        git add .
        git commit -m "chore(ai): Archived PRD & Cleanup"
        break
    fi

    if [[ "$LOOP_COUNTER" -ge "$MAX_LOOPS" ]]; then
        echo "⚠️ Max loops reached!"
        break
    fi

    LOOP_COUNTER=$((LOOP_COUNTER+1))

    echo "Active Task:
    $CURRENT_TASK"

    TARGETED_TEST=$(echo "$CURRENT_TASK" | sed -n 's/.*`\[test: \(.*\)\]`.*/\1/p')

    if [ -z "$TARGETED_TEST" ]; then
        echo "No targeted test found for this task. Defaulting to full suite."
        TARGETED_TEST="npm test"
    else
        echo "Targeted Backpressure Found: $TARGETED_TEST"
    fi

    echo "Assembling Context Window..."

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
            echo "🟠 Rate limit hit. Waiting 1 hour..."
            sleep 3600
            LOOP_COUNTER=$((LOOP_COUNTER - 1))
            continue
            ;;
        *)
            echo "🟠 Engine failed (exit $PROMPT_EXIT). Retrying in 5s..."
            sleep 5
            continue
            ;;
    esac

    echo "Agent finished. Extracting proposed state updates..."
    PROPOSED_MEMORY=$(echo "$OUTPUT" | awk '/<memory>/{flag=1; next} /<\/memory>/{flag=0} flag')
    PROPOSED_LEDGER=$(echo "$OUTPUT" | awk '/<ledger>/{flag=1; next} /<\/ledger>/{flag=0} flag')

    echo "Running Validation: $TARGETED_TEST"
    ALLOWED_PREFIXES=("npm test" "npx jest" "npx playwright" "npx tsc" "npx biome")
    ALLOWED=false
    for prefix in "${ALLOWED_PREFIXES[@]}"; do
        if [[ "$TARGETED_TEST" == "$prefix"* ]]; then
            ALLOWED=true
            break
        fi
    done

    if [[ "$ALLOWED" != "true" ]]; then
        echo "❌ Blocked test command: '$TARGETED_TEST'"
        echo "   Only commands starting with: ${ALLOWED_PREFIXES[*]} are permitted."
        echo "   Fix the [test: ...] annotation in PRD.md and re-run."
        exit 1
    fi
    set +e
    TEST_OUTPUT=$(eval "$TARGETED_TEST" 2>&1)
    TEST_EXIT_CODE=$?
    set -e

    if [ $TEST_EXIT_CODE -eq 0 ]; then
        echo "🟢 Task passed! Continuing..."
        CURRENT_TASK_LABEL="Iteration $((LOOP_COUNTER + 1))"
        
        if [ -n "$PROPOSED_MEMORY" ]; then
            echo "$PROPOSED_MEMORY" > MEMORY.md
            echo -e "Memory Updated:\n$PROPOSED_MEMORY"
        fi

        if [ -n "$PROPOSED_LEDGER" ]; then
            PROPOSED_LEDGER=$(printf '%s' "$PROPOSED_LEDGER" | tr -d '\n')
            CURRENT_TASK_LABEL=$(printf '%s' "$PROPOSED_LEDGER" | sed -nE 's/.*"task"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')
            if [ -s .agent-ledger.jsonl ] && [ -n "$(tail -c1 .agent-ledger.jsonl)" ]; then
                echo >> .agent-ledger.jsonl
            fi
            echo "$PROPOSED_LEDGER" >> .agent-ledger.jsonl
            echo -e "Ledger Entry Added:\n$PROPOSED_LEDGER"
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
        echo "🔴 Validation failed. The agent must try again."
        echo -e "Test Output:\n$TEST_OUTPUT"

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

    echo "Looping..."
done

echo "👋 Ralph Loop ended!"
