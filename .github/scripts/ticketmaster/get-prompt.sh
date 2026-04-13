#!/usr/bin/env bash

# ==============================================================================
# GET-PROMPT: Build a ticketmaster prompt for a single ticket.
# Usage: ./get-prompt.sh <blueprint-file> <ticket-number>
#
# Reads the blueprint, extracts the plan-level context (everything before the
# first "#### Ticket" heading) and the specific ticket section, then renders
# the prompt template from .github/prompts/ticketmaster.md with placeholders
# filled in. Outputs the rendered prompt to stdout.
# ==============================================================================

set -euo pipefail

source .github/scripts/helpers/log.sh

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <blueprint-file> <ticket-number>" >&2
    exit 1
fi

BLUEPRINT="$1"
TICKET_NUM="$2"

if [ ! -s "$BLUEPRINT" ]; then
    log ERROR "Blueprint file '$BLUEPRINT' does not exist or is empty." >&2
    exit 1
fi

TEMPLATE_FILE=".github/prompts/ticketmaster.md"
if [ ! -s "$TEMPLATE_FILE" ]; then
    log ERROR "Prompt template '$TEMPLATE_FILE' does not exist or is empty." >&2
    exit 1
fi

# Extract plan-level context (everything before the first #### Ticket heading)
PLAN_CONTEXT=$(awk '
    /^#### Ticket [0-9]+/ { exit }
    { print }
' "$BLUEPRINT")

# Extract the specific ticket section (from its heading to the next heading or EOF)
# Also captures the title from the heading line.
TICKET_SECTION=$(awk -v num="$TICKET_NUM" '
    BEGIN { found = 0 }
    /^#### Ticket [0-9]+/ {
        if (found) exit
        tmp = $0
        sub(/^#### Ticket /, "", tmp)
        ord = tmp + 0
        if (ord == num) {
            found = 1
            next
        }
    }
    found {
        # Strip depends_on lines
        stripped = $0
        sub(/^[ \t]*/, "", stripped)
        lower = tolower(stripped)
        if (index(lower, "**depends_on:**") == 1) next
        print
    }
' "$BLUEPRINT")

# Extract the ticket title from the heading line
TICKET_TITLE=$(awk -v num="$TICKET_NUM" '
    $0 ~ "^#### Ticket " num ":" {
        sub(/^#### Ticket [0-9]+: */, "")
        print
        exit
    }
' "$BLUEPRINT")

if [ -z "$TICKET_SECTION" ]; then
    log ERROR "Ticket $TICKET_NUM not found in '$BLUEPRINT'." >&2
    exit 1
fi

if [ -z "$TICKET_TITLE" ]; then
    log ERROR "Could not parse title for Ticket $TICKET_NUM from '$BLUEPRINT'." >&2
    exit 1
fi

# Read template and perform placeholder substitution
TEMPLATE=$(cat "$TEMPLATE_FILE")

# Use awk for safe multi-line substitution (bash string replacement can't
# handle newlines in the replacement value reliably across all shells).
RENDERED=$(awk \
    -v plan_ctx="$PLAN_CONTEXT" \
    -v ticket_sec="$TICKET_SECTION" \
    -v ticket_num="$TICKET_NUM" \
    -v ticket_title="$TICKET_TITLE" \
'{
    line = $0
    gsub(/\{\{PLAN_CONTEXT\}\}/, plan_ctx, line)
    gsub(/\{\{TICKET_SECTION\}\}/, ticket_sec, line)
    gsub(/\{\{TICKET_NUMBER\}\}/, ticket_num, line)
    gsub(/\{\{TICKET_TITLE\}\}/, ticket_title, line)
    print line
}' <<< "$TEMPLATE")

printf '%s\n' "$RENDERED"
