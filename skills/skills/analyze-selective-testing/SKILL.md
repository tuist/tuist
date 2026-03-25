---
name: analyze-selective-testing
description: Analyzes Xcode selective testing effectiveness for a test run, showing which test targets were skipped or ran, and diagnosing regressions in test selection. Can compare two test runs to identify what changed.
---

# Analyze Selective Testing

## Quick Start

1. Run `tuist test list --json` to find test runs.
2. Run `tuist test selection list <test-run-id> --json` to see per-target selective testing status.
3. If effectiveness dropped, compare targets between a known-good run and the regressed run.

## Step 1: Resolve Test Runs

### Find the test run to analyze

List recent test runs, optionally filtering by branch:

```bash
tuist test list --json --page-size 10
tuist test list --git-branch feature-x --json --page-size 5
```

Get basic info for a specific test run:

```bash
tuist test show <test-run-id> --json
```

Use this to confirm the run's branch, status, scheme, and environment (`xcode_version`, `macos_version`).

### Defaults

- If no test run is specified, use the most recent CI test run on the current branch.
- For comparison, use the most recent CI test run on the project's default branch.

## Step 2: Drill Into Selective Testing Targets

List per-target selective testing data for a test run:

```bash
tuist test selection list <test-run-id> --json
```

Each target includes:
- **name**: The test target name
- **hit_status**: `miss` (ran), `local` (skipped via local cache), or `remote` (skipped via remote cache)
- **hash**: The selective testing hash for this target

Filter by status to focus your analysis:

```bash
tuist test selection list <test-run-id> --hit-status miss --json
tuist test selection list <test-run-id> --hit-status local --json
tuist test selection list <test-run-id> --hit-status remote --json
```

### Assess effectiveness

Count the targets by status:
```
effectiveness = (local_hits + remote_hits) / total_targets * 100
```

| Effectiveness | Verdict |
|---|---|
| 60-100% | Healthy — most unchanged tests are being skipped |
| 30-60% | Moderate — some cache invalidation occurring, worth investigating |
| 0-30% | Low — likely a core dependency changed or the cache was invalidated |
| 0% | Cold cache — first run, environment change, or full invalidation |

## Step 3: Diagnose Regressions

If effectiveness dropped, investigate:

### Check for global invalidation

If nearly all targets show as `miss`, the entire selective testing cache was invalidated. Common causes:

| Cause | How to verify |
|---|---|
| Xcode version change | Compare `xcode_version` between good and bad runs via `tuist test show` |
| CI environment change | Compare `macos_version`, `model_identifier` between runs |
| Project graph or dependency change | Check git history for changes to project manifests, dependency versions, or target configurations |
| Core dependency change | A widely-depended-on target changed, invalidating all its dependents |

Note: Tuist CLI version upgrades rarely cause hash invalidation — the hash version is not updated on every release.

### Check for cascade invalidation

If only some targets show as `miss`, a dependency change likely cascaded:

1. Run `tuist test selection list <good-run-id> --json` and `tuist test selection list <bad-run-id> --json`.
2. Match targets by name — identify those that changed from `local`/`remote` to `miss`.
3. Compare hashes for changed targets — if a target's hash differs, its sources or dependencies changed.
4. Look for a common dependency among the invalidated targets.

### Compare two test runs

For each target:
- Match by `name`
- Compare `hit_status` (hit -> miss = invalidated, miss -> hit = improved)
- Compare `hash` (different hash = target or its dependencies changed)

## Step 4: Recommendations

Based on the diagnosis:

- **Environment change**: Ensure CI uses consistent Xcode/macOS versions. This is the most common cause of full cache invalidation.
- **Cascade from dependency change**: Consider if the change to the root target was necessary. If the root target is a widely-shared module, consider splitting it.
- **Cold cache on new branch**: Run tests once to warm the cache. Subsequent runs will benefit from selective testing.

## Summary Format

Produce a summary with:

1. **Overall**: effectiveness percentage, verdict (healthy/moderate/low/cold)
2. **Target breakdown**: targets grouped by hit status
3. **Comparison** (if applicable): targets that changed status between runs, with hash diffs
4. **Root cause**: what caused the regression
5. **Recommendations**: actionable next steps

Example:

```
Selective Testing Analysis: test run abc123 on feature-x

Effectiveness: 15% (3/20 targets skipped) -- LOW
  Local hits:  2 targets (CoreTests, UtilTests)
  Remote hits: 1 target (NetworkTests)
  Misses:      17 targets

Comparison with baseline (run def456, 75% effectiveness):
  14 targets changed from hit to miss
  All changed targets have different hashes

Root cause: Xcode version changed from 15.2 to 16.0 between runs.
This changed all target hashes, invalidating the entire cache.

Recommendations:
- Align CI Xcode version with the version used in the baseline run.
- If the upgrade is intentional, run tests once to re-warm the cache.
```

## Done Checklist

- Identified the test run(s) to analyze
- Drilled into per-target selective testing status via `tuist test selection list`
- Diagnosed root cause if effectiveness is low
- Compared targets with baseline if regression detected
- Provided actionable recommendations
