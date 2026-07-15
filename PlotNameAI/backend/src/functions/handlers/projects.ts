import {
  ProjectSchema,
  type Project,
} from "../../schemas/index.js";
import { type Req, type Res, ok, created, notFound, err, parseBody } from "../http.js";
import {
  CreateProjectRequestSchema,
  UpdateProjectRequestSchema,
} from "../schemas.js";
import { DataStore, newId, nowIso } from "../store.js";
import { checkPageLimit, checkProjectLimit } from "../../billing/entitlements.js";

/**
 * Projects CRUD. The original `idea` is kept on the project record (in title +
 * brief logline) so later generate steps can re-run the pipeline.
 */

export function makeProjectHandlers(store: DataStore) {
  function createProject(req: Req): Res {
    const parsed = parseBody(CreateProjectRequestSchema, req.body);
    if (!parsed.ok) return parsed.res;
    const data = parsed.data;

    const projectLimit = checkProjectLimit(store.plan, store.projects.size);
    if (!projectLimit.ok) {
      return err(403, "project_limit", projectLimit.reason);
    }
    const pageLimit = checkPageLimit(store.plan, data.page_count);
    if (!pageLimit.ok) {
      return err(403, "page_limit", pageLimit.reason);
    }

    const ts = nowIso();
    const project: Project = ProjectSchema.parse({
      id: newId("proj"),
      user_id: store.user_id,
      title: data.title,
      format: data.format,
      page_count: data.page_count,
      target_reader: data.target_reader,
      tone: data.tone,
      status: "draft",
      created_at: ts,
      updated_at: ts,
    });

    store.putProject({
      project,
      // Stash the raw idea + protagonist for later generation steps.
      brief: undefined,
    });
    // Keep idea/protagonist on the record via a side map on the project store.
    ideaMap.set(project.id, {
      idea: data.idea,
      protagonist_name: data.protagonist_name,
    });

    return created(project);
  }

  function listProjects(_req: Req): Res {
    return ok(store.listProjects().map((r) => r.project));
  }

  function getProject(req: Req): Res {
    const rec = store.getProject(req.params.id ?? "");
    if (!rec) return notFound("Project not found");
    return ok({
      ...rec.project,
      brief: rec.brief ?? null,
      genre: rec.genre ?? null,
      phases: rec.phases ?? null,
      pagePlan: rec.pagePlan ?? null,
      panels: rec.panels ?? null,
      critique: rec.critique ?? null,
    });
  }

  function updateProject(req: Req): Res {
    const rec = store.getProject(req.params.id ?? "");
    if (!rec) return notFound("Project not found");
    const parsed = parseBody(UpdateProjectRequestSchema, req.body);
    if (!parsed.ok) return parsed.res;

    if (parsed.data.page_count !== undefined) {
      const pageLimit = checkPageLimit(store.plan, parsed.data.page_count);
      if (!pageLimit.ok) return err(403, "page_limit", pageLimit.reason);
    }

    const next: Project = ProjectSchema.parse({
      ...rec.project,
      ...parsed.data,
      updated_at: nowIso(),
    });
    store.putProject({ ...rec, project: next });
    return ok(next);
  }

  function deleteProject(req: Req): Res {
    const id = req.params.id ?? "";
    if (!store.getProject(id)) return notFound("Project not found");
    store.deleteProject(id);
    ideaMap.delete(id);
    return ok({ deleted: true, id });
  }

  return {
    createProject,
    listProjects,
    getProject,
    updateProject,
    deleteProject,
  };
}

/** Side store for the raw idea/protagonist used to seed generation. */
export const ideaMap = new Map<
  string,
  { idea: string; protagonist_name?: string }
>();
