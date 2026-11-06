# Cargo sharding end-to-end fixture

This dependency-free Rust project contains six tests across three nextest binaries. `e2e.sh` runs the production Tuist executable against a real server and real object storage, not a mocked shard endpoint.

## Running

Provide `TUIST_E2E_CLI` (an absolute path to the built CLI), `TUIST_URL`, `TUIST_PROJECT` (a dedicated Cargo project), and an authorized `TUIST_TOKEN`, then run `bash cli/Tests/Fixtures/CargoSharding/e2e.sh`. Cargo, rustup, nextest, and Python 3 must be available. Build the CLI using the repository's Xcode workflow first. Do not embed credentials or hardcode local database names in the fixture.

Set optional `TUIST_E2E_TEST_DELAY_MS=200` to give each test a deterministic runtime when verifying overlapping nextest timestamps and concurrency calibration. Leave it unset for the fastest archive/execution smoke test. A repeated run against the same isolated project can then use the first run's timing evidence; do not use CPU count as the expected measured concurrency.

The runner copies sources into a temporary directory, builds/uploads a nextest archive, and executes two isolated workers without a local archive or target directory. A rejecting compiler wrapper proves workers use downloaded products. A single append write per test records executions without interleaving parallel test output. Both repeated user filter expressions must stay intersected with the assigned binaries. The script checks disjointness, exactly-once execution, successful merged server reporting, empty filter intersections, and failure without execution for invalid indices, missing plans, missing remote archives, and suite-granularity plans. The shared server clamps plan size to available modules, so use an empty user filter rather than assuming it emits empty assignment indices. Logs and response JSON remain in the printed temporary directory.

Keep this real pipeline separate from fast Swift and server unit tests. Synthetic flaky/quarantine comparison histories are seeded by `server/priv/repo/seed_cargo_xcode_test_states.exs`; do not introduce nondeterminism into this fixture.
