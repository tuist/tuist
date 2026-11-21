---
{
  "title": "Struo 建置洞察",
  "titleTemplate": ":title · 建置洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中即時追蹤 Struo 執行，並檢視動作、持續時間、失敗與快取決策。"
}
---
# Struo 建置洞察 {#struo-build-insights}

<a id="once-build-insights"></a>

Struo 會在執行期間將執行串流傳輸至 Tuist，讓你無須等待最終的 CI 記錄即可追蹤進度。開啟在執行開始時列印的儀表板連結，以檢視其圖表、動作狀態與快取決策。

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/struo-project">開始使用 Struo</.localized_link>並對執行 Struo 的機器進行驗證。

## 回報你的建置 {#report-your-builds}

繼續使用你的 Struo 指令：

```bash
struo build MyApplication
```

即時回報採盡力而為模式。回報端點無法使用或工作階段過期不會導致建置失敗。若工作階段過期，請使用 `struo auth login --provider tuist` 再次登入。

## 儀表板顯示內容 {#what-the-dashboard-shows}

使用**建置**與**建置執行**來比較不同時間、分支以及本機或 CI 環境中的執行。每次執行可包含：

- 要求的指令、狀態、開始時間與持續時間。
- Struo 版本與回報的主機資訊。
- 動作及其相依性、狀態、持續時間與快取結果。
- 回報的動作錯誤。
- 當用戶端回報時的 Git 分支、提交與 CI 上下文。

搜尋並篩選動作以找出失敗或緩慢的工作。回報的動作名稱與原始檔案有助於將工作回溯至程式碼；較舊的用戶端可能提供較少細節。已快取或跳過的動作並非已執行的工作，缺少計時資訊也不代表持續時間為零的執行。

Tuist 目前不會擷取 Struo 的原始動作記錄串流。請保留 CI 記錄以取得完整的程序輸出；執行摘要與結構化錯誤並不能取代這些記錄。

**快取**檢視將動作決策與內容物件傳輸分開。請參閱<.localized_link href="/guides/features/cache/struo">Struo 快取</.localized_link>以解讀快取活動。

## 測試 {#tests}

測試指令也會產生 Struo 執行。其回報的套件與案例會顯示在**測試**下方；託管分片還會發布合併的測試執行。請參閱<.localized_link href="/guides/features/test-insights/struo">Struo 測試洞察</.localized_link>。

## 編碼代理與 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#struo-runs">Model Context Protocol 工具</.localized_link>讓代理能夠列出 Struo 執行並讀取執行的動作與快取總計。相同的讀取也可透過 HTTP API 取得。

使用<.localized_link href="/guides/integrations/grafana">Grafana 整合</.localized_link>取得最終確定的 Struo 建置健康度指標。Struo 目前不會回報已節省的快取時間，因此該測量結果仍為不可用而非零。
