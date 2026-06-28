import {
  ProjectSchema,
  PipelineResultSchema,
  type Project,
  type PipelineResult,
  type Format,
  type PanelSpec,
  type Critique,
  type GenreVerdict,
} from "./schemas/index.js";
import type { AIProvider } from "./providers/types.js";
import { createProvider } from "./providers/index.js";
import {
  runIntake,
  runGenre,
  runPhases,
  runCharacter,
  runScene,
  runPagePlanner,
  runLayout,
  runDialogue,
  runVisualPrompt,
  runCritic,
  checkSafety,
} from "./agents/index.js";
import { UsageLedger } from "./usage/ledger.js";
import { CREDIT_COSTS } from "./billing/plans.js";

/**
 * FABLE pipeline orchestrator.
 *
 * Flow:  safety → genre → intake → character → phases → scene → page plan →
 *        per page: layout → dialogue → visual prompts → critique.
 */

export interface PipelineConfig {
  idea: string;
  page_count: number;
  format?: Format;
  target_reader?: string;
  tone?: string[];
  user_id?: string;
  title?: string;
  protagonist_name?: string;
  /** Fixed timestamp so output is fully deterministic. */
  now?: string;
}

export interface PipelineOutput extends PipelineResult {
  genre: GenreVerdict;
  critique: Critique;
  ledger: UsageLedger;
}

export class SafetyError extends Error {
  constructor(public reason: string) {
    super(`Request blocked by safety gate: ${reason}`);
    this.name = "SafetyError";
  }
}

export async function runPipeline(
  config: PipelineConfig,
  provider: AIProvider = createProvider(),
): Promise<PipelineOutput> {
  const now = config.now ?? "1970-01-01T00:00:00.000Z";
  const user_id = config.user_id ?? "demo-user";
  const format: Format = config.format ?? "manga";
  const target_reader = config.target_reader ?? "少年・青年";
  const tone = config.tone ?? ["エモーショナル", "冒険", "ノスタルジック"];
  const ledger = new UsageLedger();

  // 0) Safety gate — runs FIRST on the raw idea.
  const safety = checkSafety(config.idea);
  if (!safety.allowed) {
    throw new SafetyError(safety.reason);
  }

  const project_id = "proj_demo_0001";

  // 1) Genre classification.
  const genre = await runGenre(provider, {
    idea: config.idea,
    format,
    target_reader,
    tone,
  });
  ledger.record({
    user_id,
    project_id,
    action: "classify_genre",
    model: provider.name,
    input_tokens: 200,
    output_tokens: 120,
    credits_delta: -CREDIT_COSTS.classify_genre,
    created_at: now,
  });

  // 2) Intake → StoryBrief, then character refinement.
  let brief = runIntake({
    project_id,
    idea: config.idea,
    format,
    genre,
    protagonist_name: config.protagonist_name,
  });
  brief = runCharacter(brief);

  // 3) Project record.
  const project: Project = ProjectSchema.parse({
    id: project_id,
    user_id,
    title: config.title ?? config.idea.slice(0, 24),
    format,
    page_count: config.page_count,
    target_reader,
    tone,
    status: "ready",
    created_at: now,
    updated_at: now,
  });

  // 4) 13-phase structure, then scene sanity check.
  let phases = await runPhases(provider, brief, config.page_count);
  phases = runScene(phases);
  ledger.record({
    user_id,
    project_id,
    action: "generate_phases",
    model: provider.name,
    input_tokens: 400,
    output_tokens: 900,
    credits_delta: -CREDIT_COSTS.generate_phases,
    created_at: now,
  });

  // 5) Page plan.
  const pagePlan = await runPagePlanner(
    provider,
    brief,
    phases,
    config.page_count,
  );
  ledger.record({
    user_id,
    project_id,
    action: "generate_page_plan",
    model: provider.name,
    input_tokens: 800,
    output_tokens: 1800,
    credits_delta: -CREDIT_COSTS.generate_page_plan,
    created_at: now,
  });

  // 6) Per-page: layout → dialogue → visual prompts.
  const panels: PanelSpec[] = [];
  for (const page of pagePlan) {
    let pagePanels = await runLayout(provider, brief, page);
    ledger.record({
      user_id,
      project_id,
      action: "generate_layout",
      model: provider.name,
      input_tokens: 120,
      output_tokens: 200,
      credits_delta: -CREDIT_COSTS.generate_layout,
      created_at: now,
    });

    pagePanels = await runDialogue(provider, brief, page, pagePanels);
    ledger.record({
      user_id,
      project_id,
      action: "generate_dialogue",
      model: provider.name,
      input_tokens: 150,
      output_tokens: 180,
      credits_delta: -CREDIT_COSTS.generate_dialogue,
      created_at: now,
    });

    pagePanels = await runVisualPrompt(provider, brief, pagePanels);
    for (let i = 0; i < pagePanels.length; i++) {
      ledger.record({
        user_id,
        project_id,
        action: "generate_image_prompt",
        model: provider.name,
        input_tokens: 80,
        output_tokens: 90,
        credits_delta: -CREDIT_COSTS.generate_image_prompt,
        created_at: now,
      });
    }

    panels.push(...pagePanels);
  }

  // 7) Critique of the overall structure.
  const critique = await runCritic(provider, brief, phases, pagePlan);
  ledger.record({
    user_id,
    project_id,
    action: "critique",
    model: provider.name,
    input_tokens: 1200,
    output_tokens: 400,
    credits_delta: -CREDIT_COSTS.critique,
    created_at: now,
  });

  const result = PipelineResultSchema.parse({
    project,
    brief,
    phases,
    pagePlan,
    panels,
  });

  return { ...result, genre, critique, ledger };
}
