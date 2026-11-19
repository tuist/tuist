---
{
  "title": "Struo Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Plan Struo test batches through Tuist, distribute them across CI workers, and inspect a combined test run."
}
---
# Struo test sharding {#struo-test-sharding}

<a id="once-test-sharding"></a>

When your test suite outgrows a single machine, Struo can ask Tuist to distribute its discovered test batches across CI workers. Workers execute their assignments through Struo, and Tuist combines their reports into one test run.

> [!IMPORTANT]
> **Requirements**
>
> - Complete <.localized_link href="/guides/get-started/struo-project">Get started with Struo</.localized_link>.
> - Use [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) or later, with `struo query test-plan --shards` and `struo test --shard-plan`.
> - Have complete discovery for the selected test targets, and the same checkout and test environment available on the workers.

No Tuist CLI wrapper is required. Struo uses its native Tuist provider and credentials.

## Discover your tests {#discover-your-tests}

Run the selected tests to establish discovery before planning:

```bash
struo test MyTests --format json
```

The available batch granularity depends on the runner. Some test targets support file or case batches; others remain target-level. Follow [Struo's testing guide](https://struo.run/docs/guide/graph/testing) for discovery and batching capabilities.

## Create a hosted plan {#create-a-hosted-plan}

In the planning job, use a reference shared by this CI execution:

```bash
struo query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

The response contains a hosted plan ID and the actual worker indices:

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

Build your CI matrix from `shards`, rather than assuming it contains four entries. An empty plan returns an empty ID and array, so no workers need to start. Pass `--target` to narrow the plan or repeat `--changed-path` to use Struo's graph-based selection.

The reference defaults to `TUIST_SHARD_REFERENCE` or the detected CI run. Pass it explicitly when the environment has no supported CI identifier.

## Execute each shard {#execute-each-shard}

Give every worker the returned plan ID and its own index:

```bash
struo test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

Alternatively, set `TUIST_SHARD_PLAN_ID` and `TUIST_SHARD_INDEX`. Workers download the exact UUID-bound plan and execute only their assigned batches. An empty assignment runs nothing; missing results, failed processes, and interrupted work cannot pass the partition.

This distributes a test plan, not a precompiled test-build archive. Prepare the required sources, tools, and discovery on workers; shared caching can avoid repeating eligible build work.

## Reruns and results {#reruns-and-results}

For a rerun, increase `--shard-attempt`, or set `TUIST_SHARD_ATTEMPT`. Struo otherwise uses the GitHub run attempt, then defaults to 1. `--shard-report-revision` defaults to 0 and can increase when correcting a report within the same attempt. These counters are separate from a test's retries.

Open **Tests → Shards** to inspect the plan, balance, and reported workers, then open the combined test run for individual results. Struo's scheduling units are labeled **Batches**; cases retain their native target, suite, and test names.

See <.localized_link href="/guides/features/test-insights/struo">Struo test insights</.localized_link> for reporting detail and coverage limitations.
