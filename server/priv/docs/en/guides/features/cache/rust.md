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
> The current version caches only registry leaf libraries: library crates downloaded from a Cargo registry that don't depend on other crates. Other compilations run normally. Cache keys retain absolute paths and environment inputs, so reuse across different checkout locations isn't supported yet.

## Enable caching {#enable-caching}

Follow the <.localized_link href="/guides/get-started/rust-project">Rust project setup</.localized_link> to connect your project and authenticate. Then run your build through Tuist:

```sh
tuist cargo build --release
```

Caching is automatic for eligible compilations. There is no additional cache configuration or enablement flag. Tuist discovers your account's cache endpoint and obtains cache credentials using your existing project and server configuration.

If you use mise, <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">configure a Cargo wrapper</.localized_link> to keep typing ordinary `cargo` commands.

## How it works {#how-it-works}

For each eligible compilation, Tuist:

1. Checks its local cache for matching outputs.
2. On a local miss, queries Kura through the Remote Execution API (REAPI), downloads any missing content, and verifies the outputs before restoring them.
3. On a cache miss, runs the compiler normally. After a successful compilation, it stores the outputs locally and uploads them to Kura through REAPI when authorized. The remote cache entry is published only after all of its referenced content is available.

Local and CI builds use the same remote cache protocol. Read and write access come from Tuist's server-issued cache credentials and your account's <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">cache upload policy</.localized_link>. An account can allow developers to download while restricting uploads to CI and account tokens. Cache writers are trusted code producers: cached compiler outputs are executable code, so only grant write access to machines and tokens you trust.

If remote setup fails, local caching remains available. Unavailable, missing, or corrupt cache entries fall back to compilation. An upload failure doesn't fail the build or discard its local cache entry.

## What can be cached {#what-can-be-cached}

The current cache supports eligible registry leaf libraries producing Rust library artifacts and their accompanying metadata, dependency information, and supported split-debug outputs.

The following still build normally:

- Workspace crates and libraries with dependencies on other crates.
- Build scripts, procedural macros, and crates that depend on their outputs.
- Executables, test binaries, native linking, and C/C++ compilations.
- Incremental compilations, custom targets, and unsupported compiler arguments or source inputs.
- Metadata-only `cargo check` invocations.
- Compilations that emit rendered diagnostics or unexpected compiler output.

A pre-existing global compiler wrapper disables Tuist's compilation cache and compiler observer. Custom workspace wrappers also bypass caching. See <.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">compiler tool compatibility</.localized_link>.

Cache keys include the package contents, compiler and toolchain, arguments, working directory, and build environment. Credentials, Tuist reporting settings, and recognized CI run metadata don't invalidate entries. Crates that read those excluded variables during compilation aren't cached. Keep the other inputs and their absolute paths consistent when testing reuse. Remote transport support does not make outputs relocatable between different checkout paths.

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

If you see no hits, check that your build contains eligible registry leaf libraries, that another compiler wrapper isn't taking precedence, and that the compiler, flags, environment, and paths match the build that populated the cache. For remote uploads, also check authentication and the account's cache upload policy.
