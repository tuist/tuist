# Plain Cargo test reporting fixture

A dependency-free Rust 2024 package exercising the production stable Cargo/libtest adapter. It contains three unit tests, two integration tests (including a target named `doc`), and five doctests: normal, `should_panic`, `compile_fail`, ignored, and `no_run`. `TUIST_FIXTURE_FAIL=1` makes one unit test fail without changing source files.

`CargoTestReportTests.observesRealStableCargoTestsAndDoctests` copies this fixture into its test temporary directory using `TuistTestSupport.TestPaths`, then runs the production `CargoTestService` against real Cargo for a full run, a doctest-only run, and failed runs with and without `--no-fail-fast`. It verifies module attribution, all ten case outcomes, five doctest outcomes, and Cargo's exit code 101 on failure. It does not publish telemetry or require authentication. Rust/Cargo must be installed on the test host.

## Public CLI upload smoke

```sh
TUIST_CLI_BINARY=/absolute/path/to/freshly/built/tuist \
  /usr/bin/ruby cli/Tests/Fixtures/CargoTestReporting/e2e.rb
```

Requires stable Rust and Ruby with the standard-library WEBrick server (available in macOS's `/usr/bin/ruby`). No Python or third-party gems are required. The harness uses plain `cargo test` through a temporary PATH wrapper that delegates to the real public CLI. It compares successful test output with native Cargo, removes Cargo outputs to exercise the real compiler observer on a cold run, and checks actual authenticated HTTP build/test request fields against the checked-in OpenAPI spec (required fields, types, and enum values). It checks full runs, doctest-only runs, filtering, fail-fast and non-fail-fast failures, no-run/list/quiet/verbose bypasses (including Cargo environment settings), and successful/failing test exits when the receiver rejects uploads. A noisy failure with a consumer stalled for three seconds verifies that all 1,500 captured lines and the failure summary survive backpressure. A filtered run can intentionally leave a 30-second sleep holding inherited pipes (`TUIST_FIXTURE_LEAK_PID`), or a logger writing every 50 ms (`TUIST_FIXTURE_TICK`); the harness requires prompt successful exits without partial test uploads, then terminates the fixture helpers. It adds a sibling workspace member with the same integration target name to verify explicit package selection and omission of genuinely ambiguous workspace reports. It also adds a non-member path dependency with colliding library and integration target names, verifying that dependency, version-qualified, and glob package selections execute without misattributed uploads. A `cargo-nextest` sentinel fails if nextest is invoked.

The receiver binds only to loopback and uses a dummy project/token; caches, copied source, logs, and captured request JSON belong to a retained temporary directory printed by the script. It never sends reports to production or requires real credentials. This exercises the CLI-to-HTTP boundary, not Phoenix authorization, ClickHouse persistence, or dashboard rendering. Do not describe it as a real-server persistence test.

Keep `target/` and generated lockfiles out of version control. The fixture has no external dependencies; do not add nextest or nightly requirements. Parser tests also cover filters, ignored reasons, ANSI output, merged doctest sections, malformed/incomplete output, and stable identities independent of executable hashes.
