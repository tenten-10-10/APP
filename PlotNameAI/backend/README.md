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
| `npm run serve`    | Starts the optional `node:http` dev server (REST API)  |
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
  functions/           Framework-agnostic REST handler layer
    http.ts            Req/Res/Handler types + ok()/err()/parseBody() helpers
    schemas.ts         Small request-body Zod schemas
    store.ts           In-memory DataStore (projects/jobs + shared ledger)
    router.ts          method+path router with :param + createRouter()
    handlers/          projects (CRUD), generate (per-step), misc (pages/billing/jobs)
  jobs/index.ts        In-memory async JobRunner (generate-name, generate-panel-image)
  server.ts            Optional node:http dev server (npm run serve) — not used by tests
  demo.ts              Readable end-to-end demo
test/pipeline.test.ts  node:test assertions (pipeline)
test/functions.test.ts node:test assertions (REST handlers)
```

## REST API

A **framework-agnostic** handler layer lives in `src/functions/`. Handlers are
pure functions of `Req → Res`:

```ts
type Req = { method: string; path: string; params: Record<string,string>; query: Record<string,string>; body: unknown };
type Res = { status: number; body: unknown };
type Handler = (req: Req) => Promise<Res> | Res;
```

`createRouter(store?)` wires every route to an in-memory `DataStore` (no DB;
`crypto.randomUUID` for ids, `new Date().toISOString()` for timestamps — never
in pipeline ordering). The optional `src/server.ts` adapts `node:http` to the
router; tests call the router directly.

### Endpoints

| Method & path | Purpose |
| --- | --- |
| `POST /projects` | Create a project (body: `title`, `idea`, `format`, `page_count`, `tone`, `protagonist_name?`) |
| `GET /projects` | List projects |
| `GET /projects/:id` | Get a project + any generated data |
| `PATCH /projects/:id` | Update title/status/tone/page_count |
| `DELETE /projects/:id` | Delete a project |
| `POST /projects/:id/story-brief` | Build (or override) the StoryBrief (runs genre + intake + character) |
| `POST /projects/:id/classify-genre` | Save-the-Cat genre verdict |
| `POST /projects/:id/generate-phases` | 13-phase structure |
| `POST /projects/:id/generate-page-plan` | Page-by-page plan |
| `POST /projects/:id/generate-layout` | Per-page panels (layout + dialogue + image prompts) |
| `POST /projects/:id/critique` | Structure critique |
| `POST /projects/:id/generate-name` | **Async** — enqueue full-pipeline job → `{ job_id, status }` |
| `POST /projects/:id/generate-panel-image` | **Async** — enqueue a MOCK rough placeholder for one panel (body: `panel_id`); charges 1 image credit |
| `GET /jobs/:id` | Poll a generation job's status/result |
| `GET /projects/:id/pages` | Get the page plan + panels |
| `PATCH /projects/:id/pages/:pageNumber` | Edit a page plan |
| `PATCH /projects/:id/panels/:panelId` | Edit a panel (`panelId` = `"<page>:<panel>"`) |
| `GET /billing/entitlements` | Current plan features/limits |
| `GET /usage` | Credits spent/balance, cost estimate, ledger entries |
| `POST /ads/reward` | Grant credits for a rewarded ad (body: `credits`) |
| `POST /exports/project-json` | Full `ProjectBundle` JSON (body or query: `project_id`) |

Generate endpoints run the **safetyAgent first** on the project's idea and
return **422** if it is blocked. Invalid bodies return **400** with a typed
error; unknown routes return **404**; async enqueue returns **202**.

### Run the server + curl an example

```bash
npm run serve                       # listens on http://localhost:8787 (PORT to override)

# create a project, then classify its genre
curl -s -X POST localhost:8787/projects \
  -H 'content-type: application/json' \
  -d '{"title":"星をさがすノート","idea":"田舎の高校生が幻の星を探す話","page_count":35,"protagonist_name":"ハル"}'

curl -s -X POST localhost:8787/projects/<id>/classify-genre

# enqueue the full pipeline, then poll the job
curl -s -X POST localhost:8787/projects/<id>/generate-name
curl -s localhost:8787/jobs/<job_id>

# grant ad credits / read entitlements
curl -s -X POST localhost:8787/ads/reward -H 'content-type: application/json' -d '{"credits":10}'
curl -s localhost:8787/billing/entitlements
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

- Persistence (the `DataStore`, ledger, and jobs are all in-memory and reset on
  restart — no Postgres/Supabase yet).
- Real image generation: `generate-panel-image` returns a deterministic MOCK
  inline-SVG placeholder, not a rendered image.
- Auth / multi-user: the store assumes a single `demo-user` on the `plus` plan.
- Export endpoints other than `project-json` (PDF / PNG-zip) and the
  RevenueCat billing webhook from ARCHITECTURE.md §6 are not implemented.
- `generate-scenes` is folded into `generate-phases` (sceneAgent runs there),
  so there is no standalone endpoint for it.
- The OpenAI provider is wired to the Responses API shape but is not exercised
  offline and has not been run against the live API.
