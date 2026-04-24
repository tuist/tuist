# Processor

A dedicated Elixir/Phoenix application for server-side xcactivitylog processing.

## Architecture

The processor runs on a Hetzner dedicated server and accepts webhooks from the main Tuist server. When a build archive is uploaded, the server's Oban worker sends a webhook to the processor, which:

1. Downloads the archive from S3
2. Extracts the xcactivitylog and CAS metadata
3. Parses via a Swift NIF (using TuistXCActivityLog from the CLI)
4. Returns structured build data as JSON

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

## Dashboards

The Grafana dashboard for this service is checked in at [`infra/grafana-dashboards/processor-service.json`](../infra/grafana-dashboards/processor-service.json) and kept in sync with Grafana Cloud via Git Sync. See `infra/AGENTS.md` for the editing workflow.
