---
{
  "title": "Cache volumes",
  "titleTemplate": ":title · Runners · Features · Guides · Tuist",
  "description": "Keep the Xcode, module and Gradle caches and any other directory between Tuist Linux or macOS runner jobs with GitHub Actions, Buildkite, and GitLab CI."
}
---
# 快取卷 {#cache-volumes}

Tuist runners 可以在工作之間保留快取，讓全新的 runner 以暖啟動開始。每個工作都會獲得最新已儲存內容的私人可寫入副本。

- **受管快取** 各只需一個步驟即可保留 Xcode 編譯快取、Tuist 的模組快取以及 Gradle 的快取。Tuist 知道每個快取的位置，並將其儲存在自己的儲存空間中。
- **自訂卷** 會在你選擇的金鑰下保留任何其他目錄，例如套件管理器的下載快取。

在 checkout 之後、使用快取的指令之前加入這些步驟。在非 Tuist runners 上，它們不會執行任何動作，而且快取問題永遠不會導致工作失敗：該步驟會記錄警告，工作則會以空白快取繼續執行。

## 受管快取 {#managed-caches}

這些步驟只決定快取的存放位置。請保留你現有的快取設定：`tuist setup cache` 或啟用編譯快取的建構設定（參閱 <.localized_link href="/guides/features/cache/xcode-cache">Xcode 快取指南</.localized_link>）、模組快取的驗證，以及用於 Gradle 遠端建構快取的 <.localized_link href="/guides/features/cache/gradle-cache">Tuist Gradle 外掛程式</.localized_link>。在 GitLab CI 中，請將片段與 `!reference` 結合，因為 `extends` 會取代 `before_script`。

### Xcode 快取 {#xcode-cache}

在 macOS runners 上保留 Xcode 編譯快取的儲存區。

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

在 macOS runners 上保留 Tuist 的本機快取：<.localized_link href="/guides/features/cache/module-cache">模組快取</.localized_link> 二進位檔、已編譯的清單、外掛程式和選擇性測試結果。

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

在 Linux 和 macOS runners 上保留 Gradle 使用者主目錄中的 `caches` 和 `wrapper` 目錄：依賴項、轉換後的 jar 檔、已編譯的建構腳本以及 Gradle 發行版。如果你使用其中一個，請在步驟之前設定 `GRADLE_USER_HOME`，並關閉對那些目錄的其他快取，例如 `actions/setup-java` 上的 `cache: gradle`。

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

