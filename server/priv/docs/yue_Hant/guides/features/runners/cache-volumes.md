---
{
  "title": "快取卷宗",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "透過 GitHub Actions、Buildkite 同 GitLab CI，喺 Tuist Linux 或 macOS runner 工作之間保留 Xcode、模組同 Gradle 快取，以及任何其他目錄。"
}
---
# 快取卷 {#cache-volumes}

Tuist runner 可以喺工作之間保留快取，令到新嘅 runner 一開機就係暖狀態。每個工作都會獲得最新儲存內容嘅私人可寫副本。

- **受管快取** 只需各一個步驟，就可以保留 Xcode 編譯快取、Tuist 模組快取同 Gradle 快取。Tuist 知道每個快取嘅位置，並將其保存喺自己嘅儲存空間內。
- **自訂卷** 可以保留任何其他目錄（例如套件管理器嘅下載快取），並由你選擇嘅金鑰識別。

請將呢啲步驟加喺 checkout 之後、使用快取嘅指令之前。如果 runner 唔係 Tuist runner，呢啲步驟唔會執行任何動作；快取問題亦唔會導致工作失敗：步驟只會記錄警告，工作會繼續以空快取執行。

## 受管快取 {#managed-caches}

呢啲步驟只決定快存放喺邊。請保留你現有嘅快取設定：`tuist setup cache` 或啟用編譯快取嘅構建設定（參閱 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取指南</.localized_link>）、模組快取嘅認證，以及用於 Gradle 遠端構建快取嘅 <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle 外掛程式</.localized_link>。喺 GitLab CI 中，請使用 `!reference` 組合片段，因為 `extends` 會取代 `before_script`。

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

喺 macOS runner 上保留 Tuist 嘅本機快取：<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 二進制檔、已編譯嘅 manifest、外掛程式同選擇性測試結果。

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

喺 Linux 同 macOS runner 上，保留 Gradle 使用者主目錄中嘅 `caches` 同 `wrapper` 目錄：包括依賴項、轉換後嘅 jar 檔、已編譯嘅構建腳本同 Gradle 分發版本。如果你有用到，請喺步驟之前設定 `GRADLE_USER_HOME`，並關閉對呢啲目錄嘅其他快取功能，例如 `cache: gradle` 喺 `actions/setup-java` 上嘅設定。

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

