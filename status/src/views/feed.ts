import type { Incident, IncidentStatus, StatusSnapshot } from "../types.js";

interface FeedEntry {
  id: string;
  title: string;
  link: string;
  publishedAt: string;
  body: string;
}

const STATUS_PREFIX: Record<IncidentStatus, string> = {
  investigating: "Investigating",
  identified: "Identified",
  monitoring: "Monitoring",
  resolved: "Resolved",
};

function escapeXml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function entriesFor(snapshot: StatusSnapshot, baseUrl: string): FeedEntry[] {
  const incidents: Incident[] = [...snapshot.activeIncidents, ...snapshot.recentIncidents];
  const entries: FeedEntry[] = [];
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

export function rssFeed(opts: {
  title: string;
  baseUrl: string;
  snapshot: StatusSnapshot;
}): string {
  const { title, baseUrl, snapshot } = opts;
  const entries = entriesFor(snapshot, baseUrl);
  const lastBuild = new Date(snapshot.fetchedAt).toUTCString();
  const items = entries
    .map(
      (e) => `    <item>
      <title>${escapeXml(e.title)}</title>
      <link>${escapeXml(e.link)}</link>
      <guid isPermaLink="false">${escapeXml(e.id)}</guid>
      <pubDate>${new Date(e.publishedAt).toUTCString()}</pubDate>
      <description>${escapeXml(e.body)}</description>
    </item>`,
    )
    .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>${escapeXml(title)}</title>
    <link>${escapeXml(baseUrl)}</link>
    <atom:link href="${escapeXml(`${baseUrl}/feed.rss`)}" rel="self" type="application/rss+xml"/>
    <description>Incident updates from ${escapeXml(title)}.</description>
    <language>en</language>
    <lastBuildDate>${lastBuild}</lastBuildDate>
${items}
  </channel>
</rss>
`;
}

export function atomFeed(opts: {
  title: string;
  baseUrl: string;
  snapshot: StatusSnapshot;
}): string {
  const { title, baseUrl, snapshot } = opts;
  const entries = entriesFor(snapshot, baseUrl);
  const updated = entries[0]?.publishedAt ?? snapshot.fetchedAt;
  const items = entries
    .map(
      (e) => `  <entry>
    <id>tag:${escapeXml(new URL(baseUrl).host)},2025:${escapeXml(e.id)}</id>
    <title>${escapeXml(e.title)}</title>
    <link href="${escapeXml(e.link)}"/>
    <updated>${new Date(e.publishedAt).toISOString()}</updated>
    <published>${new Date(e.publishedAt).toISOString()}</published>
    <content type="text">${escapeXml(e.body)}</content>
  </entry>`,
    )
    .join("\n");

  return `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>${escapeXml(title)}</title>
  <id>${escapeXml(baseUrl)}/</id>
  <link href="${escapeXml(baseUrl)}/" rel="alternate" type="text/html"/>
  <link href="${escapeXml(`${baseUrl}/feed.atom`)}" rel="self" type="application/atom+xml"/>
  <updated>${new Date(updated).toISOString()}</updated>
  <subtitle>Incident updates from ${escapeXml(title)}.</subtitle>
${items}
</feed>
`;
}
