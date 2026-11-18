---
{
  "title": "Once Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Plan Once test batches through Tuist, distribute them across CI workers, and inspect a combined test run."
}
---
# Once test sharding {#once-test-sharding}

When your test suite outgrows a single machine, Once can ask Tuist to distribute its discovered test batches across CI workers. Workers execute their assignments through Once, and Tuist combines their reports into one test run.

> [!IMPORTANT]
> **Requirements**
>
> - Complete <.localized_link href="/guides/get-started/once-project">Get started with Once</.localized_link>.
> - Use a Once release that exposes `once query test-plan --shards` and `once test --shard-plan`. Once 0.71.0 supports portable plans only, not this hosted workflow.
> - Have complete discovery for the selected test targets, and the same checkout and test environment available on the workers.

No Tuist CLI wrapper is required. Once uses its native Tuist provider and credentials.

## Discover your tests {#discover-your-tests}

Run the selected tests to establish discovery before planning:

```bash
once test MyTests --format json
```

The available batch granularity depends on the runner. Some test targets support file or case batches; others remain target-level. Follow [Once's testing guide](https://buildonce.dev/docs/guide/graph/testing) for discovery and batching capabilities.

## Create a hosted plan {#create-a-hosted-plan}

In the planning job, use a reference shared by this CI execution:

```bash
once query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

The response contains a hosted plan ID and the actual worker indices:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

Build your CI matrix from `shards`, rather than assuming it contains four entries. An empty plan returns an empty ID and array, so no workers need to start. Pass `--target` to narrow the plan or repeat `--changed-path` to use Once's graph-based selection.

The reference defaults to `TUIST_SHARD_REFERENCE` or the detected CI run. Pass it explicitly when the environment has no supported CI identifier.

## Execute each shard {#execute-each-shard}

Give every worker the returned plan ID and its own index:

```bash
once test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

Alternatively, set `TUIST_SHARD_PLAN_ID` and `TUIST_SHARD_INDEX`. Workers download the exact UUID-bound plan and execute only their assigned batches. An empty assignment runs nothing; missing results, failed processes, and interrupted work cannot pass the partition.

This distributes a test plan, not a precompiled test-build archive. Prepare the required sources, tools, and discovery on workers; shared caching can avoid repeating eligible build work.

## Reruns and results {#reruns-and-results}

For a rerun, increase `--shard-attempt`, or set `TUIST_SHARD_ATTEMPT`. Once otherwise uses the GitHub run attempt, then defaults to 1. `--shard-report-revision` defaults to 0 and can increase when correcting a report within the same attempt. These counters are separate from a test's retries.

Open **Tests → Shards** to inspect the plan, balance, and reported workers, then open the combined test run for individual results. Once's scheduling units are labeled **Batches**; cases retain their native target, suite, and test names.

See <.localized_link href="/guides/features/test-insights/once">Once test insights</.localized_link> for reporting detail and coverage limitations.
