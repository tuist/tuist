---
{
  "title": "Cargo build cache for Rust",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Cut Rust compile time in CI and fresh clones with Tuist's Cargo build cache, which reuses compilation outputs locally and through a remote cache."
}
---
# Cargo build cache for Rust {#rust-cache}

Tuist caches supported Rust compilation outputs so Cargo can reuse them after its build outputs have been removed, such as after `cargo clean`, a branch switch, or in another checkout. You might also see this called a Cargo build cache or a Rust compile cache: it shortens Rust compile times by reusing what an earlier build compiled, including your workspace's incrementally compiled crates. The cache is built into the Tuist CLI. There is no separate cache executable or Cargo plugin to install.

<!-- @snippet: ./_rust-experimental -->

## Enable caching {#enable-caching}

Follow the <.localized_link href="/guides/get-started/rust-project">Rust project setup</.localized_link> to connect your project and authenticate. Then run your build through Tuist:

```sh
tuist cargo build --release
```

Caching is automatic for eligible compilations. There is no additional cache configuration or enablement flag. Tuist discovers your account's cache endpoint and obtains cache credentials using your existing project and server configuration.

If you use mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configure a Cargo wrapper</.localized_link> to keep typing ordinary `cargo` commands.

## How it works {#how-it-works}

Before Cargo starts, Tuist restores the outputs of your registry and git dependencies that an earlier build produced with the same toolchain, profile and configuration, so Cargo finds them up to date. Cargo stays in charge of deciding what to rebuild. Then, for each eligible compilation Cargo still runs, Tuist:

1. Checks its local cache for matching outputs.
2. On a local miss, queries Kura through the Remote Execution API (REAPI), downloads any missing content, and verifies the outputs before restoring them.
3. On a cache miss, runs the compiler. After a successful compilation, it stores the outputs locally and uploads them to Kura through REAPI when authorized. The remote cache entry is published only after all of its referenced content is available.

On CI, a crate's first compilation in a target directory runs without incremental compilation, as Cargo 1.99 and later already do by default: there is no earlier session to reuse, CI doesn't edit what it compiled, and building a session makes that compilation slower and its cache entry larger. Tuist remembers the crate in the target directory, so a job that keeps its target directory compiles it incrementally next time. Local builds compile incrementally as Cargo asks, so the first edit after a fresh build stays fast. Cache entries are shared either way.

Builds on the same machine share the local cache, including builds in other worktrees or target directories. When another build is already compiling the same crate or running the same build script, Tuist waits for it and restores its outputs instead of doing the same work twice. If that build takes longer than 10 minutes, Tuist stops waiting and compiles the crate itself.

Local and CI builds use the same remote cache protocol. Read and write access come from Tuist's server-issued cache credentials and your account's <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">cache upload policy</.localized_link>. An account can allow developers to download while restricting uploads to CI and account tokens. Cache writers are trusted code producers: cached compiler outputs are executable code, so only grant write access to machines and tokens you trust.

If remote setup fails, local caching remains available. Unavailable, missing, or corrupt cache entries fall back to compilation. An upload failure doesn't fail the build or discard its local cache entry.

## What can be cached {#what-can-be-cached}

The cache supports:

- Library crates, including workspace and path crates, crates with dependencies, and crates with generated sources. Tuist keys them by the sources the compiler read.
- `cargo check` and `cargo clippy`, which compile libraries to metadata only. Their entries are separate from those of builds, so a check never provides a library to `cargo build`. Dependencies that `cargo clippy` compiles with the plain compiler, such as path crates outside the workspace, reuse the entries of `cargo check`.
- On Apple silicon Macs and on x86_64 and arm64 Linux with glibc, compilations that source inspection can't key in advance, such as crates that use procedural macros, inline assembly or native libraries, procedural macros themselves, and linked executables. Tuist records the files, environment variables and read-only commands each one reads, such as `git describe`, and keys it by them. On Linux, the system linker, C library and startup files a link reads are part of its key.
- On the same platforms, build-script runs, including the C compilations they perform (with the default Apple compiler on macOS, with any dynamically linked compiler on Linux). A run is restored only when the files, environment and commands it read are unchanged.
- Warnings and other diagnostics, which a cached crate shows again, including Clippy's lints.

