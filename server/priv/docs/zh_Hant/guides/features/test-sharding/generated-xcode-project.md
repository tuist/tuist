---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Test sharding · Features · Guides · Tuist",
  "description": "Distribute tests in a Tuist-generated Xcode project across multiple CI runners with Tuist Test Sharding."
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-test-sharding}

針對產生的專案，測試分片在建置與測試階段皆使用 `tuist test`。

## 運作方式 {#how-it-works}

測試分片採用兩階段工作流程：

1. **建置階段：** Tuist 會從已建置的 `.xctestrun` 檔案讀取測試模組，並在伺服器上建立**分片計畫**。伺服器會使用過去 30 天的歷史測試計時資料，將測試分配至各分片，使每個分片的執行時間大致相同。建置階段會輸出**分片矩陣**，供你的 CI 系統用來啟動平行執行器。
2. **測試階段：** 每個持續整合執行器會收到**分片索引**與確切的**分片計畫識別碼**，然後執行該計畫所選取的測試。

當使用 `--shard-granularity suite` 時，Tuist 在建置階段不會啟動每個測試套件來列舉測試組。相反地，目前的 `.xctestrun` 檔案會提供模組清單，伺服器則為每個模組選擇已知的測試組：針對每個模組，它會合併正在建置之分支上最近幾次 CI 執行的測試組。若某模組在該分支上沒有歷史記錄，伺服器會退回至專案的預設分支。讀取多次執行而非僅最新一次很重要，因為分片執行會在每個分片完成時上傳一個測試執行結果，因此最新執行結果僅包含迄今已匯入的模組部分；同時也能避免選擇性測試執行隱藏在最近一次分支執行中被跳過的測試組。伺服器仍會使用過去 30 天的測試組計時資料來估算持續時間。

Tuist 會將這些已知測試組平均分配至要求的分片數量，並將最後一個分片作為兜底分片。例如，`--shard-total 5` 會產生分片索引 `0` 到 `4`，其中分片索引 `4` 為兜底分片。一般分片會針對其指派的測試組使用 `-only-testing` 執行。最後一個分片則在不使用 `-only-testing` 的情況下執行，並對所有指派給先前分片的測試組傳遞 `-skip-testing`，因此也會執行新增的測試組、重新命名的測試組，或歷史清單中遺漏的測試組。模組粒度不需要兜底分片，因為 `.xctestrun` 檔案已提供模組清單。

## 建置階段 {#build-phase}

產生你的專案、建置你的測試，並建立分片計畫：

```sh
tuist test --build-only --shard-total 5
```

`--build-only` 旗標會指示 Tuist 建置測試但不執行它們。若你在未提供 `--build-only` 的情況下傳遞分片規劃旗標（`--shard-min`/`--shard-max`/`--shard-total`），Tuist 會回報錯誤。

此命令會：
1. 從你的資訊清單產生 Xcode 專案
2. 建置你的測試
3. 使用歷史計時資料在 Tuist 伺服器上建立分片計畫
4. 上傳 `.xctestproducts` 套件，或寫入供分片執行器使用的分片封存檔
5. 為你的 CI 系統輸出分片矩陣
6. 保留<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>圖表（如適用），使分區執行器無需重新生成專案

### 建置選項 {#build-options}

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 最大分片數量。與 `--shard-max-duration` 搭配使用以限制分片數量 |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 最小分片數量 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 確切的分片數量（與 `--shard-min`/`--shard-max` 互斥）。在使用測試組粒度時，最後一個分片為兜底分片 |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 每個分片的目標最長持續時間（毫秒） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（預設）會將整個測試模組分配至各分片；`suite` 則會將個別測試類別分配至各分片，以實現更細緻的負載平衡 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計畫的唯一識別碼（在支援的 CI 提供者上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist 寫入最佳化分片封存檔的路徑，而非將測試產品上傳至遠端儲存空間 |

## 測試階段 {#test-phase}

每個分片執行器會執行其指派的測試：

```sh
tuist test --without-building
```

`--without-building` 旗標會指示 Tuist 使用先前建置的產品執行測試，而非重新建置。若在未設定 `--without-building` 的情況下設定 `TUIST_SHARD_INDEX` / `--shard-index`，Tuist 會回報錯誤。

### 測試選項 {#test-options}

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 要執行的分片之從零開始的索引 |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | 由建置階段輸出的確切分片計畫識別碼。產生的提供者輸出會自動包含此值 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片計畫的唯一識別碼（在支援的 CI 提供者上自動衍生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | 本機管理的分片封存檔路徑；Tuist 會解壓縮它，而非從遠端儲存空間下載測試產品 |

Tuist 會下載 `.xctestproducts` 套件，並篩選出僅包含指派給該分片的測試。

> [!TIP]
> **選擇性測試**
>
> 測試分片可與<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>無縫搭配運作。選擇性測試圖表會在建置階段保留，並在每個分片中還原，因此執行器無需重新產生專案。

