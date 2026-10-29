---
{
  "title": "Gradle Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Gradle tests across multiple CI runners with Tuist Test Sharding."
}
---
# Gradle 測試分片 {#gradle-test-sharding}

Tuist Gradle 外掛程式內建支援測試分片。它會根據 Tuist 在你專案的測試任務先前 CI 執行中記錄的測試套件來規劃，並使用 Tuist 伺服器根據歷史計時資料建立平衡的分片計劃。

> [!IMPORTANT] REQUIREMENTS
> - <.localized_link href="/guides/features/test-insights/gradle">測試洞察</.localized_link> 必須已設定

## 運作方式 {#how-it-works}

測試分片採用兩階段工作流程：

1. **建構階段：** Tuist 會根據為你專案記錄的測試套件，在伺服器上建立**分片計劃**。伺服器會使用過去 30 天的歷史測試計時資料，將測試分配到各個分片，使每個分片耗費的時間大致相同。建構階段會輸出**分片矩陣**，供你的 CI 系統用來產生平行執行器。
2. **測試階段：** 每個 CI 執行器會收到一個**分片索引**，並只執行指派給該分片的測試。最後一個分片也會執行所有未指派給其他分片的測試套件。

## 建構階段 {#build-phase}

使用 `tuistPrepareTestShards` 任務準備測試分片：

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5
```

此任務會：
1. 找出具有要分片之測試任務的專案，而無需編譯它們
2. 根據過去 30 天為這些專案記錄的測試套件與計時資料，在 Tuist 伺服器上建立分片計劃
3. 為你的 CI 系統輸出分片矩陣

當尚未記錄任何測試套件時（例如首次執行），計劃會包含單一的分片，並執行所有測試。

### 建構選項 {#build-options}

透過 Gradle 專案屬性設定分片：

| 屬性 | 說明 |
|----------|-------------|
| `-PtuistShardMax=<N>` | 最大分片數量（預設：2） |
| `-PtuistShardMin=<N>` | 最小分片數量 |
| `-PtuistShardMaxDuration=<MS>` | 每個分片的目標最長持續時間（毫秒） |
| `-PtuistShardTestTask=<NAME>` | 要進行分片的測試任務，例如 `testDebugUnitTest`。預設為建構中的所有測試任務 |

具有多個建構變體的 Android 專案，每個變體都有一個單元測試任務。將 `-PtuistShardTestTask` 設定為你的分片所執行的變體，這樣只會規劃具有該變體的專案：

```sh
./gradlew tuistPrepareTestShards \
  -PtuistShardMax=5 \
  -PtuistShardTestTask=testDebugUnitTest
```

分片參考會自動從 CI 環境變數（`GITHUB_RUN_ID`、`CI_PIPELINE_ID` 等）衍生，或可透過 `TUIST_SHARD_REFERENCE` 環境變數明確設定。

## 測試階段 {#test-phase}

每個分片執行器會使用標準的 `test` 任務執行其指派的測試。當設定 `TUIST_SHARD_INDEX` 時，外掛程式會自動從伺服器取得分片指派，並篩選測試執行範圍，僅包含指派的測試套件。若專案中沒有測試套件指派給該分片，則會跳過其測試任務。

最後一個分片會執行所有測試任務，並排除指派給其他分片的套件，因此尚未有記錄執行的套件（例如新加入的套件）仍會執行。

```sh
TUIST_SHARD_INDEX=0 ./gradlew test
```

若你在建構階段設定了 `-PtuistShardTestTask`，請在每個分片中執行相同的任務，例如 `./gradlew testDebugUnitTest`。

## 持續整合 {#continuous-integration}

Tuist 會自動偵測下列 CI 供應商：

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

對於其他供應商，請參閱 `.tuist-shard-matrix.json` 檔案以設定平行作業。

### GitHub Actions {#github-actions}

使用矩陣策略平行執行分片：

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

Tuist 會產生 `.tuist-shard-child-pipeline.yml`，你可以將其作為 [子管線](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines) 觸發。定義一個 `.tuist-shard` 範本作業，讓產生的分片作業繼承：

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

子管線需要 `.tuist-shard` 作業範本：

```yaml
# .gitlab/shard-template.yml
.tuist-shard:
  script:
    - tuist auth login
    - ./gradlew test
```

### CircleCI {#circleci}

Tuist 會產生包含 [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) 參數的 `.tuist-shard-continuation.json`：

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

Tuist 會產生 `.tuist-shard-pipeline.yml`，每個分片對應一個步驟。使用 `buildkite-agent pipeline upload` 上傳：

```yaml
# pipeline.yml
steps:
  - label: "Build test shards"
    command: |
      tuist auth login
      ./gradlew tuistPrepareTestShards -PtuistShardMax=5
      buildkite-agent pipeline upload .tuist-shard-pipeline.yml
```

每個產生的步驟都在其環境中設定了 `TUIST_SHARD_INDEX`。使用共用腳本將測試命令加入每個分片步驟：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
./gradlew test
```

### Codemagic {#codemagic}

Codemagic 不支援動態矩陣作業，因此請為每個分片定義獨立的 workflow。Tuist 會將 `TUIST_SHARD_MATRIX` 和 `TUIST_SHARD_COUNT` 寫入 `CM_ENV` 檔案，以便在每個 workflow 中使用：

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
          tuist auth login
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
          tuist auth login
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

在 Bitrise 上，Tuist 會將 `.tuist-shard-matrix.json` 寫入 `BITRISE_DEPLOY_DIR`，使其可作為下游管線階段的建構產物。使用具有預先定義平行 workflow 的 Bitrise Pipelines：

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

> [!TIP]
> Bitrise 不支援在執行階段動態建立平行作業。請在你的管線階段中定義固定數量的分片 workflow — 同一階段內的 workflow 會自動平行執行。
