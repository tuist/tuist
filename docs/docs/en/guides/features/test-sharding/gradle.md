---
{
  "title": "Gradle Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Gradle tests across multiple CI runners with Tuist Test Sharding."
}
---
# Gradle test sharding {#gradle-test-sharding}

::: warning REQUIREMENTS
<!-- -->
- The <LocalizedLink href="/guides/install-gradle-plugin">Tuist Gradle plugin</LocalizedLink> installed and configured
<!-- -->
:::

The Tuist Gradle plugin includes built-in support for test sharding. It discovers test suites by scanning compiled test class files and uses the Tuist server to create balanced shard plans based on historical timing data.

## How it works {#how-it-works}

Test sharding follows a two-phase workflow:

1. **Build phase:** Tuist enumerates your tests and creates a **shard plan** on the server. The server uses historical test timing data from the last 30 days to distribute tests across shards so each shard takes roughly the same amount of time. The build phase outputs a **shard matrix** that your CI system uses to spawn parallel runners.
2. **Test phase:** Each CI runner receives a **shard index** and executes only the tests assigned to that shard.

## Build phase {#build-phase}

Prepare test shards using the `tuistPrepareTestShards` task:

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

This task:
1. Compiles the test classes
2. Discovers test suites by scanning the compiled class files
3. Creates a shard plan on the Tuist server using historical timing data
4. Outputs a shard matrix to `.tuist-shard-matrix.json`. On GitHub Actions, it also automatically writes the matrix as a `GITHUB_OUTPUT`

### Build options {#build-options}

Configure sharding via Gradle project properties:

| Property | Description |
|----------|-------------|
| `-PtuistShardMax=<N>` | Maximum number of shards (default: 2) |
| `-PtuistShardMin=<N>` | Minimum number of shards |
| `-PtuistShardMaxDuration=<MS>` | Target maximum duration per shard in milliseconds |

The shard reference is automatically derived from CI environment variables (`GITHUB_RUN_ID`, `CI_PIPELINE_ID`, etc.) or can be set explicitly via the `TUIST_SHARD_REFERENCE` environment variable.

## Test phase {#test-phase}

Each shard runner executes its assigned tests using the `tuistRunShard` task:

```sh
./gradlew tuistRunShard
```

The `TUIST_SHARD_INDEX` environment variable specifies the zero-based shard index. The plugin fetches the shard assignment from the server and filters the test execution to include only the assigned test suites.

## Continuous integration {#continuous-integration}

Test sharding currently supports the following CI providers:

- **GitHub Actions**

### GitHub Actions {#github-actions}

On GitHub Actions, the shard reference and matrix output are derived automatically. Use a matrix strategy to run shards in parallel:

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - id: build
        run: ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: gradle/actions/setup-gradle@v4
      - run: tuist auth login
      - run: ./gradlew tuistRunShard
```

