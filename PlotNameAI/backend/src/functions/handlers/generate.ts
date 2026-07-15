import {
  StoryBriefSchema,
  type StoryBrief,
  type Format,
} from "../../schemas/index.js";
import { type Req, type Res, ok, notFound, err, parseBody } from "../http.js";
import { DataStore, nowIso } from "../store.js";
import { ideaMap } from "./projects.js";
import { StoryBriefRequestSchema } from "../schemas.js";
import { createProvider } from "../../providers/index.js";
import {
  runIntake,
  runGenre,
  runCharacter,
  runPhases,
  runScene,
  runPagePlanner,
  runLayout,
  runDialogue,
  runVisualPrompt,
  runCritic,
  checkSafety,
} from "../../agents/index.js";
import { CREDIT_COSTS } from "../../billing/plans.js";

/**
 * Per-step generation handlers — thin orchestration over the existing agents.
 * Each generate endpoint runs the safetyAgent FIRST on the project's idea and
 * returns 422 on block. Pipeline content stays deterministic (fixed `now` /
 * deterministic mock provider); only ledger timestamps use Date.
 */

const PIPELINE_NOW = "2026-01-01T00:00:00.000Z";

/** Resolve the idea seed for a project (422 if blocked by safety). */
function safetyGate(store: DataStore, projectId: string): Res | { idea: string; protagonist_name?: string } {
  const seed = ideaMap.get(projectId);
  const idea = seed?.idea ?? "";
  const verdict = checkSafety(idea);
  if (!verdict.allowed) {
    return err(422, "safety_blocked", verdict.reason);
  }
  return { idea, protagonist_name: seed?.protagonist_name };
}

