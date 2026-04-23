---
{
  "title": "Generated Projects Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute tests in Tuist generated projects across multiple CI runners with Tuist Test Sharding."
}
---
# Generated projects test sharding {#generated-projects-test-sharding}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/features/projects">Tuist generated project</.localized_link>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link>
> - <.localized_link href="/guides/features/test-insights">Test Insights</.localized_link> configured (for optimal shard balancing)


Test sharding for generated projects uses `tuist test` for both the build and test phases.

## How it works {#how-it-works}

Test sharding follows a two-phase workflow:

1. **Build phase:** Tuist enumerates your tests and creates a **shard plan** on the server. The server uses historical test timing data from the last 30 days to distribute tests across shards so each shard takes roughly the same amount of time. The build phase outputs a **shard matrix** that your CI system uses to spawn parallel runners.
2. **Test phase:** Each CI runner receives a **shard index** and executes only the tests assigned to that shard.

## Build phase {#build-phase}

Generate your project, build your tests, and create a shard plan:

```sh
tuist test --build-only --shard-total 5
```

The `--build-only` flag tells Tuist to build the tests without running them. Tuist errors out if you pass shard planning flags (`--shard-min`/`--shard-max`/`--shard-total`) without `--build-only`.

This command:
1. Generates the Xcode project from your manifests
2. Builds your tests
3. Creates a shard plan on the Tuist server using historical timing data
4. Uploads the `.xctestproducts` bundle or writes a shard archive for use by shard runners
5. Outputs a shard matrix for your CI system
6. Persists the <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link> graph (if applicable) so shard runners don't need to regenerate the project

### Build options {#build-options}

| Flag | Environment variable | Description |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Maximum number of shards. Used with `--shard-max-duration` to cap the shard count |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Minimum number of shards |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Exact number of shards (mutually exclusive with `--shard-min`/`--shard-max`) |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | Target maximum duration per shard in milliseconds |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (default) distributes entire test modules across shards; `suite` distributes individual test classes for finer-grained balancing |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Unique identifier for the shard plan (auto-derived on supported CI providers) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Path where Tuist writes the optimized shard archive instead of uploading test products to remote storage |

## Test phase {#test-phase}

Each shard runner executes its assigned tests:

```sh
tuist test --without-building
```

The `--without-building` flag tells Tuist to run the tests using the previously built products instead of rebuilding. Tuist errors out if `TUIST_SHARD_INDEX` / `--shard-index` is set without `--without-building`.

### Test options {#test-options}

| Flag | Environment variable | Description |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Zero-based index of the shard to execute |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Unique identifier for the shard plan (auto-derived on supported CI providers) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Path to a locally managed shard archive; Tuist extracts it instead of downloading test products from remote storage |

Tuist downloads the `.xctestproducts` bundle and filters it to include only the tests assigned to that shard.

> [!TIP]
> **Selective Testing**
>
> Test sharding works seamlessly with <.localized_link href="/guides/features/selective-testing">selective testing</.localized_link>. The selective testing graph is persisted during the build phase and restored for each shard, so runners don't need to regenerate the project.


## Continuous integration {#continuous-integration}

Tuist automatically detects the following CI providers:

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

For other providers, refer to the `.tuist-shard-matrix.json` file to set up parallel jobs.

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
        run: tuist test --build-only --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
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
      - run: tuist test --without-building
```

### GitLab CI {#gitlab-ci}

Tuist generates a `.tuist-shard-child-pipeline.yml` that you trigger as a [child pipeline](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines). Define a `.tuist-shard` template job that the generated shard jobs extend:

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  tags: [macos]
  script:
    - tuist auth login
    - tuist test --build-only --shard-total 5
  artifacts:
    paths:
      - .tuist-shard-child-pipeline.yml

test-shards:
  stage: test
  needs: [build-shards]
  trigger:
    include:
      - artifact: .tuist-shard-child-pipeline.yml
        job: build-shards
    strategy: depend
```

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  tags: [macos]
  script:
    - tuist auth login
    - tuist test --without-building
```

### CircleCI {#circleci}

Tuist generates a `.tuist-shard-continuation.json` with parameters for the [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation):

```yaml
# .circleci/config.yml
version: 2.1
setup: true

orbs:
  continuation: circleci/continuation@1

jobs:
  build-shards:
    macos:
      xcode: "16.0"
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            tuist test --build-only --shard-total 5
      - continuation/continue:
          configuration_path: .circleci/continue-config.yml
          parameters: .tuist-shard-continuation.json

workflows:
  setup:
    jobs:
      - build-shards
```

```yaml
# .circleci/continue-config.yml
version: 2.1

parameters:
  shard-indices:
    type: string
    default: ""
  shard-count:
    type: integer
    default: 0

