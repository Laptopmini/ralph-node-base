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

AGENT_PROMPT="
You are a TEST AUTHOR. You write ONLY test files and validation scripts. You do NOT implement application code.

Your job: for each unchecked task in the PRD below, write a test or validation script that will FAIL until that task is correctly implemented by a future agent.

Read package.json before generating tests to understand which dependencies and test runners are available.

You are running in non-interactive mode, if you have a question, pick the solution which does not break an existing constraint.

- DO NOT create application source files, configuration files, or install/modify dependencies.
- DO NOT implement any task. If a task says \"Install X\" or \"Create config Y\", write a test that asserts X is installed or Y exists — do not perform the action itself.
- Only write test files (.test.ts, .spec.ts) and validation scripts (tests/scripts/*.sh).
- Treat each checkbox item as a single atomic unit of work.
  - Every task MUST include a \`[test: command]\` annotation. If a task is missing its annotation, STOP and report the error — do NOT infer or guess what test to write.
  - Handle the \`[test: command]\` annotation as follows:
    - If the command references a specific test file (e.g., \`[test: npx jest tests/unit/foo.test.ts]\`), create that exact file with the appropriate test content.
    - If the command is a run-only command with NO file path (e.g., \`[test: npm run lint]\`, \`[test: npm run check-types]\`, \`[test: npx tsc --noEmit]\`, \`[test: npx biome check]\`), do NOT create any test file or validation script. The command itself IS the validation — it will pass or fail based on whether the implementation is correct. Skip this task entirely.
  - The generated test file MUST match the exact path in the annotation (e.g., \`[test: npx jest tests/unit/create-basepath-helpers.test.ts]\` → create \`tests/unit/create-basepath-helpers.test.ts\`).
  - The test runner specified in the annotation determines the test framework and file type:
    - \`npx jest tests/unit/foo.test.ts\` → Jest unit test
    - \`bash tests/scripts/foo.sh\` → shell validation script
- The test file's own extension is chosen by the runner and the subject's language:
    - TypeScript subject (.ts, .tsx) → .test.ts / .spec.ts
    - JavaScript subject (.js, .jsx, .mjs, .cjs) → .test.js / .spec.js
- Use imports without file extensions (e.g., import { foo } from './bar' not './bar.js') when possible. Do not use extensions if the import can be resolved without them.
- Use ONLY data-testid attributes as element selectors. Do not assume class names, routing paths, or component structure beyond what the PRD states.
- Assert on: visibility, text content, ARIA roles, and keyboard focus where relevant to the task.
- Tests should fail against a blank implementation — avoid trivially passing assertions (e.g. no expect(true).toBe(true)).
- Sanity tests must contain the minimum assertion described — do not expand them.
- Each test file must cover the following:
    - The primary happy path
    - The most likely failure or edge case
- All generated tests must FAIL if the task is not complete, such as having zero implementation code.
- Use a beforeEach block for any shared setup (navigation, auth state).

When finished, run the following quality gates in order:
- \`npm run lint\` — auto-fixes lint & formatting issues. Manually resolve any issues that cannot be auto-fixed.
- \`npm run check-types\` — verifies TypeScript compilation. Fix any type errors before finishing.

Then finally, run the tests and assert non-zero exit code.

--- ARCHITECTURAL HISTORY (Last 5 Entries) ---

$LEDGER

--- PRD ---

$PRD
"

prompt "$AGENT_PROMPT" --allowedTools "Read,Write,Edit,Glob,Grep,Bash(npm run lint),Bash(npm run check-types),Bash(npm test),Bash(npx jest:*),Bash(npx tsc:*),Bash(npx biome:*)"  --model "${STAFF_DEVELOPER_MODEL:-claude-opus-4-6}"

log INFO "Backpressure prompt completed."
