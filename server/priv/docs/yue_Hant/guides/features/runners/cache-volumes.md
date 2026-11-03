---
{
  "title": "快取卷",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "喺 GitHub Actions、Buildkite 同 GitLab CI 嘅 Tuist Linux 或 macOS runner 工作之間，保留 Xcode、模組同 Gradle 快取以及其他目錄。"
}
---
# 快取卷 {#cache-volumes}

Tuist runner 可以在工作之間保留快取，令新啟動的 runner 以暖狀態開始。每個工作都會獲得最新已儲存內容的私人可寫入副本。

- **受管快取**會分別以一個步驟保留 Xcode 編譯快取、Tuist 的模組快取同 Gradle 的快取。Tuist 知道每個快取的存放位置，並將其儲存在自己的儲存空間內。
- **自訂卷**會保留你選擇的金鑰下的任何其他目錄，例如套件管理器的下載快取。

將這些步驟加在 checkout 之後、使用快取的指令之前。喺非 Tuist runner 上，它們不會做任何事；快取問題亦唔會導致工作失敗：步驟會記錄警告，工作會以空快取繼續執行。

## 受管快取 {#managed-caches}

呢啲步驟只決定快取的存放位置。保留你現有的快取設定：`tuist setup cache` 或啟用編譯快取的構建設定（參閱 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取指南</.localized_link>）、模組快取的認證，以及用於 Gradle 遠端構建快取的 <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle 插件</.localized_link>。喺 GitLab CI 中，用 `!reference` 組合片段，因為 `extends` 會取代 `before_script`。

### Xcode 快取 {#xcode-cache}

喺 macOS runner 上保留 Xcode 編譯快取的儲存。

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

喺 macOS runner 上保留 Tuist 的本機快取：<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>二進制檔、已編譯的清單、插件同選擇性測試結果。

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

喺 Linux 同 macOS runner 上保留 Gradle 用戶主目錄中的 `caches` 同 `wrapper` 目錄：依賴項、轉換過的 jar、已編譯的構建腳本同 Gradle 分發版。如果你有用到，請喺步驟之前設定 `GRADLE_USER_HOME`，並關閉對呢啲目錄的其他快取，例如 `actions/setup-java` 上的 `cache: gradle`。

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

