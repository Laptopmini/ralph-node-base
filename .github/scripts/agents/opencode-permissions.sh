#!/usr/bin/env bash

set -euo pipefail

get_opencode_permissions() {
    local INPUT=$(echo "$1" | sed 's/^"//; s/"$//')
    local OPENCODE_FILE="opencode.json"

    # If no input is provided, return empty permissions
    if [ -z "$INPUT" ]; then
        return ""
    fi

    # Use jq to parse and build the JSON structure entirely
    local NEW_PERMISSIONS=$(echo "$INPUT" | jq -Rn '
        input | split(",") | map(gsub("^\\s+|\\s+$"; "")) |

        reduce .[] as $perm ({"*": "deny"};
            if ($perm | test("\\(.*\\)$")) then
                ($perm | split("(") | .[0] | ascii_downcase) as $key |
                ($perm | capture("\\((?<val>.*)\\)$") | .val) as $val |
                .[$key] = ((.[$key] // {}) + {($val): "allow"})
            else
                .[$perm | ascii_downcase] = "allow"
            end
        )
    ')

    echo "$NEW_PERMISSIONS"
}