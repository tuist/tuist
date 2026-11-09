---
{
  "title": "快取磁碟區",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 GitHub Actions、Buildkite 與 GitLab CI 的 Tuist Linux 或 macOS Runner 工作之間，保留 Xcode、模組與 Gradle 快取以及任何其他目錄。"
}
---
# 快取磁碟區 {#cache-volumes}

Tuist 執行器可以在工作之間保留快取，讓新的執行器以暖啟動開始。每個工作都會取得最新已儲存內容的私有可寫入副本。

- **受管快取**各只需一個步驟即可保留 Xcode 編譯快取、Tuist 模組快取與 Gradle 快取。Tuist 知道每個快取的存放位置，並將其保存在自身的儲存空間中。
- **自訂磁碟區**會在你選擇的金鑰下保留任何其他目錄，例如套件管理器的下載快取。

在 checkout 之後、使用快取的指令之前加入這些步驟。在非 Tuist 執行器上它們不會執行任何動作；快取問題也不會導致工作失敗：該步驟會記錄警告，工作則以空白快取繼續。

## 受管快取 {#managed-caches}

這些步驟只決定快取的存放位置。保留你現有的快取設定：`tuist setup cache` 或啟用編譯快取的建置設定（參閱 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取指南</.localized_link>）、模組快取的認證，以及用於 Gradle 遠端建置快取的 <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle 外掛程式</.localized_link>。在 GitLab CI 中，請將片段與 `!reference` 結合使用，因為 `extends` 會取代 `before_script`。

### Xcode 快取 {#xcode-cache}

在 macOS 執行器上保留 Xcode 編譯快取的儲存。

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

在 macOS 執行器上保留 Tuist 的本機快取：<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link>二進位檔、編譯後的資訊清單、外掛程式與選擇性測試結果。

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

在 Linux 與 macOS 執行器上保留 Gradle 使用者主目錄中的 `caches` 與 `wrapper` 目錄：相依性、轉換過的 jar、編譯後的建置腳本與 Gradle 發行版。若你有使用，請在步驟之前設定 `GRADLE_USER_HOME`，並關閉對這些目錄的其他快取，例如在 `actions/setup-java` 上的 `cache: gradle`。

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

## 自訂磁碟區 {#custom-volumes}

