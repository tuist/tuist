---
name: compare-generations
description: Compares two `tuist generate` runs to identify cache hit rate changes and root-cause analysis of cache invalidation. Can be invoked with generation IDs, dashboard URLs, or branch names.
---

# Compare Generations

## Quick Start

You'll typically receive two generation identifiers. Follow these steps:

1. Run `tuist generate list --json` to find generations on each branch.
2. Run `tuist generate show <id> --json` for both base and head generations.
3. Compare duration, status, and cache hit rates.
4. Summarize cache changes with root cause analysis.

## Step 1: Resolve Generations

### If base/head are generation IDs or dashboard URLs

Fetch each directly:

```bash
tuist generate show <base-id> --json
tuist generate show <head-id> --json
```

### If base/head are branch names

List recent generations on each branch:

```bash
tuist generate list --git-branch <base-branch> --json --page-size 1
tuist generate list --git-branch <head-branch> --json --page-size 1
```

Then fetch full details with `tuist generate show <id> --json`.

### Defaults

- If no base is provided, use the project's default branch (usually `main`).
- If no head is provided, detect the current git branch.

## Step 2: Compare Top-Level Metrics

After fetching both generations, compare:

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

Cache invalidation typically works like this:
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
Generation Comparison: base (gen-123 on main) vs head (gen-456 on feature-x)

Duration: 12.5s -> 28.3s (+126%) -- REGRESSION
Cache hit rate: 92% (46/50) -> 64% (32/50) (-28%) -- REGRESSION
Status: success -> success

Root cause: FoundationModule had source changes (3 files modified).
This cascaded to 14 downstream targets that depend on FoundationModule.

Cache invalidation breakdown:
- Direct changes: FoundationModule (sources changed)
- Cascade: NetworkModule, AuthModule, UIModule, + 11 others (dependency hash changed)

Recommendations:
- Consider splitting FoundationModule into smaller modules to reduce cascade impact
- The 14 cascaded targets could benefit from more granular dependency declarations
- If FoundationModule changes frequently, consider interface/implementation module splitting
```

## Done Checklist

- Resolved both base and head generations
- Compared duration and cache hit rates
- Identified root cause targets for cache invalidation
- Analyzed cascade impact
- Provided actionable recommendations for reducing cache misses
