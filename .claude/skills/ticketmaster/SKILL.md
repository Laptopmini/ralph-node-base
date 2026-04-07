---
name: ticketmaster
description: >
  Takes a path to a markdown implementation plan and, for each ticket, creates branches,
  generates a PRD.md, commits, pushes, and opens a pull request.
  Activated ONLY by the slash command "/ticketmaster" followed by a file path argument.
  Do NOT use this skill for any other phrasing. This skill is exclusively command-driven.
disable-model-invocation: true
---

# Ticketmaster Skill

**Important: Use extended thinking for this skill.** Before executing any step, think deeply about the implementation plan structure, the ticket contents, and how to generate clear PRD task lines. Extended thinking is required to produce high-quality, unambiguous PRDs for junior developers.

Converts an implementation plan into per-ticket branches, PRD files, and pull requests.

---

## Invocation

This skill is triggered exclusively by the slash command:

```
/ticketmaster <path-to-implementation-plan.md> <ticket-numbers>
```

`<ticket-numbers>` is a comma-separated list of ticket ordinals to process (e.g. `1`, `2,3`, `1,3,4`).

If the user types `/ticketmaster` with no path argument, respond:

> "Please provide a path to an implementation plan. Example: `/ticketmaster .claude/skills/blueprint/examples/sample.md 1,2`"

If the user provides a path but no ticket numbers, respond:

> "Please provide ticket numbers to process. Example: `/ticketmaster .claude/skills/blueprint/examples/sample.md 1,2`"

Do not run the workflow in either case.

---

## Workflow

### Step 0 — Parse the command

The user's message has the form `/ticketmaster <file-path> <ticket-numbers>`. Extract both arguments:

- `<ticket-numbers>`: the **last** whitespace-delimited token. Parse it as a comma-separated list of integers (e.g. `2,3` → `[2, 3]`).
- `<file-path>`: everything between `/ticketmaster ` and the last whitespace-delimited token.

If either argument is missing, respond with the corresponding error message from the **Invocation** section and stop. Read the file at `<file-path>`. If the file does not exist or is empty, tell the user and stop.

### Step 0.5 — Create or checkout the `maestro` branch

Before processing any tickets, ensure the shared `maestro` accumulation branch exists and is up to date:

```bash
git checkout main
git pull origin main
git checkout maestro 2>/dev/null || git checkout -b maestro
git pull origin maestro 2>/dev/null || true
git push -u origin maestro 2>/dev/null || true
```

If `maestro` already exists (locally or on the remote), check it out, pull to accept any remote changes, and continue. Do not error.

### Step 1 — Parse the implementation plan

Read the markdown file at the given path. Extract:

- **Plan-level context**: the `Assumptions` section, the `Tech Stack & Architecture Notes` section, and any other top-level context (everything outside tickets).
- **Tickets**: each `#### Ticket N: ...` block, including its description, constraints, files owned, and tasks.

Number each ticket by its ordinal position in the plan (1, 2, 3, ...). This ordinal is the `<ticket-number>` used in branch names and PR titles.

### Step 2 — Process tickets sequentially

For each ticket whose number appears in the parsed `<ticket-numbers>` list, in ascending order, perform the following steps. Tickets not in the list are silently skipped. Do **not** process tickets in parallel — each ticket involves git operations that must complete before the next begins.

#### 2a — Create the base branch

Create a branch called `prd-<ticket-number>` from `maestro`.

```bash
git checkout maestro
git pull origin maestro
git checkout -b prd-<ticket-number>
git push -u origin prd-<ticket-number>
```

If the branch `prd-<ticket-number>` already exists locally or on the remote, skip creation and check it out instead.

#### 2b — Create the requirements branch

From `prd-<ticket-number>`, create a branch called `prd-<ticket-number>-requirements`.

```bash
git checkout prd-<ticket-number>
git checkout -b prd-<ticket-number>-requirements
```

If the branch `prd-<ticket-number>-requirements` already exists, skip creation and check it out instead.

#### 2c — Generate PRD.md

Create a file called `PRD.md` at the root of the repository on this branch. Follow the PRD format described below in the **PRD Format** section.

#### 2d — Commit and push

```bash
git add PRD.md
git commit -m "chore(ai): add PRD for ticket <ticket-number>"
git push -u origin prd-<ticket-number>-requirements
```

#### 2e — Open a pull request

First, determine the GitHub `owner/repo` slug for use with `gh`:

```bash
REPO_SLUG=$(bash .github/scripts/repo-slug.sh)
```

Then use `gh pr create` to open a PR, passing `--repo "$REPO_SLUG"`:

- **Base branch**: `prd-<ticket-number>`
- **Head branch**: `prd-<ticket-number>-requirements`
- **Title**: `prd(<ticket-number>): <ticket name>`
  - The ticket name comes from the `#### Ticket N: <ticket name>` heading in the plan.
- **Body**: the ticket's description (the blockquote line) followed by its full task list from the plan.

If a PR already exists for this head/base combination, skip PR creation but retrieve its PR number.

