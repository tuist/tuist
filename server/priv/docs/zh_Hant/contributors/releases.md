---
{
  "title": "版本發布",
  "titleTemplate": ":title | 貢獻者 | Tuist",
  "description": "了解 Tuist 的持續發布流程如何運作"
}
---
# 版本發布

當變更合併至 main 分支時，Tuist 會自動發布新版本。CLI、伺服器與 Kura 快取伺服器皆透過發布管道（canary、候選版本、穩定版）交付，讓建議安裝版本保持穩定且更新節奏較慢；切割候選版本並將其提升為穩定版是每週刻意執行的步驟。應用程式持續發布（iOS 應用程式僅持續部署至 TestFlight，詳情請見[此處](#app-store-release)）。

## 概覽

我們發布以下主要元件：
- **Tuist CLI** - 命令列工具，透過 canary、候選版本與穩定[管道](#release-channels)交付
- **Tuist Server** - 後端服務，採用與 CLI 相同的管道模型交付
- **Kura** - 快取伺服器，採用與 CLI 相同的管道模型交付
- **Tuist App** - macOS 與 iOS 應用程式，持續發布（iOS 應用程式僅持續部署至 TestFlight，詳情請見[此處](#app-store-release)）

每次推送至 `main` 都會為 CLI、伺服器與 Kura 發布 canary 預發布版本。這些元件的穩定版本僅在維護者將經過充分驗證的候選版本提升時才會切割，而每週排程會讓三條發布列車同步推進（參閱[發布管道](#release-channels)）。應用程式在每次推送至 `main` 時都會發布穩定版。

## 運作方式

### 1. 提交規範

我們使用[Conventional Commits](https://www.conventionalcommits.org/)來組織提交訊息。這讓我們的工具能夠理解變更性質、決定版本遞增，並產生適當的變更記錄。

格式：`type(scope): description`

#### 提交類型及其影響

| 類型 | 說明 | 版本影響 | 範例 |
|------|-------------|----------------|---------|
| `feat` | 新功能或能力 | 次要版本遞增（x.Y.z） | `feat(cli): add support for Swift 6` |
| `fix` | 錯誤修正 | 修補版本遞增（x.y.Z） | `fix(app): resolve crash when opening projects` |
| `docs` | 文件變更 | 不發布 | `docs: update installation guide` |
| `style` | 程式碼風格變更 | 不發布 | `style: format code with swiftformat` |
| `refactor` | 程式碼重構 | 不發布 | `refactor(server): simplify auth logic` |
| `perf` | 效能改善 | 修補版本遞增 | `perf(cli): optimize dependency resolution` |
| `test` | 測試新增/變更 | 不發布 | `test: add unit tests for cache` |
| `chore` | 維護工作 | 不發布 | `chore: update dependencies` |
| `ci` | CI/CD 變更 | 不發布 | `ci: add workflow for releases` |

對 CLI 而言，這些遞增決定 canary 版本與變更記錄的分組。穩定的 CLI 版本是由人工切割的次要版本線（`X.Y.0`），而穩定修補版本（`X.Y.Z`）僅來自回溯移植，因此`feat`或`fix`會透過下方的管道流程觸達 CLI 使用者，而非立即作為穩定版本發布。

#### 破壞性變更

破壞性變更會觸發主要版本遞增（X.0.0），並應在提交內文中標示：

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. 變更偵測

每個元件都使用[git cliff](https://git-cliff.org/)來：
- 分析自上次發布以來的提交
- 依範圍篩選提交（cli、app、server）
- 判斷是否有可發布的變更
- 自動產生變更記錄

### 3. 發布流程

當偵測到可發布的變更時：

1. **版本計算**：流程決定下一個版本號碼
2. **產生變更記錄**：git cliff 根據提交訊息建立變更記錄
3. **建置流程**：建置並測試元件
4. **產生物件**：產生發布專屬資產，例如 CLI 套件、檢查碼，以及由`tuist --experimental-dump-help`產生的`tuist.spec.json`CLI 規格
5. **建立發布**：建立包含物件的 GitHub 發布
6. **分發**：將更新推送至套件管理器（例如 CLI 的 Homebrew）

對應用程式而言，每次合併都會產生穩定版本。對 CLI、伺服器與 Kura 而言，相同的自動化流程僅產生**canary**預發布版本；候選版本與穩定版本會在每週發布列車上切割（參閱[發布管道](#release-channels)）。

### 4. 範圍篩選

每個元件僅在有相關變更時才會發布：

- **CLI**：帶有`(cli)`範圍或無範圍的提交
- **App**：帶有`(app)`範圍的提交
- **Server**：帶有`(server)`範圍的提交

## 發布管道

CLI、伺服器與 Kura 不會在每次推送至`main`時都提升為穩定版本。每個元件都透過三個管道交付，讓建議安裝版本保持穩定且變動緩慢，同時讓早期採用者保留每次提交的建置版本。使用者文件位於<.localized_link href="/cli/release-channels">CLI 發布管道</.localized_link>與<.localized_link href="/guides/server/self-host/release-channels">伺服器發布管道</.localized_link>；本節是維護者操作手冊。

每個元件都使用相同的三個管道：

| 管道 | 版本 | 切割方式 |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | 自動執行，在每次影響元件的推送至`main`時（`<component>-release.yml`；對 Kura 而言，當`kura/`變更時由`server-production-deployment.yml`呼叫） |
| 候選版本 | `X.Y.0-rc.N` | 每週一，或手動在`releases/<component>-<major>.<minor>.x`分支上執行（`<component>-rc.yml`） |
| 穩定版 | `X.Y.Z` | 每週一，或手動提升經過充分驗證的候選版本（`<component>-promote.yml`）；修補版本透過`<component>-backport.yml` |

Canary 與 RC 建置會以 GitHub 預發布形式發布（絕不標記為「Latest」，絕不在 GHCR 上移動`:latest`，絕不推送至 CLI 的 Homebrew），因此套件管理器與映像解析器僅在明確選擇加入時才會採用。Canary 始終鎖定下一個尚未發布的次要版本：一旦切割出 RC 線，`main`的 canary 就會推進至下一個次要版本。

託管 Tuist 不會等待穩定列車：伺服器按每次提交部署，而託管 canary 與生產環境執行最新的 Kura canary。部署串聯會在部署前先發布該 canary，因此`kura-release.yml`沒有自己的觸發條件。僅對 Kura 發布工具鏈的變更（`mise/tasks/kura/**`、`kura-*.yml`工作流程）不會切割 canary。

你從不手動挑選版本號碼。每個管道的下一個版本都由`mise/tasks/<component>/release/channel-version.sh`從現有的 git 標籤衍生而來，下方的工作流程會叫用它。

發布分支按元件進行命名空間隔離（`releases/server-X.Y.x`、`releases/kura-X.Y.x`、CLI 的`releases/X.Y.x`），因此三個元件的線路永遠不會在同一個次要版本上衝突。

### 每週排程

每週一 UTC 06:00，三個元件的提升作業會同步執行：**CLI 提升至穩定版**、**伺服器提升至穩定版**與**Kura 提升至穩定版**。每個作業都會提升最新尚未穩定的 RC 線，通常是上週一切割的線路。若沒有這樣的線路，該作業就不會發布任何內容。

當提升完成時，無論結果為何，其對應的**候選版本**工作流程（`cli-rc.yml`、`server-rc.yml`、`kura-rc.yml`）會透過`workflow_run`觸發，並從`main`切割下一條線路。

若任何預定執行失敗或被取消，系統會將訊息張貼至 Slack。當發布分支在其最新 RC 之後還有提交時，提升會失敗。若要發布該線路，請在其上切割新的 RC 並手動提升。否則，下週一會改為提升較新的線路。

### 切割候選版本

若要在每週排程之外切割新線路（請替換下方元件的工作流程名稱）：

1. 以空的`branch`輸入執行 **\<Component\> 候選版本**工作流程（例如`server-rc.yml`）。
2. 它會發布`X.Y.0-rc.1`，並在成功後於已建置的提交處建立受保護的`releases/<component>-X.Y.x`分支。

若要將關鍵修正或回歸問題拉入驗證中的線路，請透過 PR 將其 cherry-pick 到發布分支（與回溯移植的流程相同；CI 從不進行 cherry-pick），然後迭代 RC：

1. 從`releases/<component>-X.Y.x`建立分支，cherry-pick 該修正，開啟一個合併回發布分支的 PR，解決其中的任何衝突，然後合併。
2. 再次使用`branch=releases/<component>-X.Y.x`執行**候選版本**工作流程。它會從分支 HEAD 發布`X.Y.0-rc.(N+1)`。

驗證中的線路會凍結功能：只有關鍵修正和回歸問題才會進入該線路。

### 提升至穩定版

若要在每週排程之外提升線路，請在其 RC 經過充分驗證後：

1. 使用`branch=releases/<component>-X.Y.x`執行 **\<Component\> 提升至穩定版**工作流程（例如`server-promote.yml`）。
2. 它會使用`make_latest=true`發布帶有語意化版本標籤的映像，移動 GHCR 的`:latest`標籤和 GitHub 的「Latest」指標。CLI 還會額外更新 Homebrew formula。

除非分支 HEAD 正好是最新 RC 指向的提交，否則提升作業拒絕執行。因此，若在最後一個 RC 之後有任何修正合併到該線路，你必須切割新的 RC 並讓其經過驗證，才能作為穩定版發布。

### 將修正回溯移植到穩定線路

一旦線路穩定，就使用僅限 CLI 的**回溯移植發布**工作流程（`cli-backport.yml`）來發布修補版本：透過 PR 將修正 cherry-pick 到`releases/X.Y.x`，然後使用該分支執行工作流程以切割`X.Y.(Z+1)`。回溯移植絕不會移動「Latest」指標或 Homebrew formula。同時維護兩條線路：當前線路接受回歸問題和安全修正，前一條線路僅接受關鍵和安全修正。其他錯誤修正不會回溯移植，而是隨下一個次要版本發布。

對於伺服器和 Kura，請使用**伺服器回溯移植發布**（`server-backport.yml`）或**Kura 回溯移植發布**（`kura-backport.yml`）。提升作業僅發布 RC 的`X.Y.0`；它無法修補已穩定的線路。

1. 從所選`X.Y`線路上最新發布的穩定元件標籤開始，並向其現有的`releases/server-X.Y.x`或`releases/kura-X.Y.x`分支開啟精準修正 PR。較新的次要或主要版本發布不會阻止對維護中線路的修補。請排除與 main 無關的變更。
2. 審查並合併來源 PR。抓取遠端發布分支並確認其**最終合併頂端**，包括元件支援的平台和 TLS 正負控制項。通過預合併檢查的頭部並不代表對不同 squash 或合併提交的確認。
3. 在獲得獨立的發布核准後，從 main 分派對應的回溯移植工作流程（**從 main**），將`source_sha`設為該精確合格的合併尖端，並將`base_tag`設為目前的穩定標籤，例如`server@X.Y.Z`或`kura@X.Y.Z`。工作流程會推導出`X.Y.(Z+1)`；操作人員不得選擇次要版本升級或提升 canary 內容。

規劃會刷新精確的遠端分支和基礎標籤，要求所選來源等於分支頂端，拒絕未變動的來源或元件之外的變更、其信任策略輸入和驗證，並鎖定已解析的基础提交。來自 main 的控制項會在版本化映像和 GitHub 發布之前立即重複這些檢查。如果來源分支、穩定基礎或可用版本發生變化，請停止並重新確認，而不是替換新的來源。

回溯移植使用現有的多平台發布器，而不移動 GitHub 的「Latest」指標或 GHCR `:latest`。發布與託管部署是分開的：這些工作流程不會提升託管伺服器或 Kura 艦隊，不會繞過 canary 接受檢查，也不會確認已安裝的執行環境。建置輔助工具和 Dockerfile 仍然來自所選的穩定來源。這些控制項是發布閘門，而非免憑證的建置作業；建置可以在最終閘門之前上傳未標記的映像摘要。映像和 GitHub 發布並非原子操作：如果在映像標籤發布後後續閘門失敗，請檢查部分發布並保留其原始來源和構件。切勿替換現有發布或在其標籤下使用不同的位元組。

## 撰寫良好的提交訊息

由於提交訊息直接影響發布說明，因此撰寫清晰、具描述性的訊息至關重要：

### 建議做法：
- 使用現在式：「add feature」而非「added feature」
- 簡潔但具描述性
- 當變更僅限於特定元件時，包含範圍
- 在適用時參考議題：`fix(cli): resolve build cache issue (#1234)`

### 避免做法：
- 使用模糊的訊息，如「fix bug」或「update code」
- 在一次提交中混合多個不相關的變更
- 忘記包含重大變更資訊

### 重大變更

對於重大變更，請在提交主體中包含`BREAKING CHANGE:`：

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## 發布工作流程

CLI、伺服器和 Kura 各自擁有一組管道工作流程，遵循相同的結構：

- `<component>-release.yml` - 在每次觸及元件的推送到`main`時發布 canary（Kura 的是可重複使用的工作流程，當`kura/`變更時由`server-production-deployment.yml`呼叫）
- `<component>-rc.yml` - 每週一切割候選版本（透過提升後的`workflow_run`），或手動切割或迭代
- `<component>-promote.yml` - 每週一 UTC 06:00 將待處理的 RC 提升至穩定版，或手動提升經過驗證的 RC
- `<component>-build-publish.yml` - 上述三者呼叫的共用建置和發布管道

CLI、伺服器和 Kura 另外擁有`<component>-backport.yml`，用於在穩定線路上切割修補版本。元件的所有工作流程都透過一個`<component>-publish`並行群組序列化，因此版本解析和標籤設定永遠不會競爭。Kura 是例外：其 canary 使用`kura-canary-publish`，而其 RC、提升和回溯移植使用`kura-stable-publish`，因此長時間的穩定建置永遠不會阻礙部署串聯。標籤命名空間不相交，因此這兩個群組不會衝突。

Helm Chart 和基礎設施映像（CAPI operator、runners controller、xcresult processor image、linux runner image 等）仍透過`.github/workflows/server-production-deployment.yml`發布。它在推送到`main`時執行，並為託管部署串聯 canary → 驗收測試 → 生產環境，並在這些基礎設施元件變更時發布它們。App、快取、Gradle 外掛程式、skills、Noora 和獨立的基礎設施控制器各自擁有專用的`*-release.yml`工作流程。它們都共用變更偵測：`mise/tasks/release/components.json`宣告每個元件的標籤前綴和包含路徑，而 git cliff 將符合的提交轉換為發布說明。

CLI 建置（`cli-build-publish.yml`）也會產生並發布`tuist.spec.json`成品（由`tuist --experimental-dump-help`產生），以便下游工具可以使用命令介面。

## 監控發布

你可以透過以下方式監控發布：
- [GitHub Releases 頁面](https://github.com/tuist/tuist/releases)
- GitHub Actions 分頁中的工作流程執行紀錄
- 每個元件目錄中的變更記錄檔案

## 效益

這種持續發布方法提供：

- **快速交付**：變更在合併後立即送達使用者
- **減少瓶頸**：無需等待手動發布
- **清晰溝通**：從提交訊息自動產生變更記錄
- **一致的流程**：所有元件使用相同的發布流程
- **品質保證**：僅發布經過測試的變更

## 疑難排解

如果發布失敗：

1. 檢查失敗工作流程的 GitHub Actions 日誌
2. 確保你的提交訊息遵循慣例格式
3. 驗證所有測試皆通過
4. 檢查元件是否成功建置

對於需要立即發布的緊急修復：
1. 確保你的提交具有明確的範圍
2. 合併後，監控發布工作流程
3. 對於伺服器或 App，修復會在下次推送時交付；如有需要，觸發手動發布
4. 對於 CLI，修復會自動進入 canary。若要讓穩定版使用者取得，請將其回溯移植到維護中的穩定線路（參閱[將修復回溯移植到穩定線路](#backporting-fixes-to-a-stable-line)）

## App Store 發布

雖然 CLI 和伺服器遵循上述的持續發布流程，但由於 Apple 的 App Store 審查流程，**iOS App**是例外：

- **手動發布**：iOS App 發布需要手動提交至 App Store
- **審查延遲**：每次發布都必須經過 Apple 的審查流程，可能需要 1-7 天
- **批次變更**：多個變更通常會捆綁在一起，在每次 iOS 發布中一起推出
- **TestFlight**：Beta 版本可能在 App Store 發布前透過 TestFlight 分發
- **發布說明**：必須根據 App Store 指南專門撰寫

iOS App 仍然遵循相同的提交慣例，並使用 git cliff 產生變更記錄，但實際向用戶發布的频率較低，且採用手動排程。
