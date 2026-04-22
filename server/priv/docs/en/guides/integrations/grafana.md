---
{
  "title": "Grafana",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Visualise Tuist build, test, cache, and CLI metrics in Grafana via the Tuist app plugin."
}
---
# Grafana integration {#grafana}

Tuist exposes a Prometheus-compatible `/metrics` endpoint for every account,
plus a Grafana app plugin that makes consuming those metrics a one-click
experience: install the plugin, paste a token, and you get two curated
dashboards (Xcode and Gradle) plus a ready-to-paste Grafana Alloy / Agent
scrape config.

The full metric vocabulary — counter and histogram names, label sets, and
bucket schedules — is documented in the
[Metrics reference](/en/references/metrics).

## How it fits together {#architecture}

```
tuist CLI / CI runs                     Tuist server
      │                                     │
      └───► /api/analytics ─────────────────┤
                                            ▼
                             `Tuist.Metrics` ETS aggregator
                                            │
                                            ▼
                           GET /api/accounts/:handle/metrics
                                            ▲
                                            │  scrape (Alloy/Agent)
                                            │
                                     Your Prometheus
                                            │
                                            ▼
                                        Grafana
                                            │
                                    Tuist plugin dashboards
```

The plugin itself **does not scrape**. Grafana Alloy (or Grafana Agent) does,
then remote-writes to your Prometheus. The plugin's role is to
(a) collect the config, (b) render the scrape snippet for your collector,
and (c) ship dashboards that query what was written.

## Setup {#setup}

### 1. Install the plugin

The plugin is published as **Tuist** on the public Grafana catalogue. On
Grafana Cloud, find it under *Administration → Plugins*, search for
"Tuist", and click **Install**. On self-hosted Grafana, the same catalogue
entry is available via `grafana-cli plugins install tuist-tuist-app`.

### 2. Mint a metrics token

From the Tuist CLI, create an account token carrying the
`account:metrics:read` scope:

```bash
tuist account tokens create <your-handle> \
  --scopes account:metrics:read \
  --name grafana-cloud
```

Store the returned `tuist_<id>_<hash>` value in your secret manager — the
Tuist server never shows it again.

### 3. Configure the plugin

Open the plugin in Grafana (*Administration → Plugins → Tuist*) and go to
the **Configuration** tab. Fill in:

- **Server URL** — `https://tuist.dev`, or your self-hosted URL.
- **Account handle** — the user or organisation whose metrics you want
  to scrape.
- **Metrics token** — the `tuist_...` value from the previous step.
- **Prometheus datasource** — the datasource Alloy will remote-write
  into.
- **Scrape interval** — defaults to `15s`. Stay above `10s` (the
  server rate-limits one scrape per 10 seconds per account).

Hit **Save**. A **Collector snippet** panel appears with a Grafana Alloy
configuration block parameterised with your settings.

### 4. Deploy the scrape collector

Paste the snippet into your Alloy (or Agent flow-mode) config and export
the token through `TUIST_METRICS_TOKEN` on the collector's environment —
don't commit the raw token into config files.

```bash
export TUIST_METRICS_TOKEN="tuist_..."
alloy run config.alloy
```

Reload the collector. Within one scrape interval Prometheus sees the
`tuist_*` series start filling in.

### 5. Open the dashboards

The plugin registers two dashboards automatically:

- **Tuist Xcode** — builds, tests, and binary cache activity for
  Xcode-built projects.
- **Tuist Gradle** — the same for Gradle/Android builds.

Each dashboard groups panels into rows that mirror the Tuist project
dashboard's own pages: Overview, Builds, Tests, and (for Xcode) Cache.

> [!NOTE] SINGLE PROJECT AT A TIME
> <!-- -->
> The bundled dashboards expect a single `project` at a time via the
> top-of-page dropdown. If you scrape multiple accounts / projects into
> the same Prometheus, pick the right one there.

## Rate limits and quotas {#rate-limits}

The scrape endpoint is rate-limited to roughly **1 request per 10 seconds
per account**. A small burst (3 requests) is allowed so Alloy jittering at
startup doesn't immediately trip the limit. Beyond that, Tuist replies
with `HTTP 429` and a `Retry-After: 10` header; every Prometheus-compatible
scraper honours it.

## Troubleshooting {#troubleshooting}

- **Dashboards show "No data"** — confirm Prometheus is actually
  scraping at `/targets`. If `up` is 0, check bearer-token plumbing and
  the account handle.
- **`tuist_cli_invocations_total_total` shows up** — you're looking at
  a pre-fix series from an older Tuist server version. Prometheus will
  expire it at the retention cutoff; no action needed.
- **`401 Unauthorized`** — token revoked or scope missing. Mint a new
  one with `account:metrics:read`.
- **`403 Forbidden`** — the token's account doesn't match the
  `account_handle` in the scrape URL. Check that the token was minted
  for the right account.

## Source

The plugin source lives at
<https://github.com/tuist/tuist/tree/main/grafana>. Contributions are
welcome.
