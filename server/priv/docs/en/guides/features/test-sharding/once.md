---
{
  "title": "Once Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute a portable Once test plan across CI workers and consolidate the results in Tuist."
}
---
# Once test sharding {#once-test-sharding}

Tuist distributes Once test batches across CI workers. Once decides which tests
can run together and executes each worker's batches with its native scheduler.
Tuist stores the plan and combines the workers' reports into one sharded test run.

This integration requires Once 0.71.0 or newer, a Tuist server supporting externally
grouped Once runs, and account enrollment in immutable shard reporting. Planning
rejects legacy reporting because it cannot safely replace earlier shard attempts.
Contact the Tuist team for enrollment. Upgrade every server and processor before
enrollment and before using the new CLI commands to avoid duplicate native reports.

## Plan the shards {#plan-the-shards}

Authenticate the Tuist CLI using your CI credentials, then run:

```sh
tuist test once plan --project account/project --reference pipeline-123 --shard-total 4
```

The command uploads the portable plan and prints a JSON object containing
`shard_plan_id` and the zero-based `shards` array. Pass the exact plan UUID to
every worker, including when rerunning only failed workers. The reference
defaults to `TUIST_SHARD_REFERENCE` or the supported CI provider's run reference.

Use `--target TARGET` to select one Once target, or repeat `--changed-path PATH`
to select targets affected by changed files. These options are mutually exclusive.
When no tests are selected, planning succeeds with an empty plan ID and shard
array; skip the worker jobs.

Once preserves file-level fixture boundaries and falls back to an atomic
whole-target batch when complete discovery is unavailable. To obtain finer
batches, run the relevant targets once before planning. Tuist never splits a
batch or infers test cases from historical results.

Batch-duration history is not yet connected to Tuist's planner. Once batches
currently receive default timing estimates, so plans balance batch counts rather
than measured execution time.

## Run each shard {#run-each-shard}

Each worker needs the same source revision, compatible Once version, toolchains,
dependencies, and test configuration as the planning job. It does not need the
planner's `.once` discovery state. This integration uploads the plan, not compiled
binaries; Once builds or restores the inputs it needs on each worker.

```sh
tuist test once run --project account/project \
  --shard-plan-id PLAN_UUID --shard-index 0 --jobs 2
```

`--jobs` controls concurrent Once batches on this worker, not the number of CI
workers. Both commands accept `--path` for a workspace directory and
`--executable` for a particular Once binary. The project can also come from your
Tuist configuration.

Alternatively, supply `TUIST_SHARD_PLAN_ID` and `TUIST_SHARD_INDEX`. Execution
attempts default to the CI provider's attempt number or 1. For other providers,
increase `--shard-attempt` or `TUIST_SHARD_ATTEMPT` when rerunning a plan so new
reports replace older attempts.

All assigned batches run even when one fails. A failed test, interrupted process,
stale plan, or incomplete execution fails the worker; missing results never mark
a shard successful. An empty assignment reports success without invoking Once.
Retries remain attempts of the same test case, and native target and suite names
remain unchanged in Test Insights. Native Once events remain diagnostic records;
the CLI submits one consolidated shard report.

## GitHub Actions {#github-actions}

Planning writes `shard-plan-id` and `shards` to the step's outputs. After installing
compatible Tuist and Once versions and your project's dependencies in both jobs:

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    outputs:
      plan: ${{ steps.plan.outputs.shard-plan-id }}
      shards: ${{ steps.plan.outputs.shards }}
    steps:
      - uses: actions/checkout@v4
      # Install Tuist, Once, toolchains and project dependencies here.
      - id: plan
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist test once plan --project account/project --shard-total 4

  test:
    needs: plan
    if: needs.plan.outputs.plan != ''
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.plan.outputs.shards) }}
    steps:
      - uses: actions/checkout@v4
      # Install the same tools and dependencies as the planning job.
      - env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
          TUIST_SHARD_PLAN_ID: ${{ needs.plan.outputs.plan }}
          TUIST_SHARD_INDEX: ${{ matrix.shard }}
        run: tuist test once run --project account/project --jobs 2
```
