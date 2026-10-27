---
name: compare-builds
description: Compares two Xcode build runs to identify duration regressions, cache changes, and new issues. Can be invoked with build IDs, dashboard URLs, or branch names (e.g. `tuist compare-builds --base main --head feature-branch`).
---

# Compare Builds

## Quick Start

You'll typically receive two build identifiers (IDs, dashboard URLs, or branch names). Follow these steps:

1. Run `tuist build list --json` to find builds on each branch.
2. Run `tuist build show <build-id> --json` for both base and head builds.
3. Fetch sub-resource details: targets (`tuist build xcode target list <id> --json`), issues (`tuist build xcode issue list <id> --json`), and cache tasks (`tuist build xcode cache-task list <id> --json`).
4. Compare duration, status, cache hit rates, and other metrics.
5. Summarize regressions, improvements, and recommendations.

If only one identifier is provided, use the project's default branch as the baseline.

## Step 1: Resolve Builds

### If base/head are build IDs or dashboard URLs

Fetch each directly:

```bash
tuist build show <base-id> --json
tuist build show <head-id> --json
```

### If base/head are branch names

List recent builds on each branch and pick the latest:

```bash
tuist build list --git-branch <base-branch> --json --page-size 1
tuist build list --git-branch <head-branch> --json --page-size 1
```

Then fetch full details with `tuist build show <id> --json`.

### Defaults

- If no base is provided, use the project's default branch (usually `main`).
- If no head is provided, detect the current git branch with `git rev-parse --abbrev-ref HEAD`.

## Step 2: Fetch Sub-Resource Details

After fetching both builds with `tuist build show <id> --json`, drill down into sub-resources for a deeper comparison.

### Compare targets

```bash
tuist build xcode target list <base-id> --json
tuist build xcode target list <head-id> --json
```

Look for targets that changed status (e.g., success to failure) or had significant duration changes.

### Compare issues

```bash
tuist build xcode issue list <base-id> --json
tuist build xcode issue list <head-id> --json
```

Look for new warnings or errors introduced in the head build.

### Compare cache tasks

```bash
tuist build xcode cache-task list <base-id> --json
tuist build xcode cache-task list <head-id> --json
```

Identify which specific targets had cache misses or hits and whether that changed between builds.

## Step 3: Compare Top-Level Metrics

After fetching both builds, compare:

| Metric | What to check |
|---|---|
| `duration` | Flag if head is >10% slower than base |
| `status` | Flag if base succeeded but head failed |
| `cacheable_tasks_count` | Note if task count changed |
| `cacheable_task_local_hits_count` | Compare local hit counts |
| `cacheable_task_remote_hits_count` | Compare remote hit counts |
| Cache hit rate | `(local_hits + remote_hits) / cacheable_tasks_count * 100` |
| `category` | Note if one is `clean` and the other `incremental` (makes duration comparison less meaningful) |
| `scheme` / `configuration` | Ensure both builds used the same scheme and configuration for a fair comparison |

Compute the cache miss delta: `base_misses - head_misses`. Positive means head has fewer misses (improvement). Negative means regression.

## Step 4: Investigate Duration Regressions

If the head build is significantly slower:

1. Check if the `category` differs (clean vs incremental builds are not directly comparable).
2. Check if cache hit rate dropped, which would explain longer builds.
3. If both are incremental with similar cache rates, the regression is likely in compilation time.

## Step 5: Investigate Cache Changes

Compare cache statistics:

- **Hit rate dropped**: Possible causes include dependency changes, build setting changes, or Xcode version updates.
- **Hit rate improved**: Likely due to better cache warming or fewer source changes.
- **Task count changed**: New targets added or removed.

## Step 6: Check Build Context

Compare environment details:

- `xcode_version` and `macos_version`: Different versions can affect build times and cache validity.
- `is_ci`: CI vs local builds may have different performance characteristics.
- `git_branch` and `git_commit_sha`: Verify the builds are from the expected commits.

## Summary Format

Produce a summary with:

1. **Overall verdict**: Better, worse, or neutral compared to base.
2. **Duration**: Absolute and percentage change.
3. **Cache hit rate**: Change in hit rate with explanation.
4. **Status**: Any status changes (pass to fail or vice versa).
5. **Environment**: Note any environment differences that affect comparability.
6. **Recommendations**: Actionable next steps based on findings.

Example:

```
Build Comparison: base (abc123 on main) vs head (def456 on feature-x)

Duration: 45.2s -> 62.8s (+39%) -- REGRESSION
Cache hit rate: 85% -> 72% (-13%) -- 8 new cache misses
Status: success -> success

Root cause: Cache hit rate dropped due to 8 targets with invalidated caches.
The dependency hash changed for FeatureModule, cascading to 7 downstream targets.

Recommendations:
- Investigate why FeatureModule's cache was invalidated
- Consider splitting large targets to reduce cascade impact
```

## Done Checklist

- Resolved both base and head builds
- Fetched sub-resource details (targets, issues, cache tasks)
- Compared duration, cache, and status metrics
- Identified root causes for any regressions
- Provided actionable recommendations
