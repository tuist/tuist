---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Cargo test targets across CI workers using historical test durations."
}
---
# Rust test sharding {#rust-test-sharding}

Tuist distributes Cargo test targets across CI workers using historical target durations. Unit-test targets, integration-test targets, and each library's doctests are separate modules. Tests within one target stay together.

> [!IMPORTANT] Requirements
> - Configure <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> and authenticate the CLI on the planning job and workers.
> - Select one package, using `-p <package>` in a workspace. Multi-package sharding is not supported.
> - Use the same revision, Rust toolchain, package selection, features, and test filters in every job.

## Create a plan {#create-a-plan}

Add a shard count to `--no-run` to compile and enumerate targets without executing tests:

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

The command prints JSON containing `shard_plan_id` and a zero-based `shards` array. In GitHub Actions, it also writes `shard-plan-id` and `shards` to `GITHUB_OUTPUT`. Without an explicit reference, Tuist derives one from the supported CI environment.

| Option | Description |
| --- | --- |
| `--shard-max N` | Maximum number of shards |
| `--shard-min N` | Minimum number of shards |
| `--shard-total N` | Exact count, up to the available targets |
| `--shard-max-duration N` | Target maximum shard duration in milliseconds |

Use `--shard-total` alone or combine `--shard-min` and `--shard-max`. Without historical durations, the planner uses default target estimates. Ordinary `--no-run` without shard options remains a build-only command.

## Execute each shard {#execute-each-shard}

Set the plan ID and shard index on each worker, then use the same Cargo test arguments:

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

Alternatively, set `TUIST_SHARD_REFERENCE` to the planning job's reference instead of passing the plan ID. Tuist fetches the assignment and asks Cargo to execute only those targets. Invalid or incompatible assignments fail the command rather than running all tests. Empty assignments execute no tests. Results from the workers are linked to the plan in Test Insights, and <.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantine">quarantine</.localized_link> applies within each shard.

## Limits {#limits}

This is target-level sharding, not build-once distribution. Each worker needs the source checkout and builds its own targets; the <.localized_link href="/guides/features/cache/rust">Cargo compilation cache</.localized_link> can reuse eligible compilation outputs. Tuist does not upload test executables or require another Rust test runner.

Sharding requires one selected package. Narrowing a multi-package command can change Cargo's unified dependency features, so Tuist rejects it instead of running tests with a different feature graph. Plan each package separately until multi-package sharding is supported.

Sharding requires standard libtest harnesses and captured default output. Quiet, verbose, alternate-format, uncaptured-output, and custom-harness commands are rejected. If Cargo cannot uniquely identify a target, select an exact workspace package with `-p <package>`. Dependency packages, version-qualified selectors, package/target-name globs, and Cargo's nightly `-C` option are unsupported for sharding. Keep test selection identical between planning and execution.
