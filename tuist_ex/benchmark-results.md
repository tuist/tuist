# Full-server dependency-cache benchmark

## Conclusion

The small dependency fixtures do not represent the performance of Tuist Server's
whole graph. In this exploratory full-graph run, the current warm cache restored
137 fetched applications but remained slower than caching disabled. This is not
a demonstration of complete server dependency reuse or a production remote-cache
speedup.

The full graph also exposed avoidable work: an unsupported dependency closure was
having its source contents hashed before it was rejected. Checking the entire
closure's configuration and paths first reduced cache preparation from 286.939 s
to 217.586 s in these runs. Accepted keys still contain the same inputs, and both
the freshly hashed tree and post-staging inputs are revalidated. No input
fingerprints are memoized across staging.

## Workload and method

- Actual `server/mix.exs`, configuration, dependency lock and application sources,
  plus the local `noora`, `tuist_common` and `tuist_ex` packages. The server compiled
  1,344 Elixir source files successfully in every sample.
- 217 active dependency nodes in development: 214 fetched dependencies and three
  local packages. Heroicons intentionally has `compile: false`; there are 213
  fetched applications with compiled outputs.
- The copied fetched sources were reconciled to the committed `server/mix.lock`.
  Every fetched dependency passed its SCM lock check, and the copied lock was
  byte-identical to the original. No dependency upgrades were retained.
- Baseline Tuist package: `31c8a8676bce38defdd00d010ccf7889b23bd460`.
  The initial expanded-cache implementation is `6cad26fe94`; the final warm row
  includes the subsequent early-rejection optimization.
- Same disposable checkout path for every run. Before each sample, delete the
  complete build and restore pristine dependency sources. An empty-cache sample
  also deletes its artifact store; a warm sample preserves the seeded store.
- No dependency selection or exclusions. The only cache configuration changes
  are `false` versus `[remote: false, path: STORE]`. Native builders are not
  silently opted into contracts that the real server does not configure.
- macOS arm64, Elixir 1.20.2, Erlang 29.0.3, four Erlang schedulers, one dependency
  compilation worker, development environment and host target.
- Sequential, single samples per condition, not medians. Other host workloads
  varied substantially. The initial disabled run and initial expanded-cache cold
  run are especially affected. These measurements establish coverage and expose
  overhead; they do not establish stable percentage improvements.
- Dependency downloads/source copying are outside the timer. Native download
  helpers can reuse their existing machine-wide caches. Application startup,
  database setup, tests and release/asset deployment are not part of the build.

The phase-instrumented driver runs the same underlying dependency/bootstrap and
compiler operations, without installing the analytics per-file profiler:

1. Load the server configuration.
2. Run `deps.compile tuist_ex --include-children`, then
   `deps.loadpaths --no-compile --no-deps-check` in the same process.
3. Start a local-only compile reporter and call `DependencyCache.prepare/2`.
4. Re-enable `deps.loadpaths` and `loadpaths`, then run ordinary `deps.loadpaths`
   to finish checks and remaining local compilation.
5. Invoke `Mix.Tasks.Compile.run([])` for the actual server, bypassing the alias
   only because its bootstrap/cache steps were already timed separately.
6. Finish the reporter locally. Record complete subprocess wall time as well as
   the individual phases. No build reports are sent to the hosted service.

## Results

Times are seconds. "Dependencies" includes cache preparation and the subsequent
ordinary dependency loading/compilation, including the remaining local packages.
Wall time also includes process startup, configuration and reporter teardown.
Rows are shown in execution order.

| Implementation | Cache state | Bootstrap | Dependencies | Server compilation | Process wall |
| --- | --- | ---: | ---: | ---: | ---: |
| Baseline | Disabled | 31.191 | 350.210 | 46.919 | 430.327 |
| Initial expanded cache | Empty | 41.489 | 502.454 | 113.130 | 657.938 |
| Initial expanded cache | Warm | 35.526 | 289.581 | 45.515 | 371.107 |
| Baseline | Empty | 17.681 | 192.607 | 48.263 | 259.056 |
| Baseline | Warm | 19.942 | 193.037 | 42.838 | 256.332 |
| Expanded cache | Disabled | 15.705 | 163.530 | 43.509 | 223.143 |
| Expanded cache with early rejection | Warm | 16.170 | 223.162 | 39.552 | 279.375 |

The final warm sample reused the previously populated expanded-cache store;
accepted key contents did not change. There is no final-optimization cold sample
in this table. Do not label the earlier cold sample as a measurement of that
later optimization.

## Restoration versus compilation

| Warm implementation | Keyed artifact restores | Already-current observations | Keyed misses | Bypasses | Fetched applications actually compiled |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline | 57 | 8 | 0 | 144 | 156 |
| Initial expanded cache | 137 | 15 | 8 | 56 | 76 |
| Expanded cache with early rejection | 137 | 15 | 8 | 56 | 76 |

The expanded-cache rows need these distinctions:

- The bootstrap compiles **15 fetched applications plus `tuist_ex`** from a clean
  build. The later `up_to_date` observations are Mix reuse within that process,
  not artifact restores, and do not establish zero compilation.
- The 56 bypasses comprise **53 fetched applications that compile**, Heroicons'
  intentional opt-out, and the two remaining local packages. Unsupported roots
  also prevent caching their dependent applications. This includes native/custom
  builders and substantial Phoenix/HTTP-related portions of the graph.
- Eight further fetched applications miss their keys and compile. Together with
  bootstrap and bypass compilation, that gives **76 fetched applications
  compiled**, versus 137 restored, out of the 213 compiled fetched applications.
- The final warm run restored 56,894,439 artifact bytes. Its aggregate reported
  local read/restore time was **23.256 s**. That includes staging validation; it
  is not network throughput or all dependency preparation time.
- Of 217.586 s in final cache preparation, reported restore/current observations
  account for 23.400 s, bypass compilation for 99.666 s and miss compilation for
  3.119 s. The remaining **91.401 s** covers modeling, eligibility, lookup and
  other orchestration outside those event durations. The early-rejection fix
  reduces this overhead but does not eliminate the full-graph regression.

## Why eight warm keys miss

The affected applications are `mint_web_socket`, `slipstream`, `ch`, `finch`,
`req`, `langchain`, `loki_logger_handler` and `ecto_ch`. They depend on Mint,
which is rebuilt during bootstrap rather than restored by this cache.

Comparing independently built bootstrap artifacts found byte differences in
Mint's `Elixir.Mint.HTTP1.beam` and, in another build, `Elixir.Mint.HTTP2.Frame.beam`.
The differing chunk is Elixir's `ExCk` checker metadata. For the compared
`Mint.HTTP1` artifacts, decoding that chunk produces equal terms even though the
encoded bytes differ. The same phenomenon was observed in `GRPC.Stream`.

The keys include actual upstream artifact bytes, so these are different modeled
inputs, not evidence that the key encoder randomly hashes identical inputs.
The benchmark does not strip checker metadata or weaken upstream fingerprints
to hide those misses. Restoring the bootstrap closure before compilation is a
separate, still-unresolved requirement.

## Remaining work

The full graph is the acceptance target. Before claiming a server speedup or
complete warm reuse, reduce repeated full-graph modeling without weakening
post-staging reconciliation, restore before bootstrap, and audit the remaining
builders and their upstream contracts. Then repeat clean full-graph runs under
controlled load, including remote-only restoration with an empty local store.

The focused fixture benchmarks remain useful for regressions and individual
mechanisms, but their large relative speedups must not be presented as the
whole-server result.
