# PRD: Project Infrastructure & Tooling Setup

## Constraints

- Only modify `package.json` scripts, configuration files, and the `tests/` directory.
- All test files must pass on first execution.
- Do not install additional packages.

## Tasks

- [ ] Configure TypeScript. Create a `tsconfig.json` with `target` set to `ES2022`, `module` set to `NodeNext`, `moduleResolution` set to `NodeNext`, `strict` enabled, and `outDir` set to `dist/`. Also have the config `include` any `**/*` files and create a file `src/index.ts` with only `export {};` to indicate the project is empty. Have the `types` array includes `jest` and `node`. Make sure to `exclude` the folders `.next`, `dist` and `node_modules`. `[test: npx tsc --noEmit]`

- [ ] Configure Jest. Create a `jest.config.js` using the `@swc/jest` preset for a standard Node/TypeScript environment. Add a `"test:unit"` script to `package.json` that runs Jest. Create a sanity test at `tests/unit/setup.spec.ts` with a single passing assertion (`expect(1 + 1).toBe(2)`). Add both `*.spec.ts` and `*.test.ts` as a pattern to discover test files. `[test: npx jest]`

- [ ] Configure Playwright. Create a `playwright.config.ts` set to run headless Chromium, with `baseURL` set to `http://localhost:3000` as a placeholder and `timeout` set to `10000`. Add a `"test:e2e"` script to `package.json` that runs Playwright. Create a sanity test at `tests/e2e/setup.spec.ts` that navigates to `about:blank` and asserts the page title is an empty string. Add both `*.spec.ts` and `*.test.ts` as a pattern to discover test files. `[test: npx playwright test]`

- [ ] Wire up a root test script. Update the `"test"` script in `package.json` to run `test:unit` and `test:e2e` sequentially. Verify it exits cleanly. `[test: npm test]`