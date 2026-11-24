---
{
  "title": "快取卷宗",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "透過 GitHub Actions、Buildkite 同 GitLab CI，喺 Tuist Linux 或 macOS runner 工作之間保留 Xcode、模組同 Gradle 快取，以及任何其他目錄。"
}
---
# 快取卷 {#cache-volumes}

Tuist runner 可以在工作之間保留快取，令新啟動的 runner 以暖狀態開始。每個工作都會取得最新已儲存內容的私有可寫副本。

- **受管快取**只需各一個步驟即可保留 Xcode 編譯快取、Tuist 模組快取以及 Gradle 快取。Tuist 知道每個快取的存放位置，並在其儲存空間內管理。
- **自訂卷**會在你選擇的金鑰下保留任何其他目錄，例如套件管理器的下載快取。

在 checkout 之後、使用快取的指令之前加入這些步驟。在非 Tuist runner 上它們不會執行任何操作；快取問題亦不會導致工作失敗：步驟會記錄警告，工作則以空快取繼續執行。

## 受管快取 {#managed-caches}

這些步驟只決定快取的存放位置。請保留你現有的快取設定：`tuist setup cache`或啟用編譯快取的構建設定（參閱<.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取指南</.localized_link>）、模組快取的認證，以及用於 Gradle 遠端建構快取的<.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle 外掛程式</.localized_link>。在 GitLab CI 中，請將片段與`!reference`結合，因為`extends`會取代`before_script`。

### Xcode 快取 {#xcode-cache}

在 macOS runner 上保留 Xcode 編譯快取的儲存。

::: code-group

```yaml [GitHub Actions]
jobs:
  build:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/xcode-cache@v1
      - run: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [Buildkite]
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App -destination 'generic/platform=iOS Simulator' COMPILATION_CACHE_ENABLE_CACHING=YES
```
<!-- -->
:::

### 模組快取 {#module-cache}

在 macOS runner 上保留 Tuist 的本機快取：<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>二進位檔、已編譯清單、外掛程式及選擇性測試結果。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-macos
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/module-cache@v1
      - uses: jdx/mise-action@v4
      - run: tuist auth login
      - run: tuist install
      - run: tuist generate --no-open
      - run: tuist test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      mise install
      tuist auth login
      tuist install
      tuist generate --no-open
      tuist test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - mise install
    - tuist auth login
    - tuist install
    - tuist generate --no-open
    - tuist test
```
<!-- -->
:::

### Gradle 快取 {#gradle-cache}

在 Linux 和 macOS runner 上保留 Gradle 使用者主目錄中的`caches`和`wrapper`目錄：包括依賴項、轉換後的 jar、已編譯的建構腳本及 Gradle 發行版。如果你使用自訂路徑，請在步驟之前設定`GRADLE_USER_HOME`，並關閉對這些目錄的其他快取，例如在`actions/setup-java`上的`cache: gradle`。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '21'
      - uses: tuist/gradle-cache@v1
      - run: ./gradlew test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

```yaml [GitLab CI]
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```
<!-- -->
:::

## 自訂卷 {#custom-volumes}

選擇一個穩定的`key`和一個`path`，然後在安裝依賴項之前掛載卷。該路徑必須為空或不存在。移除任何會寫入同一目錄的封存快取或構件還原。若要在一個卷中保留多個目錄，請參閱[一個卷中的多個目錄](#several-directories-in-one-volume)。

::: code-group

```yaml [GitHub Actions]
jobs:
  test:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: npm
          path: ~/.npm
      - run: npm ci
      - run: npm test
```

```yaml [Buildkite]
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: npm
              path: ~/.npm
    command: |
      npm ci
      npm test
```

```yaml [GitLab CI]
test:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key npm --path ~/.npm
  script:
    - npm ci
    - npm test
```
<!-- -->
:::

### 一個卷中的多個目錄 {#several-directories-in-one-volume}

一個卷可以容納多個目錄。在 GitHub Actions 中，每行列出一個路徑；在 Buildkite 中，將`path`設為列表；在 GitLab CI 中，為每個目錄傳遞一次`--path`。空白行及周圍空格會被忽略。

::: code-group

```yaml [GitHub Actions]
jobs:
  lint:
    runs-on: tuist-linux
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/cache-volume@v1
        with:
          key: python-tools
          path: |
            ~/.cache/pip
            ~/.cache/pre-commit
      - run: pip install pre-commit
      - run: pre-commit run --all-files
