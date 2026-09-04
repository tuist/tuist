import { html, raw } from "hono/html";
import type { HtmlEscapedString } from "hono/utils/html";
import { micromark } from "micromark";
import type { Component, ComponentStatus, Incident, IncidentSeverity, StatusSnapshot } from "../types.js";
import {
  ICON_ALERT_CIRCLE,
  ICON_ALERT_TRIANGLE,
  ICON_ATOM,
  ICON_CIRCLE_CHECK,
  ICON_DEVICE_DESKTOP,
  ICON_EXTERNAL_LINK,
  ICON_MOON,
  ICON_RSS,
  ICON_SUN_HIGH,
} from "./icons.js";
import { TUIST_MARK_SVG, TUIST_WORDMARK_SVG } from "./logo.js";
import { STYLES } from "./styles.js";
import { WAVE_SCRIPT } from "./wave.js";

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

// One glyph per status across the hero alert, the component badges and the
// incident state badges: check for success, circle for error and
// information/maintenance, triangle for every warning (Noora's status badge
// would use a hexagon there, but the alert uses a triangle, so the triangle
// wins page-wide).
const STATUS_ICONS: Record<NooraStatusBadge, string> = {
  success: ICON_CIRCLE_CHECK,
  error: ICON_ALERT_CIRCLE,
  warning: ICON_ALERT_TRIANGLE,
  attention: ICON_ALERT_TRIANGLE,
  in_progress: ICON_ALERT_CIRCLE,
  disabled: ICON_ALERT_CIRCLE,
};

// Which particle wave the stage shows: the calm sinusoid, the jittery band,
// the torn band, or the calm wave in maintenance blue.
type WaveState = "operational" | "degraded" | "outage" | "maintenance";

