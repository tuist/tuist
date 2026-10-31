---
{
  "title": "Xcode 測試分片",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 測試分片，將 Xcode 測試分散到多個 CI 執行器上。"
}
---
# Xcode 測試分片 {#xcode-test-sharding}

> [!WARNING]
> **要求**
>
> - 已設定<.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>。分片會使用過去 30 日的測試洞察時間數據來平衡各分片；如果沒有洞察數據，每個分片都會以測試套件未知的方式執行。

Xcode 專案的測試分片會使用 `tuist xcodebuild build-for-testing` 建立分片計劃，並使用 `tuist xcodebuild test` 執行每個分片。

## 運作方式 {#how-it-works}

測試分片採用兩階段工作流程：

1. **建構階段：** Tuist 會從已建構的 `.xctestrun` 檔案讀取測試模組，並在伺服器上建立**分片計劃**。伺服器會利用過去 30 日的歷史測試時間數據，將測試分配到各個分片，使每個分片的耗時大致相同。建構階段會輸出**分片矩陣**，供你的 CI 系統用來產生平行執行器。
2. **測試階段：** 每個持續整合執行器會收到一個**分片索引**和確切的**分片計劃識別碼**，然後執行該計劃所選取的測試。

在套件粒度下，伺服器會為每個模組選擇已知的測試套件：對於目前 `.xctestrun` 中的每個模組，它會合併正在建構分支上最近幾次 CI 執行的套件；如果模組沒有分支歷史記錄，則退回使用專案的預設分支。讀取多次執行而非僅最新一次很重要，因為分片執行會在每個分片完成時上傳一個測試執行結果，所以最新執行只包含迄今已處理的模組部分；此外，這樣也能避免選擇性測試執行隱藏在最新分支執行中被跳過的套件。

當使用 `--shard-granularity suite` 時，Tuist 會在請求的分片數量之間平衡已知套件，並將最後一個分片作為備用分片。例如，`--shard-total 5` 會產生分片索引 `0` 至 `4`，其中分片索引 `4` 為備用分片。常規分片會針對其分配的套件使用 `-only-testing` 執行。最後一個分片則不使用 `-only-testing`，並對分配給較早分片的每個套件傳遞 `-skip-testing`，因此它會執行其計劃中的套件，以及新加入的套件或歷史清單中缺少的套件。模組粒度不需要備用分片，因為 `.xctestrun` 檔案已提供模組清單。

## 建構階段 {#build-phase}

