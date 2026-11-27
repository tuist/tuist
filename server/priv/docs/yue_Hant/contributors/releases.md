---
{
  "title": "版本發布",
  "titleTemplate": ":title | 貢獻者 | Tuist",
  "description": "了解 Tuist 的持續發布流程如何運作"
}
---
# 發行版本

當變更合併到 main 分支時，Tuist 會自動發布新版本。CLI、伺服器同 Kura 快取伺服器都透過發行渠道（canary、release candidate、stable）發佈，令推薦安裝保持穩定同更新節奏較慢；建立 release candidate 並將其升級為 stable 係每週有意識執行嘅步驟。應用程式會持續發行（iOS 應用程式只會持續部署到 TestFlight，詳情請參閱[此處](#app-store-release)）。

## 概覽

我哋會發行以下主要元件：
- **Tuist CLI** - 命令列工具，透過 canary、release candidate 同 stable [渠道](#release-channels)發佈
- **Tuist Server** - 後端服務，採用與 CLI 相同嘅渠道模型發佈
- **Kura** - 快取伺服器，採用與 CLI 相同嘅渠道模型發佈
- **Tuist App** - macOS 同 iOS 應用程式，持續發行（iOS 應用程式只會持續部署到 TestFlight，詳情請參閱[此處](#app-store-release)）

每次推送至 `main` 都會為 CLI、伺服器同 Kura 發佈 canary 預發行版本。每個元件嘅 stable 版本只會在維護者將經過充分測試嘅 release candidate 升級時建立，而每週排程會同步觸發全部三個發行列車（參見[發行渠道](#release-channels)）。應用程式會在每次推送至 `main` 時發佈 stable 版本。

## 運作方式

### 1. Commit 規範

我哋使用 [Conventional Commits](https://www.conventionalcommits.org/) 來組織 commit 訊息。這讓工具能夠理解變更性質、決定版本號提升，並生成合適嘅變更日誌。

格式：`type(scope): description`

#### Commit 類型及其影響

| 類型 | 描述 | 版本影響 | 示例 |
|------|-------------|----------------|---------|
| `feat` | 新功能或能力 | 次要版本提升 (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | 錯誤修復 | 修補版本提升 (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | 文件變更 | 不發行 | `docs: update installation guide` |
| `style` | 程式碼風格變更 | 不發行 | `style: format code with swiftformat` |
| `refactor` | 程式碼重構 | 不發行 | `refactor(server): simplify auth logic` |
| `perf` | 效能改進 | 修補版本提升 | `perf(cli): optimize dependency resolution` |
| `test` | 測試新增/變更 | 不發行 | `test: add unit tests for cache` |
| `chore` | 維護任務 | 不發行 | `chore: update dependencies` |
| `ci` | CI/CD 變更 | 不發行 | `ci: add workflow for releases` |

對於 CLI，這些提升會決定 canary 版本同變更日誌分組。Stable CLI 版本係手動建立嘅次要版本線 (`X.Y.0`)，而 stable 修補版本 (`X.Y.Z`) 只來自回溯移植，因此 `feat` 或 `fix` 會透過下述渠道流程到達 CLI 用戶，而非立即作為 stable 發行。

#### 破壞性變更

破壞性變更會觸發主要版本提升 (X.0.0)，並應在 commit 正文中指明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 變更偵測

每個元件都使用 [git cliff](https://git-cliff.org/) 來：
- 分析自上次發行以來嘅 commits
- 按範圍篩選 commits（cli、app、server）
- 判斷是否有可發行嘅變更
- 自動生成變更日誌

### 3. 發行流程

當偵測到可發行嘅變更時：

1. **版本計算**：流程會決定下一個版本號
2. **生成變更日誌**：git cliff 根據 commit 訊息建立變更日誌
3. **構建過程**：構建並測試元件
4. **生成構件**：產生發行專用資產，例如 CLI 捆綁包、校驗和，以及由 `tuist --experimental-dump-help` 生成嘅 `tuist.spec.json` CLI 規格
5. **建立發行**：建立包含構件嘅 GitHub 發行
6. **分發**：將更新推送到套件管理器（例如 CLI 嘅 Homebrew）

對於應用程式，每次合併都會產生 stable 發行。對於 CLI、伺服器同 Kura，同一個自動流程只會產生 **canary** 預發行版本；release candidate 同 stable 發行會喺每週發行列車上建立（參見[發行渠道](#release-channels)）。

### 4. 範圍篩選

每個元件只會在有相關變更時才發行：

- **CLI**：帶有 `(cli)` 範圍或無範圍嘅 commits
- **App**：帶有 `(app)` 範圍嘅 commits
- **Server**：帶有 `(server)` 範圍嘅 commits

## 發行渠道

CLI、伺服器同 Kura 唔會喺每次推送至 `main` 時都升級為 stable 發行。每個元件都透過三個渠道發佈，令建議安裝保持穩定同緩慢更新，同時讓早期採用者保留每次 commit 嘅構建。面向用戶嘅文件位於 <.localized_link href="/cli/release/channels">CLI 發行渠道</.localized_link> 同 <.localized_link href="/guides/server/self-host/release/channels">Server 發行渠道</.localized_link>；本節係維護者操作手冊。

每個元件都使用相同嘅三個渠道：

| 渠道 | 版本 | 建立者 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動地，喺每次影響元件嘅推送至 `main` 時（`<component>-release.yml`；對於 Kura，當 `kura/` 變更時由 `server-production-deployment.yml` 調用） |
| Release candidate | `X.Y.0-rc.N` | 每週一，或手動地，喺 `releases/<component>-<major>.<minor>.x` 分支上（`<component>-rc.yml`） |
| Stable | `X.Y.Z` | 每週一，或手動地，透過升級經過充分測試嘅 RC（`<component>-promote.yml`）；修補版本透過 `<component>-backport.yml` |

Canary 同 RC 構建會作為 GitHub 預發行版本發佈（永遠唔會標記為「Latest」，永遠唔會移動 GHCR 上嘅 `:latest`，永遠唔會推送到 CLI 嘅 Homebrew），因此套件管理器同映像解析器只會在明確選擇加入時先會獲取它們。Canary 始終針對下一個未發行嘅次要版本：一旦建立咗 RC 線，`main` 嘅 canary 就會推進到下一個次要版本。

託管 Tuist 唔會等待 stable 列車：伺服器會按 commit 部署，而託管 canary 同生產環境會運行最新嘅 Kura canary。部署級聯會喺部署之前先發佈該 canary，因此 `kura-release.yml` 本身沒有觸發器。僅更改 Kura 發行工具（`mise/tasks/kura/**`、`kura-*.yml` 工作流）唔會建立 canary。

你永遠唔會手動挑選版本號。每個渠道嘅下一個版本都由 `mise/tasks/<component>/release/channel-version.sh` 從現有 git 標籤衍生而來，下述工作流會調用它。

發行分支按元件進行命名空間隔離（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI 嘅 `releases/X.Y.x`），因此三個元件嘅線永遠唔會喺同一個次要版本發生衝突。

### 每週排程

每週一 UTC 時間 06:00，三個元件嘅升級作業會同步運行：**CLI Promote to Stable**、**Server Promote to Stable** 同 **Kura Promote to Stable**。每個作業都會升級最新且尚未成為 stable 嘅 RC 線，通常係上週一建立嘅線。如果沒有這樣嘅線，該作業就唔會發佈任何內容。

當升級完成時，無論結果如何，其對應嘅 **Release Candidate** 工作流（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）都會透過 `workflow_run` 觸發，並從 `main` 建立下一條線。

如果任何預定運行失敗或被取消，系統會向 Slack 發送消息。當發行分支喺其最新 RC 之後還有 commits 時，升級會失敗。要發行該線，請喺其上建立新嘅 RC 並手動升級。否則，下週一會改為升級較新嘅線。

### 建立 release candidate

要喺每週排程之外建立新線（請替換下面嘅元件工作流名稱）：

1. 運行 **\<Component\> Release Candidate** 工作流（例如 `server-rc.yml`），並提供空嘅 `branch` 輸入。
2. 它會發佈 `X.Y.0-rc.1`，成功之後，會喺已構建嘅 commit 處建立受保護嘅 `releases/<component>-X.Y.x` 分支。

要將關鍵修復或回歸問題引入 soaking 線，請透過 PR 將其 cherry-pick 到發行分支上（流程同 backports 一樣；CI 永遠唔會執行 cherry-pick），然後迭代 RC：

1. 從 `releases/<component>-X.Y.x` 建立分支，cherry-pick 該修復，開啟一個 PR 合併回發行分支，解決當中嘅任何衝突，然後合併。
2. 再次運行 **Release Candidate** 工作流，並設定 `branch=releases/<component>-X.Y.x`。它會從分支 HEAD 發佈 `X.Y.0-rc.(N+1)`。

Soaking 線係功能凍結嘅：只有關鍵修復同回歸問題先會合入。

### 升級至 stable

要喺每週排程之外升級一條線，請喺其 RC 經過充分測試且無問題後進行：

1. 運行 **\<Component\> Promote to Stable** 工作流（例如 `server-promote.yml`），並設定 `branch=releases/<component>-X.Y.x`。
2. 它會以 `make_latest=true` 發佈帶有 semver 標籤嘅映像，移動 GHCR 嘅 `:latest` 標籤同 GitHub 嘅「Latest」指標。CLI 亦會更新 Homebrew formula。

除非分支 HEAD 正好係最新 RC 指向嘅 commit，否則升級作業拒絕運行。因此，如果喺最後一個 RC 之後有任何修復合併到該線，你必須建立新嘅 RC 並讓其經過充分測試，先可以作為 stable 發行。

### 將修復 backport 到 stable 線

一旦某條線成為 stable，就使用僅限 CLI 嘅 **Backport Release** 工作流（`cli-backport.yml`）來發行修補版本：透過 PR 將修復 cherry-pick 到 `releases/X.Y.x`，然後使用該分支運行工作流以建立 `X.Y.(Z+1)`。Backports 永遠唔會移動「Latest」指標或 Homebrew formula。同時維護兩條線：當前線處理回歸問題同安全修復，上一條線只處理關鍵同安全修復。其他錯誤修復唔會 backport，而係隨下一個次要版本一併發行。

對於伺服器同 Kura，請使用 **Server Backport Release**（`server-backport.yml`）或 **Kura Backport Release**（`kura-backport.yml`）。升級只會發佈 RC 嘅 `X.Y.0`；它無法修補已經 stable 嘅線。

1. 從所選 `X.Y` 線上最新發佈嘅 stable 元件標籤開始，並向其現有嘅 `releases/server-X.Y.x` 或 `releases/kura-X.Y.x` 分支開啟一個針對性修復 PR。較新嘅次要或主要版本發行唔會阻止對維護中線路嘅修補。請避免合入與 main 無關嘅更改。
2. 審查並合併來源 PR。獲取遠端發行分支，並確認其 **最終合併頂端**，包括元件支援嘅平台同 TLS 正負向控制。通過預合併頭部並唔代表對另一個 squash 或合併 commit 嘅確認。
3. 獲得獨立嘅發佈批准後，從 main **分派**對應嘅 backport 工作流，將 `source_sha` 設定為該精確確認嘅合併頂端，並將 `base_tag` 設定為當前 stable 標籤，例如 `server@X.Y.Z` 或 `kura@X.Y.Z`。工作流會推導出 `X.Y.(Z+1)`；營運人員唔會選擇次要版本升級或推廣 canary 內容。

規劃會刷新精確嘅遠端分支同基礎標籤，要求所選來源等於分支頂端，拒絕未變更嘅來源或元件以外嘅更改、其信任策略輸入同驗證，並鎖定已解析嘅基礎 commit。來自 main 嘅控制會喺版本化映像同 GitHub 發佈之前立即重複這些檢查。如果來源分支、stable 基礎或可用版本發生變化，請停止並重新確認，而唔係替換新來源。

Backports 使用現有嘅多平台發佈器，而唔會移動 GitHub 嘅「Latest」指標或 GHCR `:latest`。發佈同託管部署係分開嘅：這些工作流唔會推廣託管伺服器或 Kura 集群，唔會繞過 canary 接受程序，亦唔會確認已安裝嘅運行時。構建輔助工具同 Dockerfiles 仍然來自所選嘅 stable 來源。這些控制係發佈閘門，而唔係無需憑證嘅構建作業；構建可以喺最終閘門之前上傳未標記嘅映像摘要。映像同 GitHub 發佈唔係原子操作：如果喺映像標籤發佈之後後續閘門失敗，請檢查部分發行版本並保留其原始來源同產物。切勿替換現有發行版本或喺其標籤下使用不同嘅字節。

## 編寫良好嘅 commit 消息

由於 commit 消息直接影響發行說明，因此編寫清晰、具描述性嘅消息好重要：

### 應該做：
- 使用現在時態：用「add feature」而唔係「added feature」
- 簡潔但具描述性
- 當更改特定於某個元件時，包含範圍
- 適用時引用 issue：`fix(cli): resolve build cache issue (#1234)`

### 唔好做：
- 使用模糊嘅消息，例如「fix bug」或「update code」
- 喺一個 commit 中混合多個不相關嘅更改
- 忘記包含破壞性變更信息

### 破壞性變更

對於破壞性變更，請喺 commit 正文中包含 `BREAKING CHANGE:`：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 發行工作流

CLI、伺服器同 Kura 各自擁有一套渠道工作流，結構相同：

- `<component>-release.yml` - 每當有影響元件嘅 push 到 `main` 時發佈 canary（Kura 嘅係一個可重用工作流，由 `server-production-deployment.yml` 喺 `kura/` 變更時調用）
- `<component>-rc.yml` - 每週一切割 release candidate（透過升級後嘅 `workflow_run`），或手動切割或迭代
- `<component>-promote.yml` - 每週一 UTC 時間 06:00 將待定 RC 升級為 stable，或手動升級經過充分測試嘅 RC
- `<component>-build-publish.yml` - 上述三個工作流調用嘅共享構建同發佈流水線

CLI、伺服器同 Kura  additionally 擁有 `<component>-backport.yml`，用於喺 stable 線上切割修補版本。元件嘅所有工作流都透過單一 `<component>-publish` 併發組序列化，因此版本解析同標籤永遠唔會競爭。Kura 係例外：其 canary 使用 `kura-canary-publish`，而其 RC、升級同 backport 使用 `kura-stable-publish`，因此長時間嘅 stable 構建永遠唔會阻礙部署級聯。標籤命名空間係不相交嘅，因此這兩個組唔會衝突。

Helm chart 同基礎設施映像（CAPI operator、runners controller、xcresult processor image、linux runner image 等）仍然透過 `.github/workflows/server-production-deployment.yml` 發佈。佢會喺 push 到 `main` 時執行，並為託管部署級聯 canary → 驗收測試 → 生產環境，同時隨著變更發佈呢啲基礎設施元件。App、cache、Gradle plugin、skills、Noora 同獨立基礎設施控制器各自擁有專用嘅 `*-release.yml` 工作流。佢哋共用變更檢測：`mise/tasks/release/components.json` 聲明每個元件嘅標籤前綴同包含路徑，而 git cliff 會將匹配嘅 commit 轉換為發行說明。

CLI 構建（`cli-build-publish.yml`）亦會產生並發佈 `tuist.spec.json` 工件（由 `tuist --experimental-dump-help` 生成），以便下游工具可以使用命令介面。

## 監控發行

你可以透過以下方式監控發行：
- [GitHub Releases 頁面](https://github.com/tuist/tuist/releases)
- GitHub Actions 標籤頁查看工作流運行
- 每個元件目錄中嘅 Changelog 文件

## 好處

呢種持續發行方法提供：

- **快速交付**：更改喺合併後立即送達用戶
- **減少瓶頸**：無需等待手動發行
- **清晰溝通**：從 commit 消息自動生成 changelog
- **一致流程**：所有元件使用相同嘅發行流程
- **質量保證**：只發行經過測試嘅更改

## 疑難排解

如果發行失敗：

1. 檢查 GitHub Actions 日誌以了解失敗嘅工作流
2. 確保你嘅 commit 消息遵循常規格式
3. 驗證所有測試通過
4. 檢查元件是否成功構建

對於需要立即發行嘅緊急修復：
1. 確保你嘅 commit 有清晰嘅範圍
2. 合併後，監控發行工作流
3. 對於伺服器或 app，修復會喺下一次 push 時發佈；如有需要，觸發手動發行
4. 對於 CLI，修復會自動進入 canary。要讓 stable 用戶用到，請將其 backport 到維護中嘅 stable 線（參見 [Backporting fixes to a stable line](#backporting-fixes-to-a-stable-line)）

## App Store 發行

雖然 CLI 同 Server 遵循上述嘅持續發行流程，但由於 Apple App Store 嘅審查流程，**iOS app** 係例外：

- **手動發行**：iOS app 發行需要手動提交到 App Store
- **審查延遲**：每次發行都必須經過 Apple 嘅審查流程，可能需要 1-7 天
- **批量更改**：多個更改通常會打包喺每次 iOS 發行中
- **TestFlight**：Beta 版本可能喺 App Store 發行前透過 TestFlight 分發
- **發行說明**：必須根據 App Store 指南專門編寫

iOS app 仍然遵循相同嘅 commit 慣例並使用 git cliff 生成 changelog，但實際向用戶發行嘅頻率較低且為手動安排。
