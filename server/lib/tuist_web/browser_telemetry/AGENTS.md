# Browser telemetry enrichment

`Enrichment` is the pure payload boundary used by `BrowserTelemetryPlug`.
It classifies reported same-origin URLs using router metadata, separates auth
and challenge pages, overwrites reserved context, and preserves measurements.

- Authentication and Ray IDs come from the gateway, never browser metadata.
- URL, session and navigation IDs remain browser-reported. Metadata eligibility
  and an authenticated collector request do not establish humanity.
- Keep automation unknown until evidence-backed correlation exists. Do not
  introduce browser-version, viewport or ASN exclusions here.
- Add no user/account identity or Loki stream labels for correlation IDs.
- Update the schema contract, paused rules and staged rollout together in
  `infra/helm/k8s-monitoring/browser-rum.md`; update `server/data-export.md`
  whenever telemetry collection changes.

Parent context: `server/lib/tuist_web/AGENTS.md`.
