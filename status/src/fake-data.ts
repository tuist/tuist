import type { Component, Incident, StatusSnapshot } from "./types.js";

const FAKE_COMPONENTS: Omit<Component, "status">[] = [
  {
    id: "cli",
    name: "Tuist CLI",
    description: "Command-line workflows: generate, build, test, cache, registry.",
  },
  {
    id: "dashboard",
    name: "Dashboard",
    description: "Web dashboard at tuist.dev.",
  },
  {
    id: "api",
    name: "API",
    description: "Public REST and OpenAPI surfaces consumed by the CLI and integrations.",
  },
  {
    id: "cache",
    name: "Binary Cache",
    description: "Remote build and test cache used by Tuist projects.",
  },
  {
    id: "previews",
    name: "App Previews",
    description: "Shareable iOS and macOS app previews.",
  },
  {
    id: "registry",
    name: "Swift Package Registry",
    description: "Mirror of the Swift package ecosystem served by Tuist.",
  },
];

const now = () => new Date().toISOString();
const minutesAgo = (n: number) => new Date(Date.now() - n * 60_000).toISOString();
const hoursAgo = (n: number) => new Date(Date.now() - n * 60 * 60_000).toISOString();
const daysAgo = (n: number) => new Date(Date.now() - n * 24 * 60 * 60_000).toISOString();

export function fakeStatus(): StatusSnapshot {
  const components: Component[] = FAKE_COMPONENTS.map((c) => ({
    ...c,
    status: c.id === "cache" ? "degraded_performance" : "operational",
  }));

  const activeIncidents: Incident[] = [
    {
      id: "inc-2026-05-04-001",
      title: "Elevated cache hit latency in eu-central-1",
      severity: "minor",
      status: "monitoring",
      affectedComponents: ["cache"],
      startedAt: minutesAgo(42),
      resolvedAt: null,
      updates: [
        {
          at: minutesAgo(8),
          status: "monitoring",
          body: "Latency is back to baseline. We're keeping an eye on it for the next 30 minutes before resolving.",
        },
        {
          at: minutesAgo(25),
          status: "identified",
          body: "Identified a saturated upstream connection pool. Failing over now.",
        },
        {
          at: minutesAgo(42),
          status: "investigating",
          body: "Investigating reports of slow cache hits from European users.",
        },
      ],
    },
  ];

  const recentIncidents: Incident[] = [
    {
      id: "inc-2026-05-02-001",
      title: "Dashboard sign-in unavailable for ~14 minutes",
      severity: "major",
      status: "resolved",
      affectedComponents: ["dashboard", "api"],
      startedAt: daysAgo(2),
      resolvedAt: hoursAgo(47),
      updates: [
        {
          at: hoursAgo(47),
          status: "resolved",
          body: "Sign-in is fully restored. Postmortem to follow.",
        },
        {
          at: hoursAgo(48),
          status: "investigating",
          body: "Investigating a spike in sign-in errors on the dashboard.",
        },
      ],
    },
    {
      id: "inc-2026-04-28-001",
      title: "Scheduled maintenance: registry index rebuild",
      severity: "maintenance",
      status: "resolved",
      affectedComponents: ["registry"],
      startedAt: daysAgo(6),
      resolvedAt: daysAgo(6),
      updates: [
        {
          at: daysAgo(6),
          status: "resolved",
          body: "Registry index rebuild complete. No customer-visible impact.",
        },
      ],
    },
  ];

  return {
    overall: "degraded_performance",
    components,
    activeIncidents,
    recentIncidents,
    fetchedAt: now(),
  };
}
