import { Feed } from "feed";
import type { Incident, IncidentStatus, StatusSnapshot } from "../types.js";

const STATUS_PREFIX: Record<IncidentStatus, string> = {
  investigating: "Investigating",
  identified: "Identified",
  monitoring: "Monitoring",
  resolved: "Resolved",
};

interface Opts {
  title: string;
  baseUrl: string;
  snapshot: StatusSnapshot;
}

interface Entry {
  id: string;
  title: string;
  link: string;
  publishedAt: string;
  body: string;
}

function entriesFor(snapshot: StatusSnapshot, baseUrl: string): Entry[] {
  const incidents: Incident[] = [...snapshot.activeIncidents, ...snapshot.recentIncidents];
  const entries: Entry[] = [];
  for (const incident of incidents) {
    const incidentLink = `${baseUrl}/#${incident.id}`;
    for (const update of incident.updates) {
      entries.push({
        id: `${incident.id}#${update.at}`,
        title: `[${STATUS_PREFIX[update.status]}] ${incident.title}`,
        link: incidentLink,
        publishedAt: update.at,
        body: update.body,
      });
    }
  }
  entries.sort((a, b) => (a.publishedAt < b.publishedAt ? 1 : -1));
  return entries;
}

function buildFeed({ title, baseUrl, snapshot }: Opts): Feed {
  const entries = entriesFor(snapshot, baseUrl);
  const updated = entries[0]?.publishedAt ?? snapshot.fetchedAt;
  const feed = new Feed({
    id: `${baseUrl}/`,
    title,
    description: `Incident updates from ${title}.`,
    link: baseUrl,
    language: "en",
    updated: new Date(updated),
    copyright: `© ${new Date().getUTCFullYear()} Tuist`,
    feedLinks: {
      rss: `${baseUrl}/feed.rss`,
      atom: `${baseUrl}/feed.atom`,
    },
  });
  for (const entry of entries) {
    feed.addItem({
      id: entry.id,
      title: entry.title,
      link: entry.link,
      description: entry.body,
      content: entry.body,
      date: new Date(entry.publishedAt),
    });
  }
  return feed;
}

export function rssFeed(opts: Opts): string {
  return buildFeed(opts).rss2();
}

export function atomFeed(opts: Opts): string {
  return buildFeed(opts).atom1();
}
