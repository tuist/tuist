---
{
  "title": "Once Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute a portable Once test plan across CI workers and consolidate the results in Tuist."
}
---
# Once test sharding {#once-test-sharding}

Once plans and executes test batches across CI workers through its native Tuist
integration. Tuist stores the plan, assigns batches to workers, and combines their
reports into one sharded test run. You invoke Once directly; the Tuist CLI is not
required.

This integration requires a Once version with hosted sharding (`once query
test-plan --shards` and `once test --shard-plan`), a Tuist server supporting
externally grouped Once runs, and account enrollment in immutable shard reporting.
Once 0.71.0 introduced portable plans but does not include the hosted commands.
Contact the Tuist team for enrollment. Upgrade every server and processor before
enrollment and before using hosted sharding to avoid duplicate native reports.

## Configure Tuist {#configure-tuist}

Use your existing Once Tuist configuration, or configure the provider in your
workspace's `once.toml`:

```toml
[infrastructure.cache]
provider = "tuist"

[infrastructures.tuist]
kind = "tuist"
account = "account"
project = "project"
```

Sign in with `once auth login --provider workspace`, or supply `TUIST_TOKEN` in
CI. Planning and execution use the same native credentials and project
configuration as Once's other Tuist integrations.

## Plan the shards {#plan-the-shards}

Run Once from your workspace:

```sh
once query test-plan --shards 4 --reference pipeline-123 --format json
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
batches, successfully run the relevant targets once before planning. A failed
initial discovery can retain the whole-target fallback. Tuist never splits a
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
once test --shard-plan PLAN_UUID --shard-index 0 --jobs 2
```

`--jobs` controls concurrent Once batches on this worker, not the number of CI
workers. Once downloads the frozen plan and its assignments from Tuist before
executing them; you do not need a separate download command or a Tuist wrapper.

Alternatively, supply `TUIST_SHARD_PLAN_ID` and `TUIST_SHARD_INDEX`. Execution
attempts default to the CI provider's attempt number or 1. For other providers,
increase `--shard-attempt` or `TUIST_SHARD_ATTEMPT` when rerunning a plan so new
reports replace older attempts.

All assigned batches run even when one fails. A failed test, interrupted process,
stale plan, or incomplete execution fails the worker; missing results never mark
a shard successful. An empty assignment reports success without executing tests.
Retries remain attempts of the same test case, and native target and suite names
remain unchanged in Test Insights. Native Once events remain diagnostic records;
Once submits one consolidated shard report. Test Insights uses the same
target/suite/test-name identity as other build systems.

## GitHub Actions {#github-actions}

After installing a compatible Once version and your project's dependencies in
both jobs:

```yaml
jobs:
  plan:
    runs-on: ubuntu-latest
    outputs:
      plan: ${{ steps.plan.outputs.shard-plan-id }}
      shards: ${{ steps.plan.outputs.shards }}
    steps:
      - uses: actions/checkout@v4
      # Install Once, toolchains and project dependencies here.
      - id: plan
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: |
          once query test-plan --shards 4 --format json > plan.json
          echo "shard-plan-id=$(jq -r '.shard_plan_id' plan.json)" >> "$GITHUB_OUTPUT"
          echo "shards=$(jq -c '.shards' plan.json)" >> "$GITHUB_OUTPUT"

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
        run: once test --jobs 2
```
