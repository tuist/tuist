# Tuist Grafana app plugin

Visualise per-account build, test, cache, and CLI metrics from Tuist inside
Grafana.

The plugin bundles:

- A **configuration page** that collects your Tuist server URL, account
  handle, `account:metrics:read` token, and target Prometheus datasource.
- A **collector snippet generator** that emits a ready-to-paste Grafana
  Alloy / Agent scrape config for the Tuist `/metrics` endpoint.
- Two dashboards — **Tuist Xcode** and **Tuist Gradle** — each organised
  into Overview / Builds / Tests / Cache rows that mirror the Tuist
  dashboard's project pages.

The plugin itself does not scrape. Grafana Alloy (or Agent) scrapes the
Tuist `/metrics` endpoint and remote-writes to the Prometheus datasource
configured here.

## Getting started

Install the plugin, open it in Grafana, and walk through the
**Configuration** tab. For the full integration guide — including a
reference of every metric Tuist exposes — see the [Tuist Grafana
integration docs](https://docs.tuist.dev/en/guides/integrations/grafana).

## Source

<https://github.com/tuist/tuist/tree/main/grafana>