The following still build normally:

- Build scripts and recorded compilations on Linux distributions without glibc, such as Alpine.
- Build scripts that connect to the network, start programs Tuist can't observe (on Linux, statically linked programs), or write outside their output directory.
- Custom targets, and unsupported compiler arguments or source inputs.
- Clippy compilations of procedural macros and build scripts, and Clippy runs that enable the `cargo` lint group, which reads every manifest of the workspace and its lockfile through `cargo metadata`.
- Compilations that emit unexpected compiler output.
- Compilations that run with dynamic loader settings, such as `LD_PRELOAD`, or with `LD_LIBRARY_PATH` directories outside the Rust toolchain and the target directory, for example ones inherited from your shell or a `build.build-dir` outside the target directory.

A pre-existing global compiler wrapper disables Tuist's compilation cache and compiler observer. Custom workspace wrappers other than Clippy's also bypass caching. See <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compiler tool compatibility</.localized_link>.

Cache keys include the package contents, compiler and toolchain, arguments, and build environment. Clippy entries also depend on the Clippy version, the lint arguments in `CLIPPY_ARGS`, `CLIPPY_CONF_DIR`, `CLIPPY_DISABLE_DOCS_LINKS`, the package's `Cargo.toml`, and the `clippy.toml` or `.clippy.toml` Clippy loads. The checkout, target directory, Cargo home and toolchain locations are replaced with placeholders, so a checkout at another path reuses the same entries. A crate whose output embeds its own path, for example through `env!("CARGO_MANIFEST_DIR")`, is reused only at that path. Credentials, Tuist reporting settings, and recognized CI run metadata don't invalidate entries. Crates that read those excluded variables during compilation aren't cached.

## Verify reuse {#verify-reuse}

Cargo already avoids rebuilding up-to-date outputs. To exercise Tuist's cache rather than Cargo's existing outputs, build once, remove Cargo's outputs, then repeat the same build:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Eligible libraries can be restored on the second build; unsupported crates still compile. Removing Cargo's outputs doesn't remove Tuist's separate local cache. This checks reuse, not necessarily remote downloads: a local hit doesn't need a transfer from Kura. Input validation and cache operations add overhead, so avoiding compilation doesn't guarantee faster builds for small crates.

To check that hits are correct, for example as a canary in CI, set either variable to `sampled` (one crate in 64, the same crates on every build) or `always`:

- `TUIST_CARGO_VERIFY` checks that the inputs a hit was keyed by are still the ones the compiler or build script reads.
- `TUIST_CARGO_VERIFY_RECOMPILE` compiles hits again and compares their outputs with the cached ones.

A checked crate compiles instead of being restored, as if it were uncached, so its outputs are always fresh and verification doesn't change build results. Verification never stores or replaces the checked crate's cache entry. If its fresh outputs differ from the cached ones, crates that depend on it miss and are cached as in an uncached build. Incremental compilations aren't reproducible, so for those `TUIST_CARGO_VERIFY_RECOMPILE` compares only metadata and dependency information. With `TUIST_DEBUG=1`, each check prints a `Tuist Cargo cache: verified` line, and checks that found a difference are counted as divergences in the build's cache measurements.

## Inspect cache activity {#inspect-cache-activity}

Open **Cargo Cache** in your project's dashboard to inspect hit rates, recorded transfers, latency, throughput, and recent builds. Open a build's **Cache** tab for individual task decisions and CAS outputs.

Missing measurements aren't counted as zero, and a cache hit doesn't necessarily mean a remote download. See <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust cache measurements</.localized_link> for details.

## Troubleshooting {#troubleshooting}

Enable debug output to inspect cache transfer and reporting failures:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Debug output also explains why a compilation or build-script run wasn't stored. If you see no hits, check that another compiler wrapper isn't taking precedence, and that the compiler, flags and environment match the build that populated the cache. For remote uploads, also check authentication and the account's cache upload policy.
