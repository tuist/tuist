---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 MCP 端點，讓 AI 代理存取測試洞察同更多資訊。"
}
---
# 模型上下文協定

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一項開放標準，讓人工智能代理能夠與外部服務及數據來源互動。它令 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等應用程式，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等編輯器能夠與 Tuist 互通。

Tuist 在 `https://tuist.dev/mcp` 託管伺服器端 Model Context Protocol 端點。將你的客戶端連接至此端點後，代理即可存取你的 Tuist 專案數據，包括測試洞察、不穩定測試分析等。大多數工具讀取的 Tuist 數據，是已認證用戶在儀表板中本來就能看見的資料。每個工具都會標示註釋，說明其是否為唯讀、是否可能導致難以復原的變更（`destructiveHint`），以及是否能存取 Tuist 以外的資源（`openWorldHint`）。以下工具會變更狀態，且各自受用戶於帳戶或專案的權限限制：

- **組織與成員**：`create_organization`、`add_organization_member`（新增現有用戶或更改成員角色）、`invite_organization_member`（向任何地址發送邀請電郵）及 `cancel_organization_invitation`。
- **專案**：`create_project`、`start_project_logo_upload` 及 `complete_project_logo_upload`（更換標誌）、`connect_project_repository` 及 `disconnect_project_repository`（GitHub 儲存庫連結）。
- **測試**：`update_test_case`（將測試案例設為靜音、跳過、重新啟用或標記為不穩定；此變更可能會觸發帳戶的 webhook 端點）。
- **通知規則**：`create_notification_rule`、`update_notification_rule` 及 `delete_notification_rule`。
- **持續整合執行器**：`create_runner_profile`、`update_runner_profile`（縮小可儲存快取卷宗的工作範圍會捨棄待處理的儲存作業）、`delete_runner_profile` 及 `delete_runner_volume`（刪除卷宗內已儲存的內容）。
- **沙盒**：`create_sandbox`、`pause_sandbox`、`resume_sandbox`、`archive_sandbox` 及 `delete_sandbox`（刪除其磁碟）。
- **回饋**：`report_feedback`（向 Tuist 團隊發送關於工具或提示的報告；僅限 tuist.dev）。
- **代理整合**：`connect_amp_workspace`（授予工作區的 orbs CI 存取帳戶權限）、`disconnect_amp_workspace` 及 `connect_claude_environment`（允許 Claude Managed Agents 環境在 Tuist 沙盒中執行工作階段）。

`add_organization_member`、`cancel_organization_invitation`、`complete_project_logo_upload`、`disconnect_project_repository`、`update_test_case`、`update_notification_rule`、`delete_notification_rule`、`update_runner_profile`、`delete_runner_profile`、`delete_runner_volume`、`delete_sandbox` 及 `disconnect_amp_workspace` 會標示 `destructiveHint: true`，因為它們會取代或移除現有狀態。`invite_organization_member`、`update_test_case`、`connect_claude_environment` 及 `report_feedback` 會標示 `openWorldHint: true`，因為它們會發送電郵、通知外部 webhook 端點、呼叫 Anthropic，或向 Tuist 團隊發送報告。

個人 Claude 及 ChatGPT 訂閱僅在儀表板的 AI 設定中連接，因此訂閱令牌及登入憑證絕不會經過 Model Context Protocol 客戶端。帳戶設定工具需要用戶認證。專案令牌或一般帳戶令牌無法使用這些工具。當用戶在瀏覽器中授權客戶端或聲明 `auth.md` 註冊時，Tuist 僅在 Model Context Protocol 端點將該憑證與用戶關聯，以便設定工具完成所需的工作流程。

Tuist 實作了 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求為無狀態：客戶端會在每次請求中傳送協定元數據，並可直接呼叫工具而無需初始化。`server/discover` 會返回伺服器的身份、功能、支援的版本及指示。沒有工作階段識別碼或獨立的事件串流。使用 2025-06-18 或 2025-03-26 初始化流程的客戶端仍獲支援；它們同樣無需伺服器工作階段即可運作。

## Model Context Protocol 與技能比較

Model Context Protocol 工具與 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 的功能可能重疊。鑑於目前兩者存在重疊，請為每個工作流程選擇其中一種方法並一致使用，避免在同一流程中混合使用兩者。

對於支援外掛安裝的客戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 一次性安裝兩者。

## 設定

