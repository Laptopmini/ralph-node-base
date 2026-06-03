#!/usr/bin/env bash

# ==============================================================================
# BACKPRESSURE GENERATOR: Generate tests based on current PRD
# Usage: ./backpressure.sh
# ==============================================================================

set -euo pipefail

source .github/scripts/agents/prompt.sh
source .github/scripts/helpers/log.sh

# Main

LEDGER=$(tail -n 5 .agent-ledger.jsonl || echo "No history.")
PRD=$(cat PRD.md)

log INFO "Starting to generate backpressure..."

# Static test-authoring rules live in .github/prompts/backpressure.md and are
# passed as a (cacheable) system prompt; only the per-run context goes here.
AGENT_PROMPT="
--- ARCHITECTURAL HISTORY (Last 5 Entries) ---

$LEDGER

--- PRD ---

$PRD
"

prompt "$AGENT_PROMPT" --cli claude --systemPromptFile .github/prompts/backpressure.md --allowedTools "Read,Write,Edit,Glob,Grep,Bash(npm run lint),Bash(npm run check-types),Bash(npm test),Bash(npx jest:*),Bash(npx tsc:*),Bash(npx biome:*),Bash(npm install -D *),Bash(bash tests/scripts/*)"  --model "${SENIOR_DEVELOPER_MODEL:-claude-opus-4-6}"

log INFO "Backpressure prompt completed."
