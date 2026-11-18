---
{
  "title": "一次性不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "透過回報的重試次數與 CI 歷史記錄，偵測並調查一次性不穩定測試。"
}
---
# Once 不穩定測試 {#once-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 設定 <.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link>，並提供結構化的個別測試結果。

<!-- @snippet: ./_intro -->

## 不穩定偵測的運作方式 {#how-it-works}

### 測試重試 {#test-retries}

當執行器回報同一個測試的多個嘗試時，Tuist 會保留這些記錄。若測試先失敗後通過，會被標記為不穩定；若持續失敗，則仍視為失敗。請在支援的基礎執行器中啟用重試功能。將 Once 連接到 Tuist 並不會自動為每個測試目標新增重試。

### 跨執行偵測 {#cross-run-detection}

共用測試紀錄也讓 Tuist 能在 CI 中比較同一測試與提交的通過和失敗結果。Once 必須回報提交與 CI 脈絡以供此比較；本機執行仍可見，但不會自動成為跨執行不穩定的證據。

測試案例由原生目標、套件與案例名稱識別。保持這些識別資訊穩定以保留其歷史紀錄，並使用完整的個別案例報告，而非從目標的整體結果推斷可靠性。

## 調查不穩定測試 {#investigate-flaky-tests}

在 Tuist 中開啟測試案例的歷史紀錄，以比較其嘗試、失敗與受影響的 CI 提交。也可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 工具</.localized_link> 使用共用測試查詢，讓編碼代理程式調查相同的回報結果。

## 管理不穩定測試 {#managing-flaky-tests}

在調查失敗時，你可以從測試詳情頁面將測試標記或取消標記為不穩定。預設的不穩定測試偵測自動化也會在恢復期過後清除該標記，通常為 14 天內未再觸發。

Once 專案目前未顯示 **自動化** 設定分頁。偵測與儲存的測試狀態可用，但針對具備隔離強制執行的建置系統所記錄的設定工作流程，尚未在 Once 中公開。

## 隔離 {#quarantining}

Tuist 可將回報的案例對應至其儲存的隔離狀態，但原生的 Once 用戶端目前不會抓取並強制執行 Tuist 的 **靜音** 或 **略過** 政策。在 Tuist 中變更該狀態並不會阻止 Once 執行測試，也不會讓其失敗停止阻擋 CI。

當你需要執行時期隔離時，請使用執行器本身的過濾或失敗政策。不要僅依賴儀表板狀態來改變指令的結束代碼。

## Slack 通知 {#slack-notifications}

Once 專案目前未公開用於設定不穩定測試 Slack 警示的專案設定工作流程。請使用下方的共用測試查詢，將回報的不穩定狀態整合到你自己的通知中。

<!-- @snippet: ./_querying -->
