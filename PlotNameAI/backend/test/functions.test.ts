import { test } from "node:test";
import assert from "node:assert/strict";

import { DataStore } from "../src/functions/store.js";
import { createRouter, type Router } from "../src/functions/router.js";
import type { Res } from "../src/functions/http.js";

/**
 * HTTP-handler tests. Each test gets a fresh store + router so state never
 * leaks between tests. We exercise the framework-agnostic router directly
 * (no server needed).
 */

function freshRouter(): { router: Router; store: DataStore } {
  const store = new DataStore();
  const router = createRouter(store);
  return { router, store };
}

const GOOD_IDEA = "田舎の高校生が、死んだ祖父のノートを頼りに幻の星を探す話";

function call(
  router: Router,
  method: string,
  path: string,
  body?: unknown,
): Promise<Res> {
  return router.dispatch({ method, path, query: {}, body });
}

async function createProject(router: Router, idea = GOOD_IDEA, page_count = 35) {
  const res = await call(router, "POST", "/projects", {
    title: "星をさがすノート",
    idea,
    format: "manga",
    page_count,
    protagonist_name: "ハル",
  });
  assert.equal(res.status, 201);
  return res.body as { id: string };
}

/** Poll a job until it reaches a terminal status (or times out). */
async function waitForJob(
  router: Router,
  jobId: string,
): Promise<{ status: string; output: unknown; error: string | null }> {
  for (let i = 0; i < 50; i++) {
    const res = await call(router, "GET", `/jobs/${jobId}`);
    const job = res.body as { status: string; output: unknown; error: string | null };
    if (job.status === "succeeded" || job.status === "failed") return job;
    await new Promise((r) => setTimeout(r, 5));
  }
  throw new Error("job did not reach terminal status");
}

test("full per-step flow: brief → genre → 13 phases → 35 pages → layout → critique", async () => {
  const { router } = freshRouter();
  const { id } = await createProject(router);

  const brief = await call(router, "POST", `/projects/${id}/story-brief`, {});
  assert.equal(brief.status, 200);

  const genre = await call(router, "POST", `/projects/${id}/classify-genre`, {});
  assert.equal(genre.status, 200);

  const phases = await call(router, "POST", `/projects/${id}/generate-phases`, {});
  assert.equal(phases.status, 200);
  assert.equal((phases.body as unknown[]).length, 13);

  const pages = await call(router, "POST", `/projects/${id}/generate-page-plan`, {});
  assert.equal(pages.status, 200);
  assert.equal((pages.body as unknown[]).length, 35);

  const layout = await call(router, "POST", `/projects/${id}/generate-layout`, {});
  assert.equal(layout.status, 200);
  assert.ok((layout.body as unknown[]).length >= 35);

  const critique = await call(router, "POST", `/projects/${id}/critique`, {});
  assert.equal(critique.status, 200);
  assert.ok(typeof (critique.body as { score: number }).score === "number");

  // GET /projects/:id/pages returns the persisted plan + panels.
  const got = await call(router, "GET", `/projects/${id}/pages`);
  assert.equal(got.status, 200);
  assert.equal((got.body as { pagePlan: unknown[] }).pagePlan.length, 35);
});

test("projects CRUD: create/list/get/patch/delete", async () => {
  const { router } = freshRouter();
  const { id } = await createProject(router);

  const list = await call(router, "GET", "/projects");
  assert.equal(list.status, 200);
  assert.equal((list.body as unknown[]).length, 1);

  const patched = await call(router, "PATCH", `/projects/${id}`, { title: "改題" });
  assert.equal(patched.status, 200);
  assert.equal((patched.body as { title: string }).title, "改題");

  const del = await call(router, "DELETE", `/projects/${id}`);
  assert.equal(del.status, 200);

  const gone = await call(router, "GET", `/projects/${id}`);
  assert.equal(gone.status, 404);
});

test("/ads/reward increases the credit balance", async () => {
  const { router, store } = freshRouter();
  const before = store.ledger.creditsBalance();
  const res = await call(router, "POST", "/ads/reward", { credits: 25 });
  assert.equal(res.status, 200);
  const body = res.body as { granted: number; credits_balance: number };
  assert.equal(body.granted, 25);
  assert.equal(body.credits_balance, before + 25);
  assert.equal(store.ledger.creditsBalance(), before + 25);
});

