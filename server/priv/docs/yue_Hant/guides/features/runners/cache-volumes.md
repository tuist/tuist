---
{
  "title": "快取卷",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "喺 GitHub Actions、Buildkite 同 GitLab CI 嘅 Tuist Linux 或 macOS runner 工作之間，保留 Xcode、模組同 Gradle 快取以及任何其他目錄。"
}
---
# 快取磁碟區 {#cache-volumes}

Tuist runners 可以喺工作之間保留快取，令新 runner 以暖啟動開始。每個工作都會獲得最新已儲存內容嘅私人可寫入副本。

- **受管快取** 會分別用一個步驟保留 Xcode 編譯快取、Tuist 模組快取同 Gradle 快取。Tuist 知道每個快取嘅位置，並將其保存喺自己嘅儲存空間內。
- **自訂磁碟區** 會保留你選擇金鑰下嘅任何其他目錄，例如套件管理器嘅下載快取。

將步驟加喺 checkout 之後、使用快取嘅指令之前。喺非 Tuist runner 上，呢啲步驟唔會做任何事；快取問題亦唔會導致工作失敗：步驟會記錄警告，工作會以空快取繼續。

> [!NOTE]
> macOS 27 上嘅 runner 尚未掛載快取磁碟區或快取 checkout。佢哋嘅快取步驟會記錄警告，工作會以空快取繼續，而 `actions/checkout` 會如常克隆儲存庫。

## 受管快取 {#managed-caches}

呢啲步驟只決定快取嘅存放位置。保留你現有嘅快取設定：`tuist setup cache` 或啟用編譯快取嘅構建設定（參閱 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取指南</.localized_link>）、模組快取嘅認證，以及用於 Gradle 遠端構建快取嘅 <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle 外掛程式</.localized_link>。喺 GitLab CI 中，請將片段同 `!reference` 結合，因為 `extends` 會取代 `before_script`。

### Xcode 快取 {#xcode-cache}

喺 macOS runner 上保留 Xcode 編譯快取嘅儲存。

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

喺 macOS runner 上保留 Tuist 嘅本地快取：<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 二進制檔案、已編譯清單、外掛程式同選擇性測試結果。

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

喺 Linux 同 macOS runner 上保留 Gradle 用戶主目錄中嘅 `caches` 同 `wrapper` 目錄：依賴項、轉換後嘅 jar、已編譯構建腳本同 Gradle 分發版本。如果你使用其中一個，請喺步驟之前設定 `GRADLE_USER_HOME`，並關閉對呢啲目錄嘅其他快取，例如 `actions/setup-java` 上嘅 `cache: gradle`。

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