建構你的測試並建立分片計劃：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5
```

此指令會：
1. 使用 `xcodebuild build-for-testing` 建構你的測試
2. 使用歷史時間數據在 Tuist 伺服器上建立分片計劃
3. 上傳 `.xctestproducts` 套件，或寫入分片封存檔供分片執行器使用
4. 為你的 CI 系統輸出分片矩陣

### 建構選項 {#build-options}

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 最大分片數量。與 `--shard-max-duration` 搭配使用以限制分片數量 |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 最小分片數量 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 確切的分片數量（與 `--shard-min`/`--shard-max` 互斥）。在套件粒度下，最後一個分片為備用分片 |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 每個分片的目標最長持續時間（毫秒） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（預設）將整個測試模組分配到各個分片；`suite` 則分配個別測試類別，以進行更細粒度的平衡 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計劃的唯一識別碼（在支援的 CI 提供者上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist 寫入優化後分片封存檔的路徑，而非將測試產品上傳至遠端儲存空間 |

## 測試階段 {#test-phase}

每個分片執行器會執行其分配的測試：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### 測試選項 {#test-options}

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 要執行的分片之零基索引 |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | 由建構階段產生的確切分片計劃識別碼。自動產生的提供者輸出會自動包含此值 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計劃的唯一識別碼（在支援的 CI 提供者上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | 本機管理的分片封存檔路徑；Tuist 會解壓縮此檔案，而非從遠端儲存空間下載測試產品 |

Tuist 會下載 `.xctestproducts` 套件，並過濾只包含分配給該分片的測試。

## 持續整合 {#continuous-integration}

Tuist 會自動偵測以下 CI 提供者：

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

對於其他提供者，請參閱 `.tuist-shard-matrix.json` 檔案以設定平行工作。

### GitHub Actions {#github-actions}

使用矩陣策略平行執行分片：

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

Tuist 會產生 `.tuist-shard-child-pipeline.yml`，你可以將其作為 [子管線](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines) 觸發。定義一個 `.tuist-shard` 範本工作，讓產生的分片工作繼承：

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

Tuist 會產生包含 [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) 參數的 `.tuist-shard-continuation.json`。`shard-plan-id` 參數必須在你的延續設定中宣告：

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

Tuist 會產生 `.tuist-shard-pipeline.yml`，每個分片對應一個步驟。使用 `buildkite-agent pipeline upload` 上傳它：

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

每個產生的步驟都在其環境中設定了 `TUIST_SHARD_INDEX` 和 `TUIST_SHARD_PLAN_ID`。使用共用腳本將測試指令添加到每個分片步驟：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Codemagic {#codemagic}

Codemagic 不支援動態矩陣工作，因此請為每個分片定義獨立的工作流程。Tuist 會將 `TUIST_SHARD_MATRIX` 和 `TUIST_SHARD_COUNT` 寫入 `CM_ENV` 檔案，以便在建構工作流程中使用。Codemagic 的 `CM_ENV` 僅限於工作流程範圍，因此確切的分片計劃識別碼不會跨越工作流程邊界；測試工作流程會回退到基於參考的分片查找：

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

在 Bitrise 上，Tuist 會將 `.tuist-shard-matrix.json`（包括 `shard_plan_id`）寫入 `BITRISE_DEPLOY_DIR`，使其可作為建構產物供下游管線階段使用。每個測試工作流程使用 `envman` 從下載的產物中提取計劃 ID，以便將其傳遞到測試指令的環境中：

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
> Bitrise 不支援在執行階段動態建立平行工作。請在你的管線階段中定義固定數量的分片工作流程 — 同一階段內的工作流程會自動平行執行。

## 共用磁碟區 {#shared-volumes}

預設情況下，建構階段會將 `.xctestproducts` 套件上傳至遠端儲存空間，而每個分片執行器會下載它。如果你的 CI 提供者支援 **共用磁碟區**（跨工作掛載的持久化儲存空間），你可以透過共用檔案系統傳遞測試產品，完全略過此上傳/下載過程。

這可以顯著減少分片啟動時間，特別是對於大型測試套件。

要使用共用磁碟區：

1. 在 **建構階段** 中，傳遞指向共用磁碟區的 `-testProductsPath`，並添加 `--shard-skip-upload` 以略過遠端上傳：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-skip-upload \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. 在 **測試階段** 中，傳遞相同的 `-testProductsPath`，以便 Tuist 從本機讀取測試產品，而非下載它們：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

> [!IMPORTANT]
> 為每個工作流程執行使用唯一路徑（例如包含 CI 執行 ID），以避免同時執行之間的衝突。你還應該在分片完成後清理測試產品，以避免在磁碟區上累積過時數據。

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | 略過將測試產品套件上傳至遠端儲存空間 |

## 自行管理的產物 {#self-managed-artifacts}

如果你的 CI 提供者已有產物上傳和下載步驟，你可以讓 Tuist 處理封存和解壓縮，而由你的 CI 處理傳輸。

1. 在 **建構階段** 中，傳遞 `--shard-archive-path`，以便 Tuist 將優化後的分片封存檔寫入本機，而非上傳測試產品：

```sh
tuist xcodebuild build-for-testing \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. 使用你 CI 的原生產物步驟上傳該封存檔。

3. 在每個 **測試階段** 工作中，下載封存檔並將相同的路徑傳回給 Tuist：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

當設定 `--shard-archive-path` 時，Tuist 會略過遠端測試產品傳輸，改用本機封存檔。如果你同時傳遞 `--shard-skip-upload`，則封存檔路徑優先。

### Namespace {#namespace}

[Namespace](https://namespace.so) 執行器與 GitHub Actions 產物配合良好。設定 `TUIST_TEST_SHARD_ARCHIVE_PATH` 一次，讓建構工作將分片封存檔寫入本機、上傳它，並在每個分片工作中下載它，然後再執行 `tuist xcodebuild test`：

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
