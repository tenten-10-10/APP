import { type Req, type Res, type Handler, notFound, err } from "./http.js";
import { DataStore, store as defaultStore } from "./store.js";
import { JobRunner } from "../jobs/index.js";
import { makeProjectHandlers } from "./handlers/projects.js";
import { makeGenerateHandlers } from "./handlers/generate.js";
import { makeMiscHandlers } from "./handlers/misc.js";

/**
 * Tiny method+path router. Patterns support `:param` segments (e.g.
 * `/projects/:id/pages/:pageNumber`). The first matching route wins; an
 * unknown route yields 404 and an uncaught handler error yields 500.
 */

interface Route {
  method: string;
  pattern: string;
  segments: string[];
  handler: Handler;
}

function splitPath(path: string): string[] {
  return path.replace(/^\/+|\/+$/g, "").split("/").filter((s) => s.length > 0);
}

export class Router {
  private routes: Route[] = [];

  add(method: string, pattern: string, handler: Handler): this {
    this.routes.push({
      method: method.toUpperCase(),
      pattern,
      segments: splitPath(pattern),
      handler,
    });
    return this;
  }

  /** Match a method+path, extracting `:param` values. */
  match(
    method: string,
    path: string,
  ): { handler: Handler; params: Record<string, string> } | undefined {
    const reqSegs = splitPath(path);
    for (const route of this.routes) {
      if (route.method !== method.toUpperCase()) continue;
      if (route.segments.length !== reqSegs.length) continue;
      const params: Record<string, string> = {};
      let matched = true;
      for (let i = 0; i < route.segments.length; i++) {
        const seg = route.segments[i]!;
        const val = reqSegs[i]!;
        if (seg.startsWith(":")) {
          params[seg.slice(1)] = decodeURIComponent(val);
        } else if (seg !== val) {
          matched = false;
          break;
        }
      }
      if (matched) return { handler: route.handler, params };
    }
    return undefined;
  }

  async dispatch(req: Omit<Req, "params"> & { params?: Record<string, string> }): Promise<Res> {
    const found = this.match(req.method, req.path);
    if (!found) return notFound(`No route for ${req.method} ${req.path}`);
    const fullReq: Req = {
      method: req.method,
      path: req.path,
      query: req.query ?? {},
      body: req.body,
      params: { ...(req.params ?? {}), ...found.params },
    };
    try {
      return await found.handler(fullReq);
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      return err(500, "internal_error", message);
    }
  }
}

/** Build a router wired to a given store (defaults to the shared singleton). */
export function createRouter(store: DataStore = defaultStore): Router {
  const jobs = new JobRunner(store);
  const projects = makeProjectHandlers(store);
  const gen = makeGenerateHandlers(store);
  const misc = makeMiscHandlers(store, jobs);

  const r = new Router();

  // Projects CRUD
  r.add("POST", "/projects", projects.createProject);
  r.add("GET", "/projects", projects.listProjects);
  r.add("GET", "/projects/:id", projects.getProject);
  r.add("PATCH", "/projects/:id", projects.updateProject);
  r.add("DELETE", "/projects/:id", projects.deleteProject);

  // Generation (per-step)
  r.add("POST", "/projects/:id/story-brief", gen.storyBrief);
  r.add("POST", "/projects/:id/classify-genre", gen.classifyGenre);
  r.add("POST", "/projects/:id/generate-phases", gen.generatePhases);
  r.add("POST", "/projects/:id/generate-page-plan", gen.generatePagePlan);
  r.add("POST", "/projects/:id/generate-layout", gen.generateLayout);
  r.add("POST", "/projects/:id/critique", gen.critique);

  // Async generation jobs
  r.add("POST", "/projects/:id/generate-name", misc.generateName);
  r.add("POST", "/projects/:id/generate-panel-image", misc.generatePanelImage);
  r.add("GET", "/jobs/:id", misc.getJob);

  // Pages / panels
  r.add("GET", "/projects/:id/pages", misc.getPages);
  r.add("PATCH", "/projects/:id/pages/:pageNumber", misc.patchPage);
  r.add("PATCH", "/projects/:id/panels/:panelId", misc.patchPanel);

  // Billing / usage / ads / exports
  r.add("GET", "/billing/entitlements", misc.getEntitlements);
  r.add("GET", "/usage", misc.getUsage);
  r.add("POST", "/ads/reward", misc.adsReward);
  r.add("POST", "/exports/project-json", misc.exportProjectJson);

  return r;
}
