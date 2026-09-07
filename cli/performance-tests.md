# Graph mapper performance regression check

`StaticXCFrameworkModuleMapGraphMapperPerformanceTests` runs in `TuistKitTests`,
which the existing **CLI / Unit Tests** pull request check executes through
`tuist test TuistUnitTests`. It runs in Debug and needs no benchmark service,
saved Xcode performance baseline, network access, or fixture files.

## What it catches

[PR #12807](https://github.com/tuist/tuist/pull/12807) originally recovered static
XCFrameworks by walking the source graph separately for every surviving target.
On focused binary-cache graphs, many surviving targets share the same cached
dependencies. The review measured the mapper slowing from 0.031 s to 1.491 s.
The merged implementation shares per-node reachability results across targets.

The test calls the real mapper with source and substituted graphs. The small
case has 150 cached source targets and 40 surviving consumers; the large case
has 1,500 and 400. Both use a layered DAG with shared descendants. Cache
substitution removes the source targets and their vendor XCFramework edges.
Every consumer must recover both Objective-C and Swift framework search paths.

After warmup, the test alternates five measurements of each size and compares
their medians. Each mapper invocation constructs fresh traversers. Fixture
construction and output assertions are outside the measured interval. Roughly
10x more graph vertices and edges may take up to 30x as long, allowing substantial
timing noise while rejecting the approximately quadratic uncached traversal.

This checks scaling of this graph shape. It does not detect every constant-factor
slowdown, replace functional cache-substitution acceptance tests, or measure
end-to-end generation time.

## Running locally

From the repository root:

```sh
tuist generate tuist TuistKit TuistKitTests ProjectDescription --no-open
xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace \
  -destination 'platform=macOS' \
  -only-testing TuistKitTests/StaticXCFrameworkModuleMapGraphMapperPerformanceTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  COMPILATION_CACHE_ENABLE_CACHING=NO
```

The test prints both median durations and the growth ratio. Assertion failures
also include every sample, to help distinguish regressions from timing noise.

## Repeating the red/green experiment

Temporarily replace only
`GraphTraverser.staticObjcXCFrameworksReachableViaCachedTargets` with its original
`filterDependencies` implementation from commit
`632e1ed03223f5f73b63e1bad3b8c7d5f1a76ac2` in PR #12807. Keep the rest of the
current mapper and traverser, including Swift recovery, unchanged. Rebuild and
run the command above: module visibility should remain correct, but the growth
assertion should fail. Restore the memoized method, rebuild, and rerun the same
test; it should pass. Never commit the temporary regression or tune the threshold
to make the uncached version pass.

## Validation recorded on September 5, 2026

Measured in Debug with Xcode 26.5 on an Apple Silicon MacBook Pro, using the
unchanged test and 30x growth limit for both implementations:

| Implementation | Small median | Large median | Growth | Result |
| --- | ---: | ---: | ---: | --- |
| Original uncached Objective-C recovery method | 45.2 ms | 3,196.2 ms | 70.7x | Failed the growth assertion only |
| Restored memoized recovery method | 14.2 ms | 165.0 ms | 11.6x | Passed |

All 25 existing `StaticXCFrameworkModuleMapGraphMapperTests` also passed with the
restored implementation. The performance suite itself took 1.1 seconds in the
green run. The original method was restored only for the experiment; no production
code change is needed for this test addition.

Three further `test-without-building` iterations passed with growth ratios of
9.0x, 10.3x, and 9.3x. SwiftFormat and the CI test-specific SwiftLint rule
(`no_fatal_error_in_tests`) also passed for the added test.

The initial local build hit a missing shared Xcode SDK stat-cache file before
running tests. Both measured builds used `SDK_STAT_CACHE_ENABLE=NO` to work around
that local build issue. This setting is not required by the test or added to CI.
