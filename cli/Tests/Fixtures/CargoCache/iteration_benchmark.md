# Cargo iteration benchmark

An on-demand, synthetic benchmark of the public Cargo commands. It compares ordinary Cargo with
local Tuist, and optionally remote Tuist, without changing the existing clean-target correctness fixtures.

Requires Bash, Node.js 22 or later, Git, a named rustup toolchain with Cargo/rustc, and an explicitly
selected Tuist executable. Start on arm64
macOS for the currently qualified recorded-cache path. Linux can measure overhead and fallback, but
does not qualify equivalent cache support. Do not run competing benchmarks concurrently.

```sh
TUIST_CLI_BINARY=/absolute/path/to/tuist \
  bash cli/Tests/Fixtures/CargoCache/iteration_benchmark.sh
```

Defaults are seven rounds, four Cargo jobs, and two separate settings lanes:

- `normal`: Cargo's default development settings, including its normal incremental compilation.
- `no-incremental`: `CARGO_INCREMENTAL=0` for both Cargo and Tuist. This is not the baseline for the normal lane.

For a quick harness check, use `--rounds 1`. Use `--settings normal` or `--settings no-incremental`
to select a lane, and `--scenarios I1,I5,R2` to select scenarios. Results with one round validate
the harness, not repeatable performance. No-op timings include wrapper startup and reporting.

## Matrix

The controlled workspace has a shared path library, two applications that consume it, and an
unrelated sibling library. Builds use `--workspace --locked --offline` with no third-party crates.
The baseline outputs are 17 and 21; fixed application and library edits produce 19/21 and 21/33.

| ID | Before the measured command | What it measures |
| --- | --- | --- |
| I1 | Prime the same command, retain target and cache, change nothing | No-op overhead |
| I2 | Prime A, retain target/cache, change the left application's body | Fresh application edit |
| I3 | Prime A, retain target/cache, change the shared library's body | Fresh dependency-closure edit |
| I5 | Prime A, build the application edit B, rewrite A with fresh modification times | Edit-and-revert reuse |
| R1 | Empty target and client cache; source inputs unique to the run/round/scenario | Cold population cost |
| R2 | Prime A, remove target only; remote disabled | Local restoration versus rebuilding |
| R3 | Prime A, await command completion/publication, remove target and entire client cache | Remote-configured restoration versus rebuilding |

R2 compares Cargo and local Tuist. R3 compares Cargo and remote Tuist. Other rows also include
remote Tuist when explicitly enabled. R3 is explicitly skipped otherwise, including in metadata.
Each configuration owns its target tree and cache; no targets are copied between configurations.
Each sample starts independently, and configuration order rotates each round. Source tags prevent
earlier rounds/scenarios from warming later compiler-action misses. A comment-only `.cargo/config.toml`
uses the same run/lane/scenario/round tag to isolate the accumulating remote prefetch manifest, whose
key hashes Cargo configuration contents, not sources. Paired Cargo/local/remote configurations share
that tag, unchanged through priming, edits, restoration and publication proof. Filesystem page caches
are not flushed.

The driver intentionally clears inherited compiler flags, Cargo overrides, Tuist internals and CI
identifiers, and uses private Cargo/XDG directories. This controls the synthetic workload, not a
user's checked-in application configuration. It preserves inherited loader search settings and
rejects injected libraries rather than removing Linux cache-admission restrictions. The selected
rustup toolchain remains authoritative. Logs run without `TUIST_DEBUG`.

The driver resolves native Cargo and rustc through rustup once, rejects script wrappers, and pins
those executables and the toolchain for every configuration. Preparation, ordinary-Cargo samples
and reference builds never invoke a PATH Cargo decorator. The selected paths are in `toolchain.json`
and metadata; public Tuist receives the same Cargo executable through `TUIST_CARGO_EXECUTABLE`.

Local Tuist sends its ordinary build reports to a fixture-owned loopback receiver, following the
Cargo test-reporting fixture's pattern. The receiver advertises no remote cache and captures actual
compiler observations and cache counters. It avoids measuring unavailable-server retries as normal
wrapper overhead. Its lifetime is limited to this run; startup and shutdown are outside timing.
It does not model Phoenix persistence latency, authenticate real users, or implement a mock cache.

## Optional real remote transport

