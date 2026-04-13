#!/usr/bin/env bash
set -euo pipefail

source .github/scripts/helpers/log.sh

if ! command -v npm &> /dev/null; then
    log ERROR "NPM is not installed."
    exit 1
fi

if [ -f package.json ]; then
    log ERROR "package.json already exists. Exiting..."
    exit 1
fi

# Initialize the npm project
npm init -y && \
npm pkg set scripts.test="jest && playwright test" \
            scripts.maestro="bash .github/scripts/maestro.sh" \
            scripts.backpressure="bash .github/scripts/backpressure.sh" \
            scripts.ralph="bash .github/scripts/ralph.sh" \
            scripts.lint="biome check --write ." \
            scripts.check-types="tsc --noEmit" \
            engines.node=">=24.14.1" \
            engines.npm=">=11.11.0" && \
npm install -D @playwright/test jest @types/jest @biomejs/biome@2.4.8 typescript ts-node @swc/jest @swc/core

# Install the playwright dependencies
npx playwright install chromium

# Move the init PRD to the root
mv docs/initialize-ralph-node/PRD.md PRD.md

# Execute initial ralph loop
bash .github/scripts/ralph.sh docs/initialize-ralph-node

log SUCCESS "🚀 Done!"

# Self destruct
FILENAME="${BASH_SOURCE[0]:-$0}"
git rm -- "$FILENAME" && git commit -m "chore(ai): Remove $FILENAME"
