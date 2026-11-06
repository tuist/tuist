---
{
  "title": "版本發佈",
  "titleTemplate": ":title | 貢獻者 | Tuist",
  "description": "了解 Tuist 的持續發佈流程如何運作"
}
---
# 版本發佈

當變更合併到 main 分支時，Tuist 會自動發佈新版本。CLI、伺服器同 Kura 快取伺服器都透過發佈渠道（canary、候選版本、穩定版）發佈，確保推薦安裝保持穩定同更新節奏較慢；裁切候選版本並將其提升為穩定版係有意識嘅每週步驟。應用程式會持續發佈（iOS 應用程式只會持續部署到 TestFlight，詳情請參閱 [此處](#app-store-release)）。

## 概覽

我哋發佈以下主要組件：
- **Tuist CLI** - 命令列工具，透過 canary、候選版本同穩定版 [渠道](#release-channels) 發佈
- **Tuist Server** - 後端服務，採用與 CLI 相同嘅渠道模型發佈
- **Kura** - 快取伺服器，採用與 CLI 相同嘅渠道模型發佈
- **Tuist App** - macOS 同 iOS 應用程式，持續發佈（iOS 應用程式只會持續部署到 TestFlight，詳情請參閱 [此處](#app-store-release)）

每次推送到 `main` 都會為 CLI、伺服器同 Kura 發佈 canary 預發佈版本。每個組件嘅穩定版本只會在維護者將經過充分測試嘅候選版本提升時裁切，而每週排程會同步觸發所有三個發佈流程（參見 [發佈渠道](#release-channels)）。應用程式會在每次推送到 `main` 時發佈穩定版。

## 運作方式

### 1. Commit 規範

我哋使用 [Conventional Commits](https://www.conventionalcommits.org/) 來組織 commit 訊息。這讓工具能夠理解變更性質、決定版本升級並生成適當嘅變更日誌。

格式：`type(scope): description`

#### Commit 類型及其影響

| 類型 | 描述 | 版本影響 | 示例 |
|------|-------------|----------------|---------|
| `feat` | 新功能或能力 | 次版本升級 (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | 錯誤修復 | 修訂版本升級 (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | 文檔變更 | 不發佈 | `docs: update installation guide` |
| `style` | 代碼風格變更 | 不發佈 | `style: format code with swiftformat` |
| `refactor` | 代碼重構 | 不發佈 | `refactor(server): simplify auth logic` |
| `perf` | 性能改進 | 修訂版本升級 | `perf(cli): optimize dependency resolution` |
| `test` | 測試新增/變更 | 不發佈 | `test: add unit tests for cache` |
| `chore` | 維護任務 | 不發佈 | `chore: update dependencies` |
| `ci` | CI/CD 變更 | 不發佈 | `ci: add workflow for releases` |

對於 CLI，這些升級決定 canary 版本同變更日誌分組。穩定 CLI 版本係手動裁切嘅次版本線 (`X.Y.0`)，而穩定修訂版本 (`X.Y.Z`) 僅來自回溯移植，因此 `feat` 或 `fix` 會透過下面嘅渠道流程到達 CLI 用戶，而非作為即時穩定版本發佈。

#### 破壞性變更

破壞性變更會觸發主版本升級 (X.0.0)，並應在 commit 正文中標明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 變更檢測

每個組件都使用 [git cliff](https://git-cliff.org/) 來：
- 分析自上次發佈以來的 commits
- 按範圍過濾 commits（cli、app、server）
- 判斷是否有可發佈的變更
- 自動生成變更日誌

### 3. 發佈流程

當檢測到可發佈的變更時：

1. **版本計算**：流程決定下一個版本號
2. **變更日誌生成**：git cliff 根據 commit 訊息創建變更日誌
3. **構建過程**：構建並測試組件
4. **產物生成**：生成發佈專用資產，例如 CLI 捆綁包、校驗和，以及從 `tuist --experimental-dump-help` 生成的 `tuist.spec.json` CLI 規格
5. **創建發佈**：創建帶有產物的 GitHub 發佈
6. **分發**：將更新推送到套件管理器（例如 CLI 的 Homebrew）

對於應用程式，這會在每次合併時產生穩定版本。對於 CLI、伺服器同 Kura，此自動流程僅產生 **canary** 預發佈版本；候選版本同穩定版本會於每週發佈列車上裁切（參見 [發佈渠道](#release-channels)）。

### 4. 範圍過濾

每個組件僅在有相關變更時才會發佈：

- **CLI**：帶有 `(cli)` 範圍或無範圍的 commits
- **App**：帶有 `(app)` 範圍的 commits
- **Server**：帶有 `(server)` 範圍的 commits

## 發佈渠道

CLI、伺服器同 Kura 不會在每次推送到 `main` 時都提升為穩定版本。每個組件都透過三個渠道發佈，以便推薦安裝保持穩定且變動緩慢，同時讓早期採用者保留每次 commit 的構建。面向用戶的文檔位於 <.localized_link href="/cli/release-channels">CLI 發佈渠道</.localized_link> 同 <.localized_link href="/guides/server/self-host/release-channels">Server 發佈渠道</.localized_link>；本節係維護者操作手冊。

每個組件都使用相同的三個渠道：

| 渠道 | 版本 | 裁切方式 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動執行，在每次影響組件的推送到 `main` 時執行（`<component>-release.yml`；對於 Kura，當 `kura/` 變更時由 `server-production-deployment.yml` 調用） |
| 候選版本 | `X.Y.0-rc.N` | 每週一，或手動執行，在 `releases/<component>-<major>.<minor>.x` 分支上執行（`<component>-rc.yml`） |
| 穩定版 | `X.Y.Z` | 每週一，或手動執行，透過提升經過充分測試的 RC（`<component>-promote.yml`）；修訂版本透過 `<component>-backport.yml` |

Canary 同 RC 構建會作為 GitHub 預發佈版本發佈（永遠不會標記為「Latest」，永遠不會移動 GHCR 上的 `:latest`，永遠不會推送到 CLI 的 Homebrew），因此套件管理器同映像解析器只會在明確選擇加入時獲取它們。Canary 始終針對下一個未發佈的次版本：一旦裁切了 RC 線，`main` 的 canary 就會推進到下一個次版本。

託管 Tuist 不會等待穩定列車：伺服器按 commit 部署，而託管 canary 同生產環境運行最新的 Kura canary。部署級聯會在部署之前自行發佈該 canary，因此 `kura-release.yml` 沒有自己的觸發器。僅更改 Kura 發佈工具（`mise/tasks/kura/**`、`kura-*.yml` 工作流）不會裁切 canary。

你永遠不需要手動挑選版本號。每個渠道的下一個版本都由 `mise/tasks/<component>/release/channel-version.sh` 從現有 git 標籤派生，以下工作流會調用它。

發佈分支按組件進行命名空間隔離（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI 為 `releases/X.Y.x`），以便三個組件的線路永遠不會在同一個次版本上衝突。

### 每週排程

每週一 UTC 時間 06:00，三個組件的提升作業會同步運行：**CLI 提升為穩定版**、**Server 提升為穩定版** 同 **Kura 提升為穩定版**。每個作業都會提升尚未穩定的最新 RC 線，通常係上週一裁切的線路。如果沒有這樣的線路，該作業不會發佈任何內容。

當提升完成時，無論結果如何，其匹配的 **候選版本** 工作流（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）會透過 `workflow_run` 觸發，並從 `main` 裁切下一條線路。

如果任何預定運行失敗或被取消，系統會向 Slack 發送消息。當發佈分支在其最新 RC 之後有 commits 時，提升會失敗。要發佈該線路，請在其上裁切新的 RC 並手動提升。否則，下週一會改為提升較新的線路。

### 裁切候選版本

要在每週排程之外裁切新線路（請替換下方組件的工作流名稱）：

1. 使用空的 `branch` 輸入運行 **\<Component\> Release Candidate** 工作流（例如 `server-rc.yml`）。
2. 它會發佈 `X.Y.0-rc.1`，並在成功後於構建的 commit 處建立受保護的 `releases/<component>-X.Y.x` 分支。

若要將關鍵修復或回歸問題引入正在測試的線路，請透過 PR 將其 cherry-pick 到發佈分支（與 backport 流程相同；CI 從不執行 cherry-pick），然後迭代 RC：

1. 從 `releases/<component>-X.Y.x` 建立分支，cherry-pick 該修復，開啟一個 PR 合併回發佈分支，解決其中的任何衝突，然後合併。
2. 再次運行 **Release Candidate** 工作流，並設定 `branch=releases/<component>-X.Y.x`。它會從分支 HEAD 發佈 `X.Y.0-rc.(N+1)`。

測試中的線路會凍結功能：只允許關鍵修復和回歸問題進入。

### 提升為穩定版

若要在每週排程之外提升線路，請在其 RC 通過充分測試後進行：

1. 使用 `branch=releases/<component>-X.Y.x` 運行 **\<Component\> Promote to Stable** 工作流（例如 `server-promote.yml`）。
2. 它會使用 `make_latest=true` 發佈帶有 semver 標籤的映像，移動 GHCR 的 `:latest` 標籤和 GitHub 的「Latest」指標。CLI 還會更新 Homebrew formula。

除非分支 HEAD 正好是最新 RC 指向的 commit，否則提升作業拒絕運行。因此，如果在最後一個 RC 之後有任何修復合併到該線路，你必須裁切新的 RC 並讓其經過測試，然後才能作為穩定版發佈。

### 將修復 backport 到穩定線路

一旦線路穩定，就使用僅限 CLI 的 **Backport Release** 工作流（`cli-backport.yml`）來發佈修訂版本：透過 PR 將修復 cherry-pick 到 `releases/X.Y.x`，然後使用該分支運行工作流以裁切 `X.Y.(Z+1)`。Backport 永遠不會移動「Latest」指標或 Homebrew formula。同時維護兩條線路：當前線路處理回歸和安全修復，前一條線路僅處理關鍵和安全修復。其他錯誤修復不會 backport，而是隨下一個次版本發佈。

對於 Server 和 Kura，請使用 **Server Backport Release**（`server-backport.yml`）或 **Kura Backport Release**（`kura-backport.yml`）。提升只會發佈 RC 的 `X.Y.0`；它無法修補已穩定的線路。

1. 從所選 `X.Y` 線路上最新發佈的穩定組件標籤開始，並向其現有的 `releases/server-X.Y.x` 或 `releases/kura-X.Y.x` 分支開啟一個精確的修復 PR。較新的次版本或主要版本發佈不會阻止對維護中線路的修補。請排除無關的 main 更改。
2. 審查並合併來源 PR。獲取遠端發佈分支並確認其 **最終合併頂點**，包括組件支援的平台和 TLS 正負控制項。通過預合併頭部並不等同於確認不同的 squash 或合併 commit。
3. 在獲得單獨的發佈批准後，**從 main** 分派匹配的 backport 工作流，將 `source_sha` 設定為該精確確認的合併頂點，並將 `base_tag` 設定為當前穩定標籤，例如 `server@X.Y.Z` 或 `kura@X.Y.Z`。工作流會推導出 `X.Y.(Z+1)`；操作員無需選擇次版本升級或提升 canary 內容。

規劃會刷新精確的遠端分支和基礎標籤，要求所選來源等於分支頂點，拒絕未變化的來源或組件之外的更改、其信任策略輸入和驗證，並鎖定已解析的基礎 commit。源自 main 的控制項會在版本化映像和 GitHub 發佈之前立即重複這些檢查。如果來源分支、穩定基礎或可用版本發生變化，請停止並重新確認，而不是替換新來源。

Backport 使用現有的多平台發佈器，而不移動 GitHub 的「Latest」指標或 GHCR `:latest`。發佈與託管部署是分開的：這些工作流不會提升託管伺服器或 Kura 集群，不會繞過 canary 接受，也不會確認已安裝的運行時。構建輔助工具和 Dockerfiles 仍然來自所選的穩定來源。這些控制項是發佈閘門，而非無憑證構建作業；構建可以在最終閘門之前上傳未標記的映像摘要。映像和 GitHub 發佈並非原子操作：如果後續閘門在映像標籤發佈後失敗，請檢查部分發佈並保留其原始來源和構件。切勿替換現有發佈或在其標籤下使用不同的位元組。

## 編寫良好的 commit 訊息

由於 commit 訊息直接影響發行說明，因此編寫清晰、描述性的訊息非常重要：

### 應該做：
- 使用現在式：「add feature」而非「added feature」
- 簡潔但具描述性
- 當更改特定於組件時，包含範圍
- 在適用時參考 issue：`fix(cli): resolve build cache issue (#1234)`

### 不應該做：
- 使用模糊的訊息，如「fix bug」或「update code」
- 在一個 commit 中混合多個不相關的更改
- 忘記包含破壞性變更資訊

### 破壞性變更

對於破壞性變更，請在 commit 正文中包含 `BREAKING CHANGE:`：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 發佈工作流

CLI、Server 和 Kura 各自擁有一組渠道工作流，遵循相同的結構：

- `<component>-release.yml` - 在每次影響組件的 push 到 `main` 時發佈 canary（Kura 的是可重用工作流，當 `kura/` 更改時由 `server-production-deployment.yml` 調用）
- `<component>-rc.yml` - 每週一裁切候選版本（透過提升後的 `workflow_run`），或手動裁切或迭代
- `<component>-promote.yml` - 每週一 UTC 時間 06:00 將待處理的 RC 提升為穩定版，或手動提升經過測試的 RC
- `<component>-build-publish.yml` - 上述三個工作流調用的共享構建和發佈流水線

CLI、Server 和 Kura 還擁有 `<component>-backport.yml` 用於在穩定線路上裁切修訂版本。組件的所有工作流都透過一個 `<component>-publish` 併發組序列化，因此版本解析和標籤永遠不會競爭。Kura 是例外：其 canary 使用 `kura-canary-publish`，而其 RC、提升和 backport 使用 `kura-stable-publish`，因此長時間的穩定構建永遠不會阻礙部署級聯。標籤命名空間是不相交的，因此這兩個組不會衝突。

Helm chart 同基礎設施映像（CAPI operator、runners controller、xcresult processor image、linux runner image 等等）仍然透過 `.github/workflows/server-production-deployment.yml` 發佈。佢會喺 push 到 `main` 時執行，並為託管部署串聯 canary → 驗收測試 → 生產環境，同時喺基礎設施組件變更時發佈佢哋。App、cache、Gradle plugin、skills、Noora 同獨立基礎設施控制器各自擁有專用嘅 `*-release.yml` 工作流。佢哋全部共用變更檢測：`mise/tasks/release/components.json` 聲明每個組件嘅標籤前綴同包含路徑，而 git cliff 會將匹配嘅 commit 轉換為發行說明。

CLI 構建（`cli-build-publish.yml`）亦會產生並發佈 `tuist.spec.json` 工件（由 `tuist --experimental-dump-help` 生成），以便下游工具可以使用命令介面。

## 監控發行版本

你可以透過以下方式監控發行版本：
- [GitHub Releases 頁面](https://github.com/tuist/tuist/releases)
- GitHub Actions 標籤頁查看工作流運行
- 每個組件目錄中嘅 Changelog 文件

## 好處

呢種持續發行方法提供：

- **快速交付**：更改喺合併後立即送達用戶
- **減少瓶頸**：無需等待手動發行
- **清晰溝通**：從 commit 訊息自動生成 changelog
- **一致流程**：所有組件使用相同嘅發行流程
- **質量保證**：僅發行經過測試嘅更改

## 疑難排解

如果發行失敗：

1. 檢查 GitHub Actions 日誌以了解失敗嘅工作流
2. 確保你嘅 commit 訊息遵循慣例格式
3. 驗證所有測試通過
4. 检查组件是否成功構建

對於需要立即發行嘅緊急修復：
1. 確保你嘅 commit 具有清晰嘅範圍
2. 合併後，監控發行工作流
3. 對於 server 或 app，修復會喺下一次 push 時發佈；如有需要，觸發手動發行
4. 對於 CLI，修復會自動進入 canary。要將其提供畀穩定版用戶，請將其 backport 到維護中嘅穩定線路（參見 [Backporting fixes to a stable line](#backporting-fixes-to-a-stable-line)）

## App Store 發行

雖然 CLI 同 Server 遵循上述嘅持續發行流程，但由於 Apple App Store 嘅審查流程，**iOS app** 係一個例外：

- **手動發行**：iOS app 發行需要手動提交到 App Store
- **審查延遲**：每次發行都必須經過 Apple 嘅審查流程，可能需要 1-7 天
- **批量更改**：多個更改通常會打包喺每次 iOS 發行中
- **TestFlight**：Beta 版本可能會喺 App Store 發行前透過 TestFlight 分發
- **發行說明**：必須根據 App Store 指南專門編寫

iOS app 仍然遵循相同嘅 commit 慣例並使用 git cliff 生成 changelog，但實際向用戶發行嘅頻率較低且為手動安排。
