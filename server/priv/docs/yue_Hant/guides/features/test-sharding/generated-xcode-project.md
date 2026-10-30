---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist Test Sharding，將 Tuist 生成的 Xcode 專案中的測試分散到多個 CI runner 上執行。"
}
---
# 生成嘅 Xcode 專案 {#generated-xcode-project-test-sharding}

針對生成專案嘅測試分片會喺建構同測試階段使用 `tuist test`。

## 運作方式 {#how-it-works}

測試分片採用兩階段工作流程：

1. **建構階段：** Tuist 會從已建構嘅 `.xctestrun` 檔案讀取測試模組，並喺伺服器上建立**分片計劃**。伺服器會利用過去 30 日嘅歷史測試計時數據，將測試分配到各個分片，令每個分片所需時間大致相同。建構階段會輸出**分片矩陣**，你嘅 CI 系統可以用佢嚟啟動平行執行器。
2. **測試階段：** 每個持續整合執行器會收到一個**分片索引**同埋準確嘅**分片計劃識別碼**，然後執行該計劃所選定嘅測試。

當使用 `--shard-granularity suite` 時，Tuist 唔會喺建構階段啟動每個測試套件來枚舉測試組。相反，當前嘅 `.xctestrun` 檔案會提供模組清單，而伺服器會為每個模組選擇已知嘅測試組：對於每個模組，它會合併正在建構分支上最近幾次 CI 執行中出現嘅測試組。如果某個模組在該分支上沒有歷史記錄，伺服器會回退到專案嘅預設分支。讀取多次執行而非僅最新一次很重要，因為分片執行會在每個分片完成時上傳一次測試執行結果，所以最近嘅執行只包含迄今為止已攝取嘅模組部分；同時，這樣可以避免選擇性測試執行隱藏在最近分支執行中被跳過嘅測試組。伺服器仍然會使用過去 30 日嘅測試組計時數據來估算持續時間。

Tuist 會將這些已知測試組平均分配到請求嘅分片數量中，並將最後一個分片用作兜底。例如，`--shard-total 5` 會產生由 `0` 到 `4` 嘅分片索引，其中分片索引 `4` 作為兜底。常規分片會使用 `-only-testing` 來運行分配給它們嘅測試組。最後一個分片運行時不使用 `-only-testing`，並對所有分配給早期分片嘅測試組傳遞 `-skip-testing`，因此它也會運行新加入嘅測試組、重新命名嘅測試組，或歷史清單中缺失嘅測試組。模組粒度不需要兜底，因為 `.xctestrun` 檔案已經提供咗模組清單。

## 建構階段 {#build-phase}

生成你嘅專案、建構你嘅測試，並建立分片計劃：

```sh
tuist test --build-only --shard-total 5
```

`--build-only` 標誌告訴 Tuist 建構測試但唔執行它們。如果你傳遞分片規劃標誌（`--shard-min`/`--shard-max`/`--shard-total`）而沒有 `--build-only`，Tuist 會報錯。

此命令會：
1. 根據你嘅 manifest 生成 Xcode 專案
2. 建構你嘅測試
3. 使用歷史計時數據在 Tuist 伺服器上建立分片計劃
4. 上傳 `.xctestproducts` 套件或寫入分片歸檔以供分片執行器使用
5. 為你嘅 CI 系統輸出分片矩陣
6. 持久化 <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link> 圖（如適用），令分片執行器無需重新生成專案

### 建構選項 {#build-options}

| 標誌 | 環境變量 | 描述 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 最大分片數量。與 `--shard-max-duration` 一起使用以限制分片數量 |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 最小分片數量 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 精確嘅分片數量（與 `--shard-min`/`--shard-max` 互斥）。使用測試組粒度時，最後一個分片為兜底 |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 每個分片嘅目標最大持續時間（毫秒） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（預設）將整個測試模組分配到各個分片；`suite` 將單個測試類分配到各個分片，以實現更細粒度嘅平衡 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計劃嘅唯一識別碼（在支援嘅 CI 提供商上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist 寫入優化後分片歸檔嘅路徑，而非將測試產品上傳到遠程存儲 |

## 測試階段 {#test-phase}

每個分片執行器執行其分配嘅測試：

```sh
tuist test --without-building
```

`--without-building` 標誌告訴 Tuist 使用之前建構嘅產品來運行測試，而非重新建構。如果設置咗 `TUIST_SHARD_INDEX` / `--shard-index` 但沒有 `--without-building`，Tuist 會報錯。

### 測試選項 {#test-options}

| 標誌 | 環境變量 | 描述 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 要執行嘅分片嘅零基索引 |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | 由建構階段發出嘅精確分片計劃識別碼。生成嘅提供商輸出會自動包含此值 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計劃嘅唯一識別碼（在支援嘅 CI 提供商上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | 本地管理嘅分片歸檔路徑；Tuist 會提取它，而非從遠程存儲下載測試產品 |

