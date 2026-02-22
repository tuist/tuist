# Infrastructure

This node covers infrastructure and deployment assets under `infra/`.

## Components

### Grafana Alloy (`grafana-alloy/`)
Prometheus metrics collector that scrapes metrics from Tuist server instances and forwards them to Grafana Cloud.

- `config.alloy` - Alloy configuration for scraping production, canary, and staging instances
- `Dockerfile` - Container image for deploying Alloy on Render

**Scraped Targets:**
- Production: `tuist:9091`
- Canary: `tuist-canary:9091`
- Staging: `tuist-staging:9091`

**Metrics Destination:** Grafana Cloud Prometheus (EU West 2)

### Registry Router (`registry-router/`)
Cloudflare Worker that geo-routes requests to `registry.tuist.dev` to the nearest healthy cache origin based on the requester's continent. Replaces the Cloudflare Load Balancing setup.

- `wrangler.toml` - Worker configuration, routes, KV binding, and cron trigger
- `src/index.ts` - Geo-routing logic, health-check cron handler, and failover
- `package.json` - Project manifest

**Origins:**
- `cache-eu-central.tuist.dev`
- `cache-eu-north.tuist.dev`
- `cache-us-east.tuist.dev`
- `cache-us-west.tuist.dev`
- `cache-ap-southeast.tuist.dev`
- `cache-sa-west.tuist.dev`

**Health Checks:** Cron Trigger every 60s writes health state to Workers KV (TTL 120s). Missing keys are treated as healthy (fail-open).

**Adding/Removing Regions:** Update the `ROUTES` table in `src/index.ts` and deploy with `wrangler deploy`.

## Deployment
Infrastructure components are deployed on Render as private services. Configuration changes should be tested in staging before production.

The Registry Router is deployed as a Cloudflare Worker via `wrangler deploy` from `infra/registry-router/`.

## Environment Variables
The Alloy service requires:
- `PROMETHEUS_USERNAME` - Grafana Cloud username
- `PROMETHEUS_TOKEN` - Grafana Cloud API token
