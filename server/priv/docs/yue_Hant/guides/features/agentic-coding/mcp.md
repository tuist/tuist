---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · 功能 · Guides · Tuist",
  "description": "透過 Tuist 嘅 MCP 端點，讓 AI 代理存取測試洞察同其他資料。"
}
---
# 模型上下文協議

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一項開放標準，讓人工智能代理可以與外部服務和數據來源互動。它令 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等應用程式，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等編輯器能夠與 Tuist 互通。

Tuist 在 `https://tuist.dev/mcp` 託管伺服器端的 Model Context Protocol 端點。將你的客戶端連接至此端點後，代理即可存取你的 Tuist 專案數據，包括測試洞察、不穩定測試分析等。大多數工具只會讀取已認證用戶在儀表板中可見的 Tuist 數據。每個工具都會宣告註釋，說明其是否為唯讀、是否可能導致難以逆轉的變更（`destructiveHint`），以及是否能存取 Tuist 以外的資源（`openWorldHint`）。會變更狀態的工具（各自受用戶對帳戶或專案的權限限制）包括：

- **組織與成員**：`create_organization`、`add_organization_member`（新增現有用戶或更改成員角色）、`invite_organization_member`（向任何地址發送邀請電郵）及 `cancel_organization_invitation`。
- **專案**：`create_project`、`start_project_logo_upload` 及 `complete_project_logo_upload`（更換標誌）、`connect_project_repository` 及 `disconnect_project_repository`（GitHub 儲存庫連結）。
- **測試**：`update_test_case`（靜音、跳過、重新啟用或將測試案例標記為不穩定；此變更可能會觸發帳戶的 webhook 端點）。
- **通知規則**：`create_notification_rule`、`update_notification_rule` 及 `delete_notification_rule`。
- **持續整合執行器**：`create_runner_profile`、`update_runner_profile`（縮小可儲存快取卷的工作範圍會丟棄待處理的儲存）、`delete_runner_profile` 及 `delete_runner_volume`（刪除卷中已儲存的內容）。
- **沙盒**：`create_sandbox`、`pause_sandbox`、`resume_sandbox`、`archive_sandbox` 及 `delete_sandbox`（刪除其磁碟）。
- **回饋**：`report_feedback`（向 Tuist 團隊發送關於工具或提示的報告；僅限 tuist.dev）。
- **代理整合**：`connect_amp_workspace`（授予工作區的 orbs CI 存取帳戶權限）、`disconnect_amp_workspace` 及 `connect_claude_environment`（允許 Claude Managed Agents 環境在 Tuist 沙盒中運行会话）。

`add_organization_member`、`cancel_organization_invitation`、`complete_project_logo_upload`、`disconnect_project_repository`、`update_test_case`、`update_notification_rule`、`delete_notification_rule`、`update_runner_profile`、`delete_runner_profile`、`delete_runner_volume`、`delete_sandbox` 及 `disconnect_amp_workspace` 宣告 `destructiveHint: true`，因為它們會取代或移除現有狀態。`invite_organization_member`、`update_test_case`、`connect_claude_environment` 及 `report_feedback` 宣告 `openWorldHint: true`，因為它們會發送電郵、通知外部 webhook 端點、呼叫 Anthropic 或向 Tuist 團隊發送報告。

個人 Claude 和 ChatGPT 訂閱僅在儀表板的 AI 設定中連接，因此訂閱令牌和登入憑證絕不會經過 Model Context Protocol 客戶端。帳戶設定工具需要用戶認證。它們不適用於專案令牌或普通帳戶令牌。當用戶在瀏覽器中授權客戶端或聲明 `auth.md` 註冊時，Tuist 僅在 Model Context Protocol 端點上將該憑證與用戶關聯，以便設定工具完成請求的工作流程。

Tuist 實作了 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求是無狀態的：客戶端在每次請求中發送其協議元數據，並可直接呼叫工具而無需初始化。`server/discover` 返回伺服器的身份、功能、支援的版本及指令。沒有會話識別符或獨立的事件流。使用 2025-06-18 或 2025-03-26 初始化流程的客戶端仍受支援；它們同樣無需伺服器會話即可運作。

## Model Context Protocol 與技能

Model Context Protocol 工具與 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 的功能可能重疊。鑑於目前兩者的重疊情況，請為每個工作流程選擇一種方法並一致使用，避免在同一流程中混合兩者。

對於支援插件安裝的客戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 一次性安裝兩者。

## 設定

