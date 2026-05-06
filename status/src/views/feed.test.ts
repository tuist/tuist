import { describe, expect, it } from "vitest";
import type { StatusSnapshot } from "../types.js";
import { atomFeed, rssFeed } from "./feed.js";

function snapshot(): StatusSnapshot {
  return {
    overall: "degraded_performance",
    components: [],
    activeIncidents: [
      {
        id: "inc-1",
        title: "Cache slow",
        severity: "minor",
        status: "investigating",
        affectedComponents: ["cache"],
        startedAt: "2026-05-01T10:00:00.000Z",
        resolvedAt: null,
        updates: [
          { at: "2026-05-01T11:00:00.000Z", status: "monitoring", body: "Recovering." },
          { at: "2026-05-01T10:00:00.000Z", status: "investigating", body: "Looking into it." },
        ],
      },
    ],
    recentIncidents: [
      {
        id: "inc-2",
        title: "Dashboard down",
        severity: "major",
        status: "resolved",
        affectedComponents: ["dashboard"],
        startedAt: "2026-04-29T08:00:00.000Z",
        resolvedAt: "2026-04-29T08:30:00.000Z",
        updates: [{ at: "2026-04-29T08:30:00.000Z", status: "resolved", body: "Restored." }],
      },
    ],
    fetchedAt: "2026-05-05T12:00:00.000Z",
  };
}

const opts = { title: "Tuist Status", baseUrl: "https://status.example.com", snapshot: snapshot() };

describe("rssFeed", () => {
  it("emits an RSS 2.0 document with channel metadata", () => {
    const xml = rssFeed(opts);
    expect(xml).toMatch(/^<\?xml/);
    expect(xml).toContain('<rss version="2.0"');
    expect(xml).toContain("<title>Tuist Status</title>");
    expect(xml).toContain("<link>https://status.example.com</link>");
    expect(xml).toContain('<atom:link href="https://status.example.com/feed.rss"');
  });

  it("emits one <item> per incident update", () => {
    const xml = rssFeed(opts);
    expect((xml.match(/<item>/g) ?? []).length).toBe(3);
  });

  it("sorts items newest first", () => {
    const xml = rssFeed(opts);
    // The regex only matches item titles (in CDATA); the channel title isn't wrapped.
    const titles = [...xml.matchAll(/<title><!\[CDATA\[(.+?)\]\]><\/title>/g)].map((m) => m[1]);
    expect(titles).toEqual(["[Monitoring] Cache slow", "[Investigating] Cache slow", "[Resolved] Dashboard down"]);
  });

  it("links every item to the incident anchor on the page", () => {
    const xml = rssFeed(opts);
    expect(xml).toContain("<link>https://status.example.com/#inc-1</link>");
    expect(xml).toContain("<link>https://status.example.com/#inc-2</link>");
  });

  it("handles a snapshot with no incidents", () => {
    const xml = rssFeed({
      ...opts,
      snapshot: { ...snapshot(), activeIncidents: [], recentIncidents: [] },
    });
    expect(xml).toContain("<rss");
    expect(xml).not.toContain("<item>");
  });
});

describe("atomFeed", () => {
  it("emits an Atom 1.0 document", () => {
    const xml = atomFeed(opts);
    expect(xml).toMatch(/^<\?xml/);
    expect(xml).toContain('<feed xmlns="http://www.w3.org/2005/Atom">');
    expect(xml).toContain("<id>https://status.example.com/</id>");
    expect(xml).toContain('<link rel="self" href="https://status.example.com/feed.atom"');
  });

  it("emits one <entry> per incident update", () => {
    const xml = atomFeed(opts);
    expect((xml.match(/<entry>/g) ?? []).length).toBe(3);
  });
});
