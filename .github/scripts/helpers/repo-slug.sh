#!/usr/bin/env bash
set -euo pipefail

# Outputs the GitHub owner/repo slug from the origin remote URL.
git remote get-url origin | sed -E 's#(https?://github\.com/|git@github\.com:)##' | sed 's/\.git$//'
