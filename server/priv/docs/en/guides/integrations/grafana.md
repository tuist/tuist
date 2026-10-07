---
{
  "title": "Grafana",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Monitor Tuist build health, durations, and cache savings in Grafana, and configure alerts for your team."
}
---

# Grafana integration {#grafana}

The Tuist data source lets you use build, test, and cache metrics in Grafana, including durations, failure counts, and reported time saved by caching. Build dashboards around the projects and metrics your team cares about, or combine Tuist metrics with other data sources in your company's existing dashboards. Use Grafana's alert rules and notification channels to let your team know when builds get slower or failures increase.

## Available metrics {#metric-definitions}

The tables list readable labels and their query identifiers. Build-health queries use the identifier in the `metric` field; build and test duration queries select `average`, `p50`, `p90`, or `p99` in the `series` field.

### Build counts and reliability

| Metric | Identifier | What it measures |
| --- | --- | --- |
| Build count | `builds` | Number of recorded builds. |
| Successful builds | `successful_builds` | Builds that completed successfully. |
| Failed builds | `failed_builds` | Builds that failed. |
| Cancelled builds | `cancelled_builds` | Builds recorded as cancelled. See [build-system differences](#build-systems). |
| Build success rate | `success_rate` | Successful ÷ (successful + failed), as a percentage. |
| Builds needing attention | `builds_needing_attention` | Failed or slow builds, counted once per build. |

### Build and test durations

| Metric | Identifier | What it measures |
| --- | --- | --- |
| Average duration | `average` | Mean duration of the selected runs. |
| Median duration | `p50` | 50th percentile of run durations. |
| 90th percentile duration | `p90` | Duration at or below which 90% of runs fall. |
| 99th percentile duration | `p99` | Duration at or below which 99% of runs fall. |
| Slow-build threshold | `slow_build_threshold` | 90th percentile duration, or your fixed limit in milliseconds. |

Test duration metrics use the test runs recorded in Tuist. The slow-build threshold applies only to builds: a build is slow when its duration exceeds that threshold. Cancelled builds are counted separately and excluded from the build success rate.

### Cache savings

| Metric | Identifier | What it measures |
| --- | --- | --- |
| Estimated cache work avoided (Gradle) | `cache_work_avoided` | Sum of estimated task execution time avoided by cache hits. |
| Builds reporting estimated work avoided | `cache_work_avoided_samples` | Builds with a complete estimate. |
| Reported cache time saved | `cache_time_saved` | Sum of reported elapsed savings. |
| Builds reporting cache time saved | `cache_time_saved_samples` | Builds with a valid savings value. |

The Gradle plugin automatically reports estimated work avoided for local and remote task cache hits. For each cached task, it subtracts the task's restoration duration from the original execution time stored by Gradle, with a minimum of zero. The build estimate adds these values together. Parallel tasks can overlap, so this is cumulative task time, not elapsed build time saved. Up-to-date and skipped tasks are excluded.

A build without task cache hits reports zero. If any cached task lacks its original timing, telemetry is incomplete, or the custom metadata map has no space, the plugin omits the estimate. Older plugin versions and other build systems do not report it. Compare the reporting count with total builds to check coverage.

Reported elapsed savings come from `tuist.cache_time_saved_ms` metadata. This metric remains separate from the automatic estimate.

Cache savings have no value when no builds report them. Once does not currently record this measurement. Cache hit and miss rates are not available through this data source.

### Tables

These identifiers are values of the query's `queryType` field.

| Table | Query type | Contents |
| --- | --- | --- |
| Health by workload | `buildWorkloads` | Build count, success rate, median and 90th percentile duration. |
| Failure reasons | `buildFailureReasons` | All failures and counts by failure category. |
| Recent failed builds | `buildRecentFailures` | Latest 100 failures, with links to Tuist. |

Recent failures include start time, duration, user, branch, and requested tasks. Failure categories are `verification`, `infrastructure_tooling`, and `unknown`.

Workload summaries and branch/workload value lists return up to 1000 values. Build-health variable queries use the last 90 days; legacy Gradle variable queries keep their existing history window. Bazel shows the build user reported by the tool. Other integrations show the account associated with the reporting credential. Historical Bazel and Once runs, and Once runs reported with project credentials, appear as Unknown when no user was recorded.

Failure categories are also available on Tuist’s build overview pages. For Gradle, the cache insights page shows estimated cache work avoided and reporting coverage, and each build’s details show its recorded estimate.

## Standard dashboard {#what-you-can-query}

Import [the build-health dashboard](https://github.com/tuist/tuist/blob/main/grafana-datasource/src/dashboards/build-health.json), then select your data source and project. It includes build count, success rate, median and 90th percentile durations, the slow-build threshold, builds needing attention, reported cache savings, estimated cache work avoided for Gradle, and the three failure and workload tables. Add panels for other available metrics as needed.

## Build systems {#build-systems}

Build-health queries and the standard dashboard support Bazel, Once, Gradle, and Xcode. Tuist selects the build system from your project. Mix projects are not currently supported by the build-health queries or standard dashboard.

| Build system | Workload | Cancellation reporting | Cache savings |
| --- | --- | --- | --- |
| Bazel | Command | Exit code 8, except `run` | Requires custom metadata |
| Once | Command kind | Recorded cancellation reason | Not recorded |
| Gradle | Task group | Reported cancellations | Automatic work-avoided estimate; elapsed savings require custom metadata |
| Xcode | Scheme | Not distinguished; count is zero | Requires custom metadata |

Processing records and unfinished runs are excluded. Bazel includes build, test, run, and coverage commands. Once includes finalized build, test, and generic runs.

Gradle groups tasks as instrumented tests, unit tests, lint/checks, assemble/package, or Other, in that order of precedence. Each build belongs to one workload. Custom metadata can override workloads for Xcode, Bazel, and Gradle.

### Failure categories

| Category | Meaning | Recorded evidence |
| --- | --- | --- |
| `verification` | Code failed compilation, linking, tests, or checks. | Gradle verification or compilation exceptions and known failed task types; Xcode compiler and linker issues; Bazel structured nonzero compiler/test action results; Once test failures or failed actions explicitly declared as compile, link, test, lint, or check. |
| `infrastructure_tooling` | The build could not run normally because its tools, dependencies, or environment failed. | Gradle configuration, dependency resolution, input/output, or memory failures; Bazel structured infrastructure failures and [documented exit codes](https://bazel.build/run/scripts); Once infrastructure action errors. |
| `unknown` | The report does not contain enough evidence to classify the failure. | Arbitrary commands, missing diagnostics, and older reports without structured evidence. |

Gradle configuration-phase failures, including errors in build scripts, are grouped under infrastructure/tooling because task execution could not proceed.

Explicit `tuist.failure_category` metadata overrides automatic classification. Otherwise, infrastructure evidence takes precedence over verification when both occur in a build. A failed arbitrary script is not assumed to be a compiler or test failure. Historical reports can use evidence that Tuist already stores, but new reporter fields do not backfill missing information. Automatic reporter metadata uses available space within the existing 20-entry custom metadata limit.

The standard failure chart includes an `all` row. The legacy `gradleFailureReasons` query retains its original three category rows.

## Query options {#query-options}

Numeric queries use these `queryType` values:

| Query | Query type |
| --- | --- |
| Build health | `buildHealth` |
| Xcode build durations | `buildDuration` |
| Test durations | `testDuration` |

The `resultMode` field controls how results are returned:

| Result | Value | Behavior |
| --- | --- | --- |
| Time series | `series` | A value for each interval. |
| Whole period | `total` | One value calculated from all runs in the range. |

Filter labels map to these query fields:

| Filter | Query field | Available on |
| --- | --- | --- |
| Environment | `environment` | All queries |
| Branch | `gitBranch` | Build-health queries and tables |
| Workload | `workload` | Build-health queries and tables |
| Status | `status` | Build-health queries, tables, and Xcode durations |
| Scheme | `scheme` | Xcode build and test durations |
| Configuration | `configuration` | Xcode build durations |
| Build type | `category` | Xcode build durations |

Environment values are `any`, `ci` (automated builds), and `local`. Status values are `success`, `failure`, and, for build-health queries, `cancelled`; omit the value to include all statuses. Build type values are `clean` and `incremental`; omit the value to include both.

Empty build-health intervals have zero counts and no average duration, duration percentile, or success-rate value. The slow-build threshold still uses the full selected range. The separate test-duration query returns zero for empty time-series intervals. Whole-period percentiles are calculated from runs, rather than from interval percentiles. Build-health percentiles use exact aggregation; the separate Xcode and test duration queries use approximate percentiles.

Build-health time series place a partial first bucket at the selected range’s start so it remains visible. Legacy Gradle queries retain their original bucket timestamps.

All queries accept date ranges up to 366 days. Their boundaries and timestamps differ:

| Query | Timestamp used | Range boundaries |
| --- | --- | --- |
| Build health: Xcode, Bazel, Gradle | Record insertion time | Includes start, excludes end |
| Build health: Once | Run start time | Includes start, excludes end |
| Xcode build durations | Record insertion time | Excludes start and end |
| Test durations | Recorded run time | Includes start and end |

### Dashboard variables

Use dashboard variables for projects and supported filters. Branch and workload variables use these queries:

| Variable | Query |
| --- | --- |
| Branch | `buildBranches account/project` |
| Workload | `buildWorkloads account/project` |

Filters accept one exact value. For branch and workload variables, set the All option's custom value to `__tuist_all__`. Other filters use their built-in Any option or an empty value. Multiple selections and regular expressions are not supported.

## Reporting custom metadata {#custom-metadata}

Xcode, Bazel, and Gradle builds accept these optional metadata values:

| Key | Accepted value |
| --- | --- |
| `tuist.workload` | A workload name that replaces the default grouping. |
| `tuist.failure_category` | `verification` or `infrastructure_tooling`. |
| `tuist.cache_work_avoided_ms` | Gradle only. Automatically reported work-avoided estimate, in integer milliseconds up to 365 days. |
| `tuist.cache_time_saved_ms` | Integer milliseconds from 0 to 31,536,000,000 (365 days). |

Supply them through your build integration's custom metadata configuration:

```json
{
  "custom_metadata": {
    "values": {
      "tuist.workload": "Release verification",
      "tuist.failure_category": "verification",
      "tuist.cache_time_saved_ms": "12000"
    }
  }
}
```

Report cache savings only when you have an elapsed-time measurement or a documented estimate for that build. Cache hits and cumulative task durations alone cannot determine elapsed savings when tasks run concurrently. Missing cache savings remain unknown. Missing failure-category metadata falls back to recorded evidence, as described under [Build systems](#build-systems). Data retention is unchanged.

## Alerts and Slack {#alerts-and-slack}

Create a Grafana-managed alert rule with a numeric metric. For example:

| Metric | Identifier | Example condition |
| --- | --- | --- |
| Build success rate | `success_rate` | Below 99% |
| Failed builds | `failed_builds` | Above zero |
| 90th percentile duration | `p90` | Above your team's duration limit |

Use **Whole period** for a single value over the evaluation window, or reduce a time series to a single value. For duration queries in Whole period mode, select one series.

- Use fixed project and filter values. Dashboard variables are unavailable during background alert evaluation.
- Use numeric queries for alerts. To monitor a workload, filter a build-health query to that workload.
- Set the rule's no-data behavior for intervals without builds or reported cache savings.

Configure a [Slack contact point](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/configure-slack/) and route the rule to it through Grafana's notification policy. Grafana sends the notifications and stores the Slack credentials.

## Upgrading existing dashboards {#upgrading}

Existing duration panels retain their queries, filters, series names, and units. Saved Gradle health panels and variables also continue to work.

Import the standard dashboard separately to use the shared build-health queries. Existing dashboards are not migrated automatically. Shared queries require a Tuist server that provides the build-health endpoints; existing duration queries still work with older servers.

## Requirements {#requirements}

- Grafana 10.4 or newer.
- A Tuist token with permission to read the projects and metrics you want to chart. See [Authentication](#authentication) below.

## Authentication {#authentication}

Use an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> for dashboards and background alert evaluation. Grant `project:builds:read` for build metrics and `project:tests:read` for test durations, and restrict access to the projects you want to chart. Only the scopes for the metrics you use are required. Follow the <.localized_link href="/guides/server/authentication#creating-an-account-token">token creation instructions</.localized_link> to generate one.

The integration also accepts existing project tokens for their own project and <.localized_link href="/guides/server/authentication#as-a-user">user access tokens</.localized_link> with the user's read permissions. User access tokens are short-lived. Grafana stores the token you supply and does not refresh it or reuse your local Tuist login; replace it when it expires. Account tokens let you control project access, permissions, and expiration independently of a user's login session.

## Configuration {#configuration}

Add the data source and set:

| Field | Saved setting | Notes |
| --- | --- | --- |
| Server URL | `jsonData.url` | Defaults to `https://tuist.dev`. |
| Token | `secureJsonData.apiToken` | Tuist bearer token, stored encrypted. |

Select **Save & test** to check the connection. Grafana lists accessible projects, then checks build and test read permissions against the first project.

## Installation {#installation}

### From the Grafana catalog {#from-the-grafana-catalog}

Once published, install it like any other data source from **Connections → Add new connection → Tuist**, or with `grafana-cli plugins install tuist-metrics-datasource`.

### Before it is published (self-hosted Grafana) {#before-it-is-published-self-hosted-grafana}

The plugin is unsigned until it is approved for the catalog. On a self-hosted instance you can either:

- **Allow it unsigned** — add `tuist-metrics-datasource` to `allow_loading_unsigned_plugins` (or `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=tuist-metrics-datasource`) and drop the built plugin into your plugins directory.
- **Privately sign it** for your instances — `npm run sign -- --rootUrls https://grafana.example.com` (the URL must match the instance `root_url`), then distribute the zip.

[Grafana Cloud requires plugins from the catalog](https://grafana.com/docs/grafana-cloud/learn-and-build/get-started/learn/find-and-use-plugins/) and does not support unsigned or manually uploaded plugins.
