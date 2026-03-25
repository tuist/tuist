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
4. Outputs a shard matrix for your CI system

### Build options {#build-options}

Configure sharding via Gradle project properties:

| Property | Description |
|----------|-------------|
| `-PtuistShardMax=<N>` | Maximum number of shards (default: 2) |
| `-PtuistShardMin=<N>` | Minimum number of shards |
| `-PtuistShardMaxDuration=<MS>` | Target maximum duration per shard in milliseconds |

The shard reference is automatically derived from CI environment variables (`GITHUB_RUN_ID`, `CI_PIPELINE_ID`, etc.) or can be set explicitly via the `TUIST_SHARD_REFERENCE` environment variable.

## Test phase {#test-phase}

Each shard runner executes its assigned tests using the standard `test` task. When `TUIST_SHARD_INDEX` is set, the plugin automatically fetches the shard assignment from the server and filters the test execution to include only the assigned test suites.

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

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
      - run: ./gradlew test
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
  script:
    - tuist auth login
    - ./gradlew tuistPrepareTestShards -PtuistShardMax=5
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

The child pipeline needs a `.tuist-shard` job template:

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
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
    docker:
      - image: cimg/openjdk:17.0
    steps:
      - checkout
      - run:
          name: Build and plan shards
          command: |
            tuist auth login
            ./gradlew tuistPrepareTestShards -PtuistShardMax=5
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
    docker:
      - image: cimg/openjdk:17.0
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
            ./gradlew test

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
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

Each generated step has `TUIST_SHARD_INDEX` set in its environment. Add the test command to each shard step using a shared script:

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

On Codemagic, Tuist writes `TUIST_SHARD_MATRIX` and `TUIST_SHARD_COUNT` to the `CM_ENV` file, making them available in subsequent steps:

```yaml
# codemagic.yaml
workflows:
  test-shards:
    name: Test Shards
    instance_type: linux_x2
    environment:
      java: 17
    scripts:
      - name: Build and plan shards
        script: |
          tuist auth login
          ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      - name: Run shard
        script: |
          tuist auth login
          ./gradlew test
```

::: tip
Codemagic does not natively support dynamic matrix jobs. Use `TUIST_SHARD_COUNT` to configure multiple workflows or use the Codemagic API to trigger parallel builds with different `TUIST_SHARD_INDEX` values.
:::

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
                ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                ./gradlew test
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

::: tip
Bitrise does not support dynamic parallel job creation at runtime. Define a fixed number of shard workflows in your pipeline stages — workflows within a stage run in parallel automatically.
:::
