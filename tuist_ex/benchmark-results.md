# Full-server dependency-cache benchmark

## Conclusion

The small dependency fixtures do not represent the performance of Tuist Server's
whole graph. The original full-graph implementation was a regression: repeated
input modeling cost more than the dependency compilation it skipped.

After sharing speculative lookup models within a preparation and limiting
generator discovery to actual Erlang source directories, two completed warm
full-server builds took **197.163 s and 270.906 s**, versus **355.548 s** for the
completed cache-disabled follow-up. All three builds include cold SDK bootstrap
and all 1,344 server source files. Both warm samples restored the same 137 fetched
applications; no cache eligibility or key inputs were relaxed.

These are two warm samples and one disabled sample under variable host load, not
a stable percentage speedup. A further disabled sample was interrupted when host
load exceeded 100 on an 18-logical-CPU machine. It is preserved but excluded from
completed-build comparisons. This is still not complete dependency reuse or a
production remote-cache benchmark: 76 fetched applications still compile.

Lookup models are never used as installation/publication proof. Staged validation
reads fresh inputs without the lookup memo. Lookup misses also capture a fresh
context and key before compilation. Compilation clears the plan, restoration
invalidates the installed application's models, and preparation always removes
its process-local state.

## Workload and method

- Actual `server/mix.exs`, configuration, dependency lock and application sources,
  plus the local `noora`, `tuist_common` and `tuist_ex` packages. The server compiled
  1,344 Elixir source files successfully in every completed sample.
- 217 active dependency nodes in development: 214 fetched dependencies and three
  local packages. Heroicons intentionally has `compile: false`; there are 213
  fetched applications with compiled outputs.
- The copied fetched sources were reconciled to the committed `server/mix.lock`.
  Every fetched dependency passed its SCM lock check, and the copied lock was
  byte-identical to the original. No dependency upgrades were retained.
- Baseline Tuist package: `31c8a8676bce38defdd00d010ccf7889b23bd460`.
  The initial expanded-cache implementation is `6cad26fe94`; early rejection is
  `ec3ee160fc`. Follow-up rows include preparation-scoped lookup planning and
  source-directory-only generator discovery. The second warm follow-up also uses
  the boundary-preserving `Key.paths_in/2` helper; this retains the same generator
  outputs for this locked graph while preserving nested `.git`/`_build` inputs.
  A subsequent ancestor-symlink guard for that helper is regression-tested but
  has not had another full-server timing run under the contended host.
- Same disposable checkout path for every run. Before each sample, delete the
  complete build and restore pristine dependency sources. An empty-cache sample
  also deletes its artifact store; a warm sample preserves the seeded store.
- No dependency selection or exclusions. The only cache configuration changes
  are `false` versus `[remote: false, path: STORE]`. Native builders are not
  silently opted into contracts that the real server does not configure.
- macOS arm64, Elixir 1.20.2, Erlang 29.0.3, four Erlang schedulers, one dependency
  compilation worker, development environment and host target.
- Sequential samples, not medians. The initial conditions have one sample each;
  follow-up planning has two completed warm samples, one completed disabled sample
  and one interrupted disabled attempt. Other host workloads varied substantially,
  including severe contention during the interrupted attempt. These measurements
  establish coverage and expose overhead, not stable percentage improvements.
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
| Expanded cache with lookup planning, sample 1 | Warm | 27.073 | 115.513 | 54.114 | 197.163 |
| Expanded cache with lookup planning, sample 1 | Disabled | 21.473 | 273.065 | 60.192 | 355.548 |
| Expanded cache with lookup planning, sample 2 | Warm | 29.267 | 172.654 | 68.362 | 270.906 |

The warm follow-ups reused the populated expanded-cache store; accepted key
contents did not change. There is no cold sample for either the early-rejection
or lookup-planning optimization. Do not label the earlier cold sample as a
measurement of these later implementations.

A second disabled follow-up was stopped after **393.014 s**, during dependency
compilation, when observed host load exceeded 100 (later 163). Only that
benchmark's process group was terminated. It did not finish dependency loading or
server compilation and is not a completed timing sample. BEAM returned status 0
for SIGTERM, but the driver's `completed: false` and phase log establish the
interruption; exit status alone is not a successful-build criterion.

## Restoration versus compilation

| Warm implementation | Keyed artifact restores | Already-current observations | Keyed misses | Bypasses | Fetched applications actually compiled |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline | 57 | 8 | 0 | 144 | 156 |
| Initial expanded cache | 137 | 15 | 8 | 56 | 76 |
| Expanded cache with early rejection | 137 | 15 | 8 | 56 | 76 |
| Expanded cache with lookup planning, each of two samples | 137 | 15 | 8 | 56 | 76 |

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
- The early-rejection warm run restored 56,894,439 artifact bytes. Its aggregate reported
  local read/restore time was **23.256 s**. That includes staging validation; it
  is not network throughput or all dependency preparation time.
- Of 217.586 s in early-rejection cache preparation, reported restore/current observations
  account for 23.400 s, bypass compilation for 99.666 s and miss compilation for
  3.119 s. The remaining **91.401 s** covers modeling, eligibility, lookup and
  other orchestration outside those event durations. The early-rejection fix
  reduces this overhead but does not eliminate the full-graph regression.
- The lookup-planning follow-ups restored the same **56,894,439 bytes**. Cache
  preparation took **109.117 s / 167.284 s**, with reported local read/staging
  validation of **10.614 s / 16.987 s**. Time outside event durations fell to
  **45.060 s / 72.322 s**; it is not eliminated. Bypass compilation also varied
  substantially (**49.653 s / 72.349 s**, versus the earlier 99.666 s), so the
  entire preparation-time reduction must not be attributed to input modeling.

## What the lookup-planning fix changes

Previously, every lookup rebuilt the configuration, source-path enumeration,
source-content tree and upstream artifact fingerprints for its entire transitive
closure. Shared upstreams were repeatedly modeled for different consumers.
Generator discovery additionally walked each entire dependency checkout, even
when its only Erlang source directory was `src`.

`Plan` now shares those lookup records within the compiler process and effective
context/options namespace. It clears them after compilation and invalidates an
installed application's records after restoration. Generator discovery enumerates
only the effective Erlang source directories, retaining checkout-relative paths
and nested metadata names. Full structural enumeration and content hashing still
cover the entire source tree.

Every staged install/publication bypasses this memo and recomputes fresh inputs.
A lookup miss also captures a fresh compilation key, including when rejected
staging exposed an input change. Newly compiled code can then be published only
under that new key, subject to the usual fresh publication check. Regressions
cover shared-upstream work counts, source/artifact mutation, namespace/lifetime
isolation, staging mutation and source-subdirectory boundaries.

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

The full graph is the acceptance target. Lookup planning removes substantial
redundant work, and the completed follow-ups show a local warm-cache benefit, but
input-modeling overhead remains. Repeat alternating full-graph samples on a
quiet/dedicated host before quantifying a stable speedup, including a fresh cold
sample. Complete warm reuse additionally requires restoration before bootstrap
and auditing the remaining builders and upstream contracts. Remote-only
restoration with an empty local store remains unmeasured.

The focused fixture benchmarks remain useful for regressions and individual
mechanisms, but their large relative speedups must not be presented as the
whole-server result.

## Validation

The package suite passed **423 tests** after the lookup-planning changes. A final
focused run passed **36 tests**, including the ancestor-symlink guard added during
review. Formatting, compilation with warnings as errors, `mix hex.build`,
`mix docs --warnings-as-errors` and `git diff --check` passed. These checks are
separate from the measured server builds above.
