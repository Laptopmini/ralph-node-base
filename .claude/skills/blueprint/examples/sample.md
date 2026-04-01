## Implementation Plan: Pomodoro Timer Homepage

### Assumptions
- The timer is purely client-side (no server state or persistence) — vanilla HTML/CSS/JS since there's no build pipeline or framework
- "25-minute countdown" means 25:00 displayed as `MM:SS`, counting down to 00:00
- The timer does not loop or auto-restart — user must manually reset after completion
- No audio/notification on completion (not specified); a visual indicator (e.g. "Time's up!" message) will suffice
- Since `serve` is a static file server with no build step, browser code must be vanilla JavaScript (not TypeScript)

---

### 1. Tech Stack & Architecture Notes

**Detected stack:** Static HTML served by `serve` v14.2.3 on port 3000. TypeScript configured for Jest/Node only. Vanilla CSS. Jest (unit) + Playwright (E2E).

**Relevant existing patterns:**
- `src/index.html` is the single entry point, linked to `style.css`
- E2E tests at `tests/e2e/homepage.spec.ts` already target localhost:3000 and use `data-testid` selectors
- Unit tests at `tests/unit/` use `@swc/jest` for TypeScript

**Recommendations:**
- Keep timer logic in a separate `src/timer.js` file for separation of concerns and `<script src>` inclusion
- Extract pure countdown logic into a testable module (`src/timer-logic.ts`) that Jest can import directly — this avoids needing DOM mocks for unit testing core arithmetic
- Existing `src/index.ts` can be repurposed or left as-is (it's an empty export placeholder)

---

### 2. File & Code Structure

**New files:**
- `src/timer.js` — Browser-side timer controller (DOM interaction + countdown orchestration)
- `src/timer-logic.ts` — Pure functions for time formatting and countdown math (testable by Jest)
- `tests/unit/timer-logic.test.ts` — Unit tests for time formatting and countdown logic
- `tests/e2e/pomodoro.spec.ts` — E2E tests for timer UI (start, pause, reset, countdown, completion)

**Modified files:**
- `src/index.html` — Replace "Hello World" with Pomodoro timer UI
- `src/style.css` — Add timer-specific styles

---

### 3. Tickets

Each ticket is an independent workstream. No two tickets touch the same file.

---

#### Ticket 1: Timer Logic (Pure Functions)

> Implement and unit-test the pure countdown logic that powers the timer — no DOM, no UI.

**Constraints:**
- Must be a TypeScript module importable by Jest (Node environment)
- No DOM or browser APIs — pure functions only
- Use `data-testid` conventions in any test utilities if needed

**Files owned:**
- `src/timer-logic.ts` (create)
- `tests/unit/timer-logic.test.ts` (create)

**Tasks:**
1. [logic] Create `src/timer-logic.ts` with pure functions: `formatTime(totalSeconds: number): string` (returns `"MM:SS"`), `tick(remainingSeconds: number): number` (decrements by 1, floors at 0), and a constant `POMODORO_DURATION_SECONDS = 1500`
2. [logic] Create `tests/unit/timer-logic.test.ts` — test `formatTime` (25:00, 00:00, 09:59 edge cases), test `tick` (decrements, does not go below 0), test duration constant equals 1500

---

#### Ticket 2: Timer UI & Browser Integration

> Build the Pomodoro timer interface as the homepage with Start, Pause, Reset buttons and a countdown display, plus E2E test coverage.

**Constraints:**
- Use `data-testid` attributes on all interactive and display elements
- Vanilla JS only (no build step available for browser code)
- Existing E2E test `tests/e2e/homepage.spec.ts` checks for "Hello World" — it must be updated or the new E2E test must replace its expectations
- Timer display, Start, Pause, and Reset buttons must all be present on page load

**Files owned:**
- `src/index.html` (modify)
- `src/style.css` (modify)
- `src/timer.js` (create)
- `tests/e2e/pomodoro.spec.ts` (create)
- `tests/e2e/homepage.spec.ts` (modify)

**Tasks:**
1. [ui] Modify `src/index.html` — replace the `<h1>Hello World</h1>` body content with a Pomodoro timer layout: a heading ("Pomodoro Timer"), a time display element (`data-testid="time-display"` showing `25:00`), and three buttons (`data-testid="start-btn"`, `data-testid="pause-btn"`, `data-testid="reset-btn"`). Add `<script src="timer.js"></script>` before `</body>`
2. [ui] Modify `src/style.css` — add styles for the timer container (centered layout), time display (large monospace font), and buttons (distinct visual states for start/pause/reset)
3. [logic] Create `src/timer.js` — implement the browser-side timer controller using `setInterval`: Start begins/resumes the countdown, Pause clears the interval and preserves remaining time, Reset clears the interval and restores display to `25:00`. Show a "Time's up!" message when countdown reaches `00:00`
4. [ui] Modify `tests/e2e/homepage.spec.ts` — update or remove the "Hello World" assertion since the homepage content is changing (replace with a check that the page loads and contains the Pomodoro timer heading)
5. [ui] Create `tests/e2e/pomodoro.spec.ts` — E2E tests: timer displays `25:00` on load; clicking Start begins countdown (verify display changes after a short wait); clicking Pause freezes the display; clicking Reset restores `25:00`; verify all three buttons are visible and clickable

---

> **Note:** Tickets can be worked in parallel. Ticket 1 produces the pure logic module; Ticket 2 builds the UI. The browser-side `timer.js` will inline its own countdown logic (since there's no bundler to import `.ts`), but keeping `timer-logic.ts` separately tested ensures correctness of the core math. Tasks within each ticket are sequential.