export function makeGenerateHandlers(store: DataStore) {
  const provider = createProvider();

  function requireProject(id: string) {
    return store.getProject(id);
  }

  async function storyBrief(req: Req): Promise<Res> {
    const id = req.params.id ?? "";
    const rec = requireProject(id);
    if (!rec) return notFound("Project not found");
    const safety = safetyGate(store, id);
    if ("status" in safety) return safety;

    const parsed = parseBody(StoryBriefRequestSchema, req.body);
    if (!parsed.ok) return parsed.res;

    // Classify genre first (intake needs a verdict), then build the brief.
    const genre = await runGenre(provider, {
      idea: safety.idea,
      format: rec.project.format,
      target_reader: rec.project.target_reader,
      tone: rec.project.tone,
    });
    let brief = runIntake({
      project_id: id,
      idea: safety.idea,
      format: rec.project.format,
      genre,
      protagonist_name: safety.protagonist_name,
    });
    brief = runCharacter(brief);
    // Apply any client overrides on top, re-validate.
    if (parsed.data) {
      brief = StoryBriefSchema.parse({ ...brief, ...parsed.data, project_id: id });
    }

    store.putProject({ ...rec, brief, genre });
    return ok(brief);
  }

  async function classifyGenre(req: Req): Promise<Res> {
    const id = req.params.id ?? "";
    const rec = requireProject(id);
    if (!rec) return notFound("Project not found");
    const safety = safetyGate(store, id);
    if ("status" in safety) return safety;

    const genre = await runGenre(provider, {
      idea: safety.idea,
      format: rec.project.format,
      target_reader: rec.project.target_reader,
      tone: rec.project.tone,
    });
    store.ledger.record({
      user_id: store.user_id,
      project_id: id,
      action: "classify_genre",
      model: provider.name,
      input_tokens: 200,
      output_tokens: 120,
      credits_delta: -CREDIT_COSTS.classify_genre,
      created_at: nowIso(),
    });
    store.putProject({ ...rec, genre });
    return ok(genre);
  }

  function requireBrief(store: DataStore, id: string): StoryBrief | Res {
    const rec = store.getProject(id);
    if (!rec) return notFound("Project not found");
    if (!rec.brief) {
      return err(409, "missing_brief", "Call POST /projects/:id/story-brief first.");
    }
    return rec.brief;
  }

  async function generatePhases(req: Req): Promise<Res> {
    const id = req.params.id ?? "";
    const safety = safetyGate(store, id);
    if ("status" in safety) return safety;
    const brief = requireBrief(store, id);
    if ("status" in brief) return brief;
    const rec = store.getProject(id)!;

    let phases = await runPhases(provider, brief, rec.project.page_count);
    phases = runScene(phases);
    store.ledger.record({
      user_id: store.user_id,
      project_id: id,
      action: "generate_phases",
      model: provider.name,
      input_tokens: 400,
      output_tokens: 900,
      credits_delta: -CREDIT_COSTS.generate_phases,
      created_at: nowIso(),
    });
    store.putProject({ ...rec, phases });
    return ok(phases);
  }

  async function generatePagePlan(req: Req): Promise<Res> {
    const id = req.params.id ?? "";
    const safety = safetyGate(store, id);
    if ("status" in safety) return safety;
    const brief = requireBrief(store, id);
    if ("status" in brief) return brief;
    const rec = store.getProject(id)!;
    if (!rec.phases) {
      return err(409, "missing_phases", "Call generate-phases first.");
    }

    const pagePlan = await runPagePlanner(
      provider,
      brief,
      rec.phases,
      rec.project.page_count,
    );
    store.ledger.record({
      user_id: store.user_id,
      project_id: id,
      action: "generate_page_plan",
      model: provider.name,
      input_tokens: 800,
      output_tokens: 1800,
      credits_delta: -CREDIT_COSTS.generate_page_plan,
      created_at: nowIso(),
    });
    store.putProject({ ...rec, pagePlan });
    return ok(pagePlan);
  }

  async function generateLayout(req: Req): Promise<Res> {
    const id = req.params.id ?? "";
    const safety = safetyGate(store, id);
    if ("status" in safety) return safety;
    const brief = requireBrief(store, id);
    if ("status" in brief) return brief;
    const rec = store.getProject(id)!;
    if (!rec.pagePlan) {
      return err(409, "missing_page_plan", "Call generate-page-plan first.");
    }

    const panels = [];
    for (const page of rec.pagePlan) {
      let pagePanels = await runLayout(provider, brief, page);
      store.ledger.record({
        user_id: store.user_id,
        project_id: id,
        action: "generate_layout",
        model: provider.name,
        input_tokens: 120,
        output_tokens: 200,
        credits_delta: -CREDIT_COSTS.generate_layout,
        created_at: nowIso(),
      });
      pagePanels = await runDialogue(provider, brief, page, pagePanels);
      store.ledger.record({
        user_id: store.user_id,
        project_id: id,
        action: "generate_dialogue",
        model: provider.name,
        input_tokens: 150,
        output_tokens: 180,
        credits_delta: -CREDIT_COSTS.generate_dialogue,
        created_at: nowIso(),
      });
      pagePanels = await runVisualPrompt(provider, brief, pagePanels);
      panels.push(...pagePanels);
    }
    store.putProject({ ...rec, panels });
    return ok(panels);
  }

  async function critique(req: Req): Promise<Res> {
    const id = req.params.id ?? "";
    const safety = safetyGate(store, id);
    if ("status" in safety) return safety;
    const brief = requireBrief(store, id);
    if ("status" in brief) return brief;
    const rec = store.getProject(id)!;
    if (!rec.phases || !rec.pagePlan) {
      return err(409, "missing_structure", "Generate phases + page plan first.");
    }

    const result = await runCritic(provider, brief, rec.phases, rec.pagePlan);
    store.ledger.record({
      user_id: store.user_id,
      project_id: id,
      action: "critique",
      model: provider.name,
      input_tokens: 1200,
      output_tokens: 400,
      credits_delta: -CREDIT_COSTS.critique,
      created_at: nowIso(),
    });
    store.putProject({ ...rec, critique: result });
    return ok(result);
  }

  return {
    storyBrief,
    classifyGenre,
    generatePhases,
    generatePagePlan,
    generateLayout,
    critique,
  };
}

export type { Format };
