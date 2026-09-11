# Kura

This node covers the `kura/` workspace, a Rust service for low-latency cache meshes that replicate artifacts and metadata across peer nodes.

## Key Boundaries
- High-level architecture overview: `docs/architecture.md` — start here when onboarding or reasoning about how subsystems interact
- Entry points: `src/main.rs`, `src/app.rs`
- Startup recovery: `src/startup.rs` owns the bootstrap health listener, progress watchdog and process signals. Keep cache and peer traffic disabled until exclusive store recovery completes; transfer the existing bound socket into the serving listener. Eviction scan pages and commits advance recovery progress, never a timer heartbeat. Keep interruption typed through cleanup so a requested shutdown exits successfully without reporting startup failure; preserve live reverse pointers until their targets are deleted in the same batch.
- Public HTTP and gRPC surfaces: `src/http.rs`
- Negotiated Xcode compilation-cache transfers: `docs/client-chunking.md`, `../cas-plugin/`. Reuse the existing split/splice protocol and reader-first rollout. The optional `tuist-inline-max-bytes` wildcard hint must preserve explicit inline requests and ordinary full-blob reads for existing clients.
- Xcode compiler restore coverage lives in `spec/e2e/xcode_chunking_spec.sh`, with readable fixture assets in `spec/fixtures/xcode-chunking/`. Generate the fixture with Tuist's `Project.swift` and `Tuist.swift` manifests, not another project generator. It runs on Apple silicon with `KURA_E2E_XCODE=1` and local Kura; it must skip without starting processes on other hosts. Keep end-to-end coverage in ShellSpec rather than standalone Python drivers.
- Clang fault coverage lives in `spec/e2e/clang_chunking_spec.sh` and `spec/fixtures/clang-chunking/`. Its loopback-only Rust request gate forwards to real Kura, interrupts uploads, or holds chunk reads while ShellSpec deletes only the test's isolated namespace. This proves client fallback after remote dependency loss, not a server retention lease. Keep fault injection out of production handlers and assert that the fault actually occurred.
- Storage, metadata, and replication state: `src/store.rs`, `src/state.rs`
- Backfill peer catch-up walker (the pass pipeline every catch-up path runs on): `src/backfill/` — `claims.rs` (shared exclusive-claim set), `lifecycle.rs` (per-peer pass scheduling machine, for peers still on push), `pass.rs` (one pass's pipelined list/fetch/apply stages), `window.rs` (watermark/horizon and capacity rules)
- Pull replication (`docs/replication-design.md`): `src/sync/` — `feed.rs` (the bounded arrival feed a sibling reads forward), `replica.rs` (intra-region link: snapshot, backward pass, forward reads), `region.rs` (inter-region link: ascending origin-filtered reads from a per-region watermark, gateway only), `roles.rs` (who pulls from whom, from the membership view and published roles), `coordinator.rs` (opens/closes links, readiness and drain terms)
- Runtime configuration and limits: `src/config.rs`, `src/constants.rs`
  - Multipart session admission follows `src/memory/mod.rs` headroom and pressure unless explicitly overridden; `src/store.rs` owns durable slot accounting and the one-second, capacity-bounded start queue. Use the FIFO admission turn and dedicated pressure-tier signal; preserve cancellation cleanup through blocking record writes and expose queue outcomes/depth. Keep occupied-slot and effective-capacity metrics aligned with admission.
- Observability and analytics: `src/metrics.rs`, `src/telemetry.rs`, `src/request_observability.rs`, `src/analytics.rs`
  - Artifact upload readers (`src/utils.rs`, staged and inline handlers in `src/http.rs`) keep incoming-body failures separate from storage I/O. Classify typed disconnects as 499, malformed framing as 400, and incoming-body timeouts as 408; unknown body failures and storage faults remain 5xx. Record rejected reads in domain error counters and preserve bounded causes in upload completion extensions. Client failures use a separate warning limiter from server faults. Protocol and cleanup coverage lives in `src/http/upload_tests.rs` and `spec/e2e/upload_errors_spec.sh` (CI clients shard). Public and peer HTTP entry points wrap concrete Hyper Incoming bodies to reject a swallowed reset without END_STREAM; generic body end-stream hints are not sufficient for this check. The HTTP/2 test must exercise Hyper Incoming to guard both the end-stream check and the typed h2 downcast across dependency upgrades.
- Optional fixed connectivity telemetry: [`src/connectivity/AGENTS.md`](src/connectivity/AGENTS.md); dedicated thread/runtime, no startup/readiness dependency, ordinary JSON logs.
- Control-plane mesh membership (enrollment, mesh heartbeat, managed peers sync, recovery re-enrollment): `src/enrollment.rs`, `src/mesh_heartbeat.rs`
- Mesh and usage HTTP timeout policy: `src/control_plane_http.rs`, used by `src/mesh_heartbeat.rs` and `src/usage.rs` — 3 seconds for connection setup including DNS, within a 5-second total request deadline. Enrollment, registration, analytics, and authentication configure their clients separately. Keep the initial peer-view serving gate intact.
- Peer TLS support: `src/peer_tls.rs`
- Peer sync bandwidth shaping: `src/bandwidth.rs`
- Operational assets: `docker-compose.yml`, `ops/`, `test/e2e/`, `spec/e2e/`
  - `test/e2e/multipart-admission/run.py` launches an isolated native server for the multipart admission ShellSpec.
  - See `ops/AGENTS.md` for Helm, rollout helpers, and observability config boundaries
- Bazel build system: `MODULE.bazel`, `BUILD.bazel`, `.bazelrc`, `bazel/` (toolchains + vendored deps); the crate graph is resolved from `Cargo.toml`/`Cargo.lock` by rules_rs
- Rust test targets use `rust_junit_test` from `bazel/rust_junit_test.bzl` instead of `rust_test`. Stable libtest does not write JUnit, so the macro wraps the compiled test binary in `bazel/tools/rust_libtest_junit.sh`, which parses libtest's text output and writes JUnit to `$XML_OUTPUT_FILE`. Without this, Bazel synthesizes a one-case-per-target report and Tuist collapses each target to a single row. Keep this in place when adding new `#[test]` modules; the macro is a drop-in for `rust_test`.
- License and contribution terms: `LICENSE.md`, `CLA.md`, `cla/`

## Development
- Install tools from `kura/mise.toml` with `mise install` (Rust toolchain + Bazel)
- Bazel is the primary build and test path (it is what CI gates on). Use the Rust toolchain
  (`cargo`) only as a fallback when Bazel is unavailable:
  - Compile: `mise run compile` (fallback: `mise exec -- cargo build`)
  - Test: `mise run test-unit` (runs `bazel test //...`; fallback: `mise exec -- cargo test`)
  - Clippy: `mise run clippy` (runs the rules_rust clippy aspect over `//...`, warnings as errors;
    fallback: `mise exec -- cargo clippy --all-targets -- -D warnings`)
  - Format: `mise run format` fixes files in place (cargo fmt); `mise run format -- --check`
    verifies only (rules_rust rustfmt aspect, what CI runs)
- If you have access to the `tuist/kura` project on Tuist, run `tuist bazel setup` to point Bazel at
  the closest Kura remote cache (it writes `kura/.bazelrc.tuist`); re-run it after changing physical
  location. Without access, skip it — Bazel builds fine against the local cache.
- Synchronize inline write races with the test-only `FailpointAction::Pause` and explicit replicated versions; local versions are stamped at staging, so sleeps between request starts cannot guarantee distinct versions.
- Synchronize cancellation tests with explicit blocking-commit hooks; fixed scheduler-yield counts cannot guarantee that disk work has started or finished on CI.
- The two-source backfill capacity E2E checks readiness, completion, full-ring retention, and bounded evictions. Exclusive claims and independent fetchers can leave holes in the retained recency band, so do not assert fixed artifact identities; ordered marginal-trade behavior is covered by the backfill Rust unit tests.
- Consider Kura work incomplete until `mise run clippy` passes (fallback when Bazel is unavailable:
  `mise exec -- cargo clippy --all-targets -- -D warnings`)
- rules_rs resolves the Bazel crate graph directly from `Cargo.toml`/`Cargo.lock` on each build, so
  changing Rust deps just updates `Cargo.lock` as usual and Bazel picks it up on the next build
- Run the end-to-end suite with `docker compose build && mise exec -- shellspec`

## Maintenance Notes
- Keep `README.md` aligned with any protocol, configuration, or deployment changes
- Keep `LICENSE.md`, `CLA.md`, and `cla/` aligned with root licensing and contribution policy changes
- Keep `docs/architecture.md` in sync when changing how subsystems fit together (storage planes, replication model, traffic lifecycle, rollouts, observability surface)
- When changing cache protocol behavior, update the relevant shellspec coverage under `spec/e2e/`
- Keep Helm and local observability assets in `ops/` in sync with runtime configuration changes
- When adding, renaming, or changing the meaning of a metric in `src/metrics.rs`, update
  `infra/grafana-dashboards/tuist-kura-details.json` (`Tuist Kura / Details`) in the same change. That
  dashboard is meant to cover every `kura_*` family the runtime exports, so an unlisted metric is
  effectively invisible to whoever is debugging next. Add the panel to the row for its subsystem, and
  put the operational interpretation in the panel description rather than in the Prometheus HELP text.
  Note that counters scrape with a doubled suffix (a counter registered as `foo_total` is served as
  `foo_total_total`) — panels must query the scraped name, not the name in the source.

## Rollout Safety
Kura runs as a multi-node mesh and is deployed with rolling updates, so pods of mixed versions run side by side mid-deploy. Every change must be safe under that overlap:
- Keep changes backward and forward compatible across one version skew. New nodes must interoperate with old nodes on the peer replication and membership protocols, and clients must keep working against either version. Prefer additive, negotiated changes (for example, offering HTTP/2 while still accepting HTTP/1) over flag-day switches.
- Never change the on-disk segment/blob format or the replication wire format in a way that an old peer cannot read. Segment and blob files are logically append-only and reclaimed by unlink, never truncated. Active segments may receive reserved, non-overlapping positioned writes without the operating system's append flag. A failed or cancelled reservation may leave a bounded hole, but writers must never overwrite a committed range, reuse an uncertain tail offset, or truncate the file. Rotation takes the exclusive segment barrier before publishing a new active segment. Memory-mapped serving remains safe because manifests expose only fully written committed ranges and existing mappings may observe file growth; truncation could crash a process through a live mapping. Do not introduce in-place rewrites or `set_len`/`ftruncate` on those files without revisiting `src/mmap.rs` and the reservation, synchronization, and rotation protocol.
- Node-local optimizations (caching, mmap serving, readahead) must degrade gracefully to a known-good path and must not alter response bytes or headers, so a half-rolled fleet stays consistent.
- New dependencies must build in the release image (`Dockerfile`) without new system requirements, and config/limit changes must ship with matching Helm values in `ops/` so a rollout does not depend on out-of-band manual steps.

- Private runner Kura uses the ordinary managed StatefulSet rollout and account mesh. Both replicas continuously enqueue and consume replication traffic, with initial backfill after a restart; the standby is not read-only. The stable private gateway pins reads and writes to the selected primary. Replication remains asynchronous; Kubernetes readiness alone does not prove a drained outbox or complete backfill. See `infra/kura-controller/private-runner-rollouts.md`.

## Bazel timelines
- `src/reapi/bep.rs` keeps its bounded invocation summary and separately delivers the `command.profile.gz` CAS reference and action diagnostics through `src/bazel_test_artifacts.rs`. The delivery worker reserves memory before reading artifacts. Profiles are limited to 32 MiB compressed; diagnostic streams use bounded range reads that retain their first and last 16 KiB. Only project-scoped CAS artifacts are read; arbitrary profile URLs and local paths are never fetched.
- `tuist bazel setup` enables JSON profiles, disables profile event merging, includes target/output identifiers and uses the remote BEP artifact uploader. The server retains profile intervals and diagnostics for 90 days.
- `spec/e2e/bazel_timeline_spec.sh` runs real C++ builds against configured local Kura and Tuist endpoints, compares every API interval to the original profile, verifies more than 32 compiler actions and native counters, and checks the failed-action log. Configure `TUIST_TIMELINE_SERVER_URL`, `TUIST_TIMELINE_KURA_URL`, `TUIST_TIMELINE_PROJECT`, and `TUIST_TIMELINE_TOKEN_FILE` to run it.

- Timeline action and profile admission uses separate bounded nonblocking queues, isolated from test delivery. Action diagnostics are batched by account/project, at most 32 per signed request; a missing batch endpoint falls back to the legacy single-action protocol during rollout. Overflow is best effort and increments source-specific dropped metrics. Profile/action delivery outcomes use `bazel_profile` / `bazel_action` analytics kinds, including size rejections.