const WAVE_STATE: Record<ComponentStatus, WaveState> = {
  operational: "operational",
  degraded_performance: "degraded",
  partial_outage: "degraded",
  major_outage: "outage",
  under_maintenance: "maintenance",
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

const INCIDENT_STATUS_LABEL: Record<Incident["status"], string> = {
  investigating: "Investigating",
  identified: "Identified",
  monitoring: "Monitoring",
  resolved: "Resolved",
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

function formatDay(iso: string): string {
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

// Day-level range only: the update timeline below already carries the times.
function formatRange(startISO: string, endISO: string | null): string {
  const start = formatDay(startISO);
  if (!endISO) return `Started ${start}`;
  const end = formatDay(endISO);
  return start === end ? start : `${start} → ${end}`;
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
  return html`<span class="noora-badge" data-style="light-fill" data-color="${color}" data-size="large"
    ><span>${SEVERITY_LABEL[severity]}</span></span
  >`;
}

type NooraAlertStatus = "information" | "warning" | "error" | "success";

const COMPONENT_STATUS_TO_ALERT: Record<ComponentStatus, NooraAlertStatus> = {
  operational: "success",
  degraded_performance: "warning",
  partial_outage: "warning",
  major_outage: "error",
  under_maintenance: "information",
};

const ALERT_ICONS: Record<NooraAlertStatus, string> = {
  information: ICON_ALERT_CIRCLE,
  error: ICON_ALERT_CIRCLE,
  success: ICON_CIRCLE_CHECK,
  warning: ICON_ALERT_TRIANGLE,
};

// The hero's overall state as a medium Noora alert (Noora.Alert, secondary
// type): status icon plus the state label.
function overallAlert(status: ComponentStatus): Renderable {
  const alert = COMPONENT_STATUS_TO_ALERT[status];
  return html`<div class="noora-alert" data-type="secondary" data-status="${alert}" data-size="medium" role="status">
    <div data-part="icon">${raw(ALERT_ICONS[alert])}</div>
    <span data-part="title">${COMPONENT_STATUS_LABEL[status]}</span>
  </div>`;
}

const COMPONENT_STATUS_TO_BADGE_COLOR: Record<ComponentStatus, NooraBadgeColor> = {
  operational: "success",
  degraded_performance: "warning",
  partial_outage: "warning",
  major_outage: "destructive",
  under_maintenance: "information",
};

// The incident header's state as a light-fill badge (matching the severity
// badge beside it) with the status glyph in its icon slot.
function stateBadge(status: ComponentStatus): Renderable {
  const color = COMPONENT_STATUS_TO_BADGE_COLOR[status];
  const glyph = STATUS_ICONS[COMPONENT_STATUS_TO_NOORA[status]];
  return html`<span
    class="noora-badge"
    data-style="light-fill"
    data-color="${color}"
    data-size="large"
    data-icon="true"
  >
    <div data-part="icon">${raw(glyph)}</div>
    <span>${COMPONENT_STATUS_LABEL[status]}</span>
  </span>`;
}

function componentRow(component: Component): Renderable {
  return html`<li>
    <div class="status-component">
      <div data-part="name">
        <span data-part="title">${component.name}</span>
        <span data-part="description">${component.description}</span>
      </div>
      ${statusBadge(component.status)}
    </div>
  </li>`;
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
  const updates = incident.updates.map((u) => {
    const title = u.title?.trim() || INCIDENT_STATUS_LABEL[u.status];
    const punctuation = /[.!?]$/.test(title) ? "" : ".";
    const body = micromark(u.body, { allowDangerousHtml: false, allowDangerousProtocol: false });
    return html`<li>
      <time data-part="time" datetime="${u.at}">${formatDate(u.at)}</time>
      <div data-part="body">
        <span data-part="status">${title}${punctuation}</span>
        <div data-part="markdown">${raw(body)}</div>
      </div>
    </li>`;
  });
  return html`<li>
    <article class="status-incident" id="${incident.id}">
      <div data-part="meta">${formatRange(incident.startedAt, incident.resolvedAt)}</div>
      <header data-part="header">
        <h3 data-part="title">${incident.title}</h3>
        ${severityBadge(incident.severity)} ${stateBadge(incidentToComponentStatus(incident))}
      </header>
      <ol data-part="updates">
        ${updates}
      </ol>
    </article>
  </li>`;
}

interface SectionOptions {
  id: string;
  title: string;
  empty: string;
  items: Renderable[];
  action?: Renderable;
}

function section({ id, title, empty, items, action }: SectionOptions): Renderable {
  const body =
    items.length === 0
      ? html`<p class="status-empty">${empty}</p>`
      : html`<ol data-part="list">
          ${items}
        </ol>`;
  return html`<section
    class="status-frame status-section"
    data-section="${id}"
    data-live="${id}"
    aria-labelledby="${id}-title"
  >
    <header data-part="header">
      <h2 data-part="title" id="${id}-title">${title}</h2>
      ${action ?? ""}
    </header>
    ${body}
  </section>`;
}

// Runs before the stylesheet applies so the page never flashes the wrong
// theme. Shares the dashboard's and marketing site's "preferred-theme"
// localStorage key: Noora's shadow tokens key off data-theme, its colors off
// color-scheme. The footer switcher writes the same key and re-applies.
const THEME_SCRIPT = `
(function () {
  var root = document.documentElement;
  var systemDark = window.matchMedia("(prefers-color-scheme: dark)");
  function preferred() {
    try {
      var stored = localStorage.getItem("preferred-theme");
      return stored === null || stored === "null" ? "system" : stored;
    } catch (e) {
      return "system";
    }
  }
  function apply() {
    var theme = preferred();
    var resolved = theme === "system" ? (systemDark.matches ? "dark" : "light") : theme;
    root.style.setProperty("color-scheme", theme === "system" ? "light dark" : theme);
    root.setAttribute("data-theme", resolved);
    var options = document.querySelectorAll("[data-theme-option]");
    for (var i = 0; i < options.length; i++) {
      if (options[i].getAttribute("data-theme-option") === theme) options[i].setAttribute("data-selected", "");
      else options[i].removeAttribute("data-selected");
    }
  }
  apply();
  systemDark.addEventListener("change", apply);
  document.addEventListener("click", function (event) {
    var target = event.target instanceof Element ? event.target.closest("[data-theme-option]") : null;
    if (!target) return;
    try {
      localStorage.setItem("preferred-theme", target.getAttribute("data-theme-option"));
    } catch (e) {}
    apply();
  });
})();
`;

// Live refresh: poll the JSON snapshot while the tab is visible and, when the
// overall status changes, fetch the page again and swap the hero and the
// sections in place, then flip the wave's state so it morphs rather than
// reloading (a reload would re-seed the particles and cut the animation).
const LIVE_POLL_MS = 60_000;

function liveScript(): string {
  return `
(function () {
  var POLL_MS = ${LIVE_POLL_MS};
  var WAVE_STATE = ${JSON.stringify(WAVE_STATE)};
  var stage = document.querySelector(".status-stage");
  var canvas = stage && stage.querySelector("canvas[data-wave]");
  if (!stage || !canvas || typeof fetch !== "function") return;

  function refresh(overall) {
    return fetch("/", { cache: "no-store" })
      .then(function (response) {
        return response.ok ? response.text() : null;
      })
      .then(function (markup) {
        if (!markup) return;
        var next = new DOMParser().parseFromString(markup, "text/html");
        var fresh = next.querySelectorAll("[data-live]");
        for (var i = 0; i < fresh.length; i++) {
          var current = document.querySelector('[data-live="' + fresh[i].getAttribute("data-live") + '"]');
          if (current) current.replaceWith(fresh[i]);
        }
        stage.setAttribute("data-overall", overall);
        canvas.setAttribute("data-wave", WAVE_STATE[overall] || "operational");
      });
  }
  var busy = false;
  function check() {
    if (busy || document.visibilityState !== "visible") return;
    busy = true;
    fetch("/api/status.json", { cache: "no-store", headers: { Accept: "application/json" } })
      .then(function (response) {
        return response.ok ? response.json() : null;
      })
      .then(function (snapshot) {
        if (!snapshot || snapshot.overall === stage.getAttribute("data-overall")) return;
        return refresh(snapshot.overall);
      })
      .catch(function () {})
      .then(function () {
        busy = false;
      });
  }
  setInterval(check, POLL_MS);
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible") check();
  });
})();
`;
}

interface PageOptions {
  title: string;
  snapshot: StatusSnapshot;
}

export function statusPage({ title, snapshot }: PageOptions): Renderable {
  const overall = snapshot.overall;

  return html`<!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${title}</title>
        <meta name="description" content="${title} — current status of Tuist services." />
        <link rel="icon" href="/favicon.ico" sizes="any" />
        <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
        <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
        <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png" />
        <link rel="alternate" type="application/rss+xml" title="${title} — RSS" href="/feed.rss" />
        <link rel="alternate" type="application/atom+xml" title="${title} — Atom" href="/feed.atom" />
        <link rel="preconnect" href="https://rsms.me/" />
        <link rel="stylesheet" href="https://rsms.me/inter/inter.css" />
        <script>
          ${raw(THEME_SCRIPT)};
        </script>
        <style>
          ${raw(STYLES)}
        </style>
      </head>
      <body>
        <header class="status-navbar">
          <div data-part="bar">
            <a data-part="brand" href="/">
              ${raw(TUIST_MARK_SVG)}
              <span data-part="title">${title}</span>
            </a>
            <div data-part="subscribe">
              <span data-part="label">Subscribe for updates</span>
              <a
                class="noora-button"
                data-variant="secondary"
                data-size="medium"
                data-icon-only
                href="/feed.atom"
                aria-label="Atom feed"
                title="Atom feed"
                >${raw(ICON_ATOM)}</a
              >
              <a
                class="noora-button"
                data-variant="secondary"
                data-size="medium"
                data-icon-only
                href="/feed.rss"
                aria-label="RSS feed"
                title="RSS feed"
                >${raw(ICON_RSS)}</a
              >
            </div>
          </div>
        </header>
        <main>
          <!-- Status wave (Figma: 1200x96): the particle field's shape and
               ink ramp follow the overall status. -->
          <div class="status-frame status-stage" aria-hidden="true" data-overall="${overall}">
            <canvas data-wave="${WAVE_STATE[overall]}"></canvas>
          </div>
          <section class="status-frame status-hero" data-live="hero" aria-labelledby="status-overall">
            <span data-part="eyebrow">Current status</span>
            <h1 data-part="title" id="status-overall">${OVERALL_HEADLINES[overall]}</h1>
            ${overallAlert(overall)}
            <p data-part="meta">Updated ${formatDate(snapshot.fetchedAt)}</p>
          </section>

          ${section({
            id: "components",
            title: "Components",
            empty: "No components configured.",
            items: snapshot.components.map(componentRow),
          })}
          ${section({
            id: "active",
            title: "Active incidents",
            empty: "No active incidents.",
            items: snapshot.activeIncidents.map(incidentBlock),
          })}
          ${section({
            id: "recent",
            title: "Past 14 days",
            empty: "No incidents reported in the last 14 days.",
            items: snapshot.recentIncidents.map(incidentBlock),
            action: html`<a
              class="noora-link-button"
              data-variant="secondary"
              data-size="large"
              href="https://hive.tuist.dev/postmortems"
              target="_blank"
              rel="noopener noreferrer"
              ><span>Incident history</span>${raw(ICON_EXTERNAL_LINK)}</a
            >`,
          })}

          <footer class="status-frame status-footer">
            <div data-part="main">
              <div data-part="brand">
                ${raw(TUIST_WORDMARK_SVG)}
                <p data-part="tagline">
                  Live status of Tuist's hosted services, sourced from our incident tooling and refreshed on every
                  visit.
                </p>
              </div>
            </div>
            <div data-part="bar">
              <div class="noora-button-group" data-size="small" role="group" aria-label="Theme">
                <button
                  class="noora-button-group-item"
                  type="button"
                  data-icon-only
                  data-theme-option="system"
                  data-selected
                  aria-label="System theme"
                  title="System theme"
                >
                  ${raw(ICON_DEVICE_DESKTOP)}
                </button>
                <button
                  class="noora-button-group-item"
                  type="button"
                  data-icon-only
                  data-theme-option="light"
                  aria-label="Light theme"
                  title="Light theme"
                >
                  ${raw(ICON_SUN_HIGH)}
                </button>
                <button
                  class="noora-button-group-item"
                  type="button"
                  data-icon-only
                  data-theme-option="dark"
                  aria-label="Dark theme"
                  title="Dark theme"
                >
                  ${raw(ICON_MOON)}
                </button>
              </div>
              <div data-part="links">
                <a href="/api/status.json">JSON</a>
                <a href="/feed.rss">RSS</a>
                <a href="/feed.atom">Atom</a>
                <a href="https://tuist.dev" target="_blank" rel="noopener noreferrer">tuist.dev</a>
              </div>
            </div>
          </footer>
        </main>
        <script>
          ${raw(WAVE_SCRIPT)};
        </script>
        <script>
          ${raw(liveScript())};
        </script>
      </body>
    </html>`;
}
