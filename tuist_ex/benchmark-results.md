# Full-server dependency-cache benchmark

## Latest remote result

A subsequent remote-only laptop build restored **145 fetched applications** from
production REAPI with an empty local artifact store. It took **155.330 s** wall
clock, including cold SDK bootstrap and all 1,344 server files. The next disabled
build took **344.771 s**. An earlier remote attempt took **433.606 s** because
seeded keys unexpectedly missed; that result is retained, not discarded. These
single samples under changing host load do not establish a stable speedup.

The CI comparison uses the runner's injected private Kura endpoint rather than
the laptop's public route. See [Remote-only comparison](#remote-only-comparison)
for the complete results, CI method and remaining limitations.

## Local-only investigation conclusion

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
production remote-cache benchmark: in these local-only samples, 76 fetched
applications still compile.

Lookup models are never used as installation/publication proof. Staged validation
reads fresh inputs without the lookup memo. Lookup misses also capture a fresh
context and key before compilation. Compilation clears the plan, restoration
invalidates the installed application's models, and preparation always removes
its process-local state.

## Workload and method (local-only samples)

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

## Results (local-only samples)

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

## Remote-only comparison

The laptop was connected to `https://tuist.cache.tuist.dev` for `tuist/server`
using existing authentication, with zstd negotiated. All 177 verified artifacts
in the earlier local store were uploaded successfully before timing (66.6 s).
This is a populated remote containing keys from earlier builds, not a single
cold-build seed. It includes bootstrap-dependent variants: the successful remote
builds restored the eight applications that missed in the local-only samples.
No upstream bytes were normalized or removed from their keys.

Each following sample reset the same checkout's complete build and pristine
dependency sources. Remote samples also started with **zero local artifacts**
and disabled uploads, so newly compiled misses could not seed later remote
samples. Configuration, locked graph, four schedulers, one dependency worker,
phase boundaries and exclusions match the local workload above. These samples
include the final source-directory ancestor-symlink guard.

Times are seconds, in execution order. Dependencies combine cache preparation
and ordinary dependency loadpaths/compilation.

| Sample | Bootstrap | Dependencies | Server compilation | Process wall | Remote hits / misses |
| --- | ---: | ---: | ---: | ---: | --- |
| Remote attempt 1 | 21.825 | 361.585 | 49.303 | 433.606 | 50 / 95 |
| Disabled 1 | 36.435 | 204.744 | 39.003 | 280.873 | Not applicable |
| Remote diagnostic | 15.607 | 97.762 | 37.214 | 150.953 | 145 / 0 |
| Remote repeat, unmodified client | 22.284 | 96.894 | 35.682 | 155.330 | 145 / 0 |
| Disabled repeat | 15.787 | 264.018 | 64.581 | 344.771 | Not applicable |

The diagnostic sample only added transport-failure logging in a disposable SDK
copy; it emitted no failure diagnostics. The subsequent 155.330 s sample uses the
unmodified client. There are two ordinary remote samples, two disabled samples
and one diagnostic sample, not medians or a controlled estimate of CI speedup.
Laptop load declined from roughly 45–60 around the first attempt to roughly 9
around the successful remote samples, then rose again around the disabled repeat.
Server-compilation times also show that variation.

Both successful remote builds have 145 keyed remote restores, 15 already-current
bootstrap observations and 56 bypass observations. The latter include 53 fetched
compiled applications, Heroicons' intentional no-compile setting and two local
projects. **68 fetched applications still compile**: 15 during bootstrap and 53
unsupported builders/upstream chains. Already-current observations are not local
keyed restores. Local projects and the SDK are counted separately.

For the unmodified remote repeat, preparation took 94.052 s:

- Keyed restore events: 21.040 s, including acquisition, staging and fresh checks.
- Reported remote read durations: 8.809 s in aggregate across overlapping reads,
  for 60,986,063 artifact bytes. This is not a standalone elapsed download phase.
- Bypass events: 40.532 s; current observations: 0.150 s.
- Outside event durations: 32.330 s of modeling, lookups and other orchestration.
- Subsequent dependency loadpaths/local compilation: 2.842 s.

The first attempt is not a clean warm-cache comparison: 110 attempted keys matched
the seed, but only 50 restored. Fresh standalone connections subsequently fetched
several of the missed keys successfully. No transport-failure diagnostics were
captured in that original attempt, and later attempts did not reproduce it. Its
exact cause remains unresolved; do not silently discard it or claim that every
seeded lookup is reliable.

### Colocated CI method

The manual **Server Cache Benchmarks** workflow accepts `benchmark=elixir-remote`.
It runs the full server on `tuist-linux-large` (4 vCPU, 16 GiB), with OIDC cache
authentication, four schedulers and three dependency workers. The runner injects
a private, in-cluster Kura endpoint; the workflow does not override it with the
laptop's public endpoint. No Mix snapshot volume is attached.

The driver seeds remote artifacts, then runs disabled, remote, remote, disabled,
resetting source/build/local artifact state each time. It preserves raw JSON,
compiled applications, environment and logs, and requires actual remote writes
and hits with zero keyed local restores. Downloading dependencies and source
reset are outside the build timers; SDK bootstrap and server compilation remain
inside. A completed-build marker is required in addition to exit status zero.

The [first CI attempt](https://github.com/tuist/tuist/actions/runs/39802560723)
passed lifecycle tests and reached the private-endpoint runner, but its lock
safety check caught dependency upgrades by the generic setup action. No timed
builds ran. The benchmark now restores the committed lock and checks out exactly
its SCM revisions without resolving again, then verifies the lock is unchanged.
The [replacement run](https://github.com/tuist/tuist/actions/runs/39805066453) has
been dispatched; no colocated timings are available yet.

## Remaining work

The full graph is the acceptance target. Lookup planning removes substantial
redundant work, and the completed follow-ups show a local warm-cache benefit, but
input-modeling overhead remains. Repeat alternating full-graph samples on a
quiet/dedicated host before quantifying a stable speedup, including a fresh cold
sample. Complete warm reuse additionally requires restoration before bootstrap
and auditing the remaining builders and upstream contracts. Remote-only
restoration with an empty local store is now measured on the laptop, but
colocated CI results, repeatability and the first attempt's unexpected misses
remain outstanding.

The focused fixture benchmarks remain useful for regressions and individual
mechanisms, but their large relative speedups must not be presented as the
whole-server result.

## Validation

The package suite passed **423 tests** after the lookup-planning changes. A final
focused run passed **36 tests**, including the ancestor-symlink guard added during
review. Formatting, compilation with warnings as errors, `mix hex.build`,
`mix docs --warnings-as-errors` and `git diff --check` passed. These checks are
separate from the measured server builds above. The CI benchmark driver's six
Python tests, Docker-cache lifecycle shell tests, Elixir driver syntax/formatting
and actionlint passed; the first CI attempt also passed the driver/lifecycle tests.
