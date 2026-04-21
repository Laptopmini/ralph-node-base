# ralph-node-base

A fork of [ralph-node](https://github.com/Laptopmini/ralph-node) that has been initialized by running the bootstrap PRD. Save some tokens by using this as a starting point, or just do it yourself!

For full documentation on how to use `ralph-node` and these repos, see the [original ralph-node README](https://github.com/Laptopmini/ralph-node#readme).

## Changelog

- **TypeScript** — `tsconfig.json` with ES2022 target, NodeNext modules, strict mode, and `dist/` output
- **Jest** — `jest.config.js` with `@swc/jest` transform scoped to unit tests, plus a sanity test
- **Playwright** — `playwright.config.ts` targeting Chromium at `localhost:3000`, plus a sanity E2E test
- **Root test script** — `npm test` wired to run unit then E2E tests sequentially

## Stack

| Tool | Role |
|------|------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Agentic CLI |
| [OpenCode](https://opencode.ai/) | Open Source Agentic CLI |
| [LM Studio](https://lmstudio.ai/) | Local LLM Server |
| [Jest](https://jestjs.io/) | Unit testing |
| [Playwright](https://playwright.dev/) | E2E testing |
| [Biome](https://biomejs.dev/) | Linting and formatting |

## License

Apache 2.0