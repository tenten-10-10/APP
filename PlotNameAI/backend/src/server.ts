import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createRouter } from "./functions/router.js";

/**
 * Optional dev server (no new deps): adapts node:http to the framework-agnostic
 * router. NOT used by tests. Run with `npm run serve`.
 *
 *   npm run serve
 *   curl -s localhost:8787/billing/entitlements
 */

const router = createRouter();
const PORT = Number(process.env.PORT ?? 8787);

function readBody(req: IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (c) => chunks.push(c as Buffer));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

const server = createServer(async (req: IncomingMessage, res: ServerResponse) => {
  try {
    const method = req.method ?? "GET";
    const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
    const query: Record<string, string> = {};
    url.searchParams.forEach((v, k) => {
      query[k] = v;
    });

    let body: unknown = undefined;
    if (method !== "GET" && method !== "DELETE") {
      const raw = await readBody(req);
      if (raw.length > 0) {
        try {
          body = JSON.parse(raw);
        } catch {
          res.writeHead(400, { "content-type": "application/json" });
          res.end(JSON.stringify({ error: { code: "invalid_json", message: "Body is not valid JSON." } }));
          return;
        }
      }
    }

    const result = await router.dispatch({
      method,
      path: url.pathname,
      query,
      body,
    });

    res.writeHead(result.status, { "content-type": "application/json" });
    res.end(JSON.stringify(result.body));
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    res.writeHead(500, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: { code: "internal_error", message } }));
  }
});

server.listen(PORT, () => {
  console.log(`PlotName AI dev server listening on http://localhost:${PORT}`);
});
