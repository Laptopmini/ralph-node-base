---
name: blueprint
description: >
  Generates a structured implementation plan from a feature request paragraph. The skill explores the repo, detects the tech stack, and produces: (1) a file/code structure outline, (2) tech stack notes and recommendations, and (3) a sequenced list of non-conflicting implementation tickets, each broken into their own sequential tasks.
  Activated ONLY by the slash command "/blueprint" followed by a feature request paragraph.
  Do NOT use this skill for any other phrasing, even if the user asks about feature planning,
  implementation, or tickets. This skill is exclusively command-driven: it must only trigger
  when the user message starts with "/blueprint" followed by the feature request text.
disable-model-invocation: true
---

# Blueprint Feature Planner Skill

Turns a feature request paragraph into a full implementation plan by exploring the repo, understanding the existing tech stack, and producing a structured, ticket-ready breakdown.

---

## Output

The plan always contains three sections:

1. **Tech Stack & Architecture Notes** — what the existing codebase uses and any recommendations
2. **File/Code Structure** — new files to create, existing files to modify, and directory layout changes
3. **Implementation Tickets** — sequenced, non-conflicting tickets ready for downstream PRD generation

---

## Invocation

This skill is triggered exclusively by the slash command:

```
/blueprint <feature request paragraph>
```

If the user types `/blueprint` with no argument, respond:
> "Please provide a feature request after `/blueprint`. Example: `/blueprint Users should be able to save articles to a reading list.`"

Do not run the planning workflow in that case.

---

## Workflow

### Step 0 — Parse the command

Extract the feature request from everything after `/blueprint ` in the user's message. That extracted text is the input for Step 1. Treat it as plain prose regardless of length or formatting.

### Step 1 — Understand the feature request

Read the extracted feature request carefully. Extract:
- The core user-facing behavior being added
- Any technical constraints or preferences the user mentioned
- What "done" looks like

### Step 2 — Explore the repo agentically

Use file tools to explore the project. Do **not** skip this — the plan must be grounded in the actual codebase.

**Mandatory files to check (if they exist):**
```
package.json              → deps, scripts, framework
tsconfig.json / jsconfig.json → TS/JS configuration
next.config.*             → Next.js detection
vite.config.*             → Vite detection
biome.json                → linter/formatter config
tailwind.config.*         → styling system
```

**Also explore:**
- Root directory listing — understand top-level structure
- `src/` or `app/` or `lib/` — main source layout
- Any existing feature folders similar to what's being built
- README.md — architecture patterns and conventions
- Look for a test directory to understand testing conventions and identify existing test files that may conflict with the planned changes
- Look for `playwright.config.*` and `jest.config.*` — test framework setup
- Look for an existing router/navigation file if this feature involves new pages/routes

**Goal**: By the end of Step 2, you should know:
- Framework (e.g. Next.js 14 App Router, React + Vite, vercel/serve)
- Styling system (Tailwind, CSS Modules, styled-components, etc.)
- Testing framework (Jest for unit tests, Playwright for E2E, or others)
- Key conventions (file naming, folder structure, import paths)
- Which existing test files would be invalidated by the planned changes (e.g. an E2E test for a page being removed)

### Step 3 — Identify gaps and assumptions

Before writing the plan, flag:
- Anything the feature request didn't specify that will affect implementation (e.g. auth requirements, pagination, error states)
- Any conflicts with the existing architecture
- Third-party libraries that would be a natural fit vs. those already in the project

State these as **Assumptions** at the top of the plan. Keep it brief — just enough for a developer to validate.

### Step 4 — Identify workstreams and dependencies (tickets)

Before writing the plan, think carefully about how areas of work relate to each other. Some work is truly independent (can be done in parallel), while other work builds on a foundation that must exist first.

**Identify natural splits:**
- **Shared infrastructure** — layouts, shared components, utility modules, configuration that multiple features consume
- **Backend/API work** — schema, migrations, route handlers, business logic
- **Frontend/UI work** — components, pages, stores
- **Infrastructure/config** — environment variables, feature flags, third-party service setup
- **CI/CD & deployment** — GitHub Actions workflows, build pipelines, hosting configuration (e.g. GitHub Pages, Vercel). Deployment pipelines are a distinct workstream — do not bury them inside a UI or backend ticket

