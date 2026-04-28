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
MAX_LOOPS=5 # This is the maximum number of iterations per task before supervisor intervention
TYPE_CHECK_CMD="npm run check-types"
UNIT_TEST_CMD="npx jest --silent --no-verbose"
LINT_TEST_CMD="npm run lint"

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
TOTAL_REPAIRS=0
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
        mkdir -p "$ARCHIVE_FOLDER"

        PRD_TITLE=$(head -1 PRD.md | sed -E 's/^#+ (PRD: )?//')
        PRD_FILENAME=$(echo "$PRD_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed -E 's/-+/-/g' | sed -E 's/^-|-$//g')

        ARCHIVE_PATH="$ARCHIVE_FOLDER/PRD.$PRD_FILENAME.md"

        COUNTER=1
        while [[ -f $ARCHIVE_PATH ]]; do
            ARCHIVE_PATH="$ARCHIVE_FOLDER/PRD.$PRD_FILENAME.$COUNTER.md"
            ((COUNTER++))
        done

        log INFO "Archiving PRD to $ARCHIVE_PATH..."
        mv PRD.md "$ARCHIVE_PATH"

        git add .
        git commit -m "chore(ai): Archived PRD & Cleanup"
        break
    fi

    TARGETED_TEST=$(echo "$CURRENT_TASK" | sed -n 's/.*`\[test: \(.*\)\]`.*/\1/p')

    if [ -z "$TARGETED_TEST" ]; then
        log WARN "No targeted test found for this task. Defaulting to full suite."
        TARGETED_TEST="npm test"
    else
        log INFO "Targeted Backpressure Found: $TARGETED_TEST"
    fi

    LEDGER_CONTEXT=$(tail -n 5 .agent-ledger.jsonl 2>/dev/null || echo "No history.")
    
    if [[ "$LOOP_COUNTER" -ge "$MAX_LOOPS" ]]; then
        log WARN "Max loops reached for task. Escalating to repair agent before aborting..."

        REPAIR_PROMPT_BODY=$(cat .github/prompts/repair.md 2>/dev/null || echo "")
        if [[ -z "$REPAIR_PROMPT_BODY" ]]; then
            log ERROR "Repair prompt missing at .github/prompts/repair.md. Aborting."
            exit 1
        fi

        REPAIR_BLUEPRINT_CONTEXT=""
        if [[ -n "${BLUEPRINT_FILE:-}" && -s "${BLUEPRINT_FILE}" && -n "${MAESTRO_TICKET_NUM:-}" ]]; then
            REPAIR_BLUEPRINT_CONTEXT=$(awk -v num="${MAESTRO_TICKET_NUM}" '
                BEGIN { found = 0 }
                /^#### Ticket [0-9]+/ {
                    if (found) exit
                    tmp = $0; sub(/^#### Ticket /, "", tmp)
                    if ((tmp + 0) == num) { found = 1 }
                }
                found { print }
            ' "${BLUEPRINT_FILE}")
        fi

        REPAIR_PROMPT="
$REPAIR_PROMPT_BODY

--- ACTIVE PRD TASK (the loop is stuck here) ---

$CURRENT_TASK

--- LAST FAILING VALIDATION ---

Command: $TARGETED_TEST

Output:
$TEST_OUTPUT

--- ARCHITECTURAL HISTORY (Last 5 Entries) ---

$LEDGER_CONTEXT

--- TICKET BLUEPRINT (design intent) ---

$REPAIR_BLUEPRINT_CONTEXT
"

        set +e
        REPAIR_OUTPUT=$(prompt "$REPAIR_PROMPT" \
            --allowedTools "Read,Edit,Write,Glob,Grep,Bash" \
            --disallowedTools "Bash(git:*),Bash(npm test*),Bash(npm run test*),Bash($TYPE_CHECK_CMD*),Bash(npx jest*),Bash(npx playwright*),Bash(npx tsc*)" \
            --model "${STAFF_DEVELOPER_MODEL:-claude-opus-4-6}")
        REPAIR_EXIT=$?
        set -e

        if [[ $REPAIR_EXIT -ne 0 ]]; then
            log ERROR "Repair agent failed (exit $REPAIR_EXIT). Aborting."
            exit 1
        fi

        REPAIR_VERDICT=$(echo "$REPAIR_OUTPUT" | sed -n 's/.*<verdict>\(.*\)<\/verdict>.*/\1/p' | head -n1)
        REPAIR_SUMMARY=$(echo "$REPAIR_OUTPUT" | awk '/<summary>/{flag=1; sub(/.*<summary>/,""); } /<\/summary>/{sub(/<\/summary>.*/,""); print; exit} flag{print}')

        log INFO "Repair verdict: ${REPAIR_VERDICT:-(none)}"
        log INFO "Repair summary: ${REPAIR_SUMMARY:-(none)}"

        case "$REPAIR_VERDICT" in
            code-fix)
                log INFO "Repair patched code directly. Resetting loop counter and error feedback."
                TOTAL_LOOPS=$((TOTAL_LOOPS+LOOP_COUNTER))
                TOTAL_REPAIRS=$((TOTAL_REPAIRS+1))
                LOOP_COUNTER=0
                ERROR_FEEDBACK=""
                continue
                ;;
            backpressure-bug)
                git add .
                if git diff --cached --quiet; then
                    log ERROR "⚠️ Repair declared backpressure-bug but made no file changes. Aborting."
                    exit 1
                fi
                git commit -m "fix(ai): Repair backpressure for stuck task" || true
                log INFO "Backpressure patched. Resetting loop counter and error feedback."
                TOTAL_LOOPS=$((TOTAL_LOOPS+LOOP_COUNTER))
                TOTAL_REPAIRS=$((TOTAL_REPAIRS+1))
                LOOP_COUNTER=0
                ERROR_FEEDBACK=""
                continue
                ;;
            abort|*)
                log ERROR "⚠️ Repair declined to recover. Aborting."
                log ERROR "${REPAIR_SUMMARY:-(no summary)}"
                exit 1
                ;;
        esac
    fi

    LOOP_COUNTER=$((LOOP_COUNTER+1))

    log INFO "------------------------- Iteration $((LOOP_COUNTER))/$MAX_LOOPS (Total: $((LOOP_COUNTER + $TOTAL_LOOPS))) -------------------------"
    log INFO "Active Task:
    $CURRENT_TASK"

    log INFO "Assembling Context Window..."

    RALPH_PROMPT=$(cat .github/prompts/ralph.md 2>/dev/null || echo "")

    if [[ -z "$RALPH_PROMPT" ]]; then
        log ERROR "Ralph prompt missing at .github/prompts/ralph.md. Aborting."
        exit 1
    fi

    MEMORY_CONTEXT=$(cat MEMORY.md 2>/dev/null || echo "Scratchpad empty.")
    PRD_CONTENT=$(awk '
        { print }
        ENVIRON["CURRENT_TASK"] == $0 { exit }
    ' PRD.md)

    AGENT_PROMPT="
$RALPH_PROMPT

--- ARCHITECTURAL HISTORY (Last 5 Entries) ---

$LEDGER_CONTEXT

--- YOUR PREVIOUS NOTES ---

$MEMORY_CONTEXT

--- YOUR CURRENT TASK ---

$PRD_CONTENT${ERROR_FEEDBACK:+$'\n'}$ERROR_FEEDBACK
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
    ALLOWED_PREFIXES=("npm test" "npx jest" "npx tsc" "npx biome" "bash tests/scripts")
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

    UNCHECKED_COUNT=$(grep -c "^\s*- \[ \]" PRD.md || true)

    # By default, we run typecheck, lint, and the targeted test command
    COMBINED_VALIDATION=("$TYPE_CHECK_CMD" "$LINT_TEST_CMD" "$TARGETED_TEST")

    # If there were previous tasks, run their validation commands to prevent regression within the current PRD
    if [[ ${#PREVIOUS_TASK_VALIDATION[@]} -gt 0 ]]; then
        COMBINED_VALIDATION+=("${PREVIOUS_TASK_VALIDATION[@]}")
    fi

    # If this is the last task, include all available tests to cover any possible regressions in the project
    if [ "$UNCHECKED_COUNT" -eq 1 ]; then
        restore_backpressure

        COMBINED_VALIDATION=("$TYPE_CHECK_CMD" "$LINT_TEST_CMD")

        shopt -s nullglob
        for file in tests/unit/*.test.tsx; do
            if [[ -f "$file" ]]; then
                FOUND_TEST_COMMAND="npx jest $file"
                COMBINED_VALIDATION+=("$FOUND_TEST_COMMAND")
                if [[ "$FOUND_TEST_COMMAND" != "$TARGETED_TEST" ]]; then
                    PREVIOUS_TASK_VALIDATION_LOOKUP[$FOUND_TEST_COMMAND]=1
                fi
            fi
        done
        for file in tests/scripts/*.sh; do
            if [[ -f "$file" ]]; then
                FOUND_TEST_COMMAND="bash $file"
                COMBINED_VALIDATION+=("$FOUND_TEST_COMMAND")
                if [[ "$FOUND_TEST_COMMAND" != "$TARGETED_TEST" ]]; then
                    PREVIOUS_TASK_VALIDATION_LOOKUP[$FOUND_TEST_COMMAND]=1
                fi
            fi
        done
        shopt -u nullglob
    fi

    # Remove duplicates while preserving order
    declare -A _seen=()
    DEDUPED_VALIDATION=()
    for cmd in "${COMBINED_VALIDATION[@]}"; do
        if [[ -z "${_seen[$cmd]:-}" ]]; then
            _seen[$cmd]=1
            DEDUPED_VALIDATION+=("$cmd")
        fi
    done
    COMBINED_VALIDATION=("${DEDUPED_VALIDATION[@]}")
    unset _seen

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

log INFO "👋 Ralph Loop ended after $TOTAL_LOOPS iteration(s), including $TOTAL_REPAIRS repair(s)!"