在客戶端中將 `https://tuist.dev/mcp` 添加為遠端 Model Context Protocol 伺服器。伺服器的初始化指示及公開伺服器卡片描述了帶有動態客戶端註冊的 OAuth 2.0 及標準瀏覽器授權流程，無需代理抓取或遵循外部驗證文件。這些伺服器範圍的指示保持工作流程指引的通用性：工具驗證不會驗證本地命令行工具或構建系統整合，代理應通過相關的 Tuist 工具驗證請求的變更。構建系統特定的設定及驗證檢查記錄在整合指南及提示中。Tuist 仍分別宣傳 [Open Authorization](https://oauth.net/2/) 發現元數據及位於 `https://tuist.dev/auth.md` 的當前 [auth.md protocol](https://workos.com/auth-md)。

如果你的其中一個組織強制執行單一登入，在瀏覽器中授權客戶端需要透過該組織登入的工作階段，且在必要時 Tuist 會先將你導向至提供者。參閱 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>。

該端點接受無狀態的 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），以及較舊的基於工作階段的生命週期。現有客戶端可以繼續使用其目前的連接方法。

支援 Model Context Protocol 事件的客戶端可以訂閱專案事件。有關可用事件及交付要求，請參閱 [Events](#events)。

已支援遠端瀏覽器驗證的客戶端可以繼續在瀏覽器中進行驗證。支援 `auth.md` 的客戶端及代理可以匿名註冊、出示受信任的提供者身份斷言，或啟動服務驗證的電郵聲明。註冊會返回由 Tuist 簽名的身份斷言，代理可在標準令牌端點將其交換為一小時的存取令牌。Tuist 會發布其公共簽名金鑰，並支援標準令牌撤銷及提供者安全事件交付。

未驗證的代理應讀取 Model Context Protocol 端點返回的 `WWW-Authenticate` 標頭，獲取受保護資源元數據，獲取授權伺服器元數據，並遵循其 `agent_auth.skill` URL。Tuist 亦會在未經授權的回應主體中返回相同的本地 `auth_md` URL，以便由語言模型驅動的客戶端無需依賴原生客戶端整合即可發現該流程。部署本地的文件是端點名稱、請求主體、聲明輪詢及斷言交換的真實來源。

在代理啟動電郵聲明之前，必須要求用戶確認其 Tuist 帳戶的電郵地址。不得從提供者個人資料、Git 設定、環境變數或工作階段元數據中推斷該地址。

該端點使用 `mcp` 範圍群組。匿名的預聲明憑證可以發現功能並閱讀公開的整合指南，但不會被視為已登入用戶。在瀏覽器授權或聲明後，憑證將限定於用戶範圍，且每個工具都會應用與儀表板相同的授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析為已驗證用戶已有權讀取的專案。Xcode 及 Gradle 構建工具接受構建 UUID 或儀表板 URL。UUID 必須精確識別一個專案；如果它出現在多個專案中，工具會返回「未找到」，而不會選擇另一個專案的報告。專案範圍的儀表板及 API 讀取仍然可用。報告的行為者標識符是未經驗證的標籤，而非憑證或額外的存取權限。

構建列表及詳細資訊工具提供可選的 `tuist_version` 元數據：用於 Xcode 及 Cargo 的上報 Tuist CLI、用於 Gradle 的 Tuist Gradle 外掛，以及用於 Mix 的 `tuist_ex` 函式庫。Xcode 亦會從其連結的專案生成事件中公開 `tuist_generation_version`，這可能與上傳的 CLI 不同。缺失的觀測值為 null，不會從伺服器或其他報告中推斷。Bazel 使用其現有的 `bazel_version`；Once 運行詳細資訊則公開 `once_version`。這些欄位描述報告的版本，而非經過驗證的身份或線路合約版本。REST 構建端點公開相同的元數據。現有的整合及不穩定測試技能不依賴版本欄位，無需更改工作流程。

Tuist 營運人員調查客戶帳戶時，是透過 Tuist 的內部營運工具進行的，該工具會記錄每次調用；直接連接到此端點不會獲得超出用戶自身成員資格以外的任何存取權限。

### Pulse

Pulse 提供唯讀工具，用於查看帳戶的營運指標、日誌、追蹤及錯誤，全部通過 `account_handle` 定址。前三個對應 Pulse 頁面及其 REST API；其餘五個讓代理直接探索遙測數據，且沒有等效的 REST 接口：

| 工具 | 用途 | `/api/accounts/:account_handle/pulse` 下的 REST 等效項 |
| --- | --- | --- |
| `query_pulse` | Pulse 頁面表格 | `GET /:signal` |
| `get_pulse_analytics` | Pulse 頁面小部件 | `GET /:signal/analytics` |
| `get_pulse_error_issue` | 一個錯誤問題及其事件 | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | 即時或範圍 PromQL | 無 |
| `list_pulse_labels` | 標籤名稱，或某個標籤的值 | 無 |
| `search_pulse_logs` | 過濾後的日誌條目 | 無 |
| `search_pulse_traces` | 過濾後的跨度 | 無 |
| `get_pulse_trace` | 單一追蹤的所有跨度 | 無 |

Pulse 僅限於伺服器配置組織的當前成員，即使帳戶或專案是公開的。它需要用戶驗證或與用戶關聯的 `mcp` 憑證及帳戶讀取授權。專案令牌、普通帳戶令牌、匿名註冊以及沒有組織成員資格的營運人員存取權限均不授予 Pulse 存取權。憑證無法選擇其他後端或遙測租戶，且只有伺服器配置的帳戶擁有 Pulse 遙測數據，因此沒有工具可以讀取其他帳戶的數據。瀏覽器代理僅在 Pulse 頁面內、在該頁面的帳戶範圍內接收這些工具。

REST 需要用戶憑證。OAuth 及 `auth.md` 用戶關聯僅在 `/mcp` 端點上可用；沒有當前用戶的帳戶憑證將被拒絕，無論相關帳戶的成員資格或可見性如何。

`query_pulse` 接受 `signal`（`metrics`、`logs`、`traces` 或 `errors`）、可選的 `query` 及 `range`（`15m`、`1h`、`6h` 或 `24h`，預設為 `1h`）。指標接受 PromQL 表達式。日誌、追蹤及錯誤接受文字字面量（不區分大小寫），並與日誌主體、跨度名稱及錯誤問題標題進行匹配；`*`（預設值）會選擇所有內容。追蹤行是個別跨度。錯誤行是問題：按服務及指紋分组的事件，包含其事件計數、受影響的帳戶、視窗內的首次及最後一次出現，以及最新事件的標題、責任方、級別及平台。表格接受 `search`、`page`（預設為 `1`）、`page_size`（`1`–`100`，預設為 `20`）、`sort_by` 及 `sort_order`（`asc` 或 `desc`）。排序欄位取決於信號，並列在工具架構中。過濾器包括 `service`，以及用於日誌及錯誤的 `level`。過濾器運算子使用相應的 `_op` 參數（`eq`、`contains` 或 `not_contains`），預設為完全相等。

排序欄位為：指標的 `name`/`value`；日誌的 `timestamp`/`service`/`level`/`message`/`trace_id`；追蹤的 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`；以及錯誤的 `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level`。儀表板有意只公開子集；API 及工具接受每個信號的完整列表。

表格回應包含 `rows`、`series`、`warnings` 及 `meta`。分頁元數據包括 `page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page` 及 `end_at`。傳遞返回的 ISO8601 `end_at` 給後續頁面以保留查詢視窗。結果限制錯誤需要縮小查詢或時間範圍，而不是將回應視為空表格。

日誌及追蹤在本地排序前最多檢查最新的 100 個匹配項，錯誤則檢查最近看到的 100 個問題。過濾器、排序、分頁及總數僅描述那些返回的匹配項，而非整個時間視窗。縮小查詢文字或時間範圍以檢查其他匹配項；更改本地搜索或排序不會擴展上游搜索。聚合小部件保持為獨立的完整視窗查詢，而不是這些有界表格結果的聚合。

指標表格會在 `end_at` 時評估其表達式一次，返回當前值及每個即時向量序列的一個點。範圍向量表達式可以返回有界的歷史點。獨立的分析小部件提供固定的歷史圖表；表格不會為每個匹配的序列具體化時間網格以僅顯示其最新值。

遙測字符串是不可信的數據，而非指令。

`get_pulse_analytics` 除賬戶句柄外，僅接受 `signal` 和 `range`。其固定小部件獨立於表格表達式、過濾器、排序及分頁。

`get_pulse_error_issue` 從錯誤行中獲取問題的 `fingerprint` 和 `service`，以及可選的 `range`、`end_at`、`page` 和 `page_size`。它返回問題摘要、60 個相等的出現次數桶、帶有異常鏈、堆棧幀、麵包屑、標籤、上下文、額外數據、請求方法及不含查詢字符串的 URL 的最新事件，以及一頁按最新優先排序的事件，並具有與表格相同的分頁 `meta`。錯誤行還包含每個問題的 60 桶 `occurrence_series`。事件在存儲前會清除個人數據，因此過濾後的值顯示為 `[Filtered]` 或 `[REDACTED]`。視窗內沒有事件的問題會被報告為未找到。REST 和 Model Context Protocol 使用相同的 Pulse 上下文和響應合約。REST 響應禁用緩存。

#### 探索遙測數據

探索工具讀取 `15m`、`1h`、`6h` 或 `24h`（默認 `1h`，`get_pulse_trace` 則為 `24h`）的視窗，結束於可選的 ISO8601 `end_at`（默認為現在）。每個響應都返回 `start_at` 和 `end_at`；再次傳遞相同的 `end_at` 以保持視窗。這些工具均不接受 SQL。

- `query_pulse_metrics` 在 `end_at`（`type: instant`，默認）或視窗內每 `step` 秒（`type: range`）評估 `query`（一個 PromQL 表達式）。步長默認為且不能小於視窗除以 360，因此一個序列最多有 361 個點。結果最多有 5,000 個序列。點為 `[unix_seconds, value]`，而 `NaN` 和無限值為字符串。即時查詢拒絕 `range` 和 `step`。
- `list_pulse_labels` 接受一個 `signal`。如果不帶 `label`，它列出標籤名稱；如果帶 `label`，它列出該標籤的值。對於指標，`__name__` 列出指標名稱，而其他任何標籤的值都需要 `match`（一個系列選擇器，例如 `up`）。日誌和追蹤標籤值接受 `filters`；追蹤標籤名稱來自追蹤架構，因此不接受。日誌和追蹤值包括其在視窗中的條目計數，按頻率最高優先排序，因此它們也可用作細分，例如按服務劃分的錯誤。`search` 僅保留包含字面文本的名稱或值，而 `limit` 接受 `1`–`1000`（默認 `100`）。日誌標籤名稱發現最多檢查每種類型 1,000 個不同的屬性集，並僅列出過濾器接受的鍵。
- `search_pulse_logs` 返回最多 `limit` 個條目（`1`–`100`，默認 `50`），按 `newest` 或 `oldest` 優先排序，其主體包含 `text` 且匹配每個過濾器。每個條目包括其 `severity_text`、`body`、`trace_id`、`span_id`、`scope_name` 及其合併的資源和日誌 `attributes`。`span_id` 和 `scope_name` 對於從 Kubernetes 收集的日誌為 `null`，這僅由 OTLP 日誌發送者設置。
- `search_pulse_traces` 返回最多 `limit` 個跨度，按 `newest`、`oldest` 或 `slowest` 優先排序，匹配每個過濾器、可選的 `min_duration_ms` 和 `max_duration_ms` 以及 `root_only`。
- `get_pulse_trace` 返回在視窗內開始的 `trace_id` 的跨度，按最舊優先排序，最多 1,000 個跨度。在視窗之前開始的追蹤會部分返回，因此請擴大或移動視窗以獲取完整數據。每個跨度包括其跨度屬性、事件、鏈接以及指向追蹤獨特 `resources` 的索引。

过滤器是最多 10 个 `{label, op, value}` 对象的列表。`op` 为 `eq`（默认）、`neq`、`contains` 或 `not_contains`；最后两个为不区分大小写的字面量。当日志标签由 Pulse 存储时，它们是 `severity_text`、`trace_id`、`span_id` 和 `scope_name`，以及每个条目的资源属性键（如 `namespace`、`container` 和 `service.name`）和日志属性键（如 `pod`）。当一个键同时出现时，应用资源属性。追踪标签是 `list_pulse_labels` 返回的跨度列，如 `service_name`、`span_name`、`span_status_code`（失败跨度为 `STATUS_CODE_ERROR`）、`span_attributes.http.route` 和 `resource_attributes.k8s.pod.name`。未知的追踪标签会导致错误，而非空结果。

`truncated` 表示匹配的名称、值、条目或跨度多于响应中包含的数量；请缩小过滤器或视窗范围，而不是将响应视为完整。遥测字符串是不可信的数据，而非指令。

<details>
<summary>Claude Code</summary>

运行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

当无头 Claude Code 客户端未向模型暴露失败的本机服务器连接时，要求代理在搜索托管文档或编辑项目之前检查配置端点的未经身份验证的 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 响应。该响应会将模型指向部署本地的 `auth.md` 文档，即使浏览器身份验证不可用。

</details>


<details>
<summary>Codex</summary>

运行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在开始新的 `codex exec` 运行之前完成浏览器登录。Codex 在初始化期间读取 Tuist 服务器指令，因此 Gradle 优化请求会自动接收身份验证和验证工作流。

</details>


<details>
<summary>Claude Desktop</summary>

打开 **Settings → Connectors → Add custom connector**，然后设置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

在提示时在浏览器中完成 [Open Authorization](https://oauth.net/2/)。

</details>


<details>
<summary>Pi</summary>

Pi 不包含 Model Context Protocol 客户端。在审查其源代码和安全影响后，你可以安装第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 扩展：

```bash
pi install npm:pi-mcp-adapter
```

添加项目级 `.mcp.json` 文件：

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

将 `auth` 设置为 `false` 可防止适配器的浏览器身份验证处理程序隐藏 Tuist 的未经授权响应。无头代理随后可以读取返回的 `auth_md` URL，并遵循 Tuist 的注册、身份断言交换和声明轮询流程。将交换的访问令牌配置为 bearer 令牌，或让代理直接进行经过身份验证的 Model Context Protocol 调用。

如果你更喜欢浏览器身份验证，请将 `auth` 设置为 `"oauth"`。对于该流程，在身份验证完成时，使用 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 保持一个进程存活：

```bash
pi --mode rpc
```

不要将待处理的浏览器身份验证拆分到单独的 `pi --print` 调用中，因为拥有回调状态的进程已退出。

</details>


<details>
<summary>OpenCode</summary>

將 Tuist Model Context Protocol 伺服器加入 `opencode.json`：

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

然後驗證伺服器：

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

開啟 **Cursor Settings → Tools & Integrations → Model Context Protocol Tools** 並新增：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

使用 **Command Palette → MCP: Add Server**，然後設定一個 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 伺服器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

開啟 **Agent panel → Settings → Add Custom Server**，然後設定：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果你的代理支援 `auth.md`，它可以匿名啟動而無需開啟瀏覽器。當提供者身份已連結時，受信任的提供者身份也可以在不使用瀏覽器的情況下完成驗證。對於服務驗證電子郵件、匿名聲明或首次提供者連結，代理會向你顯示 Tuist 驗證連結和六位數代碼。開啟連結，登入，並在 Tuist 頁面上輸入代理的代碼。切勿將代碼發送回代理。Tuist 的授權伺服器中繼資料直接指向部署本身的 `/auth.md`，其中包含確切的請求和輪詢結構。

## Amp orbs 和 Claude Code 雲端工作階段中的代理

在連接到 Tuist 帳戶的沙盒中運行的編碼代理可以使用其自身的身份令牌對端點進行身份驗證，而無需瀏覽器或儲存的 Tuist 憑證：

- 帳戶在 **Settings → Integrations → Amp** 下連接的 Amp 工作區或項目的 **Amp orbs** 會發送 orb 的 ID 令牌。在 Amp 中，將伺服器的 `Authorization` 標頭設定為 `Bearer ${amp:id-token}`。Amp 為伺服器 URL 的來源鑄造令牌，因此 URL 必須是此 Tuist 實例本身的地址，並在其過期前刷新它。為其他來源鑄造的令牌將被拒絕。
- 已連接 Claude Code 環境的 **Claude Code cloud sessions** 會發送 Tuist 作為 `TUIST_OIDC_TOKEN` 傳遞給它們的工作階段令牌。將標頭設定為 `Bearer ${TUIST_OIDC_TOKEN}`。

Tuist 的 Linux 沙盒已預先配置：Amp 的用戶設定和 Claude Code 的用戶配置中都有一個 `tuist` 伺服器，兩者都指向 `${TUIST_URL}/mcp`，同時還包括 Tuist CLI 和一個技能，用於告訴代理何時根據項目歷史記錄檢查其結果。在其他地方，請自行使用上述標頭添加伺服器。

這些令牌提供對已連接帳戶每個項目的唯讀訪問權限：它們攜帶 `mcp` 群組的讀取範圍，而不包含創建、更改或刪除數據（例如靜音或跳過測試）的權限。斷開工作區或環境將在下一個請求時停止訪問，且訪問權限不會超過令牌本身的有效期。連接到多個 Tuist 帳戶的 Amp 工作區將被拒絕，因為其令牌未指定單一帳戶。當缺少連接時，未經授權響應的 `error_description` 會說明這一點。

此唯讀訪問權限僅適用於 Model Context Protocol 端點。同一沙盒中的命令行工具和構建系統集成仍會交換令牌以獲取連接的 CI 訪問權限。

## WebMCP

在支援 [WebMCP](https://webmachinelearning.github.io/webmcp) 的瀏覽器中，Tuist 的頁面會使用 `document.modelContext` 註冊工具，因此內置於瀏覽器的代理可以在無需任何額外配置的情況下調用它們。調用在 Tuist 伺服器上運行。

- **Website and documentation pages** 註冊文檔和源代碼工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 和 `read_tuist_file`）。它們不需要你登入。
- 當你登入時，**An account's dashboard pages** 會為該帳戶註冊 Tuist 的唯讀工具。每個頁面僅註冊與其顯示內容相關的工具，針對項目的構建系統：Gradle 項目的構建頁面獲得 Gradle 構建工具，其測試頁面獲得測試和覆蓋率工具，運行器頁面獲得運行器工具，沙盒頁面獲得沙盒工具。每個頁面還會獲得文檔工具 `list_projects` 和 `get_project`。工具以登入用戶的身份運行，因此它們只能訪問你在儀表板中可以讀取的數據，且僅限於你正在查看的帳戶。當你轉移到另一個頁面或帳戶時，工具會被該頁面的工具替換。

創建、更改或刪除數據的工具無法通過 WebMCP 使用，因為瀏覽器代理會在無需你添加的情況下接收這些工具，並讀取構建和測試產生的內容。連接 MCP 客戶端到 `/mcp` 端點以使用這些工具。

如果組織強制執行單一登入，請使用其提供者登入儀表板以使用其工具。

## 構建系統集成使用兩個憑證

用於 Model Context Protocol 工具的憑證不會驗證 Gradle 插件或 Bazel 的遠程服務。在代理編輯或驗證 Gradle 或 Bazel 集成之前，它應運行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未經過身份驗證，代理必須停止並要求用戶運行：

```bash
tuist auth login --url https://tuist.dev
```

對於本地或自託管部署，請替換兩個命令和 `tuist.toml` 中的 URL。在所有地方保持主機名拼寫一致。例如，`localhost` 和 `127.0.0.1` 使用單獨儲存的憑證。


## 功能

### 工具

以下工具可通過 Tuist Model Context Protocol 伺服器使用：

每個工具都會發布人類可讀的描述以及明確的輸入和輸出架構。成功的調用返回符合所宣傳輸出架構的結構化內容，並將相同結果序列化為文本，供尚未使用結構化內容的客戶端使用。

接受單個記錄識別符的工具，例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`，也接受該記錄的 Tuist 儀表板 URL。直接從瀏覽器貼上 URL，而不是從中提取識別符。

`get_xcode_build`、`get_test_run`、`get_gradle_build` 和 `get_project` 可以包含 `side_quests`：項目未使用但記錄顯示會有幫助的 Tuist 功能。每個功能都有一個 `id`、一個說明其依據證據的 `tip`，以及一個 `docs` 連結。建議代理先完成用戶的請求，提及適用的支線任務，並且僅在用戶同意時才執行其中一項。它們僅返回給項目帳戶的成員，無論他們是使用用戶會話、MCP 令牌還是代理身份連接：

| ID | 工具 | 建議時機 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | 使用 Xcode 26 或更高版本執行的已處理乾淨構建，沒有運行任何可緩存的編譯任務。 |
| `gradle_build_cache` | `get_gradle_build` | 構建執行了可緩存任務，但 Gradle 的構建緩存沒有為其中任何任務計算鍵值，表示構建緩存已關閉。 |
| `flaky_test_quarantine` | `get_test_run` | 一次運行包含不穩定測試，且項目中沒有啟用的自動化功能將它們靜音或跳過。不建議用於 Once 項目。 |
| `test_sharding` | `get_test_run` | 在 Tuist 支持分片的構建系統中，一次未分片的 CI 運行耗時 10 分鐘或更長。提示會說明選擇性測試已跳過了多少個測試（如果有的話）。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI 運行使用了 GitHub Actions、Bitrise、GitLab CI 或 Buildkite 機器，且該帳戶從未在 Tuist Runners 上運行過作業。僅限 tuist.dev。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actions 運行屬於一個未連接到其 GitHub 存儲庫的項目。 |
| `other_build_systems` | `get_project` | 該帳戶沒有在所有支持的構建系統中使用 Tuist。提示列出了識別其他系統的檔案，以便代理檢查存儲庫。 |

#### 文檔和社區搜索

這個只讀工具通過驅動文檔網站的同一個搜索引擎，搜索 Tuist 的文檔、[應用程式接口](https://en.wikipedia.org/wiki/API)參考、GitHub 發布、社區論壇和 GitHub 問題。發布結果包括產品、版本、發布日期和預發布狀態。默認搜索穩定發布，可以使用 `include_prereleases` 包含預發布。該工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公開的 Tuist 文檔、應用程式接口參考、GitHub 發布、社區討論和 GitHub 問題。可選限制為一個 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 反饋

當 Tuist 工具或提示未按預期工作時（例如結果令人困惑、出現錯誤、數據缺失或缺少功能），代理可以向 Tuist 團隊報告。建議代理提出報告，並僅在你同意後發送。每份報告都會開啟與 Tuist 支持的對話，他們可能會通過電子郵件回覆你。報告包括代理的預期、實際發生的情況、可選建議、你的 Tuist 用戶 ID、句柄和電子郵件，以及你所屬的組織。代理還可以指明問題發生的帳戶和項目，以便團隊知道跟進哪個組織；僅接受你所屬的帳戶。只有以 Tuist 用戶身份登入的代理才能發送報告，每個用戶每小時最多可以開啟 10 份報告。該工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `report_feedback` | 報告 Tuist 工具或提示的問題。可選指名 `tool_name`、問題發生的 `account_handle` 和 `project_handle`，並添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基於源代碼的回答

這些只讀工具讓代理使用與託管伺服器一起部署的確切公共 Tuist 源代碼修訂版，作為依賴當前行為的答案的事實來源。它們僅在 `https://tuist.dev/mcp` 可用。

兼容的客戶端在初始化期間會收到關於工具源代碼修訂版、連結和結果限制的事實描述，以及內聯 OAuth 身份驗證信息。這些描述不規定回答風格或驗證工作流程。用戶可以直接提問，無需先調用 `ask_tuist` 提示；該提示仍可用於明確的基於源代碼的工作流程。

每個操作都有固定的併發、持續時間、遍歷、讀取字節數和響應大小限制。搜索和列表結果包含 `truncated` 和 `truncation_reason` 字段。當結果被截斷時，請縮小路徑、文件模式或搜索詞，而不是將結果視為詳盡無遺。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 通過搜索源代碼文件來回答有關當前行為、默認值、配置、功能開關、錯誤處理或未記錄細節的問題。結果包括周圍行、綁定修訂版的源代碼連結和掃描統計信息。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，發現源子系統或附近的測試。列表具有有限的深度和結果數量。 | 無 |
| `read_tuist_file` | 在找到相關路徑後，檢查實現文件、調用點或測試中的特定行範圍。截斷的響應提供 `next_start_line` 以繼續。 | `path` |

#### 項目

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出經過身份驗證的用戶可用的個人和組織帳戶句柄，包括每個帳戶是否可以創建項目。 | 無 |
| `get_organization` | 獲取組織的成員目錄。待處理的邀請需要與儀表板相同的管理員權限；永遠不會返回邀請接受令牌。 | `account_handle` |
| `create_organization` | 為經過身份驗證的用戶創建 Tuist 組織。 | `handle` |
| `create_project` | 在經過身份驗證的用戶可以訪問的帳戶下創建 Tuist 項目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有 Tuist 用戶添加到組織，或更新現有成員的角色。接受 `user`（默認）、`admin` 或 `viewer`，其中檢視者可以閱讀儀表板和運行記錄，但無法更改任何內容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有 Tuist 用戶。Tuist 會發送一個有效期為 14 天的接受連結；當伺服器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製連結。接受 `user`（默認）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其連結無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出經過身份驗證的用戶可訪問的所有項目。 | 無 |
| `get_project` | 獲取項目的配置和連接的存儲庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將項目連結到帳戶的 GitHub App 安裝可以訪問的 GitHub 存儲庫。項目會採用存儲庫的默認分支。需要項目管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除項目與其 GitHub 存儲庫的連結。需要項目管理員權限。 | `account_handle`, `project_handle` |

#### 帳戶令牌

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳戶令牌元數據，而不暴露令牌值。 | `account_handle` |
| `get_account_token` | 獲取帳戶令牌元數據，而不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出項目令牌元數據，而不暴露令牌值。 | `account_handle`, `project_handle` |

#### 通知規則

這些工具管理經過身份驗證的用戶自己的通知規則：當事件（例如新預覽）在規則的項目中發生（或者在未列出任何項目時，在你可收到通知的任何項目中發生）並滿足其條件時，執行其操作，例如向你的 Tuist 應用設備發送推送通知。如果沒有規則，你將不會收到任何通知。它們需要用戶身份驗證，僅對你自己的規則生效，並且只接受你所屬帳戶的項目。它們不提供給儀表板頁面，因為規則涵蓋你所有的帳戶。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_notification_events` | 列出規則可以訂閱的事件類型，每個類型都帶有用於其條件的 JSON Schema。 | 無 |
| `list_notification_condition_options` | 建議項目中事件的條件值，例如其最近預覽的軌道和分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出你的規則。 | 無 |
| `create_notification_rule` | 從事件、可選項目和條件以及至少一個操作創建規則。 | `event`, `actions` |
| `update_notification_rule` | 更改規則的啟用狀態、項目、條件或操作。 | `rule_id` |
| `delete_notification_rule` | 刪除規則。 | `rule_id` |

#### 持續集成運行器

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳戶的持續集成運行器作業。 | `account_handle` |
| `get_runner_job` | 獲取持續集成運行器作業，包括其機器是否內存不足、它停止了什麼以及需要更改什麼。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續集成運行器作業記錄的步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續集成運行器作業記錄的機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續集成運行器作業最多 500 條捕獲的日誌行。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳戶的持續集成工作流匯總。 | `account_handle` |
| `list_runner_profiles` | 列出帳戶的持續集成運行器配置文件，並包含每個文件的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出運行器配置文件可以使用的機器規格和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 建立運行器配置文件，指定平台、機器規格，以及在 macOS 上指定 Xcode 版本。可選擇設定哪些分支會儲存其快取卷。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改運行器配置文件的機器規格、Xcode 版本，或哪些分支會儲存其自訂快取卷的變更。省略的欄位會保留其值。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 經用戶確認後刪除運行器配置文件。預設配置文件無法刪除。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

運行器卷工具公開與「卷」儀表板相同的數據。讀取工具需要運行器存取權限；清除操作需要帳戶管理權限或 `account:runners:write` 範圍，以及用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名稱和存儲庫篩選，並對卷進行排序和分頁。 | `account_handle` |
| `get_runner_volume` | 存儲庫、平台、容量、已用空間及最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁顯示作業和工作流參考、快取狀態、命中結果及掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作業掛載的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存儲序列、作業運行次數、命中率及趨勢。可選 `volume_id`、`start` 和 `end`（ISO 8601）；預設為七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 刪除卷及其儲存的內容。運行中的作業會保留其私人副本，但無法儲存；後續使用相同密鑰的作業將從空白開始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷清單還接受 `name` 和 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的測量值和命中結果保持為 `null`。快取狀態描述卷變更是否已儲存，而非作業成功與否。

#### 沙盒

沙盒工具公開與「沙盒」儀表板相同的數據和操作，存取權限與 [API](https://tuist.dev/api/docs) 相同：帳戶成員可以列出、獲取、建立、暫停、恢復和刪除沙盒，但服務於代理環境、Amp 或遠程執行的沙盒，以及分析和歸檔工具，需要帳戶管理權限。只讀檢視者無法使用它們。帳戶需要啟用沙盒功能。儀表板的沙盒頁面會註冊只讀工具。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_sandboxes` | 分頁顯示沙盒及其狀態、規格和時間戳。可選 `search`（沙盒、Amp Orb 或 Anthropic 會話 ID 中的文本）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）和 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的狀態、規格、節點、歸檔和時間戳。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小時數、建立的沙盒數量、會話、設置和啟動持續時間，以及相對於帳戶限制的峰值 vCPU、內存和磁盤用量，並包含趨勢。可選 `start` 和 `end`（ISO 8601）；預設為 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 啟動一個空白沙盒，並在運行後返回它。可選 `platform`（`linux` 或 `darwin`）、`template`、帶有 `memory_mb` 的 `vcpus`（Linux：2x4096、4x8192 或 8x16384，預設 2x4096；macOS：8x8192、8x16384 或 8x24576，預設 8x8192）和 `workspace_gb`。其描述指示代理在 Mac 上使用 `mise install` 安裝存儲庫中鎖定的 Tuist，然後自行 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">使用帳戶的快取</.localized_link>。 | `account_handle` |
| `pause_sandbox` | 將運行中的沙盒快照保存到其節點的磁盤。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢復已暫停或歸檔的沙盒。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 排隊將已暫停沙盒的磁盤移動到對象存儲。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 經用戶確認後刪除沙盒及其磁盤。 | `account_handle`, `sandbox_id` |

#### Amp 工作區

這些工具管理 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 工作區連接</.localized_link>，讓 orbs 無需令牌即可登入 Tuist。它們使用與儀表板「集成」頁面相同的管理員專用權限。orb 中的代理可以從 `$AMP_WORKSPACE_ID` 和 `$AMP_PROJECT_ID` 讀取其自身的 ID。連接允許的每個 orb 都能獲得對帳戶中所有項目的 CI 存取權限，因此代理在連接前應與用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 列出帳戶已連接的 Amp 工作區，以及每個工作區限制的項目（如有）。 | `account_handle` |
| `connect_amp_workspace` | 連接 Amp 工作區。可選 `project_id` 將登入限制為單一 Amp 項目的 orbs。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 斷開工作區連接。其 orbs 已有的會話在過期前仍然有效。 | `account_handle`, `connection_id` |

#### Claude 環境

這些工具連接 Claude Managed Agents 自託管環境，使其會話在 Tuist 沙盒中運行，如同「設置」→「集成」→「Claude」所做的一樣。它們需要帳戶管理權限並啟用沙盒。代理可以使用 Anthropic 的 API 建立環境，但只有 Claude Console 會生成其環境密鑰，因此代理會向用戶索取該密鑰。Tuist 使用 Anthropic API 密鑰或工作負載身份聯合來啟動會話，並在保存之前使用該憑證獲取環境。Anthropic 端的設置使用用戶自己的 Anthropic 憑證；Tuist 從不接收它們。密鑰會通過客戶端和模型傳遞，因此僅在明確提供時才使用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_claude_environments` | 列出已連接的環境及其使用的憑證，以及聯合規則應信任的發行者 URL 和主體前綴。 | `account_handle` |
| `connect_claude_environment` | 使用 `api_key`，或使用 `organization_id`、`workspace_id`、`service_account_id` 和 `federation_rule_id` 連接環境。可選 `platform`、`vcpus` 和 `memory_mb` 設定沙盒規格。 | `account_handle`, `environment_id`, `environment_key` |

#### Webhooks

Webhook 工具使用與儀表板相同的管理員專用權限。傳送嘗試包含為端點記錄的請求和回應數據，但絕不包含端點簽名密鑰。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳戶的 webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 獲取一個 webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點的傳送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 獲取一次傳送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 構建

用於 Xcode、Gradle、Bazel、Mix 和 Cargo 的構建詳情工具公開現有的 `custom_metadata: {tags, values}` 結構，包括基礎設施觀測數據（如有報告）。值保持為字符串，並保留不熟悉的鍵。例如，`tuist.cpu.available_processors` 描述運行時可用的邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作線程限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆限制，而非主機內存。這些是不可信的客戶端觀測數據，而非經過驗證的 runner 身份。缺失的觀測數據保持缺失；導入的日誌和較舊的客戶端可能沒有基礎設施元數據。元數據更新有待協調的客戶端/協議更新。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出項目的 Xcode 構建運行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 獲取特定 Xcode 構建運行的詳細信息，包括保存原始 `.xcactivitylog` 的歸檔文件的臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 構建運行的構建目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 構建運行的編譯文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄的構建步驟，包含耗時和結果，不含日誌文本。 | `build_run_id` |
| `get_xcode_build_step` | 獲取一個記錄的構建步驟，包括其日誌和截斷標誌。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定構建運行的構建問題（警告和錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 構建運行的可快取任務（快取命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 構建運行的 [內容尋址存儲](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 預設返回每頁 20 個步驟（通過 `page_size` 最多 100 個），並提供 `page` 和 `pagination_metadata` 用於導航。使用 `search` 匹配標題、項目或目標，或過濾精確的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以最慢優先（預設），或按 `start_ms` 排序以時間順序排列。步驟 ID 用於打破平局，並作為十進制字符串返回以保留其完整的 64 位精度。ID 僅限於單次構建，不應跨構建匹配。

可選 `start_ms` 和 `end_ms` 選擇與從構建開始起以毫秒計的時間範圍重疊的步驟；結束時間不包含在內。兩個工具都接受構建 UUID 或儀表板 URL 作為 `build_run_id`。將返回的步驟 `id` 原樣作為 `step_id` 傳遞以檢索其日誌。每個步驟的日誌最多保留 64 KiB，`log_truncated` 表示省略的輸出。

處理 Xcode 構建時預設會收集步驟。記錄的步驟數據保留 90 天。列表響應包括 `availability`：`available` 表示存在記錄的步驟，即使過濾器無匹配項；`processing` 表示構建仍在處理中且尚無步驟；或 `unavailable` 表示步驟未記錄或已過期。

HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 提供相同的操作，具有相同的過濾器和分頁功能。兩者都需要對構建項目的讀取權限。

#### Gradle 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整的身份驗證、項目設置、Gradle 插件、快取策略和兩次構建驗證工作流程。代理在編輯現有的 Android 或 Gradle 項目之前應調用此工具。 | 無 |
| `list_gradle_builds` | 列出項目的 Gradle 構建運行，包括自定義元數據。使用可選的 `tag` 參數按自定義標籤過濾。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 獲取構建元數據、任務/快取計數，以及 `failures`：每個失敗任務和配置步驟的失敗消息。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任務結果、複合構建標識、可快取性、增量狀態和失敗消息。 | `build_run_id` |
| `list_gradle_build_steps` | 列出定時任務、配置和轉換，支持搜索、元數據和重疊時間過濾器。 | `build_run_id` |
| `get_gradle_build_step` | 通過不透明 ID 檢查記錄的步驟元數據；失敗任務或配置步驟的 `log` 即為其失敗消息。 | `build_run_id`, `step_id` |

Gradle 和 Bazel 步驟列表預設返回 20 個結果（最多 100 個），支援 `search`、精確匹配 `project`、`target`、`category` 和 `status`、重疊的 `start_ms` / `end_ms` 過濾器（結束時間不包含在內），以及按 `duration_ms` 或 `start_ms` 排序。請原樣傳遞返回的 ID；它們僅限於其構建範圍。列表會公開 `time_origin` 和 `coverage`。較舊的 Gradle 報告使用 `first_recorded_timestamp`，因為沒有上傳構建開始時間。Bazel 配置文件通過 `trace_profile` 覆蓋範圍和以 `profile_start` 為時間起點，公開所有記錄的時間間隔。較舊的構建會回退到保留的 BEP 摘要。源記錄在 90 天後過期。Bazel 詳情在發布時包含經過淨化的操作日誌。失敗任務或配置步驟的 Gradle 詳情包括 Tuist Gradle 插件作為 `log` 報告的失敗消息：即異常消息及其原因鏈，如同 Gradle 控制台所打印的那樣，不包含堆疊跟蹤或任務輸出，項目內的路徑已轉換為相對路徑，憑證和其他本地路徑已脫敏，每個步驟最多 16 KiB，每次構建最多 32 個失敗步驟。其他 Gradle 步驟、由較舊插件版本報告的構建，以及無憑證報告的 `log` 為 null。配置步驟在失敗時報告 `failure`，否則報告 `unknown`。`compare_builds` 提示使用此覆蓋範圍來區分完整的 Bazel 跟踪與保留的摘要，並指導代理在檢查更廣泛的調用輸出之前，先查看步驟詳情以獲取操作結果和日誌。

單步工具 `get_gradle_build_step` 和 `get_bazel_build_step` 通過 ID 檢索步驟，不接受時間過濾器；請使用相應的列表工具按時間範圍過濾步驟。

如果在列出步驟和獲取步驟之間到達了完整的配置文件，則從保留摘要返回的 Bazel 步驟 ID 仍然可讀。如果索引配置文件的步驟數據已過期，則報告為不可用。Gradle 步驟列表包括持續時間為零的快取和跳過的操作。

#### Bazel 調用

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份驗證、項目設置、Bazel 配置和驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成的 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 調用，按最新順序排列，包括構建指標、有界的執行時間線、關鍵路徑診斷以及項目的相關遠程快取總計。按 `status`、`git_branch`、`git_commit_sha`、`is_ci` 和 `command` 過濾。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 獲取一個已完成的 Bazel 調用，包括構建指標、有界的執行時間線、關鍵路徑診斷以及相關的遠程快取總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄的 Bazel 配置文件時間間隔，帶有過濾器和明確的覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄的 Bazel 步驟及其發布的操作結果和淨化日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按執行順序列出為 Bazel 調用捕獲的淨化日誌：Bazel 進度輸出的有界尾部以及 `test.log` 構件。可選的 `stream`（`stdout` 或 `stderr`）、`source`（`progress` 或 `test_log`）、`target_label` 和 `errors` 過濾器可縮小結果範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 獲取為 Bazel 調用捕獲的一個淨化日誌塊。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 遠程快取觀察記錄，包括其操作、端點和觀察時間，可選擇縮小到特定調用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 獲取一個原始的 Bazel 遠程快取觀察記錄。 | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations` 過濾器為精確匹配，在同一秒內完成的調用按調用 ID 排序。要查找分支上最新的失敗調用，請使用 `status: "failure"`、`git_branch` 和 `page_size: 1` 進行調用。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` 接受相同的過濾器。

測試日誌攜帶其所來源測試結果的 `target_label` 和嘗試 `status`，因此 `target_label: "//foo:bar_test"` 僅返回該目標的測試日誌。`errors: true` 返回失敗嘗試的測試日誌以及包含 Bazel 報告器以 `ERROR:`、`FAIL:` 或 `TIMEOUT:` 開頭的行的 stderr 進度塊。進度輸出不歸因於目標，且在記錄歸因之前寫入的日誌字段為空。失敗的操作及其輸出可通過 `list_bazel_build_steps` 按目標獲取，每個測試用例的失敗可通過測試運行工具獲取。

#### Cargo 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出項目的 Cargo 構建，按最新順序排列。按 `git_branch`、`status`、`is_ci` 或 `command` 過濾。Cargo 測試執行結果可通過測試工具獲取，而非此構建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 獲取構建元數據、聚合快取計數，以及最多 500 個帶有診斷信息的記錄編譯器作業。`compilations_truncated` 表示省略的作業；診斷信息僅涵蓋返回的作業。 | `account_handle`, `project_handle`, `build_id` |

在 `get_cargo_build` 上設置 `include_cache_inspection: true` 以檢索經過驗證的任務決策和 CAS 操作，限制為 4 MB。預設情況下，以及當記錄缺失或無效時，`cache_inspection` 為 null。請遵守其部分捕獲的 `truncated` 標誌；傳輸不會確定每個任務命中的本地/遠程來源。HTTP 詳細端點接受相同的查詢參數。

#### Mix 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出項目的 Mix (Elixir) 編譯構建，按最新順序排列，包括自定義元數據。按 `git_branch`、`status`、`is_ci` 或 `mix_env` 過濾。 | `account_handle`, `project_handle` |
| `get_mix_build` | 獲取構建元數據、診斷計數和依賴快取摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 構建跟踪

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_build_trace` | 獲取 Xcode、Gradle、Bazel 或 Mix 構建時間線的下載鏈接，作為可在 [Perfetto](https://ui.perfetto.dev) 中打開的跟踪文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 是構建運行 ID（Bazel 的調用 ID）或構建的儀表板 URL。返回的 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有該鏈接的人都可以在 `expires_at`（調用後一小時）之前下載該構建的跟踪，無需其他憑證。代理可以使用 `curl` 下載它，交給你並在 Perfetto 中打開，或使用 Perfetto 的 `trace_processor` 進行查詢。跟踪包含按並行性打包到通道中的記錄步驟、跨越整個構建的軌道，以及在構建記錄機器指標時的 CPU 和內存計數器。它包含與上述步驟工具相同的數據，但不包含日誌。儀表板從每個構建的時間線標籤頁提供相同的文件。

#### Once 運行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出項目的 Once 運行，按最新順序排列。按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 過濾。未完成的運行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 獲取運行的操作總計、快取摘要，以及測試運行的測試總計。 | `account_handle`, `project_handle`, `run_id` |

Cargo 構建、Mix 構建和 Once 運行 ID 在項目內是唯一的。通過 HTTP API 可在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 和 `.../once/runs` 進行相同的讀取操作，每個端點都有一個用於單一 ID 的詳細信息端點。

#### 任務、操作、模塊和文件

這些項目範圍的工具檢查跨運行的持久構建身份。首先使用 `list_build_entities`，然後將返回的穩定 `id` 與相同的 `kind` 一起傳遞給 `get_build_entity` 或 `list_build_entity_history`，並連同 `account_handle` 和 `project_handle`。不需要構建或調用標識符。

| 工具 | 描述 | 必需參數 |
| --- | --- | --- |
| `list_build_entities` | 列出在項目構建中看到的一種類型的任務、模塊、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 獲取一個構建實體及其本機身份和所選時期的分析數據。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個構建實體的記錄執行、編譯或快取事件，按最新順序排列。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 報告的操作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模塊 | 編譯和模塊快取事件 |
| `once_actions` | Once 操作 | 執行 |
| `mix_files` | Mix 編譯文件 | 編譯 |
| `mix_modules` | Mix 編譯模塊 | 編譯 |
| `cargo_crates` | Cargo crate | 記錄的 rustc 調用 |

這些工具正在逐步推出，僅返回已啟用它們的項目的數據；對於其他項目，它們返回錯誤而不是空結果。一種類型僅適用於使用其構建工具鏈的項目。工具接受有界的 `start_at`/`end_at` 過濾器、`environment`（`any`、`ci` 或 `local`）和精確的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明的 `after`/`before` 遊標。未知的計時或快取觀察結果保持不可用，而不是變為零或缺失。歷史記錄引用記錄的父級和本機執行，以便使用現有的運行工具進行深入分析。

`get_build_entity` 指標包括 `duration_samples`，即具有記錄計時的觀察數量：真正的零持續時間計入，缺失的計時不計入。此計數可能低於觀察計數；不可用的持續時間統計數據保持為 null。

Xcode 模塊持續時間來自構建日誌中測量的目標編譯。模塊快取解析和沒有編譯工作的目標不會貢獻持續時間樣本。編譯觀察引用 Xcode 構建；快取事件引用生成或快取命令。

Bazel 操作由目標標籤、助記符和配置的主要輸出來標識，保持單獨的操作和配置不同，而不依賴於輸入依賴的快取摘要。歷史記錄 BEP 報告的執行，而不是快取查找或跟踪配置文件階段。完整的執行覆蓋需要 `--build_event_publish_all_actions`；工件交付是盡力而為，因此缺失的觀察結果並不是沒有運行工作的證據。較舊的 Kura 負載如果沒有穩定的身份或執行開始，仍然被接受但未編入索引。缺少結束時間測量保持不可用，真正的零持續時間計入。

Mix 模塊持續時間測量包含文件的編譯，而不是獨立測量的模塊工作。當客戶端報告目標映射時，Once 操作使用聲明的目標/能力/索引槽；僅診斷標籤不是穩定的身份。現有客戶端和運行級別工具保持不變地受支持。

Cargo crate 按精確記錄的 crate 根、名稱和類型分組。檢出路徑更改可能會分割歷史記錄，並且構建配置文件、功能和目標三元組不會區分。歷史測量 rustc 調用，而不是每個文件的工作或快取命中；缺失的作业不能確定刪除或完整的工作區清單。

分析讀取具有有界的內存和執行時間。如果查詢超過這些限制，工具將返回錯誤而不是發明一個空結果。

新觀察結果在部署後編入索引；此功能不會回填現有的運行遙測數據。身份元數據在 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link> 下比單個觀察結果更長久。

#### 測試

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出專案的測試執行。 `query` 欄位為 `git_branch`、`scheme` 和 `status`：`field:"value"` 進行精確匹配，`field~"value"` 進行不區分大小寫的子字串匹配，而前置的 `-` 則對任一運算子取反。例如，`-git_branch~"gh-readonly-queue"` 會排除合併佇列分支。以空白分隔的查詢過濾器與明確引數會以 AND 語義組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 取得測試執行的詳細指標，包括其結果套件（`.xcresult`）和工作階段封存檔的臨時下載網址。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行的測試模塊執行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行的測試套件執行，可選擇按模塊過濾。 | `test_run_id` |
| `list_test_cases` | 列出專案的測試案例（支援如 `flaky` 等過濾器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 取得測試案例的詳細指標，包括可靠性比率、不穩定比率和執行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例執行，可選擇按測試案例或測試執行過濾。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 取得特定測試案例執行的失敗詳情和重複次數。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例執行的附件。每個附件都包含一個臨時下載網址。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例的狀態變更，例如將其靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例的狀態或不穩定分類。變更可以將事件派發到已配置的 webhook 端點，包括外部服務。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試執行的選擇性測試目標結果。 | `test_run_id` |
| `get_coverage` | 取得專案的程式碼覆蓋率及其目標，基於某個提交或分支的最新完整提交。若沒有 `git_commit_sha` 或 `branch`，則讀取預設分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出某次提交的程式碼覆蓋率所測量的檔案及其行覆蓋率，基於某個提交或分支的最新完整提交。支援 `search`、排序和分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 取得檔案在某个提交或分支的最新完整提交時的程式碼覆蓋率及其函數。設定 `include_lines` 以取得每行的執行計數。 | `account_handle`, `project_handle`, `path` |

程式碼覆蓋率工具僅供已啟用程式碼覆蓋率的帳戶使用。

#### 套件

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出專案的套件（應用程式二進位檔）。可選擇按 `git_branch` 和 `tags` 過濾（所有標籤必須精確匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 取得特定套件的詳細資訊，包括自訂標籤。 | `bundle_id` |
| `get_bundle_artifact_tree` | 以按路徑排序的平面列表形式取得套件的完整工件樹。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以區分構建變體或環境。標籤是區分大小寫的標籤，包含字母、數字、連字號或底線，最多 10 個標籤，每個標籤最多 50 個字元。列表和詳細結果包含 `custom_metadata.tags`。分頁計數和分支過濾器適用於帶標籤的結果；省略 `tags` 則保留未過濾的行為。無效的標籤過濾器會返回錯誤，而不是擴大查詢範圍。

#### 生成

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_generations` | 列出專案的生成執行。 | `account_handle`, `project_handle` |
| `get_generation` | 取得特定生成執行的詳細資訊。 | `generation_id` |

#### 快取執行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出專案的快取執行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 取得特定快取執行的詳細資訊。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出某次生成或快取執行的模塊快取目標，顯示每個目標的快取命中/未命中狀態和診斷組件哈希，包括額外的哈希輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_previews` | 列出專案的可共用應用程式預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 取得預覽及其構建的臨時下載 URL。 | `preview_id` |
| `get_latest_preview` | 尋找執行中應用程式二進位檔的最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出專案的自動化警示。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 取得自動化警示。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警示的修訂歷史。動作憑證會被遮蔽。 | `alert_id` |
| `list_project_notification_alerts` | 列出專案通知警示規則。需要與儀表板設定頁面相同的管理員權限。Webhook 地址會被遮蔽。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期的用戶端可以呼叫 `events/list` 來探索事件及其負載結構：

| 事件 | 發送時機 | 訂閱過濾器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從穩定變為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持續整合的 Xcode、Gradle 或 Bazel 構建以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持續整合的測試執行以失敗結束，包括合併的分片執行或已放棄的執行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist runner 作業以失敗完成。 | `account_handle` |

要訂閱，用戶端需呼叫 `events/subscribe`，並提供事件名稱、上述列於 `arguments` 的控制代碼，以及包含 `https://` 回呼 URL 和 `whsec_` 簽署金鑰的 `webhook` 傳遞方式。專案事件需要帳戶成員資格及對應測試或構建資料的讀取權限；runner 作業事件需要帳戶成員資格及 runner 讀取權限。已聲明的 [`auth.md`](https://workos.com/auth-md) 存取權杖、已聲明的帳戶權杖和瀏覽器授權授予可以建立訂閱；當相關憑證不再有效時，傳遞會停止。每個用戶最多可保留 25 個有效訂閱。Tuist 會在儲存訂閱前向回呼發送驗證挑戰。回呼必須返回包含相同 `challenge` 值的物件。訂閱預設持續七天，可以透過再次訂閱來刷新，並在移除用戶的存取權或憑證時停止傳遞。可選的 `ttlMs` 限制在一小時到 30 天之間。Tuist 會重試超時的回呼，並在至少三次連續超時（橫跨五分鐘）後取消訂閱；恢復回呼後請再次訂閱。

當事件發生時，Tuist 會將其資源識別碼和儀表板 URL 發送到回呼。構建和測試執行失敗還包括 `is_ci` 和 `git_branch`，因此用戶端可以忽略本地失敗或按分支過濾。構建事件包括 `build_system`；runner 作業事件包括 `workflow_job_id` 和 `workflow_run_id`。請求包含訂閱識別碼和 [Standard Webhooks](https://www.standardwebhooks.com/) 簽名標頭，以便用戶端驗證其來源。Tuist 會重試失敗的傳遞，因此用戶端應使用穩定的 `eventId` 來丟棄重複項。負載省略測試名稱、日誌和失敗訊息；用戶端可以透過上述工具獲取這些詳細資訊，並決定是否通知團隊或開始除錯。用戶端可以使用 `events/unsubscribe` 停止傳遞。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 引導你修復不穩定測試，透過分析失敗模式、識別根本原因並應用針對性修正。 |
| `compare_builds` | 引導你比較構建以識別效能衰退、快取變更和構建問題。對 Xcode、Gradle、Bazel 和 Cargo 專案使用原生工具。Cargo 比較會保留部分編譯器覆蓋率，並區分估計的編譯器工作與經過時間節省。 |
| `compare_test_runs` | 引導你比較兩次測試執行以識別衰退、新失敗和不穩定測試。 |
| `compare_bundles` | 引導你比較兩個套件以識別工件樹中的大小變化。 |
| `compare_test_case` | 引導你比較測試案例在兩個分支或時間段內的行為。 |
| `compare_generations` | 引導你比較兩次生成執行以識別效能衰退和模塊快取變更。 |
| `compare_cache_runs` | 引導你比較兩次快取執行以識別快取有效性變更和目標層級衰退。 |
| `integrate_gradle_project` | 引導你將 Tuist 整合到現有的 Gradle 專案中。包括獨立的工具和 Gradle 認證、帳戶發現、專案建立、遠端快取政策、構建洞察和回讀驗證。 |
| `integrate_bazel_project` | 引導你建立或選擇 Bazel 專案、認證命令列、配置遠端快取和構建洞察，並透過 Tuist 構建資料驗證整合。 |
| `integrate_xcode_project` | 引導你將 Tuist 整合到現有的 Xcode 專案中。支援 Xcode 快取、構建洞察、測試洞察和測試分片。 |
| `ask_tuist` | 使用公開材料作為背景，並以專注的實作和測試證據作為當前行為的事實來源，來回答 Tuist 問題。它需要一個 `question` 並引用修訂綁定的證據。 |

專案資料提示接受 `account_handle` 和 `project_handle`，以將調查範圍限定於特定專案。比較提示亦接受 `base` 和 `head` 參數，以指定要比較的兩個項目（透過 ID、儀表板 URL 或分支名稱）。`ask_tuist` 接受 `question` 而非專案參數。`integrate_gradle_project` 亦接受 `features`，這是一個逗號分隔的 Gradle 整合清單： `remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可選的 `server_url`，適用於自託管或本機安裝。`integrate_xcode_project` 接受包含 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding` 的 `features`。

#### Gradle 整合提示功能

`integrate_gradle_project` 提示和 `get_gradle_integration_guide` 工具記錄了完整的設定工作流程。伺服器的初始化指引亦引用此工具，令未枚舉提示的代理程式也能發現它。

| 功能 | 代理程式設定的內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 的構建快取、設定 Tuist 遠端快取上傳政策，並建議僅從具有本機唯讀權限的持續整合執行器進行上傳。 |
| `build_insights` | 應用 Tuist Gradle 外掛程式，並在需要時設定構建分析上傳行為。 |
| `test_insights` | 應用 Tuist Gradle 外掛程式，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 引導設定不穩定測試偵測、可選的 Gradle Test Retry 外掛程式使用，以及測試隔離配置。 |
| `test_sharding` | 新增 `tuistPrepareTestShards` 的持續整合工作流程、分片矩陣生成，以及基於 `TUIST_SHARD_INDEX` 的測試執行。 |

當省略 `features` 時，提示會要求代理程式釐清用戶想要的整合項目，或在編輯 Gradle 專案前從請求中推斷出最小的實用集合。

#### Xcode 整合提示功能

`integrate_xcode_project` 提示記錄了 Tuist 支援的每項 Xcode 整合：

| 功能 | 代理程式設定的內容 |
|---------|---------------------------|
| `xcode_cache` | 設定 `tuist setup cache`、生成專案的快取設定、手動 Xcode 快取構建設定，以及僅限持續整合執行器的上傳政策。 |
| `build_insights` | 透過 `tuist setup insights` 設定 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 和可選的機器指標。 |
| `test_insights` | 設定 `tuist inspect test`、方案測試後動作，以及為持續整合測試執行生成結果套件。 |
| `test_sharding` | 新增 Xcode 或生成專案的分片規劃及分片執行工作流程，並使用 `TUIST_SHARD_INDEX`。 |

當省略 `features` 時，提示會要求代理程式釐清用戶想要的整合項目，或在編輯 Xcode 專案前從請求中推斷出最小的實用集合。
