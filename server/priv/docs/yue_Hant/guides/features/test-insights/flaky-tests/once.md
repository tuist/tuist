---
{
  "title": "一次性不穩定測試",
  "titleTemplate": ":title · 不穩定測試 · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "透過重試次數報告同 CI 歷史記錄，偵測並調查一次性不穩定測試。"
}
---
# Once 不穩定測試 {#once-flaky-tests}

> [!IMPORTANT]
> **必要條件**
>
> - 使用結構化個別測試結果設定 <.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link>。

<!-- @snippet: ./_intro -->

## 不穩定偵測運作方式 {#how-it-works}

### 測試重試 {#test-retries}

當 runner 回報同一個測試嘅多次嘗試時，Tuist 會保留呢啲記錄。如果一個測試先失敗後通過，就會被標記為不穩定；如果持續失敗，則仍視為失敗。喺支援嘅情況下，請喺底層 runner 啟用重試功能。將 Once 連接到 Tuist 並唔會自動為每個測試目標加入重試。

### 跨運行偵測 {#cross-run-detection}

共享測試歷史亦允許 Tuist 比較 CI 中同一測試同提交嘅通過同失敗結果。Once 必須回報提交同 CI 上下文以進行此比較；本地運行仍然可見，但唔會自動成為跨運行不穩定證據。

測試案例透過原生目標、套件同案例名稱來識別。保持呢啲身份穩定以保留其歷史，並使用完整嘅每案例報告，而唔係從目標嘅整體結果推斷可靠性。

## 調查不穩定測試 {#investigate-flaky-tests}

喺 Tuist 開啟測試案例歷史，以比較其嘗試、失敗同受影響嘅 CI 提交。亦可透過 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 工具</.localized_link> 使用共享測試查詢，令編碼代理可以調查相同嘅回報結果。

## 管理不穩定測試 {#managing-flaky-tests}

調查失敗時，你可以喺測試詳情頁面標記或取消標記測試為不穩定。預設嘅不穩定測試偵測自動化亦會喺恢復期（通常為 14 日內無其他觸發）過後清除標記。

Once 專案目前並未公開 **自動化** 設定標籤。雖然偵測同儲存嘅測試狀態可用，但文檔中針對具有隔離強制執行嘅構建系統所描述嘅設定工作流程，尚未喺 Once 中公開。

## 隔離 {#quarantining}

Tuist 可以將回報案例歸因於其儲存嘅隔離狀態，但原生 Once 客戶端目前並唔會獲取同執行 Tuist 嘅 **靜音** 或 **跳過** 策略。喺 Tuist 更改該狀態並唔會阻止 Once 執行測試，亦唔會令其失敗停止阻塞 CI。

當你需要執行時隔離時，請使用你 runner 自身嘅過濾或失敗策略。唔好單靠儀表板狀態來改變命令嘅退出代碼。

## Slack 通知 {#slack-notifications}

Once 專案目前並未公開用於設定不穩定測試 Slack 警示嘅專案設定工作流程。請使用下方嘅共享測試查詢，將回報嘅不穩定狀態整合到你自己嘅通知中。

<!-- @snippet: ./_querying -->
