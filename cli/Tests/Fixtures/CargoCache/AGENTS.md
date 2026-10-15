# Swift Cargo cache smoke fixture

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

Server ingestion and authenticated remote transport are separate integration boundaries. This offline fixture does not qualify remote authorization, cross-worker relocation, or performance. Cache keys intentionally retain absolute paths and the effective environment.