選擇一個穩定的 `key` 和 `path`，然後在安裝依賴項之前掛載卷。路徑必須為空或不存在。移除任何會寫入相同目錄的封存快取或構件還原。若要將多個目錄保留在一個卷中，請參閱 [一個卷中的多個目錄](#several-directories-in-one-volume)。

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

一個卷可以容納多個目錄。在 GitHub Actions 中，每行列出一個路徑；在 Buildkite 中，將 `path` 設為清單；在 GitLab CI 中，每個目錄傳遞一次 `--path`。空白行和周圍的空格會被忽略。

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

- **共用容量。** 所有路徑共用卷的容量，並一起還原和儲存。
- **將小型、相關的目錄分組。** 為大型或快速變更的目錄提供專屬卷。
- **不允許巢狀。** 同一卷中的路徑不得互相包含。
- **變更清單會以冷啟動開始。** 每個路徑都儲存在卷內的專屬目錄中，並由路徑的寫法識別。在單一路徑與多個路徑之間切換，或新增、移除或重寫路徑，會改變該佈局：變更後的第一個工作會對受影響的路徑以冷啟動開始。不再列出的路徑內容會保留在卷中，直到你清除為止。

### 金鑰運作方式 {#how-keys-work}

金鑰用來命名會隨時間變更的卷；它不是像 `actions/cache` 金鑰那樣的固定快照名稱。

- **每個金鑰對應一個卷。** 每個金鑰的作用範圍限定於儲存庫（在 Buildkite 上為 pipeline；在 GitLab CI 上為專案）、平台、CPU 架構和使用者。每個附加該金鑰的工作都會從最新已儲存的內容開始，而符合資格的工作會將其變更存回同一個卷。
- **保持金鑰穩定。** 不要在金鑰中加入版本或鎖定檔雜湊。使用 `actions/cache` 時，像 `deps-${{ hashFiles('Package.resolved') }}` 這樣的金鑰會為每次變更建立新項目，而 `restore-keys` 會回退到較舊的項目。在這裡，新金鑰代表新的空白卷：每次變更後的第一個工作會以冷啟動開始，舊卷會保留直到過期。請保留金鑰，讓你的工具更新內容；套件管理器會重複使用仍然有效的部分。
- **沒有部分相符。** 沒有還原金鑰。尚未儲存的金鑰會以空白狀態開始。
- **刻意重新開始。** 當你希望工作以空白狀態開始時，請變更金鑰，或在儀表板中清除卷。
- **將 `tuist-` 金鑰留給 Tuist。** 受管快取使用的金鑰以 `tuist-` 開頭，因此請為你的自訂卷選擇不同的名稱。

在 Linux 上，路徑會掛載為一般目錄，因此工具可以使用其慣用位置，例如 `deps`、`_build` 和 `node_modules`。請保留你正常的 `.gitignore` 規則。在 macOS 上，路徑是符號連結：請使用下載快取，例如 `~/.npm`；`node_modules` 以及會替換其快取目錄的工具不受支援。在 `.gitignore` 中忽略沒有尾隨斜線的 workspace 連結。

## 儲存變更 {#saving-changes}

受管快取和自訂卷會儲存來自你自身儲存庫的成功工作變更，適用於任何分支：

| 提供者 | 儲存變更的工作 |
| --- | --- |
| GitHub Actions | 來自儲存庫本身的推送、排程、手動觸發和拉取請求工作 |
| Buildkite | Pipeline 儲存庫的 Webhook 和排程建構，包括其拉取請求 |
| GitLab CI | 專案的推送、排程和網頁 pipeline，以及當連線擁有 <.localized_link href="/guides/features/runners/ci-providers/gitlab-ci#merge-request-pipelines">API 存取權杖</.localized_link> 時，其自身合併請求的 pipeline |

其他工作可以使用快取，但其變更會被捨棄。這些包括分支拉取請求、`pull_request_target` 工作、從 API 或儀表板啟動的 Buildkite 建構、來自分支或沒有 API 存取權杖的 GitLab 合併請求，以及標籤。不會變更卷的工作會保留已儲存的版本。你可以在 runner 設定檔中縮小哪些分支會儲存；請參閱 [選擇哪些分支儲存](#choose-which-branches-save)。

並行工作獨立運作；不同工作的變更不會合併。切勿快取憑證或不可替代的資料。

### 選擇哪些分支儲存 {#choose-which-branches-save}

你可以變更哪些分支會儲存受管快取和自訂卷。開啟 **Runners → Profiles**，編輯你的工作使用的設定檔，並展開 **Save cache from**。工作會使用它們請求的設定檔：在 GitHub Actions 的 `runs-on:` 中、在 Buildkite 上作為 queue，或在 GitLab CI 的 `tags:` 中。這些設定適用於該設定檔上工作使用的每個卷，包括稍後建立的卷。

![Runner 設定檔表單，已展開 Save cache from 區段，Default branch 已開啟，並新增 develop 和 release/* 作為額外分支](/images/guides/features/runners/save-cache-from.png)

預設情況下，儲存庫中的每個成功工作都會儲存其變更。若只從某些分支儲存，請開啟 **Limit to specific branches**：

- **Default branch** 允許每個儲存庫的預設分支上的工作進行儲存。關閉它以僅從額外分支儲存。
- 在 **Additional branches** 下，新增最多 20 個也會儲存的分支名稱。使用 `*` 作為萬用字元：`release/*` 會匹配 `release/1.0`。

[Saving changes](#saving-changes) 中列出的工作會在分支匹配時儲存其變更。在 GitHub Actions 推送和手動觸發執行中，具有匹配名稱的標籤也會匹配。

其他分支上的工作仍然可以使用快取，但其變更會被捨棄。從不儲存的工作（例如分支拉取請求）即使在匹配的分支上也不會儲存。縮小這些設定或刪除設定檔會捨棄它們不再允許的待處理變更；已刪除的設定檔會回退為從每個分支儲存。

## 容量與保留 {#capacity-and-retention}

Xcode 快取起始容量為 **30 GB**。模組快取、Gradle 快取和每個自訂卷起始容量為 **20 GB**。設定大小以賦予快取或卷不同的容量，範圍為從 `1gb` 到 `100gb` 的整數 GB：

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

Gradle 快取和自訂卷接受相同的 `size` 輸入（GitLab CI 中的 `TUIST_GRADLE_CACHE_SIZE` 和 `TUIST_VOLUME_SIZE`，`tuist-cache-volume` 的 `--size`）。較大的大小會從下一個工作開始擴大卷並保留其內容。較小的大小會在下次清除卷或過期後套用。當工作請求同一快取的不同大小時，會套用最大的大小，因此請在單一位置宣告每個大小。

所有快取在 **7 天沒有工作掛載** 後過期，過期後的下一個工作會以空白卷開始。Tuist 會修剪 Xcode 和模組快取以符合其容量，而 Gradle 快取步驟會讓 Gradle 在每次建構後移除七天未使用的項目。

自訂卷不會修剪舊依賴項：請使用你工具的清理設定以保持其小巧。寫入已满的卷可能會導致工作失敗。當已儲存的內容達到卷容量的 **80%** 且工作耗盡空間時，下一個工作會以空白卷開始，其變更會開始新的已儲存狀態。

## 檢查和清除卷 {#inspecting-and-clearing-volumes}

開啟 **Runners → Volumes** 以檢查已用空間、快取命中率和工作歷史記錄。帳戶管理員可以選擇 **Clear volume** 以使未來的工作以空白狀態開始。執行中的工作會保留其私人副本，但無法將其存回。Xcode 和模組快取也會顯示在那裡，但無法清除。
