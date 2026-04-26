#!/usr/bin/env bash
set -euo pipefail

source .github/scripts/helpers/log.sh

# Validate that the required arguments are provided
if [ $# -lt 2 ]; then
    log ERROR "Missing arguments." >&2
    log ERROR "Usage: $0 <ticket_number> \"<ticket_title>\"" >&2
    exit 1
fi

TICKET_NUMBER="$1"
TICKET_TITLE="$2"

# Determine current repo slug
REPO_SLUG="${REPO_SLUG:-$(bash .github/scripts/helpers/repo-slug.sh)}"

# Define branch names based on the ticket number
BASE_BRANCH="prd-$TICKET_NUMBER"
HEAD_BRANCH="prd-$TICKET_NUMBER-requirements"

if [[ ! -s PRD.md ]]; then
    log ERROR "There is no PRD file generated. Aborting."
    exit 1
fi

# Perform Git operations
git add PRD.md
git commit -m "feat($TICKET_NUMBER): Created PRD for $TICKET_TITLE"
git push -u origin "$HEAD_BRANCH"

# Create Pull Request
gh pr create \
    --repo "$REPO_SLUG" \
    --base "$BASE_BRANCH" \
    --head "$HEAD_BRANCH" \
    --title "prd($TICKET_NUMBER): $TICKET_TITLE" \
    --body "This PR is for requirements being generated into PRD.md for Ticket $TICKET_NUMBER."

# Capture the PR number by querying the branch details
PR_NUMBER=$(gh pr view "$HEAD_BRANCH" --repo "$REPO_SLUG" --json number --jq '.number')

if [ -z "$PR_NUMBER" ]; then
    log ERROR "Could not retrieve PR number for $HEAD_BRANCH." >&2
    exit 1
fi

# Append the mapping to the TSV file (Tab Separated)
printf '%s\t%s\n' "$BASE_BRANCH" "$PR_NUMBER" >> .maestro.pull-requests.tsv

log SUCCESS "Branches, PRD and PR created for ticket $TICKET_NUMBER!"
