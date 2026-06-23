# Kura

This node covers the `kura/` workspace, a Rust service for low-latency cache meshes that replicate artifacts and metadata across peer nodes.

## Key Boundaries
- High-level architecture overview: `docs/architecture.md` — start here when onboarding or reasoning about how subsystems interact
- Entry points: `src/main.rs`, `src/app.rs`
- Public HTTP and gRPC surfaces: `src/http.rs`
- Storage, metadata, and replication state: `src/store.rs`, `src/state.rs`
- Runtime configuration and limits: `src/config.rs`, `src/constants.rs`
- Observability and analytics: `src/metrics.rs`, `src/telemetry.rs`, `src/analytics.rs`
- Peer TLS support: `src/peer_tls.rs`
- Peer sync bandwidth shaping: `src/bandwidth.rs`
- Operational assets: `docker-compose.yml`, `ops/`, `test/e2e/`, `spec/e2e/`
  - See `ops/AGENTS.md` for Helm, rollout helpers, and observability config boundaries
- Bazel build system: `MODULE.bazel`, `BUILD.bazel`, `bazel/` (toolchains + vendored deps), `Cargo.Bazel.lock`
- License and contribution terms: `LICENSE.md`, `CLA.md`, `cla/`

## Development
- Install tools from `kura/mise.toml` with `mise install` (Rust toolchain + Bazel)
- Bazel is the primary build and test path (it is what CI gates on). Use the Rust toolchain
  (`cargo`) only as a fallback when Bazel is unavailable:
  - Compile: `mise run bazel-compile` (host binary; fallback: `mise exec -- cargo build`)
  - Test: `mise run test-unit` (runs `bazel test //:kura_lib_test`; fallback: `mise exec -- cargo test`)
- Run `tuist bazel setup` to point Bazel at the closest Kura remote cache — it writes
  `kura/.bazelrc.tuist`. Do this when that file does not exist, or after you change physical location,
  so the build uses the nearest cache.
- Consider Kura work incomplete until `mise exec -- cargo clippy --all-targets -- -D warnings` passes
- After changing Rust deps (`Cargo.toml`/`Cargo.lock`) or merging `main`, repin the Bazel crate graph
  with `mise run bazel-repin` and commit `Cargo.Bazel.lock` (`mise run bazel-repin check` verifies the
  pin without rewriting it; a stale pin fails every Bazel CI job)
- Run the end-to-end suite with `docker compose build && mise exec -- shellspec`

## Maintenance Notes
- Keep `README.md` aligned with any protocol, configuration, or deployment changes
- Keep `LICENSE.md`, `CLA.md`, and `cla/` aligned with root licensing and contribution policy changes
- Keep `docs/architecture.md` in sync when changing how subsystems fit together (storage planes, replication model, traffic lifecycle, rollouts, observability surface)
- When changing cache protocol behavior, update the relevant shellspec coverage under `spec/e2e/`
- Keep Helm and local observability assets in `ops/` in sync with runtime configuration changes

## Rollout Safety
Kura runs as a multi-node mesh and is deployed with rolling updates, so pods of mixed versions run side by side mid-deploy. Every change must be safe under that overlap:
- Keep changes backward and forward compatible across one version skew. New nodes must interoperate with old nodes on the peer replication and membership protocols, and clients must keep working against either version. Prefer additive, negotiated changes (for example, offering HTTP/2 while still accepting HTTP/1) over flag-day switches.
- Never change the on-disk segment/blob format or the replication wire format in a way that an old peer cannot read. Segment and blob files are **append-only and reclaimed by unlink, never truncated**; code that maps them (`src/mmap.rs`) depends on this invariant for memory safety (truncation would SIGBUS live mappings). Do not introduce in-place rewrites or `set_len`/`ftruncate` on those files without revisiting the mmap serving path.
- Node-local optimizations (caching, mmap serving, readahead) must degrade gracefully to a known-good path and must not alter response bytes or headers, so a half-rolled fleet stays consistent.
- New dependencies must build in the release image (`Dockerfile`) without new system requirements, and config/limit changes must ship with matching Helm values in `ops/` so a rollout does not depend on out-of-band manual steps.