A workstream becomes a **ticket**. If the feature is simple enough that all work is interdependent, one ticket is correct — do not force a split.

**Dependency installation rule:** If the feature introduces new frameworks or libraries, the *first task* of the *root ticket* (a ticket with no `depends_on`) must install all required dependencies via an explicit `npm install` command before any other task references those packages. A child ticket must never install dependencies that its parent already installed — declare `depends_on` instead.

**Dependency rules:**
- A ticket may declare `depends_on: [Ticket N]` to indicate it requires another ticket's outputs (files, exports, routes) to exist first
- A child ticket may **import from** files created by its parent ticket, but must never **modify** them
- **Scheduling:** A ticket is workable once all tickets in its `depends_on` list are complete. Any two tickets whose dependencies are both satisfied can run in parallel (this includes siblings under the same parent)
- Prefer shallow trees (depth ≤ 2). If you find yourself nesting 3+ levels deep, re-evaluate the split — the granularity is likely too fine. However, depth 3 is acceptable when the layers represent genuinely distinct concerns that own different files (e.g. infra/config → UI shell/layout → feature sections → deployment). If you go to depth 3, justify it briefly in the Assumptions section
- Do not duplicate logic to avoid a dependency. If a ticket would reimplement something another ticket already creates, add a `depends_on` instead

**Design foundation rule:** For UI-heavy features, create a foundation ticket that establishes the shared visual layer before any section-specific UI tickets: theme/design-token configuration (e.g. Tailwind theme, CSS variables), global styles, font loading, the app shell (root layout, navigation skeleton), and any shared utility components. All UI tickets should declare `depends_on` this foundation ticket so they build on a consistent visual base rather than each inventing their own styles.

**Key rule:** Two tickets must never touch the same file. If they would, merge them into one ticket.

**Constraint scope:** A ticket's `Constraints` block must state guardrails that apply equally to *every* task in that ticket. Constraints are read by the implementation agent on every cycle, including while the first task runs, so any forward-looking reference becomes a license for the agent to start work it should not yet be doing. In particular, do not reference:

- other tickets by number (e.g. "Ticket 1 files are read-only")
- files that a later task in this same ticket will create — they don't exist yet when early tasks run
- a specific task's ordering, dependencies, or internals within the ticket

Anything task-specific, time-scoped, or file-specific belongs in that task's description, not in Constraints. If you cannot phrase a rule so it applies equally from task 1 onward, it is not a ticket-level constraint. The same forward-reference rule applies to task descriptions themselves: a task must not name a file that a later task in the same ticket (or a yet-unimplemented ticket) will create, because the agent will create any missing file it sees referenced.

**Task ordering by file dependency:** Every file named in a task's description must be produced by something that runs *earlier*, so the agent can trust that the file already exists on disk when the task begins. "Earlier" means one of:

1. The file already exists in the repo at plan time.
2. A prior task in the *same* ticket creates it.
3. A task in a ticket listed in this ticket's `depends_on` creates it (remember: a child ticket may import from parent-owned files but must never modify them).

If none of those is true, the task references a file that will not exist when the agent runs it — reorder the tasks, add a `depends_on`, or merge the two tasks into one.

- *Intra-ticket example:* if one task creates an HTML file that loads `/app.js`, a prior task in the same ticket must create `app.js`. Never let the HTML task's description mention `app.js` before `app.js` exists.
- *Cross-ticket example:* if Ticket 2's first task imports from `src/lib/foo.ts`, then Ticket 2 must declare `depends_on: [Ticket 1]` and Ticket 1 must own the creation of `src/lib/foo.ts`.

Why this matters: the implementation agent only sees tasks up to and including the current one in the current ticket's PRD. It cannot know a later task — or another ticket — will create the file, so any file named in the current task's description will be created now if it does not yet exist on disk. If two tasks reference each other's files and cannot be ordered, merge them into a single task.

### Step 5 — Protected files check

Before writing the plan, verify that no ticket proposes modifying protected files:
- `.github/scripts/*` or `.github/prompts/*` — ralph loop infrastructure
- `.claude/settings.json`, `.aignore`, `biome.json` — project configuration

If the feature requires changes to any of these, flag it as an assumption and explain why.

### Step 5b — Identify conflicting test files

