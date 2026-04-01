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
- README.md or CLAUDE.md — architecture patterns and conventions
- Look for a test directory to understand testing conventions
- Look for `playwright.config.*` and `jest.config.*` — test framework setup
- Look for an existing router/navigation file if this feature involves new pages/routes

**Goal**: By the end of Step 2, you should know:
- Framework (e.g. Next.js 14 App Router, React + Vite, vercel/serve)
- Styling system (Tailwind, CSS Modules, styled-components, etc.)
- Testing framework (Jest for unit tests, Playwright for E2E, or others)
- Key conventions (file naming, folder structure, import paths)

### Step 3 — Identify gaps and assumptions

Before writing the plan, flag:
- Anything the feature request didn't specify that will affect implementation (e.g. auth requirements, pagination, error states)
- Any conflicts with the existing architecture
- Third-party libraries that would be a natural fit vs. those already in the project

State these as **Assumptions** at the top of the plan. Keep it brief — just enough for a developer to validate.

### Step 4 — Identify parallel workstreams (tickets)

Before writing the plan, think carefully about which areas of work are **truly independent** — meaning a developer working on one would never need to wait for, modify the same files as, or coordinate with a developer on another.

Common natural splits:
- **Backend/API work** — schema, migrations, route handlers, business logic
- **Frontend/UI work** — components, pages, stores — if they can be built against a mocked API
- **Infrastructure/config** — environment variables, feature flags, third-party service setup

A workstream becomes a **ticket**. If the feature is simple enough that all work is interdependent, one ticket is correct — do not force a split.

**Key rule:** Two tickets must never touch the same file. If they would, merge them into one ticket.

### Step 5 — Protected files check

Before writing the plan, verify that no ticket proposes modifying protected files:
- `.github/scripts/*` or `.github/prompts/*` — ralph loop infrastructure
- `.claude/settings.json`, `.aignore`, `biome.json` — project configuration
- Test assertions or mock logic — to prevent forcing passes

If the feature requires changes to any of these, flag it as an assumption and explain why.

### Step 6 — Write the plan

Follow the output format below exactly.

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

---

### 3. Tickets

Each ticket is an independent workstream that can be assigned to a separate developer and worked
on in parallel. No ticket depends on another, and no two tickets touch the same file.

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
1. [logic] Add `ReadingListItem` model to `schema.prisma` and run migration
2. [logic] Implement `POST /api/reading-list` to save an article for the authed user
3. [logic] Implement `DELETE /api/reading-list/[id]`
4. [logic] Implement `PATCH /api/reading-list/[id]` to toggle read/unread

---

#### Ticket 2: [Short name, e.g. "UI Components & State"]

> [One sentence describing the scope of this workstream]

**Constraints:**
- [e.g. "Use `data-testid` attributes for all interactive elements"]

**Files owned:**
- `src/stores/readingListStore.ts` (create)
- `src/components/ReadingList/ReadingList.tsx` (create)
- `src/components/ReadingList/index.ts` (create)
- `app/reading-list/page.tsx` (create)
- `src/components/Nav.tsx` (modify)

**Tasks:**
1. [logic] Create `readingListStore.ts` with Zustand; mock API calls initially
2. [ui] Build `ReadingList` component with read/unread filter UI
3. [ui] Add `/reading-list` page and wire `ReadingList` component in
4. [ui] Add nav link in `Nav.tsx`
5. [logic] Replace mocked API calls in store with real endpoints

---

> **Note:** Tickets can be worked in parallel. Tasks within each ticket are sequential.
```

---

## Quality Checklist

Before outputting the plan, verify:
- [ ] No two tickets own the same file — if they do, merge those tickets
- [ ] Every file in the File & Code Structure section is owned by exactly one ticket
- [ ] Tasks within each ticket are truly atomic and sequential (each one builds on the last)
- [ ] No ticket's tasks implicitly require output from another ticket to proceed
- [ ] The tech stack section reflects what was actually found in the repo, not guessed
- [ ] Assumptions cover any ambiguity that would block a developer from starting
- [ ] It is valid to produce only one ticket if the work cannot be cleanly parallelized
- [ ] No ticket proposes modifying protected files (`.github/scripts/*`, `.github/prompts/*`, `.claude/settings.json`, `.aignore`, `biome.json`)
- [ ] Every task has a nature tag: `[logic]`, `[ui]`, or `[infra]`
- [ ] Every file in "Files owned" has an operation tag: `(create)` or `(modify)`
- [ ] Every ticket has a Constraints section (can be empty if none apply)

---

## Notes on Ticket & Task Granularity

**Tickets** represent parallel workstreams — assign one per developer or team. A ticket owns a set of files exclusively. If all the work in a feature naturally touches the same files, one ticket is the right answer.

**Tasks** within a ticket are atomic units of work done one at a time in sequence. Each task should be a single, focused unit of work that a headless AI agent can implement in one cycle. If a task requires touching more than 2-3 files or involves multiple unrelated concerns, split it. If two adjacent tasks always touch only the same file, consider merging them.

**Task nature tags** indicate the type of work:
- `[logic]` — business logic, API routes, data models, state management, utilities
- `[ui]` — components, pages, layouts, styling, user interactions
- `[infra]` — configuration, environment setup, dependency installation, CI/CD

Avoid vague tasks like "implement X" — each task should describe exactly what to build or change. These tasks will be consumed by downstream tooling, so they should be as specific as possible.
