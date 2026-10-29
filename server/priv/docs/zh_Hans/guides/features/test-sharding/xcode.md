---
{
  "title": "Xcode Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Xcode tests across multiple CI runners with Tuist Test Sharding."
}
---
# Xcode 测试分片 {#xcode-test-sharding}

> [!WARNING]
> **要求**
>
> - 已配置<.localized_link href="/guides/features/test-insights/xcode">Xcode 测试洞察</.localized_link>。分片使用过去 30 天的测试洞察计时数据来平衡各个分片，如果没有洞察数据，每个分片都会像套件未知一样运行。

Xcode 项目的测试分片使用 `tuist xcodebuild build-for-testing` 创建分片计划，并使用 `tuist xcodebuild test` 执行每个分片。

## 工作原理 {#how-it-works}

测试分片遵循两阶段工作流：

1. **构建阶段：** Tuist 从已构建的 `.xctestrun` 文件中读取测试模块，并在服务器上创建**分片计划**。服务器使用过去 30 天的历史测试计时数据将测试分配到各个分片，以便每个分片花费大致相同的时间。构建阶段输出一个**分片矩阵**，您的 CI 系统使用该矩阵生成并行运行器。
2. **测试阶段：** 每个持续集成运行器接收一个**分片索引**和确切的**分片计划标识符**，然后执行该计划的测试选择。

在套件粒度下，服务器为每个模块选择已知套件：对于当前 `.xctestrun` 中的每个模块，它会合并正在构建的分支上最近几次 CI 运行的套件，对于没有分支历史的模块，则回退到项目的默认分支。读取多次运行而不是最新一次运行很重要，因为分片运行会在每个分片完成时上传一个测试运行，因此最新运行仅包含迄今为止已摄入的模块部分，而且这可以防止选择性测试运行隐藏最新分支运行中跳过的套件。

当使用 `--shard-granularity suite` 时，Tuist 会在请求的分片数量之间平衡已知套件，并将最后一个分片用作兜底。例如，`--shard-total 5` 生成分片索引 `0` 到 `4`，其中分片索引 `4` 作为兜底。常规分片使用 `-only-testing` 运行其分配的套件。最后一个分片在没有 `-only-testing` 的情况下运行，并为分配给较早分片的每个套件传递 `-skip-testing`，因此它会运行其计划的套件以及新添加的套件或历史清单中缺失的套件。模块粒度不需要兜底，因为 `.xctestrun` 文件提供了模块列表。

## 构建阶段 {#build-phase}

构建您的测试并创建分片计划：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

此命令：
1. 使用 `xcodebuild build-for-testing` 构建您的测试
2. 使用历史计时数据在 Tuist 服务器上创建分片计划
3. 上传 `.xctestproducts` 包或写入分片归档以供分片运行器使用
4. 为您的 CI 系统输出分片矩阵

### 构建选项 {#build-options}

| 标志 | 环境变量 | 描述 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 最大分片数。与 `--shard-max-duration` 一起使用以限制分片数量 |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 最小分片数 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 确切的分片数（与 `--shard-min`/`--shard-max` 互斥）。在套件粒度下，最后一个分片是兜底 |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 每个分片的目标最大持续时间（毫秒） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（默认）将整个测试模块分配到各个分片；`suite` 分配单个测试类以实现更细粒度的平衡 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片计划的唯一标识符（在支持的 CI 提供商上自动派生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist 写入优化后的分片归档的路径，而不是将测试产品上传到远程存储 |

## 测试阶段 {#test-phase}

每个分片运行器执行其分配的测试：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### 测试选项 {#test-options}

| 标志 | 环境变量 | 描述 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 要执行的分片的从零开始索引 |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | 由构建阶段发出的确切分片计划标识符。生成的提供商输出会自动包含此值 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片计划的唯一标识符（在支持的 CI 提供商上自动派生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | 本地管理的分片归档的路径；Tuist 会提取它，而不是从远程存储下载测试产品 |

Tuist 下载 `.xctestproducts` 包并对其进行过滤，仅包含分配给该分片的测试。

## 持续集成 {#continuous-integration}

Tuist 会自动检测以下 CI 提供商：

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

对于其他提供商，请参阅 `.tuist-shard-matrix.json` 文件以设置并行作业。

### GitHub Actions {#github-actions}

使用矩阵策略并行运行分片：

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
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: macos-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
```

### GitLab CI {#gitlab-ci}

Tuist 会生成一个 `.tuist-shard-child-pipeline.yml`，您可以将其作为 [子流水线](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines) 触发。定义一个 `.tuist-shard` 模板作业，供生成的分片作业扩展：

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
    - |
      tuist xcodebuild build-for-testing \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        --shard-total 5
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
    - |
      tuist xcodebuild test \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16'
```

### CircleCI {#circleci}

