Implemented third task: Playwright configuration.

- Created `playwright.config.ts` using `defineConfig` from `@playwright/test`, scoped to `./tests/e2e` with `testMatch: "**/*.spec.ts"`, headless Chromium via `devices["Desktop Chrome"]`, and `baseURL: "http://localhost:3000"`.
- Created `tests/e2e/setup.spec.ts` that navigates to `about:blank` and asserts `page.title()` returns `""`.
- Updated `package.json`: added `"test:e2e": "playwright test"` script, updated `"test"` to `"npm run test:unit && npm run test:e2e"`.
- `package.json` uses `"type": "commonjs"` but `playwright.config.ts` is TypeScript — Playwright handles TS configs natively so no issue.
- Validation command: `npx playwright test`
- If Playwright can't find config, check that `playwright.config.ts` is at the repo root. If browser binaries are missing, they need to be installed (`npx playwright install chromium`), but that's outside our scope.
