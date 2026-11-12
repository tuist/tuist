---
{
  "title": "Gradle 测试分片",
  "titleTemplate": ":title · 测试分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 测试分片将 Gradle 测试分发到多个 CI 运行器上。"
}
---
# Gradle 测试分片 {#gradle-test-sharding}

Tuist Gradle 插件内置支持测试分片。它会根据 Tuist 在你项目的测试任务之前的 CI 运行中记录的测试套件制定计划，并利用 Tuist 服务器基于历史耗时数据创建均衡的分片计划。

> [!IMPORTANT]
> **要求**
>
> - 必须配置<.localized_link href="/guides/features/test-insights/gradle">测试洞察</.localized_link>

## 工作原理 {#how-it-works}

测试分片遵循两阶段工作流：

1. **构建阶段：** Tuist 在服务器上根据为你项目记录的测试套件创建**分片计划**。服务器使用过去 30 天的历史测试耗时数据，将测试分配到各个分片，使每个分片的耗时大致相同。构建阶段会输出一个**分片矩阵**，你的 CI 系统可用它来生成并行运行器。
2. **测试阶段：** 每个 CI 运行器接收一个**分片索引**，并仅执行分配给该分片的测试。最后一个分片还会运行所有未分配给其他分片的测试套件。

## 构建阶段 {#build-phase}

使用 `tuistPrepareTestShards` 任务准备测试分片：

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

此任务：
1. 查找包含待分片测试任务的项目，且不编译它们
2. 根据过去 30 天为这些项目记录的测试套件和耗时，在 Tuist 服务器上创建分片计划
3. 为你的 CI 系统输出分片矩阵

当尚未记录任何测试套件时（例如首次运行），计划将包含一个运行所有测试的单一分片。

### 构建选项 {#build-options}

通过 Gradle 项目属性配置分片：

| 属性 | 描述 |
|----------|-------------|
| `-PtuistShardMax=<N>` | 最大分片数（默认值：2） |
| `-PtuistShardMin=<N>` | 最小分片数 |
| `-PtuistShardMaxDuration=<MS>` | 每个分片的目标最大持续时间（毫秒） |
| `-PtuistShardTestTask=<NAME>` | 要分片的测试任务，例如 `testDebugUnitTest`。默认为构建中的每个测试任务 |

具有多个构建变体的 Android 项目，每个变体都有一个单元测试任务。将 `-PtuistShardTestTask` 设置为你的分片所运行的变体，以便仅规划包含该变体的项目：

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

分片引用会自动从 CI 环境变量（`GITHUB_RUN_ID`、`CI_PIPELINE_ID` 等）派生，或者可以通过 `TUIST_SHARD_REFERENCE` 环境变量显式设置。

## 测试阶段 {#test-phase}

每个分片运行器使用标准的 `test` 任务执行其分配的测试。当设置了 `TUIST_SHARD_INDEX` 时，插件会自动从服务器获取分片分配，并过滤测试执行以仅包含分配的测试套件。没有为该分片分配任何套件的项目中的测试任务将被跳过。

最后一个分片会运行每个测试任务，并排除分配给其他分片的套件，因此尚未有记录运行的套件（例如新添加的套件）仍会运行。

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

如果你在构建阶段设置了 `-PtuistShardTestTask`，请在每个分片中运行相同的任务，例如 `./gradlew testDebugUnitTest`。

## 持续集成 {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

每个构建和分片作业在运行 Gradle 之前都需要进行身份验证。你可以安装 Tuist CLI 并使用你的 CI 提供程序的 OIDC 身份运行 `tuist auth login`，或者将账户令牌作为 `TUIST_TOKEN` 公开。请参阅<.localized_link href="/guides/server/authentication#gradle-plugin-authentication">Gradle 插件身份验证</.localized_link>。以下示例省略了该步骤。

### GitHub Actions {#github-actions}

使用矩阵策略并行运行分片：

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
      - run: ./gradlew test
```

### GitLab CI {#gitlab-ci}

Tuist 会生成一个 `.tuist-shard-child-pipeline.yml`，你可以将其作为[子流水线](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines)触发。定义一个 `.tuist-shard` 模板作业，生成的分片作业将扩展该模板：

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

build-shards:
  stage: build
  script:
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

子流水线需要 `.tuist-shard` 作业模板：

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist 会生成一个 `.tuist-shard-continuation.json`，其中包含用于[continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation)的参数：

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

Tuist 会生成一个 `.tuist-shard-pipeline.yml`，每个分片对应一个步骤。使用 `buildkite-agent pipeline upload` 上传它：

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

每个生成的步骤都在其环境中设置了 `TUIST_SHARD_INDEX`。使用共享脚本将测试命令添加到每个分片步骤：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
./gradlew test
```

### Codemagic {#codemagic}

Codemagic 不支持动态矩阵作业，因此为每个分片定义单独的工作流。Tuist 会将 `TUIST_SHARD_MATRIX` 和 `TUIST_SHARD_COUNT` 写入 `CM_ENV` 文件，以便在每个工作流中使用：

```yaml
# codemagic.yaml
workflows:
  build-shards:
    name: Build test shards
    instance_type: linux_x2
    environment:
      java: 17
    scripts:
      - name: Build and plan shards
        script: |
          ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    name: "Shard #0"
    instance_type: linux_x2
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 0
    scripts:
      - name: Run shard
        script: |
          ./gradlew test

  test-shard-1:
    <<: *shard-workflow
    name: "Shard #1"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 1

  test-shard-2:
    <<: *shard-workflow
    name: "Shard #2"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 2

  test-shard-3:
    <<: *shard-workflow
    name: "Shard #3"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 3

  test-shard-4:
    <<: *shard-workflow
    name: "Shard #4"
    environment:
      java: 17
      vars:
        TUIST_SHARD_INDEX: 4
```

### Bitrise {#bitrise}

在 Bitrise 上，Tuist 会将 `.tuist-shard-matrix.json` 写入 `BITRISE_DEPLOY_DIR`，使其可作为构建产物供下游流水线阶段使用。使用 Bitrise Pipelines 并配置预定义的并行工作流：

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
                ./gradlew tuistPrepareTestShards -PtuistShardMax=5

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - script:
          title: Run shard
          inputs:
            - content: |
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

> [!TIP]
> Bitrise 不支持在运行时动态创建并行作业。请在流水线阶段中定义固定数量的分片工作流——同一阶段内的工作流会自动并行运行。
