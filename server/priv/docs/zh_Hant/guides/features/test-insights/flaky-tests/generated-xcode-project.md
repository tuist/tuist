---
{
  "title": "產生的 Xcode 專案",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 產生的 Xcode 專案中偵測、管理並隔離不穩定測試。"
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-flaky-tests}

> [!WARNING]
> **必要條件**
>
> - 已設定<.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>（自動產生的 scheme 包含 `tuist inspect test` post-action；自訂 scheme 需要手動加入）。

不穩定測試是指在使用相同程式碼多次執行時，會產生不同結果（通過或失敗）的測試。這類測試會削弱你對測試套件的信任，並浪費開發者時間調查誤報的失敗。Tuist 會自動偵測不穩定測試，並協助你持續追蹤。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測的運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能執行測試時，Tuist 會分析每次嘗試的結果。如果某個測試在某些嘗試中失敗，但在其他嘗試中通過，就會被標記為不穩定。

透過 `tuist test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![不穩定測試案例詳細資訊](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也能透過比較同一個 commit 與同一個 scheme 在不同 CI 執行中的結果來偵測不穩定測試。如果某個測試在一次 CI 執行中通過，但在同一個 commit 與 scheme 的另一次執行中失敗，這兩次執行都會被標記為不穩定。

scheme 是比較鍵的一部分，因為同一個測試在不同 scheme 下可能會以確定性但不同的方式行為——例如，僅對特定模擬器目標有效的快照測試，或以不同編譯旗標建構的測試目標。同一個 commit 在不同 scheme 上的兩次執行會被視為獨立的執行變體，不會互相標記為不穩定。

這對於捕捉那些失敗頻率不足以被重試機制抓到、但仍會造成間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測與清除會透過專案上的**自動化警示**執行。每個專案都會有一個預設的「不穩定測試偵測」自動化，其*觸發條件*會將測試標記為不穩定，而當測試在設定的恢復視窗（預設**14 天**）內未再次觸發時，其*恢復*動作會清除該標記。你可以在**設定 → 自動化**中編輯它，以變更恢復視窗、替換恢復動作（例如也解除隔離），或完全停用恢復，讓測試保持標記為不穩定，直到你手動清除為止。

### 手動管理

你也可以從測試案例詳細頁面手動將測試標記為不穩定或取消標記。這在以下情況很有用：
- 你想在修復已知不穩定測試的同時承認其存在
- 測試因基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離會將不穩定測試隔離起來，讓它在修復期間不會阻礙 CI。預設情況下，這是**手動操作**——你可以從儀表板中的測試案例詳細頁面進行隔離、解除隔離和切換模式——但你也可以將其連接到**設定 → 自動化**下的**自動化警示**，以便在測試超過不穩定閾值時自動靜音（或跳過），並在恢復時解除隔離。每次轉換，無論是手動還是自動化，都會記錄在測試案例的稽核日誌中。

預設情況下，恢復會等待直到觸發條件不再成立，因此測試會保持隔離狀態，直到其舊的不穩定執行離開觸發視窗。若要更快恢復，請將**恢復時機**設定為**無新的不穩定執行**：一旦恢復視窗（天數或執行次數）過去且沒有新的不穩定執行，測試就會恢復；每次新的不穩定執行都會重新開始等待；恢復後，只有新的不穩定執行才會再次將其隔離。

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍會執行，但 `tuist test` 會遮蔽失敗。失敗仍會提供給不穩定測試偵測器，因此你可以在不破壞建置的情況下持續觀察測試。選擇此模式用於你正在積極調查的測試。
- **跳過**：xcodebuild 會收到 `-skip-testing <identifier>`，因此測試永遠不會啟動。它不會產生新結果，並會從不穩定測試儀表板中消失，直到你重新啟用它。當測試損壞、緩慢，或不穩定程度高到執行它只是浪費 CI 分鐘數時，請選擇此模式。

### 為何被隔離的測試可能顯示為通過 {#quarantined-passing}

- **靜音測試**仍會執行。失敗的靜音測試會在測試案例執行中記錄為**失敗**並標記為不穩定——個別測試的狀態不會被改寫。被覆寫的是**整體測試執行**：如果執行中所有失敗的測試案例都是靜音的，則整個執行會被報告為通過，因此靜音失敗不會破壞 CI。
- **跳過的測試**根本不會執行，因此儀表板會繼續顯示測試最後一次實際執行的狀態——該快照可能已是數週前的資料。

### 執行測試 {#running-tests}

`tuist test` 會自動遵循這兩種模式：

```sh
tuist test
```

跳過的測試會以 `-skip-testing` 的形式傳遞給 xcodebuild，且永遠不會啟動。靜音測試會正常執行；如果它們失敗，失敗會在產生的建置狀態中被遮蔽。

若要完全繞過隔離並執行所有内容，包括靜音和跳過的測試：

```sh
tuist test --skip-quarantine
```

## 壓力測試新測試 {#stress-testing-new-tests}

壓力閘道會重新執行你的分支新增的測試案例，每個案例在全新程序中執行數次，並報告結果為不穩定的案例。你可以在引入該不穩定測試的拉取請求上看到它，而不是幾週後。

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或未在已合併至該分支的 commit 上執行時，即視為新測試案例。使用合併佇列時，佇列執行的測試案例在佇列的 commit 合併後即被知悉，若佇列將其丟棄，則保持為新測試案例。Commit 是透過 Tuist 在 CI 上收集的<.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史記錄</.localized_link>進行比對。

### 啟用方式

閘道預設為關閉。設定模式：

- **`report`**：針對每個不穩定測試案例發出警告。執行仍會以其自身結果結束。
- **`enforce`**：若存在不穩定測試案例，則執行失敗，並回傳與測試失敗相同的退出碼。

在這兩種模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link>不會在下次執行時跳過包含新的不穩定測試案例的測試目標。該目標會再次執行，閘道會再次對該測試案例進行壓力測試，直到它通過所有重新執行為止。

先使用 `report` 幾週，看看 `enforce` 會攔截哪些情況。

將其放在透傳參數之前傳遞，或設定 `TUIST_TEST_STRESS_NEW_TESTS` 以根據 CI 管道調整模式：

```sh
tuist test --stress-new-tests report
```

### 每個測試重新執行的次數

取決於測試案例在首次執行時所花費的時間：

| 首次執行 | 重新執行次數 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分鐘 | 2 |
| 超過 5 分鐘 | 不重新執行 |

重新執行會重複使用首次執行所建置的內容。當達到 200 個測試案例或 10 分鐘（以先到者為準）時，執行就會停止，並說明觸發了哪項限制。

### 閘道未執行的情況

- 首次執行已失敗。請先修復這些測試。
- 專案沒有預設分支，或其上尚未在 CI 中執行任何內容。
- 超過 30% 的專案測試案例看起來是新的。重新執行這麼多案例所花的時間將得不償失。在剛開始向 Tuist 回報的專案，或在一次重新命名移動了大量測試之後，可能會出現這種情況。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定<.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，即可在測試變得不穩定時立即收到通知。

## 查詢不穩定與隔離狀態 {#querying}

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

這些命令都接受 `--json` 以便進行腳本處理。

### REST API

相同的資料可透過 HTTP 取得——請參閱 API 參考中的[測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以取得完整的路由、篩選器和回應欄位清單。若要變更測試案例的狀態（標記或取消標記為不穩定、靜音、跳過），請傳送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` 並附上 `is_flaky` 或 `state`。相同的變更也可透過 `tuist test case update` 以及 `update_test_case` Model Context Protocol 工具進行。
