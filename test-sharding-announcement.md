
As your test suite grows, running everything on a single CI runner becomes a bottleneck. That's when teams reach for sharding: splitting tests across multiple runners to execute in parallel.

But your pipeline is only as fast as the slowest shard. If one runner gets all the heavy tests, the others finish early and sit idle. Statically splitting tests means constantly rebalancing as your codebase evolves.

Instead, Tuist uses historical timing data from [Test Insights](https://tuist.dev/docs/guides/develop/test/insights) to dynamically distribute tests across shards using a bin-packing algorithm. No continuous manual maintenance required.

## How it works

1. **Build once**: a single runner builds your test artifacts and uploads them. Tuist calculates the optimal shard matrix from real test durations.
2. **Test in parallel**: each runner downloads the pre-built artifacts and runs only its assigned slice. Results flow back into a unified dashboard.

Just add `--shard-total` to your build command and Tuist handles the rest.

## Example: GitHub Actions with `tuist xcodebuild`

```yaml
jobs:
  build:
    runs-on: macos-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

  test:
    needs: build
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
```

If you use Tuist-generated projects, you can use `tuist build` with `--shard-total` for the build phase and `tuist test` with the `TUIST_SHARD_INDEX` environment variable for the test phase. This also composes with selective testing, so you skip redundant project generation and only run the tests that are affected by your changes.

For Gradle projects, the build phase uses the `tuistPrepareTestShards` task with `-PtuistShardMax=N` to create the shard plan, and the test phase runs `./gradlew test` with the `TUIST_SHARD_INDEX` environment variable.

## What's supported

- `tuist xcodebuild` for Xcode projects
- `tuist test` for Tuist-generated projects
- Gradle projects via the Tuist Gradle plugin

## Learn more

Read the full blog post: [Test sharding](https://tuist.dev/blog/2026/03/25/test-sharding)