選擇一個穩定的 `key` 同 `path`，然後喺安裝依賴項之前掛載卷。路徑必須為空或不存在。移除任何會寫入同一目錄的歸檔快取或構件還原。要喺一個卷中保留多個目錄，請參閱 [一個卷中的多個目錄](#several-directories-in-one-volume)。

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

一個卷可以容納多個目錄。喺 GitHub Actions 中，每行列出一個路徑；喺 Buildkite 中，將 `path` 設為列表；喺 GitLab CI 中，每個目錄傳遞一次 `--path`。空白行同周圍的空格會被忽略。

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

- **共享容量。** 所有路徑共享卷的容量，並一齊還原同儲存。
- **將細小、相關的目錄分組。** 為大型或快速變化的目錄分配專屬卷。
- **不允許嵌套。** 同一卷中的路徑不得互相包含。
- **更改列表會以冷狀態開始。** 每個路徑都儲存喺卷內的專屬目錄中，由路徑的寫法識別。喺單一路徑同多個路徑之間切換，或者新增、刪除或重寫路徑，會改變該佈局：更改後的第一個工作會以冷狀態開始處理受影響的路徑。不再列出的路徑內容會保留喺卷中，直到你清除為止。

### 金鑰如何運作 {#how-keys-work}

金鑰命名一個隨時間變化的卷；它唔係像 `actions/cache` 金鑰嗰樣固定快照的名稱。

- **每個金鑰對應一個卷。** 每個金鑰的作用範圍限於儲存庫（喺 Buildkite 上為流水線；喺 GitLab CI 上為項目）、平台、CPU 架構同用戶。每個掛載它的工作都從最新已儲存的內容開始，符合条件的工作會將更改儲存回同一卷。
- **保持金鑰穩定。** 唔好將版本或鎖定文件哈希放入金鑰。使用 `actions/cache` 時，類似 `deps-${{ hashFiles('Package.resolved') }}` 的金鑰會為每次更改建立新條目，而 `restore-keys` 會回退到較舊的條目。喺度，新金鑰代表一個新的空卷：每次更改後的第一個工作會以冷狀態開始，舊卷會保留直到過期。保持金鑰不變，讓你的工具更新內容；套件管理器會重用仍然有效的部分。
- **沒有部分匹配。** 沒有還原金鑰。尚未儲存的金鑰會以空狀態開始。
- **以 `tuist-` 開頭的金鑰已預留**給 Tuist 自身的快取，並會喺卷掛載之前被拒絕。
- **有意重新開始。** 當你希望工作以空狀態開始時，更改金鑰或喺儀表板中清除卷。
- **將 `tuist-` 金鑰留給 Tuist。** 受管快取使用以 `tuist-` 開頭的金鑰，因此請為你的自訂卷選擇其他名稱。

喺 Linux 上，路徑會作為普通目錄掛載，因此工具可以使用其常見位置，例如 `deps`、`_build` 同 `node_modules`。保留你正常的 `.gitignore` 規則。喺 macOS 上，路徑係符號連結：使用下載快取例如 `~/.npm`；`node_modules` 同替換其快取目錄的工具不受支援。喺 `.gitignore` 中忽略沒有尾部斜槓的工作區連結。

## 儲存更改 {#saving-changes}

受管快取同自訂卷會儲存來自你自身儲存庫的成功工作的更改，適用於任何分支：

| 提供者 | 儲存更改的工作 |
| --- | --- |
| GitHub Actions | 來自儲存庫本身的推送、排程、手動觸發同拉取請求工作 |
| Buildkite | 流水線儲存庫的 Webhook 同排程構建，包括其拉取請求 |
| GitLab CI | 項目的推送、排程同網頁流水線，以及當連線擁有 <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API 存取權杖</.localized_link> 時其合併請求的流水線 |

其他工作可以使用快取，但其更改會被丟棄。這些包括分支拉取請求、`pull_request_target` 工作、從 API 或儀表板啟動的 Buildkite 構建、來自分支或沒有 API 存取權杖的 GitLab 合併請求，以及標籤。不更改卷的工作會保留已儲存的版本。你可以縮小在執行者配置檔上儲存的分支範圍；參見 [選擇哪些分支儲存](#choose-which-branches-save)。

並行工作獨立運作；不同工作的更改不會合併。切勿快取憑證或不可替代的數據。

### 選擇哪些分支儲存 {#choose-which-branches-save}

你可以更改哪些分支儲存受管快取同自訂卷。打開 **執行者 → 配置檔**，編輯你的工作使用的配置檔，並展開 **儲存快取來源**。工作使用它們請求的配置檔：喺 GitHub Actions 上使用 `runs-on:`，喺 Buildkite 上作為佇列，或喺 GitLab CI 上使用 `tags:`。設定適用於該配置檔上工作使用的每個卷，包括後來建立的卷。

![執行者配置檔表單，展開了「儲存快取來源」部分，開啟了預設分支，並添加了 develop 同 release/* 作為額外分支](/images/guides/features/runners/save-cache-from.png)

預設情況下，儲存庫中每個成功的工作都會儲存其更改。要僅從某些分支儲存，請開啟 **限制為特定分支**：

- **預設分支** 允許每個儲存庫預設分支上的工作儲存。關閉它以僅從額外分支儲存。
- 喺 **額外分支** 下，添加最多 20 個也會儲存的分支名稱。使用 `*` 作為萬用字元：`release/*` 匹配 `release/1.0`。

[儲存更改](#saving-changes) 中列出的工作會喺其分支匹配時儲存更改。喺 GitHub Actions 推送同手動觸發運行中，具有匹配名稱的標籤也會匹配。

其他分支上的工作仍然可以使用快取，但其更改會被丟棄。從不儲存的工作（例如分支拉取請求）即使喺匹配的分支上也不會儲存。縮小這些設定或刪除配置檔會丟棄它們不再允許的待處理更改；刪除的配置檔會回退到從每個分支儲存。

## 容量同保留 {#capacity-and-retention}

Xcode 快取起始容量為 **30 GB**。模組快取、Gradle 快取同每個自訂卷起始容量為 **20 GB**。設定大小以賦予快取或卷其他容量，範圍為 `1gb` 至 `100gb` 的整數 GB：

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

Gradle 快取同自訂卷接受相同的 `size` 輸入（GitLab CI 中的 `TUIST_GRADLE_CACHE_SIZE` 同 `TUIST_VOLUME_SIZE`，`tuist-cache-volume` 的 `--size`）。較大的大小會從下一個工作開始擴大卷並保留其內容。較小的大小會喺下次清除卷或過期後應用。當工作請求同一快取的不同大小時，會應用最大的大小，因此請喺一處聲明每個大小。

所有這些都會喺 **7 天沒有工作掛載** 後過期，過期後下一個工作會以空卷開始。Tuist 會修剪 Xcode 同模組快取以適應其容量，而 Gradle 快取步驟會讓 Gradle 喺每次構建後移除七天未使用的條目。

自訂卷不會修剪舊依賴項：使用你的工具的清理設定以保持它們小巧。寫入滿載的卷可能會導致工作失敗。當已儲存的內容達到卷容量的 **80%** 且工作耗盡空間時，下一個工作會以空卷開始，其更改會開始一個新的儲存狀態。

## 檢查同清除卷 {#inspecting-and-clearing-volumes}

打開 **執行者 → 卷** 以檢查已用空間、快取命中率同工作歷史記錄。帳戶管理員可以選擇 **清除卷** 以使未來的工作以空狀態開始。運行中的工作會保留其私有副本但無法將其儲存回去。Xcode 同模組快取也會顯示喺度，但無法清除。
