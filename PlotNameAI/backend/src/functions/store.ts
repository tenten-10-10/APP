import { randomUUID } from "node:crypto";
import type {
  Project,
  StoryBrief,
  PhaseCard,
  PagePlan,
  PanelSpec,
  GenerationJob,
  GenreVerdict,
  Critique,
} from "../schemas/index.js";
import { UsageLedger } from "../usage/ledger.js";

/**
 * In-memory data store for the REST scaffold (no DB).
 *
 * Holds projects/briefs/phases/pages/panels/jobs keyed by id, plus a single
 * shared usage ledger (credits + cost estimates). `randomUUID` is used for ids
 * — this is the HTTP/store layer, NOT the deterministic pipeline ordering
 * logic. Timestamps come from `new Date().toISOString()`, which is acceptable
 * here (never inside pipeline output that tests assert on).
 */

export interface ProjectRecord {
  project: Project;
  brief?: StoryBrief;
  genre?: GenreVerdict;
  phases?: PhaseCard[];
  pagePlan?: PagePlan[];
  panels?: PanelSpec[];
  critique?: Critique;
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function newId(prefix: string): string {
  return `${prefix}_${randomUUID()}`;
}

export class DataStore {
  readonly projects = new Map<string, ProjectRecord>();
  readonly jobs = new Map<string, GenerationJob>();
  /** Shared usage ledger across all requests in this process. */
  readonly ledger = new UsageLedger();
  /** Plan for the (single, demo) user — drives entitlements/limits. */
  plan: "free" | "plus" | "pro" | "studio" = "plus";
  readonly user_id = "demo-user";

  getProject(id: string): ProjectRecord | undefined {
    return this.projects.get(id);
  }

  listProjects(): ProjectRecord[] {
    return [...this.projects.values()];
  }

  putProject(rec: ProjectRecord): ProjectRecord {
    this.projects.set(rec.project.id, rec);
    return rec;
  }

  deleteProject(id: string): boolean {
    return this.projects.delete(id);
  }

  getJob(id: string): GenerationJob | undefined {
    return this.jobs.get(id);
  }

  putJob(job: GenerationJob): GenerationJob {
    this.jobs.set(job.id, job);
    return job;
  }
}

/** Default singleton store used by the router/handlers and dev server. */
export const store = new DataStore();
