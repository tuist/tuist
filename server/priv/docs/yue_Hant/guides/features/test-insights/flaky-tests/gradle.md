---
{
  "title": "Gradle Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Gradle projects with Tuist."
}
---
# Gradle 不穩定測試 {#gradle-flaky-tests}

不穩定測試是指在相同程式碼下多次執行時會產生不同結果（通過或失敗）的測試。它們會削弱你對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助你隨時間追蹤它們。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測如何運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能執行測試時，Tuist 會分析每次嘗試的結果。如果某個測試在某些嘗試中失敗，但在其他嘗試中通過，則會被標記為不穩定。

你可以使用 [Test Retry 外掛程式](https://github.com/gradle/test-retry-gradle-plugin) 或類似機制來重新執行失敗的測試。Tuist 會偵測到那些在某些嘗試中通過但在其他嘗試中失敗的測試。

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

![不穩定測試案例詳情](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也能透過比較同一個 commit 和同一個 Gradle 專案在不同 CI 執行中的結果來偵測不穩定測試。如果某個測試在一次 CI 執行中通過，但在同一個 commit 和專案的另一次執行中失敗，則這兩次執行都會被標記為不穩定。

Gradle 專案是比較鍵的一部分，因為同一個測試在不同專案中可能會以確定性但不同的方式表現——例如，一個共用測試類別以不同的依賴關係編譯，或在不同的模組 fixture 上執行。同一個 commit 在不同 Gradle 專案上的兩次執行會被視為獨立的執行變體，不會互相標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試捕捉、但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和清除是透過專案上的 **自動化警示** 進行。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其 *觸發條件* 會將測試標記為不穩定，而其 *恢復* 則會在測試經過設定的恢復視窗（預設 **14 天**）且未再次觸發後清除標記。你可以在 **設定 → 自動化** 下編輯它，以更改恢復視窗、交換恢復動作（例如也解除隔離），或完全停用恢復，讓測試保持標記為不穩定，直到你手動清除它們。

### 手動管理

你也可以從測試案例詳情頁面手動將測試標記為不穩定或取消標記。這在以下情況很有用：
- 你想在修復已知不穩定測試的同時確認它
- 由於基礎設施問題，測試被錯誤地標記

## 隔離不穩定測試 {#quarantining}

隔離會將不穩定測試隔離起來，使其在你修復時不會阻擋 CI。預設情況下，這是一個 **手動動作**——你可以從儀表板中的測試案例詳情頁面進行隔離、解除隔離和切換模式——但你也可以將其連接到 **設定 → 自動化** 下的 **自動化警示**，以便當測試超過不穩定閾值時自動靜音（或跳過），並在恢復時解除隔離。每次轉換，無論是手動還是自動，都會記錄在測試案例的稽核日誌中。

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍然執行，但外掛程式會設定 `ignoreFailures = true`，並且只在非隔離失敗時才使建構失敗。失敗仍會饋送至不穩定測試偵測器，因此你可以持續監控測試而不會破壞建構。選擇此模式用於你正在積極調查的測試。
- **跳過**：外掛程式會透過 Gradle 的 `excludeTestsMatching` 過濾掉測試，使其永遠不會啟動。它不會產生新結果，並會從不穩定測試儀表板中消失，直到你重新啟用它。當測試損壞、緩慢或不穩定程度如此持久以致於執行它只是浪費 CI 分鐘數時，請選擇此模式。

### 為什麼被隔離的測試可能顯示為通過 {#quarantined-passing}

- **靜音測試** 仍然執行。失敗的靜音測試會在測試案例執行中被記錄為 **失敗** 並標記為不穩定——每個測試的狀態不會被覆寫。被覆寫的是 **整體測試執行**：如果執行中每個失敗的測試案例都被靜音，則整個執行會被報告為通過，因此靜音失敗不會破壞 CI。
- **跳過的測試** 根本不會執行，因此儀表板會繼續顯示測試最後一次實際執行的狀態——該快照可能是幾週前的。

### 啟用隔離 {#enabling-quarantine}

隔離在 CI 上**自動啟用**（當設定 `CI` 環境變數時），並在本地建構中停用。外掛程式會在每個測試任務之前從 Tuist 伺服器獲取隔離測試清單；靜音測試正常執行並遮蔽其失敗，跳過的測試則被過濾掉。

你可以在你的 `settings.gradle.kts` 中明確控制這一點：

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

當未設定 `enabled` 時，預設為自動偵測：在 CI 上啟用，在本地停用。

## 壓力測試新測試 {#stress-testing-new-tests}

壓力閘門會重新執行你的分支新增的測試案例，每個案例在全新的程序中執行數次，並報告那些結果為不穩定的案例。你可以在引入它的 pull request 上看到新的不穩定測試，而不是幾週後。

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或未在已合併到該分支的 commit 上執行時，即視為新測試案例。使用合併佇列時，一旦佇列的 commit 合併，佇列執行的測試案例即被識別，如果佇列將其丟棄，則保持為新測試案例。Commit 是透過 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/gradle#git-history">Git 歷史</.localized_link> 進行匹配的。

### 啟用

閘門預設為關閉。設定模式：

- **`report`**：警告每個不穩定測試案例。執行仍會以其自身結果結束。
- **`enforce`**：不穩定測試案例會使執行失敗，退出碼與失敗測試相同。

先使用 `report` 幾週，看看 `enforce` 會攔截什麼。

在 `settings.gradle.kts` 中宣告，或設定 `TUIST_TEST_STRESS_NEW_TESTS` 以針對每個 CI 通道變更模式：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

與隔離不同，此閘門沒有感知 CI 的預設值。若未設定 `mode`，它不會在任何地方執行。

### 每個測試重新執行的次數

這取決於測試案例在第一次執行時所花的時間：

| 第一次執行 | 重新執行 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分鐘 | 2 |
| 超過 5 分鐘 | 不重新執行 |

每次重新執行都是針對該單一測試案例過濾的巢狀 Gradle 建構，因此每次重新執行都會獲得全新的測試 JVM。當達到 200 個測試案例或 10 分鐘時（以先到者為準），執行就會停止，並指出觸發了哪個限制。

### 閘門不執行的情況

- 第一次執行已經失敗。請先修復這些測試。
- 專案沒有預設分支，或者尚未在其上於 CI 中執行任何內容。
- 超過 30% 的專案測試案例看起來是新的。重新執行這麼多案例會得不償失。在剛開始向 Tuist 報告的專案，或在一次重新命名移動了大量測試之後，可能會出現這種情況。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，在測試變得不穩定時立即收到通知。

## 查詢不穩定和隔離狀態 {#querying}

### CLI

`tuist test case` 命令樹公開 Tuist 追蹤關於測試案例的所有資訊：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有這些都接受 `--json` 以進行腳本化。

### REST API

相同的資料可透過 HTTP 取得——請參閱 API 參考中的 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases) 以獲取完整的路由、篩選器和回應欄位清單。若要變更測試案例的狀態（標記或取消標記為不穩定、靜音、跳過），請發送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 並附上 `is_flaky` 或 `state`。相同的變更也可透過 `tuist test case update` 以及 `update_test_case` Model Context Protocol 工具進行。
