---
{
  "title": "Xcode 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 偵測、管理並隔離 Xcode 專案中的不穩定測試。"
}
---
# Xcode 不穩定測試 {#xcode-flaky-tests}

> [!WARNING]
> **必要條件**
>
> - 已設定<.localized_link href="/guides/features/test-insights/xcode">Xcode 測試洞察</.localized_link>。Tuist 會從每次測試執行上傳的測試洞察事件中偵測不穩定測試。

不穩定測試是指在相同程式碼下多次執行時，會產生不同結果（通過或失敗）的測試。它們會侵蝕你對測試套件的信任，並浪費開發人員調查誤報失敗的時間。Tuist 會自動偵測不穩定測試，並協助你長期追蹤。

![不穩定測試頁面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不穩定偵測運作方式 {#how-it-works}

Tuist 透過兩種方式偵測不穩定測試：

### 測試重試 {#test-retries}

當你使用重試功能執行測試時，Tuist 會分析每次嘗試的結果。如果某個測試在某些嘗試中失敗，但在其他嘗試中通過，就會被標記為不穩定。

透過 `tuist xcodebuild test` 傳遞 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不穩定測試案例詳細資訊](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨執行偵測 {#cross-run-detection}

即使沒有測試重試，Tuist 也能透過比較同一個提交、Scheme 與回報目的地（裝置名稱、平台與作業系統版本）在不同 CI 執行中的結果，來偵測不穩定測試。如果某個測試在一個相符的 CI 執行中通過，但在另一個中失敗，該失敗的執行就會被標記為不穩定。無論哪個結果先到達，此機制皆有效。

同一個測試在不同 Scheme 或目的地上的行為可能持續不同。例如，在 iOS 26 上通過而在 iOS 27 上失敗，並不構成不穩定。來自不同 Scheme、裝置、平台或作業系統版本的結果不會互相標記為不穩定。

無法歸因至特定目的地的結果，會與其他未歸因的結果進行比較，並與具有已知目的地的結果分開處理。這包括缺少或不完整目的地中繼資料的回報，以及包含多個不同目的地的回報，因為個別測試結果尚無法歸因至單一目的地。此群組中環境之間的差異仍可能導致錯誤的不穩定分類。基於重試的偵測仍然適用。現有的歷史不穩定分類保持不變。

這對於捕捉那些失敗頻率不足以被重試機制抓到，但仍會造成間歇性 CI 失敗的不穩定測試特別有用。

## 管理不穩定測試 {#managing-flaky-tests}

### 自動清除

偵測與清除是透過專案上的**自動化警示**執行。每個專案都會獲得一個預設的「不穩定測試偵測」自動化，其*觸發條件*會將測試標記為不穩定，而其*恢復*則會在測試於設定的恢復視窗（預設為**14 天**）內未再次觸發後清除標記。你可以在**設定 → 自動化**中編輯它，以變更恢復視窗、替換恢復動作（例如也解除隔離），或完全停用恢復，讓測試保持標記為不穩定，直到你手動清除為止。

### 手動管理

你也可以從測試案例詳細資訊頁面手動將測試標記或取消標記為不穩定。這在以下情況很有用：
- 你想在修復已知不穩定測試的同時承認其存在
- 測試因基礎設施問題而被錯誤標記

## 隔離不穩定測試 {#quarantining}

隔離功能會將不穩定測試隔離，讓它在修復期間不會阻礙 CI。預設為**手動操作**：你可以在儀表板的測試案例詳情頁面中進行隔離、解除隔離，以及切換模式；你也可以將其設定為**自動化警示**，在**設定 → 自動化**中設定，讓測試在不穩定程度超過門檻時自動靜音（或略過），並在恢復穩定後解除隔離。每一次狀態轉換，不論是手動或自動化，都會記錄在測試案例的稽核日誌中。

被隔離的測試處於以下兩種模式之一：

- **靜音**：測試仍會執行，但`tuist xcodebuild test`會遮蔽失敗。失敗仍會提供給不穩定測試偵測器，因此你可以持續觀察該測試而不會破壞建置。選擇此模式適用於你正在積極調查的測試。
- **跳過**：xcodebuild 會收到`-skip-testing <identifier>`，因此測試永遠不會啟動。它不會產生新結果，並會從不穩定測試儀表板中消失，直到你重新啟用為止。當測試損壞、緩慢，或不穩定程度高到執行它只是浪費 CI 分鐘數時，請選擇此模式。

### 為何被隔離的測試可能顯示為通過 {#quarantined-passing}

- **靜音測試**仍會執行。失敗的靜音測試會在測試案例執行中被記錄為**失敗**並標記為不穩定—每個測試的狀態不會被覆寫。被覆寫的是**整體測試執行**：如果執行中所有失敗的測試案例都被靜音，則整個執行會被回報為通過，因此靜音失敗不會破壞 CI。
- **跳過的測試**根本不會執行，因此儀表板會繼續顯示該測試最後一次實際執行的狀態—該快照可能已是數週前的資料。

### 執行測試 {#running-tests}

`tuist xcodebuild test`是一個直通包裝器，會自動尊重這兩種模式。使用方式與呼叫 xcodebuild 相同：

```sh
tuist xcodebuild test -scheme MyScheme
```

跳過的測試會以`-skip-testing <identifier>`的形式附加到你的 xcodebuild 叫用中，且永遠不會啟動。靜音測試正常執行；如果它們失敗，失敗會在產生的建置狀態中被遮蔽。

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

这是在`tuist xcodebuild test`之外的安全預設值：靜音測試的失敗遮蔽僅在你透過該命令執行時才會發生，因此跳過這兩種模式可避免虛假的 CI 失敗。如果你需要更細緻的控制，請改用`tuist xcodebuild test`。

## 壓力測試新測試 {#stress-testing-new-tests}

壓力測試閘道會重新執行你的分支新增的測試案例，每個案例在全新程序中執行多次，並回報結果為不穩定的案例。你會在引入該測試的拉取請求上看到新的不穩定測試，而不是數週後。

當測試案例在過去 90 天內未在專案的預設分支上於 CI 中執行，或尚未合併至該分支的提交中執行時，即視為新測試。若使用合併佇列，一旦佇列的提交合併後，佇列執行的測試案例便會被識別；若佇列將其移除，則該測試案例仍維持為新測試。提交是透過 Tuist 在 CI 上收集的<.localized_link href="/guides/features/test-insights/xcode#git-history">Git 歷史記錄</.localized_link>進行比對。

### 啟用方式

閘道預設為關閉狀態。設定模式：

- **`report`報告**：警告每個不穩定的測試案例。執行仍會以其自身結果結束。
- **`enforce`強制**：不穩定的測試案例會導致執行失敗，退出碼與失敗測試相同。

先使用`report`幾週，看看`enforce`會攔截哪些內容。

將其傳遞至直通參數之前，或設定`TUIST_TEST_STRESS_NEW_TESTS`以根據 CI 通道變更模式：

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
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

重新執行會重複使用首次執行所建置的內容。執行會在達到 200 個測試案例或 10 分鐘時停止，以先到者為準，並說明達到了哪個限制。

### 閘道未執行的情況

- 首次執行已經失敗。請先修復這些測試。
- 專案沒有預設分支，或其上尚未在 CI 中執行任何內容。
- 超過 30% 的專案測試案例看起來是新的。重新執行這麼多案例會耗費過多時間。這通常發生在剛開始向 Tuist 回報的專案，或在大量移動測試的重命名之後。

## Slack 通知 {#slack-notifications}

透過在 Slack 整合中設定<.localized_link href="/guides/integrations/slack#flaky-test-alerts">不穩定測試警示</.localized_link>，即可在測試變得不穩定時立即收到通知。

## 查詢不穩定與隔離狀態 {#querying}

### CLI

`tuist test case`命令樹暴露了 Tuist 追蹤測試案例的所有資訊：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有這些都接受`--json`以進行腳本化。

### REST API

相同的資料可透過 HTTP 取得—請參閱 API 參考中的[測試案例端點](https://tuist.dev/api/docs#tag/test-cases)以獲取完整的路由、篩選器和回應欄位清單。若要變更測試案例的狀態（標記或取消標記為不穩定、靜音、跳過），請發送`PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`並包含`is_flaky`或`state`。相同的變更也可透過`tuist test case update`以及`update_test_case`模型上下文協定工具進行。
