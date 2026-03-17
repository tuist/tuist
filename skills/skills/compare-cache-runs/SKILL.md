---
name: compare-cache-runs
description: Compares two `tuist cache` runs to identify cache hit rate changes and root-cause analysis of cache invalidation. Can be invoked with cache run IDs, dashboard URLs, or branch names.
---

# Compare Cache Runs

## Quick Start

You'll typically receive two cache run identifiers. Follow these steps:

1. Run `tuist cache-run list --json` to find cache runs on each branch.
2. Run `tuist cache-run show <id> --json` for both base and head cache runs.
3. Compare duration, status, and cache hit rates.
4. Summarize cache changes with root cause analysis.

## Step 1: Resolve Cache Runs

### If base/head are cache run IDs or dashboard URLs

Fetch each directly:

```bash
tuist cache-run show <base-id> --json
tuist cache-run show <head-id> --json
```

### If base/head are branch names

List recent cache runs on each branch:

```bash
tuist cache-run list --git-branch <base-branch> --json --page-size 1
tuist cache-run list --git-branch <head-branch> --json --page-size 1
```

Then fetch full details with `tuist cache-run show <id> --json`.

### Defaults

- If no base is provided, use the project's default branch (usually `main`).
- If no head is provided, detect the current git branch.

## Step 2: Compare Top-Level Metrics

After fetching both cache runs, compare:

| Metric | What to check |
|---|---|
| `duration` | Flag if head is >10% slower |
| `status` | Flag if base succeeded but head failed |
| `cacheable_targets` | Note if target count changed |
| `local_cache_target_hits` | Compare local hit counts |
| `remote_cache_target_hits` | Compare remote hit counts |
| `is_ci` | Note if one is CI and the other local |

Compute cache hit rates:
- Base: `(local_hits + remote_hits) / cacheable_targets * 100`
- Head: same formula
- Delta: `head_rate - base_rate`

## Step 3: Analyze Cache Invalidation

If cache hit rate dropped, the key question is: **which target(s) caused the invalidation cascade?**

Cache invalidation in `tuist cache` works the same way as in `tuist generate`:
1. A "root cause" target has a direct change (source file modified, build setting changed, etc.)
2. All targets that depend on the root cause target also get invalidated because their `dependencies` hash changes.
3. This cascade can invalidate many targets from a single root change.

### Identifying root cause targets

Without the module cache target detail endpoint (available via MCP), use these heuristics:

1. Check `git diff` between the base and head commits to see which files changed.
2. Map changed files to their Tuist targets/modules.
3. Targets with direct source changes are likely root causes.
4. Targets that only changed due to dependency hash cascading are secondary invalidations.

### Common root causes of cache invalidation

| Cause | Description |
|---|---|
| Source changes | Files in the target's source directory were modified |
| Resource changes | Assets, XIBs, storyboards, or other resources changed |
| Build settings | Target or project build settings were modified |
| Dependency changes | An external dependency version changed |
| Info.plist changes | The target's Info.plist was modified |
| Entitlements changes | The entitlements file was modified |
| Deployment target | The minimum deployment target changed |
| Headers | Public or project headers changed |
| Project settings | Shared project-level settings changed |

## Step 4: Assess Impact

Categorize the cache invalidation:

- **Expected**: Source files were intentionally changed, causing expected cache misses.
- **Unexpected**: No source changes but cache was invalidated (build settings, Xcode version, etc.).
- **Cascade**: A small change invalidated many downstream targets.

For `tuist cache` specifically, also consider:
- Cache warming strategy: Was the cache run warming from scratch or incrementally?
- The `command_arguments` field can reveal if different flags were used.

## Summary Format

Produce a summary with:

1. **Overall verdict**: Cache hit rate improved, regressed, or stable.
2. **Cache hit rate**: Base rate vs head rate with delta.
3. **Duration**: Absolute and percentage change.
4. **Root cause targets**: Which targets had direct changes.
5. **Cascade impact**: How many targets were invalidated due to dependency cascading.
6. **Recommendations**: How to minimize cache invalidation.

Example:

```
Cache Run Comparison: base (run-123 on main) vs head (run-456 on feature-x)

Duration: 95.2s -> 142.8s (+50%) -- REGRESSION
Cache hit rate: 88% (44/50) -> 60% (30/50) (-28%) -- REGRESSION
Status: success -> success

Root cause: CoreModule had source changes (5 files modified).
This cascaded to 14 downstream targets that depend on CoreModule.

Cache invalidation breakdown:
- Direct changes: CoreModule (sources changed)
- Cascade: UIKit, Networking, Analytics, + 11 others (dependency hash changed)

Recommendations:
- Consider splitting CoreModule into smaller, more focused modules
- Use interface/implementation module pattern for frequently-changed modules
- Run `tuist cache` on the feature branch after rebasing to warm caches
```

## Done Checklist

- Resolved both base and head cache runs
- Compared duration and cache hit rates
- Identified root cause targets for cache invalidation
- Analyzed cascade impact
- Provided actionable recommendations for reducing cache misses
