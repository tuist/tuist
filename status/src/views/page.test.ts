import { describe, expect, it } from "vitest";
import type { StatusSnapshot } from "../types.js";
import { downshiftHeadings, statusPage } from "./page.js";

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
              body: "Cache authentication is **recovering** after the [configuration change](https://example.com/change).",
            },
            {
              at: "2026-07-17T15:18:00.000Z",
              status: "investigating",
              title: "Investigating",
              body: "We are investigating authentication failures against the cache. <script>alert('unsafe')</script> [unsafe](javascript:alert(1))",
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
    expect(output).toContain(
      'Cache authentication is <strong>recovering</strong> after the <a href="https://example.com/change">configuration change</a>.',
    );
    expect(output).toContain("Investigating.");
    expect(output).toContain(
      "We are investigating authentication failures against the cache. &lt;script&gt;alert('unsafe')&lt;/script&gt; <a href=\"\">unsafe</a>",
    );
    expect(output).not.toContain("<script>alert('unsafe')</script>");
    // The paragraphs land directly in the update body, no wrapper.
    expect(output).not.toContain('data-part="markdown"');
    expect(output).toContain(
      '<div data-part="body"><span data-part="status">Mitigation applied, monitoring impact.</span> <p>',
    );
  });

  it("exposes the page structure to assistive technology", async () => {
    const snapshot: StatusSnapshot = {
      overall: "operational",
      components: [
        {
          id: "cache",
          name: "Cache",
          description: "Binary cache storage and retrieval.",
          status: "operational",
        },
      ],
      activeIncidents: [],
      recentIncidents: [],
      fetchedAt: "2026-07-17T15:45:00.000Z",
    };

    const output = String(await statusPage({ title: "Tuist Status", snapshot }));
    const body = output.slice(output.indexOf("<body>"));

    // Skip link and live region come first; the hero alert is no longer a
    // live region itself (the refresh replaces it wholesale).
    expect(body).toMatch(
      /<body>\s*<a class="visually-hidden" data-part="skip" href="#status-overall">Skip to content<\/a>/,
    );
    expect(body).toContain(
      '<p id="status-announcer" class="visually-hidden" aria-live="polite" aria-atomic="true"></p>',
    );
    expect(body).not.toContain('role="status"');
    expect(body).toContain('<h1 data-part="title" id="status-overall" tabindex="-1">');
    expect(body).toContain('<main aria-labelledby="status-overall">');

    // Theme switcher: one radio group, the system option checked by default.
    expect(body).toContain('role="radiogroup" aria-label="Theme"');
    expect(body.match(/role="radio"/g)).toHaveLength(3);
    expect(body).toMatch(/role="radio"\s+aria-checked="true"\s+data-icon-only\s+data-theme-option="system"/);
    expect(body.match(/aria-checked="false"/g)).toHaveLength(2);

    // Icon-only controls carry one accessible name, not a duplicate title.
    expect(body).not.toContain('title="');

    // The feed buttons are one labelled group; the visible label is not read twice.
    expect(body).toContain('data-part="subscribe" role="group" aria-label="Subscribe for updates"');
    expect(body).toContain('<span data-part="label" aria-hidden="true">Subscribe for updates</span>');

    // Component name and description are a term/definition pair.
    expect(body).toContain('<dl data-part="name">');
    expect(body).toContain('<dt data-part="title">Cache</dt>');
    expect(body).toContain('<dd data-part="description">Binary cache storage and retrieval.</dd>');

    // The theme script mirrors selection into aria-checked and the live
    // script writes status changes into the announcer.
    expect(output).toContain('setAttribute("aria-checked", selected ? "true" : "false")');
    expect(output).toContain('announcer.textContent = "Status changed: "');
    expect(output).toContain("current.contains(document.activeElement)");
  });

  it("downshifts headings from incident markdown below the incident title", () => {
    expect(
      downshiftHeadings('<h1>Root cause</h1><h2 id="x">Impact</h2><h3>Next</h3><h6>Deep</h6><p>h1 in text</p>'),
    ).toBe('<h4>Root cause</h4><h5 id="x">Impact</h5><h6>Next</h6><h6>Deep</h6><p>h1 in text</p>');
  });
});
