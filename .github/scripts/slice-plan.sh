#!/usr/bin/env bash

# ==============================================================================
# SLICE-PLAN: Extract a per-level slice of an implementation plan.
# Usage: ./slice-plan.sh <blueprint-file> <comma-separated-ticket-ordinals> <output-path>
#
# Writes a markdown file containing the plan header (everything before the first
# "#### Ticket " heading) plus only the "#### Ticket N" sections whose ordinal N
# is in the level list. Strips "**depends_on:**" lines from kept sections.
# ==============================================================================

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <blueprint-file> <ticket-ordinals> <output-path>" >&2
    exit 1
fi

SRC="$1"
LEVEL="$2"
OUT="$3"

if [ ! -s "$SRC" ]; then
    echo "❌ Error: Blueprint file '$SRC' does not exist or is empty." >&2
    exit 1
fi

if [ -z "$LEVEL" ]; then
    echo "❌ Error: Empty ticket ordinal list." >&2
    exit 1
fi

EXPECTED_COUNT=$(echo "$LEVEL" | tr ',' '\n' | grep -c .)

awk -v keep="$LEVEL" '
BEGIN {
    n = split(keep, parts, ",")
    for (i = 1; i <= n; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", parts[i])
        keepset[parts[i]] = 1
    }
    in_header = 1
    keeping = 0
}
{
    line = $0
    if (line ~ /^#### Ticket [0-9]+/) {
        in_header = 0
        tmp = line
        sub(/^#### Ticket /, "", tmp)
        ord = tmp + 0
        keeping = (ord in keepset) ? 1 : 0
        if (keeping) print line
        next
    }
    if (in_header) {
        # End header at top-level "## " after we have started? We end at first ticket heading.
        print line
        next
    }
    if (keeping) {
        # Strip depends_on lines (case-insensitive, allow leading whitespace)
        stripped = line
        sub(/^[ \t]*/, "", stripped)
        lower = tolower(stripped)
        if (index(lower, "**depends_on:**") == 1) next
        print line
    }
}
' "$SRC" > "$OUT"

ACTUAL_COUNT=$(grep -c '^#### Ticket ' "$OUT" || true)
if [ "$ACTUAL_COUNT" != "$EXPECTED_COUNT" ]; then
    echo "❌ Error: slice-plan expected $EXPECTED_COUNT ticket section(s) for level [$LEVEL] but wrote $ACTUAL_COUNT to '$OUT'." >&2
    exit 1
fi

echo "⚪️ Wrote sliced plan to $OUT ($ACTUAL_COUNT ticket section(s))."
