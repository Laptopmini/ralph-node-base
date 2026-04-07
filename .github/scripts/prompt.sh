#!/usr/bin/env bash
# Usage: prompt.sh "<agent prompt>" [extra args...]
# Returns agent output on stdout. Narrates progress + echoes agent output on stderr.
# 
# The engine is selected via the ENGINE environment variable. Default is claude.
# 
# Exit codes:
#   0  = success
#   2  = rate limit / quota / credit exhausted  (caller may want to back off long)
#   1  = other engine failure                   (caller may want to retry short)


set -euo pipefail

ENGINE="${ENGINE:-claude}"

if ! command -v $ENGINE &> /dev/null; then
    echo "❌ Error: $ENGINE CLI is not installed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq is not installed."
    exit 1
fi

AGENT_PROMPT="$1"
shift
EXTRA_ARGS=("$@")

# FIXME: Convert claude flags used to opencode flags
# --allowedTools
# --model

echo "🟡 Handing control to $ENGINE..." >&2

set +e
if [[ "$ENGINE" == "claude" ]]; then
    RAW=$(mktemp)
    OUTPUT=$(claude -p "$AGENT_PROMPT" \
        --output-format stream-json --verbose \
        "${EXTRA_ARGS[@]}" 2>&1 \
    | tee "$RAW" \
    | tee >(jq -r --unbuffered 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' >&2) \
    | jq -r 'select(.type=="result") | .result')
    ENGINE_EXIT=${PIPESTATUS[0]}
else
    # FIXME: Add support for opencode response json streaming & error handling
    OUTPUT=$(opencode run "$AGENT_PROMPT" "${EXTRA_ARGS[@]}" 2>&1 | tee /dev/stderr)
    ENGINE_EXIT=${PIPESTATUS[0]}
fi
set -e

if [[ "$ENGINE" == "claude" ]]; then
    if [[ "$OUTPUT" == *"rate_limit_error"* ]] || \
       [[ "$OUTPUT" == *"insufficient_quota"* ]] || \
       [[ "$OUTPUT" == *"credit balance"* ]]; then
        echo "🟠 Claude rate limit exceeded." >&2
        exit 2
    fi

    if jq -e 'select(.type=="result") | select(.is_error==true)' "$RAW" >/dev/null; then
        ERR=$(jq -r 'select(.type=="result" and .is_error==true) | .result // .error // "(no detail)"' "$RAW" | head -n1)
        echo "🟠 Claude returned an error result: $ERR" >&2
        rm -f "$RAW"
        exit 1
    fi
    rm -f "$RAW"
fi

if [[ $ENGINE_EXIT -ne 0 ]]; then
    echo "🟠 Engine exited with code $ENGINE_EXIT." >&2
    exit 1
fi

echo "$OUTPUT"
