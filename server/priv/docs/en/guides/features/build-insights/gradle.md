---
{
  "title": "Gradle Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Gradle task timings and cache behavior in the Tuist dashboard."
}
---
# Gradle build insights {#gradle-build-insights}

> [!WARNING]
> **Requirements**
>
> - The <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle plugin</.localized_link> installed and configured


Tuist's Gradle plugin can send build analytics to Tuist, giving you visibility into task execution and build performance.

## Configure upload behavior {#configure-upload-behavior}

By default:
- Build analytics are uploaded in the background for local builds.
- Build analytics are uploaded in the foreground for CI runs to avoid losing telemetry on short-lived agents.

You can control this behavior using `uploadInBackground` inside the `tuist` extension:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## Configuration reference {#configuration-reference}

The `uploadInBackground` option is available in the `tuist` extension block in `settings.gradle.kts`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null` (background locally, foreground on CI) | Whether to upload build insights in the background for local builds. |

This setting does not affect remote cache settings in the `buildCache` block.

## Custom metadata {#custom-metadata}

Attach tags and key-value data to Gradle builds to compare runs from different teams, hardware, or workflows. Tags are available as dashboard filters, and values appear on each build's detail page and in the application programming interface and Model Context Protocol tools.

Set metadata with environment variables:

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

You can also configure metadata in `settings.gradle.kts`:

```kotlin
tuist {
    buildInsights {
        tag("nightly")
        tag("android")
        value("ticket", "TUIST-123")
        value("runner", "macos-14")
    }
}
```

When the same value is configured in both places, the value in `settings.gradle.kts` takes precedence.

Tags must contain only letters, numbers, hyphens, and underscores. A build can have up to 50 tags, and each tag can contain up to 50 characters. A build can have up to 20 key-value entries, each key can contain up to 50 characters, and each value can contain up to 500 characters. These are the same server-side limits used for Xcode build metadata. The plugin skips invalid tags and oversized or empty metadata entries before it sends the report, so invalid configuration cannot prevent the rest of the build insights report from being stored. Use key-value metadata for values that do not meet the tag constraint.

Custom metadata is visible to project members in the dashboard and through the application programming interface and Model Context Protocol tools. Do not use it for credentials, access tokens, or other sensitive data. Tuist retains Gradle build data, including this metadata, for 90 days. See the <.localized_link href="/guides/server/data-retention">data retention policy</.localized_link> for details.

## Find recurring bottlenecks {#bottlenecks}

Open **Builds → Tasks** to rank work across builds. Start with cumulative execution time, then compare duration percentiles and cache hit rates. Use the **Environment** dropdown to compare local or CI builds, and the table’s **Filter** menu to narrow by branch. These filters apply to analytics and task executions as well.

**Executions** is selected by default. Select **Cache hit rate** to see its percentage over time, or the task duration widget to compare average, p50, p90, and p99 durations. The duration widget defaults to p90, and its dropdown changes the summary value. Use the chart legend to toggle individual duration series. Lines connect recorded duration samples across intervals without observations. Cumulative task time remains available in the tasks table.

Trends compare against the previous period. Cache hit rate changes use percentage points; a higher rate is positive. Longer task durations are negative. For count and duration metrics, a zero previous value produces an absolute change instead of a percentage. The task count is distinct across the full period; each chart point counts distinct tasks within its own interval.

A task's detail page shows analytics and a **Task executions** table with Project, Outcome, Branch, Ran by, Duration, and Ran at columns. **Ran by** shows CI for CI builds, the account name for local builds, or Unknown when the account is unavailable. Select a row to inspect that task execution, with a compact summary of duration, runner, cacheability, branch, and commit. Build identity and incremental status appear in the same details card. Execution details link back to the build and to the task overview. The Tasks table on an individual build opens these same execution details. Composite builds remain separate using their build paths and root project names. Historical reports retain task durations; detailed execution metadata requires the updated Gradle plugin.

| Metric | Meaning |
| --- | --- |
| Executions | Tasks with the `executed` outcome, shown as Succeeded in the execution table; cache hits, up-to-date, skipped, failed and no-source tasks are separate outcomes. |
| Misses | Confirmed remote lookups that returned no entry. A disabled cache, local hit or failed lookup is not a remote miss. |
| Cache hit rate | Remote hits divided by remote hits plus confirmed misses. Cacheable tasks without hits show 0%. Non-cacheable tasks and tasks with unknown cacheability and no lookups show an unavailable state instead of a numeric rate. |
| Avg. duration | Average duration of executed tasks. |
| p50 / p90 / p99 duration | Durations below which 50%, 90% and 99% of executed tasks fall. |
| Cumulative task time | Sum of executed task durations across matching builds. Parallel work overlaps, so this is not elapsed build time or time that splitting a module will necessarily save. |

Execution collection uses Gradle's internal operation APIs and is compatible with configuration-cache reuse. Reports identify the telemetry version. Cache hits with an unobserved origin are reported as `cache_hit` rather than attributed to the local or remote cache.

Cache transfer timings are not collected. Throughput widgets show No data; task duration is not used as transfer time.
