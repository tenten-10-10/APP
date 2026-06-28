import { test } from "node:test";
import assert from "node:assert/strict";

import { runPipeline, SafetyError } from "../src/pipeline.js";
import { MockProvider } from "../src/providers/mockProvider.js";
import { createProvider } from "../src/providers/index.js";
import { checkSafety } from "../src/agents/safetyAgent.js";
import {
  PhaseCardSchema,
  PagePlanSchema,
  PanelSpecSchema,
  ProjectSchema,
  StoryBriefSchema,
  phaseNameFor,
} from "../src/schemas/index.js";

const baseConfig = {
  idea: "田舎の高校生が、死んだ祖父のノートを頼りに幻の星を探す話",
  page_count: 35,
  format: "manga" as const,
  protagonist_name: "ハル",
  now: "2026-01-01T00:00:00.000Z",
};

test("pipeline produces exactly 13 phases, numbered 1..13 with canonical names", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  assert.equal(out.phases.length, 13);
  out.phases.forEach((p, i) => {
    assert.equal(p.phase_number, i + 1);
    assert.equal(p.phase_name, phaseNameFor(i + 1));
    PhaseCardSchema.parse(p);
  });
});

test("phases cover all 35 pages contiguously without gaps or overlaps", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  const allPages = out.phases.flatMap((p) => p.pages).sort((a, b) => a - b);
  assert.equal(allPages.length, 35);
  for (let i = 0; i < 35; i++) {
    assert.equal(allPages[i], i + 1);
  }
});

test("pipeline produces exactly 35 page plans", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  assert.equal(out.pagePlan.length, 35);
  out.pagePlan.forEach((p, i) => {
    assert.equal(p.page_number, i + 1);
    PagePlanSchema.parse(p);
  });
});

test("every page has at least one panel and panels validate", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  for (let page = 1; page <= 35; page++) {
    const pagePanels = out.panels.filter((p) => p.page_number === page);
    assert.ok(pagePanels.length >= 1, `page ${page} has no panels`);
  }
  out.panels.forEach((panel) => PanelSpecSchema.parse(panel));
});

test("page 1 is a single-panel hook and a turning point", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  const page1 = out.pagePlan[0]!;
  assert.equal(page1.page_number, 1);
  assert.equal(page1.panel_count, 1);
  assert.equal(page1.turning_point, true);
});

test("phase 9 (破滅) carries the lowest emotional value", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  const phase9 = out.phases.find((p) => p.phase_number === 9)!;
  assert.equal(phase9.phase_name, "破滅");
  const minEv = Math.min(...out.phases.map((p) => p.emotional_value));
  assert.equal(phase9.emotional_value, minEv);
});

test("phase 13 (満足) is the final satisfaction beat", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  const phase13 = out.phases.find((p) => p.phase_number === 13)!;
  assert.equal(phase13.phase_name, "満足");
  assert.ok(phase13.pages.includes(35));
  assert.equal(phase13.emotional_value, 3);
});

test("all top-level outputs pass Zod", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  ProjectSchema.parse(out.project);
  StoryBriefSchema.parse(out.brief);
});

test("safetyAgent blocks ONE PIECE風に描いて", () => {
  const verdict = checkSafety("ONE PIECE風に描いて");
  assert.equal(verdict.allowed, false);
  assert.ok(verdict.reason.length > 0);
});

test("safetyAgent blocks 鬼滅 and ○○先生風 and 'の絵柄で'", () => {
  assert.equal(checkSafety("鬼滅の刃みたいな話").allowed, false);
  assert.equal(checkSafety("尾田先生風のキャラで").allowed, false);
  assert.equal(checkSafety("有名作家の絵柄で描いて").allowed, false);
  assert.equal(checkSafety("in the style of Akira").allowed, false);
});

test("safetyAgent allows an original idea", () => {
  assert.equal(checkSafety(baseConfig.idea).allowed, true);
});

test("pipeline throws SafetyError for an infringing idea", async () => {
  await assert.rejects(
    () => runPipeline({ ...baseConfig, idea: "ONE PIECE風に描いて" }, new MockProvider()),
    SafetyError,
  );
});

test("pipeline is deterministic across runs", async () => {
  const a = await runPipeline(baseConfig, new MockProvider());
  const b = await runPipeline(baseConfig, new MockProvider());
  assert.deepEqual(a.pagePlan, b.pagePlan);
  assert.deepEqual(a.phases, b.phases);
  assert.deepEqual(a.panels, b.panels);
});

test("usage ledger records spend and estimates cost", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  assert.ok(out.ledger.all().length > 0);
  assert.ok(out.ledger.creditsSpent() > 0);
  assert.ok(out.ledger.totalEstimatedCostUsd() > 0);
});

test("default provider factory returns mock when AI_PROVIDER unset", () => {
  const prev = process.env.AI_PROVIDER;
  delete process.env.AI_PROVIDER;
  const p = createProvider();
  assert.equal(p.name, "mock");
  if (prev !== undefined) process.env.AI_PROVIDER = prev;
});

test("image prompts contain no real-IP references", async () => {
  const out = await runPipeline(baseConfig, new MockProvider());
  for (const panel of out.panels) {
    assert.equal(checkSafety(panel.image_prompt).allowed, true);
  }
});

test("works for a non-35 page count too (16 pages)", async () => {
  const out = await runPipeline({ ...baseConfig, page_count: 16 }, new MockProvider());
  assert.equal(out.pagePlan.length, 16);
  assert.equal(out.phases.length, 13);
  const allPages = out.phases.flatMap((p) => p.pages).sort((a, b) => a - b);
  assert.deepEqual(allPages, Array.from({ length: 16 }, (_, i) => i + 1));
});
