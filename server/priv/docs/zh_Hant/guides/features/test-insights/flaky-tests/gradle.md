---
{
  "title": "Gradle 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 偵測、管理並隔離 Gradle 專案中的不穩定測試。"
}
---
# Gradle 不穩定測試 {#gradle-flaky-tests}

不穩定測試是指在使用相同程式碼多次執行時，會產生不同結果（通過或失敗）的測試。這類測試會侵蝕你對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助你長期追蹤。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定測試偵測運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能執行測試時，Tuist 會分析每次嘗試的結果。如果某個測試在部分嘗試中失敗，但在其他嘗試中通過，就會被標記為不穩定。

你可以使用 [Test Retry 外掛程式](https://github.com/gradle/test-retry-gradle-plugin) 或類似機制來重新執行失敗的測試。Tuist 會偵測到那些在部分嘗試中通過、但在其他嘗試中失敗的測試。

將外掛程式加入你的 `build.gradle.kts`：

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![不穩定測試案例詳細資訊](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也能透過比較同一個提交與同一個 Gradle 專案在不同 CI 執行中的結果，來偵測不穩定測試。如果某個測試在一次 CI 執行中通過，但在同一個提交與專案的另一次執行中失敗，這兩次執行都會被標記為不穩定。

Gradle 專案是比較鍵的一部分，因為相同的測試在不同專案中可能以確定性但不同的方式行為——例如，一個共用測試類別使用不同的相依性編譯，或在不同的模組固定裝置上執行。同一個提交在不同 Gradle 專案上的兩次執行會被視為獨立的執行變體，不會互相標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試機制捕捉，但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測與清除是透過專案上的 **自動化警示** 來執行。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其 *觸發條件* 會將測試標記為不穩定，而其 *復原* 會在測試於設定的復原視窗（預設 **14 天**）內未再次觸發後清除標記。你可以在 **設定 → 自動化** 下編輯它，以變更復原視窗、替換復原動作（例如也解除隔離），或完全停用復原，讓測試保持標記為不穩定，直到你手動清除為止。

### 手動管理

你也可以從測試案例詳細資訊頁面手動將測試標記為不穩定或取消標記。這在以下情況很有用：
- 你想在修復已知不穩定測試的同時承認其狀態
- 測試因基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離會將不穩定測試孤立起來，使其在你修復期間不會阻礙 CI。預設情況下，這是一個 **手動動作**——你可以從儀表板中的測試案例詳細資訊頁面進行隔離、解除隔離和切換模式——但你也可以將其連接到 **設定 → 自動化** 下的 **自動化警示**，這樣當測試超過不穩定閾值時會自動靜音（或跳過），並在復原時解除隔離。每一次轉換，無論是手動還是自動化，都會記錄在測試案例的稽核日誌中。

預設情況下，復原會等待直到觸發條件不再成立，因此測試會保持隔離狀態，直到其舊的不穩定執行離開觸發視窗。若要更快復原，請將 **復原時機** 設為 **無新的不穩定執行**：一旦復原視窗（天數或執行次數）過去且沒有新的不穩定執行，測試就會復原；每個新的不穩定執行都會重新開始這段等待；復原後，只有新的不穩定執行才會再次將其隔離。

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍會執行，但外掛程式會設定 `ignoreFailures = true`，並且僅在非隔離測試失敗時才讓建置失敗。失敗仍會提供給不穩定測試偵測器，因此你可以持續觀察該測試而不中斷建置。選擇此模式適用於你正在積極調查的測試。
- **跳過**：外掛程式會透過 Gradle 的 `excludeTestsMatching` 將測試過濾掉，因此它根本不會啟動。它不會產生新結果，並會從不穩定測試儀表板中消失，直到你重新啟用它。當測試損壞、緩慢，或不穩定程度高到執行它只是浪費 CI 分鐘數時，請選擇此模式。

### 為何被隔離的測試可能顯示為通過 {#quarantined-passing}

- **靜音測試** 仍會執行。失敗的靜音測試會在測試案例執行中被記錄為 **失敗** 並標記為不穩定——個別測試的狀態不會被覆寫。被覆寫的是 **整體測試執行**：如果執行中每個失敗的測試案例都是靜音的，則整個執行會被報告為通過，因此靜音失敗不會中斷 CI。
- **跳過的測試** 根本不會執行，因此儀表板會繼續顯示該測試最後一次實際執行的狀態——該快照可能已是數週前的資料。

### 啟用隔離 {#enabling-quarantine}

隔離會在 **CI 上自動啟用**（當設定 `CI` 環境變數時），並在本機建置中停用。外掛程式會在每個測試任務之前從 Tuist 伺服器取得被隔離測試的清單；靜音測試會正常執行並遮蔽其失敗，跳過的測試則會被過濾掉。

你可以在你的 `settings.gradle.kts` 中明確控制此設定：

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

當未設定 `enabled` 時，預設為自動偵測：在 CI 上啟用，在本機停用。

## 壓力測試新測試 {#stress-testing-new-tests}

壓力閘道會重新執行你的分支新增的測試案例，每個案例在全新程序中執行數次，並回報結果為不穩定的案例。你可以在引入新不穩定測試的拉取請求上看到它，而不是幾週後。

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或未在已合併至該分支的提交上執行時，即視為新測試案例。使用合併佇列時，佇列執行的測試案例在佇列的提交合併後即被識別，若佇列將其移除，則保持為新測試案例。提交是透過 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/gradle#git-history">Git 歷史</.localized_link> 進行比對。

### 啟用方式

閘道預設為關閉。設定一種模式：

- **`report`**：警告每個不穩定測試案例。執行仍會以其自身結果結束。
- **`enforce`**：不穩定測試案例會導致執行失敗，並使用與失敗測試相同的結束代碼。

先使用 `report` 幾週，看看 `enforce` 會阻擋哪些情況。

在 `settings.gradle.kts` 中宣告，或設定 `TUIST_TEST_STRESS_NEW_TESTS` 以針對不同 CI 管線變更模式：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

與隔離不同，此閘道沒有感知 CI 的預設值。若未設定 `mode`，則不會在任何地方執行。

### 每個測試重新執行的次數

取決於測試案例在首次執行時所花的時間：

| 首次執行 | 重新執行次數 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分鐘 | 2 |
| 超過 5 分鐘 | 不重新執行 |

每次重新執行都是針對單一測試案例過濾的巢狀 Gradle 建置，因此每次重新執行都會獲得全新的測試 JVM。當達到 200 個測試案例或 10 分鐘時（以先到者為準），執行就會停止，並說明觸發了哪項限制。

### 閘道不執行的情況

- 首次執行已經失敗。請先修復這些測試。
- 專案沒有預設分支，或尚未在其上於 CI 中執行任何內容。
- 超過 30% 的專案測試案例看起來是新的。重新執行這麼多案例會耗費過多時間而不值得。這通常發生在剛開始向 Tuist 回報的專案，或在一次重新命名移動了大量測試之後。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，在測試變為不穩定時立即收到通知。

## 查詢不穩定與隔離狀態 {#querying}

### CLI

`tuist test case` 命令樹公開了 Tuist 追蹤測試案例的所有資訊：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

這些命令都接受 `--json` 以便進行腳本化處理。

### REST API

相同的資料可透過 HTTP 取得——請參閱 API 參考中的 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases) 以獲取完整的路由、篩選器和回應欄位清單。若要變更測試案例的狀態（標記或取消標記為不穩定、靜音、跳過），請發送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 並附上 `is_flaky` 或 `state`。相同的變更也可透過 `tuist test case update` 以及 `update_test_case` Model Context Protocol 工具進行。
