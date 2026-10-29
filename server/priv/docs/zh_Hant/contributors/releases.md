---
{
  "title": "版本發布",
  "titleTemplate": ":title | 貢獻者 | Tuist",
  "description": "了解 Tuist 的持續發布流程如何運作"
}
---
# 版本發布

當變更合併至主分支時，Tuist 會自動發布新版本。CLI、伺服器與 Kura 快取伺服器皆透過發布管道（canary、候選版本、穩定版）交付，確保建議安裝版本保持穩定且更新節奏較慢；切割候選版本並將其提升為穩定版是每週刻意執行的步驟。應用程式持續發布（iOS 應用程式僅持續部署至 TestFlight，詳情請見[此處](#app-store-release)）。

## 概覽

我們發布以下主要元件：
- **Tuist CLI** - 命令列工具，透過 canary、候選版本與穩定版[管道](#release-channels)交付
- **Tuist Server** - 後端服務，採用與 CLI 相同的管道模型交付
- **Kura** - 快取伺服器，採用與 CLI 相同的管道模型交付
- **Tuist App** - macOS 與 iOS 應用程式，持續發布（iOS 應用程式僅持續部署至 TestFlight，詳情請見[此處](#app-store-release)）

每次推送到 `main` 都會為 CLI、伺服器與 Kura 發布 canary 預發布版本。這些元件的穩定版本僅在維護者將經過充分驗證的候選版本提升時才會切割，而每週排程會同步觸發這三條發布列車（參閱[發布管道](#release-channels)）。應用程式會在每次推送到 `main` 時發布穩定版。

## 運作方式

### 1. 提交訊息規範

我們使用[Conventional Commits](https://www.conventionalcommits.org/)來組織提交訊息。這讓我們的工具能夠理解變更性質、決定版本升級，並產生適當的變更紀錄。

格式：`type(scope): description`

#### 提交類型及其影響

| 類型 | 說明 | 版本影響 | 範例 |
|------|-------------|----------------|---------|
| `feat` | 新功能或能力 | 次要版本升級（x.Y.z） | `feat(cli): add support for Swift 6` |
| `fix` | 錯誤修復 | 修補版本升級（x.y.Z） | `fix(app): resolve crash when opening projects` |
| `docs` | 文件變更 | 不發布 | `docs: update installation guide` |
| `style` | 程式碼風格變更 | 不發布 | `style: format code with swiftformat` |
| `refactor` | 程式碼重構 | 不發布 | `refactor(server): simplify auth logic` |
| `perf` | 效能改進 | 修補版本升級 | `perf(cli): optimize dependency resolution` |
| `test` | 測試新增/變更 | 不發布 | `test: add unit tests for cache` |
| `chore` | 維護任務 | 不發布 | `chore: update dependencies` |
| `ci` | CI/CD 變更 | 不發布 | `ci: add workflow for releases` |

對 CLI 而言，這些升級決定了 canary 版本與變更紀錄的分組。穩定的 CLI 版本為手動切割的次要版本線（`X.Y.0`），而穩定修補版本（`X.Y.Z`）僅來自回溯移植，因此`feat`或`fix`會透過下方的管道流程觸達 CLI 使用者，而非立即作為穩定版發布。

#### 破壞性變更

破壞性變更會觸發主要版本升級（X.0.0），並應在提交訊息內文中標示：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 變更偵測

每個元件都使用 [git cliff](https://git-cliff.org/) 來：
- 分析自上次發布以來的提交
- 依範圍過濾提交（cli、app、server）
- 判斷是否有可發布的變更
- 自動產生變更紀錄

### 3. 發布流程

當偵測到可發布的變更時：

1. **版本計算**：流程決定下一個版本號
2. **變更紀錄產生**：git cliff 根據提交訊息建立變更紀錄
3. **建置流程**：建置並測試元件
4. **產物產生**：產生發布專屬資產，例如 CLI 套件、檢查碼，以及由 `tuist --experimental-dump-help` 產生的 `tuist.spec.json` CLI 規格
5. **建立發布**：建立包含產物的 GitHub 發布
6. **分發**：將更新推送至套件管理器（例如 CLI 的 Homebrew）

對應用程式而言，這會在每次合併時產生穩定版。對 CLI、伺服器與 Kura 而言，同樣的自動化流程僅產生 **canary** 預發布版本；候選版本與穩定版本則在每週發布列車上切割（參閱[發布管道](#release-channels)）。

### 4. 範圍過濾

每個元件僅在有相關變更時才會發布：

- **CLI**：帶有 `(cli)` 範圍或無範圍的提交
- **App**：帶有 `(app)` 範圍的提交
- **Server**：帶有 `(server)` 範圍的提交

## 發布管道

CLI、伺服器與 Kura 不會在每次推送到 `main` 時都提升為穩定版。每個元件都透過三個管道交付，讓推薦安裝保持穩定且變動緩慢，同時讓早期採用者保留每次提交的建置版本。使用者可見的文件位於 <.localized_link href="/cli/release-channels">CLI 發布管道</.localized_link> 與 <.localized_link href="/guides/server/self-host/release-channels">Server 發布管道</.localized_link>；本節為維護者操作手冊。

每個元件都使用相同的三個管道：

| 管道 | 版本 | 切割方式 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動執行，在每次影響元件的推送到 `main` 時（`<component>-release.yml`；對 Kura 而言，當 `kura/` 變更時由 `server-production-deployment.yml` 呼叫） |
| 候選版本 | `X.Y.0-rc.N` | 每週一，或手動在 `releases/<component>-<major>.<minor>.x` 分支上（`<component>-rc.yml`） |
| 穩定版 | `X.Y.Z` | 每週一，或手動提升經過充分驗證的候選版本（`<component>-promote.yml`）；修補版本透過 `<component>-backport.yml` |

Canary 與 RC 建置會以 GitHub 預發布形式發布（從不標記為「Latest」，從不在 GHCR 上移動 `:latest`，從不將 CLI 推送至 Homebrew），因此套件管理器與映像解析器僅在明確選擇加入時才會採用。Canary 始終鎖定下一個未發布的次要版本：一旦切割出 RC 線，`main` 的 canary 就會推進至下一個次要版本。

託管式 Tuist 不會等待穩定列車：伺服器會依每次提交部署，而託管式 canary 與生產環境會執行最新的 Kura canary。部署串流會在部署前自行發布該 canary，因此 `kura-release.yml` 沒有自己的觸發條件。僅變更 Kura 發布工具（`mise/tasks/kura/**`、`kura-*.yml` 工作流程）不會切割 canary。

你從不手動挑選版本號。每個管道的下一個版本都由 `mise/tasks/<component>/release/channel-version.sh` 從現有的 git 標籤衍生而來，下方的工作流程會叫用它。

發布分支按元件進行命名空間隔離（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI 為 `releases/X.Y.x`），因此這三個元件的線路永遠不會在同一個次要版本上衝突。

### 每週排程

每週一 UTC 06:00，三個元件的提升作業會同步執行：**CLI 提升至穩定版**、**Server 提升至穩定版** 與 **Kura 提升至穩定版**。每個作業都會提升尚未成為穩定版的最新 RC 線，通常是上週一切割的線路。若沒有這樣的線路，該作業就不會發布任何內容。

當提升完成時，無論結果為何，其對應的 **候選版本** 工作流程（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）會透過 `workflow_run` 觸發，並從 `main` 切割下一條線路。

若任一預定執行失敗或取消，系統會將訊息張貼至 Slack。當發布分支在其最新 RC 之後仍有提交時，提升會失敗。若要發布該線路，請在其上切割新的 RC 並手動提升。否則，下週一將改為提升較新的線路。

### 切割候選版本

若要在每週排程之外切割新線路（請將下方元件的工作流程名稱替換為對應名稱）：

1. 以空的 `branch` 輸入執行 **\<Component\> Release Candidate** 工作流程（例如 `server-rc.yml`）。
2. 它會發布 `X.Y.0-rc.1`，並在成功後於已建置的提交處建立受保護的 `releases/<component>-X.Y.x` 分支。

若要將關鍵修復或回歸問題拉入浸泡中的線路，請透過 PR 將其 cherry-pick 到發布分支（與回溯移植的流程相同；CI 從不執行 cherry-pick），然後迭代 RC：

1. 從 `releases/<component>-X.Y.x` 建立分支，cherry-pick 該修復，開啟一個回到發布分支的 PR，解決其中的任何衝突，然後合併。
2. 再次以 `branch=releases/<component>-X.Y.x` 執行 **Release Candidate** 工作流程。它會從分支 HEAD 發布 `X.Y.0-rc.(N+1)`。

浸泡中的線路會凍結功能：僅允許關鍵修復和回歸問題進入。

### 提升至穩定版

若要在每週排程之外提升線路，請在其 RC 順利完成浸泡後：

1. 以 `branch=releases/<component>-X.Y.x` 執行 **\<Component\> Promote to Stable** 工作流程（例如 `server-promote.yml`）。
2. 它會以 `make_latest=true` 發布帶有語意化版本標籤的映像，移動 GHCR `:latest` 標籤與 GitHub「Latest」指標。CLI 還會更新 Homebrew formula。

除非分支 HEAD 正好是最新 RC 指向的提交，否則提升作業拒絕執行。因此，若在最後一個 RC 之後有任何修復合併到該線路，你必須切割新的 RC 並讓其浸泡，才能作為穩定版發布。

### 將修補程式回溯移植到穩定線路

一旦線路成為穩定版，就使用僅限 CLI 的 **Backport Release** 工作流程（`cli-backport.yml`）來發布修補程式：透過 PR 將修復 cherry-pick 到 `releases/X.Y.x`，然後以該分支執行工作流程以切割 `X.Y.(Z+1)`。回溯移植從不會移動「Latest」指標或 Homebrew formula。同時維護兩條線路：當前線路處理回歸問題與安全性修復，前一條線路僅處理關鍵與安全性修復。其他錯誤修復不會回溯移植，而是隨下一個次要版本發布。

對於 Server 與 Kura，目前的回溯移植是透過對較舊的發布分支執行提升工作流程來切割。後續工作將新增專用的回溯移植工作流程，以鏡像 CLI 的做法。

## 撰寫良好的提交訊息

由於提交訊息會直接影響發行說明，因此撰寫清晰、具描述性的訊息至關重要：

### 建議做法：
- 使用現在式：「add feature」而非「added feature」
- 簡潔但具描述性
- 當變更屬於特定元件時，請包含範圍
- 在適用時參考議題：`fix(cli): resolve build cache issue (#1234)`

### 避免做法：
- 使用模糊的訊息，例如「fix bug」或「update code」
- 在一次提交中混合多個不相關的變更
- 忘記包含破壞性變更資訊

### 破壞性變更

對於破壞性變更，請在提交主體中包含 `BREAKING CHANGE:`：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 發布工作流程

CLI、Server 與 Kura 各自擁有一組管道工作流程，結構相同：

- `<component>-release.yml` - 在每次觸及元件的推送到 `main` 時發布 canary（Kura 的是可重複使用的工作流程，由 `server-production-deployment.yml` 在 `kura/` 變更時呼叫）
- `<component>-rc.yml` - 每週一切割候選版本（透過提升後的 `workflow_run`），或手動切割或迭代
- `<component>-promote.yml` - 每週一 UTC 06:00 將待定的 RC 提升至穩定版，或手動提升已浸泡的 RC
- `<component>-build-publish.yml` - 上述三者共用的建置與發布管線

CLI 另有 `cli-backport.yml` 用於在穩定線路上切割修補程式。元件的所有工作流程都會透過單一 `<component>-publish` 並行群組序列化，因此版本解析與標籤不會發生競爭。Kura 是例外：其 canary 使用 `kura-canary-publish`，而其 RC 與提升則使用 `kura-stable-publish`，因此長時間的 RC 或提升建置不會阻礙部署串流。標籤命名空間互不相交，因此這兩個群組不會衝突。

Helm chart 與基礎設施映像（CAPI operator、runners controller、xcresult processor image、linux runner image 等）仍透過 `.github/workflows/server-production-deployment.yml` 發布。它在推送到 `main` 時執行，並為託管部署串流 canary → 驗收測試 → 生產環境，並在這些基礎設施元件變更時發布它們。App、快取、Gradle plugin、skills、Noora 與獨立的基礎設施控制器各自擁有專用的 `*-release.yml` 工作流程。它們共用變更偵測：`mise/tasks/release/components.json` 宣告每個元件的標籤前綴與包含路徑，而 git cliff 會將相符的提交轉換為發行說明。

CLI 建置（`cli-build-publish.yml`）也會產生並發布 `tuist.spec.json` 產物（由 `tuist --experimental-dump-help` 產生），以便下游工具鏈使用命令介面。

## 監控發布

你可以透過以下方式監控發布：
- [GitHub Releases 頁面](https://github.com/tuist/tuist/releases)
- GitHub Actions 分頁中的工作流程執行記錄
- 各元件目錄中的變更記錄檔案

## 優點

這種持續發布方式提供：

- **快速交付**：變更在合併後立即送達使用者
- **減少瓶頸**：無需等待手動發布
- **清晰溝通**：從提交訊息自動產生變更記錄
- **一致流程**：所有元件採用相同的發布流程
- **品質保證**：僅發布經過測試的變更

## 疑難排解

如果發布失敗：

1. 檢查 GitHub Actions 日誌中失敗的工作流程
2. 確保你的提交訊息遵循慣例格式
3. 確認所有測試皆通過
4. 確認元件建置成功

對於需要立即發布的緊急修復：
1. 確保你的提交具有明確的作用範圍
2. 合併後，監控發布工作流程
3. 對於 Server 或 App，修復會在下一次推送時交付；如有需要，觸發手動發布
4. 對於 CLI，修復會自動進入 canary。若要讓穩定版使用者取得，請將其回溯移植至維護中的穩定線路（參閱[將修復回溯移植至穩定線路](#backporting-fixes-to-a-stable-line)）

## App Store 發布

雖然 CLI 與 Server 遵循上述的持續發布流程，但由於 Apple 的 App Store 審查流程，**iOS App**是例外：

- **手動發布**：iOS App 發布需要手動提交至 App Store
- **審查延遲**：每次發布都必須經過 Apple 的審查流程，可能需要 1-7 天
- **批次變更**：每次 iOS 發布通常會將多項變更打包在一起
- **TestFlight**：Beta 版本可能在 App Store 發布前透過 TestFlight 分發
- **發行說明**：必須依照 App Store 規範撰寫

iOS App 仍遵循相同的提交慣例並使用 git cliff 產生變更記錄，但實際向使用者發布的频率較低，且採用手動排程。
