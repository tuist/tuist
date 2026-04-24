# Processor

A dedicated Elixir/Phoenix application for server-side xcactivitylog processing.

## Architecture

The processor runs in the Tuist Kubernetes cluster alongside the main server. When a build archive is uploaded, the server's Oban `ProcessBuildWorker` picks the least-busy processor replica (by querying each pod's `GET /stats` endpoint) and sends an HMAC-signed webhook. The selected pod:

1. Downloads the archive from S3
2. Extracts the xcactivitylog and CAS metadata
3. Parses via a Swift NIF (using TuistXCActivityLog from the CLI)
4. Returns structured build data as JSON

Replica count, topology spread, and the headless Service that backs discovery are defined in the `infra/helm/tuist` chart (`processor-*.yaml` templates). Self-hosters can still point the server at a single external URL via `TUIST_PROCESSOR_URL` — in that mode the dispatcher skips discovery.

## HTTP endpoints

- `POST /webhooks/process-build` — HMAC-authenticated build processing webhook
- `GET /health` — liveness/readiness probe target
- `GET /stats` — returns `{"in_flight": N}`; the server's dispatcher uses this to pick the least-busy replica
- `GET /metrics` — Prometheus / PromEx metrics

## Development

```bash
cd processor
mix deps.get
mix phx.server  # Runs on port 4002
```

## Swift NIF

The native Swift NIF is in `native/xcactivitylog_nif/`. To build:

```bash
cd native/xcactivitylog_nif
swift build -c release
# Copy the built dylib to priv/native/
```

## Testing

```bash
mix test
```

## Deployment

- **Managed cloud:** the processor image is built and pushed alongside the server image in `.github/workflows/server-deployment.yml`, and the Helm chart's `processor.*` stanza rolls out two replicas per environment with soft anti-affinity across Kubernetes nodes.
- **Self-hosted:** set `processor.enabled: true` in `values.yaml` and provide `processor.webhookSecret` + `processor.secretKeyBase`, or enable `processor.managedSecrets` with an external-secrets store.
- **Legacy Kamal/NixOS path** (`config/deploy*.yml`, `platform/`) is preserved for reference during the cutover but no longer drives production deploys. The `.github/workflows/processor-*-deploy.yml` workflows are disabled accordingly.

## Webhook secret coupling

The server signs webhooks with `processor.webhook_secret` from its encrypted `priv/secrets/<env>.yml.enc`, and the processor verifies signatures using the `WEBHOOK_SECRET` env var set by the chart. Both ends must carry the same value — updating one without the other breaks dispatch until both rotate.
