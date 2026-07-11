# tuist-cas-plugin

A Rust `cdylib` implementing the LLVM CAS plugin ABI (`llcas_*`, v0.1) that Xcode's compilation caching loads via `COMPILATION_CACHE_PLUGIN_PATH`. It wraps Xcode's bundled `libToolchainCASPlugin.dylib` for local storage, hashing, and digest handling, and adds Tuist-remote (kura) read-through and write-through on top.

## Why it exists

Xcode's own remote-caching mode (`COMPILATION_CACHE_REMOTE_SERVICE_PATH`, the gRPC socket its built-in remote mode uses, previously served by the now-removed `tuist cache start` daemon) is net-negative on deep module graphs: the remote choreography inside Apple's closed plugin stalls in 30-50s bursts, taking a 274s no-cache build to 325-445s even with all cache hits served in ~2ms. This plugin bypasses that path entirely: the build system runs in its fast plugin-local mode (no remote service path configured), and all remote traffic happens inside this plugin. Measured on the same fixture: warm remote 113.6s against a 105.5s local-replay floor (~8s over, after the kura serving fixes narrowed an earlier ~145s), and 50.4s vs 87.8s no-cache on a shallow-graph app project, which runs at its 50.1s floor.

## Architecture

The crate builds two artifacts from shared modules: the `cdylib` (`libtuist_cas_plugin.dylib`) loaded into compiler frontends, and the `tuist-cas-proxy` binary (the per-machine daemon).

