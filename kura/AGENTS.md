# Kura

This node covers the `kura/` workspace, a Rust service for low-latency cache meshes that replicate artifacts and metadata across peer nodes.

## Key Boundaries
- Entry points: `src/main.rs`, `src/app.rs`
- Public HTTP and gRPC surfaces: `src/http.rs`
- Storage, metadata, and replication state: `src/store.rs`, `src/state.rs`
- Runtime configuration and limits: `src/config.rs`, `src/constants.rs`
- Observability and analytics: `src/metrics.rs`, `src/telemetry.rs`, `src/analytics.rs`
- Peer TLS support: `src/peer_tls.rs`
- Operational assets: `docker-compose.yml`, `ops/`, `test/e2e/`, `spec/e2e/`

## Development
- Install tools from `kura/mise.toml` with `mise install`
- Run unit tests with `mise exec -- cargo test`
- Run the end-to-end suite with `docker compose build && mise exec -- shellspec`

## Maintenance Notes
- Keep `README.md` aligned with any protocol, configuration, or deployment changes
- When changing cache protocol behavior, update the relevant shellspec coverage under `spec/e2e/`
- Keep Helm and local observability assets in `ops/` in sync with runtime configuration changes
