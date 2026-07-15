import {
  GenerationJobSchema,
  type GenerationJob,
  type PanelSpec,
} from "../schemas/index.js";
import { runPipeline, SafetyError } from "../pipeline.js";
import { createProvider } from "../providers/index.js";
import { CREDIT_COSTS } from "../billing/plans.js";
import { DataStore, newId, nowIso } from "../functions/store.js";

/**
 * Minimal in-memory async job runner.
 *
 * `generate-name` runs the full FABLE pipeline for a project; `generate-panel-image`
 * produces a deterministic MOCK rough placeholder for a single panel and charges
 * image credits via the shared usage ledger. Jobs are enqueued, return
 * immediately as { job_id, status: "queued" }, and run on a microtask so callers
 * can poll GET /jobs/:id.
 *
 * Determinism note: ids use randomUUID and timestamps use Date — that is fine
 * here (HTTP/store layer). Pipeline *content* (phases/pages/panels) stays
 * deterministic because runPipeline is fed a fixed `now`.
 */

export type JobType = "generate-name" | "generate-panel-image";

interface EnqueueNameInput {
  job_type: "generate-name";
  project_id: string;
  idea: string;
  page_count: number;
  format?: import("../schemas/index.js").Format;
  target_reader?: string;
  tone?: string[];
  title?: string;
  protagonist_name?: string;
}

interface EnqueuePanelImageInput {
  job_type: "generate-panel-image";
  project_id: string;
  panel: PanelSpec;
}

export type EnqueueInput = EnqueueNameInput | EnqueuePanelImageInput;

export interface PanelRoughResult {
  panel_id: string;
  image_kind: "rough_placeholder";
  width: number;
  height: number;
  data_uri: string;
}

/** Build a tiny inline-SVG placeholder data URI (NOT a real rendered image). */
export function roughPlaceholder(panel: PanelSpec): PanelRoughResult {
  const width = 768;
  const height = 1024;
  const label = `p${panel.page_number}-c${panel.panel_number} ${panel.shot}`;
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">` +
    `<rect width="100%" height="100%" fill="#eee" stroke="#333" stroke-width="4"/>` +
    `<text x="24" y="48" font-family="sans-serif" font-size="28" fill="#333">ROUGH</text>` +
    `<text x="24" y="88" font-family="sans-serif" font-size="20" fill="#555">${label}</text>` +
    `</svg>`;
  const data_uri = `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
  return {
    panel_id: `${panel.page_number}:${panel.panel_number}`,
    image_kind: "rough_placeholder",
    width,
    height,
    data_uri,
  };
}

export class JobRunner {
  constructor(private readonly store: DataStore) {}

  /** Create a queued job, schedule async work, return the queued job. */
  enqueue(input: EnqueueInput): GenerationJob {
    const job = GenerationJobSchema.parse({
      id: newId("job"),
      user_id: this.store.user_id,
      project_id: input.project_id,
      job_type: input.job_type,
      status: "queued",
      input: this.serializeInput(input),
      output: null,
      cost_estimate: 0,
      credits_used: 0,
      error: null,
      created_at: nowIso(),
      completed_at: null,
    });
    this.store.putJob(job);

    // Run asynchronously (do not await): callers poll GET /jobs/:id.
    queueMicrotask(() => {
      void this.run(job.id, input);
    });

    return job;
  }

  private serializeInput(input: EnqueueInput): unknown {
    if (input.job_type === "generate-panel-image") {
      return { job_type: input.job_type, panel_id: roughPlaceholder(input.panel).panel_id };
    }
    return { job_type: input.job_type, idea: input.idea, page_count: input.page_count };
  }

  private async run(jobId: string, input: EnqueueInput): Promise<void> {
    const job = this.store.getJob(jobId);
    if (!job) return;
    this.store.putJob({ ...job, status: "running" });

    try {
      if (input.job_type === "generate-name") {
        await this.runGenerateName(jobId, input);
      } else {
        this.runGeneratePanelImage(jobId, input);
      }
    } catch (e) {
      const message =
        e instanceof SafetyError
          ? e.reason
          : e instanceof Error
            ? e.message
            : String(e);
      const cur = this.store.getJob(jobId);
      if (cur) {
        this.store.putJob({
          ...cur,
          status: "failed",
          error: message,
          completed_at: nowIso(),
        });
      }
    }
  }

  private async runGenerateName(
    jobId: string,
    input: EnqueueNameInput,
  ): Promise<void> {
    const out = await runPipeline(
      {
        idea: input.idea,
        page_count: input.page_count,
        format: input.format,
        target_reader: input.target_reader,
        tone: input.tone,
        title: input.title,
        protagonist_name: input.protagonist_name,
        user_id: this.store.user_id,
        now: "2026-01-01T00:00:00.000Z",
      },
      createProvider(),
    );

    // Persist results onto the project record (keyed by the real project id).
    const rec = this.store.getProject(input.project_id);
    if (rec) {
      this.store.putProject({
        ...rec,
        project: {
          ...rec.project,
          status: "ready",
          page_count: input.page_count,
          updated_at: nowIso(),
        },
        brief: out.brief,
        genre: out.genre,
        phases: out.phases,
        pagePlan: out.pagePlan,
        panels: out.panels,
        critique: out.critique,
      });
    }

    // Fold the pipeline ledger into the shared store ledger (text = 0 net here
    // because grants offset spends per request scope; we mirror spends).
    for (const entry of out.ledger.all()) {
      this.store.ledger.record({
        user_id: entry.user_id,
        project_id: input.project_id,
        action: entry.action,
        model: entry.model,
        input_tokens: entry.input_tokens,
        output_tokens: entry.output_tokens,
        image_count: entry.image_count,
        credits_delta: entry.credits_delta,
        created_at: nowIso(),
      });
    }

    const result = {
      project_id: input.project_id,
      phase_count: out.phases.length,
      page_count: out.pagePlan.length,
      panel_count: out.panels.length,
      critique_score: out.critique.score,
    };

    const cur = this.store.getJob(jobId);
    if (cur) {
      this.store.putJob({
        ...cur,
        status: "succeeded",
        output: result,
        cost_estimate: out.ledger.totalEstimatedCostUsd(),
        credits_used: out.ledger.creditsSpent(),
        completed_at: nowIso(),
      });
    }
  }

  private runGeneratePanelImage(
    jobId: string,
    input: EnqueuePanelImageInput,
  ): void {
    const result = roughPlaceholder(input.panel);

    // Charge 1 image credit per panel rough (text stages are 0 credits).
    this.store.ledger.record({
      user_id: this.store.user_id,
      project_id: input.project_id,
      action: "generate_panel_image",
      model: "mock-image",
      image_count: 1,
      credits_delta: -CREDIT_COSTS.generate_image_prompt, // 1 credit per panel rough
      created_at: nowIso(),
    });

    const cur = this.store.getJob(jobId);
    if (cur) {
      this.store.putJob({
        ...cur,
        status: "succeeded",
        output: result,
        cost_estimate: 0,
        credits_used: 1,
        completed_at: nowIso(),
      });
    }
  }
}
