---
{
  "title": "版本發佈",
  "titleTemplate": ":title | 貢獻者 | Tuist",
  "description": "了解 Tuist 的持續版本發佈流程如何運作"
}
---
# 版本發佈

當改動合併到 main 分支時，Tuist 會自動發佈新版本。CLI、伺服器同 Kura 快取伺服器都透過發佈渠道（canary、候選版本、穩定版）進行發佈，令建議安裝保持穩定同更新節奏較慢；建立候選版本並將其提升為穩定版係刻意執行嘅每週步驟。應用程式會持續發佈（iOS 應用程式只會持續部署到 TestFlight，詳情請見[此處](#app-store-release)）。

## 概覽

我哋會發佈以下主要組件：
- **Tuist CLI** - 命令列工具，透過 canary、候選版本同穩定[渠道](#release-channels)發佈
- **Tuist Server** - 後端服務，採用與 CLI 相同嘅渠道模型發佈
- **Kura** - 快取伺服器，採用與 CLI 相同嘅渠道模型發佈
- **Tuist App** - macOS 同 iOS 應用程式，持續發佈（iOS 應用程式只會持續部署到 TestFlight，詳情請見[此處](#app-store-release)）

每次推送到 `main` 都會為 CLI、伺服器同 Kura 發佈 canary 預發佈版本。每個組件嘅穩定版本只會在維護者將經過充分測試嘅候選版本提升時才會建立，而每週排程會同步觸發所有三個發佈流程（參閱[發佈渠道](#release-channels)）。應用程式會喺每次推送到 `main` 時發佈穩定版本。

## 運作方式

### 1. 提交規範

我哋使用[Conventional Commits](https://www.conventionalcommits.org/)來組織提交訊息。這讓工具能夠理解變更性質、決定版本升級，並生成適當嘅變更日誌。

格式：`type(scope): description`

#### 提交類型及其影響

| 類型 | 描述 | 版本影響 | 示例 |
|------|-------------|----------------|---------|
| `feat` | 新功能或能力 | 次版本升級 (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | 錯誤修復 | 修訂版本升級 (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | 文件變更 | 不發佈 | `docs: update installation guide` |
| `style` | 程式碼風格變更 | 不發佈 | `style: format code with swiftformat` |
| `refactor` | 程式碼重構 | 不發佈 | `refactor(server): simplify auth logic` |
| `perf` | 效能改進 | 修訂版本升級 | `perf(cli): optimize dependency resolution` |
| `test` | 測試新增/變更 | 不發佈 | `test: add unit tests for cache` |
| `chore` | 維護任務 | 不發佈 | `chore: update dependencies` |
| `ci` | CI/CD 變更 | 不發佈 | `ci: add workflow for releases` |

對於 CLI，這些升級決定 canary 版本同變更日誌分組。穩定 CLI 版本係人手建立嘅次版本線路（`X.Y.0`），而穩定修訂版本（`X.Y.Z`）只來自回溯移植，因此`feat`或`fix`會透過下面嘅渠道流程到達 CLI 用戶，而唔係作為即時穩定版本發佈。

#### 破壞性變更

破壞性變更會觸發主版本升級 (X.0.0)，並應喺提交內容中標明：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 變更檢測

每個組件都使用[git cliff](https://git-cliff.org/)嚟：
- 分析自上次發佈以來嘅提交
- 按範圍篩選提交（cli、app、server）
- 判斷是否有可發佈嘅變更
- 自動生成變更日誌

### 3. 發佈流程

當檢測到可發佈嘅變更時：

1. **版本計算**：流程會決定下一個版本號
2. **變更日誌生成**：git cliff 根據提交訊息建立變更日誌
3. **建構流程**：建構並測試組件
4. **產物生成**：產生發佈專用資產，例如 CLI 套件、校驗和，以及從`tuist --experimental-dump-help`生成嘅`tuist.spec.json` CLI 規格
5. **建立發佈**：建立包含產物嘅 GitHub 發佈
6. **分發**：將更新推送至套件管理器（例如 CLI 嘅 Homebrew）

對於應用程式，每次合併都會產生穩定版本。對於 CLI、伺服器同 Kura，同一個自動化流程只會產生**canary**預發佈版本；候選版本同穩定版本會喺每週發佈列車上建立（參閱[發佈渠道](#release-channels)）。

### 4. 範圍篩選

每個組件只會在有相關變更時才發佈：

- **CLI**：帶有`(cli)`範圍或無範圍嘅提交
- **App**：帶有`(app)`範圍嘅提交
- **Server**：帶有`(server)`範圍嘅提交

## 發佈渠道

CLI、伺服器同 Kura 唔會喺每次推送到`main`時都提升為穩定版本。每個組件都透過三個渠道發佈，令推薦安裝保持穩定且變動緩慢，同時讓早期採用者保留每次提交嘅建構版本。用戶可見嘅文件位於<.localized_link href="/cli/release-channels">CLI 發佈渠道</.localized_link>同<.localized_link href="/guides/server/self-host/release-channels">Server 發佈渠道</.localized_link>；本節係維護者操作手冊。

每個組件都使用相同嘅三個渠道：

| 渠道 | 版本 | 建立方式 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動執行，每次推送到影響組件嘅`main`時（`<component>-release.yml`；對於 Kura，當`kura/`變更時由`server-production-deployment.yml`呼叫） |
| 候選版本 | `X.Y.0-rc.N` | 每週一，或手動執行，喺`releases/<component>-<major>.<minor>.x`分支上（`<component>-rc.yml`） |
| 穩定 | `X.Y.Z` | 每週一，或手動執行，透過提升經過充分測試嘅 RC（`<component>-promote.yml`）；修訂版本透過`<component>-backport.yml` |

Canary 同 RC 建構版本會以 GitHub 預發佈形式發佈（永遠唔會標記為「Latest」，永遠唔會移動 GHCR 上嘅`:latest`，永遠唔會推送至 CLI 嘅 Homebrew），因此套件管理器同映像解析器只會在明確選擇加入時先會採用。Canary 永遠針對下一個未發佈嘅次版本：一旦建立咗 RC 線路，`main`嘅 canary 就會推進到下一個次版本。

託管版 Tuist 唔會等待穩定列車：伺服器會按每次提交部署，而託管 canary 同生產環境會運行最新嘅 Kura canary。部署級聯會喺部署之前自行發佈該 canary，因此`kura-release.yml`沒有自己嘅觸發器。單獨更改 Kura 發佈工具（`mise/tasks/kura/**`、`kura-*.yml`工作流程）唔會建立 canary。

你永遠唔會手動挑選版本號。每個渠道嘅下一個版本都由`mise/tasks/<component>/release/channel-version.sh`從現有 git 標籤衍生得出，以下工作流程會調用它。

發佈分支按組件進行命名空間隔離（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI 用`releases/X.Y.x`），因此三個組件嘅線路永遠唔會喺同一個次版本衝突。

### 每週排程

每週一 UTC 時間 06:00，三個組件嘅提升作業會同步運行：**CLI Promote to Stable**、**Server Promote to Stable**同**Kura Promote to Stable**。每個作業都會提升最新但尚未穩定嘅 RC 線路，通常係上週一建立嘅線路。如果沒有這樣嘅線路，該作業就唔會發佈任何內容。

當提升完成時，無論結果如何，其對應嘅**Release Candidate**工作流程（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）會透過`workflow_run`觸發，並從`main`建立下一條線路。

如果任何預定運行失敗或被取消，系統會向 Slack 發送訊息。當發佈分支喺其最新 RC 之後還有提交時，提升就會失敗。要發佈該線路，請喺上面建立新嘅 RC 並手動提升。否則，下週一會改為提升較新嘅線路。

### 建立候選版本

要喺每週排程之外建立新線路（將下面嘅組件工作流程名稱替換為對應組件）：

1. 運行 **\<Component\> Release Candidate**工作流程（例如`server-rc.yml`），並將`branch`輸入留空。
2. 它會發佈`X.Y.0-rc.1`，成功後會喺已建構嘅提交處建立受保護嘅`releases/<component>-X.Y.x`分支。

要將關鍵修復或回歸問題引入正在測試嘅線路，請透過 PR 將其 cherry-pick 到發佈分支（流程同 backport 一樣；CI 永遠唔會執行 cherry-pick），然後迭代 RC：

1. 從`releases/<component>-X.Y.x`建立分支，cherry-pick 該修復，開啟一個 PR 合併回發佈分支，解決任何衝突，然後合併。
2. 再次運行**Release Candidate**工作流程，並設定`branch=releases/<component>-X.Y.x`。它會從分支 HEAD 發佈`X.Y.0-rc.(N+1)`。

測試中嘅線路會凍結功能：只接受關鍵修復同回歸問題。

### 提升至穩定版

要喺每週排程之外提升線路，請確保其 RC 已經過充分測試且無問題：

1. 運行 **\<Component\> Promote to Stable**工作流程（例如`server-promote.yml`），並設定`branch=releases/<component>-X.Y.x`。
2. 它會使用`make_latest=true`發佈帶有 semver 標籤嘅映像，移動 GHCR 嘅`:latest`標籤同 GitHub「Latest」指標。CLI 亦會更新 Homebrew formula。

除非分支 HEAD 正好係最新 RC 指向嘅提交，否則提升作業拒絕運行。因此，如果喺最後一個 RC 之後有任何修復合併到該線路，你必須建立新嘅 RC 並讓其經過充分測試，先可以作為穩定版發佈。

### 將修復 backport 到穩定線路

一旦線路成為穩定版，就使用僅限 CLI 嘅**Backport Release**工作流程（`cli-backport.yml`）來發佈修訂版本：透過 PR 將修復 cherry-pick 到`releases/X.Y.x`，然後使用該分支運行工作流程以建立`X.Y.(Z+1)`。Backport 永遠唔會移動「Latest」指標或 Homebrew formula。同時維護兩條線路：當前線路接受回歸問題同安全修復，上一條線路只接受關鍵同安全修復。其他錯誤修復唔會 backport，而會隨下一個次版本一併發佈。

對於伺服器同 Kura，目前嘅 backport 係透過針對較舊發佈分支運行提升工作流程來建立。後續工作將添加模仿 CLI 嘅專用 backport 工作流程。

## 撰寫良好嘅提交訊息

由於提交訊息直接影響發行說明，因此撰寫清晰、具描述性嘅訊息非常重要：

### 應該做：
- 使用現在式：「add feature」而非「added feature」
- 簡潔但具描述性
- 當變更特定於某個組件時，包含範圍
- 適用時參考議題：`fix(cli): resolve build cache issue (#1234)`

### 唔好做：
- 使用模糊嘅訊息，例如「fix bug」或「update code」
- 喺一次提交中混合多個不相關嘅變更
- 忘記包含破壞性變更資訊

### 破壞性變更

對於破壞性變更，請喺提交正文中包含`BREAKING CHANGE:`：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 發佈工作流程

CLI、伺服器同 Kura 各自擁有一套渠道工作流程，結構相同：

- `<component>-release.yml` - 每當有涉及組件嘅推送至`main`時發佈 canary（Kura 嘅係可重用工作流程，由`server-production-deployment.yml`喺`kura/`變更時調用）
- `<component>-rc.yml` - 每週一切割候選版本（透過提升後嘅`workflow_run`觸發），或手動切割或迭代
- `<component>-promote.yml` - 每週一 UTC 時間 06:00 將待定 RC 提升至穩定版，或手動提升經過充分測試嘅 RC
- `<component>-build-publish.yml` - 上述三個工作流程共用嘅建構同發佈管道

CLI 另有`cli-backport.yml`用於喺穩定線路上切割修訂版本。組件嘅所有工作流程都透過單一`<component>-publish`併發組序列化，因此版本解析同標籤永遠唔會競爭。Kura 係例外：其 canary 使用`kura-canary-publish`，而其 RC 同提升使用`kura-stable-publish`，因此長時間嘅 RC 或提升建構永遠唔會阻礙部署級聯。標籤命名空間互不相交，因此兩個組別唔會衝突。

Helm chart 同基礎設施映像（CAPI operator、runners controller、xcresult processor image、linux runner image 等）仍然透過`.github/workflows/server-production-deployment.yml`發佈。它會喺推送至`main`時運行，並為託管部署執行 canary → 驗收測試 → 生產環境嘅級聯，並喺那些基礎設施組件變更時發佈它們。應用程式、快取、Gradle plugin、skills、Noora 同獨立基礎設施控制器各自擁有專用嘅`*-release.yml`工作流程。它們都共用變更檢測：`mise/tasks/release/components.json`聲明每個組件嘅標籤前綴同包含路徑，git cliff 則將匹配嘅提交轉換為發行說明。

CLI 建構（`cli-build-publish.yml`）亦會產生並發佈`tuist.spec.json`工件（由`tuist --experimental-dump-help`生成），以便下游工具可以使用命令介面。

## 監控發佈

你可以透過以下方式監控發佈：
- [GitHub Releases page](https://github.com/tuist/tuist/releases)
- GitHub Actions 標籤頁查看工作流程運行
- 每個組件目錄中嘅 Changelog 文件

## 好處

呢種持續發佈方法提供：

- **快速交付**：變更喺合併後立即送達用戶
- **減少瓶頸**：無需等待手動發佈
- **清晰溝通**：從提交訊息自動生成變更日誌
- **一致流程**：所有組件使用相同嘅發佈流程
- **質量保證**：只發佈經過測試嘅變更

## 疑難排解

如果發佈失敗：

1. 檢查 GitHub Actions 日誌以了解失敗嘅工作流程
2. 確保你嘅提交訊息遵循慣例格式
3. 驗證所有測試均已通過
4. 檢查組件是否成功建構

對於需要立即發佈嘅緊急修復：
1. 確保你嘅提交有明確嘅範圍
2. 合併後，監控發佈工作流程
3. 對於伺服器或應用程式，修復會喺下次推送時發佈；如有需要，觸發手動發佈
4. 對於 CLI，修復會自動進入 canary。要讓穩定版用戶獲得修復，請將其回溯移植到維護中嘅穩定線路（參見[將修復回溯移植到穩定線路](#backporting-fixes-to-a-stable-line)）

## App Store 發佈

雖然 CLI 同伺服器遵循上述嘅持續發佈流程，但由於 Apple App Store 嘅審查流程，**iOS 應用程式**係例外：

- **手動發佈**：iOS 應用程式發佈需要手動提交至 App Store
- **審查延遲**：每次發佈都必須經過 Apple 嘅審查流程，可能需要 1-7 天
- **批量變更**：多個變更通常會打包喺每次 iOS 發佈中
- **TestFlight**：Beta 版本可能會喺 App Store 發佈之前透過 TestFlight 分發
- **發行說明**：必須根據 App Store 指南專門編寫

iOS 應用程式仍然遵循相同嘅提交慣例並使用 git cliff 生成變更日誌，但實際向用戶發佈係按照較低頻率嘅手動時間表進行。
