---
{
  "title": "Xcode 测试分片",
  "titleTemplate": ":title · 测试分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 测试分片将 Xcode 测试分发到多个 CI 运行器上。"
}
---
# Xcode 测试分片 {#xcode-test-sharding}

> [!IMPORTANT]
> **要求**
>
> - 已配置<.localized_link href="/guides/features/test-insights/xcode">Xcode 测试洞察</.localized_link>。分片功能会使用过去 30 天的测试洞察计时数据来平衡各分片；若未启用洞察，每个分片都会将测试套件视为未知状态运行。

针对 Xcode 项目的测试分片使用 `tuist xcodebuild build-for-testing` 生成分片计划，并使用 `tuist xcodebuild test` 执行每个分片。

## 工作原理 {#how-it-works}

测试分片遵循两阶段工作流：

1. **构建阶段：** Tuist 从已构建的 `.xctestrun` 文件中读取测试模块，并在服务器上创建**分片计划**。服务器利用过去 30 天的历史测试计时数据，将测试均匀分布到各个分片，使每个分片的耗时大致相同。构建阶段会输出一个**分片矩阵**，供你的 CI 系统用于启动并行运行器。
2. **测试阶段：** 每个持续集成运行器会收到一个**分片索引**和确切的**分片计划标识符**，然后执行该计划所选定的测试。

在套件粒度模式下，服务器会使用当前 `.xctestrun` 中各模块在当前分支最近的 CI 运行中所报告的套件；对于没有分支历史的模块，则回退到项目的默认分支。合并多次运行结果可以保留那些在分片运行或选择性运行中被最新报告遗漏的套件。

当使用 `--shard-granularity suite` 时，Tuist 会在请求的分片数量之间均衡已知套件，并将最后一个分片作为兜底分片。例如，`--shard-total 5` 会生成分片索引 `0` 到 `4`，其中分片索引 `4` 为兜底分片。常规分片会对其分配的套件使用 `-only-testing` 运行。最后一个分片在不使用 `-only-testing` 的情况下运行，并对分配给前面所有分片的套件传入 `-skip-testing`，因此它会运行其计划内的套件，以及新增的套件或历史清单中缺失的套件。模块粒度不需要兜底分片，因为 `.xctestrun` 文件提供了模块列表。

## 构建阶段 {#build-phase}

构建测试并创建分片计划：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

此命令会：
1. 使用 `xcodebuild build-for-testing` 构建测试
2. 利用历史计时数据在 Tuist 服务器上创建分片计划
3. 上传 `.xctestproducts` 包，或写入供分片运行器使用的分片归档文件
4. 为 CI 系统输出分片矩阵

<!-- @snippet: ./_xcode-build-options -->

## 测试阶段 {#test-phase}

每个分片运行器执行其分配的测试：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

<!-- @snippet: ./_xcode-test-options -->

## 持续集成 {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

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

Tuist 会生成一个 `.tuist-shard-child-pipeline.yml`，你可以将其作为[子流水线](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines)触发。定义一个 `.tuist-shard` 模板作业，供生成的分片作业继承：

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

Tuist 会生成一个包含 [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) 所需参数的 `.tuist-shard-continuation.json`。`shard-plan-id` 参数必须在你的延续配置中声明：

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

Tuist 会生成一个 `.tuist-shard-pipeline.yml`，其中每个分片对应一个步骤。使用 `buildkite-agent pipeline upload` 上传该文件：

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

每个生成的步骤都在其环境中设置了 `TUIST_SHARD_INDEX` 和 `TUIST_SHARD_PLAN_ID`。使用共享脚本将测试命令添加到每个分片步骤中：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic 不支持动态矩阵作业，因此需要为每个分片定义单独的工作流。Tuist 会将 `TUIST_SHARD_MATRIX` 和 `TUIST_SHARD_COUNT` 写入 `CM_ENV` 文件，供构建工作流使用。Codemagic 的 `CM_ENV` 作用于工作流范围，因此确切的分片计划标识符不会跨工作流边界传递；测试工作流会回退到基于引用的分片查找：

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

在 Bitrise 上，Tuist 会将 `.tuist-shard-matrix.json`（包括 `shard_plan_id`）写入 `BITRISE_DEPLOY_DIR`，使其可作为构建产物供下游流水线阶段使用。每个测试工作流使用 `envman` 从下载的产物中提取计划 ID，以便将其注入测试命令的环境：

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

默认情况下，构建阶段会将 `.xctestproducts` 包上传到远程存储，每个分片运行器再下载它。如果你的 CI 提供商支持**共享卷**（跨作业挂载的持久化存储），你可以通过共享文件系统传递测试产物，从而完全跳过此上传/下载过程。

这可以显著缩短分片启动时间，尤其是对于大型测试包。

要使用共享卷：

1. 在**构建阶段**中，传入指向共享卷的 `-testProductsPath`，并添加 `--shard-skip-upload` 以跳过远程上传：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. 在**测试阶段**中，传入相同的 `-testProductsPath`，以便 Tuist 本地读取测试产物而非下载它们：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> 为每次工作流运行使用唯一路径（例如包含 CI 运行 ID），以避免并发运行之间发生冲突。你还应在分片完成后清理测试产物，避免在卷上积累过时数据。

| 标志 | 环境变量 | 描述 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | 跳过将测试产物包上传到远程存储 |

## 自管理产物 {#self-managed-artifacts}

如果你的 CI 提供商已具备产物上传和下载步骤，你可以让 Tuist 处理归档和解压，而由你的 CI 负责传输。

1. 在**构建阶段**中，传入 `--shard-archive-path`，以便 Tuist 将优化后的分片归档写入本地，而不是上传测试产物：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. 使用 CI 的原生产物步骤上传该归档。

3. 在每个**测试阶段**作业中，下载归档并将相同的路径传回给 Tuist：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

设置 `--shard-archive-path` 后，Tuist 会跳过远程测试产物传输，转而使用本地归档。如果你同时传入 `--shard-skip-upload`，则归档路径优先。

### Namespace {#namespace}

[Namespace](https://namespace.so) 运行器与 GitHub Actions 产物配合良好。一次性设置 `TUIST_TEST_SHARD_ARCHIVE_PATH`，使构建作业将分片归档写入本地，上传它，并在每个分片作业中下载它，然后再运行 `tuist xcodebuild test`：

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