Tuist 会生成一个包含 [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) 参数的 `.tuist-shard-continuation.json`。`shard-plan-id` 参数必须在您的延续配置中声明：

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
            tuist xcodebuild build-for-testing \
              -scheme MyScheme \
              -destination 'platform=iOS Simulator,name=iPhone 16' \
              --shard-total 5
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
  shard-plan-id:
    type: string
    default: ""

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
            export TUIST_SHARD_PLAN_ID=<< pipeline.parameters.shard-plan-id >>
            tuist auth login
            tuist xcodebuild test \
              -scheme MyScheme \
              -destination 'platform=iOS Simulator,name=iPhone 16'

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
      tuist auth login
      tuist xcodebuild build-for-testing \
        -scheme MyScheme \
        -destination 'platform=iOS Simulator,name=iPhone 16' \
        --shard-total 5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
    agents:
      queue: macos
```

每个生成的步骤都在其环境中设置了 `TUIST_SHARD_INDEX` 和 `TUIST_SHARD_PLAN_ID`。使用共享脚本将测试命令添加到每个分片步骤：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic 不支持动态矩阵作业，因此请为每个分片定义单独的工作流。Tuist 会将 `TUIST_SHARD_MATRIX` 和 `TUIST_SHARD_COUNT` 写入 `CM_ENV` 文件，以便在构建工作流中使用。Codemagic 的 `CM_ENV` 是工作流范围的，因此确切的分片计划标识符不会跨越工作流边界；测试工作流会回退到基于引用的分片查找：

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
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5

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
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'

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

在 Bitrise 上，Tuist 会将 `.tuist-shard-matrix.json`（包括 `shard_plan_id`）写入 `BITRISE_DEPLOY_DIR`，使其可作为构建产物供下游流水线阶段使用。每个测试工作流使用 `envman` 从下载的产物中提取计划 ID，以便将其传递到测试命令的环境中：

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
                tuist xcodebuild build-for-testing \
                  -scheme MyScheme \
                  -destination 'platform=iOS Simulator,name=iPhone 16' \
                  --shard-total 5
      - deploy-to-bitrise-io: {}

  test-shard-0: &shard-workflow
    envs:
      - TUIST_SHARD_INDEX: 0
    steps:
      - pull-intermediate-files: {}
      - script:
          title: Set shard plan ID from artifact
          inputs:
            - content: |
                PLAN_ID=$(jq -r '.shard_plan_id' "$BITRISE_DEPLOY_DIR/.tuist-shard-matrix.json")
                envman add --key TUIST_SHARD_PLAN_ID --value "$PLAN_ID"
      - script:
          title: Run shard
          inputs:
            - content: |
                tuist auth login
                tuist xcodebuild test \
                  -scheme MyScheme \
                  -destination 'platform=iOS Simulator,name=iPhone 16'
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

## 共享卷 {#shared-volumes}

默认情况下，构建阶段会将 `.xctestproducts` 包上传到远程存储，并且每个分片运行器都会下载它。如果您的 CI 提供商支持 **共享卷**（跨作业挂载的持久性存储），您可以通过共享文件系统传递测试产品来完全跳过此上传/下载过程。

这可以显著减少分片启动时间，尤其是对于大型测试包。

要使用共享卷：

1. 在 **构建阶段** 中，传递指向共享卷的 `-testProductsPath` 并添加 `--shard-skip-upload` 以跳过远程上传：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. 在 **测试阶段** 中，传递相同的 `-testProductsPath`，以便 Tuist 本地读取测试产品而不是下载它们：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> 为每次工作流运行使用唯一路径（例如，包含 CI 运行 ID），以避免并发运行之间的冲突。您还应在分片完成后清理测试产品，以避免在卷上积累过时数据。

| 标志 | 环境变量 | 描述 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | 跳过将测试产品包上传到远程存储 |

## 自管理产物 {#self-managed-artifacts}

如果您的 CI 提供商已有产物上传和下载步骤，您可以让 Tuist 处理归档和解压，而由您的 CI 处理传输。

1. 在 **构建阶段** 中，传递 `--shard-archive-path`，以便 Tuist 在本地写入其优化的分片归档，而不是上传测试产品：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. 使用 CI 的原生产物步骤上传该归档。

3. 在每个 **测试阶段** 作业中，下载归档并将相同的路径传回给 Tuist：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

当设置 `--shard-archive-path` 时，Tuist 会跳过远程测试产品传输，转而使用本地归档。如果您还传递了 `--shard-skip-upload`，则归档路径优先。

### Namespace {#namespace}

[Namespace](https://namespace.so) 运行器与 GitHub Actions 产物配合良好。设置一次 `TUIST_TEST_SHARD_ARCHIVE_PATH`，以便构建作业在本地写入分片归档、上传它，并在每个分片作业中下载它，然后再运行 `tuist xcodebuild test`：

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
        run: |
          tuist xcodebuild build-for-testing \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            --shard-total 5
      - uses: actions/upload-artifact@v4
        with:
          name: test-shard-archive
          path: ${{ env.TUIST_TEST_SHARD_ARCHIVE_PATH }}
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: namespace-profile-default-macos
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.build.outputs.matrix) }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
      TUIST_SHARD_PLAN_ID: ${{ matrix.shard_plan_id }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - uses: actions/download-artifact@v4
        with:
          name: test-shard-archive
          path: /tmp/shards/${{ github.run_id }}
      - run: |
          tuist xcodebuild test \
            -scheme MyScheme \
            -destination 'platform=iOS Simulator,name=iPhone 16'
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
