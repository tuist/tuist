---
{
  "title": "Struo 構建洞察",
  "titleTemplate": ":title · 構建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中即時追蹤 Struo 執行，並檢查操作、持續時間、失敗及快取決策。"
}
---
# Struo 建置洞察 {#struo-build-insights}

<a id="once-build-insights"></a>

Struo 會在執行期間將運行串流至 Tuist，讓你可以追蹤進度，無須等待最終的 CI 日誌。開啟在運行開始時印出的儀表板連結，以檢查其圖表、動作狀態及快取決策。

> [!IMPORTANT]
> **需求**
>
> - 完成 <.localized_link href="/guides/get-started/struo-project">開始使用 Struo</.localized_link> 並對執行 Struo 的機器進行身份驗證。

## 回報你的建置 {#report-your-builds}

繼續使用你的 Struo 指令：

```bash
struo build MyApplication
```

即時回報屬盡力而為。若回報端點無法使用或工作階段已過期，不會導致建置失敗。如果工作階段過期，請使用 `struo auth login --provider tuist` 重新登入。

## 儀表板顯示內容 {#what-the-dashboard-shows}

使用 **Builds** 和 **Build Runs** 來比較不同時間、分支以及本地或 CI 環境中的運行。每次運行可包括：

- 所請求的指令、狀態、開始時間及持續時間。
- Struo 版本及報告的主機資訊。
- 動作及其依賴項、狀態、持續時間和快取結果。
- 報告的動作錯誤。
- 由客戶端報告時的 Git 分支、提交及 CI 上下文。

搜尋並篩選動作以找出失敗或緩慢的工作。報告的動作名稱和原始檔有助於將工作連結回程式碼；較舊的客戶端可能提供較少細節。已快取或略過的動作並非已執行的工作，而缺少計時並非零持續時間的執行。

Tuist 目前不會攝取 Struo 的原始動作日誌串流。請保留 CI 日誌以獲取完整的程序輸出；運行摘要和結構化錯誤並不能取代這些日誌。

**Cache** 檢視將動作決策與內容物件傳輸分開。請參閱 <.localized_link href="/guides/features/cache/struo">Struo cache</.localized_link> 以解讀快取活動。

## 測試 {#tests}

測試指令也會產生 Struo 運行。它們報告的套件和案例會出現在 **Tests** 下；託管的分片還會發布一個合併的測試運行。請參閱 <.localized_link href="/guides/features/test-insights/struo">Struo test insights</.localized_link>。

## 編碼代理與 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#struo-runs">Model Context Protocol tools</.localized_link> 讓代理可以列出 Struo 運行並讀取運行的動作和快取總數。相同的讀取也可透過 HTTP API 取得。

使用 <.localized_link href="/guides/integrations/grafana">Grafana integration</.localized_link> 獲取最終確定的 Struo 建置健康指標。Struo 目前不會報告經過的快取時間節省，因此該測量結果仍為不可用，而非零。