在客戶端中將 `https://tuist.dev/mcp` 添加為遠程 Model Context Protocol 伺服器。伺服器的初始化指令和公開伺服器卡片描述了帶有動態客戶端註冊的 OAuth 2.0 及標準瀏覽器授權流程，無須代理抓取或遵循外部認證文件。這些伺服器範圍的指令保持工作流程指引的通用性：工具認證不會認證本地命令行工具或構建系統整合，代理應通過相關的 Tuist 工具驗證請求的變更。構建系統特定的設定和認證檢查記錄在整合指南和提示中。Tuist 仍分別宣傳 [Open Authorization](https://oauth.net/2/) 發現元數據和目前的 [auth.md protocol](https://workos.com/auth-md)（位於 `https://tuist.dev/auth.md`）。

如果你的其中一個組織強制執行單一登入，則在瀏覽器中授權客戶端需要透過該組織登入的會話，且在需要時 Tuist 會先將你導向提供者。參閱 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>。

該端點接受無狀態的 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），以及較舊的基於會話的生命週期。現有客戶端可以繼續使用其目前的連接方法。

支援 Model Context Protocol 事件的客戶端可以訂閱專案事件。參閱 [Events](#events) 以了解可用事件及交付要求。

已支援遠程瀏覽器認證的客戶端可以繼續在瀏覽器中進行認證。支援 `auth.md` 的客戶端和代理可以匿名註冊、呈現受信任的提供者身份斷言，或啟動服務認證的電郵聲明。註冊會返回由 Tuist 簽名的身份斷言，代理可在標準令牌端點將其交換為一小時的存取令牌。Tuist 發布其公共簽名金鑰，並支援標準令牌撤銷及提供者安全事件交付。

未經認證的代理應讀取 Model Context Protocol 端點返回的 `WWW-Authenticate` 標頭，獲取受保護資源元數據，獲取授權伺服器元數據，並遵循其 `agent_auth.skill` URL。Tuist 亦在未經授權的回應主體中返回相同的本地 `auth_md` URL，以便由語言模型驅動的客戶端無需依賴原生客戶端整合即可發現該流程。部署本地的文件是端點名稱、請求主體、聲明輪詢及斷言交換的權威來源。

在代理啟動電郵聲明之前，必須要求用戶確認其 Tuist 帳戶的電郵地址。不得從提供者個人資料、Git 設定、環境變數或會話元數據中推斷該地址。

該端點使用 `mcp` 範圍組。匿名的預聲明憑證可以發現功能並閱讀公開的整合指引，但不會被視為已登入用戶。在瀏覽器授權或聲明後，憑證將限定於用戶範圍，且每個工具都會應用與儀表板相同的授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析為已認證用戶可讀取的專案。Xcode 和 Gradle 構建工具接受構建 UUID 或儀表板 URL。UUID 必須唯一標識一個專案；如果它出現在多個專案中，工具會返回未找到，而不是選擇另一個專案的報告。專案範圍的儀表板和 API 讀取仍然可用。報告的行為者標識符是未經驗證的標籤，而非憑證或額外的存取權限。

構建列表和詳細資訊工具暴露可選的 `tuist_version` 元數據：用於 Xcode 和 Cargo 的上報 Tuist CLI、用於 Gradle 的 Tuist Gradle 插件，以及用於 Mix 的 `tuist_ex` 庫。Xcode 還從其連結的專案生成事件中暴露 `tuist_generation_version`，這可能與上傳的 CLI 不同。缺失的觀測值為 null，不會從伺服器或其他報告中推斷。Bazel 使用其現有的 `bazel_version`；Once 運行詳細資訊暴露 `once_version`。這些欄位描述報告的版本，而非經過驗證的身份或線路合約版本。REST 構建端點暴露相同的元數據。現有的整合和不穩定測試技能不依賴版本欄位，無需更改工作流程。

Tuist 營運人員透過 Tuist 的內部營運工具調查客戶帳戶，該工具會記錄每次呼叫；直接連接到此端點不會獲得超出用戶自身成員資格以外的存取權限。

### Pulse

Pulse 提供唯讀工具，用於檢視帳戶的營運指標、日誌、追蹤和錯誤，全部透過 `account_handle` 定址。前三者對應 Pulse 頁面及其 REST API；其餘五個讓代理直接探索遙測數據，且沒有等效的 REST 介面：

| 工具 | 用途 | 在 `/api/accounts/:account_handle/pulse` 下的 REST 等效項目 |
| --- | --- | --- |
| `query_pulse` | Pulse 頁面表格 | `GET /:signal` |
| `get_pulse_analytics` | Pulse 頁面小工具 | `GET /:signal/analytics` |
| `get_pulse_error_issue` | 一個錯誤問題及其事件 | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | 即時或範圍 PromQL | 無 |
| `list_pulse_labels` | 標籤名稱，或某個標籤的值 | 無 |
| `search_pulse_logs` | 過濾後的日誌條目 | 無 |
| `search_pulse_traces` | 過濾後的跨度 | 無 |
| `get_pulse_trace` | 單一追蹤的所有跨度 | 無 |

即使帳戶或專案是公開的，Pulse 也僅限於伺服器設定組織的現行成員使用。它需要用戶認證或與用戶關聯的 `mcp` 憑證，以及帳戶讀取授權。專案令牌、普通帳戶令牌、匿名註冊以及沒有組織成員資格的營運人員存取權，都不會授予 Pulse 存取權。憑證無法選擇其他後端或遙測租戶，且只有伺服器設定的帳戶擁有 Pulse 遙測數據，因此沒有工具可以讀取其他帳戶的數據。瀏覽器代理僅在 Pulse 頁面內（在該頁面的帳戶範圍內）接收這些工具。

REST 需要用戶憑證。OAuth 和 `auth.md` 用戶關聯僅在 `/mcp` 端點可用；沒有當前用戶的帳戶憑證將被拒絕，無論相關帳戶的成員資格或可見性如何。

`query_pulse` 接受 `signal`（`metrics`、`logs`、`traces` 或 `errors`）、可選的 `query`，以及 `range`（`15m`、`1h`、`6h` 或 `24h`，預設為 `1h`）。指標接受 PromQL 表達式。日誌、追蹤和錯誤接受文字字串（不區分大小寫），並與日誌主體、跨度名稱和錯誤問題標題進行匹配；`*`（預設值）會選擇所有內容。追蹤行是個別跨度。錯誤行是問題：按服務和指紋分組的事件，包含其事件數量、受影響的帳戶、視窗內的首次和最後一次出現，以及最新事件的標題、責任方、級別和平台。表格接受 `search`、`page`（預設為 `1`）、`page_size`（`1`–`100`，預設為 `20`）、`sort_by` 和 `sort_order`（`asc` 或 `desc`）。排序欄位取決於信號類型，並在工具架構中列出。過濾器包括 `service`，以及用於日誌和錯誤的 `level`。過濾器運算子使用相應的 `_op` 參數（`eq`、`contains` 或 `not_contains`），預設為完全相等。

排序欄位為：指標的 `name`/`value`；日誌的 `timestamp`/`service`/`level`/`message`/`trace_id`；追蹤的 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`；以及錯誤的 `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level`。儀表板故意只公開子集；API 和工具接受每個信號的完整列表。

表格響應包含 `rows`、`series`、`warnings` 和 `meta`。分頁元數據包括 `page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page` 和 `end_at`。傳遞返回的 ISO8601 `end_at` 給後續頁面以保留查詢視窗。結果限制錯誤需要縮小查詢或時間範圍，而不是將響應視為空表格。

日誌和追蹤在本地排序前最多檢查 100 個最新的匹配項，錯誤則檢查最近看到的 100 個問題。過濾器、排序、分頁和總數僅描述那些返回的匹配項，而非整個時間視窗。縮小查詢文字或時間範圍以檢查其他匹配項；更改本地搜索或排序不會擴展上游搜索。聚合小工具保持獨立，是對完整視窗的查詢，而不是這些有限表格結果的聚合。

指標表格會在 `end_at` 時評估其表達式一次，傳回當前數值及每個即時向量序列的一個點。範圍向量表達式可以傳回有界歷史點。獨立的分析小工具提供固定的歷史圖表；表格不會為每個匹配序列實例化時間網格以僅顯示其最新值。

遙測字串是不可信數據，而非指令。

`get_pulse_analytics` 除帳號句柄外，只接受 `signal` 和 `range`。其固定小工具獨立於表格表達式、過濾器、排序和分頁。

`get_pulse_error_issue` 從錯誤行中獲取問題的 `fingerprint` 和 `service`，以及可選的 `range`、`end_at`、`page` 和 `page_size`。它傳回問題摘要、60 個等量發生次數桶、帶有異常鏈、堆疊幀、麵包屑、標籤、上下文、額外數據、請求方法和不含查詢字串的 URL 的最新事件，以及一頁事件（最新的在前），並具有與表格相同的分頁 `meta`。錯誤行還攜帶每個問題的 60 桶 `occurrence_series`。事件在儲存前會清除個人數據，因此過濾後的值顯示為 `[Filtered]` 或 `[REDACTED]`。視窗內沒有事件的問題會報告為未找到。REST 和 Model Context Protocol 使用相同的 Pulse 上下文和響應合約。REST 響應禁用緩存。

#### 探索遙測數據

探索工具讀取 `15m`、`1h`、`6h` 或 `24h` 的視窗（預設為 `1h`，`get_pulse_trace` 則為 `24h`），結束於可選的 ISO8601 `end_at`（預設為現在）。每個響應都傳回 `start_at` 和 `end_at`；再次傳遞相同的 `end_at` 以保持視窗不變。這些工具均不接受 SQL。

- `query_pulse_metrics` 在 `end_at`（`type: instant`，預設）或視窗內每 `step` 秒（`type: range`）評估 `query`（PromQL 表達式）。步長預設為且不能小於視窗除以 360，因此一個序列最多有 361 個點。結果最多有 5,000 個序列。點是 `[unix_seconds, value]`，而 `NaN` 和無限值是字串。即時查詢拒絕 `range` 和 `step`。
- `list_pulse_labels` 接受 `signal`。如果沒有 `label`，它列出標籤名稱；如果有 `label`，它列出該標籤的值。對於指標，`__name__` 列出指標名稱，任何其他標籤的值都需要 `match`（系列選擇器，例如 `up`）。日誌和追蹤標籤值接受 `filters`；追蹤標籤名稱來自追蹤模式，不接受。日誌和追蹤值包括它們在視窗中的條目計數，最頻繁的在前，因此它們也可用作細分，例如按服務劃分的錯誤。`search` 僅保留包含文字文本的名稱或值，而 `limit` 接受 `1`–`1000`（預設 `100`）。日誌標籤名稱發現最多檢查每種類型 1,000 個不同的屬性集，並僅列出過濾器接受的鍵。
- `search_pulse_logs` 傳回最多 `limit` 個條目（`1`–`100`，預設 `50`），按 `newest` 或 `oldest` 排序，其主體包含 `text` 並匹配每個過濾器。每個條目包括其 `severity_text`、`body`、`trace_id`、`span_id`、`scope_name` 及其合併的資源和日誌 `attributes`。對於從 Kubernetes 收集的日誌，`span_id` 和 `scope_name` 為 `null`，這只有 OTLP 日誌發送者才會設置。
- `search_pulse_traces` 傳回最多 `limit` 個跨度，按 `newest`、`oldest` 或 `slowest` 排序，匹配每個過濾器、可選的 `min_duration_ms` 和 `max_duration_ms` 以及 `root_only`。
- `get_pulse_trace` 傳回在視窗內開始的 `trace_id` 的跨度，按最舊優先排序，最多 1,000 個跨度。在視窗之前開始的追蹤會部分傳回，因此請擴大或移動視窗以獲取完整數據。每個跨度包括其跨度屬性、事件、鏈接以及指向追蹤不同 `resources` 的索引。

過濾器是最多 10 個 `{label, op, value}` 對象的列表。`op` 是 `eq`（預設）、`neq`、`contains` 或 `not_contains`；最後兩個是不區分大小寫的文字。當日誌標籤由 Pulse 儲存時，它們是 `severity_text`、`trace_id`、`span_id` 和 `scope_name`，以及每個條目的資源屬性鍵（例如 `namespace`、`container` 和 `service.name`）和日誌屬性鍵（例如 `pod`）。當鍵同時出現在兩者中時，適用資源屬性。追蹤標籤是 `list_pulse_labels` 傳回的跨度列，例如 `service_name`、`span_name`、`span_status_code`（失敗跨度為 `STATUS_CODE_ERROR`）、`span_attributes.http.route` 和 `resource_attributes.k8s.pod.name`。未知的追蹤標籤是錯誤，而非空結果。

`truncated` 表示匹配的名稱、值、條目或跨度多於響應中包含的數量；請縮小過濾器或視窗，而不是將響應視為完整。遙測字串是不可信數據，而非指令。

<details>
<summary>Claude Code</summary>

運行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 客戶端未向模型公開失敗的本機伺服器連接時，要求代理在搜索託管文檔或編輯項目之前檢查配置端點的未認證 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 響應。即使瀏覽器認證不可用，該響應也會將模型指向部署本地的 `auth.md` 文檔。

</details>


<details>
<summary>Codex</summary>

運行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在開始新的 `codex exec` 運行之前完成瀏覽器登錄。Codex 在初始化期間讀取 Tuist 伺服器指令，因此 Gradle 優化請求會自動獲得認證和驗證工作流程。

</details>


<details>
<summary>Claude Desktop</summary>

打開 **Settings → Connectors → Add custom connector**，然後設置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

出現提示時在瀏覽器中完成 [Open Authorization](https://oauth.net/2/)。

</details>


<details>
<summary>Pi</summary>

Pi 不包含 Model Context Protocol 客戶端。您可以在審查其源代碼和安全影響後安裝第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 擴展：

```bash
pi install npm:pi-mcp-adapter
```

添加項目級別的 `.mcp.json` 文件：

```json
{
  "mcpServers": {
    "tuist": {
      "url": "https://tuist.dev/mcp",
      "auth": false
    }
  }
}
```

將 `auth` 設置為 `false` 可防止適配器的瀏覽器認證處理程序隱藏 Tuist 的未經授權響應。無頭代理隨後可以讀取返回的 `auth_md` URL 並遵循 Tuist 的註冊、身份聲明交換和聲明輪詢流程。將交換的訪問令牌配置為 bearer 令牌，或讓代理直接進行認證的 Model Context Protocol 調用。

如果您更喜欢瀏覽器認證，請將 `auth` 設置為 `"oauth"`。對於該流程，在認證完成時保持一個進程處於活動狀態，使用 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc)：

```bash
pi --mode rpc
```

不要將待處理的瀏覽器認證拆分到單獨的 `pi --print` 調用中，因為擁有回調狀態的進程已退出。

</details>


<details>
<summary>OpenCode</summary>

將 Tuist Model Context Protocol 伺服器添加到 `opencode.json`：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tuist": {
      "type": "remote",
      "url": "https://tuist.dev/mcp"
    }
  }
}
```

然後認證伺服器：

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

打開 **Cursor Settings → Tools & Integrations → Model Context Protocol Tools** 並添加：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

使用 **Command Palette → MCP: Add Server**，然後配置一個 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 伺服器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

打開 **Agent panel → Settings → Add Custom Server**，然後設置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果你的代理支援 `auth.md`，它可以匿名啟動而無需打開瀏覽器。當提供者身份已連結時，受信任的提供者身份也可以在不使用瀏覽器的情況下完成。對於服務認證電子郵件、匿名聲明或首次提供者連結，代理會向你顯示 Tuist 驗證連結和六位數代碼。打開連結，登錄，並在 Tuist 頁面上輸入代理的代碼。切勿將代碼發送回代理。Tuist 的授權伺服器元數據直接指向部署自己的 `/auth.md`，其中包含確切的請求和輪詢結構。

## Amp orbs 和 Claude Code 雲端會話中的代理

在連接到 Tuist 帳戶的沙盒中運行的編碼代理可以使用其自身的身份令牌向端點進行認證，無需瀏覽器或存儲的 Tuist 憑證：

- 通過 **Settings → Integrations → Amp** 連接帳戶的 Amp 工作區或項目的 **Amp orbs** 會發送 orb 的 ID 令牌。在 Amp 中，將伺服器的 `Authorization` 標頭設置為 `Bearer ${amp:id-token}`。Amp 為伺服器 URL 的來源鑄造令牌，因此 URL 必須是此 Tuist 實例自身的地址，並在過期前刷新它。為其他來源鑄造的令牌將被拒絕。
- 已連接 Claude Code 環境的 **Claude Code cloud sessions** 會發送 Tuist 作為 `TUIST_OIDC_TOKEN` 傳遞給它們的會話令牌。將標頭設置為 `Bearer ${TUIST_OIDC_TOKEN}`。

Tuist 的 Linux 沙盒不會為你添加伺服器：它們附帶 Tuist CLI（使用相同身份登錄）以及一項技能，該技能會告訴代理何時根據項目歷史檢查其結果。要讓代理也獲得 MCP 工具，請使用上述標頭將伺服器添加到你的 Amp 或 Claude Code 設置，或項目的 `.mcp.json` 中。

這些令牌提供對連接帳戶下每個項目的只讀訪問權限：它們攜帶 `mcp` 組的讀取範圍，而不包含創建、更改或刪除數據（例如靜音或跳過測試）的範圍。斷開工作區或環境連接將在下一個請求時停止訪問，且訪問權限永遠不會超過令牌本身的有效期。連接到多個 Tuist 帳戶的 Amp 工作區將被拒絕，因為其令牌未指定單一帳戶。當缺少連接時，未經授權響應的 `error_description` 會說明這一點。

此只讀訪問權限僅適用於 Model Context Protocol 端點。同一沙盒中的命令行工具和構建系統集成仍會交換令牌以獲取連接的 CI 訪問權限。

## WebMCP

在支援 [WebMCP](https://webmachinelearning.github.io/webmcp) 的瀏覽器中，Tuist 的頁面會使用 `document.modelContext` 註冊工具，因此內置於瀏覽器的代理可以在無需任何額外配置的情況下調用它們。調用在 Tuist 伺服器上運行。

- **Website and documentation pages** 註冊文檔和源代碼工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 和 `read_tuist_file`）。它們不需要你登錄。
- 當你登錄時，**An account's dashboard pages** 會為該帳戶註冊 Tuist 的只讀工具。每個頁面僅註冊其顯示內容所需的工具，針對項目的構建系統：Gradle 項目的構建頁面獲得 Gradle 構建工具，其測試頁面獲得測試和覆蓋率工具，運行器頁面獲得運行器工具，沙盒頁面獲得沙盒工具。每個頁面還獲得文檔工具 `list_projects` 和 `get_project`。工具以登錄用戶的身份運行，因此它們只能訪問你在儀表板中可以讀取的數據，且僅限於你正在查看的帳戶。當你轉移到另一個頁面或帳戶時，工具會被該頁面的工具替換。

創建、更改或刪除數據的工具無法通過 WebMCP 使用，因為瀏覽器代理會在無需你添加的情況下接收這些工具，並讀取構建和測試產生的內容。將 MCP 客戶端連接到 `/mcp` 端點以使用這些工具。

如果組織強制執行單一登錄，請使用其提供者登錄儀表板以使用其工具。

## 構建系統集成使用兩種憑證

用於 Model Context Protocol 工具的憑證不會認證 Gradle 插件或 Bazel 的遠程服務。在代理編輯或驗證 Gradle 或 Bazel 集成之前，它應運行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未經過認證，代理必須停止並要求用戶運行：

```bash
tuist auth login --url https://tuist.dev
```

對於本地或自託管部署，請替換兩個命令和 `tuist.toml` 中的 URL。在所有地方保持主機名拼寫一致。例如，`localhost` 和 `127.0.0.1` 使用單獨存儲的憑證。


## 功能

### 工具

以下工具可通過 Tuist Model Context Protocol 伺服器使用：

每個工具都會發布人類可讀的描述以及明確的輸入和輸出架構。成功的調用返回符合所宣傳輸出架構的結構化內容，並將相同結果序列化為文本，供尚不支持消費結構化內容的客戶端使用。

接受單個記錄標識符（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）的工具也接受該記錄的 Tuist 儀表板 URL。直接從瀏覽器貼上 URL，而不是從中提取標識符。

`get_xcode_build`、`get_test_run`、`get_gradle_build` 和 `get_project` 可以包含 `side_quests`：項目未使用但記錄顯示會有幫助的 Tuist 功能。每個都有一個 `id`、一個說明其所基於證據的 `tip`，以及一個 `docs` 連結。要求代理首先完成用戶的請求，提及適用的支線任務，並且僅在用戶同意時才執行其中一個。它們僅返回給項目帳戶的成員，無論他們是使用用戶會話、MCP 令牌還是代理身份連接：

| ID | 工具 | 建議時機 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | 使用 Xcode 26 或更新版本執行的已處理乾淨構建，沒有運行任何可緩存的編譯任務。 |
| `gradle_build_cache` | `get_gradle_build` | 構建執行了可緩存任務，但 Gradle 的構建緩存沒有為其中任何任務計算鍵值，表示構建緩存已關閉。 |
| `flaky_test_quarantine` | `get_test_run` | 一次運行包含不穩定測試，且項目中沒有啟用的自動化將其靜音或跳過。不建議用於 Once 項目。 |
| `test_sharding` | `get_test_run` | 在 Tuist 支持分片的構建系統中，一次未分片的 CI 運行耗時 10 分鐘或更長。提示會說明選擇性測試當時跳過了多少個測試。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | 一次 CI 運行使用了 GitHub Actions、Bitrise、GitLab CI 或 Buildkite 機器，且該帳戶從未在 Tuist Runners 上運行過作業。僅適用於 tuist.dev。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | 一次 GitHub Actions 運行屬於一個未連接到其 GitHub 倉庫的項目。 |
| `other_build_systems` | `get_project` | 該帳戶並未在所有支持的構建系統中使用 Tuist。提示列出了標識其他構建系統的文件，以便代理檢查倉庫。 |

#### 文檔和社區搜索

這個只讀工具通過驅動文檔網站的同一搜索引擎，搜索 Tuist 的文檔、[應用程式介面](https://en.wikipedia.org/wiki/API)參考、GitHub 發布、社區論壇和 GitHub 問題。發布結果包括產品、版本、發布日期和預發布狀態。默認搜索穩定發布，可以通過 `include_prereleases` 包含預發布。該工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公開的 Tuist 文檔、應用程式介面參考、GitHub 發布、社區討論和 GitHub 問題。可選限制為一個 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 反饋

當 Tuist 工具或提示未按預期工作時（例如結果令人困惑、出現錯誤、數據缺失或缺少功能），代理可以向 Tuist 團隊報告。要求代理建議提交報告，並僅在你同意後發送。每份報告都會開啟與 Tuist 支援的對話，他們可能會通過電子郵件回覆你。報告包括代理的預期、實際發生的情況、可選建議、你的 Tuist 用戶 ID、ハンドル和電子郵件，以及你所屬的組織。代理還可以指明問題發生的帳戶和項目，以便團隊知道跟進哪個組織；僅接受你所屬的帳戶。只有以 Tuist 用戶身份登錄的代理才能發送報告，每個用戶每小時最多可提交 10 份報告。該工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `report_feedback` | 報告 Tuist 工具或提示的問題。可選指定發生問題的 `tool_name`、`account_handle` 和 `project_handle`，並添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基於源代碼的回答

這些只讀工具讓代理使用與託管伺服器一起部署的確切公開 Tuist 源代碼修訂版，作為依賴當前行為的答案的事實來源。它們僅在 `https://tuist.dev/mcp` 可用。

兼容的客戶端在初始化期間會收到關於工具源代碼修訂版、連結和結果限制的事實描述，以及內聯 OAuth 認證資訊。這些描述不規定回答風格或驗證工作流程。用戶可以直接提問，無需先調用 `ask_tuist` 提示；該提示仍可用於明確的基於源代碼的工作流程。

每個操作都有固定的併發、持續時間、遍歷、讀取字節數和響應大小限制。搜索和列表結果包括 `truncated` 和 `truncation_reason` 字段。當結果被截斷時，請縮小路徑、文件模式或搜索詞，而不是將結果視為詳盡無遺。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 通過搜索源代碼文件來回答有關當前行為、默認值、配置、功能開關、錯誤處理或未記錄細節的問題。結果包括周圍行、固定修訂版的源代碼連結和掃描統計信息。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，發現源子系統或附近的測試。列表具有有限的深度和結果數量。 | 無 |
| `read_tuist_file` | 在找到相關路徑後，檢查實現文件、調用站點或測試中的特定行範圍。截斷的響應提供 `next_start_line` 以繼續。 | `path` |

#### 項目

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出經過認證的用戶可用的個人和組織帳戶ハンドル，包括每個帳戶是否可以創建項目。 | 無 |
| `get_organization` | 獲取組織的成員目錄。待處理的邀請需要與儀表板相同的管理員權限；永遠不會返回邀請接受令牌。 | `account_handle` |
| `create_organization` | 為經過認證的用戶創建 Tuist 組織。 | `handle` |
| `create_project` | 在經過認證的用戶可以訪問的帳戶下創建 Tuist 項目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有的 Tuist 用戶添加到組織，或更新現有成員的角色。接受 `user`（預設）、`admin` 或 `viewer`，其中檢視者可以閱讀儀表板和運行記錄，但無法更改任何內容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有的 Tuist 用戶。Tuist 會發送一個有效期為 14 天的接受連結；當伺服器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製連結。接受 `user`（預設）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其連結無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出經過認證的用戶可訪問的所有項目。 | 無 |
| `get_project` | 獲取項目的配置和連接的倉庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將項目連結到帳戶的 GitHub App 安裝可以訪問的 GitHub 倉庫。項目會採用倉庫的預設分支。需要項目管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除項目與其 GitHub 倉庫的連結。需要項目管理員權限。 | `account_handle`, `project_handle` |

#### 帳戶令牌

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳戶令牌元數據，而不暴露令牌值。 | `account_handle` |
| `get_account_token` | 獲取帳戶令牌元數據，而不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出項目令牌元數據，而不暴露令牌值。 | `account_handle`, `project_handle` |

#### 通知規則

這些工具管理經過認證的用戶自己的通知規則：當事件（例如新的預覽）在規則的項目中發生（或者在未列出項目時，在任何你可以收到通知的項目中發生）並滿足其條件時，執行其操作，例如向你的 Tuist 應用設備發送推送通知。如果沒有規則，你將不會收到任何通知。它們需要用戶認證，僅對你自己的規則生效，並且只接受你所屬帳戶的項目。它們不提供給儀表板頁面，因為規則涵蓋你所有的帳戶。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_notification_events` | 列出規則可以訂閱的事件類型，每個類型都帶有用於其條件的 JSON Schema。 | 無 |
| `list_notification_condition_options` | 建議項目中事件的條件值，例如其最近預覽的軌道和分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出你的規則。 | 無 |
| `create_notification_rule` | 根據事件、可選項目和條件以及至少一個操作創建規則。 | `event`, `actions` |
| `update_notification_rule` | 更改規則的啟用狀態、項目、條件或操作。 | `rule_id` |
| `delete_notification_rule` | 刪除規則。 | `rule_id` |

#### 持續集成運行器

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳戶的持續集成運行器作業。 | `account_handle` |
| `get_runner_job` | 獲取持續集成運行器作業，包括其機器是否記憶體不足、停止了什麼以及需要更改什麼。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續集成運行器作業記錄的步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續集成運行器作業記錄的機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續集成運行器作業捕獲的最多 500 行日誌。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳戶的持續集成工作流匯總。 | `account_handle` |
| `list_runner_profiles` | 列出帳戶的持續集成運行器配置文件，包括每個文件的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出運行器配置文件可以使用的機器規格和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 使用平台、機器規格，以及在 macOS 上的 Xcode 版本建立運行器配置文件。可選擇設定哪些分支會儲存其快取卷。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改運行器配置文件的機器規格、Xcode 版本，或哪些分支會儲存其自訂快取卷的變更。省略的欄位會保留其值。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 經用戶確認後刪除運行器配置文件。無法刪除預設配置文件。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

運行器卷工具顯示與「卷」儀表板相同的數據。讀取工具需要運行器存取權限；清除需要帳戶管理權限或 `account:runners:write` 範圍，以及用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名稱和倉庫過濾，並對卷進行排序和分頁。 | `account_handle` |
| `get_runner_volume` | 倉庫、平台、容量、已用空間和最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁的作業和工作流參考、快取狀態、命中結果和掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作業掛載的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存儲序列、作業運行、命中率和趨勢。可選 `volume_id`、`start` 和 `end`（ISO 8601）；預設為七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 刪除卷及其儲存的內容。正在運行的作業會保留其私有副本，但無法儲存它們；後續使用相同密鑰的作業將從空狀態開始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷清單還接受 `name` 和 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的測量值和命中結果保持為 `null`。快取狀態描述卷變更是否已儲存，而非作業成功與否。

#### 沙盒

沙盒工具顯示與沙盒儀表板相同的數據和操作，並具有與 [API](https://tuist.dev/api/docs) 相同的存取權限：帳戶成員可以使用帳戶中每個沙盒的每個工具。唯讀檢視者無法使用它們。帳戶需要啟用沙盒功能。儀表板的沙盒頁面會註冊唯讀工具。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_sandboxes` | 對沙盒進行分頁，顯示其狀態、規格和時間戳。可選 `search`（沙盒中的文本、Amp Orb 或 Anthropic 會話 ID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）和 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的狀態、規格、節點、歸檔和時間戳。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小時數、建立的沙盒數量、會話、設置和啟動持續時間，以及相對於帳戶限制的峰值 vCPU、記憶體和磁碟使用量，並附帶趨勢。可選 `start` 和 `end`（ISO 8601）；預設為 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 啟動一個空白沙盒，並在運行後返回它。可選 `platform`（`linux` 或 `darwin`）、`xcode_version`（macOS 沙盒的確切 Xcode 版本，來自工具描述中列出的版本；意味著 `darwin`）、`template`、`vcpus` 搭配 `memory_mb`（Linux：2x4096、4x8192 或 8x16384，預設 2x4096；macOS：8x8192、8x16384 或 8x24576，預設 8x8192）和 `workspace_gb`。其描述指示代理使用 `mise install` 在 Mac 上安裝倉庫中固定的 Tuist，然後自行 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">使用帳戶的快取</.localized_link>。 | `account_handle` |
| `pause_sandbox` | 將正在運行的沙盒快照儲存到其節點的磁碟。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢復已暫停或歸檔的沙盒。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 排隊將已暫停沙盒的磁碟移動到對象存儲。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 經用戶確認後刪除沙盒及其磁碟。 | `account_handle`, `sandbox_id` |

#### Amp 工作區

這些工具管理 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 工作區連接</.localized_link>，讓 orbs 無需令牌即可登入 Tuist。它們使用與儀表板「整合」頁面相同的管理員專用權限。orb 中的代理可以從 `$AMP_WORKSPACE_ID` 和 `$AMP_PROJECT_ID` 讀取其自身的 ID。連接允許的每個 orb 都會獲得對帳戶中所有項目的 CI 存取權限，因此代理應在連接前與用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 列出帳戶已連接的 Amp 工作區，以及每個工作區限制的項目（如有）。 | `account_handle` |
| `connect_amp_workspace` | 連接 Amp 工作區。可選 `project_id` 將登入限制為單一 Amp 項目的 orbs。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 斷開工作區連接。其 orbs 已擁有的會話在過期前仍然有效。 | `account_handle`, `connection_id` |

#### Claude 環境

這些工具連接 Claude Managed Agents 自託管環境，使其會話在 Tuist 沙盒中運行，如同「設置」→「整合」→「Claude」所做的那樣。它們需要帳戶管理權限並啟用沙盒。代理可以使用 Anthropic 的 API 建立環境，但只有 Claude Console 會生成其環境密鑰，因此代理會向用戶索取該密鑰。Tuist 使用 Anthropic API 密鑰或工作負載身份聯合啟動會話，並在儲存之前使用該憑證獲取環境。Anthropic 端的設置使用用戶自己的 Anthropic 憑證；Tuist 永遠不會接收它們。密鑰會通過客戶端和模型傳遞，因此僅在明確提供時才使用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_claude_environments` | 列出已連接的環境及其使用的憑證，以及聯合規則應信任的發行者 URL 和主體前綴。 | `account_handle` |
| `connect_claude_environment` | 使用 `api_key` 連接環境，或使用 `organization_id`、`workspace_id`、`service_account_id` 和 `federation_rule_id`。可選的 `platform`、`vcpus` 和 `memory_mb` 用於設定沙盒規格。 | `account_handle`, `environment_id`, `environment_key` |

#### Webhooks

Webhook 工具使用與儀表板相同的管理員專用權限。傳送嘗試包含為端點記錄的請求和回應數據，但絕不包含端點簽名密鑰。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳戶的 Webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 獲取 Webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點的傳送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 獲取傳送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 構建

適用於 Xcode、Gradle、Bazel、Mix 和 Cargo 的構建詳情工具會公開現有的 `custom_metadata: {tags, values}` 結構，包括基礎設施觀測數據（如有報告）。值保持為字符串，並保留不熟悉的鍵。例如，`tuist.cpu.available_processors` 描述運行時可用的邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作線程限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆限制，而非主機記憶體。這些是不可信的客戶端觀測數據，並非經過驗證的執行者身份。缺失的觀測數據將保持缺失；導入的日誌和較舊的客戶端可能沒有基礎設施元數據。一旦元數據等待協調的客戶端/協議更新。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出項目的 Xcode 構建運行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 獲取特定 Xcode 構建運行的詳細資訊，包括保存原始 `.xcactivitylog` 的歸檔文件的臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 構建運行的構建目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 構建運行的編譯文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄的構建步驟，包含耗時和結果，但不含日誌文本。 | `build_run_id` |
| `get_xcode_build_step` | 獲取一個記錄的構建步驟，包括其日誌和截斷標誌。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定構建運行的構建問題（警告和錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 構建運行的可緩存任務（緩存命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 構建運行的 [內容定址存儲](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 預設返回每頁 20 個步驟（通過 `page_size` 最多可達 100 個），並提供 `page` 和 `pagination_metadata` 用於導航。使用 `search` 匹配標題、項目或目標，或過濾精確的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以優先顯示最慢的步驟（預設），或按 `start_ms` 排序以顯示時間順序。步驟 ID 用於打破平局，並作為十進制字符串返回以保留其完整的 64 位精度。ID 僅限於單個構建，不應跨構建匹配。

可選的 `start_ms` 和 `end_ms` 選擇與從構建開始算起的毫秒時間範圍重疊的步驟；結束時間為互斥。兩個工具都接受構建 UUID 或儀表板 URL 作為 `build_run_id`。將返回的步驟 `id` 原樣傳遞為 `step_id` 以檢索其日誌。每個步驟的日誌最多保留 64 KiB，`log_truncated` 表示省略的輸出。

處理 Xcode 構建時預設會收集步驟。記錄的步驟數據保留 90 天。列表響應包括 `availability`：`available` 表示存在記錄的步驟，即使過濾器沒有匹配項；`processing` 表示構建仍在處理中且尚無步驟；或 `unavailable` 表示步驟未被記錄或已過期。

相同的操作可通過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上使用，具有相同的過濾器和分頁功能。兩者都需要對構建項目的讀取權限。

#### Gradle 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整的身份驗證、項目設置、Gradle 插件、緩存策略和兩次構建驗證工作流程。代理在編輯現有的 Android 或 Gradle 項目之前應調用此方法。 | 無 |
| `list_gradle_builds` | 列出項目的 Gradle 構建運行，包括自定義元數據。使用可選的 `tag` 參數按自定義標籤過濾。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 獲取構建元數據、任務/緩存計數，以及 `failures`：每個失敗任務和配置步驟的失敗消息。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任務結果、複合構建身份、可緩存性、增量狀態和失敗消息。 | `build_run_id` |
| `list_gradle_build_steps` | 列出定時任務、配置和轉換，支持搜索、元數據和重疊時間過濾器。 | `build_run_id` |
| `get_gradle_build_step` | 通過不透明 ID 檢查記錄的步驟元數據；失敗任務或配置步驟的 `log` 即為其失敗消息。 | `build_run_id`, `step_id` |

Gradle 同 Bazel 嘅步驟列表預設返回 20 個結果（最多 100 個），支援 `search`、精確匹配 `project`、`target`、`category` 同 `status`、重疊時間範圍過濾 `start_ms` / `end_ms`（結束時間互斥），以及按 `duration_ms` 或 `start_ms` 排序。請原樣傳遞返回嘅 ID；佢哋係針對特定構建嘅。列表會顯示 `time_origin` 同 `coverage`。較舊嘅 Gradle 報告使用 `first_recorded_timestamp`，因為無上傳構建開始時間。Bazel 配置文件透過 `trace_profile` 覆蓋範圍同以 `profile_start` 作為時間起點，顯示所有記錄嘅間隔。較舊嘅構建會回退到保留嘅 BEP 摘要。源記錄喺 90 天後過期。Bazel 詳情喺發布時包括經清理嘅動作日誌。失敗任務或配置步驟嘅 Gradle 詳情包括 Tuist Gradle 插件作為 `log` 報告嘅失敗消息：即異常消息及其原因鏈，如同 Gradle 控制台打印咁，但無堆棧追蹤或任務輸出，項目內嘅路徑會轉換為相對路徑，憑證同其他本地路徑會被塗黑，每個步驟最多 16 KiB，每次構建最多 32 個失敗步驟。其他 Gradle 步驟、由較舊插件版本報告嘅構建，以及無憑證嘅報告，其 `log` 為 null。配置步驟喺失敗時報告 `failure`，否則報告 `unknown`。`compare_builds` 提示使用此覆蓋範圍來區分完整嘅 Bazel 追蹤同保留嘅摘要，並指引代理喺檢查更廣泛嘅調用輸出之前，先查看步驟詳情以獲取動作結果同日誌。

單步工具 `get_gradle_build_step` 同 `get_bazel_build_step` 透過 ID 檢索步驟，唔接受時間過濾器；請使用相應嘅列表工具按時間範圍過濾步驟。

如果喺列出步驟同獲取步驟之間收到完整配置文件，從保留摘要返回嘅 Bazel 步驟 ID 仍然可讀。如果索引配置文件嘅步驟數據已過期，則會報告為不可用。Gradle 步驟列表包括持續時間為零嘅緩存同跳過操作。

#### Bazel 調用

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份驗證、項目設置、Bazel 配置同驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成嘅 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 調用，按最新順序排列，包括構建指標、有限執行時間線、關鍵路徑診斷同項目相關嘅遠程緩存總計。可按 `status`、`git_branch`、`git_commit_sha`、`is_ci` 同 `command` 過濾。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 獲取一個已完成嘅 Bazel 調用，包括構建指標、有限執行時間線、關鍵路徑診斷同相關嘅遠程緩存總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄嘅 Bazel 配置文件間隔，帶有過濾器同明確嘅覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄嘅 Bazel 步驟及其發布嘅動作結果同經清理嘅日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按執行順序列出為 Bazel 調用捕獲嘅經清理日誌：Bazel 進度輸出嘅有限尾部同 `test.log` 構件。可選嘅 `stream`（`stdout` 或 `stderr`）、`source`（`progress` 或 `test_log`）、`target_label` 同 `errors` 過濾器可以縮小結果範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 獲取為 Bazel 調用捕獲嘅一個經清理日誌塊。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始 Bazel 遠程緩存觀察記錄，包括其操作、端點同觀察時間，可選擇縮小到特定調用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 獲取一個原始 Bazel 遠程緩存觀察記錄。 | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations` 過濾器係精確匹配，同一秒內完成嘅調用按調用 ID 排序。要查找分支上最新嘅失敗調用，請使用 `status: "failure"`、`git_branch` 同 `page_size: 1` 調用。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` 接受相同嘅過濾器。

喺 `list_bazel_build_steps` 上設置 `remote_execution: true` 以僅返回具有安全關聯服務器階段計時嘅動作（來自索引配置文件）。列表同詳細響應會顯示可選嘅可空值 `remote_queue_ms`、`remote_input_fetch_ms`、`remote_execution_ms` 同 `remote_output_upload_ms`。數值係記錄階段嘅總和，包括動作內嘅重試；缺失或 null 值表示不可用，而非零。呢啲係配置文件觀察結果，並非計費用量或新執行嘅證明，因為緩存嘅服務器結果可能攜帶執行元數據。客戶端上傳被排除。較舊或模糊嘅配置文件即使發生過遠程工作，都可能返回無匹配動作。步驟 REST 端點接受相同嘅 `remote_execution=true` 過濾器。儀表板嘅「Remote execution」標籤頁使用相同嘅查詢同 90 天保留期。

測試日誌攜帶來自測試結果嘅 `target_label` 同嘗試 `status`，所以 `target_label: "//foo:bar_test"` 只返回該目標嘅測試日誌。`errors: true` 返回失敗嘗試嘅測試日誌同包含 Bazel 報告器以 `ERROR:`、`FAIL:` 或 `TIMEOUT:` 開頭行嘅 stderr 進度塊。進度輸出唔歸因於目標，喺記錄歸因之前寫入嘅日誌字段為空。失敗動作及其輸出可以透過 `list_bazel_build_steps` 按目標獲取，每個測試用例嘅失敗可以透過測試運行工具獲取。

#### Cargo 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出項目嘅 Cargo 構建，按最新順序排列。可按 `git_branch`、`status`、`is_ci` 或 `command` 過濾。Cargo 測試執行結果可透過測試工具獲取，而非此構建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 獲取構建元數據、聚合緩存計數，以及最多 500 個帶診斷信息嘅記錄編譯作業。`compilations_truncated` 表示省略嘅作業；診斷信息僅涵蓋返回嘅作業。 | `account_handle`, `project_handle`, `build_id` |

喺 `get_cargo_build` 上設置 `include_cache_inspection: true` 以檢索經過驗證嘅任務決策同 CAS 操作，限制為 4 MB。預設情況下，以及當記錄缺失或無效時，`cache_inspection` 為 null。請尊重其部分捕獲嘅 `truncated` 標誌；傳輸並唔確立每個任務命中嘅本地/遠程來源。HTTP 詳細端點接受相同嘅查詢參數。

#### Mix 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出項目嘅 Mix (Elixir) 編譯構建，按最新順序排列，包括自定義元數據。可按 `git_branch`、`status`、`is_ci` 或 `mix_env` 過濾。 | `account_handle`, `project_handle` |
| `get_mix_build` | 獲取構建元數據、診斷計數同依賴緩存摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 構建追蹤

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_build_trace` | 獲取 Xcode、Gradle、Bazel 或 Mix 構建時間線嘅下載連結，作為可以在 [Perfetto](https://ui.perfetto.dev) 中打開嘅追蹤文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 係構建運行 ID（Bazel 嘅調用 ID）或者構建嘅儀表板 URL。返回嘅 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有該連結嘅人都可以在 `expires_at`（調用後一小時）之前，無需其他憑證即可下載該構建嘅追蹤文件。Agents 可以使用 `curl` 下載，交畀你喺 Perfetto 中打開，或者使用 Perfetto 嘅 `trace_processor` 進行查詢。追蹤文件包含按並行性打包到通道中嘅記錄步驟、跨越整個構建嘅軌道，以及當構建記錄機器指標時嘅 CPU 同內存計數器。它包含與上述步驟工具相同嘅數據，但沒有日誌。儀表板從每個構建嘅時間線標籤頁提供相同嘅文件。

#### Once 運行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出項目嘅 Once 運行，按最新順序排列。可按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 過濾。未完成嘅運行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 獲取運行及其動作總數、緩存摘要，對於測試運行，還包括測試總數。 | `account_handle`, `project_handle`, `run_id` |

Cargo 構建、Mix 構建同 Once 運行 ID 喺項目內係唯一嘅。HTTP API 喺 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 同 `.../once/runs` 提供相同嘅讀取操作，每個都有一個針對單一 ID 嘅詳細端點。

#### 任務、動作、模塊同文件

呢啲項目範圍嘅工具檢查跨運行嘅持久構建身份。首先使用 `list_build_entities`，然後將返回嘅穩定 `id` 連同相同嘅 `kind` 傳遞給 `get_build_entity` 或 `list_build_entity_history`，並附上 `account_handle` 同 `project_handle`。不需要構建或調用標識符。

| 工具 | 描述 | 必需參數 |
| --- | --- | --- |
| `list_build_entities` | 列出喺項目構建中看到嘅某一類任務、模塊、動作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 獲取一個構建實體，包括其本機身份同所選時期嘅分析數據。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個構建實體嘅記錄執行、編譯或緩存事件，按最新順序排列。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 動作 | BEP 報告嘅動作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模塊 | 編譯同模塊緩存事件 |
| `once_actions` | Once 動作 | 執行 |
| `mix_files` | Mix 編譯文件 | 編譯 |
| `mix_modules` | Mix 編譯模塊 | 編譯 |
| `cargo_crates` | Cargo crates | 記錄嘅 rustc 調用 |

呢啲工具正在逐步推出，只返回已啟用它們嘅項目嘅數據；對於其他項目，它們返回錯誤而不是空結果。只有使用其構建工具鏈嘅項目才可用某一種類型。工具接受有界嘅 `start_at`/`end_at` 過濾器、`environment`（`any`、`ci` 或 `local`）同精確嘅 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明嘅 `after`/`before` 遊標。未知嘅計時或緩存觀察仍然不可用，而唔會變成零或缺失。歷史引用記錄嘅父級同本機執行，以便使用現有嘅運行工具進行下鑽。

`get_build_entity` 指標包括 `duration_samples`，即具有記錄計時嘅觀察次數：真正嘅零持續時間計入，缺失嘅計時不計入。此計數可能低於觀察次數；不可用嘅持續時間統計信息保持為 null。

Xcode 模塊持續時間來自構建日誌中測量嘅目標編譯。模塊緩存解析同沒有編譯工作嘅目標唔貢獻持續時間樣本。編譯觀察引用 Xcode 構建；緩存事件引用生成或緩存命令。

Bazel 動作由目標標籤、助記符同配置嘅主要輸出標識，保持單獨嘅動作同配置區分開來，而唔依賴於輸入依賴嘅緩存摘要。歷史記錄 BEP 報告嘅執行，而唔係緩存查找或追蹤配置文件階段。完整嘅執行覆蓋需要 `--build_event_publish_all_actions`；工件交付係盡力而為，所以缺失嘅觀察並唔證明沒有工作運行。較舊嘅 Kura 負載如果沒有穩定身份或執行開始，仍然被接受但未被索引。缺失嘅結束時間測量保持不可用，真正嘅零持續時間計入。

Mix 模塊持續時間測量包含文件嘅編譯，而唔係獨立測量嘅模塊工作。Once 動作喺客戶端報告目標映射時使用聲明嘅目標/能力/索引槽；僅診斷標籤唔係穩定身份。現有客戶端同運行級別工具保持不變支持。

Cargo crates 按精確記錄嘅 crate 根、名稱同類型分組。檢出路徑更改可能會分割歷史，並且構建配置文件、功能同目標三元組唔作區分。歷史測量 rustc 調用，而唔係每個文件嘅工作或緩存命中；缺失嘅作業並唔確立刪除或完整嘅工作區清單。

分析讀取有受限制嘅內存同執行時間。如果查詢超過這些限制，工具將返回錯誤，而唔係發明一個空結果。

新觀察喺部署後被索引；此功能唔回填現有嘅運行遙測數據。身份元數據喺 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link> 下比單個觀察存活更久。

#### 測試

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出項目嘅`selective_testing_strategy`。按 `selective_testing` 篩選（`coverage`，包括基於覆蓋率選擇嘅回退，或 `module_hash`）。`query` 字段為 `git_branch`、`scheme`、`status` 同 `selective_testing`：`field:"value"` 精確匹配，`field~"value"` 匹配不區分大小寫嘅子字符串（唔適用於 `selective_testing`），前置 `-` 則否定任一運算符。例如，`-git_branch~"gh-readonly-queue"` 排除合併隊列分支。以空格分隔嘅查詢過濾器同明確參數以 AND 語義組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 獲取測試執行嘅詳細指標，包括其代碼覆蓋率（`coverage`：是否測量咗任何內容、行數同數值，以及是否部分覆蓋或從_dirty checkout_ 運行）、選擇性測試摘要（`selective_testing`：策略、基準提交，以及請求、選擇、跳過同估計嘅測試計數，這些用於計算測試選擇有效性），以及結果包 (`.xcresult`) 同會話存檔嘅臨時下載 URL。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行嘅測試模塊運行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行嘅測試套件運行，可選按模塊篩選。 | `test_run_id` |
| `list_test_cases` | 列出項目嘅測試案例（支持如 `flaky` 等過濾器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 獲取測試案例嘅詳細指標，包括可靠性比率、不穩定比率同運行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例運行，可選按測試案例或測試執行篩選。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 獲取特定測試案例運行嘅失敗詳情同重複次數，如果其運行嘅基於覆蓋率嘅選擇保留咗該測試，則說明原因（`selective_testing`：決策、原因、匹配嘅變更文件同分片）。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例運行嘅附件。每個附件都包含一個臨時下載 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例嘅狀態變更，例如靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例嘅狀態或不穩定分類。變更可以向配置嘅 webhook 端點（包括外部服務）發送事件。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試執行嘅選擇性測試目標結果。 | `test_run_id` |
| `list_selective_testing_tests` | 列出測試執行嘅基於覆蓋率嘅選擇所決定、選擇同跳過嘅測試，包括每個決策嘅原因、選擇它嘅變更文件、其分片以及其在運行中嘅結果。按 `decision`、`reason` 或 `search` 篩選。 | `test_run_id` |
| `list_selective_testing_changed_files` | 列出自測試執行嘅基於覆蓋率嘅選擇基準以來變更嘅文件，包括每個文件選擇咗幾多個測試，以及它是否係一個追蹤文件，其變更會導致選擇回退。 | `test_run_id` |
| `get_coverage` | 獲取項目及其目標嘅代碼覆蓋率，基於某個提交或分支嘅最新完整提交。如果沒有 `git_commit_sha` 或 `branch`，則讀取默認分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出某個提交嘅代碼覆蓋率測量嘅文件及其行覆蓋率，基於某個提交或分支嘅最新完整提交。支持 `search`、排序同分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 獲取文件嘅代碼覆蓋率及其函數，基於某個提交或分支嘅最新完整提交。設置 `include_lines` 以獲取每行嘅執行計數。 | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | 列出具有代碼覆蓋率嘅分支，默認分支排在前面。 | `account_handle`, `project_handle` |
| `list_coverage_commits` | 列出分支嘅提交及其覆蓋率狀態（`complete`、`incomplete`、`in_progress`、`not_measured`）、數值，以及與之前完整提交相比嘅變化，最新嘅排在前面。使用游標分頁。 | `account_handle`, `project_handle` |
| `list_coverage_runs` | 列出在提交或分支後面具有代碼覆蓋率嘅測試執行，每個標記為 `full`、`partial` 或 `discarded`（dirty checkout）。使用游標分頁。 | `account_handle`, `project_handle` |
| `list_coverage_targets` | 列出每個目標嘅提交覆蓋率，然後係從二進制緩存中獲取但沒有覆蓋率計數器嘅目標（`measured: false`）。支持 `search`、排序同分頁。 | `account_handle`, `project_handle` |

代碼覆蓋率工具僅對啟用咗代碼覆蓋率嘅帳戶可用。

#### 捆綁包

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出項目嘅捆綁包（應用二進制文件）。可選按 `git_branch` 同 `tags` 篩選（所有標籤必須精確匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 獲取特定捆綁包嘅詳細信息，包括自定義標籤。 | `bundle_id` |
| `get_bundle_artifact_tree` | 將捆綁包嘅完整工件樹作為按路徑排序嘅平面列表獲取。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以區分構建變體或環境。標籤係區分大小寫嘅標籤，包含字母、數字、連字符或下劃線，最多 10 個標籤，每個標籤最多 50 個字符。列表同詳細結果包括 `custom_metadata.tags`。分頁計數同分支過濾器應用於帶標籤嘅結果；省略 `tags` 則保留未過濾行為。無效嘅標籤過濾器會返回錯誤，而唔係擴大查詢範圍。

#### 生成

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_generations` | 列出項目嘅生成執行。 | `account_handle`, `project_handle` |
| `get_generation` | 獲取特定生成執行嘅詳細信息。 | `generation_id` |

#### 緩存執行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出項目嘅緩存執行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 獲取特定緩存執行嘅詳細信息。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出生成或緩存執行嘅模塊緩存目標，顯示每個目標嘅快取命中/未命中狀態同診斷組件哈希值，包括額外嘅哈希輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_previews` | 列出項目可共享嘅應用預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 獲取預覽及其構建嘅臨時下載 URL。 | `preview_id` |
| `get_latest_preview` | 查找運行中應用二進制文件嘅最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出項目嘅自動化警報。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 獲取自動化警報。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警報嘅修訂歷史。操作憑證已被遮蓋。 | `alert_id` |
| `list_project_notification_alerts` | 列出項目通知警報規則。需要與儀表板設置頁面相同嘅管理員權限。Webhook 地址已被遮蓋。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期嘅客戶端可以調用 `events/list` 來發現事件及其負載架構：

| 事件 | 發送時間 | 訂閱過濾器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從非不穩定變為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持續集成嘅 Xcode、Gradle 或 Bazel 構建以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持續集成嘅測試執行以失敗結束，包括合併嘅分片執行或已放棄嘅執行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist runner 作業以失敗完成。 | `account_handle` |

要訂閱，客戶端需調用 `events/subscribe`，並提供事件名稱、上面列出嘅 `arguments` 句柄，以及包含 `https://` 回調 URL 同 `whsec_` 簽名密鑰嘅 `webhook` 交付。項目事件需要帳戶成員資格以及對相應測試或構建數據嘅讀取權限；runner 作業事件需要帳戶成員資格同 runner 讀取權限。已聲明嘅 [`auth.md`](https://workos.com/auth-md) 訪問令牌、已聲明嘅帳戶令牌同瀏覽器授權授予可以創建訂閱；當相關憑證不再有效時，交付將停止。每個用戶最多可以保留 25 個活躍訂閱。Tuist 會在保存訂閱之前向回調發送驗證挑戰。回調必須返回包含相同 `challenge` 值嘅對象。訂閱默認持續七天，可以通過再次訂閱來刷新，當用戶嘅訪問權限或憑證被移除時，交付將停止。可選嘅 `ttlMs` 限制在一小時到 30 天之間。Tuist 會重試超時嘅回調，並在至少三次連續超時（跨越五分鐘）後取消訂閱；恢復回調後請重新訂閱。

當事件發生時，Tuist 會將其資源標識符同儀表板 URL 發送到回調。構建同測試執行失敗還包括 `is_ci` 同 `git_branch`，以便客戶端可以忽略本地失敗或按分支過濾。構建事件包括 `build_system`；runner 作業事件包括 `workflow_job_id` 同 `workflow_run_id`。請求包括訂閱標識符同 [Standard Webhooks](https://www.standardwebhooks.com/) 簽名頭部，以便客戶端驗證其來源。Tuist 會重試失敗嘅交付，因此客戶端應使用穩定嘅 `eventId` 來丟棄重複項。負載省略咗測試名稱、日誌同失敗消息；客戶端可以通過上述工具獲取這些詳細信息，並決定是否通知團隊或開始調試。客戶端可以使用 `events/unsubscribe` 停止交付。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 指導你修復不穩定測試，通過分析失敗模式、識別根本原因並應用針對性修正。 |
| `compare_builds` | 指導你比較構建以識別性能回歸、緩存變化同構建問題。為 Xcode、Gradle、Bazel 同 Cargo 項目使用原生工具。Cargo 比較保留部分編譯器覆蓋率，並區分估計嘅編譯器工作同已節省嘅時間。 |
| `compare_test_runs` | 指導你比較兩次測試執行，以識別回歸、新失敗同不穩定測試。 |
| `compare_bundles` | 指導你比較兩個捆綁包，以識別構件樹中嘅大小變化。 |
| `compare_test_case` | 指導你比較一個測試案例喺兩個分支或時間段內嘅行為。 |
| `compare_generations` | 指導你比較兩次生成運行，以識別性能回歸同模塊緩存變化。 |
| `compare_cache_runs` | 指導你比較兩次緩存運行，以識別緩存有效性變化同目標級別回歸。 |
| `integrate_gradle_project` | 指導你將 Tuist 集成到現有 Gradle 項目中。包括獨立嘅工具同 Gradle 認證、帳戶發現、項目創建、遠程緩存策略、構建洞察同讀回驗證。 |
| `integrate_bazel_project` | 指導你創建或選擇 Bazel 項目、認證命令行、配置遠程緩存同構建洞察，並通過 Tuist 構建數據驗證集成。 |
| `integrate_xcode_project` | 指導你將 Tuist 集成到現有 Xcode 項目中。支持 Xcode 緩存、構建洞察、測試洞察同測試分片。 |
| `ask_tuist` | 使用公開材料作為上下文，並以專注嘅實現同測試證據作為當前行為嘅事實來源，來回答 Tuist 問題。它需要 `question` 並引用修訂固定嘅證據。 |

項目數據提示接受 `account_handle` 同 `project_handle`，將調查範圍限定於特定項目。比較提示還接受 `base` 同 `head` 參數，以指定要比較嘅兩個項目（按 ID、儀表板 URL 或分支名稱）。`ask_tuist` 接受 `question` 而非項目參數。`integrate_gradle_project` 還接受 `features`，即要應用嘅 Gradle 集成嘅逗號分隔列表：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 同 `test_sharding`。`integrate_bazel_project` 接受可選嘅 `server_url`，用於自託管或本地安裝。`integrate_xcode_project` 接受帶有 `xcode_cache`、`build_insights`、`test_insights` 同 `test_sharding` 嘅 `features`。

#### Gradle 集成提示功能

`integrate_gradle_project` 提示同 `get_gradle_integration_guide` 工具記錄咗完整嘅設置工作流程。該工具還被服務器嘅初始化指令引用，這使得未枚舉提示嘅代理能夠發現它。

| 功能 | 代理配置嘅內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 嘅構建緩存，配置 Tuist 遠程緩存上傳策略，並建議僅從具有本地只讀用法嘅持續集成 runner 上傳。 |
| `build_insights` | 應用 Tuist Gradle 插件，並喺需要時配置構建分析上傳行為。 |
| `test_insights` | 應用 Tuist Gradle 插件，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 指導設置不穩定測試檢測、可選嘅 Gradle Test Retry 插件用法同測試隔離配置。 |
| `test_sharding` | 添加用於 `tuistPrepareTestShards`、分片矩陣生成同基於 `TUIST_SHARD_INDEX` 嘅測試執行嘅持續集成工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或喺編輯 Gradle 項目之前從請求中推斷出最小嘅有用集合。

#### Xcode 集成提示功能

`integrate_xcode_project` 提示記錄咗 Tuist 支持嘅每種 Xcode 集成：

| 功能 | 代理配置嘅內容 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成項目緩存設置、手動 Xcode 緩存構建設置，以及僅限於持續集成 runner 嘅上傳策略。 |
| `build_insights` | 通過 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 同可選嘅機器指標。 |
| `test_insights` | 配置 `tuist inspect test`、方案測試後操作同持續集成測試運行嘅結果捆綁包生成。 |
| `test_sharding` | 添加帶有 `TUIST_SHARD_INDEX` 嘅 Xcode 或生成項目分片規劃同分片執行工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或喺編輯 Xcode 項目之前從請求中推斷出最小嘅有用集合。
