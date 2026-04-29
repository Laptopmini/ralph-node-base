```
┌──────────────────────────────────────────────────────────────────────────────┐
│__________        .__         .__               _______             .___      │
│\______   \_____  |  | ______ |  |__            \      \   ____   __| _/____  │
│ |       _/\__  \ |  | \____ \|  |  \   ______  /   |   \ /  _ \ / __ |/ __ \ │
│ |    |   \ / __ \|  |_|  |_> >   Y  \ /_____/ /    |    (  <_> ) /_/ \  ___/ │
│ |____|_  /(____  /____/   __/|___|  /         \____|__  /\____/\____ |\___  >│
│        \/      \/     |__|        \/                  \/            \/    \/ │
└──────────────────────────────────────────────────────────────────────────────┘
```

An orchestrated, test-gated AI development pipeline for Node.js using a Ralph loop — turn a simple paragraph into a planned, tested, reviewed, fully working implementation using PR-gated phases.

> This is my Ralph loop. There are many like it, but this one is mine.

1. **Blueprint-driven planning** — a highly optimized prompt turns a feature request into a hierarchical implementation plan with tree levels
2. **Test backpressure** — failing tests are generated for each ticket
3. **Ralph implementation** — the inner test-gated loop iterates per PRD until every task passes its targeted test
4. **PR-gated supervision** — a human reviews and merges PRs at key checkpoints (tickets, backpressure, implementation); a final summary PR closes out the feature

## Why this exists

This repo is an exercise in applied AI engineering — specifically in designing systems where LLM agents operate reliably under constraints. The goals:

- **Create my own implementation of the Ralph Loop** based on my readings and experience
- **Research orchestration of heterogeneous LLM models** routing tasks to the model that is best-suited by capability, cost, and latency
- **Write highly optimized prompts for agents of different capabilities** — from large frontier planners to small local models used as interns
- **Minimize token spend** leverage local and cheaper cloud execution while being guarded by smarter models to avoid failure and maximize bang for the buck
- **Build a forkable starting point** for generating different project types (Next.js, React + Vite, static sites) by iterating new executions without starting from scratch

## Models

Each role in the pipeline is assigned a model matched to the cognitive demand and cost tolerance of that task.

| Role | Default Model | Execution | Responsibility |
|------|--------------|-----------|----------------|
| Project Manager | `claude-opus-4-7` | Cloud (Anthropic) | Blueprint planning — turns a feature request into a structured, strongly-typed implementation contract |
| Staff Developer | `claude-opus-4-6` | Cloud (Anthropic) | Repair & supervision — intervenes when the implementation loop gets stuck and reviews the final implmentation |
| Senior Developer | `deepseek-v4-pro` | Cloud (OpenRouter) | Backpressure — writes failing tests that guard each PRD task |
| Junior Developer | `minimax/MiniMax-M2.7` | Cloud (MiniMax) | Implementation — executes one PRD task at a time inside the Ralph loop |
| Intern | `google/gemma-4-26b-a4b` | Local (LM Studio) | PR summaries — writes titles and descriptions for each pull request |

Models are configured in `maestro.sh` and can be overridden in `.env`. Any model reachable via LM Studio (local) or in the cloud via Claude Code or OpenCode.

## How it works

**Pick a starting point:**

- **From scratch** — fork this repo and run `nvm use && bash init.sh` to bootstrap. `init.sh` runs a Ralph loop on the seed PRD to set the project up, then self-destructs. Once that's done, `npm run maestro` takes over for all feature work.
- **From a fork** — browse [existing forks](https://github.com/topics/ralph-node) and start from one that already has an initialized project. This saves tokens by iterating from a checkpoint instead of regenerating from zero.

Any repo — this one or a fork — can serve as the starting point for the next iteration.

**Run Maestro:**

```bash
npm run maestro   # Provide a feature request
```

Maestro then drives the full pipeline automatically, pausing only at PR gates:

1. **Plan** — the Project Manager produces a blueprint and opens it locally for your review. Approve to proceed, or reject to regenerate.
2. **Ticket** — the blueprint is deterministically parsed into per-ticket branches with PRDs. The Senior Developer generates failing tests (backpressure) for each ticket and opens PRs for your review. Merge to continue.
3. **Implement** — the Junior Developer runs the Ralph loop on each ticket: one PRD task at a time, gated by its targeted test. If a task stalls, the Staff Developer intervenes — patching code or backpressure directly — then hands control back. Completed branches are opened as PRs for your review. Merge to continue.
4. **Review** — once all tickets are complete, the Staff Developer reviews the final implementation against the original blueprint, validates accuracy, and fixes minor discrepancies. If it identifies improvements to the process itself, it surfaces them as suggestions for your next run.

At each step, the Intern writes PR titles and descriptions so every gate is reviewable without reading diffs.

## Key design decisions

- **Multi-model routing by role**: planning goes to the most capable frontier model; backpressure to an advanced model; implementation to a cheap model; low-stakes writing (PR summaries) to a free local model — cost scales with cognitive demand
- **Deterministic ticketing**: Ticketmaster parses a regex-strict blueprint format into PRDs with zero token spend and zero hallucination risk
- **Blueprint as a strongly-typed contract**: the blueprint prompt enforces a machine-parseable task-line schema (`[tag, slug, ext]`) so the downstream parser never needs to interpret freeform prose
- **Human-in-the-loop via PRs only**: supervision happens through PR review gates (backpressure, implementation), allowing to prevent runaway executions
- **Hierarchical planning**: Maestro breaks features into blueprint tree levels so dependent slices land in order
- **Test-gated commits**: code only lands if validation passes — no manual review inside the inner loop
- **Targeted backpressure**: each PRD task specifies its own test command via `[test: ...]`, so the agent gets fast, focused feedback instead of running the full suite
- **Regression guarding**: Ralph accumulates prior tasks' test commands and re-runs them on each iteration, catching regressions before they are committed
- **Repair escalation**: when the implementation loop stalls, a Staff Developer inspects the failure and patches code or backpressure directly, then hands control back to the Junior
- **Stateless agents with structured handoff**: Ralph agents have no memory between cycles — context is explicitly injected via a scratchpad (`MEMORY.md`) and an append-only ledger (`.agent-ledger.jsonl`)
- **Dual CLI execution**: Leverages both Claude Code and OpenCode based on the task at hand and the model being used based on the optimal context the task requires

## Stack

| Tool | Role |
|------|------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Agentic CLI for Anthropic and MiniMax models |
| [OpenCode](https://opencode.ai/) | Agentic CLI for local LM Studio models |
| [LM Studio](https://lmstudio.ai/) | Local LLM server (Intern role) |
| [Jest](https://jestjs.io/) | Unit testing |
| [Playwright](https://playwright.dev/) | E2E testing |
| [Biome](https://biomejs.dev/) | Linting and formatting |

## License

Apache 2.0
