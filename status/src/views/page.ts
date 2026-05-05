import { html, raw } from "hono/html";
import type { HtmlEscapedString } from "hono/utils/html";
import type {
  Component,
  ComponentStatus,
  Incident,
  IncidentSeverity,
  StatusSnapshot,
} from "../types.js";
import {
  ICON_ALERT_CIRCLE,
  ICON_ALERT_HEXAGON,
  ICON_ALERT_TRIANGLE,
  ICON_CIRCLE_CHECK,
  ICON_CIRCLE_DASHED,
  ICON_INFO_CIRCLE,
  ICON_RSS,
} from "./icons.js";
import { TUIST_MARK_SVG } from "./logo.js";
import { STYLES } from "./styles.js";

type Renderable = HtmlEscapedString | Promise<HtmlEscapedString>;

type NooraStatusBadge = "success" | "error" | "warning" | "attention" | "in_progress" | "disabled";
type NooraBadgeColor =
  | "neutral"
  | "destructive"
  | "warning"
  | "attention"
  | "success"
  | "information"
  | "focus"
  | "primary"
  | "secondary";
type NooraBannerStatus = "primary" | "error" | "success" | "warning" | "information";

const COMPONENT_STATUS_LABEL: Record<ComponentStatus, string> = {
  operational: "Operational",
  degraded_performance: "Degraded performance",
  partial_outage: "Partial outage",
  major_outage: "Major outage",
  under_maintenance: "Maintenance",
};

const COMPONENT_STATUS_TO_NOORA: Record<ComponentStatus, NooraStatusBadge> = {
  operational: "success",
  degraded_performance: "warning",
  partial_outage: "warning",
  major_outage: "error",
  under_maintenance: "in_progress",
};

const COMPONENT_STATUS_TO_BANNER: Record<ComponentStatus, NooraBannerStatus> = {
  operational: "success",
  degraded_performance: "warning",
  partial_outage: "warning",
  major_outage: "error",
  under_maintenance: "information",
};

const STATUS_ICONS: Record<NooraStatusBadge, string> = {
  success: ICON_CIRCLE_CHECK,
  error: ICON_ALERT_CIRCLE,
  warning: ICON_ALERT_HEXAGON,
  attention: ICON_ALERT_TRIANGLE,
  in_progress: ICON_CIRCLE_DASHED,
  disabled: ICON_ALERT_CIRCLE,
};

const OVERALL_HEADLINES: Record<ComponentStatus, string> = {
  operational: "All systems operational",
  degraded_performance: "Some systems degraded",
  partial_outage: "Partial outage in progress",
  major_outage: "Major outage in progress",
  under_maintenance: "Scheduled maintenance in progress",
};

const SEVERITY_LABEL: Record<IncidentSeverity, string> = {
  minor: "Minor",
  major: "Major",
  critical: "Critical",
  maintenance: "Maintenance",
};

const SEVERITY_TO_BADGE_COLOR: Record<IncidentSeverity, NooraBadgeColor> = {
  minor: "warning",
  major: "warning",
  critical: "destructive",
  maintenance: "information",
};

function formatDate(iso: string): string {
  const date = new Date(iso);
  return date.toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    timeZoneName: "short",
  });
}

function formatRange(startISO: string, endISO: string | null): string {
  const start = formatDate(startISO);
  if (!endISO) return `Started ${start}`;
  return `${start} → ${formatDate(endISO)}`;
}

function statusBadge(status: ComponentStatus): Renderable {
  const noora = COMPONENT_STATUS_TO_NOORA[status];
  return html`<span class="noora-status-badge" data-status="${noora}">
    <span data-part="icon">${raw(STATUS_ICONS[noora])}</span>
    <span data-part="label">${COMPONENT_STATUS_LABEL[status]}</span>
  </span>`;
}

function severityBadge(severity: IncidentSeverity): Renderable {
  const color = SEVERITY_TO_BADGE_COLOR[severity];
  return html`<span
    class="noora-badge"
    data-style="light-fill"
    data-color="${color}"
    data-size="small"
    >${SEVERITY_LABEL[severity]}</span
  >`;
}

function lineDivider(): Renderable {
  return html`<div class="noora-line-divider" role="separator">
    <span data-part="line"></span>
  </div>`;
}

function joinWithDividers(items: Renderable[]): Renderable[] {
  const out: Renderable[] = [];
  items.forEach((item, i) => {
    if (i > 0) out.push(lineDivider());
    out.push(item);
  });
  return out;
}

function componentRow(component: Component): Renderable {
  return html`<div class="status-component">
    <div data-part="name">
      <span data-part="title">${component.name}</span>
      <span data-part="description">${component.description}</span>
    </div>
    ${statusBadge(component.status)}
  </div>`;
}