Review existing test files (unit tests, E2E specs, etc.) and determine which ones would be **invalidated** by the planned implementation changes. For example:
- An E2E test for a page that is being removed or replaced
- A unit test for a module that is being deleted or fundamentally restructured
- A test file whose assertions would no longer make sense after the implementation

Each conflicting test file must be:
1. Listed in the appropriate ticket's "Files owned" section with a `(delete)` tag
2. Represented as a dedicated task describing **which file to delete** and **how to validate the removal** (e.g. "Delete `tests/unit/old-page.test.ts` — verify by confirming the file no longer exists on disk and that no other source files import or reference it")

This ensures the implementation does not leave behind broken or misleading tests.

### Step 6 — Write the plan

Write the plan to `.maestro.blueprint.md`, following the output format below exactly. The file content must match the output format — nothing before, nothing after. Do NOT print the plan to the chat.

### Step 7 — Review embedded commands with a subagent

Before printing the execution levels, spawn a subagent to audit commands embedded in task prose against the detected tech stack. This catches issues like invalid CLI flags, or commands that are syntactically valid but inappropriate for the stack (e.g., `tsc` as a production build when the framework ships its own `build` command). The subagent's fresh context makes it a better reviewer than a self-check by the author.

Call the `Agent` tool with:
- `subagent_type: "general-purpose"`
- `description`: `"Review blueprint commands"`
- `prompt`: a self-contained brief including:
  1. **What you're reviewing** — explain this is a freshly written implementation blueprint at `.maestro.blueprint.md`. Paste the full file contents inline (read it back from disk so the subagent does not need to).
  2. **Detected tech stack** — a short bullet list of what Step 2 found: framework, build tool/script, test framework, TypeScript config presence, any notable conventions. This is the context the reviewer needs to judge "inappropriate for the stack."
  3. **What to hunt for** — quote this verbatim: *"Find commands embedded in task descriptions (prose, backtick spans, or proposed `package.json` `scripts` entries) that are (a) syntactically invalid for the named tool, (b) using flags that don't fit that tool's purpose, or (c) inappropriate given the detected stack — especially `tsc` used as a production builder when the framework has its own build command, or test-runner flags that don't exist. Check any task that mutates `package.json` `scripts` with extra scrutiny."*
  4. **Return format** — quote this verbatim: *"If nothing is wrong, return exactly `NO_ISSUES` and nothing else. Otherwise, return a punch list, one entry per issue, each formatted as:*

     ```
     - Section: <ticket number and task number, or 'Tech Stack' / 'File Structure'>
       Bad: `<quoted command>`
       Why: <one sentence>
       Fix: <suggested replacement>
     ```

     *Keep the full response under 300 words. Do not include any other commentary."*

When the subagent returns:
- If the response is exactly `NO_ISSUES`, proceed to Step 8.
- Otherwise, for each punch-list entry, apply the suggested fix to `.maestro.blueprint.md` via the `Edit` tool. Do not print anything to chat in this step — the final chat output in Step 8 must remain the execution levels alone.

### Step 8 — Output parallel execution levels

After the review step, compute the dependency tree levels for the tickets and print them to the chat. A "level" is a set of tickets whose dependencies are all satisfied by tickets in earlier levels (level 0 = tickets with no dependencies).

Algorithm:
1. Level 0: all tickets with no `depends_on`
2. Level N: all tickets whose `depends_on` are entirely contained in levels 0..N-1
3. Repeat until all tickets are placed

Print one line per level, with comma-separated ticket numbers (no spaces, ascending order). For example, given Ticket 1 (no deps), Ticket 2 (no deps), Ticket 3 (depends on 1), Ticket 4 (depends on 2), print exactly:

```
1,2
3,4
```

**CRITICAL:** The execution levels are the ONLY thing the skill prints to the chat. No preamble, no explanation, no acknowledgement, no trailing text, no code fences — just the raw level lines. The entire chat output from start to finish must be exclusively these lines so a bash script can consume it directly.

---

## Output Format

