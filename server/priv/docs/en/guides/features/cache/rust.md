---
{
  "title": "Rust cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Reuse supported Rust compilation outputs locally and through Tuist's remote cache with Cargo."
}
---
# Rust cache {#rust-cache}

Tuist caches supported Rust compilation outputs so Cargo can reuse them after its build outputs have been removed. The cache is built into the Tuist CLI. There is no separate cache executable or Cargo plugin to install.

> [!WARNING] Experimental compilation cache
> The cache is experimental and qualified on Apple silicon Macs. Build scripts, procedural macros, executables and native code are cached only there, and Linux library caching isn't qualified yet. Reuse is verified for checkouts at different paths on the same machine, not across machines.

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
3. On a cache miss, runs the compiler normally. After a successful compilation, it stores the outputs locally and uploads them to Kura through REAPI when authorized. The remote cache entry is published only after all of its referenced content is available.

Local and CI builds use the same remote cache protocol. Read and write access come from Tuist's server-issued cache credentials and your account's <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">cache upload policy</.localized_link>. An account can allow developers to download while restricting uploads to CI and account tokens. Cache writers are trusted code producers: cached compiler outputs are executable code, so only grant write access to machines and tokens you trust.

If remote setup fails, local caching remains available. Unavailable, missing, or corrupt cache entries fall back to compilation. An upload failure doesn't fail the build or discard its local cache entry.

## What can be cached {#what-can-be-cached}

The cache supports:

- Library crates, including workspace and path crates, crates with dependencies, and crates with generated sources. Tuist keys them by the sources the compiler read.
- On Apple silicon Macs, compilations that source inspection can't key in advance, such as crates that use procedural macros, inline assembly or native libraries, procedural macros themselves, and linked executables. Tuist records the files, environment variables and read-only commands each one reads, such as `git describe`, and keys it by them.
- On Apple silicon Macs, build-script runs, including the C compilations they perform with the default Apple compiler. A run is restored only when the files, environment and commands it read are unchanged.
- Warnings and other diagnostics, which a cached crate shows again.

The following still build normally:

- Build scripts and recorded compilations on Linux.
- Build scripts that connect to the network, start programs Tuist can't observe, or write outside their output directory.
- Incremental compilations, custom targets, and unsupported compiler arguments or source inputs.
- Metadata-only `cargo check` invocations.
- Compilations that emit unexpected compiler output.

A pre-existing global compiler wrapper disables Tuist's compilation cache and compiler observer. Custom workspace wrappers also bypass caching. See <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compiler tool compatibility</.localized_link>.

Cache keys include the package contents, compiler and toolchain, arguments, and build environment. The checkout, target directory, Cargo home and toolchain locations are replaced with placeholders, so a checkout at another path reuses the same entries. A crate whose output embeds its own path, for example through `env!("CARGO_MANIFEST_DIR")`, is reused only at that path. Credentials, Tuist reporting settings, and recognized CI run metadata don't invalidate entries. Crates that read those excluded variables during compilation aren't cached.

## Verify reuse {#verify-reuse}

Cargo already avoids rebuilding up-to-date outputs. To exercise Tuist's cache rather than Cargo's existing outputs, build once, remove Cargo's outputs, then repeat the same build:

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

Eligible libraries can be restored on the second build; unsupported crates still compile. Removing Cargo's outputs doesn't remove Tuist's separate local cache. This checks reuse, not necessarily remote downloads: a local hit doesn't need a transfer from Kura. Input validation and cache operations add overhead, so avoiding compilation doesn't guarantee faster builds for small crates.

## Inspect cache activity {#inspect-cache-activity}

Open **Cargo Cache** in your project's dashboard to inspect hit rates, recorded transfers, latency, throughput, and recent builds. Open a build's **Cache** tab for individual task decisions and CAS outputs.

Missing measurements aren't counted as zero, and a cache hit doesn't necessarily mean a remote download. See <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust cache measurements</.localized_link> for details.

## Troubleshooting {#troubleshooting}

Enable debug output to inspect cache transfer and reporting failures:

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

Debug output also explains why a compilation or build-script run wasn't stored. If you see no hits, check that another compiler wrapper isn't taking precedence, and that the compiler, flags and environment match the build that populated the cache. For remote uploads, also check authentication and the account's cache upload policy.
