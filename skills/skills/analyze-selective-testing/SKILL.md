---
name: analyze-selective-testing
description: Analyzes Xcode selective testing effectiveness for a test run, showing which test targets were skipped or ran, and diagnosing regressions in test selection. Can compare two test runs to identify what changed.
---

# Analyze Selective Testing

## Quick Start

1. Run `tuist test list --json` to find test runs.
2. Run `tuist test show <id> --json` to see selective testing metrics.
3. Drill into per-target details to understand which targets ran and which were skipped.
4. If effectiveness dropped, compare with a known-good run to find the root cause.

## Step 1: Resolve Test Runs

### Find the test run to analyze

List recent test runs, optionally filtering by branch:

```bash
tuist test list --json --page-size 10
tuist test list --git-branch feature-x --json --page-size 5
```

Get detailed metrics for a specific test run:

```bash
tuist test show <test-run-id> --json
```

The response includes:
- `xcode_selective_testing_targets`: total test targets eligible for selective testing
- `xcode_selective_testing_local_hits`: targets skipped (local cache hit)
- `xcode_selective_testing_remote_hits`: targets skipped (remote cache hit)

### Defaults

- If no test run is specified, use the most recent CI test run on the current branch.
- For comparison, use the most recent CI test run on the project's default branch.

## Step 2: Assess Effectiveness

Compute selective testing effectiveness:

```
effectiveness = (local_hits + remote_hits) / targets * 100
```

| Effectiveness | Verdict |
|---|---|
| 60-100% | Healthy — most unchanged tests are being skipped |
| 30-60% | Degraded — some cache invalidation occurring |
| 0-30% | Broken — selective testing is not working effectively |
| 0% | Expected on the very first run or after a full cache invalidation |

## Step 3: Diagnose Regressions

If effectiveness dropped, investigate:

### Check for global invalidation

If nearly all targets show as `miss`, the entire selective testing cache was invalidated. Common causes:

| Cause | How to verify |
|---|---|
| Tuist CLI version change | Check if the team recently upgraded Tuist |
| Xcode version change | Compare `xcode_version` between good and bad runs |
| CI environment change | Compare `macos_version`, `model_identifier` |
| Project structure change | Check git history for Tuist manifest changes |

### Check for cascade invalidation

If only some targets show as `miss`, a dependency change likely cascaded:

1. Identify the targets that went from hit to miss.
2. Look for a common dependency among the invalidated targets.
3. Check git history for changes to that dependency.

### Compare two test runs

To understand what changed, compare a known-good run with the regressed run:

```bash
tuist test show <good-run-id> --json
tuist test show <bad-run-id> --json
```

Compare the selective testing metrics between them. Use the MCP `list_xcode_selective_testing_targets` tool (available via Tuist MCP server) for per-target drill-down with hash comparison.

## Step 4: Recommendations

Based on the diagnosis:

- **Global invalidation from CLI upgrade**: Expected one-time cost. Effectiveness should recover on the next run as hashes are re-established.
- **Cascade from dependency change**: Consider if the change to the root target was necessary. If the root target is a widely-shared module, consider splitting it.
- **Environment change**: Ensure CI uses consistent Xcode/macOS versions.
- **Cold cache on new branch**: Run tests once to warm the cache. Subsequent runs will benefit from selective testing.

## Summary Format

Produce a summary with:

1. **Overall**: effectiveness percentage, verdict (healthy/degraded/broken)
2. **Metrics**: total targets, local hits, remote hits, misses
3. **Comparison** (if applicable): effectiveness delta, targets that changed status
4. **Root cause**: what caused the regression
5. **Recommendations**: actionable next steps

Example:

```
Selective Testing Analysis: test run abc123 on feature-x

Effectiveness: 15% (3/20 targets skipped) -- BROKEN
  Local hits:  2 targets
  Remote hits: 1 target
  Misses:      17 targets

Comparison with baseline (run def456 on main, 75% effectiveness):
  14 targets changed from hit to miss

Root cause: Tuist CLI was upgraded from 4.157.0 to 4.158.2 on March 17.
The hash computation changed, invalidating all cached test hashes.

Recommendations:
- This is a one-time cost. Run tests once on the default branch to re-warm the cache.
- Subsequent feature branch runs should recover to normal effectiveness.
```

## Done Checklist

- Identified the test run(s) to analyze
- Computed selective testing effectiveness
- Diagnosed root cause if effectiveness is low
- Compared with baseline if regression detected
- Provided actionable recommendations
