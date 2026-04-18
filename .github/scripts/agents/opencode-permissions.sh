#!/usr/bin/env bash
# bash opencode-permissions.sh <allowed> [disallowed]
# allowed: comma-separated list of tools to allow
# disallowed: comma-separated list of tools to disallow

set -euo pipefail

get_opencode_permissions() {
    local ALLOWED_INPUT=$(echo "${1:-}" | sed 's/^"//; s/"$//')
    local DISALLOWED_INPUT=$(echo "${2:-}" | sed 's/^"//; s/"$//')

    # If neither input is provided, return nothing
    if [ -z "$ALLOWED_INPUT" ] && [ -z "$DISALLOWED_INPUT" ]; then
        return 0
    fi

    # 'Agent' permission is called `task` in OpenCode
    ALLOWED_INPUT="${ALLOWED_INPUT//Agent/task}"
    DISALLOWED_INPUT="${DISALLOWED_INPUT//Agent/task}"

    local NEW_PERMISSIONS=$(jq -Rn \
        --arg allowed "$ALLOWED_INPUT" \
        --arg disallowed "$DISALLOWED_INPUT" '
        def parse_list(s):
            if (s | length) == 0 then []
            else (s | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
            end;

        def apply(perm; action):
            if (perm | test("\\(.*\\)$")) then
                (perm | split("(") | .[0] | ascii_downcase) as $key |
                (perm | capture("\\((?<val>.*)\\)$") | .val) as $val |
                if (.[$key] | type) == "object" then
                    .[$key] += {($val): action}
                elif (.[$key] | type) == "string" then
                    .[$key] = {"*": .[$key], ($val): action}
                else
                    .[$key] = {($val): action}
                end
            else
                .[perm | ascii_downcase] = action
            end;

        reduce parse_list($allowed)[] as $perm ({"*": "deny"}; apply($perm; "allow"))
        | reduce parse_list($disallowed)[] as $perm (.; apply($perm; "deny"))
    ')

    echo "$NEW_PERMISSIONS"
}