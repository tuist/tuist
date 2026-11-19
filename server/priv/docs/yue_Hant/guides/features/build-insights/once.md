---
{
  "title": "Once Build Insights",
  "titleTemplate": ":title · Build Insights · 功能 · 指南 · Tuist",
  "description": "追蹤 Once runs 嘅實時情況，並喺 Tuist 儀表板檢視動作、持續時間、失敗同快取決策。"
}
---
# Once 構建洞察 {#once-build-insights}

Once 會在執行期間將運行數據流式傳輸到 Tuist，讓你可以即時追蹤進度，無須等待最終的 CI 日誌。開啟在運行開始時列印的控制台連結，以檢查其圖表、操作狀態及快取決策。

> [!IMPORTANT]
> **必要條件**
>
> - 完成 <.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link> 並對執行 Once 的機器進行身份驗證。

## 報告你的構建 {#report-your-builds}

繼續使用你的 Once 指令：

```bash
once build MyApplication
```

即時報告屬尽力而為。若報告端點不可用或工作階段已過期，不會導致構建失敗。如果工作階段過期，請使用 `once auth login --provider tuist` 重新登入。

## 控制台顯示內容 {#what-the-dashboard-shows}

使用 **Builds** 和 **Build Runs** 來比較不同時間、分支以及本地或 CI 環境中的運行。每次運行可包括：

- 所請求的指令、狀態、開始時間及持續時間。
- Once 版本及報告的主機資訊。
- 操作及其依賴項、狀態、持續時間和快取結果。
- 報告的操作錯誤。
- 由客戶端報告的 Git 分支、提交及 CI 上下文。

搜尋並篩選操作以找出失敗或緩慢的工作。報告的操作名稱和源文件有助於將工作關聯回代碼；較舊的客戶端可能提供較少細節。已快取或跳過的操作並非已執行的工作，而缺少計時資訊亦不代表執行 duration 為零。

Tuist 目前並未攝取 Once 的原始操作日誌流。請保留 CI 日誌以獲取完整的進程輸出；運行摘要和結構化錯誤無法取代這些日誌。

**Cache** 視圖將操作決策與內容對象傳輸分開。請參閱 <.localized_link href="/guides/features/cache/once">Once 快取</.localized_link> 以了解如何解讀快取活動。

## 測試 {#tests}

測試指令也會產生 Once 運行。其報告的套件和用例會顯示在 **Tests** 下；託管的分片還會發布一個合併的測試執行。請參閱 <.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link>。

## 編碼代理與 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#once-runs">Model Context Protocol 工具</.localized_link> 讓代理可以列出 Once 運行並讀取運行的操作和快取總數。相同的讀取也可透過 HTTP API 取得。

使用 <.localized_link href="/guides/integrations/grafana">Grafana 整合</.localized_link> 獲取最終確定的 Once 構建健康度指標。Once 目前並未報告經過的快取時間節省，因此該測量結果顯示為不可用而非零。