jobs:
  test-shard:
    macos:
      xcode: "16.0"
    parameters:
      shard-index:
        type: integer
    steps:
      - checkout
      - run:
          name: Run shard
          command: |
            export TUIST_SHARD_INDEX=<< parameters.shard-index >>
            tuist auth login
            tuist test --without-building

workflows:
  test:
    jobs:
      - test-shard:
          matrix:
            parameters:
              shard-index: [<< pipeline.parameters.shard-indices >>]
```

### Buildkite {#buildkite}

Tuist generates a `.tuist-shard-pipeline.yml` with one step per shard. Upload it with `buildkite-agent pipeline upload`:

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      tuist test --build-only --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

Each generated step has `TUIST_SHARD_INDEX` set in its environment. Add the test command to each shard step using a shared script:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic does not support dynamic matrix jobs, so define a separate workflow per shard. Tuist writes `TUIST_SHARD_MATRIX` and `TUIST_SHARD_COUNT` to the `CM_ENV` file for use within each workflow:

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: mac_mini_m2
    environment:
      xcode: latest
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          tuist test --build-only --shard-total 5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: mac_mini_m2
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          tuist auth login
          tuist test --without-building

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      xcode: latest
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

On Bitrise, Tuist writes `.tuist-shard-matrix.json` to the `BITRISE_DEPLOY_DIR`, making it available as a build artifact for downstream pipeline stages. Use Bitrise Pipelines with pre-defined parallel workflows:

```yaml
# bitrise.yml
pipelines:
  test-pipeline:
    stages:
      - build-stage: {}
      - test-stage: {}

stages:
  build-stage:
    workflows:
      - build-shards: {}
  test-stage:
    workflows:
      - test-shard-0: {}
      - test-shard-1: {}
      - test-shard-2: {}
      - test-shard-3: {}
      - test-shard-4: {}

workflows:
  build-shards:
    steps:
      - script:
          title: Build and plan shards
          inputs:
            - content: |
                tuist auth login
                tuist test --build-only --shard-total 5

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                tuist test --without-building
  test-shard-1:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 1
  test-shard-2:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 2
  test-shard-3:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 3
  test-shard-4:
    <<: *shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 4
```

> [!TIP]
> Bitrise does not support dynamic parallel job creation at runtime. Define a fixed number of shard workflows in your pipeline stages — workflows within a stage run in parallel automatically.

## Shared volumes {#shared-volumes}

By default, the build phase uploads the `.xctestproducts` bundle to remote storage, and each shard runner downloads it. If your CI provider supports **shared volumes** (persistent storage mounted across jobs), you can skip this upload/download entirely by passing the test products through a shared filesystem.

This can significantly reduce shard startup time, especially for large test bundles.

To use shared volumes:

1. In the **build phase**, pass `-testProductsPath` (after `--`) pointing to a shared volume and add `--shard-skip-upload` to skip the remote upload:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. In the **test phase**, pass the same `-testProductsPath` so Tuist reads the test products locally instead of downloading them:

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| Flag | Environment variable | Description |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | Skip uploading the test products bundle to remote storage |

## Self-managed artifacts {#self-managed-artifacts}

If your CI provider already has artifact upload and download steps, you can let Tuist handle archive and extraction while your CI handles transport.

1. In the **build phase**, pass `--shard-archive-path` so Tuist writes its optimized shard archive locally instead of uploading test products:

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. Upload that archive using your CI's native artifact step.

3. In each **test phase** job, download the archive and pass the same path back to Tuist:

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

When `--shard-archive-path` is set, Tuist skips remote test-products transfer and uses the local archive instead. If you also pass `--shard-skip-upload`, the archive path takes precedence.

> [!IMPORTANT]
> Use a unique path per workflow run (e.g. include the CI run ID) to avoid collisions between concurrent runs. You should also clean up the shard archive after sharding completes to avoid accumulating stale data on the runner.

### Namespace {#namespace}

[Namespace](https://namespace.so) runners work well with GitHub Actions artifacts. Set `TUIST_TEST_SHARD_ARCHIVE_PATH` once so the build job writes the shard archive locally, upload it, and download it in each shard job before running `tuist test`:

```yaml
name: Tests
on: [pull_request]

env:
  TUIST_TEST_SHARD_ARCHIVE_PATH: /tmp/shards/${{ github.run_id }}/bundle.aar

jobs:
  build:
    name: Build test shards
    runs-on: namespace-profile-default-macos
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - id: build
        run: tuist test --build-only --shard-total 5
      - uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
    runs-on: namespace-profile-default-macos
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
      - uses: actions/download-artifact@v4
        with:
          name: test-shard-archive
          path: /tmp/shards/${{ github.run_id }}
      - run: tuist test --without-building
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
