import {
  PagePlanSchema,
  PanelSpecSchema,
  type PanelSpec,
} from "../../schemas/index.js";
import { type Req, type Res, ok, notFound, err, parseBody } from "../http.js";
import { DataStore, nowIso } from "../store.js";
import { ideaMap } from "./projects.js";
import {
  UpdatePageRequestSchema,
  UpdatePanelRequestSchema,
  AdsRewardRequestSchema,
  GeneratePanelImageRequestSchema,
} from "../schemas.js";
import { resolveEntitlement } from "../../billing/entitlements.js";
import { checkSafety } from "../../agents/index.js";
import { JobRunner } from "../../jobs/index.js";

/**
 * Pages/panels reads + edits, billing/usage, ads reward, exports, and the
 * async job endpoints (generate-name, generate-panel-image, GET /jobs/:id).
 */

export function makeMiscHandlers(store: DataStore, jobs: JobRunner) {
  // ---- Pages / panels ----------------------------------------------------

  function getPages(req: Req): Res {
    const rec = store.getProject(req.params.id ?? "");
    if (!rec) return notFound("Project not found");
    return ok({
      pagePlan: rec.pagePlan ?? [],
      panels: rec.panels ?? [],
    });
  }

  function patchPage(req: Req): Res {
    const rec = store.getProject(req.params.id ?? "");
    if (!rec) return notFound("Project not found");
    if (!rec.pagePlan) return err(409, "missing_page_plan", "No page plan yet.");
    const n = Number(req.params.pageNumber);
    if (!Number.isInteger(n)) return err(400, "invalid_body", "pageNumber must be an integer.");
    const idx = rec.pagePlan.findIndex((p) => p.page_number === n);
    if (idx === -1) return notFound(`Page ${n} not found`);

    const parsed = parseBody(UpdatePageRequestSchema, req.body);
    if (!parsed.ok) return parsed.res;

    const updated = PagePlanSchema.parse({
      ...rec.pagePlan[idx],
      ...parsed.data,
      page_number: n,
    });
    const pagePlan = [...rec.pagePlan];
    pagePlan[idx] = updated;
    store.putProject({ ...rec, pagePlan });
    return ok(updated);
  }

  function patchPanel(req: Req): Res {
    const rec = store.getProject(req.params.id ?? "");
    if (!rec) return notFound("Project not found");
    if (!rec.panels) return err(409, "missing_panels", "No panels yet.");
    const panelId = req.params.panelId ?? "";
    const [pageStr, panelStr] = panelId.split(":");
    const page = Number(pageStr);
    const panel = Number(panelStr);
    const idx = rec.panels.findIndex(
      (p) => p.page_number === page && p.panel_number === panel,
    );
    if (idx === -1) return notFound(`Panel ${panelId} not found`);

    const parsed = parseBody(UpdatePanelRequestSchema, req.body);
    if (!parsed.ok) return parsed.res;

    // Re-check any edited image_prompt against the safety gate.
    if (typeof parsed.data.image_prompt === "string") {
      const v = checkSafety(parsed.data.image_prompt);
      if (!v.allowed) return err(422, "safety_blocked", v.reason);
    }

    const updated: PanelSpec = PanelSpecSchema.parse({
      ...rec.panels[idx],
      ...parsed.data,
      page_number: page,
      panel_number: panel,
    });
    const panels = [...rec.panels];
    panels[idx] = updated;
    store.putProject({ ...rec, panels });
    return ok(updated);
  }

  // ---- Billing / usage ---------------------------------------------------

  function getEntitlements(_req: Req): Res {
    return ok(resolveEntitlement(store.plan));
  }

  function getUsage(_req: Req): Res {
    return ok({
      plan: store.plan,
      monthly_credits: resolveEntitlement(store.plan).limits.monthly_credits,
      credits_spent: store.ledger.creditsSpent(),
      credits_balance: store.ledger.creditsBalance(),
      estimated_cost_usd: store.ledger.totalEstimatedCostUsd(),
      entries: store.ledger.all(),
    });
  }

  function adsReward(req: Req): Res {
    const parsed = parseBody(AdsRewardRequestSchema, req.body);
    if (!parsed.ok) return parsed.res;
    const balanceBefore = store.ledger.creditsBalance();
    store.ledger.record({
      user_id: store.user_id,
      project_id: parsed.data.project_id ?? "account",
      action: "ad_reward",
      model: "admob",
      credits_delta: parsed.data.credits, // positive grant
      created_at: nowIso(),
    });
    return ok({
      granted: parsed.data.credits,
      credits_balance: store.ledger.creditsBalance(),
      previous_balance: balanceBefore,
    });
  }

  // ---- Exports -----------------------------------------------------------

  function exportProjectJson(req: Req): Res {
    const id =
      req.params.id ??
      (typeof req.body === "object" && req.body !== null
        ? (req.body as { project_id?: string }).project_id
        : undefined) ??
      (req.query.project_id ?? "");
    const rec = store.getProject(id);
    if (!rec) return notFound("Project not found");
    const bundle = {
      project: rec.project,
      brief: rec.brief ?? null,
      genre: rec.genre ?? null,
      phases: rec.phases ?? [],
      pagePlan: rec.pagePlan ?? [],
      panels: rec.panels ?? [],
      critique: rec.critique ?? null,
      exported_at: nowIso(),
    };
    return ok(bundle);
  }

  // ---- Async jobs --------------------------------------------------------

  function generateName(req: Req): Res {
    const id = req.params.id ?? "";
    const rec = store.getProject(id);
    if (!rec) return notFound("Project not found");
    const seed = ideaMap.get(id);
    const idea = seed?.idea ?? "";
    const v = checkSafety(idea);
    if (!v.allowed) return err(422, "safety_blocked", v.reason);

    const job = jobs.enqueue({
      job_type: "generate-name",
      project_id: id,
      idea,
      page_count: rec.project.page_count,
      format: rec.project.format,
      target_reader: rec.project.target_reader,
      tone: rec.project.tone,
      title: rec.project.title,
      protagonist_name: seed?.protagonist_name,
    });
    return ok({ job_id: job.id, status: job.status }, 202);
  }

  function generatePanelImage(req: Req): Res {
    const id = req.params.id ?? "";
    const rec = store.getProject(id);
    if (!rec) return notFound("Project not found");
    if (!resolveEntitlement(store.plan).features.image_generation) {
      return err(403, "feature_locked", `Plan "${store.plan}" has no image generation.`);
    }
    const parsed = parseBody(GeneratePanelImageRequestSchema, req.body);
    if (!parsed.ok) return parsed.res;

    const [pageStr, panelStr] = parsed.data.panel_id.split(":");
    const page = Number(pageStr);
    const panelNum = Number(panelStr);
    const panel = rec.panels?.find(
      (p) => p.page_number === page && p.panel_number === panelNum,
    );
    if (!panel) return notFound(`Panel ${parsed.data.panel_id} not found`);

    // Safety re-check on the prompt that would drive the image.
    const v = checkSafety(panel.image_prompt);
    if (!v.allowed) return err(422, "safety_blocked", v.reason);

    const job = jobs.enqueue({
      job_type: "generate-panel-image",
      project_id: id,
      panel,
    });
    return ok({ job_id: job.id, status: job.status }, 202);
  }

  function getJob(req: Req): Res {
    const job = store.getJob(req.params.id ?? "");
    if (!job) return notFound("Job not found");
    return ok(job);
  }

  return {
    getPages,
    patchPage,
    patchPanel,
    getEntitlements,
    getUsage,
    adsReward,
    exportProjectJson,
    generateName,
    generatePanelImage,
    getJob,
  };
}
