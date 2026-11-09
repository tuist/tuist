---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 测试分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 测试分片，将 Tuist 生成的 Xcode 项目中的测试分发到多个 CI 运行器上。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project-test-sharding}

生成项目的测试分片在构建和测试阶段均使用 `tuist test`。

## 工作原理 {#how-it-works}

测试分片遵循两阶段工作流：

1. **构建阶段：** Tuist 从已构建的 `.xctestrun` 文件中读取测试模块，并在服务器上创建**分片计划**。服务器使用过去 30 天的历史测试耗时数据，将测试分配到各个分片，使每个分片的耗时大致相同。构建阶段会输出一个**分片矩阵**，你的 CI 系统用它来启动并行运行器。
2. **测试阶段：** 每个持续集成运行器接收一个**分片索引**和确切的**分片计划标识符**，然后执行该计划的测试选择。

使用 `--shard-granularity suite` 时，服务器会根据当前 `.xctestrun` 中各模块在最近分支 CI 运行中报告的测试套件进行分配；对于没有分支历史的模块，则回退到项目的默认分支。合并多次运行可以保留被分片或选择性运行排除在最新报告之外的套件。服务器使用过去 30 天的套件耗时来估算持续时间。

Tuist 将这些已知套件均衡分配到请求的分片数量中，并将最后一个分片作为兜底。例如，`--shard-total 5` 会生成分片索引 `0` 到 `4`，其中分片索引 `4` 为兜底分片。常规分片使用 `-only-testing` 仅运行其分配的套件。最后一个分片在不使用 `-only-testing` 的情况下运行，并为分配给前面分片的每个套件传入 `-skip-testing`，因此它还会运行新增的套件、重命名的套件或历史清单中缺失的套件。模块粒度不需要兜底，因为 `.xctestrun` 文件提供了模块列表。

## 构建阶段 {#build-phase}

生成项目、构建测试并创建分片计划：

```sh
tuist test --build-only --shard-total 5
```

`--build-only` 标志指示 Tuist 构建测试但不运行它们。如果在不使用 `--build-only` 的情况下传递分片规划标志（`--shard-min`/`--shard-max`/`--shard-total`），Tuist 会报错。

该命令：
1. 根据你的清单生成 Xcode 项目
2. 构建你的测试
3. 使用历史耗时数据在 Tuist 服务器上创建分片计划
4. 上传 `.xctestproducts` 包或写入供分片运行器使用的分片归档
5. 为你的 CI 系统输出分片矩阵
6. 持久化<.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link>图（如适用），这样分片运行器就不需要重新生成项目

<!-- @snippet: ./_xcode-build-options -->

## 测试阶段 {#test-phase}

每个分片运行器执行其分配的测试：

```sh
tuist test --without-building
```

`--without-building` 标志指示 Tuist 使用之前构建的产品运行测试，而不是重新构建。如果在不使用 `--without-building` 的情况下设置 `TUIST_SHARD_INDEX` / `--shard-index`，Tuist 会报错。

<!-- @snippet: ./_xcode-test-options -->

> [!TIP]
> **选择性测试**
>
> 测试分片与<.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link>无缝协作。选择性测试图在构建阶段持久化，并在每个分片中恢复，因此运行器不需要重新生成项目。

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
        run: tuist test --build-only --shard-total 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    if: toJSON(fromJSON(needs.build.outputs.matrix).shard) != '[]'
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
      - run: tuist test --without-building
```

### GitLab CI {#gitlab-ci}

Tuist 生成一个 `.tuist-shard-child-pipeline.yml`，你可以将其作为[子流水线](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines)触发。定义一个 `.tuist-shard` 模板作业，供生成的分片作业扩展：

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

Tuist 生成一个包含[continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation)参数的 `.tuist-shard-continuation.json`。`shard-plan-id` 参数必须在你的延续配置中声明：

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

Tuist 生成一个 `.tuist-shard-pipeline.yml`，每个分片对应一个步骤。使用 `buildkite-agent pipeline upload` 上传它：

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

每个生成的步骤都在其环境中设置了 `TUIST_SHARD_INDEX` 和 `TUIST_SHARD_PLAN_ID`。使用共享脚本将测试命令添加到每个分片步骤：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic 不支持动态矩阵作业，因此为每个分片定义单独的工作流。Tuist 将 `TUIST_SHARD_MATRIX` 和 `TUIST_SHARD_COUNT` 写入 `CM_ENV` 文件，供构建工作流使用。Codemagic 的 `CM_ENV` 是工作流作用域的，因此确切的分片计划标识符不会跨越工作流边界；测试工作流会回退到基于引用的分片查找：

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

在 Bitrise 上，Tuist 将 `.tuist-shard-matrix.json`（包括 `shard_plan_id`）写入 `BITRISE_DEPLOY_DIR`，使其可作为构建产物供下游流水线阶段使用。每个测试工作流使用 `envman` 从下载的产物中提取计划 ID，以便将其传递到测试命令的环境：

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
> Bitrise 不支持在运行时动态创建并行作业。在流水线阶段中定义固定数量的分片工作流——同一阶段内的工作流会自动并行运行。

## 共享卷 {#shared-volumes}

默认情况下，构建阶段会将 `.xctestproducts` 包上传到远程存储，每个分片运行器再下载它。如果你的 CI 提供商支持**共享卷**（跨作业挂载的持久存储），你可以通过共享文件系统传递测试产物，从而完全跳过此上传/下载过程。

这可以显著缩短分片启动时间，尤其是对于大型测试包。

要使用共享卷：

1. 在**构建阶段**中，传递指向共享卷的 `-testProductsPath`（在 `--` 之后），并添加 `--shard-skip-upload` 以跳过远程上传：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. 在**测试阶段**中，传递相同的 `-testProductsPath`，以便 Tuist 从本地读取测试产物而不是下载它们：

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| 标志 | 环境变量 | 描述 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | 跳过将测试产物包上传到远程存储 |

## 自管理产物 {#self-managed-artifacts}

如果你的 CI 提供商已有产物上传和下载步骤，你可以让 Tuist 处理归档和解压，而由你的 CI 负责传输。

1. 在**构建阶段**中，传递 `--shard-archive-path`，以便 Tuist 将优化后的分片归档写入本地，而不是上传测试产物：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. 使用 CI 的原生产物步骤上传该归档。

3. 在每个**测试阶段**作业中，下载归档并将相同的路径传回给 Tuist：

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

设置 `--shard-archive-path` 后，Tuist 会跳过远程测试产物传输，转而使用本地归档。如果你同时传递 `--shard-skip-upload`，则归档路径优先。

当没有可运行的测试时（例如因为选择性测试跳过了每个测试目标），构建阶段会输出空的分片矩阵且不写入归档。仅当矩阵包含分片时才运行上传步骤。

> [!IMPORTANT]
> 为每次工作流运行使用唯一路径（例如包含 CI 运行 ID），以避免并发运行之间的冲突。你还应在分片完成后清理分片归档，以免在运行器上积累陈旧数据。

### Namespace {#namespace}

[Namespace](https://namespace.so) 运行器与 GitHub Actions 产物配合良好。一次性设置 `TUIST_TEST_SHARD_ARCHIVE_PATH`，使构建作业将分片归档写入本地，上传它，并在每个分片作业中于运行 `tuist test` 之前下载它：

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
      - if: toJSON(fromJSON(steps.build.outputs.matrix).shard) != '[]'
        uses: actions/upload-artifact@v4
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
      - run: tuist test --without-building
      - if: always()
        run: rm -rf /tmp/shards/${{ github.run_id }}
```
