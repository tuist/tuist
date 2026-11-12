---
{
  "title": "Once 不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "透過報告的重試次數同 CI 歷史記錄，偵測並調查 Once 嘅不穩定測試。"
}
---
# Once 不穩定測試 {#once-flaky-tests}

> [!IMPORTANT]
> **要求**
>
> - 設定 <.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link>，並提供結構化的個別測試結果。

<!-- @snippet: ./_intro -->

## 不穩定測試偵測運作方式 {#how-it-works}

### 測試重試 {#test-retries}

當 runner 報告同一個測試的多個嘗試時，Tuist 會保留這些記錄。先失敗後通過的測試會被標記為不穩定；持續失敗的測試仍視為失敗。在支援的底层 runner 中啟用重試功能。將 Once 連接到 Tuist 不會自動為每個測試目標加入重試。

### 跨執行偵測 {#cross-run-detection}

共用測試歷史記錄讓 Tuist 能夠比較 CI 中同一測試和提交的成功與失敗結果。Once 必須報告提交和 CI 上下文以進行此比較；本機執行仍然可見，但不會自動成為跨執行不穩定的證據。

測試案例透過原生目標、套件和案例名稱來識別。保持這些識別碼穩定以保留其歷史記錄，並使用完整的每個案例報告，而非從目標的整體結果推斷可靠性。

## 調查不穩定測試 {#investigate-flaky-tests}

在 Tuist 中開啟測試案例的歷史記錄，以比較其嘗試、失敗和受影響的 CI 提交。亦可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 工具</.localized_link> 使用共用測試查詢，讓編碼代理程式調查相同的報告結果。

## 管理不穩定測試 {#managing-flaky-tests}

在調查失敗時，你可以從測試詳情頁面將測試標記或取消標記為不穩定。預設的不穩定測試偵測自動化也會在恢復期過後清除標記，通常為 14 天內沒有其他觸發。

Once 專案目前未公開 **自動化** 設定標籤。偵測和儲存的測試狀態可用，但文件記錄中針對具有隔離強制執行的建置系統的設定工作流程尚未對 Once 公開。

## 隔離 {#quarantining}

Tuist 可以將報告的案例歸因於其儲存的隔離狀態，但原生 Once 用戶端目前不會抓取並強制執行 Tuist 的 **靜音** 或 **略過** 政策。在 Tuist 中更改該狀態不會阻止 Once 執行測試，也不會使其失敗停止阻擋 CI。

當你需要執行時間隔離時，請使用你 runner 自身的過濾或失敗政策。不要僅依賴儀表板狀態來更改命令的退出代碼。

## Slack 通知 {#slack-notifications}

Once 專案目前未公開用於設定不穩定測試 Slack 警示的專案設定工作流程。使用下方的共用測試查詢，將報告的不穩定狀態整合到你自己的通知中。

<!-- @snippet: ./_querying -->
