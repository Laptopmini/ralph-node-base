#!/usr/bin/env bash

# ==============================================================================
# GENERATE-PRD: Deterministically convert a blueprint ticket into PRD.md.
# Usage: ./generate-prd.sh <blueprint-file> <ticket-number>
#
# Replaces the previous LLM-based ticketmaster. Parses the blueprint's
# [tag, short-title] annotations to derive test commands without ambiguity.
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
    log ERROR "Blueprint file '$BLUEPRINT' does not exist or is empty."
    exit 1
fi

# Extract ticket title from heading line: "#### Ticket N: Title"
TICKET_TITLE=$(awk -v num="$TICKET_NUM" '
    $0 ~ "^#### Ticket " num ":" {
        sub(/^#### Ticket [0-9]+: */, "")
        print
        exit
    }
' "$BLUEPRINT")

if [ -z "$TICKET_TITLE" ]; then
    log ERROR "Could not parse title for Ticket $TICKET_NUM from '$BLUEPRINT'."
    exit 1
fi

# Extract numbered task lines from the ticket section.
# Task lines match: N. [tag, short-title] description...
TASKS=$(awk -v num="$TICKET_NUM" '
    BEGIN { found = 0 }
    /^#### Ticket [0-9]+/ {
        if (found) exit
        tmp = $0; sub(/^#### Ticket /, "", tmp)
        if ((tmp + 0) == num) { found = 1; next }
    }
    found && /^[0-9]+\. \[/ { print }
' "$BLUEPRINT")

if [ -z "$TASKS" ]; then
    log ERROR "No tasks found for Ticket $TICKET_NUM in '$BLUEPRINT'."
    exit 1
fi

# Build PRD content
{
    printf '# PRD: %s\n\n## Tasks\n' "$TICKET_TITLE"

    while IFS= read -r line; do
        # Parse: N. [tag, short-title] description...
        tag=$(printf '%s' "$line" | sed -E 's/^[0-9]+\. \[([a-z]+), .*/\1/')
        short_title=$(printf '%s' "$line" | sed -E 's/^[0-9]+\. \[[a-z]+, ([a-z0-9-]+)\] .*/\1/')
        description=$(printf '%s' "$line" | sed -E 's/^[0-9]+\. \[[a-z]+, [a-z0-9-]+\] //')

        if [ "$tag" = "infra" ]; then
            test_cmd="bash tests/scripts/${short_title}.sh"
        else
            test_cmd="npx jest tests/unit/${short_title}.test.tsx"
        fi

        printf '\n- [ ] %s `[test: %s]`' "$description" "$test_cmd"
    done <<< "$TASKS"

    printf '\n'
} > PRD.md

log SUCCESS "Generated PRD.md for Ticket $TICKET_NUM: $TICKET_TITLE"
