---
{
  "title": "生成的 Xcode 專案",
  "titleTemplate": ":title · 測試分片 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 測試分片，將 Tuist 生成的 Xcode 專案中的測試分散到多個 CI 執行器上。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-test-sharding}

針對產生的專案，測試分片在建置與測試階段皆使用 `tuist test`。

## 運作方式 {#how-it-works}

測試分片採用兩階段工作流程：

1. **建置階段：** Tuist 從已建置的 `.xctestrun` 檔案讀取測試模組，並在伺服器上建立**分片計畫**。伺服器會依據過去 30 天的歷史測試耗時資料，將測試分配到各分片，使每個分片的執行時間大致相同。建置階段會輸出**分片矩陣**，供你的 CI 系統用來啟動平行執行器。
2. **測試階段：** 每個持續整合執行器會收到**分片索引**與確切的**分片計畫識別碼**，然後執行該計畫所選取的測試。

當使用 `--shard-granularity suite` 時，伺服器會採用近期在該分支上的 CI 執行回報給目前 `.xctestrun` 中每個模組的套件；若模組沒有分支歷史紀錄，則回退至專案的預設分支。合併多次執行可保留被分片或選擇性執行遺漏於最新報告中的套件。伺服器會使用過去 30 天的套件耗時來估算duration。

Tuist 會將這些已知套件平均分配至要求的分片數量，並將最後一個分片作為兜底分片。例如，`--shard-total 5` 會產生分片索引 `0` 到 `4`，其中分片索引 `4` 為兜底分片。一般分片會針對其分配的套件使用 `-only-testing` 執行。最後一個分片在不使用 `-only-testing` 的情況下執行，並對所有分配給前面分片的套件傳遞 `-skip-testing`，因此也會執行新加入的套件、重新命名的套件，或歷史清單中缺少的套件。模組粒度不需要兜底分片，因為 `.xctestrun` 檔案已提供模組清單。

## 建置階段 {#build-phase}

產生你的專案、建置測試，並建立分片計畫：

```sh
tuist test --build-only --shard-total 5
```

`--build-only` 旗標會指示 Tuist 建置測試但不執行。若你在未提供 `--build-only` 的情況下傳入分片規劃旗標（`--shard-min`/`--shard-max`/`--shard-total`），Tuist 會報錯。

此指令會：
1. 從你的 manifest 產生 Xcode 專案
2. 建置你的測試
3. 使用歷史耗時資料在 Tuist 伺服器上建立分片計畫
4. 上傳 `.xctestproducts` bundle，或寫入供分片執行器使用的分片封存檔
5. 輸出供你的 CI 系統使用的分片矩陣
6. 持久化<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>圖（如適用），讓分片執行器無需重新產生專案

<!-- @snippet: ./_xcode-build-options -->

## 測試階段 {#test-phase}

每個分片執行器會執行其分配的測試：

```sh
tuist test --without-building
```

`--without-building` 旗標會指示 Tuist 使用先前建置的產品執行測試，而非重新建置。若在未設定 `--without-building` 的情況下設定 `TUIST_SHARD_INDEX` / `--shard-index`，Tuist 會報錯。

<!-- @snippet: ./_xcode-test-options -->

> [!TIP]
> **選擇性測試**
>
> 測試分片可與<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>無縫搭配。選擇性測試圖會在建置階段持久化，並在每個分片中還原，因此執行器無需重新產生專案。

## 持續整合 {#continuous-integration}

<!-- @snippet: ./_ci-providers -->

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

Tuist 會產生 `.tuist-shard-child-pipeline.yml`，你可以將其觸發為[子管線](https://docs.gitlab.com/ci/pipelines/downstream_pipelines/#parent-child-pipelines)。定義一個 `.tuist-shard` 範本工作，讓產生的分片工作繼承：

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

Tuist 會產生 `.tuist-shard-pipeline.yml`，每個分片對應一個步驟。使用 `buildkite-agent pipeline upload` 上傳：

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

每個產生的步驟都會在其環境中設定 `TUIST_SHARD_INDEX` 與 `TUIST_SHARD_PLAN_ID`。使用共用腳本將測試指令加入每個分片步驟：

```bash
# .buildkite/shard-step.sh
#!/bin/bash
tuist auth login
tuist test --without-building
```

### Codemagic {#codemagic}

Codemagic 不支援動態矩陣工作，因此請為每個分片定義獨立的工作流程。Tuist 會將 `TUIST_SHARD_MATRIX` 與 `TUIST_SHARD_COUNT` 寫入 `CM_ENV` 檔案，供建置工作流程使用。Codemagic 的 `CM_ENV` 屬於工作流程範圍，因此確切的分片計畫識別碼不會跨越工作流程邊界；測試工作流程會回退至基於參考的分片查找：

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

在 Bitrise 上，Tuist 會將 `.tuist-shard-matrix.json`（包含 `shard_plan_id`）寫入 `BITRISE_DEPLOY_DIR`，使其可作為下游管線階段的建置產物。每個測試工作流程會使用 `envman` 從下載的產物中擷取計畫 ID，以便將其傳遞至測試指令的環境：

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
> Bitrise 不支援在執行期間動態建立平行工作。請在你的管線階段中定義固定數量的分片工作流程——同一階段內的工作流程會自動平行執行。

## 共用磁碟區 {#shared-volumes}

預設情況下，建置階段會將 `.xctestproducts` bundle 上傳至遠端儲存空間，而每個分片執行器會下載它。若你的 CI 供應商支援**共用磁碟區**（跨工作掛載的持久化儲存空間），你可以透過共用檔案系統傳遞測試產品，完全略過此上傳/下載步驟。

這可以顯著縮短分片啟動時間，特別是對於大型測試套件。

若要使用共用磁碟區：

1. 在**建置階段**中，傳遞 `-testProductsPath`（在 `--` 之後）並指向共用磁碟區，同時加入 `--shard-skip-upload` 以略過遠端上傳：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-skip-upload \
  -- \
  -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

2. 在**測試階段**中，傳遞相同的 `-testProductsPath`，讓 Tuist 從本機讀取測試產品，而非下載它們：

```sh
tuist test --without-building -- -testProductsPath /path/to/shared/volume/$UNIQUE_ID/MyScheme.xctestproducts
```

| 旗標 | 環境變數 | 說明 |
|------|---------------------|-------------|
| `--shard-skip-upload` | `TUIST_TEST_SHARD_SKIP_UPLOAD` | 略過將測試產品 bundle 上傳至遠端儲存空間 |

## 自行管理的產物 {#self-managed-artifacts}

若你的 CI 供應商已具備產物上傳與下載步驟，你可以讓 Tuist 處理封存與解壓縮，而由你的 CI 負責傳輸。

1. 在**建置階段**中，傳遞 `--shard-archive-path`，讓 Tuist 將最佳化的分片封存寫入本機，而非上傳測試產品：

```sh
tuist test \
  --build-only \
  --shard-total 5 \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

2. 使用你 CI 的原生產物步驟上傳該封存。

3. 在每個**測試階段**工作中，下載封存並將相同路徑傳回給 Tuist：

```sh
tuist test \
  --without-building \
  --shard-archive-path /tmp/shards/${UNIQUE_ID}/bundle.aar
```

設定 `--shard-archive-path` 時，Tuist 會略過遠端測試產品傳輸，改用本機封存。若你也傳遞 `--shard-skip-upload`，則封存路徑具有優先權。

當沒有測試可執行時（例如因為選擇性測試略過了所有測試目標），建置階段會輸出空的分片矩陣且不會寫入任何封存。僅在矩陣包含分片時才執行上傳步驟。

> [!IMPORTANT]
> 為每次工作流程執行使用唯一路徑（例如包含 CI 執行 ID），以避免同時執行之間的衝突。你也應在完成分片後清理分片封存，以免在執行器上累積過時的資料。

### Namespace {#namespace}

[Namespace](https://namespace.so) 執行器能與 GitHub Actions 產物良好搭配。設定一次 `TUIST_TEST_SHARD_ARCHIVE_PATH`，讓建置工作將分片封存寫入本機、上傳它，並在每個分片工作中於執行 `tuist test` 之前下載它：

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
