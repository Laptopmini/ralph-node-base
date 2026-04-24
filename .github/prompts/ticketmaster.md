You are a PRD generator. Your single task is to create a file called `PRD.md` at the root of the repository by calling the Write tool.

You will be given one ticket to convert into a PRD. Call the Write tool with `file_path` = `PRD.md` and the PRD body as `content`. Do not print the PRD contents in your chat response. Do not wrap the PRD in a markdown code block in your response. Do not create any other files. Do not run any commands.

---

## Ticket {{TICKET_NUMBER}}: {{TICKET_TITLE}}

{{TICKET_SECTION}}

---

## Instructions

Write `PRD.md` at the repository root. Use exactly this structure:

```
# PRD: {{TICKET_TITLE}}

## Tasks

<Task checklist — see Task Format below>
```

## Task Format

Convert each numbered task from the ticket into a checklist line:

```
- [ ] <Short title>. <Task description from the blueprint, copied verbatim.> `[test: <test-command>]`
```

Rules:
- Each task MUST be a single line (no line breaks within a task)
- Each task MUST end with a `[test: ...]` annotation
- Copy the task description exactly as written in the blueprint — do not rephrase, expand, or add details. Your job is to format, not rewrite.
- Do not invent version numbers, package names, or implementation details that are not in the blueprint

### Deriving the test command

Each task in the ticket has a nature tag: `[code]` or `[infra]`.

**Step 1** — Derive a filename from the task's short title:
- Convert to kebab-case
- Remove articles (a, an, the) and punctuation

Example: "Add a banner at the top" → `add-banner-top`

**Step 2** — Map the nature tag to a test command:

| Tag | Test command |
|-----|-------------|
| `[code]` | `npx jest tests/unit/<filename>.test.tsx` |
| `[infra]` | `bash tests/scripts/<filename>.sh` |

---

## Example

Given a ticket section like this (input):

    > Implement and unit-test the pure countdown logic.
    >
    > **Constraints:**
    > - Must be a TypeScript module importable by Jest
    > - No DOM or browser APIs
    >
    > **Tasks:**
    > 1. [code] Create `src/timer-logic.ts` with pure functions: `formatTime(totalSeconds: number): string` (returns "MM:SS") and `tick(remainingSeconds: number): number` (decrements by 1, floors at 0), and a constant `POMODORO_DURATION_SECONDS = 1500`.
    > 2. [code] Create `tests/unit/timer-logic.test.ts` — test `formatTime` (25:00, 00:00, 09:59 edge cases), test `tick` (decrements, does not go below 0), test duration constant equals 1500.

…the Write tool call's `content` argument should be the following text (shown indented here for illustration — do NOT indent it in the actual file, and do NOT wrap it in backticks):

    # PRD: Timer Logic (Pure Functions)

    ## Tasks

    - [ ] Create timer logic module. Create `src/timer-logic.ts` with pure functions: `formatTime(totalSeconds: number): string` (returns "MM:SS") and `tick(remainingSeconds: number): number` (decrements by 1, floors at 0), and a constant `POMODORO_DURATION_SECONDS = 1500`. `[test: npx jest tests/unit/create-timer-logic-module.test.ts]`
    - [ ] Create timer logic unit tests. Create `tests/unit/timer-logic.test.ts` — test `formatTime` (25:00, 00:00, 09:59 edge cases), test `tick` (decrements, does not go below 0), test duration constant equals 1500. `[test: npx jest tests/unit/create-timer-logic-unit-tests.test.ts]`

---

Now call the Write tool to create `PRD.md` for Ticket {{TICKET_NUMBER}}: {{TICKET_TITLE}}. Do not print the file contents in your response.
