---
{
  "title": "一次性建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "追蹤一次性執行的即時狀態，並在 Tuist 儀表板中檢查動作、持續時間、失敗情形與快取決策。"
}
---
# Once 建置洞察 {#once-build-insights}

Once 會在執行期間將執行串流傳輸至 Tuist，因此你無需等待最終的 CI 日誌即可追蹤進度。開啟在執行開始時列印的控制台連結，以檢視其圖表、動作狀態與快取決策。

> [!IMPORTANT]
> **需求**
>
> - 完成<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>並對執行 Once 的機器進行身分驗證。

## 回報你的建置 {#report-your-builds}

繼續使用你的 Once 指令：

```bash
once build MyApplication
```

即時回報採尽力而為原則。回報端點無法使用或工作階段過期不會導致建置失敗。若工作階段過期，請使用 `once auth login --provider tuist` 重新登入。

## 控制台顯示內容 {#what-the-dashboard-shows}

使用**建置**與**建置執行**來比較不同時間、分支以及本機或 CI 環境中的執行。每次執行可包含：

- 所請求的指令、狀態、開始時間與持續時間。
- Once 版本與回報的主機資訊。
- 動作及其相依性、狀態、持續時間與快取結果。
- 回報的動作錯誤。
- 當用戶端回報時的 Git 分支、提交與 CI 脈絡。

搜尋並篩選動作以找出失敗或緩慢的工作。回報的動作名稱與原始檔有助於將工作回溯至程式碼；較舊的用戶端可能提供較少細節。已快取或略過的動作並非已執行的工作，缺少時間資訊也不代表執行持續時間為零。

Tuist 目前不會匯入 Once 的原始動作日誌串流。請保留 CI 日誌以取得完整的程序輸出；執行摘要與結構化錯誤並非這些日誌的替代品。

**快取**檢視將動作決策與內容物件傳輸分開。請參閱<.localized_link href="/guides/features/cache/once">Once 快取</.localized_link>以解讀快取活動。

## 測試 {#tests}

測試指令也會產生 Once 執行。其回報的套件與案例會顯示在**測試**之下；託管的分片還會發布合併的測試執行。請參閱<.localized_link href="/guides/features/test-insights/once">Once 測試洞察</.localized_link>。

## 編碼代理程式與 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#once-runs">Model Context Protocol 工具</.localized_link>讓代理程式能夠列出 Once 執行，並讀取執行的動作與快取總計。相同的讀取也可透過 HTTP API 取得。

使用<.localized_link href="/guides/integrations/grafana">Grafana 整合</.localized_link>取得最終確定的 Once 建置健康度指標。Once 目前不會回報已節省的快取時間，因此該測量結果會顯示為無法使用，而非零。
