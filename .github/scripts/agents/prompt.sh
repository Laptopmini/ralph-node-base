#!/usr/bin/env bash
# prompt.sh
# 
# Usage:
#   source ./prompt.sh
#   prompt "<agent prompt>" [options]
# 
# Exit codes:
#   0 = success
#   2 = rate limit / quota / credit exhausted (caller may want to back off long)
#   1 = other engine failure                 (caller may want to retry short)


set -euo pipefail

source .github/scripts/agents/opencode-permissions.sh

prompt() {
    # Parse arguments
    if [[ $# -lt 1 ]]; then
        log ERROR "Usage: prompt \"<agent prompt>\" [extra args...]" >&2
        return 1
    fi

    if ! command -v jq &> /dev/null; then
        log ERROR "jq is not installed." >&2
        return 1
    fi

    local AGENT_PROMPT="$1"
    shift

    local MODEL="haiku" # Defaults to cheapest Anthropic model
    local CLI="opencode" # Default to OpenCode unless using Anthropic models
    local BASH_MAX_TIMEOUT=2500000 # Used for all bash commands executed by the agent

    local ALLOWED=""
    local EXTRA_ARGS=()
    local LOCAL_ENV=()

    # Parse arguments to capture --model value
    local ARGS=("$@")                                                                                                                                                                   
    local i=0                                                                                                                                                                           
    while [[ $i -lt ${#ARGS[@]} ]]; do
        local arg="${ARGS[$i]}"
        
        case "$arg" in
            --model)
                if (( i + 1 < ${#ARGS[@] })) && [[ "${ARGS[$((i+1))]}" != --* ]]; then
                    MODEL="${ARGS[$((i+1))]}"
                    ((i+=2)) || true
                    continue
                fi ;;
            --cli)
                if (( i + 1 < ${#ARGS[@] })) && [[ "${ARGS[$((i+1))]}" != --* ]]; then
                    CLI="${ARGS[$((i+1))]}"
                    ((i+=2)) || true
                    continue
                fi ;;
            --allowedTools)
                if (( i + 1 < ${#ARGS[@] })) && [[ "${ARGS[$((i+1))]}" != --* ]]; then
                    ALLOWED="${ARGS[$((i+1))]}"
                    ((i+=2)) || true
                    continue
                fi ;;
        esac
        
        EXTRA_ARGS+=("$arg")
        ((i++)) || true
    done

    if [[ "$MODEL" != "opus" && "$MODEL" != "sonnet" && "$MODEL" != "haiku" ]]; then
        bash .github/scripts/agents/load-model.sh "$MODEL"

        if [[ "$CLI" == "claude" ]]; then
            # Determine the max context window size for the model
            local MAX_CONTEXT_WINDOW=4000
            case "$MODEL" in
                qwen/qwen3.5-35b-a3b)
                    MAX_CONTEXT_WINDOW=262144
                    ;;
                google/gemma-4-26b-a4b)
                    MAX_CONTEXT_WINDOW=120000
                    ;;
                *)
                    log WARN "Model $MODEL does not have a max context window size! Using default of $MAX_CONTEXT_WINDOW." >&2
                    ;;
            esac

            # Setup Claude Code environment variables for LM Studio
            LOCAL_ENV=(
                ANTHROPIC_BASE_URL="http://localhost:1234"
                ANTHROPIC_AUTH_TOKEN="lmstudio"
                # Force all Claude Code model selections (Opus, Sonnet, Haiku) to route through local model
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
                BASH_MAX_TIMEOUT_MS="$BASH_MAX_TIMEOUT"
                # Context Window Settings
                CLAUDE_CODE_AUTO_COMPACT_WINDOW="$MAX_CONTEXT_WINDOW" # Max context window tokens
                CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="90" # Compaction triggers at 90% usage
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
            # FIXME: If MiniMax-M2.7, use `minimax` provider
            LOCAL_ENV=(
                OPENCODE_PERMISSION="$(get_opencode_permissions "$ALLOWED")" # Inlined json permissions config
                OPENCODE_CUSTOM_PROVIDER="lmstudio"
                OPENCODE_CUSTOM_PROVIDER_NAME="LM Studio (local)"
                OPENCODE_CUSTOM_MODEL="$MODEL"
                OPENCODE_CUSTOM_MODEL_NAME="$MODEL"
                OPENCODE_MODEL="$OPENCODE_CUSTOM_PROVIDER/$MODEL"
                OPENCODE_AUTO_SHARE=false # Disable automatically shared sessions
                OPENCODE_DISABLE_AUTOUPDATE=true # Disable automatic update checks
                OPENCODE_DISABLE_MOUSE=true # Disable mouse support
                OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=$([[ "$AGENT_PROMPT" = /* ]] && echo false || echo true) # Disable Claude Code skills if not using command
                OPENCODE_DISABLE_LSP_DOWNLOAD=true # Disable LSP download
                OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=true # Disable reading .CLAUDE.md file
                # Experimental settings
                OPENCODE_EXPERIMENTAL_BASH_DEFAULT_TIMEOUT_MS=$BASH_MAX_TIMEOUT # Increase bash timeout
                # OPENCODE_EXPERIMENTAL_PLAN_MODE=true # Enable experimental plan mode
            )
        fi
    else
        # Always use Claude CLI with Anthropic models
        CLI="claude"
        LOCAL_ENV=(
            ANTHROPIC_MODEL="$MODEL"
        )
    fi

    log WARN "Handing control to $MODEL using $CLI..." >&2

    local ENGINE_EXIT=0

    if [[ "$CLI" == "claude" ]]; then
        if ! command -v claude &> /dev/null; then
            log ERROR "Claude CLI is not installed." >&2
            return 1
        fi

        local RAW
        local CLAUDE_CONTEXT_TEMP_FILE=".maestro.claude.tmp"

        # Include the allowed tools if provided
        if [[ -n "$ALLOWED" ]]; then
            EXTRA_ARGS+=("--allowedTools" "$ALLOWED")
        fi
        
        # Move the .CLAUDE.md file to a temp file to avoid it being read by the agent
        mv -f "CLAUDE.md" "$CLAUDE_CONTEXT_TEMP_FILE"

        set +e
        RAW=$(mktemp)
        env "${LOCAL_ENV[@]}" claude -p "$AGENT_PROMPT" \
            --output-format stream-json --verbose \
            "${EXTRA_ARGS[@]}" 2>&1 \
            | tee "$RAW" \
            | tee >(jq -r --unbuffered 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' >&2) \
            | jq -r 'select(.type=="result") | .result'
        ENGINE_EXIT=${PIPESTATUS[0]}
        set -e

        # Move the temp file back to .CLAUDE.md
        mv -f "$CLAUDE_CONTEXT_TEMP_FILE" "CLAUDE.md"

        if jq -e 'select(.type=="result") | select(.is_error==true)' "$RAW" >/dev/null 2>&1; then
            local ERR=$(jq -r 'select(.type=="result" and .is_error==true) | .result // .error // "(no detail)"' /tmp/prompt_output_$$ | head -n1)
            log ERROR "Claude returned an error result: $ERR" >&2
            rm -f "$RAW"
            return 1
        fi

        if [[ "$RAW" == *"rate_limit_error"* ]] || \
        [[ "$RAW" == *"insufficient_quota"* ]] || \
        [[ "$RAW" == *"billing_error"* ]]; then
            log ERROR "Claude rate limit exceeded." >&2
            rm -f "$RAW"
            return 2
        fi

        rm -f "$RAW"
    elif [[ "$CLI" == "opencode" ]]; then
        if ! command -v opencode &> /dev/null; then
            log ERROR "OpenCode CLI is not installed." >&2
            return 1
        fi

        env "${LOCAL_ENV[@]}" opencode run "$AGENT_PROMPT" "${EXTRA_ARGS[@]}"
        ENGINE_EXIT=$?
    else
        # FIXME: Add support for Aider (https://aider.chat/)
        log ERROR "$CLI CLI is not supported." >&2
        return 1
    fi

    if [[ $ENGINE_EXIT -ne 0 ]]; then
        log ERROR "$CLI exited with code $ENGINE_EXIT." >&2
        return 1
    fi
}
