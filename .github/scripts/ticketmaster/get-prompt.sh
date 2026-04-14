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

# Strip trailing blank lines and "---" separators from extracted blueprint sections.
# This prevents duplicating the "---" that the template already supplies after each placeholder.
strip_trailing_separator() {
    awk '
        { lines[NR] = $0 }
        END {
            end = NR
            while (end > 0 && (lines[end] ~ /^[[:space:]]*$/ || lines[end] ~ /^---/)) end--
            for (i = 1; i <= end; i++) print lines[i]
        }
    '
}

# Extract plan-level context (everything before the first #### Ticket heading)
PLAN_CONTEXT=$(awk '
    /^#### Ticket [0-9]+/ { exit }
    { print }
' "$BLUEPRINT" | strip_trailing_separator)

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
' "$BLUEPRINT" | strip_trailing_separator)

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

# Use awk for safe multi-line substitution (bash string replacement can't
# handle newlines in the replacement value reliably across all shells).
# Set environment variables to avoid issues with newlines in command-line args.
export PLAN_CONTEXT
export TICKET_SECTION
export TICKET_NUM
export TICKET_TITLE

RENDERED=$(awk '
    BEGIN {
        plan_ctx = ENVIRON["PLAN_CONTEXT"]
        ticket_sec = ENVIRON["TICKET_SECTION"]
        ticket_num = ENVIRON["TICKET_NUM"]
        ticket_title = ENVIRON["TICKET_TITLE"]
        # Escape \ and & in replacement strings so awk gsub treats them literally.
        # Order matters: escape \ first, then &.
        gsub(/\\/, "\\\\", plan_ctx);   gsub(/&/, "\\&", plan_ctx)
        gsub(/\\/, "\\\\", ticket_sec);  gsub(/&/, "\\&", ticket_sec)
        gsub(/\\/, "\\\\", ticket_title); gsub(/&/, "\\&", ticket_title)
    }
    {
        line = $0
        gsub(/\{\{PLAN_CONTEXT\}\}/, plan_ctx, line)
        gsub(/\{\{TICKET_SECTION\}\}/, ticket_sec, line)
        gsub(/\{\{TICKET_NUMBER\}\}/, ticket_num, line)
        gsub(/\{\{TICKET_TITLE\}\}/, ticket_title, line)
        print line
    }
' "$TEMPLATE_FILE")

printf '%s\n' "$RENDERED"
