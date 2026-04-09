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

**Always write the PR body to a temp file and use `--body-file`** to avoid shell escaping issues with backticks, quotes, and newlines in the generated description:

```bash
PR_BODY_FILE=$(mktemp /tmp/pr-body-XXXXXX.md)
cat > "$PR_BODY_FILE" << 'PRBODYEOF'
<pr-description>
PRBODYEOF
gh pr create \
  --repo <repository> \
  --title "<commit-prefix>: <title>" \
  --body-file "$PR_BODY_FILE" \
  --base <base-branch> \
  --head <head-branch>
rm -f "$PR_BODY_FILE"
```

Where:
- `<repository>` is the first argument (e.g., `Laptopmini/ralph-maestro-demo`)
- `<commit-prefix>` is `feat(<ticket-number>)` when a ticket number was extracted, otherwise `feat(ai)`
- `<title>` is the generated PR title (e.g., `Timer Logic Module`)
- `<pr-description>` is the full generated PR description from Step 2
- `<base-branch>` is the third argument (e.g., `main`)
- `<head-branch>` is the second argument (e.g., `prd-1`)

Do **not** use `--body "..."` inline — it breaks when the diff or description contains backticks or quotes.

If `gh pr create` fails, exit with a non-zero exit code.

**Capture the PR number:** Extract the `<pr-number>` from the URL returned by `gh pr create`, or query it with:

```bash
gh pr view <head-branch> --repo <repository> --json number --jq .number
```

### Step 4 — Record the PR in `.maestro.pull-requests.tsv`

Append a single tab-separated line to `.maestro.pull-requests.tsv` at the repository root (create the file if it does not exist):

```bash
printf '%s\t%s\n' "<base-branch>" "<pr-number>" >> .maestro.pull-requests.tsv
```

Where `<base-branch>` is the third argument passed in Step 0 (the same value used for `--base` in Step 3), and `<pr-number>` is the PR number captured in Step 3.

This file is the canonical handoff to `maestro.sh`. Do not commit it (it is gitignored). Do not write any other content to it. Do not emit the record to stdout.

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
5. Write the PR description to a temp file and run `gh pr create --repo Laptopmini/ralph-maestro-demo --title "feat(1): Timer Logic Module" --body-file /tmp/pr-body-XXXXXX.md --base main --head prd-1`
6. Extract PR number (e.g., `12`) from the created PR
7. Append `main\t12` to `.maestro.pull-requests.tsv`

---

## Error Handling

Exit with a non-zero exit code if any of the following occur:

- Missing or insufficient arguments
- `git diff` fails or produces empty output
- `gh pr create` fails