選擇一個穩定嘅 `key` 同 `path`，然後喺安裝依賴項之前掛載卷。路徑必須為空或不存在。移除任何會寫入同一目錄嘅歸檔快取或構件還原。如果要喺一個卷中保留多個目錄，請參閱 [一個卷中嘅多個目錄](#several-directories-in-one-volume)。

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

### 一個卷中嘅多個目錄 {#several-directories-in-one-volume}

一個卷可以容納多個目錄。喺 GitHub Actions 中，每行列出一個路徑；喺 Buildkite 中，將 `path` 設定為清單；喺 GitLab CI 中，每個目錄傳遞一次 `--path`。空白行同周圍嘅空白字符會被忽略。

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

- **共享容量。** 所有路徑共享卷嘅容量，並一齊還原同儲存。
- **將細小且相關嘅目錄分組。** 對於大型或快速變化嘅目錄，請給予其獨立嘅卷。
- **不允許嵌套。** 同一卷中嘅路徑唔可以互相包含。
- **更改清單會導致冷啟動。** 每個路徑都儲存喺卷內嘅獨立目錄中，並根據路徑嘅寫法來識別。切換單一或多個路徑，或者新增、刪除或重寫路徑，都會改變該佈局：更改後嘅第一個工作會對受影響嘅路徑進行冷啟動。不再列出嘅路徑內容會保留喺卷中，直到你清除為止。

### 金鑰如何運作 {#how-keys-work}

金鑰命名一個會隨時間變化嘅卷；佢唔係好像 `actions/cache` 金鑰嗰樣固定快照嘅名稱。

- **每個金鑰對應一個卷。** 每個金鑰嘅範圍限定於儲存庫（喺 Buildkite 上係 pipeline；喺 GitLab CI 上係專案）、平台、CPU 架構同使用者。每個掛載咗佢嘅工作都會從最新儲存嘅內容開始，而符合資格嘅工作會將更改儲存返去同一個卷。
- **保持金鑰穩定。** 唔好將版本或鎖定文件雜湊放入金鑰中。使用 `actions/cache` 時，好似 `deps-${{ hashFiles('Package.resolved') }}` 咁嘅金鑰會為每次更改建立新條目，而 `restore-keys` 則會回退到較舊嘅條目。喺度，新金鑰代表一個新嘅空卷：每次更改後嘅第一個工作都會冷啟動，舊卷會保留直到過期。請保持金鑰不變，讓你嘅工具更新內容；套件管理器會重用仍然有效嘅部分。
- **無部分匹配。** 無還原金鑰。尚未儲存嘅金鑰會以空狀態開始。
- **有意重新開始。** 當你希望工作以空狀態開始時，請更改金鑰，或喺儀表板中清除卷。
- **將 `tuist-` 金鑰留畀 Tuist。** 受管快取使用以 `tuist-` 開頭嘅金鑰，所以請為你嘅自訂卷選擇其他名稱。

喺 Linux 上，路徑會掛載為普通目錄，因此工具可以使用佢哋慣常嘅位置，例如 `deps`、`_build` 同 `node_modules`。請保留你正常嘅 `.gitignore` 規則。喺 macOS 上，路徑係符號連結：請使用下載快取（例如 `~/.npm`）；`node_modules` 同替換其快取目錄嘅工具不受支援。喺 `.gitignore` 中忽略無尾隨斜線嘅工作區連結。

## 儲存更改 {#saving-changes}

受管快取同自訂卷會儲存來自你自己儲存庫中成功工作嘅更改，適用於任何分支：

| 提供者 | 儲存更改嘅工作 |
| --- | --- |
| GitHub Actions | 來自儲存庫本身嘅推送、排程、手動觸發同拉取請求工作 |
| Buildkite | Pipeline 儲存庫嘅 Webhook 同排程構建，包括其拉取請求 |
| GitLab CI | 專案嘅推送、排程同網頁 pipeline，以及當連線擁有 <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API 存取權杖</.localized_link> 時，其合併請求嘅 pipeline |

其他工作可以使用快取，但佢哋嘅更改會被丟棄。呢啲包括分叉拉取請求、`pull_request_target` 工作、從 API 或儀表板啟動嘅 Buildkite 構建、來自分叉或無 API 存取權杖嘅 GitLab 合併請求，以及標籤。無更改卷嘅工作會保留已儲存嘅版本。你可以喺執行者設定檔中縮小儲存更改嘅分支範圍；請參閱 [選擇儲存更改嘅分支](#choose-which-branches-save)。

並行工作獨立運作；唔同工作嘅更改唔會合併。切勿快取憑證或無法取代嘅資料。

### 選擇儲存更改嘅分支 {#choose-which-branches-save}

你可以更改儲存受管快取同自訂卷嘅分支。開啟 **執行者 → 設定檔**，編輯你工作使用嘅設定檔，並展開 **儲存快取來源**。工作會使用佢哋請求嘅設定檔：喺 GitHub Actions 上係 `runs-on:`，喺 Buildkite 上係佇列，或者喺 GitLab CI 上係 `tags:`。設定適用於該設定檔上工作使用嘅每個卷，包括之後建立嘅卷。

![執行者設定檔表單，展開咗「儲存快取來源」部分，啟用咗「預設分支」，並添加咗 develop 同 release/* 作為額外分支](/images/guides/features/runners/save-cache-from.png)

預設情況下，儲存庫中每個成功嘅工作都會儲存其更改。要只從某些分支儲存，請啟用 **限制為特定分支**：

- **預設分支** 允許每個儲存庫預設分支上嘅工作儲存更改。關閉它以僅從額外分支儲存。
- 喺 **額外分支** 下，添加最多 20 個亦會儲存嘅分支名稱。使用 `*` 作為萬用字元：`release/*` 會匹配 `release/1.0`。

[儲存更改](#saving-changes) 中列出嘅工作會喺其分支匹配時儲存更改。喺 GitHub Actions 推送同手動觸發運行中，具有匹配名稱嘅標籤亦會匹配。

其他分支上嘅工作仍然可以使用快取，但佢哋嘅更改會被丟棄。永遠唔會儲存嘅工作（例如分叉拉取請求）即使喺匹配分支上亦唔會儲存。縮窄呢啲設定或刪除設定檔會丟棄佢哋不再允許嘅待定更改；刪除嘅設定檔會回退到從每個分支儲存。

## 容量同保留 {#capacity-and-retention}

Xcode 快取起始容量為 **30 GB**。模組快取、Gradle 快取同每個自訂卷起始容量為 **20 GB**。設定大小以賦予快取或卷其他容量，範圍為從 `1gb` 到 `100gb` 嘅 GB 整數：

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

Gradle 快取同自訂卷接受相同嘅 `size` 輸入（喺 GitLab CI 中為 `TUIST_GRADLE_CACHE_SIZE` 同 `TUIST_VOLUME_SIZE`，喺 `tuist-cache-volume` 中為 `--size`）。較大嘅大小會從下一個工作開始擴大卷並保留其內容。較小嘅大小會喺卷下次清除或過期後生效。當工作請求同一快取嘅唔同大小時，會應用最大嘅大小，因此請喺一處聲明每個大小。

所有快取喺 **7 日無工作掛載** 後過期，過期後下一個工作會以空卷開始。Tuist 會修剪 Xcode 同模組快取以適應其容量，而 Gradle 快取步驟會讓 Gradle 喺每次構建後移除七日未使用嘅條目。

自訂卷唔會修剪舊依賴項：請使用你工具嘅清理設定以保持佢哋細小。寫入已满嘅卷可能會導致工作失敗。當儲存內容達到卷容量嘅 **80%** 且工作喺其上用完空間時，下一個工作會以空卷開始，其更改會開始一個新嘅儲存狀態。

## 檢查同清除卷 {#inspecting-and-clearing-volumes}

開啟 **執行者 → 卷** 以檢查已使用空間、快取命中率同工作歷史記錄。帳戶管理員可以選擇 **清除卷** 以使未來工作以空狀態開始。運行中嘅工作會保留其私有副本，但無法將佢哋儲存回去。Xcode 同模組快取亦會顯示喺度，但無法清除。
