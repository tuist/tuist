---
name: compare-bundles
description: Compares two app bundles to identify size changes, new or removed artifacts, and platform differences. Can be invoked with bundle IDs, dashboard URLs, or branch names.
---

# Compare Bundles

## Quick Start

You'll typically receive two bundle identifiers. Follow these steps:

1. Run `tuist bundle list --json` to find bundles on each branch.
2. Run `tuist bundle show <bundle-id> --json` for both base and head bundles.
3. Compare artifact trees with `tuist bundle artifact list <bundle-id> --json`.
4. Compare install size, download size, and other metadata.
5. Summarize size changes with actionable recommendations.

## Step 1: Resolve Bundles

### If base/head are bundle IDs or dashboard URLs

Fetch each directly:

```bash
tuist bundle show <base-id> --json
tuist bundle show <head-id> --json
```

### If base/head are branch names

List recent bundles on each branch and pick the latest:

```bash
tuist bundle list --git-branch <base-branch> --json
tuist bundle list --git-branch <head-branch> --json
```

Then fetch full details with `tuist bundle show <id> --json`.

### Defaults

- If no base is provided, use the project's default branch (usually `main`).
- If no head is provided, detect the current git branch.

## Step 2: Compare Artifact Trees

After fetching both bundles with `tuist bundle show <id> --json`, compare the individual artifacts:

```bash
tuist bundle artifact list <base-id> --json
tuist bundle artifact list <head-id> --json
```

Match artifacts by name across both bundles. Look for:
- New artifacts added in the head bundle (potential size contributors)
- Removed artifacts (explain size decreases)
- Size changes in existing artifacts

## Step 3: Compare Top-Level Metrics

After fetching both bundles, compare:

| Metric | What to check |
|---|---|
| `install_size` | Flag if head is >5% larger |
| `download_size` | Flag if head is >5% larger |
| `version` | Note version changes |
| `supported_platforms` | Note platform changes |
| `app_bundle_id` | Should match between base and head |

Compute deltas:
- Install size delta: `head_install_size - base_install_size`
- Download size delta: `head_download_size - base_download_size`
- Percentage change: `delta / base_size * 100`

## Step 4: Analyze Size Changes

If size increased significantly (>5%):

1. Check if `version` changed, which might explain expected size growth.
2. Check if `supported_platforms` changed (adding a platform increases size).
3. Look at the `artifacts` field in the bundle details for individual artifact sizes.

Common causes of size increases:
- New frameworks or libraries added
- Asset catalogs grew (new images, videos)
- Unoptimized resources (large PNGs instead of compressed formats)
- Debug symbols included in release builds
- New localizations added

Common causes of size decreases:
- Removed unused frameworks
- Optimized assets
- Tree shaking or dead code elimination improvements
- Moved functionality to on-demand resources

## Summary Format

Produce a summary with:

1. **Overall verdict**: Size increased, decreased, or stable.
2. **Install size**: Absolute and percentage change.
3. **Download size**: Absolute and percentage change.
4. **Version**: Note if version changed.
5. **Platforms**: Note any platform changes.
6. **Recommendations**: Actionable next steps for size regressions.

Example:

```
Bundle Comparison: base (v2.1.0 on main) vs head (v2.2.0 on feature-x)

Install Size: 45.2 MB -> 52.8 MB (+16.8%) -- REGRESSION
Download Size: 28.1 MB -> 32.4 MB (+15.3%) -- REGRESSION
Version: 2.1.0 -> 2.2.0
Platforms: iOS, macOS (unchanged)

The install size increased by 7.6 MB. This is a significant increase
that may affect user download and storage experience.

Recommendations:
- Review new frameworks or assets added in this version
- Check for uncompressed resources or oversized image assets
- Consider using asset compression or on-demand resources
- Run `xcrun bitcode_strip` analysis to check for unnecessary bitcode
```

## Done Checklist

- Resolved both base and head bundles
- Compared artifact trees using `tuist bundle artifact list`
- Compared install and download sizes
- Analyzed root causes of size changes
- Provided actionable recommendations
