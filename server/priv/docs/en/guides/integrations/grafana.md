---
{
  "title": "Grafana",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Visualise Tuist build, test, cache, and CLI metrics in Grafana via the Tuist app plugin."
}
---
# Grafana integration {#grafana}

Tuist exposes a Prometheus-compatible `/metrics` endpoint for every
account. The **Tuist** Grafana app plugin bundles two dashboards (Xcode
and Gradle) and a one-click scrape-config generator for Grafana Alloy or
Agent.

## Setup {#setup}

### 1. Install the plugin

On Grafana Cloud: *Administration → Plugins → search "Tuist" → Install*.
On self-hosted Grafana: `grafana-cli plugins install tuist-tuist-app`.

### 2. Create an account token

```bash
tuist account tokens create <your-handle> \
  --scopes account:metrics:read \
  --name grafana
```

Store the returned `tuist_<id>_<hash>` value in a secret manager — Tuist
does not show it again.

### 3. Configure the plugin

In *Administration → Plugins → Tuist → Configuration*, fill in:

- **Server URL** — `https://tuist.dev`, or your self-hosted URL.
- **Account handle** — the account you want to scrape.
- **Metrics token** — the `tuist_...` value from step 2.
- **Scrape interval** — defaults to `15s` (minimum `10s`).

Save. A collector snippet appears.

### 4. Deploy the scrape collector

Paste the snippet into your Alloy or Agent config. Expose the token as
`TUIST_METRICS_TOKEN` wherever your collector runs — a host env var for
self-hosted Alloy, or a secret in Grafana Cloud Fleet Management for
Cloud users with hosted Alloy.

### 5. Open the dashboards

The plugin installs **Tuist Xcode** and **Tuist Gradle** dashboards. Pick
the project from the top-of-page dropdown.

## Source

<https://github.com/tuist/tuist/tree/main/grafana>
