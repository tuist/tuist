# Cargo cache smoke fixtures

This fixture validates the Swift compiler-cache hook with real Cargo/rustc, without a server, credentials, or a separate cache executable. `itoa` is a registry leaf library; the application remains uncached.

```sh
TUIST_CLI_BINARY=/absolute/path/to/freshly/built/tuist \
  bash cli/Tests/Fixtures/CargoCache/e2e.sh
```

Fetch the pinned dependency with ordinary Cargo first if it is not already available. The script builds offline in a temporary checkout, removes Cargo's outputs between runs, and checks:

- Cold: one cache miss and two observed compiler executions.
- Warm: one cache hit, with only the application compiler execution observed.
- Corrupt artifact: safe fallback to compilation and repair, not an invalid restore.
- Every executable prints `42`. Split debug objects are retained alongside cached libraries.

The local cache and reports belong to the temporary fixture, never the user's normal Tuist cache. Successful runs remove it; failures retain the directory and compiler arguments/context for diagnosis. Do not alter downloaded registry source files to test invalidation; unit tests use synthetic package/toolchain directories for that purpose.

## Native public CLI integration

`native_e2e.py` requires a freshly built `tuist` with the freshly built native
helper staged beside it. It runs the public command, real Cargo/rustc and an
isolated loopback-only mock API, never a production service:

```sh
TUIST_CLI_BINARY=/absolute/path/to/freshly/built/tuist \
  python3 cli/Tests/Fixtures/CargoCache/native_e2e.py
```

The fixture clears inherited Tuist/GitHub/wrapper settings, uses private temporary
Cargo/target/cache directories, and supplies only a synthetic loopback token.
It checks native workspace-library/build-script reuse after deleting Cargo
outputs, the actual aggregate/detail payload through the Swift reporting path,
source invalidation, and digest-corruption fallback while running each produced
executable. A mock API does not validate real-server authorization or Kura.

## Swift fallback public CLI and real remote transport

`remote_e2e.py` drives the public command, not the private compiler hook. Its cache-layout and counter assertions target the Swift fallback: use a source-built CLI without a native sibling. Run it against an isolated local project, server, real Kura and ClickHouse:

```sh
TUIST_CLI_BINARY=/absolute/path/to/tuist \
TUIST_PROJECT=owner/project TUIST_URL=http://localhost:8080 \
TUIST_CACHE_ENDPOINT=http://localhost:9090 \
TUIST_CARGO_E2E_CLICKHOUSE_URL=http://localhost:8123 \
TUIST_CARGO_E2E_CLICKHOUSE_DB=isolated_development \
python3 cli/Tests/Fixtures/CargoCache/remote_e2e.py
```

Supply `TUIST_TOKEN` privately. Do not use production data. Configure matching server cache-token signing and Kura verification keys (ES256), and writable local S3 for the separate sharding fixture. Kura needs the account header and project-only REAPI instance name, not the full handle as its instance. Purpose-bound cache tokens are not ordinary API credentials.

The fixture simulates protected GitHub push variables only to exercise remote-write eligibility; it does not claim to run on GitHub or manufacture a CI run URL. A real temporary Git checkout gives its recorded builds a unique branch. Its `XDG_CACHE_HOME` and target are temporary and isolated. Every scenario removes Cargo outputs, verifies executable behavior, and checks actual ingested task decisions, compiler executions and transfer counters. It covers cold publication, remote reuse with the publisher's entire local cache moved away, local hits, corrupt-blob repair, unavailable-cache fallback, and recovery on the next command. Analytics may arrive asynchronously, so the checker polls for complete reports. Successful and failed runs retain logs/timings/build IDs outside the repository.

Pass `--benchmark` to generate a standard Cargo local-registry leaf with substantial compiler work. This is an explicitly generated workload, not a representative real-world application. The driver compares three ordinary Cargo clean builds against three public-CLI local hits; timings include CLI setup/reporting. Chunked uploads leave transferred-byte provenance unknown rather than counting the full spliced parent size, so the benchmark does not require a positive cold upload counter; the subsequent remote hit after moving the publisher cache proves publication independently. Do not run benchmarks concurrently or present a small fixture's compiler avoidance as a wall-clock speedup. Tiny crates may cost less to compile than the cache/decorator overhead.

These fixtures do not qualify cross-worker relocation: cache keys intentionally retain absolute paths and the effective environment. The Swift fixtures exercise the fallback; `native_e2e.py` exercises the restored model under `cli/native/cargo-cache/`. Rust programs in this fixture directory remain inputs for Cargo to compile.