選擇穩定的 `key` 與 `path`，然後在安裝相依性之前掛載磁碟區。路徑必須為空或不存在。移除任何會寫入相同目錄的封存快取或構件還原。若要將多個目錄放在同一個磁碟區中，請參閱 [在同一個磁碟區中使用多個目錄](#several-directories-in-one-volume)。

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

### 在同一個磁碟區中使用多個目錄 {#several-directories-in-one-volume}

一個磁碟區可以容納多個目錄。在 GitHub Actions 中，每行列出一個路徑；在 Buildkite 中，將 `path` 設為清單；在 GitLab CI 中，每個目錄傳遞一次 `--path`。空白行與周圍的空格會被忽略。

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

- **共用容量。** 所有路徑共用磁碟區的容量，並一起還原與儲存。
- **將小型且相關的目錄分組。** 為大型或快速變動的目錄提供專屬磁碟區。
- **禁止巢狀。** 同一磁碟區中的路徑不得彼此包含。
- **變更清單會以冷啟動開始。** 每個路徑會儲存在磁碟區內各自的目錄中，並以路徑的寫法作為識別。在單一與多個路徑之間切換，或新增、移除、改寫路徑，都會改變該配置：變更後的第一個工作會對受影響的路徑以冷啟動開始。不再列出的路徑內容會留在磁碟區中，直到你刪除為止。

### 金鑰運作方式 {#how-keys-work}

金鑰用來命名會隨時間變化的磁碟區；它不是像 `actions/cache` 金鑰那樣的固定快照名稱。

- **每個金鑰對應一個磁碟區。** 每個金鑰的作用範圍限定於儲存庫（在 Buildkite 上為管線；在 GitLab CI 上為專案）、平台、CPU 架構與使用者。每個掛載該金鑰的工作都會從最新已儲存的內容開始，而符合條件的工作會將其變更存回同一個磁碟區。
- **保持金鑰穩定。** 不要在金鑰中放入版本號或鎖定檔案雜湊。使用 `actions/cache` 時，像 `deps-${{ hashFiles('Package.resolved') }}` 這樣的金鑰會為每次變更建立新項目，而 `restore-keys` 會回溯到較舊的項目。在這裡，新金鑰代表一個新的空白磁碟區：每次變更後的第一個工作會以冷啟動開始，舊磁碟區則會保留直到過期。保留金鑰並讓你的工具更新內容；套件管理器會重複使用仍然有效的部分。
- **不支援部分比對。** 沒有還原金鑰。尚未儲存過的金鑰會以空白狀態開始。
- **以 `tuist-` 開頭的金鑰為保留字**，供 Tuist 自身的快取使用，並在掛載磁碟區前被拒絕。
- **刻意重新開始。** 當你希望工作以空白狀態開始時，變更金鑰或刪除磁碟區。
- **將 `tuist-` 金鑰留給 Tuist。** 受管快取使用以 `tuist-` 開頭的金鑰，因此請為你的自訂磁碟區選擇不同的名稱。

在 Linux 上，路徑會以一般目錄的形式掛載，因此工具可以使用其慣用位置，例如 `deps`、`_build` 與 `node_modules`。保留你正常的 `.gitignore` 規則。在 macOS 上，路徑為符號連結：請使用下載快取，例如 `~/.npm`；不支援 `node_modules` 與會替換其快取目錄的工具。在 `.gitignore` 中忽略不含結尾斜線的 workspace 連結。

## 儲存變更 {#saving-changes}

受管快取與自訂磁碟區會儲存來自你自有儲存庫、在任何分支上成功工作的變更：

| 提供者 | 會儲存變更的工作 |
| --- | --- |
| GitHub Actions | 來自儲存庫本身的推送、排程、手動觸發與拉取請求工作 |
| Buildkite | 管線儲存庫的 Webhook 與排程建置，包含其拉取請求 |
| GitLab CI | 專案的推送、排程與網頁管線，以及當連線擁有 <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API 存取權杖</.localized_link> 時，其合併請求的管線 |

其他工作可以使用快取，但其變更會被捨棄。這些包括分叉拉取請求、`pull_request_target` 工作、從 API 或儀表板啟動的 Buildkite 建置、來自分叉或缺少 API 存取權杖的 GitLab 合併請求，以及標籤。未變更磁碟區的工作會保留已儲存的版本。你可以在執行器設定檔中縮小哪些分支會儲存；請參閱 [選擇要儲存的分支](#choose-which-branches-save)。

並行工作獨立運作；不同工作的變更不会合併。切勿快取憑證或無法取代的資料。

### 選擇要儲存的分支 {#choose-which-branches-save}

你可以變更哪些分支會儲存受管快取與自訂磁碟區。開啟 **執行器 → 設定檔**，編輯你的工作所使用的設定檔，並展開 **儲存快取來源**。工作會使用其要求的設定檔：在 GitHub Actions 上為 `runs-on:`，在 Buildkite 上為佇列，或在 GitLab CI 上為 `tags:`。這些設定適用於該設定檔上工作使用的每個磁碟區，包含稍後建立的磁碟區。

![執行器設定檔表單，其中「儲存快取來源」區段已展開，預設分支已啟用，並新增 develop 與 release/* 作為額外分支](/images/guides/features/runners/save-cache-from.png)

預設情況下，儲存庫中每個成功的工作都會儲存其變更。若只從特定分支儲存，請啟用 **限制為特定分支**：

- **預設分支** 允許各儲存庫預設分支上的工作進行儲存。關閉它以僅從額外分支儲存。
- 在 **額外分支** 下方，新增最多 20 個也會儲存的分支名稱。使用 `*` 作為萬用字元：`release/*` 會比對 `release/1.0`。

[儲存變更](#saving-changes) 中列出的工作會在其分支符合時儲存變更。在 GitHub Actions 的推送與手動觸發執行中，名稱相符的標籤也會被視為符合。

其他分支上的工作仍可使用快取，但其變更會被捨棄。從不儲存的工作（例如分叉拉取請求）即使在相符的分支上也不會儲存。縮小這些設定或刪除設定檔會捨棄它們不再允許的暫止變更；刪除設定檔後會恢復為從所有分支儲存。

## 容量與保留 {#capacity-and-retention}

Xcode 快取的起始容量為 **30 GB**。模組快取、Gradle 快取與每個自訂磁碟區的起始容量為 **20 GB**。設定大小以賦予快取或磁碟區不同的容量，範圍為從 `1gb` 到 `100gb` 的整數 GB：

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

Gradle 快取與自訂磁碟區採用相同的 `size` 輸入（在 GitLab CI 中為 `TUIST_GRADLE_CACHE_SIZE` 與 `TUIST_VOLUME_SIZE`，在 `tuist-cache-volume` 中為 `--size`）。較大的大小會從下一個工作開始擴大磁碟區並保留其內容。較小的大小則會在磁碟區下次被刪除或過期後套用。當工作要求同一快取的不同大小時，會套用最大值，因此請在單一位置宣告每個大小。

所有快取與磁碟區在 **7 天無工作掛載** 後會過期，過期後的下一個工作將以空白磁碟區開始。Tuist 會修剪 Xcode 與模組快取以符合其容量，而 Gradle 快取步驟會讓 Gradle 在每次建置後移除七天未使用的項目。

自訂磁碟區不會修剪舊的相依性：請使用你工具的清理設定以保持其小巧。寫入已滿的磁碟區可能導致工作失敗。當已儲存內容達到磁碟區容量的 **80%** 且工作耗盡空間時，下一個工作將以空白磁碟區開始，其變更將開始新的已儲存狀態。

## 檢查與刪除磁碟區 {#inspecting-and-clearing-volumes}

開啟 **執行器 → 磁碟區** 以檢查已使用空間、快取命中率與工作歷史記錄。Xcode、模組與 Gradle 快取也會顯示在此處。

帳戶管理員可以選取 **刪除磁碟區** 以移除磁碟區及其已儲存的內容。執行中的工作會保留其私有副本但無法存回，而使用相同金鑰的下一個工作將以空白磁碟區開始。已刪除的磁碟區不再出現在清單中。

若要從終端機或工作流程刪除磁碟區，請查詢其 ID 並傳遞給 `tuist runner volume delete`：

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

相同的操作可透過 [API](https://tuist.dev/api/docs#tag/runners) 以 `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}` 執行，並透過 [MCP 伺服器](/guides/features/agentic-coding/mcp) 以 `delete_runner_volume` 執行。這些操作都需要帳戶管理權限或具有 `account:runners:write` 範圍的權杖。