選擇一個穩定嘅 `key` 同一個 `path`，然後喺安裝依賴項之前掛載磁碟區。路徑必須為空或不存在。移除任何寫入相同目錄嘅歸檔快取或構件還原。要喺一個磁碟區中保留多個目錄，請參閱 [一個磁碟區中嘅多個目錄](#several-directories-in-one-volume)。

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

### 一個磁碟區中嘅多個目錄 {#several-directories-in-one-volume}

一個磁碟區可以容纳多個目錄。喺 GitHub Actions 中，每行列出一個路徑；喺 Buildkite 中，將 `path` 設為列表；喺 GitLab CI 中，每個目錄傳遞一次 `--path`。空白行同周圍空格會被忽略。

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

- **共享容量。** 所有路徑共享磁碟區嘅容量，並一齊還原同儲存。
- **將細小且相關嘅目錄分組。** 為大型或快速變化嘅目錄提供專屬磁碟區。
- **不可嵌套。** 同一磁碟區中嘅路徑唔可以互相包含。
- **更改列表會以冷啟動開始。** 每個路徑都儲存喺磁碟區內自己嘅目錄中，由路徑嘅書寫方式識別。喺單一路徑同多個路徑之間切換，或者新增、刪除或重寫路徑，會改變嗰種佈局：更改後嘅第一個工作會以冷啟動開始處理受影響嘅路徑。不再列出嘅路徑內容會保留喺磁碟區中，直到你刪除佢。

### 金鑰點樣運作 {#how-keys-work}

金鑰命名一個隨時間變化嘅磁碟區；佢唔係好似 `actions/cache` 金鑰嗰樣固定快照嘅名稱。

- **每個金鑰對應一個磁碟區。** 每個金鑰嘅範圍限於儲存庫（喺 Buildkite 上係流水線；喺 GitLab CI 上係專案）、平台、CPU 架構同用戶。每個掛載佢嘅工作都從最新已儲存內容開始，符合條件嘅工作會將更改儲存回同一磁碟區。
- **保持金鑰穩定。** 唔好將版本或鎖定文件哈希放入金鑰。使用 `actions/cache` 時，好似 `deps-${{ hashFiles('Package.resolved') }}` 咁嘅金鑰會為每次更改創建新條目，而 `restore-keys` 會回退到較舊嘅條目。喺度，新金鑰代表一個新嘅空磁碟區：每次更改後嘅第一個工作會以冷啟動開始，舊磁碟區會保留直到過期。保持金鑰不變，讓你嘅工具更新內容；套件管理器會重用仍然有效嘅內容。
- **無部分匹配。** 冇恢復金鑰。尚未儲存嘅金鑰會以空狀態開始。
- **以 `tuist-` 開頭嘅金鑰係保留**畀 Tuist 自己嘅快取，並會喺磁碟區掛載之前被拒絕。
- **有意重新開始。** 當你希望工作以空狀態開始時，更改金鑰或刪除磁碟區。
- **將 `tuist-` 金鑰留畀 Tuist。** 受管快取使用以 `tuist-` 開頭嘅金鑰，所以請為你嘅自訂磁碟區選擇另一個名稱。

喺 Linux 上，路徑會作為普通目錄掛載，因此工具可以使用佢哋通常嘅位置，例如 `deps`、`_build` 同 `node_modules`。保留你正常嘅 `.gitignore` 規則。喺 macOS 上，路徑係符號連結：使用下載快取例如 `~/.npm`；`node_modules` 同替換其快取目錄嘅工具不受支援。喺 `.gitignore` 中忽略冇尾隨斜槓嘅工作區連結。

## 儲存更改 {#saving-changes}

受管快取同自訂磁碟區會儲存來自你自己儲存庫、任何分支上成功工作嘅更改：

| 提供者 | 儲存更改嘅工作 |
| --- | --- |
| GitHub Actions | 來自儲存庫本身嘅推送、排程、手動觸發同拉取請求工作 |
| Buildkite | 流水線儲存庫嘅 Webhook 同排程構建，包括其拉取請求 |
| GitLab CI | 專案嘅推送、排程同網頁流水線，以及當連接擁有 <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API 存取權杖</.localized_link> 時其合併請求嘅流水線 |

其他工作可以使用快取，但佢哋嘅更改會被丟棄。呢啲包括分叉拉取請求、`pull_request_target` 工作、從 API 或儀表板啟動嘅 Buildkite 構建、來自分叉或冇 API 存取權杖嘅 GitLab 合併請求，以及標籤。唔會更改磁碟區嘅工作會保留已儲存版本。你可以縮小喺執行者設定檔上儲存嘅分支範圍；請參閱 [選擇儲存嘅分支](#choose-which-branches-save)。

並行工作獨立運作；唔同工作嘅更改唔會合併。切勿快取憑證或不可替代嘅數據。

### 選擇儲存嘅分支 {#choose-which-branches-save}

你可以更改儲存受管快取同自訂磁碟區嘅分支。打開 **執行者 → 設定檔**，編輯你工作使用嘅設定檔，並展開 **儲存快取來源**。工作使用佢哋請求嘅設定檔：喺 GitHub Actions 上使用 `runs-on:`，喺 Buildkite 上作為隊列，或喺 GitLab CI 上使用 `tags:`。設定適用於該設定檔上工作使用嘅每個磁碟區，包括後來創建嘅磁碟區。

![執行者設定檔表單，展開咗「儲存快取來源」部分，開啟咗「預設分支」並添加咗 develop 同 release/* 作為額外分支](/images/guides/features/runners/save-cache-from.png)

預設情況下，儲存庫中每個成功嘅工作都會儲存其更改。要只從某些分支儲存，請開啟 **限制到特定分支**：

- **預設分支** 允許每個儲存庫預設分支上嘅工作進行儲存。關閉它以僅從額外分支儲存。
- 喺 **額外分支** 下，添加最多 20 個亦會儲存嘅分支名稱。使用 `*` 作為萬用字元：`release/*` 匹配 `release/1.0`。

[儲存更改](#saving-changes) 中列出嘅工作會喺其分支匹配時儲存更改。喺 GitHub Actions 推送同手動觸發運行中，具有匹配名稱嘅標籤亦會匹配。

其他分支上嘅工作仍然可以使用快取，但佢哋嘅更改會被丟棄。從不儲存嘅工作（例如分叉拉取請求）即使喺匹配分支上亦唔會儲存。縮窄呢啲設定或刪除設定檔會丟棄佢哋不再允許嘅待定更改；刪除嘅設定檔會回退到從每個分支儲存。

## 容量同保留 {#capacity-and-retention}

Xcode 快取起始容量為 **30 GB**。模組快取、Gradle 快取同每個自訂磁碟區起始容量為 **20 GB**。設定大小以賦予快取或磁碟區另一容量，即從 `1gb` 到 `100gb` 嘅整數 GB：

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

Gradle 快取同自訂磁碟區接受相同嘅 `size` 輸入（喺 GitLab CI 中為 `TUIST_GRADLE_CACHE_SIZE` 同 `TUIST_VOLUME_SIZE`，喺 `tuist-cache-volume` 中為 `--size`）。較大嘅大小會從下一個工作開始增長磁碟區並保留其內容。較小嘅大小會喺磁碟區下次刪除或過期後應用。當工作請求同一快取嘅唔同大小時，最大嘅大小會生效，因此請喺一處聲明每個大小。

所有快取都係喺 **7 日無工作掛載** 後過期，過期後下一個工作會以空磁碟區開始。Tuist 會修剪 Xcode 同模組快取以適應其容量，而 Gradle 快取步驟會讓 Gradle 喺每次構建後刪除七日未使用嘅條目。

自訂磁碟區唔會修剪舊依賴項：使用你工具嘅清理設定以保持佢哋細小。寫入已满磁碟區可能會導致工作失敗。當已儲存內容達到磁碟區容量嘅 **80%** 且工作喺其上耗盡空間時，下一個工作會以空磁碟區開始，其更改會開始一個新嘅已儲存狀態。

## 檢查同刪除磁碟區 {#inspecting-and-clearing-volumes}

打開 **執行者 → 磁碟區** 以檢查已用空間、快取命中率同工作歷史記錄。Xcode、模組同 Gradle 快取亦會顯示喺嗰度。

帳戶管理員可以選擇 **刪除磁碟區** 以移除磁碟區及其已儲存內容。運行中嘅工作會保留其私有副本但無法將其儲存回去，使用相同金鑰嘅下一個工作會以空磁碟區開始。已刪除嘅磁碟區唔再顯示喺列表中。

要從終端或工作流程刪除磁碟區，請查找其 ID 並傳遞畀 `tuist runner volume delete`：

```bash
tuist runner volume list --account my-org --name gradle-build-cache --json
tuist runner volume delete <volume-id> --account my-org --yes
```

相同操作亦可通過 [API](https://tuist.dev/api/docs#tag/runners) 以 `DELETE /api/accounts/{account_handle}/runners/volumes/{volume_id}` 形式，以及通過 [MCP 伺服器](/guides/features/agentic-coding/mcp) 以 `delete_runner_volume` 形式進行。所有操作都需要帳戶管理權限或具有 `account:runners:write` 範圍嘅權杖。