test("an infringing idea returns 422 from a generate endpoint", async () => {
  const { router } = freshRouter();
  const { id } = await createProject(router, "ONE PIECE風に描いて");
  const res = await call(router, "POST", `/projects/${id}/classify-genre`, {});
  assert.equal(res.status, 422);
  assert.equal((res.body as { error: { code: string } }).error.code, "safety_blocked");
});

test("enqueued generate-name job reaches succeeded with a result", async () => {
  const { router } = freshRouter();
  const { id } = await createProject(router);
  const res = await call(router, "POST", `/projects/${id}/generate-name`, {});
  assert.equal(res.status, 202);
  const { job_id, status } = res.body as { job_id: string; status: string };
  assert.equal(status, "queued");

  const job = await waitForJob(router, job_id);
  assert.equal(job.status, "succeeded");
  const out = job.output as { panel_count: number; page_count: number };
  assert.equal(out.page_count, 35);
  assert.ok(out.panel_count >= 35);
});

test("enqueued generate-panel-image job charges 1 credit and returns a rough placeholder", async () => {
  const { router, store } = freshRouter();
  const { id } = await createProject(router);
  // Build panels first so a panel exists.
  await call(router, "POST", `/projects/${id}/story-brief`, {});
  await call(router, "POST", `/projects/${id}/generate-phases`, {});
  await call(router, "POST", `/projects/${id}/generate-page-plan`, {});
  await call(router, "POST", `/projects/${id}/generate-layout`, {});

  const spentBefore = store.ledger.creditsSpent();
  const res = await call(router, "POST", `/projects/${id}/generate-panel-image`, {
    panel_id: "1:1",
  });
  assert.equal(res.status, 202);
  const { job_id } = res.body as { job_id: string };
  const job = await waitForJob(router, job_id);
  assert.equal(job.status, "succeeded");
  const out = job.output as { image_kind: string; data_uri: string };
  assert.equal(out.image_kind, "rough_placeholder");
  assert.ok(out.data_uri.startsWith("data:image/svg+xml"));
  assert.equal(store.ledger.creditsSpent(), spentBefore + 1);
});

test("GET /billing/entitlements and GET /usage", async () => {
  const { router } = freshRouter();
  const ent = await call(router, "GET", "/billing/entitlements");
  assert.equal(ent.status, 200);
  assert.ok((ent.body as { plan: string }).plan);

  const usage = await call(router, "GET", "/usage");
  assert.equal(usage.status, 200);
  assert.ok("credits_balance" in (usage.body as object));
});

test("POST /exports/project-json returns the full bundle", async () => {
  const { router } = freshRouter();
  const { id } = await createProject(router);
  await call(router, "POST", `/projects/${id}/story-brief`, {});
  const res = await call(router, "POST", "/exports/project-json", { project_id: id });
  assert.equal(res.status, 200);
  const bundle = res.body as { project: { id: string }; brief: unknown };
  assert.equal(bundle.project.id, id);
  assert.ok(bundle.brief);
});

test("PATCH page and panel persist edits", async () => {
  const { router } = freshRouter();
  const { id } = await createProject(router);
  await call(router, "POST", `/projects/${id}/story-brief`, {});
  await call(router, "POST", `/projects/${id}/generate-phases`, {});
  await call(router, "POST", `/projects/${id}/generate-page-plan`, {});
  await call(router, "POST", `/projects/${id}/generate-layout`, {});

  const page = await call(router, "PATCH", `/projects/${id}/pages/2`, {
    page_goal: "新しい目的",
  });
  assert.equal(page.status, 200);
  assert.equal((page.body as { page_goal: string }).page_goal, "新しい目的");

  const panel = await call(router, "PATCH", `/projects/${id}/panels/1:1`, {
    dialogue: "……星か。",
  });
  assert.equal(panel.status, 200);
  assert.equal((panel.body as { dialogue: string }).dialogue, "……星か。");
});

test("unknown route → 404", async () => {
  const { router } = freshRouter();
  const res = await call(router, "GET", "/nope/nowhere");
  assert.equal(res.status, 404);
});

test("invalid body → 400", async () => {
  const { router } = freshRouter();
  // Missing required title/idea.
  const res = await call(router, "POST", "/projects", { format: "manga" });
  assert.equal(res.status, 400);
  assert.equal((res.body as { error: { code: string } }).error.code, "invalid_body");
});
