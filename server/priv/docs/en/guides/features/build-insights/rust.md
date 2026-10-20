---
{
  "title": "Rust Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Find slow crates, compare build performance, and inspect Rust compiler warnings and errors in Tuist."
}
---
# Rust build insights {#rust-build-insights}

Build Insights helps you find what slows your Cargo builds down and catch regressions before they affect the whole team. You can compare local builds with CI, see how build times change, and inspect the crates compiled in each build.

> [!IMPORTANT] Requirements
> - Follow the <.localized_link href="/guides/get-started/rust-project">Rust project setup</.localized_link> to connect your project and authenticate.

## Report your builds {#report-your-builds}

Run your usual Cargo commands through Tuist:

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

If you use mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configure a Cargo wrapper</.localized_link> to keep using ordinary `cargo` commands. Your arguments, toolchain selection, output, and exit code stay the same.

## Find what slows a build down {#explore-your-builds}

Open a build from **Builds → Build Runs** on the dashboard. Use the date, environment, and Rust-version filters to compare similar builds.

On **Overview**, use **Compiler jobs** to find slow crates. Sort by **Duration** or **Started after** (time since the Cargo command started), or search by crate name or root source file.

Each row is one `rustc` invocation for a crate, which can contain many source files. **Crate root** identifies its root source file; the duration is for the whole compiler job, not that file alone. A crate can appear more than once for different targets or configurations. Compiler messages are grouped in **Warnings** and **Errors**.

## Read the timings {#timing-boundaries}

The build duration is how long the whole Cargo command took. Compiler jobs can run in parallel, so their durations won't add up to the build duration.

Cargo only compiles crates that need rebuilding. Crates that are already up to date won't appear in the compiler list. With Tuist's compilation cache, restored jobs appear in the cache measurements, not as compiler executions.

Tuist doesn't measure build scripts separately or show a build Timeline. A large build shows the first 500 compiler jobs, with a notice if more were recorded.

## Read cache measurements {#cache-measurements}

`tuist cargo` includes an experimental compilation cache. Official bundles include the native runtime; source builds without it retain the narrower Swift fallback. There is no separate tool to install; project and server settings come from `tuist.toml`. See <.localized_link href="/guides/features/cache/rust">Rust cache</.localized_link> for coverage, CI publication, and limitations. Unsupported compilations run normally.

Open **Cargo Cache** in the project sidebar to track cache hit rates and recorded transfer, latency, and throughput measurements across builds. Filter by date or environment, switch between daily trends and individual-build hit rates, or open a recent build to inspect its cache activity. Builds without cache measurements remain unavailable rather than counting as zero.

Open a build's **Cache** tab to see task hits, task misses, hit rate, and downloaded and uploaded bytes. The tab appears when the build reports cache data.

- **Cacheable Tasks** shows which compiler and build-script tasks reused cached outputs. Search or filter the tasks, inspect cache read/write latency, and expand a row to see its outputs.
- **CAS Outputs** shows artifact downloads and uploads, with their sizes, durations, and throughput. The chart counts completed transfers; already-present artifacts and failed attempts remain in the table.

**Hit** means cached outputs were reused. **Missed** means the task compiled instead. Hits aren't split into local and remote; CAS Outputs shows the recorded artifact operations.

If detailed records are missing or incomplete, the page shows a notice. The summary still covers the whole build. Estimated compiler work avoided is **not elapsed build time saved**.

> [!WARNING] Experimental compilation cache
> Native executable/link restores remain disabled while a macOS verification divergence is investigated. Incremental compilation and unsupported inputs can bypass caching. The Swift fallback remains limited to registry leaf libraries with path-sensitive keys. Cross-worker and cross-toolchain reuse is not production-qualified.

### Builds that run tests {#builds-that-run-tests}

`tuist cargo test` reports the duration of the whole command, including its tests. Use <.localized_link href="/guides/features/test-insights/rust">nextest Test Insights</.localized_link> to track individual test results. Nextest runs appear under **Tests**, not in build-duration charts.

For <.localized_link href="/guides/features/test-sharding/rust">test sharding</.localized_link>, `tuist cargo test-build` reports the time spent compiling and archiving the tests.

## Other compiler tools {#other-compiler-tools}

Tuist preserves existing compiler wrappers configured through `RUSTC_WRAPPER`, `CARGO_BUILD_RUSTC_WRAPPER`, or Cargo configuration, and leaves `RUSTC_WORKSPACE_WRAPPER` intact. A pre-existing global wrapper disables Tuist's cache and compiler observer: Tuist cannot establish whether that wrapper actually ran rustc. Custom workspace wrappers can likewise leave fewer compiler jobs in the report.

Tuist finds Cargo through rustup. If you use a custom installation, set `TUIST_CARGO_EXECUTABLE` to its executable path. Calling Cargo by a direct toolchain path bypasses mise's wrapper. A Cargo alias can't replace a built-in command such as `build`.

If you use Cargo's nightly `-C` option, change into the workspace first instead: Tuist forwards `-C` commands but doesn't collect their build timings.

## Troubleshooting {#troubleshooting}

If a build doesn't appear in the dashboard, enable debug output to see why its report wasn't sent:

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

Reporting doesn't change the result of your build.
