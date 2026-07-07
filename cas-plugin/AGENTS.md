# tuist-cas-plugin

A Rust `cdylib` implementing the LLVM CAS plugin ABI (`llcas_*`, v0.1) that Xcode's compilation caching loads via `COMPILATION_CACHE_PLUGIN_PATH`. It wraps Xcode's bundled `libToolchainCASPlugin.dylib` for local storage, hashing, and digest handling, and adds Tuist-remote (kura) read-through and write-through on top.

## Why it exists

Xcode's own remote-caching mode (`COMPILATION_CACHE_REMOTE_SERVICE_PATH`, a gRPC socket served by the `tuist cache start` daemon) is net-negative on deep module graphs: the remote choreography inside Apple's closed plugin stalls in 30-50s bursts, taking a 274s no-cache build to 325-445s even with all cache hits served in ~2ms. This plugin bypasses that path entirely: the build system runs in its fast plugin-local mode (no remote service path configured), and all remote traffic happens inside this plugin. Measured on the same fixture: warm remote 113.6s against a 105.5s local-replay floor (~8s over, after the kura serving fixes narrowed an earlier ~145s), and 50.4s vs 87.8s no-cache on a shallow-graph app project, which runs at its 50.1s floor.

## Architecture

- `src/upstream.rs` - dlopen table for the wrapped Apple plugin. Symbols are split required/optional: Apple's plugin does not export `llcas_cas_store_from_filepath`, `llcas_loaded_object_export_data_to_filepath`, or the on-disk size/prune entry points, so those have fallback implementations in `lib.rs`.
- `src/lib.rs` - the exported `llcas_*` surface. Every string returned to the client is allocated by this crate (the client frees through our `llcas_string_dispose`); upstream strings are copied and released immediately. Read-through: action-cache gets and object loads probe the local CAS first, fetch from the remote on miss, store locally, and answer. Write-through happens ONLY on `llcas_actioncache_put_for_digest`: a background pool walks the value object's ref graph and uploads it. Do not intercept `llcas_cas_store_object` for uploads: the compiler stores input-file ingests and dependency-scan trees on every build (warm included), and mirroring those re-uploads the world (~21k redundant uploads per warm build when we tried).
- `src/prefetch.rs` - a shared worker-pool primitive used twice: the prefetcher (walks ref graphs after an entry hit so compiler frontends find objects locally instead of paying a round trip per node along deep module chains; droppable on dispose) and the uploader (drains fully on dispose, since queued uploads must not be lost when short-lived compiler processes exit).
- `src/remote.rs` - kura HTTP client. Artifacts live at `/api/cache/cas/{id}`: action-cache entries at `tcp0-v-<key digest hex>` (body: raw value-object digest bytes), object nodes at `tcp0-o-<digest hex>` (body: zstd-compressed `"TCP0" | u32 ref_count | (u32 len | digest bytes)* | data`). Everything fetched is marked already-uploaded so it is never re-posted.

## Hard-won invariants

- Panics must never cross the `extern "C"` boundary or skip worker bookkeeping. ureq 2.x can panic while returning a connection to its pool; both HTTP entry points run under `catch_unwind`, the worker loop decrements its in-flight counter even when the job panics (a skipped decrement wedges the drain-on-dispose and hangs the build service), and the async paths guarantee the client callback fires exactly once.
- The plugin and builtin caching modes use different local CAS directories (`CompilationCache.noindex/plugin` vs `/builtin`); numbers from one do not carry to the other.
- `llcas_cas_dispose` must stop/drain the worker pools before disposing the upstream CAS and freeing state - workers hold references to both.

## Configuration (environment)

The plugin runs in one of two modes. **Proxy mode** (`TUIST_CAS_PROXY_SOCKET` set) delegates all remote work to the per-machine proxy over a unix socket; this is the productized path and the one the benchmarks measure. **Direct mode** (no proxy socket, `TUIST_CAS_REMOTE_GRPC_URL` set) opens a REAPI channel per compiler process; kept for benchmarks. Without either, the plugin is a pure passthrough.

