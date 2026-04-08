# ralph-node

An orchestrated, test-gated AI development pipeline for Node.js using a Ralph loop — turn a feature request into reviewed, merged code through PR-gated phases.

> This is my Ralph loop. There are many like it, but this one is mine.

1. **Blueprint-driven planning** — `/blueprint` turns a feature request into a hierarchical implementation plan with tree levels
2. **Ticketmaster** — `/ticketmaster` slices each level into branches and per-ticket PRDs, then opens PRs for human review
3. **Test backpressure** — failing tests are generated for each ticket and opened as a second PR for review
4. **Ralph implementation** — the inner test-gated loop iterates per PRD until every task passes its targeted test
5. **PR-gated supervision** — a human reviews and merges PRs at three checkpoints (tickets, backpressure, implementation); a final summary PR closes out the feature

## Why this exists

This repo is an exercise in applied AI engineering — specifically in designing systems where LLM agents operate reliably under constraints. The goals:

- **Create my own implementation of the Ralph Loop** based on my readings and experience
- **Practice writing PRDs and blueprints that AI agents can execute** without inline human intervention
- **Optimize prompts and constraints** for deterministic, test-driven AI output
- **Build a forkable starting point** for generating different project types (Next.js, React + Vite, static sites) by swapping in a new seed PRD

## How it works

**Pick a starting point:**

- **From scratch** — fork this repo and run `nvm use && bash init.sh` to bootstrap. `init.sh` runs a Ralph loop on the seed PRD to set the project up, then self-destructs. Once that's done, `npm run maestro` takes over for all feature work.
- **From a fork** — browse [existing forks](https://github.com/topics/ralph-node) and start from one that already has an initialized project. This saves tokens by iterating from a checkpoint instead of regenerating from zero.

Any repo — this one or a fork — can serve as the starting point for the next iteration.

**Run Maestro:**

```bash
npm run maestro   # Provide a feature request; Maestro drives blueprint → tickets → backpressure → ralph
```

Maestro pauses at three PR gates so a human can review and merge between phases. Each PRD task uses the same checkbox + targeted-test format Ralph consumes:

```markdown
- [ ] Create a responsive landing page `[test: npx playwright test tests/landing.spec.ts]`
- [ ] Add dark mode toggle `[test: npx playwright test tests/theme.spec.ts]`
```

PRDs are normally authored by `/ticketmaster` from the blueprint, but you can hand-edit them when needed. The inner phases are also available as escape hatches:

- `npm run backpressure` — generate failing tests for the active `PRD.md`
- `npm run ralph` — run the test-gated implementation loop on a single PRD

## Key design decisions

- **Human-in-the-loop via PRs only**: supervision happens through three PR review gates (tickets, backpressure, implementation), not interactive prompts
- **Hierarchical planning**: Maestro breaks features into blueprint tree levels so dependent slices land in order
- **Test-gated commits**: code only lands if validation passes — no manual review inside the inner loop
- **Targeted backpressure**: each PRD task can specify its own test command via `[test: ...]`, so the agent gets fast, focused feedback instead of running the full suite
- **Stateless agents with structured handoff**: Ralph agents have no memory between cycles — context is explicitly injected via a scratchpad (`MEMORY.md`) and an append-only ledger (`.agent-ledger.jsonl`)
- **Infrastructure isolation**: orchestrator scripts and prompts are protected from agent modification via `.aignore` and permission settings

## Stack

| Tool | Role |
|------|------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Agentic CLI |
| [LM Studio](https://lmstudio.ai/) | Local LLM Server |
| [Jest](https://jestjs.io/) | Unit testing |
| [Playwright](https://playwright.dev/) | E2E testing |
| [Biome](https://biomejs.dev/) | Linting and formatting |

## License

Apache 2.0