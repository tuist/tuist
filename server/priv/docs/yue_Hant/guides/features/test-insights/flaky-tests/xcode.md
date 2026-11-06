---
{
  "title": "Xcode 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 偵測、管理及隔離 Xcode 專案中的不穩定測試。"
}
---
# Xcode 不穩定測試 {#xcode-flaky-tests}

> [!WARNING]
> **必要條件**
>
> - 已設定<.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>。Tuist 會從每次測試執行上傳的測試洞察事件中偵測不穩定測試。

不穩定測試是指在使用相同程式碼多次執行時，會產生不同結果（通過或失敗）的測試。它們會削弱你對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助你隨時間追蹤它們。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測如何運作 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能執行測試時，Tuist 會分析每次嘗試的結果。如果某個測試在某些嘗試中失敗，但在其他嘗試中通過，它會被標記為不穩定。

透過 `tuist xcodebuild test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不穩定測試案例詳情](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也可以透過比較同一個提交、scheme 和報告的目標裝置（裝置名稱、平台和作業系統版本）在不同 CI 執行中的結果來偵測不穩定測試。如果某個測試在一個相符的 CI 執行中通過，但在另一個中失敗，則該失敗的執行會被標記為不穩定。無論哪個結果先到達，此機制都會生效。

同一個測試在不同的 scheme 或目標裝置上可能會有一致的不同行為。例如，在 iOS 26 上通過而在 iOS 27 上失敗，並不構成不穩定。來自不同 scheme、裝置、平台或作業系統版本的結果不會互相標記為不穩定。

沒有可歸屬目標裝置的結果會與其他未歸屬的結果進行比較，這與具有已知目標裝置的結果是分開處理的。這包括缺少或不完整目標裝置中繼資料的報告，以及包含多個不同目標裝置的報告，因為個別測試結果尚無法歸屬到特定目標裝置。此群組中環境之間的差異仍可能產生錯誤的不穩定分類。基於重試的偵測仍然適用。現有的歷史不穩定分類保持不變。

這對於捕捉那些失敗頻率不足以被重試機制捕捉，但仍會導致間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測和清除是透過專案上的**自動化警示**執行的。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其*觸發條件*會將測試標記為不穩定，而其*恢復條件*會在測試經過設定的恢復視窗（預設為**14 天**）且未重新觸發後清除標記。你可以在**設定 → 自動化**下編輯它，以更改恢復視窗、交換恢復動作（例如也解除隔離），或完全停用恢復功能，讓測試保持標記為不穩定，直到你手動清除為止。

### 手動管理

你也可以從測試案例詳情頁面手動將測試標記為不穩定或取消標記。這在以下情況很有用：
- 你想在修復已知不穩定測試的同時確認其狀態
- 由於基礎設施問題導致測試被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離會將不穩定測試孤立起來，使其在你修復時不會阻塞 CI。預設情況下，這是一個**手動動作**——你可以從儀表板中的測試案例詳情頁面進行隔離、解除隔離和切換模式——但你也可以將其連接到**設定 → 自動化**下的**自動化警示**，以便當測試超過不穩定閾值時自動靜音（或跳過），並在恢復時解除隔離。每次轉換，無論是手動還是自動，都會記錄在測試案例的審核日誌中。

預設情況下，恢復會等待直到觸發條件不再成立，因此測試會保持隔離狀態，直到其舊的不穩定執行離開觸發視窗。若要更快恢復，請將**恢復時機**設定為**無新的不穩定執行**：一旦恢復視窗（天數或執行次數）過去而沒有新的不穩定執行，測試就會恢復；每次新的不穩定執行都會重新開始等待；恢復後，只有新的不穩定執行才會再次將其隔離。

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍然執行，但`tuist xcodebuild test`會掩蓋失敗。失敗仍會提供給不穩定測試偵測器，因此你可以繼續觀察測試而不破壞建構。選擇此模式用於你正在積極調查的測試。
- **跳過**：xcodebuild 會收到`-skip-testing <identifier>`，因此測試永遠不會啟動。它不會產生新結果，並從不穩定測試儀表板中消失，直到你重新啟用它。當測試損壞、緩慢，或持續不穩定到執行它只是浪費 CI 分鐘數時，請選擇此模式。

### 為何被隔離的測試可能顯示為通過 {#quarantined-passing}

- **靜音測試**仍然執行。失敗的靜音測試會在測試案例執行中被記錄為**失敗**並標記為不穩定——每個測試的狀態不會被改寫。被覆蓋的是**整體測試執行**：如果執行中每個失敗的測試案例都被靜音，則整個執行會被報告為通過，因此靜音失敗不會破壞 CI。
- **跳過的測試**根本不會執行，因此儀表板會繼續顯示測試最後一次實際執行的狀態——該快照可能是幾週前的。

### 執行測試 {#running-tests}

`tuist xcodebuild test`是一個直通包裝器，會自動尊重這兩種模式。使用它的方式與呼叫 xcodebuild 相同：

```sh
tuist xcodebuild test -scheme MyScheme
```

跳過的測試會作為`-skip-testing <identifier>`附加到你的 xcodebuild 呼叫中，並且永遠不會啟動。靜音測試正常執行；如果它們失敗，失敗會在 resulting build status 中被掩蓋。

#### 繞過隔離

`tuist xcodebuild test`接受`--skip-quarantine`以執行所有內容，包括靜音和跳過的測試：

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### 直接呼叫 xcodebuild

如果你無法透過`tuist xcodebuild test`執行，請使用`tuist test case list`自行將被隔離的測試展開為`-skip-testing`參數：

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

这是在`tuist xcodebuild test`之外的安全預設值：靜音測試的失敗掩蓋僅在你透過該命令執行時發生，因此跳過這兩種模式可以避免虛假的 CI 失敗。如果你需要更細粒度的控制，請改用`tuist xcodebuild test`。

## 壓力測試新測試 {#stress-testing-new-tests}

壓力閘門會重新執行你分支新增的測試案例，每個案例在全新程序中執行多次，並回報結果為不穩定的案例。你可以在引入該問題的拉取請求上看到新的不穩定測試，而不是幾週後才發現。

如果測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或未在已合併至該分支的提交上執行，則視為新案例。使用合併佇列時，一旦佇列的提交合併，佇列執行的測試案例即被識別；若佇列將其移除，該案例仍保持為新案例。提交是透過 Tuist 在 CI 上收集的<.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史記錄</.localized_link>進行比對。

### 啟用功能

閘門預設為關閉狀態。設定模式：

- **`report`**：警告每個不穩定的測試案例。執行仍會以其自身結果退出。
- **`enforce`**：不穩定的測試案例會導致執行失敗，退出碼與失敗測試相同。

先使用`report`幾週，以了解`enforce`會攔截哪些情況。

將它放在直通參數之前，或設定`TUIST_TEST_STRESS_NEW_TESTS`以針對不同 CI 管道變更模式：

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

### 每個測試重新執行的次數

取決於測試案例在首次執行時所花的時間：

| 首次執行 | 重新執行次數 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分鐘 | 2 |
| 超過 5 分鐘 | 不重新執行 |

重新執行會重用首次執行所建構的內容。當達到 200 個測試案例或 10 分鐘時（以先到者為準），執行就會停止，並指出觸發了哪項限制。

### 閘門不執行的情況

- 首次執行已經失敗。請先修復這些測試。
- 專案沒有預設分支，或尚未在其上執行任何 CI。
- 超過 30% 的專案測試案例看起來是新的。重新執行這麼多案例會耗費過多時間而不值得。這通常發生在剛開始向 Tuist 回報的專案，或在一次重新命名移動了大量測試之後。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定<.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，即可在測試變得不穩定時立即收到通知。

## 查詢不穩定與隔離狀態 {#querying}

### CLI

`tuist test case`命令樹顯示 Tuist 追蹤測試案例的所有資訊：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有這些命令都接受`--json`以便進行腳本化。

### REST API

相同的資料可透過 HTTP 取得——請參閱 API 參考中的[測試案例端點](https://tuist.dev/api/docs#tag/test-cases)，以獲取完整的路由、篩選器和回應欄位清單。若要變更測試案例的狀態（標記或取消標記為不穩定、靜音、跳過），請發送`PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`並包含`is_flaky`或`state`。相同的變更也可透過`tuist test case update`以及`update_test_case` Model Context Protocol 工具進行。