- `src/types.rs` - C ABI types mirroring `llvm-c/CAS/PluginAPI_types.h` (v0.1).
- `src/upstream.rs` - dlopen table for the wrapped Apple plugin. Symbols are split required/optional: Apple's plugin does not export `llcas_cas_store_from_filepath`, `llcas_loaded_object_export_data_to_filepath`, or the on-disk size/prune entry points, so those have fallback implementations in `lib.rs`.
- `src/lib.rs` - the exported `llcas_*` surface. Every string returned to the client is allocated by this crate (the client frees through our `llcas_string_dispose`); upstream strings are copied and released immediately. Read-through: action-cache gets and object loads probe the local CAS first, resolve from the remote on miss (one unix-socket round trip to the proxy), store locally, and answer. Write-through happens ONLY on `llcas_actioncache_put_for_digest`: it writes a durable write-ahead record and fire-and-forget notifies the proxy. Do not intercept `llcas_cas_store_object` for uploads: the compiler stores input-file ingests and dependency-scan trees on every build (warm included), and mirroring those re-uploads the world (~21k redundant uploads per warm build when we tried).
- `src/proxy_proto.rs` - the length-prefixed wire protocol between the plugin and the proxy over a unix socket (RESOLVE / PUBLISH / INVALIDATE / FETCH_OBJECT ops), guarded by a `PROTOCOL_VERSION` byte so a stale proxy left running across a CLI upgrade is rejected rather than misparsed (the plugin degrades to a local miss). v2 changed RESOLVE's semantics (see the non-blocking resolve bullet), which is exactly the kind of change the version byte exists for.
- `src/proxy.rs`, `src/bin/tuist-cas-proxy.rs` - the per-machine proxy: one long-lived process owns the REAPI channel(s), the resolved-key map, the global known-local set, and all publications, multiplexing every project on the machine by REAPI instance (`account/project`). It opens the same on-disk local CAS the compilers use and materializes fetched value graphs into it. Keeping per-process cost thin here is what holds warm builds near the local-CAS floor: any fixed cost is multiplied by thousands of short-lived frontends.
- **Non-blocking resolve** (protocol v2): action-cache gets are issued from swift-build's task-setup path — the llbuild engine thread that schedules every task in the build, verified by sampling (`BuildEngine::build → demandRule → CommandTask::start → ClangCachingMaterializeKeyTaskAction.taskSetup → getCachedCompilation → llcas_actioncache_get`) — so a RESOLVE must never wait on a graph fetch. The proxy replies with the value digest right after the action lookup and moves the fetch+store to a background materializer pool. Correctness holds through `pending_objects`: before any reply, every graph node's fetch instructions (blob digest or server-inlined bytes) are registered, and a demand load that outruns the materializer produces its object through FETCH_OBJECT (present → yes; pending → fetched inline on the compiler's worker thread; otherwise a genuine not-found, which the compiler downgrades to a `cache replay failed` warning + recompile, never a build failure). Read-ahead wavefront resolves still materialize inline: they run on the read-ahead pool where blocking is free, and inline work bounds how much fetched-but-unstored data sits in memory.
- `src/reapi.rs` - the remote transport: the Bazel Remote Execution API (REAPI) over gRPC/HTTP-2 to kura (TLS with system roots for public `https`, plaintext h2c for private-network endpoints). An llcas action key `K` maps to the ActionCache key `Digest{sha256(K), len(K)}`; each llcas node is one CAS blob whose content is the zstd-compressed `"TCP0" | u32 ref_count | (u32 len | digest)* | data` frame, addressed by sha256 of that content; the ActionResult is the closure manifest (one OutputFile per node, `path` = the node's llcas digest in hex root-first, `digest` = the blob's sha256), so a reader learns every blob it needs in one round trip and fetches the missing set in one batch. Publication is `FindMissingBlobs` -> `BatchUpdateBlobs` (missing only, so cross-process upload dedup is server-side) -> `UpdateActionResult` LAST, so a reader can never observe an entry whose graph is incomplete.
- `src/prefetch.rs` - a shared worker-pool primitive used for the prefetcher (walks ref graphs after an entry hit so demand loads along deep module chains are local instead of one round trip per node; droppable on dispose) and the publisher/uploader. Bounded drain on teardown; anything still queued is left as a durable write-ahead record that a later process or the proxy sweeps, so uploads survive short-lived compiler frontends exiting.
- **Read-ahead** (proxy): the proxy records every demanded action key per local CAS path, in demand order, to `<state dir>/cas-keylogs/`, and at the start of the next build (first resolve; re-armed after a wipe or prune) replays the whole set through `resolve` on a worker pool (`TUIST_CAS_READAHEAD`, default 64, `0` disables). The demand path is serial — the build system and compilers ask one key at a time — so on a real-RTT link a warm build otherwise degenerates into a chain of round trips (measured 702s warm vs an 88s local floor at ~60ms RTT; with read-ahead 103-119s vs the daemon mode's 193-211s on the same interleaved runs). Two invariants make it work: `resolved` map entries survive `invalidate` (each cached Hit is presence-verified on disk before it is served, so pruned values self-heal per key — the build system prunes several times per build, and clearing the map on each prune threw the wavefront's work away), and the keylog preserves demand order so the wavefront stays ahead of the build. Scope: the keylog is machine-local, so a fresh machine's first build gets no wavefront and pays the engine-serial action-lookup chain even with the non-blocking resolve. The structural replacement is bulk key→value distribution from the remote (an instance-level snapshot of the action-cache map, fetched once at build start), which needs a kura surface and removes the per-machine memoization dependency.
- **Per-key overhead**: presence checks use `llcas_cas_contains_object`, never a data load — probes run once per served hit and once per manifest entry, so loading bytes put real I/O on the resolve path. Publish churn is suppressed at two layers: the proxy drops spool records whose `(key, value)` its resolved map already holds (the client re-puts replayed results at the end of its job — thousands per warm build, measured 12k → ~500), and each frontend skips puts matching associations it received from the proxy in-process. A genuinely recomputed value (different digest for the same key) still publishes.
- **Runner regime**: with the correct configuration (the kura client flag reaching `tuist generate`, so the plugin settings branch bakes `tuist-instance`), a wiped-CAS warm build on a runner VM measures **96.8s ± 3.9 against a 77-83s floor and 193.6s no-cache** — near-floor with NO cache volume, 13.5k hits, zero proxy misses, every blob inlined in the action responses. Persistent `CompilationCache.noindex` (per-account cache volumes) remains a further optimization (75.5s, at the floor), not a dependency. Cautionary tale (2026-07-11): a full day of earlier runner numbers (~240s, worse than no-cache) measured a misconfigured benchmark — generation without the kura flag takes the legacy daemon settings branch (no `tuist-instance`), and the proxy's unprimed-instance path silently answered every resolve as a miss. The proxy now logs unprimed requests; treat a "plugin barely beats no-cache" runner result as a routing failure until proven otherwise.
- `src/analytics.rs` - the proxy's per-node transfer analytics, written to `cas_analytics.db` (bundled SQLite, WAL, background writer) in the exact schema the Swift `CASAnalyticsDatabase` defines, so the existing build-report upload + server (xcactivitylog NIF) pipeline is unchanged.
- `src/token.rs` - bearer acquisition for the REAPI endpoint. The proxy holds no auth logic; it caches a bearer and, when it needs one, shells out to `tuist auth token` (the CLI owns keychain, refresh, and the cross-process lock). Refetched only when the cached JWT is within a small window of its `exp`.

## Hard-won invariants

- Panics must never cross the `extern "C"` boundary or skip worker bookkeeping. Both llcas entry points run under `catch_unwind`; the worker loop decrements its in-flight counter even when a job panics (a skipped decrement wedges the drain-on-dispose and hangs the build service); and the async paths guarantee the client callback fires exactly once.
- The plugin and builtin caching modes use different local CAS directories (`CompilationCache.noindex/plugin` vs `/builtin`); numbers from one do not carry to the other.
- `llcas_cas_dispose` must stop/drain the worker pools before disposing the upstream CAS and freeing state - workers hold references to both.

## Configuration (environment)

The plugin runs in one of two modes. **Proxy mode** (`TUIST_CAS_PROXY_SOCKET` set) delegates all remote work to the per-machine proxy over a unix socket; this is the productized path and the one the benchmarks measure. **Direct mode** (no proxy socket, `TUIST_CAS_REMOTE_GRPC_URL` set) opens a REAPI channel per compiler process; kept for benchmarks. Without either, the plugin is a pure passthrough.

- `TUIST_CAS_UPSTREAM_PLUGIN` - path to the wrapped plugin (default: `$DEVELOPER_DIR/usr/lib/libToolchainCASPlugin.dylib`).
- `TUIST_CAS_PROXY_SOCKET` - unix socket of the per-machine proxy; when set the plugin runs in proxy mode.
- `TUIST_CAS_ACCOUNT`, `TUIST_CAS_PROJECT` - the `account/project` this build's cache belongs to, used to declare the instance to the proxy. Lower precedence than the `tuist-instance` plugin option (see below); when neither is present the proxy falls back to its `cas_path -> instance` registry.
- `TUIST_CAS_REMOTE_GRPC_URL`, `TUIST_CAS_TOKEN` - REAPI endpoint + bearer. In proxy mode these configure the proxy (one endpoint/token, many instances); in direct mode they configure this process.
- `TUIST_CAS_UPLOAD` (default true) - upload policy from `xcodeCache(upload:)`. When false the plugin still serves remote read hits but publishes nothing (no value graphs to proxy or remote). Lower precedence than the `tuist-upload` plugin option (see below).
- `TUIST_CAS_PREFETCH` (default 24) - size of the plugin's prefetch/upload worker pool.
- `TUIST_CAS_LOG` - append per-process stats (hits, misses, prefetched, cache get/put latency) on dispose.

## Configuration (plugin options)

Xcode passes `-cas-plugin-option <name>=<value>` flags to the plugin via `llcas_cas_options_set_option`, sourced from build settings (`tuist generate` bakes them into `OTHER_SWIFT_FLAGS`). Unlike the environment, these reach **every** compiler frontend — including an Xcode ⌘B build that carries no CLI environment — which is how the plugin learns its instance without the CLI.

- `tuist-instance=<account/project>` - the instance this build routes to; takes precedence over `TUIST_CAS_ACCOUNT`/`TUIST_CAS_PROJECT`. `tuist-*` options are consumed here and never forwarded to the wrapped plugin.
- `tuist-upload=false` - disables publishing for this build (`xcodeCache(upload: false)`); read hits are unaffected. Takes precedence over `TUIST_CAS_UPLOAD`. This is the carrier that reaches a ⌘B build (the per-machine proxy env can't express a per-project setting).

## Development

A source-built `tuist` has nothing bundled beside it, so `ResourceLocator` and the generation mapper find no dylib and fall back to local-only caching. Point them at your `cargo`-built artifacts with two overrides:

```sh
cd cas-plugin && mise run build   # → target/release/{libtuist_cas_plugin.dylib, tuist-cas-proxy}
export TUIST_CAS_PLUGIN_PATH="$PWD/target/release/libtuist_cas_plugin.dylib"
export TUIST_CAS_PROXY_PATH="$PWD/target/release/tuist-cas-proxy"
```

**Through a dev `tuist` (recommended).** With both exports set and logged in (`tuist auth`), run the proxy foregrounded (it resolves the kura endpoint and auto-refreshes the token, like production), then generate + build in another shell:

```sh
tuist cache-proxy --url https://tuist.dev   # hidden command; Ctrl-C to stop
tuist generate                              # bakes the dev dylib path + tuist-instance
```

`tuist setup cache` / `tuist teardown cache` install and remove the same thing as a launchd agent (honoring `TUIST_CAS_PROXY_PATH`).

**Plugin/proxy only (fastest Rust loop).** Run the proxy binary directly and hand `xcodebuild` the dev dylib; the plugin auto-finds the proxy at the default socket. You supply the kura gRPC URL yourself (no endpoint resolution):

```sh
TUIST_CAS_REMOTE_GRPC_URL="<kura grpc url>" TUIST_CAS_TUIST_BIN="$(which tuist)" \
TUIST_CAS_SERVER_URL="https://tuist.dev" ./target/release/tuist-cas-proxy
xcodebuild ... \
  COMPILATION_CACHE_ENABLE_CACHING=YES COMPILATION_CACHE_ENABLE_PLUGIN=YES \
  COMPILATION_CACHE_PLUGIN_PATH="$PWD/target/release/libtuist_cas_plugin.dylib" \
  COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
  OTHER_SWIFT_FLAGS="-cas-plugin-option tuist-instance=<account>/<project>"
```

For **direct mode** (no proxy, bench/debug), put `TUIST_CAS_REMOTE_GRPC_URL` + `TUIST_CAS_TOKEN` in the build environment instead of running a proxy: the plugin opens its own REAPI channel per compiler.

Requires `SWIFT_ENABLE_EXPLICIT_MODULES` and works with Xcode 26.x. `TUIST_CAS_LOG=/tmp/cas.log` appends per-process stats on dispose and `COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS` prints Xcode's hit/miss remarks in the build log. In a shipped CLI all of this is automatic (`tuist setup cache` + `tuist generate`; the dylib and proxy ship next to `tuist`).

## Kura placement (on-host vs PN node)

The proxy can point at kura wherever it runs; two placements were measured on the CLI fixture (8-core runner VM, all kura perf fixes):

- **On-host** — one kura per runner Mac (served to the VM over the loopback/bridge). Warm build **113.6s** (median of 5). This placement is **not bandwidth-constrained**: the bridge measured 2.34 GB/s and loopback is effectively unbounded, so a very cache-heavy build or many concurrent frontends never contend on a shared NIC.
- **PN node off-host** — a shared kura on a nearby Private Network fleet node (0.89ms). Warm build **118s** (median of 3) — only ~5s slower, since sub-ms LAN is the same latency regime as the bridge. Simpler operationally (one kura per region instead of per-Mac), at the cost of a shared node NIC that could bottleneck under enough concurrent runners.

Build time only diverges at true WAN latency (66ms → warm ~0.76x of no-cache but ~65s over the local floor, since the ~2.5GB namespace fetch costs real round-trips).

**Current decision: rely on the PN kura node** — it is not meaningfully slower and avoids running kura on every Mac. On-host remains the documented fallback for when guaranteed non-bandwidth-constrained per-runner cache is needed.
