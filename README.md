# ralph-node-base

A custom implementation of the Ralph Loop for Node.js — a test-gated, autonomous AI development cycle that turns PRDs into working code.

> This is my Ralph loop. There are many like it, but this one is mine.

## Why this exists

This repo is an exercise in applied AI engineering — specifically in designing systems where LLM agents operate reliably under constraints. The goals:

- **Create my own implementation of the Ralph Loop** based on my readings and experience
- **Practice writing PRDs that AI agents can execute** without human intervention
- **Optimize prompts and constraints** for deterministic, test-driven AI output
- **Build a forkable starting point** for generating different project types (Next.js, React + Vite, static sites) by swapping in a new PRD

## How it works

**Pick a starting point:**

- **From scratch** — fork this repo and run `nvm use && sh init.sh` to bootstrap. This lets you optimize the initial PRD and infrastructure.
- **From a fork** — browse [existing forks](https://github.com/topics/ralph-node) and start from one that already has an initialized project. This saves tokens by iterating from a checkpoint instead of regenerating from zero.

Any repo — this one or a fork — can serve as the starting point for the next iteration.

**Run the Ralph Loop:**

1. **Write a PRD** (`PRD.md`) with checkbox tasks:

   ```markdown
   - [ ] Create a responsive landing page `[test: npx playwright test tests/landing.spec.ts]`
   - [ ] Add dark mode toggle `[test: npx playwright test tests/theme.spec.ts]`
   ```

2. **Generate test backpressure** — failing tests that define "done", which are human verified and optimized post-creation:

   ```bash
   npm run backpressure
   ```

3. **Run the loop** — the agent implements until all tests pass:

   ```bash
   npm run ralph
   ```

## Key design decisions

- **Test-gated commits**: code only lands if validation passes — no manual review in the loop
- **Targeted backpressure**: each PRD task can specify its own test command via `[test: ...]`, so the agent gets fast, focused feedback instead of running the full suite
- **Stateless agents with structured handoff**: agents have no memory between cycles — context is explicitly injected via a scratchpad (`MEMORY.md`) and an append-only ledger (`.agent-ledger.jsonl`)
- **Infrastructure isolation**: the loop scripts and prompts are protected from agent modification via `.aignore` and permission settings

## Stack

| Tool | Role |
|------|------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Default AI engine |
| [OpenCode](https://opencode.ai/docs) | Alternative AI engine |
| [Jest](https://jestjs.io/) | Unit testing |
| [Playwright](https://playwright.dev/) | E2E testing |
| [Biome](https://biomejs.dev/) | Linting and formatting |

## License

Apache 2.0
