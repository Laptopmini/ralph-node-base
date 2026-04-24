## Implementation Plan: Pomodoro Timer Homepage

### Assumptions
- The timer will be built with vanilla HTML, CSS, and JavaScript (ES modules) — no framework is installed and the PRD does not request one
- The 25-minute countdown displays as `MM:SS` format (e.g., `25:00`)
- "Pause" pauses at the current time; "Start" resumes from where it was paused; "Reset" returns the timer to `25:00` and stops it
- No audio notification or visual alert when the timer reaches `00:00` — the timer simply stops at zero (if desired, this can be added as a follow-up)
- The existing "Hello World" homepage content will be fully replaced by the Pomodoro timer

---

### 1. Tech Stack & Architecture Notes

**Detected stack:**
- Static HTML/CSS/JS served by `serve` (v14) on port 3000 — `src/` is served as-is, no build step
- No frontend framework (no React, Next.js, or Vite)
- TypeScript toolchain (SWC) exists for compiling `.ts` test sources, but the served `src/` is plain JS
- Jest (unit tests in `tests/unit/`)
- Biome for linting/formatting

**Relevant existing patterns:**
- Single-page app structure: `src/index.html` is the entry point, `src/style.css` for styles, `src/index.ts` for logic
- `serve -s src -l 3000` serves the `src/` directory as a static site
- E2E tests navigate to `http://localhost:3000/` and assert on visible content

**Recommendations:**
- Keep the timer logic in a separate ES module (`src/timer.js`) so it can be unit-tested independently via Jest — the pure logic (countdown math, state transitions) should be importable without a DOM. Use JSDoc type annotations for clarity
- Load the browser-facing code (`src/app.js`) as an ES module via `<script type="module">`, importing from `./timer.js` directly. This keeps the project build-free end-to-end
- No new dependencies are needed

---

### 2. File & Code Structure

**New files:**
- `src/timer.js` — pure timer logic (no DOM)
- `src/app.js` — browser script that wires DOM to timer logic

**Modified files:**
- `src/index.html` — replace "Hello World" with Pomodoro timer UI
- `src/style.css` — add styles for timer display and buttons

**Conflicting test files to remove:**
- `tests/unit/homepage.test.ts` — asserts "Hello World" text which will no longer exist on the homepage

---

### 3. Tickets

Tickets are workstreams. No two tickets touch the same file. A ticket is workable once
all tickets in its `depends_on` list are complete. Siblings under the same parent run in parallel.

---

#### Ticket 1: Timer Logic Module

> Pure JavaScript ES module implementing the Pomodoro countdown state machine, testable without a browser.

**Constraints:**
- Must be a pure module with no DOM or browser API references — use dependency injection for the clock (`Date.now` or a callback) so tests can control time
- Export all public classes and functions as named ES module exports so Jest and the browser can import them directly
- Use JSDoc `@param` / `@returns` annotations on public methods for clarity

**Files owned:**
- `src/timer.js` (create)

**Tasks:**
1. [code] Create `src/timer.js` as an ES module exporting a `PomodoroTimer` class (or equivalent factory) with the following interface:
   - Constructor accepts `durationSeconds: number` (default `1500` for 25 minutes) and an `onTick` callback `(remainingSeconds: number) => void`
   - `start()` — begins or resumes the countdown, calling `onTick` every second with the remaining seconds. If already running, no-op
   - `pause()` — pauses the countdown, preserving the remaining time. If not running, no-op
   - `reset()` — stops the countdown and resets remaining time to the initial `durationSeconds`, calling `onTick` once with the reset value
   - `getRemaining(): number` — returns current remaining seconds
   - `isRunning(): boolean` — returns whether the timer is actively counting down
   - When remaining seconds reaches `0`, the timer stops automatically and calls `onTick(0)`
   - Use `setInterval` / `clearInterval` internally (1-second interval). Accept an optional `intervalFn` parameter for testability (defaults to `setInterval`/`clearInterval`)

---

#### Ticket 2: UI & Styling
**depends_on:** [Ticket 1]

> Replace the Hello World homepage with the Pomodoro timer interface, wiring the DOM to the PomodoroTimer class from Ticket 1.

**Constraints:**
- Use `data-testid` attributes on all interactive and display elements
- The page must remain a single static HTML file served by `serve` — no build step
- Follow existing Biome formatting rules (double quotes, trailing commas, semicolons, 2-space indent)

**Files owned:**
- `src/app.js` (create)
- `src/index.html` (modify)
- `src/style.css` (modify)
- `tests/unit/homepage.test.ts` (delete)

**Tasks:**
1. [infra] Delete `tests/unit/homepage.test.ts` — this E2E test asserts "Hello World" text which will no longer exist after the homepage is replaced by the Pomodoro timer. Verify the file no longer exists on disk and that no other source files import or reference it
2. [code] Create `src/app.js` as an ES module — imports `PomodoroTimer` from `./timer.js` at the top. On `DOMContentLoaded`, selects elements by `data-testid` attribute. Instantiates `PomodoroTimer` with an `onTick` callback that formats remaining seconds as `MM:SS` using `Math.floor(remaining / 60)` and `remaining % 60`, zero-padded, and updates `[data-testid="timer-display"]` text content. Wire button click handlers:
   - **Start button click**: calls `timer.start()`
   - **Pause button click**: calls `timer.pause()`
   - **Reset button click**: calls `timer.reset()`
3. [code] Modify `src/index.html` — replace the `<body>` content with the Pomodoro timer layout:
   - Page title: `<h1 data-testid="page-title">Pomodoro Timer</h1>`
   - Timer display: `<div data-testid="timer-display">25:00</div>` — large, centered text showing `MM:SS`
   - Three buttons in a row:
     - `<button data-testid="start-button">Start</button>`
     - `<button data-testid="pause-button">Pause</button>`
     - `<button data-testid="reset-button">Reset</button>`
   - Add `<script type="module" src="app.js"></script>` before `</body>` (the `type="module"` is required so `app.js` can import from `./timer.js`)
   - Keep the existing `<link rel="stylesheet" href="style.css" />` in the head
   - Keep the `<title>` as "Pomodoro Timer"
4. [code] Modify `src/style.css` — add styles for the timer UI:
   - Center the content vertically and horizontally on the page
   - `[data-testid="timer-display"]`: large font size (at least 4rem), monospace font, centered
   - Buttons: visually distinct, at least 44px tall for accessibility, spaced evenly, with hover/active states
   - Responsive: readable on mobile viewports (min-width 320px)

---

> **Note:** A ticket is workable once all tickets in its `depends_on` list are complete — siblings under the same parent run in parallel. Tasks within each ticket are sequential. No ticket includes test creation — testing is handled separately.