function incidentToComponentStatus(i: Incident): ComponentStatus {
  if (i.status === "resolved") return "operational";
  switch (i.severity) {
    case "maintenance":
      return "under_maintenance";
    case "minor":
      return "degraded_performance";
    case "major":
      return "partial_outage";
    case "critical":
      return "major_outage";
  }
}

function incidentBlock(incident: Incident): Renderable {
  const updates = incident.updates.map(
    (u) => html`<li>
      <time data-part="time" datetime="${u.at}">${formatDate(u.at)}</time>
      <div data-part="body">
        <span data-part="status">${u.status}.</span> ${u.body}
      </div>
    </li>`,
  );
  return html`<article class="status-incident" id="${incident.id}">
    <header data-part="header">
      <h3 data-part="title">${incident.title}</h3>
      ${severityBadge(incident.severity)} ${statusBadge(incidentToComponentStatus(incident))}
    </header>
    <div data-part="meta">${formatRange(incident.startedAt, incident.resolvedAt)}</div>
    <ol data-part="updates">
      ${updates}
    </ol>
  </article>`;
}

interface CardOptions {
  icon: string;
  title: string;
  body: Renderable;
}

function card({ icon, title, body }: CardOptions): Renderable {
  return html`<div class="noora-card">
    <div data-part="header">
      <div data-part="icon-with-title">
        <div data-part="icon">${raw(icon)}</div>
        <div data-part="title">${title}</div>
      </div>
    </div>
    <div class="noora-card__section">${body}</div>
  </div>`;
}

interface PageOptions {
  title: string;
  snapshot: StatusSnapshot;
}

export function statusPage({ title, snapshot }: PageOptions): Renderable {
  const overall = snapshot.overall;
  const bannerStatus = COMPONENT_STATUS_TO_BANNER[overall];
  const bannerIcon = STATUS_ICONS[COMPONENT_STATUS_TO_NOORA[overall]];

  const componentsBody =
    snapshot.components.length === 0
      ? html`<div class="status-empty">No components configured.</div>`
      : html`${joinWithDividers(snapshot.components.map(componentRow))}`;

  const activeBody =
    snapshot.activeIncidents.length === 0
      ? html`<div class="status-empty">No active incidents.</div>`
      : html`${joinWithDividers(snapshot.activeIncidents.map(incidentBlock))}`;

  const recentBody =
    snapshot.recentIncidents.length === 0
      ? html`<div class="status-empty">No incidents reported in the last 14 days.</div>`
      : html`${joinWithDividers(snapshot.recentIncidents.map(incidentBlock))}`;

  const subscribeBody = html`<div class="status-subscribe">
    <p data-part="text">Follow updates from any feed reader.</p>
    <div data-part="links">
      <a data-part="link" href="/feed.rss">${raw(ICON_RSS)} RSS</a>
      <a data-part="link" href="/feed.atom">${raw(ICON_RSS)} Atom</a>
    </div>
  </div>`;

  return html`<!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${title}</title>
        <meta name="description" content="${title} — current status of Tuist services." />
        <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
        <link
          rel="alternate"
          type="application/rss+xml"
          title="${title} — RSS"
          href="/feed.rss"
        />
        <link
          rel="alternate"
          type="application/atom+xml"
          title="${title} — Atom"
          href="/feed.atom"
        />
        <link rel="stylesheet" href="https://rsms.me/inter/inter.css" />
        <style>
          ${raw(STYLES)}
        </style>
      </head>
      <body>
        <main>
          <section class="noora-banner" data-status="${bannerStatus}">
            <div data-part="icon">${raw(bannerIcon)}</div>
            <div data-part="title">${OVERALL_HEADLINES[overall]}</div>
          </section>
          <div class="status-page">
            <header class="status-header">
              <a data-part="brand" href="/">
                <span data-part="mark">${raw(TUIST_MARK_SVG)}</span>
                <span data-part="title">${title}</span>
              </a>
              <span data-part="meta">Updated ${formatDate(snapshot.fetchedAt)}</span>
            </header>

            ${card({ icon: ICON_CIRCLE_CHECK, title: "Components", body: componentsBody })}
            ${card({ icon: ICON_ALERT_CIRCLE, title: "Active incidents", body: activeBody })}
            ${card({ icon: ICON_INFO_CIRCLE, title: "Past 14 days", body: recentBody })}
            ${card({ icon: ICON_RSS, title: "Subscribe", body: subscribeBody })}

            <footer class="status-footer">
              <span>Tuist — status.tuist.dev</span>
              <span>
                <a href="/api/status.json">JSON</a> ·
                <a href="/feed.rss">RSS</a> ·
                <a href="/feed.atom">Atom</a>
              </span>
            </footer>
          </div>
        </main>
      </body>
    </html>`;
}