```

```yaml [Buildkite]
steps:
  - label: Lint
    agents:
      queue: tuist-linux
    plugins:
      - tuist/cache-volume#v1:
          volumes:
            - key: python-tools
              path:
                - ~/.cache/pip
                - ~/.cache/pre-commit
    command: |
      pip install pre-commit
      pre-commit run --all-files
```

```yaml [GitLab CI]
lint:
  tags: [tuist-linux]
  before_script:
    - tuist-cache-volume --key python-tools --path ~/.cache/pip --path ~/.cache/pre-commit
  script:
    - pip install pre-commit
    - pre-commit run --all-files
```
<!-- -->
:::

- **共享容量。** 所有路徑共享卷的容量，並一起還原和儲存。
- **將小型相關目錄分組。** 為大型或快速變化的目錄分配專屬卷。
- **禁止巢狀。** 同一卷中的路徑不得互相包含。
- **更改列表會以冷啟動開始。** 每個路徑都儲存在卷內的獨立目錄中，並由路徑的寫法識別。在單一路徑與多個路徑之間切換，或新增、移除或重寫路徑，都會改變該佈局：變更後的第一個工作會對受影響的路徑以冷啟動開始。不再列出的路徑內容會保留在卷中，直到你刪除為止。

### 金鑰運作方式 {#how-keys-work}

金鑰用於命名會隨時間變化的卷；它並非像`actions/cache`金鑰那樣固定快照的名稱。

- **每個金鑰對應一個卷。** 每個金鑰的作用範圍限定於儲存庫（在 Buildkite 上為流水線；在 GitLab CI 上為專案）、平台、CPU 架構及使用者。每個掛載該金鑰的工作都會從最新已儲存的內容開始，而符合條件的工作會將其變更存回同一卷。
- **保持金鑰穩定。** 不要將版本或鎖定檔案雜湊放入金鑰。使用`actions/cache`時，類似`deps-${{ hashFiles('Package.resolved') }}`的金鑰會為每次變更建立新條目，而`restore-keys`則會回退到較舊的條目。在此處，新金鑰代表一個新的空卷：每次變更後的第一個工作都會以冷啟動開始，舊卷則會保留直至過期。請保持金鑰不變，讓你的工具更新內容；套件管理器會重用仍然有效的部分。
- **沒有部分匹配。** 沒有還原金鑰。尚未儲存過的金鑰會以空狀態開始。
- **以`tuist-`開頭的金鑰已保留**供 Tuist 自身快取使用，並在卷掛載前被拒絕。
- **有意重新開始。** 當你希望工作以空狀態開始時，請更改金鑰或删除卷。
- **將`tuist-`金鑰留給 Tuist。** 受管快取使用以`tuist-`開頭的金鑰，因此請為你的自訂卷選擇其他名稱。

在 Linux 上，路徑會掛載為普通目錄，因此工具可以使用其常見位置，例如`deps`、`_build`和`node_modules`。請保留你正常的`.gitignore`規則。在 macOS 上，路徑為符號連結：請使用下載快取（例如`~/.npm`）；不支援`node_modules`及會替換其快取目錄的工具。在`.gitignore`中忽略沒有尾隨斜線的 workspace 連結。

## 儲存變更 {#saving-changes}

受管快取和自訂卷會儲存來自你自身儲存庫、任何分支上成功工作的變更：

| 提供者 | 儲存變更的工作 |
| --- | --- |
| GitHub Actions | 來自儲存庫本身的推送、排程、手動觸發及拉取請求工作 |
| Buildkite | 流水線儲存庫的 Webhook 及排程建構，包括其拉取請求 |
| GitLab CI | 專案的推送、排程及網頁流水線，以及當連線擁有<.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API 存取權杖</.localized_link>時其合併請求的流水線 |

其他工作可以使用快取，但其變更會被捨棄。這些包括分叉拉取請求、`pull_request_target`工作、從 API 或儀表板啟動的 Buildkite 建構、來自分叉或沒有 API 存取權杖的 GitLab 合併請求，以及標籤。未變更卷的工作會保留已儲存的版本。你可以縮小在執行者設定檔上儲存變更的分支範圍；請參閱[選擇哪些分支儲存](#choose-which-branches-save)。

並行工作獨立運作；不同工作的變更不會合併。切勿快取憑證或不可取代的資料。

### 選擇哪些分支儲存 {#choose-which-branches-save}

你可以更改哪些分支會儲存受管快取和自訂卷。開啟**執行者 → 設定檔**，編輯你的工作所使用的設定檔，並展開**儲存快取來源**。工作會使用其請求的設定檔：在 GitHub Actions 上使用`runs-on:`，在 Buildkite 上作為佇列，或在 GitLab CI 上使用`tags:`。這些設定適用於該設定檔上工作使用的每個卷，包括後續建立的卷。

![執行者設定檔表單，已展開「儲存快取來源」部分，預設分支已開啟，並新增 develop 和 release/* 作為額外分支](/images/guides/features/runners/save-cache-from.png)

預設情況下，儲存庫中每個成功的工作都會儲存其變更。若只想從特定分支儲存，請開啟**限制為特定分支**：

- **預設分支**允許每個儲存庫預設分支上的工作儲存變更。關閉它以僅從額外分支儲存。
- 在**額外分支**下，新增最多 20 個也會儲存的分支名稱。使用`*`作為萬用字元：`release/*`會匹配`release/1.0`。

[儲存變更](#saving-changes)中列出的工作會在分支匹配時儲存其變更。在 GitHub Actions 推送和手動觸發運行中，名稱匹配的標籤也會匹配。

其他分支上的工作仍然可以使用快取，但其變更會被捨棄。從不儲存的工作（例如分叉拉取請求）即使在匹配的分支上也不會儲存。縮小這些設定或刪除設定檔會捨棄它們不再允許的待處理變更；已刪除的設定檔會回復為從所有分支儲存。

## 容量與保留 {#capacity-and-retention}

Xcode 快取的起始容量為**30 GB**。模組快取、Gradle 快取及每個自訂卷的起始容量為**20 GB**。設定大小可賦予快取或卷不同的容量，範圍為從`1gb`到`100gb`的整數 GB：

::: code-group

```yaml [GitHub Actions]
- uses: tuist/xcode-cache@v1
  with:
    size: 50gb
- uses: tuist/module-cache@v1
  with:
    size: 40gb
```

```yaml [Buildkite]
plugins:
  - tuist/xcode-cache#v1:
      size: 50gb
  - tuist/module-cache#v1:
      size: 40gb
```

```yaml [GitLab CI]
build:
  variables:
    TUIST_XCODE_CACHE_SIZE: 50gb
    TUIST_MODULE_CACHE_SIZE: 40gb
```
<!-- -->
:::

Gradle 快取和自訂卷接受相同的`size`輸入（在 GitLab CI 中為`TUIST_GRADLE_CACHE_SIZE`和`TUIST_VOLUME_SIZE`，在`tuist-cache-volume`中為`--size`）。較大的大小會從下一個工作開始擴大卷並保留其內容。較小的大小則在卷下次被刪除或過期後生效。當工作請求同一快取的不同大小時，會套用最大的大小，因此請在單一位置宣告每個大小。

所有快取在**7 天沒有工作掛載**後都會過期，過期後的下一個工作將以空卷開始。Tuist 會修剪 Xcode 和模組快取以符合其容量，而 Gradle 快取步驟會讓 Gradle 在每次建構後移除七天未使用的條目。

自訂卷不會修剪舊的依賴項：請使用你工具的清理設定以保持其小巧。寫入已滿的卷可能會導致工作失敗。當已儲存的內容達到卷容量的**80%** 且工作在其上耗盡空間時，下一個工作將以空卷開始，其變更將開始新的儲存狀態。

## 檢查與刪除卷 {#inspecting-and-clearing-volumes}

開啟**執行者 → 卷**以檢查已用空間、快取命中率和工作歷史記錄。Xcode、模組和 Gradle 快取也會顯示在此處。

帳戶管理員可以選擇**刪除卷**以移除卷及其已儲存的內容。正在運行的工作會保留其私人副本但無法存回，而下一個使用相同金鑰的工作將以空卷開始。已刪除的卷不再出現在列表中。

若要從終端機或工作流程中刪除卷，請查找其 ID 並將其傳遞給`tuist runner volume delete`：

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

相同的操作可透過[API](https://tuist.dev/api/docs#tag/runners)以`DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}`執行，並透過[MCP 伺服器](/guides/features/agentic-coding/mcp)以`delete_runner_volume`執行。所有這些操作都需要帳戶管理權限或具有`account:runners:write`範圍的權杖。