Tuist 會下載 `.xctestproducts` 套件並進行過濾，只包含分配給該分片嘅測試。

> [!TIP]
> **選擇性測試**
>
> 測試分片可與 <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link> 無縫配合使用。選擇性測試圖在建構階段被持久化，並在每個分片中恢復，因此執行器無需重新生成專案。

## 持續整合 {#continuous-integration}

Tuist 會自動檢測以下 CI 提供商：

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

對於其他提供商，請參考 `.tuist-shard-matrix.json` 文件以設置平行作業。

### GitHub Actions {#github-actions}

使用矩陣策略平行運行分片：

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

Tuist 會生成一個 `.tuist-shard-child-pipeline.yml`，你可以將其作為 [子流水線](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines) 觸發。定義一個 `.tuist-shard` 模板作業，供生成的分片作業擴展：

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

Tuist 會生成一個包含 [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) 參數嘅 `.tuist-shard-continuation.json`。`shard-plan-id` 參數必須在你嘅延續配置中聲明：

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

Tuist 會生成一個 `.tuist-shard-pipeline.yml`，每個分片對應一個步驟。使用 `buildkite-agent pipeline upload` 上傳它：

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

每個生成的步驟都在其環境中設置咗 `TUIST_SHARD_INDEX` 和 `TUIST_SHARD_PLAN_ID`。使用共享腳本將測試命令添加到每個分片步驟：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic 不支援動態矩陣作業，因此需要為每個分片定義單獨嘅工作流程。Tuist 會將 `TUIST_SHARD_MATRIX` 和 `TUIST_SHARD_COUNT` 寫入 `CM_ENV` 文件，以便在建構工作流程中使用。Codemagic 嘅 `CM_ENV` 係工作流程範圍內嘅，因此精確嘅分片計劃識別碼不會跨越工作流程邊界；測試工作流程會回退到基於參考嘅分片查找：

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

在 Bitrise 上，Tuist 會將 `.tuist-shard-matrix.json`（包括 `shard_plan_id`）寫入 `BITRISE_DEPLOY_DIR`，使其可用作下游流水線階段嘅建構產物。每個測試工作流程使用 `envman` 從下載嘅產物中提取計劃 ID，以便將其傳遞到測試命令嘅環境中：

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
> Bitrise 不支援在運行時動態創建平行作業。在你嘅流水線階段中定義固定數量嘅分片工作流程 — 同一階段內嘅工作流程會自動平行運行。

## 共享卷 {#shared-volumes}

預設情況下，建構階段會將 `.xctestproducts` 套件上傳到遠程存儲，並且每個分片執行器都會下載它。如果你嘅 CI 提供商支援 **共享卷**（跨作業掛載嘅持久存儲），你可以通過共享文件系統傳遞測試產品，從而完全跳過此上傳/下載過程。

這可以顯著減少分片啟動時間，特別是對於大型測試套件。

要使用共享卷：

1. 在 **建構階段** 中，傳遞 `-testProductsPath`（在 `--` 之後）指向共享卷，並添加 `--shard-skip-upload` 以跳過遠程上傳：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. 在 **測試階段** 中，傳遞相同嘅 `-testProductsPath`，以便 Tuist 從本地讀取測試產品而非下載它們：

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| 標誌 | 環境變量 | 描述 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | 跳過將測試產品套件上傳到遠程存儲 |

## 自管理產物 {#self-managed-artifacts}

如果你嘅 CI 提供商已經有產物上傳和下載步驟，你可以讓 Tuist 處理歸檔和解壓，而讓你嘅 CI 處理傳輸。

1. 在 **建構階段** 中，傳遞 `--shard-archive-path`，以便 Tuist 將優化後嘅分片歸檔寫入本地，而非上傳測試產品：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. 使用你嘅 CI 原生產物步驟上傳該歸檔。

3. 在每個 **測試階段** 作業中，下載歸檔並將相同路徑傳回 Tuist：

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

當設定 `--shard-archive-path` 時，Tuist 會跳過遠程測試產品傳輸，改為使用本地歸檔。如果你同時傳遞 `--shard-skip-upload`，則歸檔路徑具有優先權。

當沒有測試可運行時（例如因為選擇性測試跳過了所有測試目標），建構階段會輸出空嘅分片矩陣且不會寫入任何歸檔。僅當矩陣包含分片時才執行上傳步驟。

> [!IMPORTANT]
> 為每次工作流程運行使用唯一路徑（例如包含 CI 運行 ID），以避免並發運行之間嘅衝突。你還應該在分片完成後清理分片歸檔，以避免在執行器上積聚過時數據。

### Namespace {#namespace}

[Namespace](https://namespace.so) 執行器與 GitHub Actions 產物配合良好。設置一次 `TUIST_TEST_SHARD_ARCHIVE_PATH`，以便建構作業將分片歸檔寫入本地，上傳它，並在每個分片作業中下載它，然後再運行 `tuist test`：

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