Use only an isolated local server project and real Kura with compatible signing keys, as for
`remote_e2e.py`. Both URLs must be loopback endpoints; the driver rejects production URLs.
Supply `TUIST_TOKEN` privately, never in a committed command or result. This mode writes to the
explicitly selected fixture project, so provision a disposable project before running it.

```sh
TUIST_CLI_BINARY=/absolute/path/to/tuist \
TUIST_PROJECT=fixture/iteration TUIST_URL=http://localhost:8080 \
TUIST_CACHE_ENDPOINT=http://localhost:9090 \
  bash cli/Tests/Fixtures/CargoCache/iteration_benchmark.sh --remote
```

The unique source tags make R1 a new corpus without deleting server-side data. R3 discards the
publisher's entire local cache after its command exits. Keep Kura running and label its server-side
cache as warm. The token also needs build-read access: after each remote command, the driver reads
its report through the Cargo build API, identified by a unique per-command Git branch. Observation
and bounded ingestion polling occur outside timing. Missing reports and reported remote failures
fail the run rather than silently benchmarking fallback compilation.

Before each remote command, an untimed authenticated cache-token request checks that cache
credentials are available; tokens are never retained. This is not proof of REAPI connectivity.
Incremental-disabled R1 additionally removes target and the entire client cache after its measured
cold build, then requires an untimed remote restore with hits and downloaded bytes. This proves
publication even when cold upload counters are zero. Missing cache decisions or an unsuccessful
restore fail the run. The extra proof does not enter R1's timing.

In the incremental-disabled R3 lane, require both observed cache hits and downloaded bytes from an
initially empty client cache. Normal incremental builds may bypass compilation caching; their
observed counters are recorded without inventing hits. Summaries call the lane `remote-configured`
and explicitly count samples whose remote activity remains unproven. Credential availability or
a successful build alone never establishes remote execution or reuse. In the incremental-disabled local R2 lane
on arm64 macOS, require observed hits too. CPU, memory and dependency-unit counts remain unmeasured.

## Results and correctness

Every sample verifies both binaries against independently calculated expected values. After each
measured command, the same source revision is built with ordinary Cargo into a separate reference
target, and both results must agree. Reference builds and all preparation occur outside timing.
No result is summarized before verification succeeds. A failed command stops the run and retains
its exit status, signal/error, log and partial timing records.

Compiler observations must account for the controlled workload: four compilations for cold/prime/
restoration builds, zero for no-op, one for application edits/reverts, and three for a shared-library
edit, minus observed compiler-cache hits. Remote reads poll until the expected execution count
arrives, up to 40 attempts, rather than treating `compilations_truncated: false` as ingestion readiness.
Unexpected counts or observations still missing at the deadline fail the sample.

The printed private temporary directory retains:

- `metadata.json`: platform, CPU, toolchain/CLI/Xcode versions, CLI and driver digests, repository
  revision when Git metadata is available, settings, skipped scenarios and explicit measurement
  limits. No token or arbitrary environment values.
- Per sample: workspace, starting Git revision, measured-source patch, prime/edit/reference logs,
  measured log, raw monotonic wall timing, status and cache size before/after. Cache bytes are
  logical file sizes, not disk allocation or wire traffic.
- `results.json` and `results.md`: all verified samples, median, interpolated IQR, median paired
  delta and median paired ratio against ordinary Cargo for the same settings/scenario/round.

The timer includes the complete public command, including setup and publication it waits for.
Debug diagnostics are disabled. Tuist samples also retain observed cache counters and compiler
execution counts, never inferred from Cargo's progress messages. Transfer counters describe the
client's measured uncompressed content bytes, not wire traffic. CPU, peak memory, dependency-unit
counts, internal phase breakdowns and time to test verdict are not collected by this first build-only
driver. Seven samples do not justify p95 claims. It neither sets a CI timing gate nor asserts that a
tiny workspace must be faster with caching.

Preserve negative results and report absolute differences as well as ratios. Evaluate no-op and
fresh-edit regressions separately from clean-target wins. An initial review threshold is the larger
of 100 ms or 5% of the ordinary Cargo median, confirmed in a second session; it is not a product SLO.

The reporting helper's public interface has portable tests for native-toolchain selection, paired
statistics, incomplete runs, failed commands, credential redaction, endpoint restrictions, delayed
compiler ingestion, remote credentials and publication/reuse evidence:

```sh
node --test cli/Tests/Fixtures/CargoCache/iteration_benchmark.test.mjs
```
