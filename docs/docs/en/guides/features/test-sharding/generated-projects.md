---
{
  "title": "Generated Projects Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute tests in Tuist generated projects across multiple CI runners with Tuist Test Sharding."
}
---
# Generated projects test sharding {#generated-projects-test-sharding}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
- <LocalizedLink href="/guides/features/test-insights">Test Insights</LocalizedLink> configured (for optimal shard balancing)
<!-- -->
:::

Test sharding for generated projects uses `tuist test` for both the build and test phases.

## How it works {#how-it-works}

Test sharding follows a two-phase workflow:

1. **Build phase:** Tuist enumerates your tests and creates a **shard plan** on the server. The server uses historical test timing data from the last 30 days to distribute tests across shards so each shard takes roughly the same amount of time. The build phase outputs a **shard matrix** that your CI system uses to spawn parallel runners.
2. **Test phase:** Each CI runner receives a **shard index** and executes only the tests assigned to that shard.

## Build phase {#build-phase}

Generate your project, build your tests, and create a shard plan:

```sh
tuist test --shard-total 5
```

This command:
1. Generates the Xcode project from your manifests
2. Builds your tests
3. Creates a shard plan on the Tuist server using historical timing data
4. Uploads the `.xctestproducts` bundle for use by shard runners
5. Outputs a shard matrix for your CI system
6. Persists the <LocalizedLink href="/guides/features/selective-testing">selective testing</LocalizedLink> graph (if applicable) so shard runners don't need to regenerate the project

### Build options {#build-options}

| Flag | Environment variable | Description |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Maximum number of shards. Used with `--shard-max-duration` to cap the shard count |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Minimum number of shards |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Exact number of shards (mutually exclusive with `--shard-min`/`--shard-max`) |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | Target maximum duration per shard in milliseconds |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (default) distributes entire test modules across shards; `suite` distributes individual test classes for finer-grained balancing |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Unique identifier for the shard plan (auto-derived on supported CI providers) |

## Test phase {#test-phase}

Each shard runner executes its assigned tests:

```sh
tuist test
```

### Test options {#test-options}

| Flag | Environment variable | Description |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Zero-based index of the shard to execute |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Unique identifier for the shard plan (auto-derived on supported CI providers) |

Tuist downloads the `.xctestproducts` bundle and filters it to include only the tests assigned to that shard.

::: tip SELECTIVE TESTING
<!-- -->
Test sharding works seamlessly with <LocalizedLink href="/guides/features/selective-testing">selective testing</LocalizedLink>. The selective testing graph is persisted during the build phase and restored for each shard, so runners don't need to regenerate the project.
<!-- -->
:::

## Continuous integration {#continuous-integration}

Test sharding currently supports the following CI providers:

- **GitHub Actions**

### GitHub Actions {#github-actions}

Use a matrix strategy to run shards in parallel:

```yaml
name: Tests
on: [pull_request]

jobs:
  build:
    name: Build test shards
    runs-on: macos-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: tuist test --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
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
      - run: tuist test
```
