---
{
  "title": "Struo 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中即時追蹤 Struo 運行，並檢視操作、持續時間、失敗情況及快取決策。"
}
---
# Struo 構建洞察 {#struo-build-insights}

<a id="once-build-insights"></a>

Struo 會在執行期間將運行數據串流到 Tuist，讓你可以追蹤進度，無須等待最終的 CI 日誌。開啟在運行開始時列印的控制面板連結，以檢視其圖表、動作狀態及快取決策。

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/struo-project">開始使用 Struo</.localized_link>並對執行 Struo 的機器進行身份驗證。

## 匯報你的構建 {#report-your-builds}

繼續使用你的 Struo 指令：

```bash
struo build MyApplication
```

即時匯報屬盡力而為。如果匯報端點不可用或工作階段已過期，不會導致構建失敗。如果工作階段過期，請使用 `struo auth login --provider tuist` 重新登入。

## 控制面板顯示的內容 {#what-the-dashboard-shows}

使用**構建**和**構建運行**來比較不同時間、分支以及本地或 CI 環境中的運行。每次運行可以包括：

- 所請求的指令、狀態、開始時間和持續時間。
- Struo 版本及報告的主機資訊。
- 動作及其依賴項、狀態、持續時間和快取結果。
- 報告的動作錯誤。
- 當客戶端報告時，包括 Git 分支、提交和 CI 上下文。

搜尋和篩選動作以找出失敗或緩慢的工作。報告的動作名稱和原始檔有助於將工作關聯回代碼；較舊的客戶端可能提供較少的細節。已快取或跳過的動作並非已執行的工作，而缺少計時數據亦不代表執行持續時間為零。

Tuist 目前不會攝取 Struo 的原始動作日誌串流。請保留 CI 日誌以獲取完整的程序輸出；運行摘要和結構化錯誤不能取代這些日誌。

**快取**檢視將動作決策與內容物件傳輸分開。請參閱<.localized_link href="/guides/features/cache/struo">Struo 快取</.localized_link>以了解如何解讀快取活動。

## 測試 {#tests}

測試指令也會產生 Struo 運行。它們報告的套件和用例會顯示在**測試**之下；託管的分片還會發布一個合併的測試運行。請參閱<.localized_link href="/guides/features/test-insights/struo">Struo 測試洞察</.localized_link>。

## 編碼代理與 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#struo-runs">Model Context Protocol 工具</.localized_link>讓代理可以列出 Struo 運行並讀取運行的動作和快取總數。相同的讀取操作亦可透過 HTTP API 進行。

使用<.localized_link href="/guides/integrations/grafana">Grafana 整合</.localized_link>獲取最終確定的 Struo 構建健康度指標。Struo 目前不會報告已節省的快取時間，因此該測量結果顯示為不可用，而非零。
