---
{
  "title": "Once Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Follow Once runs live and inspect actions, durations, failures, and cache decisions in the Tuist dashboard."
}
---
# Once build insights {#once-build-insights}

Once streams runs to Tuist while they execute, so you can follow progress without waiting for the final CI log. Open the dashboard link printed at the start of a run to inspect its graph, action status, and cache decisions.

> [!IMPORTANT]
> **Requirements**
>
> - Complete <.localized_link href="/guides/get-started/once-project">Get started with Once</.localized_link> and authenticate the machine running Once.

## Report your builds {#report-your-builds}

Keep using your Once commands:

```bash
once build MyApplication
```

Live reporting is best-effort. An unavailable reporting endpoint or expired session does not fail the build. Sign in again with `once auth login --provider tuist` if the session expires.

## What the dashboard shows {#what-the-dashboard-shows}

Use **Builds** and **Build Runs** to compare runs across time, branches, and local or CI environments. Each run can include:

- The requested command, status, start time, and duration.
- The Once version and reported host information.
- Actions and their dependencies, status, duration, and cache results.
- Reported action errors.
- Git branch, commit, and CI context when reported by the client.

Search and filter the actions to find failed or slow work. Reported action names and source files help connect work back to the code; older clients may provide less detail. Cached or skipped actions are not executed work, and missing timing is not a zero-duration execution.

Tuist does not currently ingest Once's raw action log stream. Keep CI logs for full process output; run summaries and structured errors are not a replacement for those logs.

The **Cache** view separates action decisions from content-object transfers. See <.localized_link href="/guides/features/cache/once">Once cache</.localized_link> for interpreting cache activity.

## Tests {#tests}

Test commands also produce Once runs. Their reported suites and cases appear under **Tests**; hosted shards additionally publish a combined test run. See <.localized_link href="/guides/features/test-insights/once">Once test insights</.localized_link>.

## Coding agents and Grafana {#coding-agents-and-grafana}

The <.localized_link href="/guides/features/agentic-coding/mcp#once-runs">Model Context Protocol tools</.localized_link> let an agent list Once runs and read a run's action and cache totals. The same reads are available through the HTTP API.

Use the <.localized_link href="/guides/integrations/grafana">Grafana integration</.localized_link> for finalized Once build-health metrics. Once does not currently report elapsed cache time savings, so that measurement remains unavailable rather than zero.
