import { describe, expect, it } from "vitest";
import type { StatusSnapshot } from "../types.js";
import { statusPage } from "./page.js";

describe("statusPage", () => {
  it("renders the status updates for an incident", async () => {
    const snapshot: StatusSnapshot = {
      overall: "partial_outage",
      components: [],
      activeIncidents: [
        {
          id: "incident-1",
          title: "Authentication issues against the cache",
          severity: "major",
          status: "monitoring",
          affectedComponents: ["cache"],
          startedAt: "2026-07-17T15:18:00.000Z",
          resolvedAt: null,
          updates: [
            {
              at: "2026-07-17T15:42:00.000Z",
              status: "monitoring",
              title: "Mitigation applied, monitoring impact",
              body: "Cache authentication is recovering after the configuration change.",
            },
            {
              at: "2026-07-17T15:18:00.000Z",
              status: "investigating",
              title: "Investigating",
              body: "We are investigating authentication failures against the cache.",
            },
          ],
        },
      ],
      recentIncidents: [],
      fetchedAt: "2026-07-17T15:45:00.000Z",
    };

    const output = String(await statusPage({ title: "Tuist Status", snapshot }));

    expect(output).toContain('ol data-part="updates"');
    expect(output).toContain("Mitigation applied, monitoring impact.");
    expect(output).toContain("Cache authentication is recovering after the configuration change.");
    expect(output).toContain("Investigating.");
    expect(output).toContain("We are investigating authentication failures against the cache.");
  });
});
