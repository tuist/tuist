# Cargo code coverage fixture

A dependency-free Rust 2024 package for `tuist cargo` coverage: a library (`src/lib.rs`, with a generic `apply` and a `classify` whose branches the tests cover unevenly), a module with methods (`src/shapes.rs`), a binary with a unit test (`src/bin/tool.rs`), integration tests (`tests/api.rs`) and a helper module they share (`tests/common/mod.rs`), and one doctest. `TUIST_FIXTURE_FAIL=1` makes the library's `fails_on_request` test fail without changing source files. Tests assert line numbers in `src/lib.rs` and `src/shapes.rs`: append to those files rather than inserting above existing code.

`CargoCoverageTests.collectsRealCargoAndNextestCoverage` copies the fixture into a temporary directory through `TuistTestSupport.TestPaths` and collects real coverage from plain `cargo test` (target evidence and overlapped tests) and, when installed, `cargo nextest run` (per-test evidence). It needs the `llvm-tools` rustup component and is skipped without it.

## Public CLI coverage smoke

```sh
TUIST_CLI_BINARY=/absolute/path/to/freshly/built/tuist \
  /usr/bin/ruby cli/Tests/Fixtures/CargoCoverage/e2e.rb
```

Requires stable Rust with `llvm-tools`, Ruby with the standard-library WEBrick server (macOS's `/usr/bin/ruby`, 2.6 compatible) and optionally `cargo-nextest`. Use a CLI binary built without coverage counters (`CLANG_COVERAGE_MAPPING=NO`): an instrumented `tuist` writes its own `default.profraw` into the checkout. The harness commits the fixture into a Git repository whose remote is a local bare repository, turns coverage on through `tuist.toml`, and runs the public CLI against a loopback receiver that validates every test-run request against the checked-in OpenAPI spec and answers the coverage settings, upload, Git history, quarantine, shard and completion endpoints. It covers coverage off, full plain and nextest runs, a report uploaded above the inline threshold, narrowed runs (`--test`, `--skip`, `-E`), fail-fast and `--no-fail-fast` failures, a quarantine skip, plain and archive-based shards whose union matches the full run (archive shards run in separate clones, as CI workers do, so their coverage maps name the build checkout's paths), and `coverage-complete`. Every run must leave the checkout clean.

The receiver binds only to loopback and uses a dummy project and token; artifacts stay in a temporary directory the script prints. It exercises the CLI-to-HTTP boundary, not Phoenix authorization, ClickHouse persistence or dashboard rendering.

Keep `target/` and `Cargo.lock` out of version control (`.gitignore`). Do not add dependencies.
