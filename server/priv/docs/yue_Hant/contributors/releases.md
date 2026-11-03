---
{
  "title": "版本發佈",
  "titleTemplate": ":title | 貢獻者 | Tuist",
  "description": "了解 Tuist 的持續發佈流程如何運作"
}
---
# 版本

當變更合併到 main 分支時，Tuist 會自動發布新版本。CLI、伺服器同 Kura 快取伺服器都透過發布渠道（canary、候選版本、穩定版）發佈，令推薦安裝保持穩定同更新節奏較慢；切出候選版本並提升為穩定版係刻意嘅每週步驟。應用程式會持續發布（iOS 應用程式只會持續部署到 TestFlight，詳情請見[此處](#app-store-release)）。

## 概覽

我哋會發布以下主要組件：
- **Tuist CLI** - 命令列工具，透過 canary、候選版本同穩定[渠道](#release-channels)發佈
- **Tuist Server** - 後端服務，採用與 CLI 相同嘅渠道模型發佈
- **Kura** - 快取伺服器，採用與 CLI 相同嘅渠道模型發佈
- **Tuist App** - macOS 同 iOS 應用程式，持續發布（iOS 應用程式只會持續部署到 TestFlight，詳情請見[此處](#app-store-release)）

每次推送到 `main` 都會為 CLI、伺服器同 Kura 發布 canary 預發布版本。每個組件嘅穩定版本只會在維護者將經過充分測試嘅候選版本提升時先至切出，而每週排程會同步觸發全部三個發布列車（參閱[發布渠道](#release-channels)）。應用程式會在每次推送到 `main` 時發布穩定版。

## 運作方式

### 1. Commit 規範

我哋使用[Conventional Commits](https://www.conventionalcommits.org/)來組織 commit 訊息。這讓工具能夠理解變更性質、決定版本升級，並生成適當嘅變更日誌。

格式：`type(scope): description`

#### Commit 類型及其影響

| 類型 | 描述 | 版本影響 | 範例 |
|------|-------------|----------------|---------|
| `feat` | 新功能或能力 | 次版本升級 (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | 錯誤修復 | 修訂版本升級 (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | 文件變更 | 不發布 | `docs: update installation guide` |
| `style` | 程式碼風格變更 | 不發布 | `style: format code with swiftformat` |
| `refactor` | 程式碼重構 | 不發布 | `refactor(server): simplify auth logic` |
| `perf` | 效能改進 | 修訂版本升級 | `perf(cli): optimize dependency resolution` |
| `test` | 測試新增/變更 | 不發布 | `test: add unit tests for cache` |
| `chore` | 維護任務 | 不發布 | `chore: update dependencies` |
| `ci` | CI/CD 變更 | 不發布 | `ci: add workflow for releases` |

對於 CLI，這些升級決定 canary 版本同變更日誌分組。穩定 CLI 版本係手動切出嘅次版本線 (`X.Y.0`)，而穩定修訂版 (`X.Y.Z`) 只來自回溯移植，因此 `feat` 或 `fix` 會透過下方渠道流程到達 CLI 用戶，而非立即作為穩定版本發布。

#### 破壞性變更

破壞性變更會觸發主版本升級 (X.0.0)，並應在 commit 內文中标明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 變更偵測

每個組件都使用 [git cliff](https://git-cliff.org/) 來：
- 分析自上次發布以來嘅 commit
- 按範圍過濾 commit（cli、app、server）
- 判斷是否有可發布嘅變更
- 自動生成變更日誌

### 3. 發布流程

當偵測到可發布嘅變更時：

1. **版本計算**：流程決定下一個版本號
2. **變更日誌生成**：git cliff 根據 commit 訊息建立變更日誌
3. **建構流程**：建構並測試組件
4. **產物生成**：產生發布專用資產，例如 CLI 套件、校驗和，以及從 `tuist --experimental-dump-help` 生成嘅 `tuist.spec.json` CLI 規格
5. **建立發布**：建立包含產物嘅 GitHub 發布
6. **分發**：將更新推送到套件管理器（例如 CLI 嘅 Homebrew）

對於應用程式，每次合併都會產生穩定版本。對於 CLI、伺服器同 Kura，同樣嘅自動流程只會產生 **canary** 預發布版本；候選版本同穩定版本會喺每週發布列車上切出（參閱[發布渠道](#release-channels)）。

### 4. 範圍過濾

每個組件只會在有相關變更時先至發布：

- **CLI**：帶有 `(cli)` 範圍或無範圍嘅 commit
- **App**：帶有 `(app)` 範圍嘅 commit
- **Server**：帶有 `(server)` 範圍嘅 commit

## 發布渠道

CLI、伺服器同 Kura 唔會喺每次推送到 `main` 時都提升為穩定版本。每個組件都透過三個渠道發佈，令推薦安裝保持穩定同變動緩慢，同時讓早期採用者保留每次 commit 嘅建構。用戶可見嘅文件位於 <.localized_link href="/cli/release-channels">CLI 發布渠道</.localized_link> 同 <.localized_link href="/guides/server/self-host/release-channels">伺服器發布渠道</.localized_link>；本節係維護者操作手冊。

每個組件都使用相同嘅三個渠道：

| 渠道 | 版本 | 切出方式 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動，於每次影響組件嘅推送到 `main` 時（`<component>-release.yml`；對於 Kura，當 `kura/` 變更時由 `server-production-deployment.yml` 呼叫） |
| 候選版本 | `X.Y.0-rc.N` | 每星期一，或手動，喺 `releases/<component>-<major>.<minor>.x` 分支上（`<component>-rc.yml`） |
| 穩定 | `X.Y.Z` | 每星期一，或手動，透過提升經過充分測試嘅 RC（`<component>-promote.yml`）；修訂版透過 `<component>-backport.yml` |

Canary 同 RC 建構會以 GitHub 預發布形式發布（永遠唔會標記為「Latest」，永遠唔會移動 GHCR 上嘅 `:latest`，永遠唔會推送到 CLI 嘅 Homebrew），因此套件管理器同映像解析器只會在明確選擇加入時先至採用。Canary 永遠針對下一個未發布嘅次版本：一旦切出 RC 線，`main` 嘅 canary 就會推進到下一個次版本。

託管 Tuist 唔會等待穩定列車：伺服器按 commit 部署，而託管 canary 同生產環境運行最新嘅 Kura canary。部署級聯會喺部署之前發布該 canary 本身，因此 `kura-release.yml` 冇自己嘅觸發器。單獨更改 Kura 發布工具（`mise/tasks/kura/**`、`kura-*.yml` 工作流）唔會切出 canary。

你永遠唔會手動挑選版本號。每個渠道嘅下一個版本都由 `mise/tasks/<component>/release/channel-version.sh` 從現有 git 標籤衍生，下方工作流會呼叫它。

發布分支按組件進行命名空間隔離（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI 用 `releases/X.Y.x`），因此三個組件嘅線永遠唔會喺同一個次版本衝突。

### 每週排程

每星期一 UTC 時間 06:00，三個組件嘅提升作業會同步運行：**CLI 提升至穩定**、**伺服器提升至穩定** 同 **Kura 提升至穩定**。每個作業都會提升最新嘅未穩定 RC 線，通常係上星期一切出嘅線。如果冇咁嘅線，該作業就唔會發布任何內容。

當提升完成後，無論結果如何，其對應嘅 **候選版本** 工作流（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）會透過 `workflow_run` 觸發，並從 `main` 切出下一條線。

如果任何預定運行失敗或被取消，系統會向 Slack 發送訊息。當發布分支喺其最新 RC 之後有 commit 時，提升會失敗。要發布該線，請喺上面切出新嘅 RC 並手動提升。否則，下星期一會改為提升較新嘅線。

### 切出候選版本

要喺每週排程之外切出新線（將下方組件嘅工作流名稱替換）：

1. 運行 **\<Component\> 候選版本** 工作流（例如 `server-rc.yml`），並將 `branch` 輸入留空。
2. 佢會發布 `X.Y.0-rc.1`，成功後喺已建構嘅 commit 建立受保護嘅 `releases/<component>-X.Y.x` 分支。

要將關鍵修復或回歸問題引入浸泡中嘅線路，請透過 PR 將其 cherry-pick 到發布分支（流程同 backport 一樣；CI 永遠唔會執行 cherry-pick），然後迭代 RC：

1. 從 `releases/<component>-X.Y.x` 開出分支，cherry-pick 該修復，開啟一個 PR 合併回發布分支，解決任何衝突，然後合併。
2. 再次運行 **候選版本** 工作流，並設定 `branch=releases/<component>-X.Y.x`。佢會從分支 HEAD 發布 `X.Y.0-rc.(N+1)`。

浸泡中嘅線路係功能凍結嘅：只有關鍵修復同回歸問題先至會合併入去。

### 提升至穩定

要喺每週排程之外提升線路，請喺其 RC 充分浸泡且無問題後進行：

1. 運行 **\<Component\> 提升至穩定** 工作流（例如 `server-promote.yml`），並設定 `branch=releases/<component>-X.Y.x`。
2. 佢會使用 `make_latest=true` 發布帶有 semver 標籤嘅映像，移動 GHCR `:latest` 標籤同 GitHub「Latest」指標。CLI 亦會更新 Homebrew formula。

除非分支 HEAD 正好係最新 RC 指向嘅 commit，否則提升作業拒絕運行。因此，如果喺最後一個 RC 之後有任何修復合併到該線路，你必須切出新嘅 RC 並讓其浸泡，先至可以作為穩定版發布。

### 將修復 backport 到穩定線路

一旦線路穩定，就使用僅限 CLI 嘅 **Backport Release** 工作流（`cli-backport.yml`）來發布修訂版：透過 PR 將修復 cherry-pick 到 `releases/X.Y.x`，然後使用該分支運行工作流以切出 `X.Y.(Z+1)`。Backport 永遠唔會移動「Latest」指標或 Homebrew formula。同時維護兩條線路：當前線路處理回歸問題同安全修復，上一條線路只處理關鍵同安全修復。其他錯誤修復唔會 backport，而係隨下一個次版本發布。

對於伺服器同 Kura，請使用 **Server Backport Release**（`server-backport.yml`）或 **Kura Backport Release**（`kura-backport.yml`）。提升作業只發布 RC 嘅 `X.Y.0`；佢無法修補已經穩定嘅線路。

1. 從所選 `X.Y` 線路上最新發布嘅穩定組件標籤開始，並向其現有嘅 `releases/server-X.Y.x` 或 `releases/kura-X.Y.x` 分支開啟一個精準修復 PR。較新嘅次版本或主版本發布唔會阻止對維護中線路嘅修補。請排除無關嘅 main 變更。
2. 審查並合併來源 PR。抓取遠端發布分支並確認其 **最終合併頂點**，包括組件支援嘅平台同 TLS 正負控制項。通過預合併頭部並唔代表對不同 squash 或合併 commit 嘅確認。
3. 獲得獨立嘅發布批准後，從 **main** 調度對應嘅 backport 工作流，將 `source_sha` 設定為該精確確認嘅合併頂點，並將 `base_tag` 設定為當前穩定標籤，例如 `server@X.Y.Z` 或 `kura@X.Y.Z`。工作流會推導出 `X.Y.(Z+1)`；操作員唔會選擇次版本升級或提升 canary 內容。

規劃會刷新精確嘅遠端分支同基礎標籤，要求所選來源等於分支頂點，拒絕未更改嘅來源或組件之外嘅變更、其信任策略輸入同驗證，並鎖定已解析嘅基礎 commit。源自 main 嘅控制項會喺版本化映像同 GitHub 發布之前立即重複這些檢查。如果來源分支、穩定基礎或可用版本發生變化，請停止並重新確認，而唔係替換新來源。

Backport 使用現有嘅多平台發布器，而唔會移動 GitHub 嘅「Latest」指標或 GHCR `:latest`。發布同託管部署係分開嘅：這些工作流唔會提升託管伺服器或 Kura 集群，唔會繞過 canary 接受，亦唔會確認已安裝嘅運行時。建構助手同 Dockerfiles 仍然來自所選嘅穩定來源。控制項係發布閘門，而唔係免憑證嘅建構作業；建構可以喺最終閘門之前上傳未標記嘅映像摘要。映像同 GitHub 發布唔係原子操作：如果喺映像標籤發布後後續閘門失敗，請檢查部分發布並保留其原始來源同產物。切勿替換現有發布或喺其標籤下使用不同嘅字節。

## 撰寫良好嘅 commit 訊息

由於 commit 訊息直接影響發布說明，因此撰寫清晰、具描述性嘅訊息好重要：

### 應該做：
- 使用現在式：「add feature」而唔係「added feature」
- 簡潔但具描述性
- 當變更係組件特定時，包含範圍
- 適用時引用 issue：`fix(cli): resolve build cache issue (#1234)`

### 唔好做：
- 使用模糊嘅訊息，例如「fix bug」或「update code」
- 喺一個 commit 中混合多個無關嘅變更
- 忘記包含破壞性變更資訊

### 破壞性變更

對於破壞性變更，請喺 commit 正文中包含 `BREAKING CHANGE:`：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 發布工作流

CLI、伺服器同 Kura 各自有一套渠道工作流，遵循相同嘅結構：

- `<component>-release.yml` - 喺每次影響組件嘅 push 到 `main` 時發布 canary（Kura 嘅係可重用工作流，當 `kura/` 變更時由 `server-production-deployment.yml` 呼叫）
- `<component>-rc.yml` - 每星期一切出候選版本（透過提升後嘅 `workflow_run`），或手動切出或迭代
- `<component>-promote.yml` - 每星期一 UTC 時間 06:00 將待定 RC 提升至穩定，或手動提升已浸泡嘅 RC
- `<component>-build-publish.yml` - 上述三個工作流共用嘅建構同發布流水線

CLI、伺服器同 Kura 仲有 `<component>-backport.yml` 用於喺穩定線路上切出修訂版。組件嘅所有工作流都透過一個 `<component>-publish` 併發組序列化，因此版本解析同標籤永遠唔會競爭。Kura 係例外：其 canary 使用 `kura-canary-publish`，而其 RC、提升同 backport 使用 `kura-stable-publish`，因此長時間嘅穩定建構永遠唔會阻礙部署級聯。標籤命名空間係不相交嘅，因此兩個組別唔會衝突。

Helm chart 同基礎設施映像（CAPI operator、runners controller、xcresult processor image、linux runner image 等）仍然透過 `.github/workflows/server-production-deployment.yml` 發布。佢會喺 push 到 `main` 時執行，並為託管部署級聯 canary → 驗收測試 → 生產環境，同時喺基礎設施組件變更時發布佢哋。App、cache、Gradle plugin、skills、Noora 同獨立基礎設施控制器各自有專用嘅 `*-release.yml` 工作流。佢哋都共用變更檢測：`mise/tasks/release/components.json` 宣告每個組件嘅標籤前綴同包含路徑，而 git cliff 會將匹配嘅 commit 轉換為發布說明。

CLI 建構（`cli-build-publish.yml`）亦會產生並發布 `tuist.spec.json` 構件（由 `tuist --experimental-dump-help` 生成），以便下游工具可以使用命令介面。

## 監控發布

你可以透過以下方式監控發布：
- [GitHub Releases 頁面](https://github.com/tuist/tuist/releases)
- GitHub Actions 標籤頁查看工作流運行
- 每個組件目錄中嘅 Changelog 文件

## 好處

呢種持續發布方法提供：

- **快速交付**：變更喺合併後立即送達用戶
- **減少瓶頸**：無需等待手動發布
- **清晰溝通**：從 commit 訊息自動生成 changelog
- **一致流程**：所有組件使用相同嘅發布流程
- **質量保證**：只發布經過測試嘅變更

## 疑難排解

如果發布失敗：

1. 檢查 GitHub Actions 日誌以了解失敗嘅工作流
2. 確保你嘅 commit 訊息遵循慣例格式
3. 驗證所有測試通過
4. 檢查組件是否成功建構

對於需要立即發布嘅緊急修復：
1. 確保你嘅 commit 有清晰嘅範圍
2. 合併後，監控發布工作流
3. 對於伺服器或 app，修復會喺下一次 push 時發布；如有需要，觸發手動發布
4. 對於 CLI，修復會自動進入 canary。要令穩定用戶收到，請將其 backport 到受維護嘅穩定線路（參見 [Backporting fixes to a stable line](#backporting-fixes-to-a-stable-line)）

## App Store 發布

雖然 CLI 同 Server 遵循上述嘅持續發布流程，但由於 Apple App Store 審查流程，**iOS app** 係例外：

- **手動發布**：iOS app 發布需要手動提交到 App Store
- **審查延遲**：每次發布都必須經過 Apple 嘅審查流程，可能需要 1-7 天
- **批量變更**：多個變更通常會打包喺每次 iOS 發布中
- **TestFlight**：Beta 版本可能喺 App Store 發布之前透過 TestFlight 分發
- **發布說明**：必須根據 App Store 指南專門編寫

iOS app 仍然遵循相同嘅 commit 慣例並使用 git cliff 生成 changelog，但實際向用戶發布係按照較少頻率、手動嘅時間表進行。
