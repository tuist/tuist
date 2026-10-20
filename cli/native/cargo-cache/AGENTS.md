# Tuist Cargo compilation cache

This is Tuist's internal Cargo/Rust/C/C++ cache runtime, restored from the last pre-Swift-replacement snapshot (`e40ef61c9c^`). Generated upstream changelogs are intentionally excluded. The public entry point
is `tuist cargo`; never resolve an independent cache executable. All seven model
packages are local sources. Preserve LICENSE, NOTICE and the original revision
recorded there, and keep model versions reviewable when changing copied code.

## Storage and transport

- Remote caching uses Kura's existing Bazel Remote Execution API: Capabilities,
  Action Cache, CAS FindMissingBlobs and ByteStream. No alternative Kura HTTP
  protocol, cache server, Phoenix upload API or new object-storage plane.
- `remote_reapi.rs` preserves algorithm-tagged local action/input identities.
  Every remote CAS digest is SHA-256 of actual content. Deterministic serialized
  Command/Action messages provide domain-separated indexes for local blob
  identities, compilation actions and prediction selectors; never relabel a
  BLAKE3 hash as SHA-256.
- Upload and verify blobs before publishing indexes. Compilation ActionResults
  carry their entire discovered output closure as SHA-256 references, including
  directories, compiler metadata and captured stdout/stderr. Missing/corrupt
  objects must miss, never become a compiler hit.
- Prediction manifests remain speculative. REAPI does not provide conditional
  writes, global CAS or compilation promises. Stale-snapshot checks are advisory;
  concurrent last-writer updates may lose predictions, not authorize hits.
  Unsupported pack/promise/batch extensions use the copied model's ordinary
  fallback paths. Do not invent remote guarantees from local locks.
- Endpoints and refreshed private tokens come from Tuist's existing discovery
  and authentication services. The REAPI instance is the project handle;
  `x-tuist-account-handle` carries the account on every RPC. Never put the full
  account/project handle in `instance_name`, which would authorize a different
  project. Local/index identity retains the full handle.
- Respect existing network settings: TLS roots and optional certificate bundles,
  environment CONNECT proxies and NO_PROXY, bounded transfers/read retries,
  overall deadlines and the copied model's session read-stall budget.

## Runtime semantics

- `tuist_main.rs` ships only `tuist-cargo-cache`; its private protocol probe is
  `__tuist_protocol`. Detached automatic collectors use `__tuist_gc_automatic`
  with Tuist-only configuration; never forward cleanup to Cargo. Cargo arguments
  bypass the legacy application parser.
- Swift uses the shared `cargoNative` cache category with a 30-second session heartbeat; shared retention can reclaim only idle project roots. Native GC owns its nested action/blob/lock lifecycle and receives `CacheBudget.supportCaches` as its maximum total size on managed runners. Never reuse the Swift action/blob entry glob for this layout. The Swift cache remains the fallback when the sibling is absent or protocol-incompatible.
- `load_for_tuist` ignores independent global/workspace cache policy. Swift clears
  inherited `TUIST_CARGO_CACHE_*` settings, sets native policy, and isolates local
  state by server, project and transport version. These are internal settings,
  not a `[cargo]` configuration surface.
- Preserve Cargo planning, target directories, incremental settings, toolchains,
  jobserver descriptors, argument ordering, terminal output and exit status.
  Never rerun Cargo after it may have performed work. Cache setup failures before
  execution must safely fall back; guard fallback with successful Cargo spawn,
  not wrapper completion. Remote setup failures retain isolated local caching.
  Preserve Cargo's progress environment rather than forcing the copied model's
  plain-output preference onto Cargo.
- Keep the complete input tracking, local CAS, predictions, prefetching, Rust/C/C++
  and build-script model. Neither a lockfile nor a prediction proves a hit.
- `tuist_observer.rs` records actual compiler executions, not restores or opaque
  wrapper calls. Bypassed executions forward stderr live while retaining at most
  2 MiB for diagnostics; queries and absent observers retain direct execution.
  It never authenticates or uploads. Stats version 5 supplies bounded aggregates. `public_cache_report.rs` is a separate allowlisted inspection boundary, not a dump of private agent events: report actual keyed decisions, per-request cache-agent durations, real SHA-256 CAS operation outcomes, and closure references already observed without extra RPCs. Build-script executions gain a public key only after declared-input validation and successful local result storage; hits supply an explicit adapter annotation. Never identify an adapter by suffix guessing or turn script actions into rustc observations. Its private invocation-local NDJSON files are capped at 8 MB, use mode 0600, and use a bounded 512-record writer queue with a two-second shutdown flush. Signal queue pressure, write failure or truncation rather than affecting Cargo; do not drop records merely because another request is writing. Never infer hit origin, transfer completion from presence, or measurements from cumulative counters; estimates are not measured wall-clock savings.
- Executable/link caching remains bypassed until the retained macOS divergence
  is explained and qualified. Preserve the implementation, but do not enable
  known-unqualified output restores just to claim full coverage.

## Validation

Build with `cargo build --locked --manifest-path
cli/native/cargo-cache/Cargo.toml -p tuist-cargo-cache --bin tuist-cargo-cache`.
Keep generated outputs in ignored `target/`. The feature-gated
`tuist-cargo-cache-model` binary exists only for retained integration fixtures;
never include it in releases or runtime discovery. Use `--features model-tests`
when running those fixtures. Test the copied model and REAPI
adapter. Linux cross-compilation uses the pinned Zig/cargo-zigbuild tools in `mise.toml`; release Rust remains pinned by `cas-plugin/mise.toml`. Both architectures must pass the ELF static/architecture check in `mise/utilities/build_cargo_cache_linux.sh`. `--test tuist_runtime` tests the shipped entry without `model-tests`,
including actual cleanup, pre-execution fallback and incremental bypass warnings.
See `PARITY.md` for the pinned comparison and intentional gaps. Then test actual
cold, clean-worker, local, invalidation, corruption,
authorization, unavailable-server and verification scenarios. A successful
single-host fixture is not cross-toolchain or sustained resource qualification.