**Retain the PR number** returned by `gh pr create` (or from the existing PR) for use in the summary output. You can extract the number from the URL returned by `gh pr create`, or by querying with `gh pr view prd-<ticket-number>-requirements --json number --jq .number`.

### Step 3 — Output summary

After all tickets have been processed, output ONLY a block in the exact format below with no other text before or after it:

```
<head-branch-name><TAB><pr-number>
```

One record per ticket, one record per line, in ascending ticket order. `<head-branch-name>` is the name `prd-<ticket-number>-requirements` of the head branch created for that ticket during Step 2a (e.g., `prd-1-requirements`), and `<pr-number>` is the pull request number opened (or already existing) for that ticket's requirements branch.

Fields are separated by a single ASCII tab character (`\t`, 0x09). Do not emit parentheses, `#`, or any surrounding prose.

**Example output** (for a plan with three tickets, where the gaps are real tab characters):

```
prd-1-requirements	12
prd-2-requirements	13
prd-3-requirements	14
```

Do not output any other text BEFORE or AFTER this block. This output is consumed by a bash script and must be machine-readable.

---

## PRD Format

The generated `PRD.md` must follow this structure. Refer to `.claude/skills/ticketmaster/examples/sample.md` for a concrete example.

```markdown
# PRD: <Ticket Name>

## Objective

<A clear, concise paragraph describing what this ticket accomplishes, derived from the ticket's description line.>

## Context

<Relevant context pulled from the implementation plan's top-level sections: assumptions, tech stack notes, relevant existing patterns, and recommendations. Include only what is relevant to this specific ticket. This section should give a junior developer enough background to understand why this work matters and how it fits into the broader project.>

## Constraints

<Bullet list of constraints from the ticket's Constraints section. If the ticket has no constraints, state "No additional constraints beyond the project defaults.">

## Tasks

- [ ] <Task line 1> `[test: <test-command>]`
- [ ] <Task line 2> `[test: <test-command>]`
...
```

### Task line rules

Each task must be a **single line** in the format:

```
- [ ] <Short title>. <Description of what to do, specific enough for a junior developer.> `[test: <test-command>]`
```

These PRDs will be handled by a junior developer, so write them clearly and without ambiguity. Spell out exactly what to create, modify, or configure. Do not assume the reader has context beyond what is in the PRD itself.

### Determining the test command

Each task in the implementation plan has a nature tag: `[logic]`, `[ui]`, or `[infra]`.

**Derive the test filename** from the task's short title:
1. Take the short title (the text before the first period in the task line).
2. Convert to kebab-case.
3. Remove articles (a, an, the) and punctuation.

Example: "Add a banner at the top" becomes `add-banner-top`.

**Map the nature tag to a test command:**

| Nature tag | Test command template |
|------------|----------------------|
| `[logic]`  | `npx jest tests/unit/<filename>.test.ts` |
| `[ui]`     | `npx playwright test tests/e2e/<filename>.spec.ts` |
| `[infra]`  | `bash scripts/<filename>.sh` — unless the task is a config validation, in which case use the relevant CLI command directly (e.g., `npx tsc --noEmit`, `npx biome check`, etc.) |

---

## Example

Given an implementation plan with:

```markdown
#### Ticket 1: Timer Logic (Pure Functions)

> Implement and unit-test the pure countdown logic.

**Constraints:**
- Must be a TypeScript module importable by Jest
- No DOM or browser APIs

**Tasks:**
1. [logic] Create `src/timer-logic.ts` with pure functions: `formatTime` and `tick`
2. [logic] Create unit tests for timer logic
```

The skill would:
1. Create branch `prd-1` from `main`
2. Create branch `prd-1-requirements` from `prd-1`
3. Generate `PRD.md` with:
   - **Objective**: based on "Implement and unit-test the pure countdown logic"
   - **Context**: pulled from the plan's assumptions and tech stack notes
   - **Constraints**: "Must be a TypeScript module importable by Jest", "No DOM or browser APIs"
   - **Tasks**:
     - `- [ ] Create timer logic module. Create src/timer-logic.ts with pure functions: formatTime(totalSeconds: number): string (returns "MM:SS") and tick(remainingSeconds: number): number (decrements by 1, floors at 0), and a constant POMODORO_DURATION_SECONDS = 1500. [test: npx jest tests/unit/create-timer-logic-module.test.ts]`
     - `- [ ] Create timer logic unit tests. Create tests/unit/timer-logic.test.ts — test formatTime (25:00, 00:00, 09:59 edge cases), test tick (decrements, does not go below 0), test duration constant equals 1500. [test: npx jest tests/unit/create-timer-logic-unit-tests.test.ts]`
4. Commit and push
5. Open PR: `prd(1): Timer Logic (Pure Functions)` against `prd-1`

---

## Quality Checklist

Before generating each PRD, verify:

- [ ] Every task is on a single line
- [ ] Every task has a `[test: ...]` annotation
- [ ] Test filenames are derived from the task's short title in kebab-case
- [ ] The correct test runner is used based on the nature tag
- [ ] Context section includes only information relevant to this specific ticket
- [ ] Constraints are copied faithfully from the implementation plan
- [ ] The PRD is written clearly enough for a junior developer to follow without external context
