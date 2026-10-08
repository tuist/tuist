# Tuist and Blacksmith: toolchain evidence or integrated GitHub Actions acceleration?

Choose Tuist when you need supported build and test investigation and compatible cache reuse beyond one runner fleet. Combine [Build Insights](/en/docs-markdown/guides/features/build-insights), test evidence, and authorized agent access to explain the toolchain work behind a slow job, without moving CI.

## What overlaps

Blacksmith documents [Bazel build caching](https://docs.blacksmith.sh/blacksmith-caching/bazel-build-caching.md), [Test Analytics](https://docs.blacksmith.sh/blacksmith-observability/test-analytics.md), and [CI Analytics](https://docs.blacksmith.sh/blacksmith-observability/dashboard.md). Its Bazel cache reuses action outputs across jobs, including cacheable tests. Its test analytics detects JUnit files and also parses supported test output from logs on a best-effort basis.

These are real overlapping capabilities. Tuist's case should rest on the environments, integrations, and diagnostic records you need, not a claim that Blacksmith cannot cache build outputs or show tests.

## Compare the scope and evidence

| Requirement | Tuist | Blacksmith evidence to evaluate |
| --- | --- | --- |
| Bazel action reuse | [Bazel Cache](/en/docs-markdown/guides/features/cache/bazel-cache) connects compatible supported clients independently of Tuist Runners. | Blacksmith documents automatic Bazel cache configuration on its jobs and repository-scoped reuse across branches. Evaluate additional client support separately. |
| Test failure investigation | [Test Insights](/en/docs-markdown/guides/features/test-insights) records supported Xcode, Gradle, Bazel, and Elixir test results. | Test Analytics parses JUnit XML and supported job logs, showing failing tests and inline logs. Compare report completeness for the same suite. |
| Find expensive work | Tuist exposes toolchain-specific operations and cache evidence through [Build Insights](/en/docs-markdown/guides/features/build-insights) and authorized [MCP](/en/docs-markdown/guides/features/agentic-coding/mcp). | CI Analytics reports GitHub Actions performance and costs. Compare whether the job-level or toolchain-level record answers the actual bottleneck question. |
| Adopt without choosing compute | Use supported Tuist integrations on current developer and CI machines. | The cited automatic caching and test collection are integrated with Blacksmith runners. This is not an audit of every Blacksmith offering or agent feature. |

## Choose Tuist when

Your investigation needs to connect local and CI behavior, or needs specific Xcode steps, Gradle tasks, Bazel profile data, and test attempts that its documented integrations expose. You want agents to reason over authorized records and engineers to inspect the [public implementation](https://github.com/tuist/tuist). Adopt that capability independently of compute and measure whether it adds evidence beyond the runner dashboard.

## First experiment

Pilot a [supported Tuist integration](/en/docs-markdown/guides/get-started) on the current runner and emit structured test results. Compare setup, compilation, hit/miss transfers, report completeness, and total job cost against the existing baseline. Use Tuist MCP to investigate one expensive operation or failed test, then try compatible cache reuse on a developer machine. Blacksmith documents that an explicit Bazel `--remote_cache` takes precedence over its automatic cache; verify that the intended Tuist backend is active.

## Sources and review

Sources checked on **2026-10-08**: Blacksmith's [Bazel cache](https://docs.blacksmith.sh/blacksmith-caching/bazel-build-caching.md), [Test Analytics](https://docs.blacksmith.sh/blacksmith-observability/test-analytics.md), [CI Analytics](https://docs.blacksmith.sh/blacksmith-observability/dashboard.md), and [Tuist Build Insights](/en/docs-markdown/guides/features/build-insights). This comparison is written by Tuist and recognizes documented build-cache and test-analytics overlap.

## Limitations

Automatic log parsing is not equivalent to complete structured results. Cache trust, architecture, and branch policies must be checked for each backend. Tuist's Bazel cache is not remote execution; selective testing requires generated Xcode projects. Public source and self-hosting terms differ by component. Tuist Runners are invite-only with no public pricing, so no cheapest-runner claim is made.

Related: [Depot](/marketing-markdown/compare/depot), [WarpBuild](/marketing-markdown/compare/warpbuild), and [all comparisons](/marketing-markdown/compare).
