---
name: summarizer
description: >
  Generates a diff-based PR description and opens a pull request for a prd branch.
  Activated ONLY by the slash command "/summarizer" followed by three arguments:
  repository name, head branch, and base branch.
  Do NOT use this skill for any other phrasing. This skill is exclusively command-driven.
disable-model-invocation: true
---

# Summarizer Skill

Analyzes the diff between a PRD branch and a base branch, generates a professional PR description, and opens a pull request.

---

## Invocation

This skill is triggered exclusively by the slash command:

```
/summarizer <repository> <head-branch> <base-branch>
```

**Arguments (positional, in order):**

1. `<repository>` — GitHub `owner/repo` slug (e.g., `Laptopmini/ralph-maestro-demo`)
2. `<head-branch>` — The branch with changes (e.g., `prd-1`)
3. `<base-branch>` — The branch to diff against (e.g., `main`)

If the user types `/summarizer` with missing arguments, respond:

> "Please provide all three arguments. Example: `/summarizer Laptopmini/ralph-maestro-demo prd-1 main`"

Do not run the workflow in that case.

---

## Workflow

### Step 0 — Parse and validate the command

Extract the three arguments from the user's message.

**Extract the ticket number:** Match the head branch name against the pattern `prd-([0-9]+)` and capture the digits as `<ticket-number>` (e.g. `prd-3` → `3`, `prd-3-requirements` → `3`). If the head branch does not match this pattern, there is no ticket number — do not exit; the conventional commit prefix in Step 3 will fall back to a default.

### Step 1 — Generate the diff

Run `git diff` between the base branch and the head branch:

```bash
git diff <base-branch>..<head-branch>
```

If the diff command fails or produces no output, exit with a non-zero exit code.

### Step 2 — Analyze the diff and generate the PR description

Given the diff output, perform the following analysis:

1. **Analyze the code changes** — understand what was added, modified, and removed
2. **Identify the key modifications** — group related changes together
3. **Extract scope, purpose, and impact** — determine what the changes accomplish and what areas of the codebase are affected
4. **Generate a professional PR description** with the following sections:

#### PR Description Format

The generated PR Description must follow this structure. Refer to `.claude/skills/summarizer/examples/sample.md` for a concrete example.

```markdown
## Summary

<A concise paragraph describing what this PR accomplishes and why.>

## Changes Made

<Bulleted list of key changes, grouped logically. Each bullet should describe a meaningful change, not just list files.>

## Impacted Files

<Bulleted list of all files that were added, modified, or deleted, with a short note about what changed in each.>
```

Also generate a short, descriptive **Title** for the PR (under 60 characters, no prefix — the prefix is added automatically).

### Step 3 — Open the pull request

Use `gh pr create` to open the pull request:

**Determine the conventional-commit prefix:**
- If `<ticket-number>` was extracted in Step 0, use `feat(<ticket-number>)` (e.g. `feat(1)`).
- Otherwise, use `feat(ai)`.

This value is `<commit-prefix>` below.

```bash
gh pr create \
  --repo <repository> \
  --title "<commit-prefix>: <title>" \
  --body "<pr-description>" \
  --base <base-branch> \
  --head <head-branch>
```

Where:
- `<repository>` is the first argument (e.g., `Laptopmini/ralph-maestro-demo`)
- `<commit-prefix>` is `feat(<ticket-number>)` when a ticket number was extracted, otherwise `feat(ai)`
- `<title>` is the generated PR title (e.g., `Timer Logic Module`)
- `<pr-description>` is the full generated PR description from Step 2
- `<base-branch>` is the third argument (e.g., `main`)
- `<head-branch>` is the second argument (e.g., `prd-1`)

If `gh pr create` fails, exit with a non-zero exit code.

**Capture the PR number:** Extract the `<pr-number>` from the URL returned by `gh pr create`, or query it with:

```bash
gh pr view <head-branch> --repo <repository> --json number --jq .number
```

### Step 4 — Output result

Output ONLY the following single line with no other text before or after it:

```
<head-branch><TAB><pr-number>
```

Where `<head-branch>` is the second argument passed in Step 0 (the same value used for `--head` in Step 3), and `<pr-number>` is the PR number captured in Step 3.

Fields are separated by a single ASCII tab character (`\t`, 0x09). Do not emit parentheses, `#`, or any surrounding prose. Do not emit a trailing newline beyond the single record.

For example, head branch `prd-3-requirements` with PR number 12 (where the gap is a real tab character):

```
prd-3-requirements	12
```

This output is consumed by a bash script and must be machine-readable.

If any step failed, exit with a non-zero exit code.

---

## Example

Given the command:

```
/summarizer Laptopmini/ralph-maestro-demo prd-1 main
```

The skill would:

1. Match `prd-1` against `prd-([0-9]+)` and extract ticket number `1`
2. Run `git diff main..prd-1`
3. Analyze the diff and generate:
   - **Title**: `Timer Logic Module`
   - **Summary**: description of the changes
   - **Changes Made**: bulleted list of key modifications
   - **Impacted Files**: list of affected files
4. Determine the commit prefix: `feat(1)` (since a ticket number was extracted)
5. Run `gh pr create --repo Laptopmini/ralph-maestro-demo --title "feat(1): Timer Logic Module" --body "..." --base main --head prd-1`
6. Extract PR number (e.g., `12`) from the created PR
7. Output `prd-1<TAB>12` (a single line, where `<TAB>` is a literal ASCII tab character)

---

## Error Handling

Exit with a non-zero exit code if any of the following occur:

- Missing or insufficient arguments
- `git diff` fails or produces empty output
- `gh pr create` fails
