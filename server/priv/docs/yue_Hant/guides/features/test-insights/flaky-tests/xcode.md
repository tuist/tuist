---
{
  "title": "Xcode Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in Xcode projects with Tuist."
}
---
# Xcode 不穩定測試 {#xcode-flaky-tests}

> [!WARNING]
> **必要條件**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>已設定。Tuist 會從每次測試運行上傳的測試洞察事件中偵測不穩定測試。

不穩定測試是指在相同程式碼下多次運行時會產生不同結果（通過或失敗）的測試。它們會削弱你對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助你長期追蹤它們。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測如何運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能運行測試時，Tuist 會分析每次嘗試的結果。如果某個測試在某些嘗試中失敗，但在其他嘗試中通過，則會被標記為不穩定。

透過 `tuist xcodebuild test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不穩定測試案例詳細資訊](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨運行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 仍可透過比較同一提交、scheme 和報告目的地（裝置名稱、平台和作業系統版本）的不同 CI 運行結果來偵測不穩定測試。如果某個測試在一個相符的 CI 運行中通過，但在另一個中失敗，則該失敗的執行會被標記為不穩定。無論哪個結果先到達，此機制皆有效。

同一個測試在不同 scheme 或目的地之間的行為可能持續不同。例如，在 iOS 26 上通過而在 iOS 27 上失敗，並不構成不穩定性。來自不同 scheme、裝置、平台或作業系統版本的結果不會互相標記為不穩定。

無法歸因於特定目的地的結果會與其他未歸因結果進行比較，並與已知目的地的結果分開處理。這包括缺少或不完整目的地中繼資料的報告，以及包含多個不同目的地的報告，因為個別測試結果尚無法歸因於特定目的地。此群組中環境之間的差異仍可能產生錯誤的不穩定分類。基於重試的偵測仍然適用。現有的歷史不穩定分類保持不變。

這對於捕捉那些未能一致失敗以致無法被重試捕捉，但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和清除透過專案上的**自動化警示**執行。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其*觸發條件*會將測試標記為不穩定，而其*恢復*會在測試經過設定的恢復視窗（預設**14 天**）且未重新觸發後清除標記。在**設定 → 自動化**下編輯它以更改恢復視窗、交換恢復動作（例如也解除隔離），或完全停用恢復，以便測試保持標記為不穩定，直到你手動清除它們。

### 手動管理

你也可以從測試案例詳細資訊頁面手動將測試標記為不穩定或取消標記。這在以下情況很有用：
- 你想在修復已知不穩定測試的同時確認它
- 由於基礎設施問題而錯誤地標記了測試

## 隔離不穩定測試 {#quarantining}

隔離會將不穩定測試孤立起來，使其在你修復時不會阻礙 CI。預設情況下，這是一項**手動操作** — 你可以從儀表板中的測試案例詳細資訊頁面進行隔離、解除隔離和切換模式 — 但你也可以將其連接到**設定 → 自動化**下的**自動化警示**，以便當測試超過不穩定閾值時自動靜音（或跳過），並在恢復時解除隔離。每次轉換，無論是手動還是自動化，都會記錄在測試案例的審核日誌中。

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍然運行，但`tuist xcodebuild test`會掩蓋失敗。失敗仍會輸入不穩定測試偵測器，因此你可以繼續監視測試而不破壞建置。選擇此模式用於你正在積極調查的測試。
- **跳過**：xcodebuild 會收到`-skip-testing <identifier>`，因此測試永遠不會開始。它不會產生新結果，並會從不穩定測試儀表板中消失，直到你重新啟用它。當測試損壞、緩慢或不穩定性持續到運行它只是浪費 CI 分鐘數時，請選擇此模式。

### 為何被隔離的測試可能顯示為通過 {#quarantined-passing}

- **靜音測試**仍然執行。失敗的靜音測試會在測試案例運行中被記錄為**失敗**並標記為不穩定 — 每個測試的狀態不會被改寫。被覆蓋的是**整體測試運行**：如果運行中每個失敗的測試案例都被靜音，則整個運行會被報告為通過，因此靜音失敗不會破壞 CI。
- **跳過的測試**根本不會運行，因此儀表板會繼續顯示測試最後一次實際執行的狀態 — 該快照可能已是數週前的。

### 運行測試 {#running-tests}

`tuist xcodebuild test`是一個直通包裝器，會自動尊重這兩種模式。以與呼叫 xcodebuild 相同的方式使用它：

```sh
tuist xcodebuild test -scheme MyScheme
```

跳過的測試會作為`-skip-testing <identifier>`附加到你的 xcodebuild 調用中，並且永遠不會開始。靜音測試正常運行；如果它們失敗，失敗會在產生的建置狀態中被掩蓋。

#### 繞過隔離

`tuist xcodebuild test`接受`--skip-quarantine`以運行所有內容，包括靜音和跳過的測試：

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### 直接呼叫 xcodebuild

如果你無法透過`tuist xcodebuild test`，請使用`tuist test case list`自行將隔離的測試擴展為`-skip-testing`參數：

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

這是`tuist xcodebuild test`之外的安全預設值：靜音測試的失敗掩蓋僅在你透過該命令時發生，因此跳過這兩種模式可以避免虛假的 CI 失敗。如果你需要更精細的控制，請改用`tuist xcodebuild test`。

## 壓力測試新測試 {#stress-testing-new-tests}

壓力閘門會重新運行你的分支新增的測試案例，每個測試在全新進程中運行數次，並報告結果不穩定的測試。你可以在引入該測試的拉取請求上看到新的不穩定測試，而不是幾週後。

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中運行，或未在已合併至該分支的提交中運行時，即視為新測試。使用合併佇列時，佇列運行的測試案例會在佇列的提交合併後被識別，如果佇列將其移除，則保持為新測試。提交是透過 Tuist 在 CI 上收集的<.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史記錄</.localized_link>進行比對。

### 啟用功能

閘門預設為關閉狀態。設定模式：

- **`report`**：警告每個不穩定的測試案例。運行仍會以其自身結果退出。
- **`enforce`**：不穩定的測試案例會導致運行失敗，退出碼與失敗測試相同。

先使用`report`幾週，看看`enforce`會阻擋什麼。

將它放在直通參數之前，或設定`TUIST_TEST_STRESS_NEW_TESTS`以根據 CI 通道變更模式：

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

### 每個測試重新運行的次數

這取決於測試案例在第一次通過時所花的時間：

| 第一次通過 | 重新運行次數 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分鐘 | 2 |
| 超過 5 分鐘 | 不重新運行 |

重新運行會重用第一次通過所建置的內容。當達到 200 個測試案例或 10 分鐘時（以先到者為準），通過會停止，並說明達到了哪個限制。

### 閘門不運行的情況

- 第一次通過已經失敗。請先修復這些測試。
- 專案沒有預設分支，或者尚未在其上運行任何 CI。
- 超過 30% 的專案測試案例看起來是新的。重新運行這麼多測試會耗費過多時間。在剛開始向 Tuist 報告的專案上，或在一次重新命名移動了大量測試之後，預計會出現這種情況。

## Slack 通知 {#slack-notifications}

透過在你的 Slack 整合中設定<.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，在測試變得不穩定時立即收到通知。

## 查詢不穩定和隔離狀態 {#querying}

### CLI

`tuist test case`命令樹公開了 Tuist 追蹤測試案例的所有資訊：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有這些都接受`--json`用於腳本編寫。

### REST API

相同的數據可透過 HTTP 取得 — 請參閱 API 參考中的[測試案例端點](https://tuist.dev/api/docs#tag/test-cases)以獲取完整的路由、過濾器和回應字段列表。要更改測試案例的狀態（標記或取消標記為不穩定、靜音、跳過），請發送帶有`is_flaky`或`state`的`PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`。相同的更改也可作為`tuist test case update`和`update_test_case`模型上下文協議工具使用。
