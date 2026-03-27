---
name: compare-gradle-builds
description: Compares two Gradle build runs to identify duration regressions, cache changes, and task outcome differences. Can be invoked with build IDs, dashboard URLs, or branch names.
---

# Compare Gradle Builds

## Quick Start

You'll typically receive two build identifiers (IDs, dashboard URLs, or branch names). Follow these steps using the Tuist MCP tools:

1. Use `list_gradle_builds` to find builds on each branch.
2. Use `get_gradle_build` for both base and head builds.
3. Use `list_gradle_build_tasks` to fetch task-level details for both builds.
4. Compare duration, status, cache hit rates, and task outcomes.
5. Summarize regressions, improvements, and recommendations.

If only one identifier is provided, use the project's default branch as the baseline.

## Step 1: Resolve Builds

### If base/head are build IDs or dashboard URLs

Fetch each directly with `get_gradle_build(build_run_id: "<id>")`.

### If base/head are branch names

List recent builds on each branch and pick the latest:

```
list_gradle_builds(account_handle: "...", project_handle: "...", git_branch: "<branch>", page_size: 1)
```

Then fetch full details with `get_gradle_build(build_run_id: "<id>")`.

### Defaults

- If no base is provided, use the project's default branch (usually `main`).
- If no head is provided, detect the current git branch with `git rev-parse --abbrev-ref HEAD`.

## Step 2: Compare Top-Level Metrics

After fetching both builds, compare:

| Metric | What to check |
|---|---|
| `duration_ms` | Flag if head is >10% slower than base |
| `status` | Flag if base succeeded but head failed |
| `tasks_local_hit_count` | Compare local cache hit counts |
| `tasks_remote_hit_count` | Compare remote cache hit counts |
| `tasks_executed_count` | Compare how many tasks ran (higher means more cache misses) |
| `cacheable_tasks_count` | Note if the cacheable task count changed |
| `cache_hit_rate` | `(local_hits + remote_hits) / cacheable_tasks_count * 100` |
| `requested_tasks` | Ensure both builds ran the same tasks for a fair comparison |
| `gradle_version` / `java_version` | Note environment differences that affect comparability |

Compute the cache miss delta: `base_executed - head_executed`. Positive means head has fewer executions (improvement). Negative means regression.

## Step 3: Drill Into Tasks

Use `list_gradle_build_tasks` for both builds. Compare `duration_ms` and `outcome` per task path.

Look for:
- Tasks that changed from `local_hit` or `remote_hit` to `executed` (cache invalidation).
- Tasks that changed from `executed` to `local_hit` or `remote_hit` (cache improvement).
- Tasks that changed to `failed` (new failures).
- New tasks that appeared in the head build.
- Tasks with significant duration increases.

Sort by absolute time difference to find the biggest regressions.

### Filtering tasks

Use the `outcome` filter to focus on specific task states:
- `list_gradle_build_tasks(build_run_id: "<id>", outcome: "executed")` to see only executed tasks.
- `list_gradle_build_tasks(build_run_id: "<id>", outcome: "failed")` to see failures.
- `list_gradle_build_tasks(build_run_id: "<id>", cacheable: true)` to see only cacheable tasks.

## Step 4: Investigate Duration Regressions

If the head build is significantly slower:

1. Check if `requested_tasks` differ (different task sets are not directly comparable).
2. Check if cache hit rate dropped, which would explain longer builds.
3. Look for tasks that changed from cache hits to `executed`.
4. Check if `gradle_version` or `java_version` changed, which can affect performance.
5. Compare individual task durations to find the biggest contributors.

## Step 5: Investigate Cache Changes

Compare task-level cache behavior:

- **Hit rate dropped**: Possible causes include dependency changes, build configuration changes, or Gradle version updates that alter cache keys.
- **Hit rate improved**: Likely due to better cache warming or fewer source changes.
- **Task count changed**: New modules or tasks added/removed.
- **Outcome changes**: Tasks moving between `up_to_date`, `local_hit`, `remote_hit`, and `executed` reveal cache effectiveness.

## Step 6: Check Build Context

Compare environment details:

- `gradle_version` and `java_version`: Different versions can affect build times and cache validity.
- `is_ci`: CI vs local builds may have different performance characteristics.
- `git_branch` and `git_commit_sha`: Verify the builds are from the expected commits.
- `root_project_name`: Ensure both builds are from the same project structure.

## Summary Format

Produce a summary with:

1. **Overall verdict**: Better, worse, or neutral compared to base.
2. **Duration**: Absolute and percentage change in `duration_ms`.
3. **Cache hit rate**: Change in hit rate with explanation.
4. **Task outcomes**: Notable outcome changes (hit to executed, new failures).
5. **Status**: Any status changes (success to failure or vice versa).
6. **Environment**: Note any environment differences that affect comparability.
7. **Recommendations**: Actionable next steps based on findings.

Example:

```
Build Comparison: base (abc123 on main) vs head (def456 on feature-x)

Duration: 45200ms -> 62800ms (+39%) -- REGRESSION
Cache hit rate: 85% -> 72% (-13%) -- 8 tasks went from cache hit to executed
Status: success -> success

Root cause: Cache hit rate dropped because 8 tasks had invalidated caches.
The :app:compileKotlin task changed from remote_hit to executed,
cascading to 7 downstream tasks.

Recommendations:
- Investigate which source changes invalidated :app:compileKotlin cache
- Consider splitting large modules to reduce cache invalidation cascading
```

## Done Checklist

- Resolved both base and head builds
- Compared duration, cache, and status metrics
- Drilled into task-level outcomes for both builds
- Identified root causes for any regressions
- Provided actionable recommendations
