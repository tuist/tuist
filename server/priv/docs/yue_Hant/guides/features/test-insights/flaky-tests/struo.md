---
{
  "title": "偵測不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "透過重試記錄同 CI 歷史，偵測並調查不穩定嘅 Struo 測試。"
}
---
# Struo 不穩定測試 {#struo-flaky-tests}

<a id="once-flaky-tests"></a>

> [!IMPORTANT]
> **必要條件**
>
> - 設定 <.localized_link href="/guides/features/test-insights/struo">Struo 測試洞察</.localized_link>，並提供結構化的個別測試結果。

<!-- @snippet: ./_intro -->

## 不穩定偵測運作方式 {#how-it-works}

### 測試重試 {#test-retries}

當執行器回報同一個測試的多個嘗試時，Tuist 會保留這些記錄。先失敗後通過的測試會被標記為不穩定；持續失敗的測試仍視為失敗。在支援的基礎執行器中啟用重試功能。將 Struo 連接至 Tuist 不會自動為每個測試目標加入重試。

### 跨執行偵測 {#cross-run-detection}

共享測試歷史讓 Tuist 能夠比較 CI 中同一測試與提交的通過和失敗結果。Struo 必須回報提交與 CI 上下文以進行此比較；本機執行仍然可見，但不會自動成為跨執行的不穩定證據。

測試案例透過原生目標、套件及案例名稱來識別。保持這些識別碼穩定以保留其歷史記錄，並使用完整的每案例報告，而非從目標的整體結果推斷可靠性。

## 調查不穩定測試 {#investigate-flaky-tests}

在 Tuist 中開啟測試案例的歷史記錄，以比較其嘗試、失敗及受影響的 CI 提交。亦可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 工具</.localized_link> 使用共享測試查詢，讓編碼代理程式調查相同的回報結果。

## 管理不穩定測試 {#managing-flaky-tests}

調查失敗時，你可以從詳細頁面將測試標記或取消標記為不穩定。預設的不穩定測試偵測自動化也會在恢復期過後清除標記，通常為 14 天內沒有其他觸發事件。

Struo 專案目前並未公開 **自動化** 設定分頁。雖然可使用偵測功能及儲存的測試狀態，但針對具備隔離強制執行功能的建構系統所記錄的設定工作流程，尚未對 Struo 公開。

## 隔離 {#quarantining}

Tuist 可以將回報的案例關聯至其儲存的隔離狀態，但原生 Struo 用戶端目前不會抓取並強制執行 Tuist 的 **靜音** 或 **跳過** 政策。在 Tuist 中變更該狀態不會阻止 Struo 執行測試，亦不會使其失敗停止阻擋 CI。

當你需要執行期間的隔離時，請使用執行器自身的過濾或失敗政策。不要僅依賴儀表板狀態來變更指令的退出代碼。

## Slack 通知 {#slack-notifications}

Struo 專案目前並未公開用於設定不穩定測試 Slack 警示的專案設定工作流程。請使用下方的共享測試查詢，將回報的不穩定狀態整合至你自己的通知中。

<!-- @snippet: ./_querying -->