```markdown
## Implementation Plan: [Feature Name]

### Assumptions
- [Short assumption 1]
- [Short assumption 2]

---

### 1. Tech Stack & Architecture Notes

**Detected stack:** [framework, key libs]

**Relevant existing patterns:**
- [e.g. "API routes follow the pattern in `src/api/[resource]/route.ts`"]
- [e.g. "State is managed with Zustand stores in `src/stores/`"]

**Recommendations:**
- [Any lib to add, pattern to follow, or architectural decision to make]

---

### 2. File & Code Structure

**New files:**
- `app/api/reading-list/route.ts`
- `src/components/ReadingList/ReadingList.tsx`

**Modified files:**
- `prisma/schema.prisma`
- `src/components/Nav.tsx`

**Conflicting test files to remove:**
- `tests/unit/old-page.test.ts` — tests a page being replaced by this feature

---

### 3. Tickets

Tickets are workstreams. No two tickets touch the same file. A ticket is workable once
all tickets in its `depends_on` list are complete. Siblings under the same parent run in parallel.

---

#### Ticket 1: [Short name, e.g. "API & Data Layer"]

> [One sentence describing the scope of this workstream]

**Constraints:**
- [Architectural guardrails — e.g. "Must use existing auth middleware at `src/middleware/auth.ts`"]
- [Patterns to follow — e.g. "Follow API route pattern in `src/api/`"]

**Files owned:**
- `prisma/schema.prisma` (modify)
- `app/api/reading-list/route.ts` (create)
- `app/api/reading-list/[id]/route.ts` (create)

**Tasks:**
1. [code] Add `ReadingListItem` model to `schema.prisma` with fields: `id` (cuid), `userId` (relation to User), `articleUrl` (string), `title` (string), `isRead` (boolean, default false), `createdAt` (datetime). Run migration
2. [code] Implement `POST /api/reading-list` — accepts `{ articleUrl, title }`, creates a `ReadingListItem` for the authenticated user, returns 201 with the created item. Returns 401 if unauthenticated
3. [code] Implement `DELETE /api/reading-list/[id]` — deletes the item if it belongs to the authenticated user, returns 204. Returns 404 if not found, 403 if owned by another user
4. [code] Implement `PATCH /api/reading-list/[id]` — toggles `isRead` between true/false for the authenticated user's item, returns 200 with the updated item

---

#### Ticket 2: [Short name, e.g. "UI Components & State"]
**depends_on:** [Ticket 1]

> [One sentence describing the scope of this workstream]

**Constraints:**
- Use `data-testid` attributes on all interactive and display elements (buttons, inputs, lists, status indicators)
- Do not modify files owned by another ticket — import from them as read-only

**Files owned:**
- `src/stores/readingListStore.ts` (create)
- `src/components/ReadingList/ReadingList.tsx` (create)
- `src/components/ReadingList/index.ts` (create)
- `app/reading-list/page.tsx` (create)
- `src/components/Nav.tsx` (modify)
- `tests/unit/old-page.test.ts` (delete)

**Tasks:**
1. [infra] Delete `tests/unit/old-page.test.ts` — this E2E test targets a page being replaced by the reading list feature. Verify the file no longer exists on disk and that no other source files import or reference it
2. [code] Create `readingListStore.ts` with Zustand — expose `items` (array of `ReadingListItem`), `fetchItems()`, `addItem(articleUrl, title)`, `removeItem(id)`, `toggleRead(id)`. Use real `fetch()` calls to `/api/reading-list` endpoints from Ticket 1
3. [code] Build `ReadingList` component — renders a list of items (`data-testid="reading-list"`), each item shows title, URL, read/unread status (`data-testid="item-{id}"`), a delete button (`data-testid="delete-{id}"`), and a toggle-read button (`data-testid="toggle-read-{id}"`). Include a filter bar (`data-testid="filter-bar"`) with "All", "Unread", "Read" options
4. [code] Add `/reading-list` page (`data-testid="reading-list-page"`) — mounts `ReadingList` component, shows loading state (`data-testid="loading-indicator"`) while fetching, and empty state (`data-testid="empty-state"`) when no items exist
5. [code] Add nav link (`data-testid="nav-reading-list"`) in `Nav.tsx` pointing to `/reading-list`

---

> **Note:** A ticket is workable once all tickets in its `depends_on` list are complete — siblings under the same parent run in parallel. Tasks within each ticket are sequential. No ticket includes test creation — testing is handled separately.
```

---

## Quality Checklist

