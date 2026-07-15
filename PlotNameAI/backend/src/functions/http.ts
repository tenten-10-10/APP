import { z } from "zod";

/**
 * Framework-agnostic request/response shapes for the REST handler layer.
 * No web framework is pulled in — `server.ts` (optional) adapts node:http to
 * these, and tests call handlers/router directly.
 */

export interface Req {
  method: string;
  path: string;
  params: Record<string, string>;
  query: Record<string, string>;
  body: unknown;
}

export interface Res {
  status: number;
  body: unknown;
}

export type Handler = (req: Req) => Promise<Res> | Res;

export interface ApiError {
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

export function ok(body: unknown, status = 200): Res {
  return { status, body };
}

export function created(body: unknown): Res {
  return { status: 201, body };
}

export function err(
  status: number,
  code: string,
  message: string,
  details?: unknown,
): Res {
  const body: ApiError = { error: { code, message, details } };
  return { status, body };
}

export function notFound(message = "Not found"): Res {
  return err(404, "not_found", message);
}

/**
 * Validate a request body against a Zod schema. Returns the parsed value or a
 * typed 400 response.
 */
export function parseBody<T extends z.ZodTypeAny>(
  schema: T,
  body: unknown,
):
  | { ok: true; data: z.infer<T> }
  | { ok: false; res: Res } {
  const result = schema.safeParse(body);
  if (!result.success) {
    return {
      ok: false,
      res: err(
        400,
        "invalid_body",
        "Request body failed validation.",
        result.error.flatten(),
      ),
    };
  }
  return { ok: true, data: result.data };
}
