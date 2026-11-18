---
{
  "title": "Once 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "追蹤 Once 運行過程，並在 Tuist 儀表板中檢查操作、持續時間、失敗情況及快取決策。"
}
---
# Once 構建洞察 {#once-build-insights}

Once 會在執行期間將運行數據串流到 Tuist，讓你可以追蹤進度，無須等待最終的 CI 日誌。開啟在運行開始時列印的控制台連結，以檢查其圖表、操作狀態及快取決策。

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>並為執行 Once 的機器進行身份驗證。

## 報告你的構建 {#report-your-builds}

繼續使用你的 Once 指令：

```bash
once build MyApplication
```

即時報告屬於盡力而為。如果報告端點不可用或工作階段已過期，不會導致構建失敗。若工作階段過期，請使用 `once auth login --provider tuist` 重新登入。

## 控制台顯示內容 {#what-the-dashboard-shows}

使用**Builds**和**Build Runs**來比較不同時間、分支以及本地或 CI 環境中的運行。每次運行可包括：

- 所請求的指令、狀態、開始時間及持續時間。
- Once 版本及報告的主機資訊。
- 操作及其依賴項、狀態、持續時間和快取結果。
- 報告的操作錯誤。
- 由客戶端報告時的 Git 分支、提交及 CI 上下文。

搜尋並篩選操作以找出失敗或緩慢的工作。報告的操作名稱和原始檔案有助於將工作關聯回代碼；較舊的客戶端可能提供較少細節。已快取或跳過的操作並非已執行的工作，而缺少計時資訊亦不代表執行時間為零。

Tuist 目前不會攝取 Once 的原始操作日誌串流。請保留 CI 日誌以獲取完整的程序輸出；運行摘要和結構化錯誤不能取代這些日誌。

**Cache** 檢視將操作決策與內容物件傳輸分開。請參閱<.localized_link href="/guides/features/cache/once">Once cache</.localized_link>以了解如何解讀快取活動。

## 測試 {#tests}

測試指令也會產生 Once 運行。它們報告的套件和案例會顯示在**Tests**之下；託管的 shard 還會發布合併的測試執行。請參閱<.localized_link href="/guides/features/test-insights/once">Once test insights</.localized_link>。

## 編碼代理與 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#once-runs">Model Context Protocol tools</.localized_link> 讓代理可以列出 Once 運行並讀取運行的操作和快取總數。相同的讀取亦可透過 HTTP API 取得。

使用<.localized_link href="/guides/integrations/grafana">Grafana integration</.localized_link>獲取最終確定的 Once 構建健康指標。Once 目前不會報告經過的快取時間節省，因此該測量結果顯示為不可用而非零。
