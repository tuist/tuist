# Swift Cargo cache smoke fixture

This fixture validates the Swift compiler-cache hook with real Cargo/rustc, without a server, credentials, or a separate cache executable. `itoa` is a registry leaf library; the application remains uncached.

```sh
TUIST_CLI_BINARY=/absolute/path/to/freshly/built/tuist \
  bash cli/Tests/Fixtures/CargoCache/e2e.sh
```

Fetch the pinned dependency with ordinary Cargo first if it is not already available. The script builds offline in a temporary checkout, removes Cargo's outputs between runs, and checks:

- Compiler hooks work even when the generic CLI state directory is unavailable; they must not initialize logging sessions.
- Cold: one cache miss and two observed compiler executions.
- Warm: one cache hit, with only the application compiler execution observed.
- Corrupt artifact: safe fallback to compilation and repair, not an invalid restore.
- Every executable prints `42`. Split debug objects are retained alongside cached libraries.

The local cache and reports belong to the temporary fixture, never the user's normal Tuist cache. Successful runs remove it; failures retain the directory and compiler arguments/context for diagnosis. Do not alter downloaded registry source files to test invalidation; unit tests use synthetic package/toolchain directories for that purpose.

## Public CLI and real remote transport

`remote_e2e.py` drives the public command, not the private compiler hook. Run it against an isolated local project, server, real Kura and ClickHouse:

```sh
TUIST_CLI_BINARY=/absolute/path/to/tuist \
TUIST_PROJECT=owner/project TUIST_URL=http://localhost:8080 \
TUIST_CACHE_ENDPOINT=http://localhost:9090 \
TUIST_CARGO_E2E_CLICKHOUSE_URL=http://localhost:8123 \
TUIST_CARGO_E2E_CLICKHOUSE_DB=isolated_development \
python3 cli/Tests/Fixtures/CargoCache/remote_e2e.py
```

Supply `TUIST_TOKEN` privately. Optionally supply `TUIST_CARGO_E2E_READER_TOKEN` with a distinct read-only cache credential for the remote/repair/recovery phases and extra reader-miss/reader-local phases; reuse must not depend on the publisher's token, and a reader miss must remain locally cacheable without uploads or upload-failure rows. Do not use production data. Configure matching server cache-token signing and Kura verification keys (ES256), and writable local S3 for the separate sharding fixture. Kura needs the account header and project-only REAPI instance name, not the full handle as its instance. Purpose-bound cache tokens are not ordinary API credentials.

The fixture clears GitHub and inherited internal cache settings; remote publication must work without CI-provider or protected-branch flags, using the token's server-authorized cache grants. Each phase changes standalone CI job/run identifiers without claiming a CI provider; this must not invalidate eligible cache entries. A real temporary Git checkout gives its recorded builds a unique branch. Its `XDG_CACHE_HOME` and target are temporary and isolated. Every scenario removes Cargo outputs, verifies executable behavior, and checks actual ingested task decisions, compiler executions and transfer counters. It covers cold publication, remote reuse with the publisher's entire local cache moved away, local hits, corrupt-blob repair, unavailable-cache fallback, and recovery on the next command. Analytics may arrive asynchronously, so the checker polls for complete reports. Successful and failed runs retain logs/timings/build IDs outside the repository.

Pass `--benchmark` to generate a standard Cargo local-registry leaf with substantial compiler work. This is an explicitly generated workload, not a representative real-world application. The driver compares three ordinary Cargo clean builds against three public-CLI local hits; timings include CLI setup/reporting. Chunked uploads leave transferred-byte provenance unknown rather than counting the full spliced parent size, so the benchmark does not require a positive cold upload counter; the subsequent remote hit after moving the publisher cache proves publication independently. Do not run benchmarks concurrently or present a small fixture's compiler avoidance as a wall-clock speedup. Tiny crates may cost less to compile than the cache/decorator overhead.

These fixtures do not qualify cross-worker relocation: cache keys intentionally retain absolute paths and the effective environment. All cache logic remains Swift; the Rust sources here are only programs Cargo compiles.

## Dependency and generated-input admission

```sh
TUIST_CLI_BINARY=/absolute/path/to/freshly/built/tuist \
  python3 cli/Tests/Fixtures/CargoCache/coverage_e2e.py
```

This offline fixture creates a workspace with a generated-source library and two downstream libraries. Each phase removes Cargo outputs and uses a new private compiler session. Cold builds miss, unchanged builds restore all three, generated input changes invalidate all three, and changing the middle library preserves only the generated library hit. Every phase compares executable output against a fresh uncached Cargo build.

A proc macro reading an undeclared external file, an upstream generic using inline assembly with an assembler `.include`, and a `naked_asm!` function stay uncached. Mutating each external file must change program output without invalidating unrelated eligible libraries. This protects the transitive admission boundary: successful dep-info resolution and direct extern hashes alone cannot certify those backend/macro reads. Metadata admission must be available before Cargo pipelines a dependent compiler, not only when upstream codegen finishes. The assembly fixture supports aarch64 and x86-64 hosts. Success removes its temporary workspace; failure retains all sources, reports and logs.

The direct-compiler guard cases also exercise an implicit proc macro hidden behind grouped `-gL` search options and a loader-library-search override. These must execute normally without a cache decision; changing the macro's undeclared input must change the linked program. Loader guards are conservative: `LD_`/`DYLD_` settings bypass caching, including Cargo's ordinary Linux `LD_LIBRARY_PATH`. The positive cache-reuse scenarios are currently qualified on macOS, not Linux.

## Native build-script compiler actions

On arm64 macOS with Xcode:

```sh
TUIST_CLI_BINARY=/absolute/path/to/freshly/built/tuist \
  python3 cli/Tests/Fixtures/CargoCache/native_e2e.py
```

This fixture exercises `cargo __native` with real Clang and verifies linked executable output against uncached Clang. It checks cold/warm reuse, corrupt-blob fallback, header edits, a newly present `__has_include` file without a corresponding `#include`, and an earlier search-path header shadowing an unchanged old header. SDK declaration asm labels and empty instruction templates remain eligible. Caller-owned dependency outputs and assembler `.include` inputs bypass caching; changing the assembler input still changes the program. The hook must work with an unavailable generic CLI state directory. Full public Cargo benchmarks separately qualify wrapper installation, normal build-script execution and remote storage.

Header symlinks must support warm reuse and invalidate when retargeted. C23 digit separators must not hide assembly from source admission, and response files in option operands must bypass caching so caller-owned outputs are preserved. The small fixture runs local-only; remote native caching intentionally bypasses sources smaller than 32 KiB to avoid spending more on discovery and transfer than compilation.

## Dependency units

```sh
TUIST_CLI_BINARY=/absolute/path/to/freshly/built/tuist \
  python3 cli/Tests/Fixtures/CargoCache/units_e2e.py
```

Offline and local-only, through the public command. A cold build publishes `itoa`'s unit; the same project at another path restores it and Cargo compiles only the application; different rustflags in `.cargo/config.toml` miss; a corrupted stored rlib is never linked. Every build's program must print `42`.
