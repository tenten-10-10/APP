# PlotName AI — Backend

Backend scaffold for **PlotName AI**, an app that turns a one-line idea into a
manga plot / storyboard (ネーム) using the **FABLE pipeline**.

```
one-line idea
  → StoryBrief
  → Save the Cat genre classification
  → 13-phase structure (日常 … 満足)
  → page plan (e.g. 35 pages)
  → per-page panel layout
  → dialogue + image prompts
```

It runs **end-to-end fully offline** with a deterministic Mock AI provider (no
API key needed). An OpenAI provider exists behind the same interface but is not
required to run.

## Quick start

```bash
cd PlotNameAI/backend
npm install
npm run typecheck   # tsc --noEmit
npm run demo        # prints the full 35-page plan summary
npm test            # node:test suite (via tsx)
```

### Scripts

| Script             | What it does                                           |
| ------------------ | ------------------------------------------------------ |
| `npm run build`    | `tsc` → `dist/`                                         |
| `npm run typecheck`| `tsc --noEmit`                                          |
| `npm run demo`     | Runs the pipeline on a sample idea and prints a report |
| `npm test`         | Runs `tsx --test test/*.test.ts`                       |

## Environment variables

| Var              | Default | Meaning                                              |
| ---------------- | ------- | ---------------------------------------------------- |
| `AI_PROVIDER`    | `mock`  | `mock` (offline, deterministic) or `openai`          |
| `OPENAI_API_KEY` | —       | Required only when `AI_PROVIDER=openai`              |
| `OPENAI_MODEL`   | `gpt-4.1` | Model id used by the OpenAI provider               |

The `openai` package is an **optional dependency** loaded via dynamic import
only inside `openaiProvider`, so `npm install` and the demo never depend on it.

## Architecture

```
src/
  schemas/index.ts     Canonical Zod schemas + inferred TS types (shared with iOS)
  providers/
    types.ts           AIProvider interface
    mockProvider.ts    Deterministic, schema-valid output (35-page plan)
    openaiProvider.ts  OpenAI Responses API shape (optional, not run offline)
    index.ts           createProvider() factory (env AI_PROVIDER, default mock)
  agents/              One wrapper per pipeline step; each validates with Zod
    intakeAgent, genreAgent, phaseAgent, characterAgent, sceneAgent,
    pagePlannerAgent, layoutAgent, dialogueAgent, visualPromptAgent,
    criticAgent, safetyAgent
  billing/
    plans.ts           free/plus/pro/studio limits + credit cost table
    entitlements.ts    resolve features/limits + enforcement helpers
  usage/ledger.ts      In-memory ledger: record(), creditsBalance(), estimateCost()
  pipeline.ts          FABLE orchestrator (safety → genre → … → critique)
  demo.ts              Readable end-to-end demo
test/pipeline.test.ts  node:test assertions
```

### The FABLE pipeline

`runPipeline()` runs, in order:

1. **safetyAgent** (gate, runs first on the raw idea)
2. **genreAgent** — Save the Cat classification
3. **intakeAgent** + **characterAgent** — build the StoryBrief
4. **phaseAgent** + **sceneAgent** — 13-phase structure (enforces exactly 13)
5. **pagePlannerAgent** — page-by-page plan (enforces exact page count)
6. per page: **layoutAgent** → **dialogueAgent** → **visualPromptAgent**
7. **criticAgent** — overall structure score

Every agent validates its provider output against the canonical Zod schemas;
invalid output throws. The mock provider is fully deterministic — no
`Math.random` / `Date.now` influences output ordering — so the same input always
yields the same plan.

#### Standard structure template

The mock provider apportions pages across the 13 phases (largest-remainder, so
totals are exact) and shapes the emotional curve:

- **page 1** — single-panel hook, turning point
- **phase 7 (達成)** — mid-story victory, emotional peak (+3)
- **phase 9 (破滅)** — all-is-lost low point (−3)
- **phase 13 (満足)** — final satisfaction (+3), owns the last page
- structural turning points near pages 16 & 20 (scaled to the page count)

## Copyright / safety stance

PlotName AI generates **original** work. The `safetyAgent` refuses any request
that tries to imitate specific real manga, real authors, or "draw in the style
of \<real artist\>". It uses:

- a **deny list** of well-known titles/franchises and authors
  (e.g. ONE PIECE / ワンピース, 鬼滅, NARUTO, ドラゴンボール, 尾田栄一郎, 鳥山明 …)
- **structural patterns** such as `○○先生風`, `…の絵柄で`, `…風に描いて`,
  `in the style of …`

The gate runs **first** on the raw idea, and every generated `image_prompt` is
re-checked so no IP-infringing style reference can leak into output. Blocked
requests return `{ allowed: false, reason }`; the pipeline throws `SafetyError`.

## Billing model (summary)

Plans: `free` / `plus` / `pro` / `studio`, each with monthly credits, project /
page / image limits, and feature flags (OpenAI provider, image generation, PDF
export, team seats, priority queue). Billable actions have a credit cost
(`CREDIT_COSTS`) and the usage ledger also estimates USD cost from token / image
counts.

## TODO / not implemented

- HTTP layer (this is a library scaffold; no server is started).
- Persistence (ledger and projects are in-memory).
- Real image generation (only prompts are produced).
- The OpenAI provider is wired to the Responses API shape but is not exercised
  offline and has not been run against the live API.
