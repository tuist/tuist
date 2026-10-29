---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Flaky tests · Test insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in a Tuist-generated Xcode project."
}
---
# 產生的 Xcode 專案 {#generated-xcode-project-flaky-tests}

> [!WARNING]
> **必要條件**
>
> - 已設定 <.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>（自動產生的 scheme 包含 `tuist inspect test` post-action；自訂 scheme 需要手動加入）。

不穩定測試是指使用相同程式碼多次執行時，會產生不同結果（通過或失敗）的測試。它們會削弱你對測試套件的信任，並浪費開發人員調查虛假失敗的時間。Tuist 會自動偵測不穩定測試，並協助你隨時間追蹤它們。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測如何運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你執行具有重試功能的測試時，Tuist 會分析每次嘗試的結果。如果測試在某些嘗試中失敗，但在其他嘗試中通過，則會被標記為不穩定。

透過 `tuist test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![不穩定測試案例詳細資訊](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也可以透過比較同一個 commit 和同一個 scheme 在不同 CI 執行中的結果來偵測不穩定測試。如果測試在一次 CI 執行中通過，但在同一個 commit 和 scheme 的另一次執行中失敗，則兩次執行都會被標記為不穩定。

Scheme 是比較鍵的一部分，因為同一個測試在不同 scheme 下可能會以確定性的方式表現不同——例如，僅針對特定模擬器目的地有效的快照測試，或使用不同旗標編譯的測試目標。同一個 commit 在不同 scheme 上的兩次執行被視為獨立的執行變體，不會互相標記為不穩定。

這對於捕捉那些未能一致失敗以致無法被重試捕捉，但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和清除透過專案上的 **自動化警示** 執行。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其 *觸發條件* 會將測試標記為不穩定，而其 *恢復* 會在測試經過設定的恢復視窗（預設 **14 天**）且未重新觸發後清除標記。在 **設定 → 自動化** 下編輯它以更改恢復視窗、交換恢復動作（例如也解除隔離），或完全停用恢復，以便測試保持標記為不穩定，直到你手動清除它們。

### 手動管理

你也可以從測試案例詳細資訊頁面手動將測試標記為不穩定或取消標記。這在以下情況很有用：
- 你想在修復已知不穩定測試的同時確認它
- 由於基礎設施問題錯誤地標記了測試

## 隔離不穩定測試 {#quarantining}

隔離會將不穩定測試孤立起來，使其在你修復時不會阻塞 CI。預設情況下，這是一個 **手動動作** — 你可以從儀表板中的測試案例詳細資訊頁面進行隔離、解除隔離和切換模式 — 但你也可以將其連接到 **設定 → 自動化** 下的 **自動化警示**，以便當測試超過不穩定閾值時自動靜音（或跳過），並在恢復時解除隔離。每次轉換，無論是手動還是自動化，都會記錄在測試案例的審核日誌中。

被隔離的測試處於兩種模式之一：

- **靜音**：測試仍然執行，但 `tuist test` 會掩蓋失敗。失敗仍會饋送給不穩定測試偵測器，因此你可以在不破壞建構的情況下繼續觀察測試。選擇此選項用於你正在積極調查的測試。
- **跳過**：xcodebuild 接收 `-skip-testing <identifier>`，因此測試永遠不會啟動。它不會產生新結果，並從不穩定測試儀表板中消失，直到你重新啟用它。當測試損壞、緩慢或不穩定程度如此之高以致執行它只是浪費 CI 分鐘數時，請選擇此選項。

### 為何被隔離的測試可能顯示為通過 {#quarantined-passing}

- **靜音測試** 仍然執行。失敗的靜音測試在測試案例執行中被記錄為 **失敗** 並標記為不穩定 — 每個測試的狀態不會被重寫。被覆蓋的是 **整體測試執行**：如果執行中每個失敗的測試案例都被靜音，則整個執行會被報告為通過，因此靜音失敗不會破壞 CI。
- **跳過的測試** 根本不會運行，因此儀表板會繼續顯示測試最後一次實際執行的狀態 — 該快照可能已是幾週前的。

### 執行測試 {#running-tests}

`tuist test` 會自動尊重這兩種模式：

```sh
tuist test
```

跳過的測試作為 `-skip-testing` 傳遞給 xcodebuild 且永遠不會啟動。靜音測試正常運行；如果它們失敗，失敗會在產生的建構狀態中被掩蓋。

要完全繞過隔離並運行所有内容，包括靜音和跳過的測試：

```sh
tuist test --skip-quarantine
```

## 壓力測試新測試 {#stress-testing-new-tests}

壓力閘門會重新運行你的分支新增的測試案例，每個案例在全新的進程中運行數次，並報告結果為不穩定的案例。你會在看見引入新不穩定測試的 pull request 上立即看到它，而不是幾週後。

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中運行，或在已合併到該分支的 commit 上運行時，它被視為新測試。使用合併佇列時，佇列運行的測試案例在佇列的 commit 合併後即被知曉，如果佇列丟棄它，則保持為新測試。Commits 是透過 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史</.localized_link> 進行匹配的。

### 啟用它

閘門預設為關閉。設定模式：

- **`report`**：警告每個不穩定測試案例。執行仍會以其自身結果退出。
- **`enforce`**：不穩定的測試案例會導致執行失敗，並產生與測試失敗相同的退出代碼。

在這兩種模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">選擇性測試</.localized_link> 不會在下次執行時跳過包含不穩定新測試案例的測試目標。該目標會再次運行，而閘門會再次對測試案例進行壓力測試，直到它通過所有重新運行為止。

先使用 `report` 幾週，看看 `enforce` 會攔截什麼。

將它放在透傳參數之前，或設定 `TUIST_TEST_STRESS_NEW_TESTS` 以根據 CI 通道變更模式：

```sh
tuist test --stress-new-tests report
```

### 每個測試重新運行的次數

這取決於測試案例在第一次運行時所花的時間：

| 第一次運行 | 重新運行 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分鐘 | 2 |
| 超過 5 分鐘 | 不重新運行 |

重新運行會重用第一次運行所建構的內容。當達到 200 個測試案例或 10 分鐘（以先到者為準）時，運行就會停止，並說明達到了哪個限制。

### 何時不運行閘門

- 第一次運行已經失敗。請先修復這些測試。
- 專案沒有預設分支，或者尚未在其上運行任何 CI。
- 超過 30% 的專案測試案例看起來是新的。重新運行這麼多案例會得不償失。在剛開始向 Tuist 報告的專案上，或在一次重新命名移動了大量測試後，預計會出現這種情況。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警報</.localized_link>，在測試變得不穩定時立即收到通知。

## 查詢不穩定和隔離狀態 {#querying}

### CLI

`tuist test case` 命令樹顯示 Tuist 追蹤有關測試案例的所有資訊：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有這些都接受 `--json` 用於腳本編寫。

### REST API

相同的數據可透過 HTTP 取得 — 請參閱 API 參考中的 [測試案例端點](https://tuist.dev/api/docs#tag/test-cases) 以獲取完整的路由、過濾器和回應欄位清單。若要變更測試案例的狀態（標記或取消標記為不穩定、靜音、跳過），請發送帶有 `is_flaky` 或 `state` 的 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`。相同的變更也可作為 `tuist test case update` 和 `update_test_case` Model Context Protocol 工具使用。