## 持續整合 {#continuous-integration}

Tuist 會自動偵測下列 CI 提供者：

- [GitHub Actions](#github-actions)
- [GitLab CI](#gitlab-ci)
- [CircleCI](#circleci)
- [Buildkite](#buildkite)
- [Codemagic](#codemagic)
- [Bitrise](#bitrise)

對於其他提供者，請參閱 `.tuist-shard-matrix.json` 檔案以設定平行作業。

### GitHub Actions {#github-actions}

使用矩陣策略來平行執行分片：

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

Tuist 會產生 `.tuist-shard-child-pipeline.yml`，你可以將其作為 [子管線](https://docs.gitlab.com/ee/ci/pipelines/downstream_pipelines.html#parent-child-pipelines) 觸發。定義一個 `.tuist-shard` 範本作業，讓產生的分片作業擴充它：

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

Tuist 會產生包含 [continuation orb](https://circleci.com/developer/orbs/orb/circleci/continuation) 參數的 `.tuist-shard-continuation.json`。`shard-plan-id` 參數必須在你的延續組態中宣告：

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

Tuist 會產生 `.tuist-shard-pipeline.yml`，其中每個分片對應一個步驟。使用 `buildkite-agent pipeline upload` 上傳它：

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

每個產生的步驟都在其環境中設定了 `TUIST_SHARD_INDEX` 和 `TUIST_SHARD_PLAN_ID`。使用共用腳本將測試命令新增至每個分片步驟：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic 不支援動態矩陣作業，因此請為每個分片定義獨立的工作流程。Tuist 會將 `TUIST_SHARD_MATRIX` 和 `TUIST_SHARD_COUNT` 寫入 `CM_ENV` 檔案，以便在建置工作流程中使用。Codemagic 的 `CM_ENV` 是工作流程範圍，因此確切的分片計畫識別碼不會跨越工作流程邊界；測試工作流程會回退至基於參考的分片查詢：

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

在 Bitrise 上，Tuist 會將 `.tuist-shard-matrix.json`（包含 `shard_plan_id`）寫入 `BITRISE_DEPLOY_DIR`，使其可作為下游管線階段的建置成品使用。每個測試工作流程會使用 `envman` 從下載的成品中提取計畫 ID，以便將其傳遞至測試命令的環境：

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
> Bitrise 不支援在執行階段動態建立平行作業。請在你的管線階段中定義固定數量的分片工作流程 — 同一階段內的工作流程會自動平行執行。

## 共用磁碟區 {#shared-volumes}

預設情況下，建置階段會將 `.xctestproducts` 套件上傳至遠端儲存空間，而每個分片執行器會下載它。如果你的 CI 提供者支援 **共用磁碟區**（跨作業掛載的持久化儲存空間），你可以透過共用檔案系統傳遞測試產品，完全略過此上傳/下載步驟。

這可以顯著減少分片啟動時間，特別是對於大型測試套件。

若要使用共用磁碟區：

1. 在 **建置階段** 中，傳遞 `-testProductsPath`（在 `--` 之後）指向共用磁碟區，並新增 `--shard-skip-upload` 以略過遠端上傳：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. 在 **測試階段** 中，傳遞相同的 `-testProductsPath`，讓 Tuist 從本機讀取測試產品，而非下載它們：

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | 略過將測試產品套件上傳至遠端儲存空間 |

## 自行管理的成品 {#self-managed-artifacts}

如果你的 CI 提供者已有成品上傳和下載步驟，你可以讓 Tuist 處理封存和解壓縮，而由你的 CI 處理傳輸。

1. 在 **建置階段** 中，傳遞 `--shard-archive-path`，讓 Tuist 將最佳化的分片封存檔寫入本機，而非上傳測試產品：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. 使用你的 CI 的原生成品步驟上傳該封存檔。

3. 在每個 **測試階段** 作業中，下載封存檔並將相同的路徑傳回給 Tuist：

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

當設定 `--shard-archive-path` 時，Tuist 會略過遠端測試產品傳輸，並改用本機封存檔。如果你也傳遞 `--shard-skip-upload`，則封存檔路徑具有優先權。

當沒有要執行的測試時（例如因為選擇性測試略過了每個測試目標），建置階段會輸出空的分片矩陣且不寫入任何封存檔。僅在矩陣包含分片時才執行上傳步驟。

> [!IMPORTANT]
> 為每次工作流程執行使用唯一的路徑（例如包含 CI 執行 ID），以避免同時執行之間發生衝突。你也應該在完成分片後清理分片封存檔，以避免在執行器上累積過時的資料。

### Namespace {#namespace}

[Namespace](https://namespace.so) 執行器與 GitHub Actions 成品搭配運作良好。設定一次 `TUIST_TEST_SHARD_ARCHIVE_PATH`，讓建置作業將分片封存檔寫入本機、上傳它，並在每個分片作業中於執行 `tuist test` 之前下載它：

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