Before outputting the plan, verify:
- [ ] No two tickets own the same file — if they do, merge those tickets
- [ ] Every file in the File & Code Structure section is owned by exactly one ticket
- [ ] Tasks within each ticket are truly atomic and sequential (each one builds on the last)
- [ ] If a ticket's tasks require output from another ticket, `depends_on` is declared explicitly
- [ ] No ticket implicitly requires another ticket's output without declaring `depends_on`
- [ ] Child tickets never modify files owned by their parent — they may only import/read from them
- [ ] Dependency depth is ≤ 2 levels by default. If depth 3 is used, each layer owns distinct files and the justification is stated in Assumptions
- [ ] No logic is duplicated to avoid a dependency — use `depends_on` instead
- [ ] The tech stack section reflects what was actually found in the repo, not guessed
- [ ] Assumptions cover any ambiguity that would block a developer from starting
- [ ] It is valid to produce only one ticket if the work cannot be cleanly parallelized
- [ ] No ticket proposes modifying protected files (`.github/scripts/*`, `.github/prompts/*`, `.claude/settings.json`, `.aignore`, `biome.json`)
- [ ] Every task has a nature tag: `[code]` or `[infra]`
- [ ] Every file in "Files owned" has an operation tag: `(create)`, `(modify)`, or `(delete)`
- [ ] Every ticket has a Constraints section (can be empty if none apply)
- [ ] Every Constraints entry applies to every task in the ticket — no entry references another ticket, references a file created only by a later task in this ticket, or scopes itself to a specific task's ordering
- [ ] Every file named in a task's description is produced by something that runs earlier: the file already exists in the repo, OR an earlier task in the same ticket creates it, OR a ticket in this ticket's `depends_on` creates it. No task references a file that a later task (in any ticket) will create
- [ ] **No task creates, writes, or modifies test files** — test creation is handled by a separate effort. Deleting or modifying conflicting test files is allowed and expected
- [ ] Every task description is specific enough that a developer could derive unit, E2E, or utility tests from it (includes inputs, outputs, edge cases, expected behaviors, status codes, `data-testid` values, etc.)
- [ ] All UI tasks enforce `data-testid` attributes on interactive and display elements
- [ ] Existing test files that conflict with the planned changes are listed for deletion in the appropriate ticket
- [ ] Commands embedded in task prose (including proposed `package.json` `scripts` entries) have been audited by the Step 7 review subagent against the detected stack
- [ ] If new dependencies are introduced, the first task of the root ticket installs them — no later task or child ticket runs `npm install` for the same packages
- [ ] CI/CD and deployment pipelines (GitHub Actions, hosting config) are in their own ticket, not buried inside a UI or backend ticket
- [ ] For UI-heavy features, a design foundation ticket establishes the shared visual layer (theme, global styles, fonts, app shell) before section-specific UI tickets

---

## Notes on Ticket & Task Granularity

**Tickets** represent workstreams — assign one per developer or team. A ticket owns a set of files exclusively. A ticket is workable once all tickets in its `depends_on` list are complete — siblings under the same parent can run in parallel. A child ticket may import from (but never modify) parent-owned files. If all the work in a feature naturally touches the same files, one ticket is the right answer.

**Tasks** within a ticket are atomic units of work done one at a time in sequence. Each task should be a single, focused unit of work that a headless AI agent can implement in one cycle. If a task requires touching more than 2-3 files or involves multiple unrelated concerns, split it. If two adjacent tasks always touch only the same file, consider merging them.

**Task nature tags** indicate the type of work:
- `[code]` — application code: business logic, API routes, data models, state management, components, pages, layouts, styling
- `[infra]` — configuration, environment setup, dependency installation, CI/CD, standalone resource files not yet consumed by application code

Avoid vague tasks like "implement X" — each task should describe exactly what to build or change. These tasks will be consumed by downstream tooling, so they should be as specific as possible.

**Testing policy:**
- **Do not create test files or test-writing tasks.** Testing is performed by a separate developer as part of a dedicated effort. No ticket should include tasks to create, write, or modify test files (`.test.ts`, `.spec.ts`, etc.). Deleting or modifying conflicting test files is distinct from this rule and is expected.
- **Do remove conflicting test files.** If the implementation removes or replaces functionality that has existing test coverage, include the deletion of those test files as a task in the relevant ticket.
- **Do write testable code.** Tasks must still follow test-friendly practices: use `data-testid` attributes on all interactive and display elements, keep pure logic in separate importable modules, and describe behavior with enough specificity (inputs, outputs, edge cases, status codes, error states) that a developer could derive comprehensive tests from the task description alone.
