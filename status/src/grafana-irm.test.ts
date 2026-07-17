import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fetchStatusFromGrafana } from "./grafana-irm.js";

const ENV = {
  GRAFANA_INCIDENT_API_URL: "https://tuist.grafana.net/api/plugins/grafana-irm-app/resources",
  GRAFANA_INCIDENT_API_TOKEN: "glsa_test",
  GRAFANA_COMPONENT_LABEL_KEY: "affected_service",
};

const NOW = new Date("2026-05-05T12:00:00.000Z");

interface MockCall {
  url: string;
  method: string;
  headers: Record<string, string>;
  body: unknown;
}

function installFetchMock(responses: Map<string, unknown>): MockCall[] {
  const calls: MockCall[] = [];
  globalThis.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    const method = init?.method ?? "GET";
    const headers = init?.headers as Record<string, string>;
    const body = typeof init?.body === "string" ? JSON.parse(init.body) : undefined;
    calls.push({ url, method, headers, body });
    const path = url.split("/api/v1/")[1] ?? "";
    const payload = responses.get(path);
    if (!payload) {
      throw new Error(`unmocked path: ${path}`);
    }
    return new Response(JSON.stringify(payload), { status: 200 });
  }) as typeof fetch;
  return calls;
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(NOW);
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("fetchStatusFromGrafana", () => {
  it("throws when the token is missing", async () => {
    await expect(
      fetchStatusFromGrafana({
        GRAFANA_INCIDENT_API_URL: ENV.GRAFANA_INCIDENT_API_URL,
        GRAFANA_COMPONENT_LABEL_KEY: ENV.GRAFANA_COMPONENT_LABEL_KEY,
      }),
    ).rejects.toThrow(/GRAFANA_INCIDENT_API_TOKEN/);
  });

  it("issues three POST RPCs with bearer auth and the right query strings", async () => {
    const calls = installFetchMock(
      new Map<string, unknown>([
        ["FieldsService.GetFields", { fields: [] }],
        ["IncidentsService.QueryIncidents", { incidents: [] }],
      ]),
    );
    await fetchStatusFromGrafana(ENV);

    expect(calls).toHaveLength(3);
    for (const call of calls) {
      expect(call.method).toBe("POST");
      expect(call.headers.Authorization).toBe("Bearer glsa_test");
      expect(call.headers["Content-Type"]).toBe("application/json; charset=utf-8");
      expect(call.url.startsWith(ENV.GRAFANA_INCIDENT_API_URL + "/api/v1/")).toBe(true);
    }

    const fields = calls.find((c) => c.url.endsWith("FieldsService.GetFields"));
    expect(fields?.body).toEqual({ domainName: "labels" });

    const incidentCalls = calls.filter((c) => c.url.endsWith("IncidentsService.QueryIncidents"));
    expect(incidentCalls).toHaveLength(2);
    const queries = incidentCalls.map((c) => (c.body as { query: { queryString: string } }).query.queryString).sort();
    expect(queries).toEqual(["isdrill:false status:active", "isdrill:false status:resolved"]);
  });

  it("rejects when the API returns a non-2xx status", async () => {
    globalThis.fetch = vi.fn(
      async () => new Response(JSON.stringify({ error: "bad query" }), { status: 400 }),
    ) as typeof fetch;
    await expect(fetchStatusFromGrafana(ENV)).rejects.toThrow(/returned 400/);
  });

  it("derives components from the configured label field's select options", async () => {
    installFetchMock(
      new Map<string, unknown>([
        [
          "FieldsService.GetFields",
          {
            fields: [
              { name: "team", selectoptions: [{ value: "platform" }] },
              {
                name: "affected_service",
                selectoptions: [
                  { value: "cli", description: "Command-line workflows." },
                  { value: "cache", label: "Binary Cache", description: "Remote build cache." },
                ],
              },
            ],
          },
        ],
        ["IncidentsService.QueryIncidents", { incidents: [] }],
      ]),
    );

    const snapshot = await fetchStatusFromGrafana(ENV);

    expect(snapshot.components).toEqual([
      { id: "cli", name: "cli", description: "Command-line workflows.", status: "operational" },
      { id: "cache", name: "Binary Cache", description: "Remote build cache.", status: "operational" },
    ]);
    expect(snapshot.overall).toBe("operational");
  });

  it("returns no components when the configured label field is absent", async () => {
    installFetchMock(
      new Map<string, unknown>([
        ["FieldsService.GetFields", { fields: [{ name: "team", selectoptions: [{ value: "platform" }] }] }],
        ["IncidentsService.QueryIncidents", { incidents: [] }],
      ]),
    );
    const snapshot = await fetchStatusFromGrafana(ENV);
    expect(snapshot.components).toEqual([]);
  });

  it("rolls up the worst severity per affected component", async () => {
    let call = 0;
    globalThis.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.endsWith("FieldsService.GetFields")) {
        return new Response(
          JSON.stringify({
            fields: [
              {
                name: "affected_service",
                selectoptions: [{ value: "cache" }, { value: "api" }],
              },
            ],
          }),
        );
      }
      // First QueryIncidents → active; second → resolved
      const isActive = (typeof init?.body === "string" ? init.body : "").includes("status:active");
      const incidents = isActive
        ? [
            {
              incidentID: "inc-a",
              title: "Cache slow",
              severity: "minor",
              status: "active",
              createdTime: "2026-05-05T11:00:00.000Z",
              labels: [{ label: { key: "affected_service", value: "cache" } }],
            },
            {
              incidentID: "inc-b",
              title: "Cache outage",
              severity: "critical",
              status: "active",
              createdTime: "2026-05-05T11:30:00.000Z",
              labels: [{ label: { key: "affected_service", value: "cache" } }],
            },
          ]
        : [];
      call++;
      return new Response(JSON.stringify({ incidents }));
    }) as typeof fetch;

    const snapshot = await fetchStatusFromGrafana(ENV);
    const cache = snapshot.components.find((c) => c.id === "cache")!;
    const api = snapshot.components.find((c) => c.id === "api")!;
    expect(cache.status).toBe("major_outage"); // critical wins over minor
    expect(api.status).toBe("operational");
    expect(snapshot.overall).toBe("major_outage");
    expect(call).toBeGreaterThan(0);
  });

  it("filters resolved incidents to the last 14 days", async () => {
    installFetchMock(
      new Map<string, unknown>([
        ["FieldsService.GetFields", { fields: [{ name: "affected_service", selectoptions: [{ value: "cache" }] }] }],
        ["IncidentsService.QueryIncidents", { incidents: [] }],
      ]),
    );

    // The mock above returns no incidents for either call. Now override fetch to return
    // a resolved-incident list with one fresh and one stale entry on the resolved call.
    globalThis.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.endsWith("FieldsService.GetFields")) {
        return new Response(
          JSON.stringify({ fields: [{ name: "affected_service", selectoptions: [{ value: "cache" }] }] }),
        );
      }
      const isActive = (typeof init?.body === "string" ? init.body : "").includes("status:active");
      if (isActive) return new Response(JSON.stringify({ incidents: [] }));
      return new Response(
        JSON.stringify({
          incidents: [
            {
              incidentID: "fresh",
              title: "Recent",
              status: "resolved",
              closedTime: "2026-04-30T00:00:00.000Z", // 5 days ago, within 14
            },
            {
              incidentID: "stale",
              title: "Old",
              status: "resolved",
              closedTime: "2026-04-10T00:00:00.000Z", // 25 days ago, outside 14
            },
          ],
        }),
      );
    }) as typeof fetch;

    const snapshot = await fetchStatusFromGrafana(ENV);
    expect(snapshot.recentIncidents.map((i) => i.id)).toEqual(["fresh"]);
  });

  it("loads every key update for an incident and uses its summary as a fallback", async () => {
    const keyUpdateBodies: Array<Record<string, unknown>> = [];
    let keyUpdatePage = 0;
    globalThis.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input.toString();
      const body = typeof init?.body === "string" ? JSON.parse(init.body) : {};
      if (url.endsWith("FieldsService.GetFields")) {
        return new Response(JSON.stringify({ fields: [] }));
      }
      if (url.endsWith("IncidentsService.QueryIncidents")) {
        const isActive = JSON.stringify(body).includes("status:active");
        return new Response(
          JSON.stringify({
            incidents: isActive
              ? [
                  {
                    incidentID: "with-updates",
                    title: "Cache unavailable",
                    status: "active",
                    summary: "This is replaced by the key updates.",
                    createdTime: "2026-05-05T10:00:00.000Z",
                  },
                  {
                    incidentID: "with-summary",
                    title: "Cache slow",
                    status: "active",
                    summary: "We are investigating elevated latency.",
                    createdTime: "2026-05-05T11:00:00.000Z",
                  },
                ]
              : [],
          }),
        );
      }
      if (url.endsWith("KeyUpdatesService.QueryKeyUpdates")) {
        const incidentID = body.query.incidentID;
        if (incidentID === "with-summary") {
          return new Response(JSON.stringify({ keyUpdates: [] }));
        }
        keyUpdateBodies.push(body);
        keyUpdatePage++;
        if (keyUpdatePage === 1) {
          return new Response(
            JSON.stringify({
              keyUpdates: [
                {
                  id: "update-2",
                  title: "Monitoring",
                  content: "Authentication has recovered and we are monitoring cache traffic.",
                  createdTime: "2026-05-05T11:30:00.000Z",
                },
              ],
              cursor: { hasMore: true, nextValue: "next-update" },
            }),
          );
        }
        return new Response(
          JSON.stringify({
            keyUpdates: [
              {
                id: "update-1",
                title: "Investigating",
                content: "We are investigating cache authentication failures.",
                createdTime: "2026-05-05T10:00:00.000Z",
              },
            ],
            cursor: { hasMore: false, nextValue: "" },
          }),
        );
      }
      throw new Error(`unmocked URL: ${url}`);
    }) as typeof fetch;

    const snapshot = await fetchStatusFromGrafana(ENV);

    expect(snapshot.activeIncidents[0]?.updates).toEqual([
      {
        at: "2026-05-05T11:30:00.000Z",
        status: "monitoring",
        title: "Monitoring",
        body: "Authentication has recovered and we are monitoring cache traffic.",
      },
      {
        at: "2026-05-05T10:00:00.000Z",
        status: "investigating",
        title: "Investigating",
        body: "We are investigating cache authentication failures.",
      },
    ]);
    expect(snapshot.activeIncidents[1]?.updates).toEqual([
      {
        at: "2026-05-05T11:00:00.000Z",
        status: "investigating",
        body: "We are investigating elevated latency.",
      },
    ]);
    expect(keyUpdateBodies).toEqual([
      {
        query: {
          incidentID: "with-updates",
          limit: 100,
          orderDirection: "DESC",
          orderField: "createdTime",
          contentType: "text/plain",
        },
      },
      {
        query: {
          incidentID: "with-updates",
          limit: 100,
          orderDirection: "DESC",
          orderField: "createdTime",
          contentType: "text/plain",
        },
        cursor: "next-update",
      },
    ]);
  });

  it("matches affectedComponents from real Grafana labels of shape {key, label}", async () => {
    globalThis.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.endsWith("FieldsService.GetFields")) {
        return new Response(
          JSON.stringify({
            fields: [{ name: "affected_service", selectoptions: [{ value: "cache" }, { value: "api" }] }],
          }),
        );
      }
      const isActive = (typeof init?.body === "string" ? init.body : "").includes("status:active");
      const incidents = isActive
        ? [
            {
              incidentID: "inc-real",
              title: "Cache slow",
              severity: "minor",
              status: "active",
              createdTime: "2026-05-05T11:00:00.000Z",
              // The shape Grafana actually returns: a flat { key, label } pair.
              labels: [{ key: "affected_service", label: "cache" }],
            },
          ]
        : [];
      return new Response(JSON.stringify({ incidents }));
    }) as typeof fetch;

    const snapshot = await fetchStatusFromGrafana(ENV);
    expect(snapshot.activeIncidents[0]?.affectedComponents).toEqual(["cache"]);
    expect(snapshot.components.find((c) => c.id === "cache")?.status).toBe("degraded_performance");
  });

  it("sends pagination cursor as a top-level sibling of query, not inside it", async () => {
    const incidentBodies: Array<Record<string, unknown>> = [];
    let page = 0;
    globalThis.fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.endsWith("FieldsService.GetFields")) {
        return new Response(JSON.stringify({ fields: [] }));
      }
      const body = typeof init?.body === "string" ? JSON.parse(init.body) : {};
      const isActive = JSON.stringify(body).includes("status:active");
      if (!isActive) {
        return new Response(JSON.stringify({ incidents: [] }));
      }
      incidentBodies.push(body);
      page++;
      if (page === 1) {
        return new Response(
          JSON.stringify({
            incidents: [{ incidentID: "p1", title: "P1", status: "active" }],
            cursor: { hasMore: true, nextValue: "next-token" },
          }),
        );
      }
      return new Response(
        JSON.stringify({
          incidents: [{ incidentID: "p2", title: "P2", status: "active" }],
          cursor: { hasMore: false, nextValue: "" },
        }),
      );
    }) as typeof fetch;

    const snapshot = await fetchStatusFromGrafana(ENV);

    // First active call has no cursor; second carries it as a top-level field.
    expect(incidentBodies[0]).toEqual({
      query: { queryString: "isdrill:false status:active", limit: 100, orderDirection: "DESC" },
    });
    expect(incidentBodies[1]).toEqual({
      query: { queryString: "isdrill:false status:active", limit: 100, orderDirection: "DESC" },
      cursor: "next-token",
    });
    // Both pages of incidents are merged.
    expect(snapshot.activeIncidents.map((i) => i.id).sort()).toEqual(["p1", "p2"]);
  });
});
