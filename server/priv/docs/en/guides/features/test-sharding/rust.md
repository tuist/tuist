---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Compile a nextest archive once and distribute Rust test binaries across compatible CI runners."
}
---
# Rust test sharding {#rust-test-sharding}

Tuist compiles your tests once, uploads a nextest archive, and assigns whole test binaries to parallel workers. The workers download the archive and execute their assigned tests without recompiling. Their results merge into one test run in the dashboard.

> [!IMPORTANT] Requirements
> - Configure <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>.
> - Build and worker jobs need the Tuist CLI, Cargo, cargo-nextest, authentication, and the same project configuration.
> - Workers must be compatible with the archive's OS, architecture, and runtime dependencies.

## Build once {#build-phase}

Give each pipeline attempt a unique reference shared by the build and workers:

```sh
export TUIST_SHARD_REFERENCE="${CI_PIPELINE_ID}-${CI_JOB_ATTEMPT}"
tuist cargo test-build --workspace --shard-total 4
```

Replace the example variables with your provider's pipeline and attempt identifiers. Tuist can also derive a reference on supported CI providers. A commit SHA alone is not unique across reruns of the same commit.

`test-build` runs `cargo nextest archive`, enumerates its binaries, creates a plan, and uploads the archive. Cargo compilation options such as features and target selection belong in this phase.

| Option | Meaning |
| --- | --- |
| `--shard-total <N>` | Request a fixed number of shards. |
| `--shard-min <N>` | Minimum number of shards. |
| `--shard-max <N>` | Maximum number of shards. |
| `--shard-max-duration <MS>` | Target shard duration in **milliseconds**. |

The server caps the shard count at the available binary count. Always consume the emitted shard indexes rather than assuming your requested count was used.

The command prints JSON:

```json
{"shard_plan_id":"<plan-uuid>","shards":[0,1,2,3]}
```

On GitHub Actions it also appends the `shard-plan-id` and `shards` step outputs to `GITHUB_OUTPUT`.

## Execute workers {#test-phase}

Each worker checks out the same revision and gets a distinct zero-based index:

```sh
TUIST_SHARD_PLAN_ID="$PLAN_ID" TUIST_SHARD_INDEX=0 \
  tuist cargo nextest run --profile ci
```

The plan ID can identify the plan without a reference. Otherwise, provide the same `TUIST_SHARD_REFERENCE` as the build job. Worker options should configure nextest execution, not change the already archived compilation selection.

Tuist remaps the archive to the worker checkout. Workers still need test fixtures, native libraries, and any files the tests open at runtime. Check [nextest's archive constraints](https://nexte.st/docs/ci-features/archiving/) before distributing archives across machines, especially if your tests embed build-time absolute paths.

User filtersets narrow the assigned binaries; repeated `-E` expressions retain nextest's union semantics and are intersected with the assignment. An empty intersection succeeds without running tests. A missing or incompatible plan, missing local archive, or failed download fails the job instead of running the whole suite. Nightly Cargo `-C` is not supported for sharding; change into the workspace first.

## Parallelism and estimates {#parallelism}

Nextest can run tests both within a binary and across binaries concurrently. Summing all test durations would overstate a binary's elapsed time; summing binary durations would likewise overstate a worker's wall time.

Tuist uses timestamped test execution windows for binary timings, declares the binaries as concurrent units, and uses the shared concurrency-aware shard planner. History measures the achieved concurrency from valid shard reports rather than assuming CPU count or `--test-threads` is fully utilized. The shard estimate has a floor at its longest binary.

Without usable concurrency history, planning uses conservative summed estimates. New binaries get a historical/default duration estimate. Keep runner resources, nextest profiles, test groups, and thread settings consistent: estimates are not a guarantee, and changing them can invalidate historical assumptions. Binary-level sharding cannot split one very large binary across workers.

## GitHub Actions {#github-actions}

Install and pin Tuist, Rust, and cargo-nextest in your repository's mise configuration. Then use the build step's outputs for your worker matrix:

```yaml
name: Rust tests
on: [pull_request]

env:
  TUIST_PROJECT: account/project
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
  TUIST_SHARD_REFERENCE: ${{ github.run_id }}-${{ github.run_attempt }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      plan: ${{ steps.plan.outputs.shard-plan-id }}
      shards: ${{ steps.plan.outputs.shards }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v3
      - id: plan
        run: tuist cargo test-build --workspace --shard-total 4

  test:
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.shards) }}
    env:
      TUIST_SHARD_PLAN_ID: ${{ needs.build.outputs.plan }}
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v3
      - run: tuist cargo nextest run
```

Outside GitHub Actions, capture the JSON output and pass its plan ID and indexes to your provider's parallel jobs.

## Bring your own artifact storage {#local-archives}

Set `TUIST_TEST_SHARD_ARCHIVE_PATH` on the build and workers to a path managed by your CI artifact mechanism. The build writes the archive there and skips Tuist's archive upload; each worker must download that file before starting nextest. Tuist still creates and authorizes the server-side binary assignments.

Doctests remain a separate `tuist cargo test --doc` job. Cargo sharding does not apply dashboard quarantine or coverage-based test selection.