- `TUIST_CAS_UPSTREAM_PLUGIN` - path to the wrapped plugin (default: `$DEVELOPER_DIR/usr/lib/libToolchainCASPlugin.dylib`).
- `TUIST_CAS_PROXY_SOCKET` - unix socket of the per-machine proxy; when set the plugin runs in proxy mode.
- `TUIST_CAS_ACCOUNT`, `TUIST_CAS_PROJECT` - the `account/project` this build's cache belongs to, used to declare the instance to the proxy. Lower precedence than the `tuist-instance` plugin option (see below); when neither is present the proxy falls back to its `cas_path -> instance` registry.
- `TUIST_CAS_REMOTE_GRPC_URL`, `TUIST_CAS_TOKEN` - REAPI endpoint + bearer. In proxy mode these configure the proxy (one endpoint/token, many instances); in direct mode they configure this process.
- `TUIST_CAS_UPLOAD` (default true) - upload policy from `xcodeCache(upload:)`. When false the plugin still serves remote read hits but publishes nothing (no value graphs to proxy or remote).
- `TUIST_CAS_PREFETCH` (default 24), `TUIST_CAS_POOL` (default 16) - worker pool sizes.
- `TUIST_CAS_LOG` - append per-process stats (hits, misses, prefetched, GET/POST latency) on dispose.

## Configuration (plugin options)

Xcode passes `-cas-plugin-option <name>=<value>` flags to the plugin via `llcas_cas_options_set_option`, sourced from build settings (`tuist generate` bakes them into `OTHER_SWIFT_FLAGS`). Unlike the environment, these reach **every** compiler frontend — including an Xcode ⌘B build that carries no CLI environment — which is how the plugin learns its instance without the CLI.

- `tuist-instance=<account/project>` - the instance this build routes to; takes precedence over `TUIST_CAS_ACCOUNT`/`TUIST_CAS_PROJECT`. `tuist-*` options are consumed here and never forwarded to the wrapped plugin.

## Build and use

```sh
cargo build --release
xcodebuild ... \
  COMPILATION_CACHE_ENABLE_CACHING=YES COMPILATION_CACHE_ENABLE_PLUGIN=YES \
  COMPILATION_CACHE_PLUGIN_PATH=$PWD/target/release/libtuist_cas_plugin.dylib
```

Requires `SWIFT_ENABLE_EXPLICIT_MODULES` and works with Xcode 26.x. Not yet wired into the CLI; see the introducing PR for the productization follow-ups (dylib distribution, CLI env wiring, auth token minting).

## Kura placement (on-host vs PN node)

The proxy can point at kura wherever it runs; two placements were measured on the CLI fixture (8-core runner VM, all kura perf fixes):

- **On-host** — one kura per runner Mac (served to the VM over the loopback/bridge). Warm build **113.6s** (median of 5). This placement is **not bandwidth-constrained**: the bridge measured 2.34 GB/s and loopback is effectively unbounded, so a very cache-heavy build or many concurrent frontends never contend on a shared NIC.
- **PN node off-host** — a shared kura on a nearby Private Network fleet node (0.89ms). Warm build **118s** (median of 3) — only ~5s slower, since sub-ms LAN is the same latency regime as the bridge. Simpler operationally (one kura per region instead of per-Mac), at the cost of a shared node NIC that could bottleneck under enough concurrent runners.

Build time only diverges at true WAN latency (66ms → warm ~0.76x of no-cache but ~65s over the local floor, since the ~2.5GB namespace fetch costs real round-trips).

**Current decision: rely on the PN kura node** — it is not meaningfully slower and avoids running kura on every Mac. On-host remains the documented fallback for when guaranteed non-bandwidth-constrained per-runner cache is needed.
