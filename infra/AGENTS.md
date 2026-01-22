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

## Deployment
Infrastructure components are deployed on Render as private services. Configuration changes should be tested in staging before production.

## Environment Variables
The Alloy service requires:
- `PROMETHEUS_USERNAME` - Grafana Cloud username
- `PROMETHEUS_TOKEN` - Grafana Cloud API token
