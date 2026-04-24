#!/usr/bin/env bash

# ==============================================================================
# RALPH LOOP: The test-gated, autonomous AI development cycle
# Usage: ./ralph.sh <ARCHIVE_FOLDER>
# ==============================================================================

set -euo pipefail

source .github/scripts/helpers/log.sh
source .github/scripts/agents/prompt.sh
source .github/scripts/helpers/isolator.sh

# Settings

LOCK_FILE=".ralph.lock"
MAX_LOOPS=10 # This is the maximum number of iterations per task
TYPE_CHECK_CMD="npm run check-types"
UNIT_TEST_CMD="npx jest --silent --no-verbose"
E2E_TEST_CMD="npx playwright test --reporter=line"

# Main

if [ -e "$LOCK_FILE" ]; then
    log ERROR "Ralph Loop is already running! Exiting..."
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE && restore_backpressure" EXIT
trap 'exit 130' INT HUP TERM

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
TOTAL_LOOPS=0
PREVIOUS_TASK_VALIDATION=()
declare -A PREVIOUS_TASK_VALIDATION_LOOKUP

isolate_backpressure

while true; do
    log INFO "Parsing Active Task & Target Test..."

    CURRENT_TASK=$(grep -m 1 "^\s*- \[ \]" PRD.md || true)
    export CURRENT_TASK

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
        log ERROR "⚠️ Max loops reached for task:
    $CURRENT_TASK
    Aborting..."
        exit 1
    fi

    LOOP_COUNTER=$((LOOP_COUNTER+1))

    log INFO "------------------------- Iteration $((LOOP_COUNTER))/$MAX_LOOPS (Total: $((LOOP_COUNTER + $TOTAL_LOOPS))) -------------------------"
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
    PRD_CONTENT=$(awk '
        { print }
        ENVIRON["CURRENT_TASK"] == $0 { exit }
    ' PRD.md)

    AGENT_PROMPT="
$RALPH_PROMPT${ERROR_FEEDBACK:+$'\n'}$ERROR_FEEDBACK

--- ARCHITECTURAL HISTORY (Last 5 Entries) ---

$LEDGER_CONTEXT

--- YOUR PREVIOUS NOTES (MEMORY.md) ---

$MEMORY_CONTEXT

--- YOUR CURRENT TASK ---

$PRD_CONTENT
"

    ERROR_FEEDBACK=""

    restore_backpressure "$TARGETED_TEST"

    set +e
    OUTPUT=$(prompt "$AGENT_PROMPT" \
        --allowedTools "Read,Edit,Write,Glob,Grep,Bash" \
        --disallowedTools "Bash(git:*),Bash(npm test*),Bash(npm run test*),Bash($TYPE_CHECK_CMD*),Bash(npx jest*),Bash(npx playwright*),Bash(npx tsc*)" \
        --model "${JUNIOR_DEVELOPER_MODEL:-claude-sonnet-4-6}")
    PROMPT_EXIT=$?
    set -e

    case $PROMPT_EXIT in
        0)
            ;;  # Prompt succeeded
        2)
            log WARN "Rate limit hit. Waiting 15 minutes..."
            sleep 900
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

    log INFO "Determining validation commands..."
    ALLOWED_PREFIXES=("npm test" "npx jest" "npx tsc" "npx biome" "bash scripts/")
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

    TASK_VALIDATION=()
    UNCHECKED_COUNT=$(grep -c "^\s*- \[ \]" PRD.md || true)

    # Make sure to lint unless biome is already being used
    if [[ "$TARGETED_TEST" != "npm run lint"* ]]; then
        TASK_VALIDATION+=("npm run lint")
    fi

    # Add the targeted test command
    TASK_VALIDATION+=("$TARGETED_TEST")

    # Combine the required task validations into a single array
    COMBINED_VALIDATION=("${TASK_VALIDATION[@]}")
    if [ "$UNCHECKED_COUNT" -eq 1 ]; then
        # If this is the last task, include a final typecheck & full test suite
        COMBINED_VALIDATION+=("$TYPE_CHECK_CMD")
        PREVIOUS_TASK_VALIDATION_LOOKUP[$TYPE_CHECK_CMD]=1

        if ls -A tests/unit | grep -q .; then
            COMBINED_VALIDATION+=("$UNIT_TEST_CMD")
            PREVIOUS_TASK_VALIDATION_LOOKUP[$UNIT_TEST_CMD]=1
        fi

        if ls -A tests/e2e | grep -q .; then
            COMBINED_VALIDATION+=("$E2E_TEST_CMD")
            PREVIOUS_TASK_VALIDATION_LOOKUP[$E2E_TEST_CMD]=1
        fi

        # Restore all backpressure
        restore_backpressure
    elif [[ ${#PREVIOUS_TASK_VALIDATION[@]} -gt 0 ]]; then
        # Make sure previous tasks are still passing
        COMBINED_VALIDATION+=("${PREVIOUS_TASK_VALIDATION[@]}")
    fi

    # FIXME: Remove duplicate validations, multiple `npx tsc --noEmit` for example

    for TEST_COMMAND in "${COMBINED_VALIDATION[@]}"; do
        log INFO "Running Validation: $TEST_COMMAND"
        set +e
        TEST_OUTPUT=$(eval "$TEST_COMMAND" 2>&1)
        TEST_EXIT_CODE=$?
        set -e
        
        if [ $TEST_EXIT_CODE -ne 0 ]; then
            break;
        fi
    done

    if [ $TEST_EXIT_CODE -eq 0 ]; then
        log SUCCESS "Task passed! Continuing..."
        CURRENT_TASK_LABEL="Iteration $((LOOP_COUNTER + 1))"

        PREVIOUS_TASK_VALIDATION+=("$TARGETED_TEST")
        PREVIOUS_TASK_VALIDATION_LOOKUP[$TARGETED_TEST]=1
        
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

        awk '{
            if (!done && $0 == ENVIRON["CURRENT_TASK"]) {
                sub(/- \[ \]/, "- [x]")
                done = 1
            }
            print
        }' PRD.md > PRD.md.tmp && mv PRD.md.tmp PRD.md
        
        git add .
        git commit -m "feat(ai): $CURRENT_TASK_LABEL"

        TOTAL_LOOPS=$((TOTAL_LOOPS+LOOP_COUNTER))
        LOOP_COUNTER=0
    else
        log ERROR "Validation failed. The agent must try again."
        log INFO "Test Output:\n$TEST_COMMAND\n$TEST_OUTPUT"

        ERROR_FEEDBACK_HEADER="YOUR LAST ATTEMPT FAILED!
        You tried to complete the task, but the validation failed."
        if [[ ${PREVIOUS_TASK_VALIDATION_LOOKUP[$TEST_COMMAND]:-} ]]; then
            ERROR_FEEDBACK_HEADER="YOUR LAST ATTEMPT CAUSED A REGRESSION!
        You successfully implemented the task, but a previously working validation is now failing."
        fi

        ERROR_FEEDBACK="
        $ERROR_FEEDBACK_HEADER
        
        Test Command: $TEST_COMMAND
        Exit Code: $TEST_EXIT_CODE
        
        Test Output / Error Logs:
        $TEST_OUTPUT
        
        Please analyze the error, fix the code, and try again.
        "

        log WARN "Retrying in 5 seconds... (Ctrl+C to abort)"
        sleep 5
    fi

    log INFO "Looping..."
done

remove_backpressure

log INFO "👋 Ralph Loop ended after $TOTAL_LOOPS successful iteration(s)!"
