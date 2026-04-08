#!/usr/bin/env bash
# Usage: prompt.sh "<agent prompt>" [extra args...]
# Returns agent output on stdout. Narrates progress + echoes agent output on stderr.
# 
# Exit codes:
#   0  = success
#   2  = rate limit / quota / credit exhausted  (caller may want to back off long)
#   1  = other engine failure                   (caller may want to retry short)


set -euo pipefail

if ! command -v claude &> /dev/null; then
    echo "❌ Error: Claude CLI is not installed."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ Error: jq is not installed."
    exit 1
fi

AGENT_PROMPT="$1"
shift
MODEL="haiku"
EXTRA_ARGS=()
LOCAL_ENV=()

# Parse arguments to capture --model value
for arg in "$@"; do
    if [[ "$arg" == "--model="* ]]; then
        MODEL="${arg#--model=}"
    else
        EXTRA_ARGS+=("$arg")
    fi
done

if [[ "$MODEL" != "opus" && "$MODEL" != "sonnet" && "$MODEL" != "haiku" ]]; then
    # Make sure the model has been loaded
    bash .github/scripts/load-model.sh "$MODEL"

    # Setup Claude Code environment variables
    LOCAL_ENV=(
        ANTHROPIC_BASE_URL="http://localhost:1234"
        ANTHROPIC_AUTH_TOKEN="lmstudio"
        # Force all Claude Code model selections (Opus, Sonnet, Haiku) to route through local model.
        # Without these, Claude Code would try to call Anthropic model names that LM Studio does not recognize
        ANTHROPIC_MODEL="$MODEL"
        ANTHROPIC_CUSTOM_MODEL_OPTION="$MODEL"
        ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="LM Studio ($MODEL)"
        ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION="The local LM Studio server running the model $MODEL locally."
        ANTHROPIC_DEFAULT_OPUS_MODEL="$MODEL"
        ANTHROPIC_DEFAULT_SONNET_MODEL="$MODEL"
        ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL"
        CLAUDE_CODE_SUBAGENT_MODEL="$MODEL"
        # Extend shell command timeouts for long-running operations (40-42 minutes)
        BASH_DEFAULT_TIMEOUT_MS="2400000" 
        BASH_MAX_TIMEOUT_MS="2500000"
        # Context Window Settings
        CLAUDE_CODE_AUTO_COMPACT_WINDOW="$MAX_CONTEXT_WINDOW" # Max context window tokens
        CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="90" # Compaction triggers at 90% usage
        CLAUDE_CODE_MAX_OUTPUT_TOKENS="$MAX_TOKEN_OUTPUT_PER_REPONSE" # Token reponse output limit
        CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS="$MAX_TOKEN_OUTPUT_PER_REPONSE" # Other token reponse output limit
        # Miscellaneous settings
        API_TIMEOUT_MS="30000000" # Max out timeout for slower models (30 million ms / ~8.3 hours)
        CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY="2" # The model's max concurrent predictions setting in LM Studio
        CLAUDE_CODE_NO_FLICKER="0" # Disable flicker-free rendering mode
        CLAUDE_CODE_ATTRIBUTION_HEADER="0" # Disable special billing header (x-anthropic-billing-header)
        # Disable Claude features not compatible with open-source models
        CLAUDE_CODE_DISABLE_1M_CONTEXT="1"
        CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING="1"
    )
else
    LOCAL_ENV=(
        ANTHROPIC_MODEL="$MODEL"
    )
fi

echo "🟡 Handing control to $MODEL..." >&2

set +e
RAW=$(mktemp)
OUTPUT=$(env "${LOCAL_ENV[@]}" claude -p "$AGENT_PROMPT" \
    --output-format stream-json --verbose \
    "${EXTRA_ARGS[@]}" 2>&1 \
| tee "$RAW" \
| tee >(jq -r --unbuffered 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' >&2) \
| jq -r 'select(.type=="result") | .result')
ENGINE_EXIT=${PIPESTATUS[0]}
set -e

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

if [[ $ENGINE_EXIT -ne 0 ]]; then
    echo "🟠 Engine exited with code $ENGINE_EXIT." >&2
    exit 1
fi

echo "$OUTPUT"
