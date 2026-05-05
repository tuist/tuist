import { Hono } from "hono";
import { fakeStatus } from "./fake-data.js";
import { fetchRawFields, fetchRawIncidents, fetchStatusFromGrafana } from "./grafana-irm.js";
import type { Env, StatusSnapshot } from "./types.js";
import { atomFeed, rssFeed } from "./views/feed.js";
import { faviconSvg } from "./views/logo.js";
import { statusPage } from "./views/page.js";

const app = new Hono<{ Bindings: Env }>();

async function loadSnapshot(env: Env): Promise<StatusSnapshot> {
  if (env.USE_FAKE_DATA === "true") return fakeStatus();
  return fetchStatusFromGrafana(env);
}

function baseUrlFrom(req: Request): string {
  const url = new URL(req.url);
  return `${url.protocol}//${url.host}`;
}

app.get("/", async (c) => {
  const snapshot = await loadSnapshot(c.env);
  return c.html(statusPage({ title: c.env.STATUS_PAGE_TITLE, snapshot }));
});

app.get("/api/status.json", async (c) => {
  const snapshot = await loadSnapshot(c.env);
  return c.json(snapshot);
});

// Debug routes return the raw upstream Grafana responses (incidents and label
// fields) for diagnosing field-name drift and missing components. They expose
// internal-only metadata so they're gated behind ENABLE_DEBUG_ROUTES, which is
// unset in production and only enabled locally via .dev.vars.
function debugRoutesEnabled(env: Env): boolean {
  return env.ENABLE_DEBUG_ROUTES === "true";
}

app.get("/api/debug/incidents.json", async (c) => {
  if (!debugRoutesEnabled(c.env)) return c.notFound();
  if (c.env.USE_FAKE_DATA === "true") {
    return c.json({ error: "USE_FAKE_DATA is true; nothing to debug" }, 400);
  }
  const raw = await fetchRawIncidents(c.env);
  return c.json(raw);
});

app.get("/api/debug/fields.json", async (c) => {
  if (!debugRoutesEnabled(c.env)) return c.notFound();
  if (c.env.USE_FAKE_DATA === "true") {
    return c.json({ error: "USE_FAKE_DATA is true; nothing to debug" }, 400);
  }
  const raw = await fetchRawFields(c.env);
  return c.json({
    configuredLabelKey: c.env.GRAFANA_COMPONENT_LABEL_KEY,
    fields: raw,
  });
});

app.get("/feed.rss", async (c) => {
  const snapshot = await loadSnapshot(c.env);
  const xml = rssFeed({
    title: c.env.STATUS_PAGE_TITLE,
    baseUrl: baseUrlFrom(c.req.raw),
    snapshot,
  });
  return c.body(xml, 200, {
    "Content-Type": "application/rss+xml; charset=utf-8",
    "Cache-Control": "public, max-age=60",
  });
});

app.get("/feed.atom", async (c) => {
  const snapshot = await loadSnapshot(c.env);
  const xml = atomFeed({
    title: c.env.STATUS_PAGE_TITLE,
    baseUrl: baseUrlFrom(c.req.raw),
    snapshot,
  });
  return c.body(xml, 200, {
    "Content-Type": "application/atom+xml; charset=utf-8",
    "Cache-Control": "public, max-age=60",
  });
});

app.get("/favicon.svg", (c) =>
  c.body(faviconSvg(), 200, {
    "Content-Type": "image/svg+xml; charset=utf-8",
    "Cache-Control": "public, max-age=86400, immutable",
  }),
);

app.get("/favicon.ico", (c) => c.body(null, 204));

app.get("/healthz", (c) => c.text("ok"));

export default app;
