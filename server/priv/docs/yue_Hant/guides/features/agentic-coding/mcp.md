---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 MCP 端點，讓 AI 代理存取測試洞察等功能。"
}
---
# 模型上下文協定

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一項開放標準，讓人工智能代理可以與外部服務和數據來源互動。它令 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等應用程式，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等編輯器能夠與 Tuist 互通。

Tuist 在 `https://tuist.dev/mcp` 託管伺服器端的 Model Context Protocol 端點。將你的客戶端連接至此端點後，代理即可存取你的 Tuist 專案數據，包括測試洞察、不穩定測試分析等。大多數工具只會讀取已驗證用戶在儀表板中已經可見的 Tuist 數據。每個工具都會標示註釋，說明其是否為唯讀、是否可能導致難以復原的變更（`destructiveHint`），以及是否可以存取 Tuist 以外的資源（`openWorldHint`）。會變更狀態的工具如下，每項工具均受用戶於帳戶或專案的權限限制：

- **組織與成員**：`create_organization`、`add_organization_member`（新增現有用戶或更改成員角色）、`invite_organization_member`（向任何電郵地址發送邀請）及 `cancel_organization_invitation`。
- **專案**：`create_project`、`start_project_logo_upload` 及 `complete_project_logo_upload`（更換標誌）、`connect_project_repository` 及 `disconnect_project_repository`（GitHub 儲存庫連結）。
- **測試**：`update_test_case`（靜音、跳過、重新啟用或將測試案例標記為不穩定；此變更可能會觸發帳戶的 webhook 端點）。
- **通知規則**：`create_notification_rule`、`update_notification_rule` 及 `delete_notification_rule`。
- **持續整合執行器**：`create_runner_profile`、`update_runner_profile`（縮小可儲存快取卷的工作範圍會捨棄待處理的儲存）、`delete_runner_profile` 及 `delete_runner_volume`（刪除卷中已儲存的內容）。
- **沙盒**：`create_sandbox`、`pause_sandbox`、`resume_sandbox`、`extend_sandbox`、`archive_sandbox`、`delete_sandbox`（刪除其磁碟），以及在沙盒裝置上（現時指 macOS 沙盒中的 iOS 模擬器）`boot_sandbox_device`、`launch_sandbox_app` 及 `open_sandbox_url`。
- **回饋**：`report_feedback`（向 Tuist 團隊發送關於工具或提示的報告；僅限 tuist.dev）。
- **組織 AI**：`save_organization_ai_model`、`remove_organization_ai_model`、`set_organization_ai_default_model`、`save_organization_ai_task_route`、`remove_organization_ai_task_route` 及 `remove_organization_ai_provider`（刪除供應商的密鑰和模型，並解除與 Anthropic 上連結的 Claude 組織的關聯）。
- **代理整合**：`connect_amp_workspace`（授予工作區的 orbs CI 存取帳戶的權限）、`disconnect_amp_workspace` 及 `connect_claude_environment`（允許 Claude Managed Agents 環境在 Tuist 沙盒中執行工作階段）。

`add_organization_member`、`cancel_organization_invitation`、`complete_project_logo_upload`、`disconnect_project_repository`、`update_test_case`、`update_notification_rule`、`delete_notification_rule`、`update_runner_profile`、`delete_runner_profile`、`delete_runner_volume`、`delete_sandbox`、`disconnect_amp_workspace`、`remove_organization_ai_provider`、`remove_organization_ai_model` 及 `remove_organization_ai_task_route` 會標示 `destructiveHint: true`，因為它們會取代或移除現有狀態。`invite_organization_member`、`update_test_case`、`connect_claude_environment`、`remove_organization_ai_provider` 及 `report_feedback` 會標示 `openWorldHint: true`，因為它們會發送電郵、通知外部 webhook 端點、呼叫 Anthropic 或向 Tuist 團隊發送報告。

個人 Claude 和 ChatGPT 訂閱僅在儀表板的 AI 設定中連接，因此訂閱令牌和登入憑證絕不會經過 Model Context Protocol 客戶端。帳戶設定工具需要用戶驗證。專案令牌或一般帳戶令牌無法使用這些工具。當用戶在瀏覽器中授權客戶端或聲明 `auth.md` 註冊時，Tuist 僅在 Model Context Protocol 端點將該憑證與用戶關聯，以便設定工具完成所需的工作流程。由於任何人都可以註冊客戶端，在瀏覽器中授權時會顯示一個同意頁面，列出客戶端名稱及其存取權發送到的主機，而 Tuist 僅在你於該頁面批准後才會發出憑證。未請求任何範圍的客戶端將獲得 `mcp` 範圍組。客戶端必須使用帶有 `S256` 的 PKCE，而其重定向 URI 必須使用 HTTPS、環回地址上的 HTTP，或應用程式自身的協議。

Tuist 實作了 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求是無狀態的：客戶端在每次請求中發送其協議元數據，並可直接呼叫工具而無需初始化。`server/discover` 會返回伺服器的身份、功能、支援的版本及指示。沒有工作階段識別碼或獨立的事件流。使用 2025-06-18 或 2025-03-26 初始化流程的客戶端仍獲支援；它們同樣無需伺服器工作階段即可運作。

## Model Context Protocol 與技能比較

Model Context Protocol 工具與 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 的功能可能存在重疊。鑑於目前兩者的重疊情況，請為每個工作流程選擇其中一種方法並一致使用，避免在同一流程中混合使用兩者。

對於支援外掛安裝的客戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 一併安裝兩者。

## 設定

在客戶端中將 `https://tuist.dev/mcp` 添加為遠端 Model Context Protocol 伺服器。伺服器的初始化指示和公開伺服器卡片內置描述了帶有動態客戶端註冊的 OAuth 2.0 及標準瀏覽器授權流程，無需用戶代理獲取或遵循外部驗證文件。這些伺服器範圍的指示保持工作流程指導的通用性：工具驗證不會驗證本地命令行工具或構建系統整合，且用戶代理應透過相關的 Tuist 工具驗證請求的變更。特定構建系統的設定和驗證檢查記錄在整合指南和提示中。Tuist 仍分別在 `https://tuist.dev/auth.md` 宣傳 [Open Authorization](https://oauth.net/2/) 發現元數據和目前的 [auth.md protocol](https://workos.com/auth-md)。

如果你的其中一個組織強制執行單一登入，則在瀏覽器中授權客戶端需要透過該組織登入的工作階段，且在必要時 Tuist 會先將你導向供應商。參閱 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>。

該端點接受無狀態的 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），以及較舊的基於工作階段的生命週期。現有客戶端可以繼續使用其目前的連接方法。

支援 Model Context Protocol 事件的客戶端可以訂閱專案事件。有關可用事件和交付要求，請參閱 [Events](#events)。

已經支援遠端瀏覽器驗證的客戶端可以繼續在瀏覽器中進行驗證。支援 `auth.md` 的客戶端和代理可以匿名註冊、出示受信任的供應商身分斷言，或啟動服務驗證的電子郵件聲明。註冊會傳回由 Tuist 簽署的身分斷言，代理會在標準權杖端點將其交換為一小時的存取權杖。Tuist 會發布其公開簽署金鑰，並支援標準權杖撤銷及供應商安全事件交付。

未經驗證的代理應讀取 Model Context Protocol 端點傳回的 `WWW-Authenticate` 標頭，擷取受保護資源元數據，擷取授權伺服器元數據，並遵循其 `agent_auth.skill` URL。Tuist 也會在未授權回應主體中傳回相同的本地 `auth_md` URL，讓語言模型驅動的客戶端無需依賴原生客戶端整合即可發現流程。部署本地的文件是端點名稱、請求主體、聲明輪詢和斷言交換的真實來源。

在代理啟動電子郵件聲明之前，必須要求用戶確認其 Tuist 帳戶的電子郵件地址。不得從供應商個人資料、Git 設定、環境變數或工作階段元數據推斷該地址。

該端點使用 `mcp` 範圍群組。匿名的預聲明憑證可以探索功能並閱讀公開的整合指南，但不會被視為已登入用戶。經過瀏覽器授權或聲明後，憑證將具有用戶範圍，且每個工具都會應用與儀表板相同的授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析為已驗證用戶已有權限讀取的專案。Xcode 和 Gradle 構建工具接受構建 UUID 或儀表板 URL。UUID 必須精確識別一個專案；如果它出現在多個專案中，工具會傳回未找到，而不會選擇另一個專案的報告。專案範圍的儀表板和 API 讀取仍然可用。報告的行為者識別碼是未經驗證的標籤，並非憑證或額外的存取權限。

構建列表和詳細資訊工具提供可選的 `tuist_version` 元數據：用於 Xcode 和 Cargo 的報告 Tuist CLI、用於 Gradle 的 Tuist Gradle 外掛，以及用於 Mix 的 `tuist_ex` 函式庫。Xcode 還會從其連結的專案生成事件中公開 `tuist_generation_version`，這可能與上傳的 CLI 不同。缺失的觀測值為 null，不會從伺服器或其他報告推斷。Bazel 使用其現有的 `bazel_version`；Struo 運行詳細資訊公開 `once_version`。這些欄位描述報告的版本，而非經驗證的身分或線路協定版本。REST 構建端點公開相同的元數據。現有的整合和不穩定測試技能不依賴版本欄位，無需更改工作流程。

Tuist 營運人員調查客戶帳戶時，是透過 Tuist 的內部營運工具進行，該工具會記錄每次呼叫；直接連接到此端點不會獲得超出用戶自身成員資格之外的任何存取權限。

### Pulse

Pulse 提供只讀工具，用於帳戶的營運指標、日誌、追蹤和錯誤，全部透過 `account_handle` 定址。前三者對應 Pulse 頁面及其 REST API；另外五個讓代理直接探索遙測數據，且沒有 REST 等效項：

| 工具 | 用途 | `/api/accounts/:account_handle/pulse` 下的 REST 等效項 |
| --- | --- | --- |
| `query_pulse` | Pulse 頁面表格 | `GET /:signal` |
| `get_pulse_analytics` | Pulse 頁面小工具 | `GET /:signal/analytics` |
| `get_pulse_error_issue` | 一個錯誤問題及其事件 | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | 即時或範圍 PromQL | 無 |
| `list_pulse_labels` | 標籤名稱，或一個標籤的值 | 無 |
| `search_pulse_logs` | 過濾後的日誌條目 | 無 |
| `search_pulse_traces` | 過濾後的跨度 | 無 |
| `get_pulse_trace` | 一個追蹤的所有跨度 | 無 |

Pulse 僅限於伺服器設定組織的當前成員，即使帳戶或專案是公開的。它需要用戶驗證或與用戶關聯的 `mcp` 憑證以及帳戶讀取授權。專案權杖、普通帳戶權杖、匿名註冊以及沒有組織成員資格的營運人員存取權限都不會授予 Pulse 存取權。憑證無法選擇其他後端或遙測租戶，且只有伺服器設定的帳戶擁有 Pulse 遙測數據，因此沒有任何工具可以讀取其他帳戶的數據。瀏覽器代理僅在 Pulse 頁面上收到這些工具，且在該頁面的帳戶範圍內。

REST 需要用戶憑證。OAuth 和 `auth.md` 用戶關聯僅在 `/mcp` 端點上可用；沒有當前用戶的帳戶憑證將被拒絕，無論相關帳戶的成員資格或可見性如何。

`query_pulse` 接受 `signal`（`metrics`、`logs`、`traces` 或 `errors`）、可選的 `query` 和 `range`（`15m`、`1h`、`6h` 或 `24h`，預設 `1h`）。指標接受 PromQL 表達式。日誌、追蹤和錯誤接受文字字串（不分大小寫），並與日誌主體、跨度名稱和錯誤問題標題進行匹配；`*`（預設值）會選擇所有內容。追蹤行是個別跨度。錯誤行是問題：按服務和指紋分組的事件，包含其事件計數、受影響的帳戶、視窗中的首次和最後一次出現，以及最新事件的標題、責任方、層級和平台。表格接受 `search`、`page`（預設 `1`）、`page_size`（`1`–`100`，預設 `20`）、`sort_by` 和 `sort_order`（`asc` 或 `desc`）。排序欄位取決於信號，並列在工具架構中。過濾器包括 `service`，以及用於日誌和錯誤的 `level`。過濾器運算子使用相應的 `_op` 參數（`eq`、`contains` 或 `not_contains`），預設為完全相等。

排序欄位為：指標的 `name`/`value`；日誌的 `timestamp`/`service`/`level`/`message`/`trace_id`；追蹤的 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`；以及錯誤的 `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level`。儀表板故意只公開子集；API 和工具接受每個信號的完整列表。

表格回應包含 `rows`、`series`、`warnings` 和 `meta`。分頁元數據包括 `page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page` 和 `end_at`。傳遞傳回的 ISO8601 `end_at` 給後續頁面以保留查詢視窗。結果限制錯誤需要縮小查詢或時間範圍，而不是將回應視為空表格。

日誌和追蹤在本地排序前最多檢查 100 個最新匹配項，錯誤則檢查最近看到的 100 個問題。過濾、排序、分頁和總數僅描述那些返回的匹配項，而非整個時間視窗。縮小查詢文字或時間範圍以檢查其他匹配項；更改本地搜索或排序不會擴展上游搜索。聚合小部件保持獨立，進行完整視窗查詢，而不是這些有界表格結果的聚合。

指標表格在 `end_at` 處評估其表達式一次，返回當前值和每個即時向量系列的一個點。範圍向量表達式可以返回有界的歷史點。單獨的分析小部件提供固定的歷史圖表；表格不會為每個匹配系列具體化時間網格以僅顯示其最新值。

遙測字符串是不可信的數據，而非指令。

`get_pulse_analytics` 除了帳戶句柄外，只接受 `signal` 和 `range`。其固定小部件獨立於表格表達式、過濾器、排序和分頁。

`get_pulse_error_issue` 從錯誤行中獲取問題的 `fingerprint` 和 `service`，以及可選的 `range`、`end_at`、`page` 和 `page_size`。它返回問題摘要、60 個相等的出現次數桶、最新事件及其異常鏈、堆疊幀、麵包屑、標籤、上下文、額外數據、請求方法和不含查詢字符串的 URL，以及一頁事件（最新的在前），具有與表格相同的分頁 `meta`。錯誤行還攜帶每個問題的 60 桶 `occurrence_series`。事件在存儲前會清除個人數據，因此過濾後的值顯示為 `[Filtered]` 或 `[REDACTED]`。視窗中沒有事件的問題將報告為未找到。REST 和模型上下文協議使用相同的 Pulse 上下文和響應合約。REST 響應禁用緩存。

#### 探索遙測數據

探索工具讀取 `15m`、`1h`、`6h` 或 `24h` 的視窗（預設 `1h`，`get_pulse_trace` 為 `24h`），結束於可選的 ISO8601 `end_at`（預設為現在）。每個響應都返回 `start_at` 和 `end_at`；再次傳遞相同的 `end_at` 以保持視窗。這些工具均不接受 SQL。

- `query_pulse_metrics` 在 `end_at`（`type: instant`，預設）或視窗內的每 `step` 秒（`type: range`）評估 `query`（PromQL 表達式）。步長預設為且不能小於視窗除以 360，因此一個系列最多有 361 個點。結果最多有 5,000 個系列。點為 `[unix_seconds, value]`，`NaN` 和無限值為字符串。即時查詢拒絕 `range` 和 `step`。
- `list_pulse_labels` 接受 `signal`。如果沒有 `label`，它列出標籤名稱；如果有 `label`，它列出該標籤的值。對於指標，`__name__` 列出指標名稱，任何其他標籤的值都需要 `match`（系列選擇器，例如 `up`）。日誌和追蹤標籤值接受 `filters`；追蹤標籤名稱來自追蹤架構，不接受。日誌和追蹤值包括其在視窗中的條目計數，最頻繁的在前，因此它們也可用作細分，例如按服務的錯誤。`search` 僅保留包含文字文本的名稱或值，`limit` 接受 `1`–`1000`（預設 `100`）。日誌標籤名稱發現最多檢查每種類型的 1,000 個不同屬性集，並僅列出過濾器接受的鍵。
- `search_pulse_logs` 返回最多 `limit` 個條目（`1`–`100`，預設 `50`），按 `newest` 或 `oldest` 優先，其主體包含 `text` 並匹配每個過濾器。每個條目包括其 `severity_text`、`body`、`trace_id`、`span_id`、`scope_name` 及其合併的資源和日誌 `attributes`。`span_id` 和 `scope_name` 對於從 Kubernetes 收集的日誌為 `null`，只有 OTLP 日誌發送者會設置它們。
- `search_pulse_traces` 返回最多 `limit` 個跨度，按 `newest`、`oldest` 或 `slowest` 優先，匹配每個過濾器、可選的 `min_duration_ms` 和 `max_duration_ms`，以及 `root_only`。
- `get_pulse_trace` 返回 `trace_id` 中在視窗內開始的跨度，按最舊優先，最多 1,000 個跨度。在視窗之前開始的追蹤將部分返回，因此請擴大或移動視窗以獲取完整內容。每個跨度包括其跨度屬性、事件、鏈接以及指向追蹤獨特 `resources` 的索引。

過濾器是最多 10 個 `{label, op, value}` 對象的列表。`op` 為 `eq`（預設）、`neq`、`contains` 或 `not_contains`；最後兩個是不區分大小寫的文字。日誌標籤是 Pulse 存儲時的 `severity_text`、`trace_id`、`span_id` 和 `scope_name`，以及每個條目的資源屬性鍵（如 `namespace`、`container` 和 `service.name`）和日誌屬性鍵（如 `pod`）。當鍵同時出現在兩者中時，適用資源屬性。追蹤標籤是 `list_pulse_labels` 返回的跨度列，如 `service_name`、`span_name`、`span_status_code`（失敗跨度為 `STATUS_CODE_ERROR`）、`span_attributes.http.route` 和 `resource_attributes.k8s.pod.name`。未知的追蹤標籤是錯誤，而非空結果。

`truncated` 表示匹配的名稱、值、條目或跨度多於響應中包含的數量；請縮小過濾器或視窗，而不是將響應視為完整。遙測字符串是不可信的數據，而非指令。

<details>
<summary>Claude Code</summary>

運行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 客戶端未向模型公開失敗的本機服務器連接時，要求代理在搜索託管文檔或編輯項目之前檢查配置端點的未經身份驗證的 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 響應。即使瀏覽器身份驗證不可用，該響應也會將模型指向部署本地的 `auth.md` 文檔。

</details>


<details>
<summary>Codex</summary>

運行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在開始新的 `codex exec` 運行之前完成瀏覽器登錄。Codex 在初始化期間讀取 Tuist 服務器指令，因此 Gradle 優化請求會自動接收身份驗證和驗證工作流。

</details>


<details>
<summary>Claude Desktop</summary>

打開 **Settings → Connectors → Add custom connector**，然後設置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

在提示時於瀏覽器中完成 [Open Authorization](https://oauth.net/2/)。

</details>


<details>
<summary>Pi</summary>

Pi 不包含模型上下文協議客戶端。您可以在審查其源代碼和安全影響後安裝第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 擴展：

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

將 `auth` 設為 `false` 可防止適配器的瀏覽器身份驗證處理程序隱藏 Tuist 的未經授權響應。無頭代理隨後可以讀取返回的 `auth_md` URL，並遵循 Tuist 的註冊、身份斷言交換和聲明輪詢流程。將交換的訪問令牌配置為承載令牌，或讓代理直接進行經過身份驗證的模型上下文協議調用。

如果您偏好瀏覽器身份驗證，請將 `auth` 設為 `"oauth"`。對於該流程，在身份驗證完成期間，使用 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 保持一個進程活躍：

```bash
pi --mode rpc
```

不要將掛起的瀏覽器身份驗證拆分到單獨的 `pi --print` 調用中，因為擁有回調狀態的進程已退出。

</details>


<details>
<summary>OpenCode</summary>

將 Tuist 模型上下文協議服務器添加到 `opencode.json`：

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

然後對服務器進行身份驗證：

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

使用 **Command Palette → MCP: Add Server**，然後配置具有以下設置的 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 服務器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

打開 **Agent panel → Settings → Add Custom Server**，然後設置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果您的代理支持 `auth.md`，它可以匿名啟動而無需打開瀏覽器。當提供者身份已鏈接時，受信任的提供者身份也可以在不使用瀏覽器的情況下完成。對於服務認證電子郵件、匿名聲明或首次提供者鏈接，代理會向您顯示 Tuist 驗證鏈接和六位數代碼。打開鏈接，登錄，並在 Tuist 頁面上輸入代理的代碼。切勿將代碼發送回代理。Tuist 的授權服務器元數據直接指向部署自身的 `/auth.md`，其中包含確切的請求和輪詢結構。

## Amp orbs 和 Claude Code 雲會話中的代理

在連接到 Tuist 帳戶的沙盒中運行的編碼代理可以使用其自身的身份令牌對端點進行身份驗證，而無需瀏覽器或存儲的 Tuist 憑據：

- 通過 **Settings → Integrations → Amp** 連接的 Amp 工作區或項目的 **Amp orbs** 會發送 orb 的 ID 令牌。在 Amp 中，將服務器的 `Authorization` 標頭設置為 `Bearer ${amp:id-token}`。Amp 為服務器 URL 的來源鑄造令牌，因此 URL 必須是此 Tuist 實例自身的地址，並在過期前刷新它。為其他來源鑄造的令牌將被拒絕。
- 連接的 Claude Code 環境的 **Claude Code cloud sessions** 會發送 Tuist 作為 `TUIST_OIDC_TOKEN` 傳遞給它們的會話令牌。將標頭設置為 `Bearer ${TUIST_OIDC_TOKEN}`。

Tuist 的 Linux 沙盒不會為您添加服務器：它們附帶 Tuist CLI（使用相同身份登錄）以及一項技能，告訴代理何時根據項目歷史檢查其結果。要為代理提供 MCP 工具，請使用上述標頭將服務器添加到您的 Amp 或 Claude Code 設置中，或添加到項目的 `.mcp.json` 中。

這些令牌提供對連接帳戶每個項目的只讀訪問權限：它們攜帶 `mcp` 組的讀取範圍，而不攜帶創建、更改或刪除數據（例如靜音或跳過測試）的範圍。斷開工作區或環境將在下次請求時停止訪問，且訪問權限從不超過令牌本身的有效期。連接到多個 Tuist 帳戶的 Amp 工作區將被拒絕，因為其令牌未指定單一帳戶。當缺少連接時，未經授權響應的 `error_description` 會說明這一點。

此只讀訪問權限僅適用於模型上下文協議端點。同一沙盒中的命令行工具和構建系統集成仍會交換令牌以獲取連接的 CI 訪問權限。

## WebMCP

在支持 [WebMCP](https://webmachinelearning.github.io/webmcp) 的瀏覽器中，Tuist 的頁面使用 `document.modelContext` 註冊工具，因此內置於瀏覽器的代理可以在無需任何額外配置的情況下調用它們。調用在 Tuist 服務器上運行。

- **Website and documentation pages** 註冊文檔和源代碼工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 和 `read_tuist_file`）。它們不需要您登錄。
- 當您登錄時，**An account's dashboard pages** 會為該帳戶註冊 Tuist 的只讀工具。每個頁面僅註冊其顯示內容的工具，針對項目的構建系統：Gradle 項目的構建頁面獲得 Gradle 構建工具，其測試頁面獲得測試和覆蓋率工具，運行器頁面獲得運行器工具，沙盒頁面獲得沙盒工具。每個頁面還獲得文檔工具 `list_projects` 和 `get_project`。工具以登錄用戶的身份運行，因此它們只能訪問您可以在儀表板中讀取的數據，且僅限於您正在查看的帳戶。當您移動到另一個頁面或帳戶時，工具將替換為該頁面的工具。

創建、更改或刪除數據的工具無法通過 WebMCP 使用，因為瀏覽器代理在無需您添加的情況下接收工具，並讀取構建和測試產生的內容。連接 MCP 客戶端到 `/mcp` 端點以使用這些工具。

如果組織強制執行單點登錄，請使用其提供者登錄儀表板以使用其工具。

## 構建系統集成使用兩個憑據

用於模型上下文協議工具的憑據不會對 Gradle 插件或 Bazel 的遠程服務進行身份驗證。在代理編輯或驗證 Gradle 或 Bazel 集成之前，它應運行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未經過身份驗證，代理必須停止並要求用戶運行：

```bash
tuist auth login --url https://tuist.dev
```

對於本地或自託管部署，請替換兩個命令和 `tuist.toml` 中的 URL。在所有地方保持主機名拼寫一致。例如，`localhost` 和 `127.0.0.1` 使用單獨的存儲憑據。


## 功能

### 工具

以下工具可通過 Tuist 模型上下文協議服務器使用：

每個工具都發布人類可讀的描述以及明確的輸入和輸出模式。成功的調用返回符合宣傳輸出模式的結構化內容，以及為尚未使用結構化內容的客戶端序列化為文本的相同結果。

接受單一記錄識別碼（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）的工具，亦接受該記錄的 Tuist 儀表板 URL。請直接從瀏覽器複製 URL，無須從中提取識別碼。

`get_xcode_build`、`get_test_run`、`get_gradle_build` 和 `get_project` 可以包含 `side_quests`：項目未使用但記錄顯示會有幫助的 Tuist 功能。每個都有 `id`、說明其依據證據的 `tip`，以及 `docs` 連結。系統會要求代理先完成用戶請求，提及適用的附帶任務，並僅在用戶同意時才執行其中一項。這些只返回給項目帳戶的成員，無論他們是使用用戶會話、MCP 令牌還是代理身份連接：

| ID | 工具 | 建議時機 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | 使用 Xcode 26 或更高版本處理的乾淨構建沒有運行任何可緩存的編譯任務。 |
| `gradle_build_cache` | `get_gradle_build` | 構建執行了可緩存任務，但 Gradle 的構建緩存沒有為任何任務計算鍵值，表示構建緩存已關閉。 |
| `flaky_test_quarantine` | `get_test_run` | 一次運行包含不穩定測試，且項目中沒有啟用的自動化將其靜音或跳過。不建議用於 Struo 項目。 |
| `test_sharding` | `get_test_run` | 在 Tuist 可分片的構建系統中，一次未分片的 CI 運行耗時 10 分鐘或以上。提示會說明選擇性測試當時跳過了多少測試。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI 運行使用了 GitHub Actions、Bitrise、GitLab CI 或 Buildkite 機器，而該帳戶從未在 Tuist Runners 上運行作業。僅限 tuist.dev。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actions 運行屬於一個未連接到其 GitHub 存儲庫的項目。 |
| `other_build_systems` | `get_project` | 該帳戶並未在所有支持的構建系統中使用 Tuist。提示列出了識別其他系統的文件，以便代理檢查存儲庫。 |

#### 文檔和社區搜索

此只讀工具通過驅動文檔網站的同一搜索引擎，搜索 Tuist 的文檔、[應用程序編程接口](https://en.wikipedia.org/wiki/API)參考、GitHub 發布、社區論壇和 GitHub issues。發布結果包括產品、版本、發布日期和預發布狀態。默認搜索穩定發布，可以使用 `include_prereleases` 包含預發布。該工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管服務器上可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公開的 Tuist 文檔、應用程序編程接口參考、GitHub 發布、社區討論和 GitHub issues。可選限制為一個 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 反饋

當 Tuist 工具或提示未按預期工作時（例如結果令人困惑、出錯、數據缺失或功能缺失），代理可以向 Tuist 團隊報告。系統會要求代理建議提交報告，並僅在您同意後發送。每份報告都會開啟與 Tuist 支持團隊的對話，他們可能會通過電子郵件回覆您。報告包括代理的預期、實際發生情況、可選建議、您的 Tuist 用戶 ID、handle 和電子郵件，以及您所屬的組織。代理還可以指明問題發生的帳戶和項目，以便團隊知道跟進哪個組織；僅接受您所屬的帳戶。只有以 Tuist 用戶身份登錄的代理才能發送報告，每個用戶每小時最多可提交 10 份報告。該工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管服務器上可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `report_feedback` | 報告 Tuist 工具或提示的問題。可選指定 `tool_name`、問題發生的 `account_handle` 和 `project_handle`，並添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基於源代碼的回答

這些只讀工具讓代理使用與託管服務器一起部署的確切公共 Tuist 源代碼修訂版，作為依賴當前行為的答案的事實來源。它們僅在 `https://tuist.dev/mcp` 可用。

兼容的客戶端在初始化期間會收到關於工具源代碼修訂版、連結和結果限制的事實描述，以及內聯 OAuth 認證信息。這些描述不規定回答風格或驗證工作流程。用戶可以直接提問，無須先調用 `ask_tuist` 提示；該提示仍可用於明確的基於源代碼的工作流程。

每個操作都有固定的併發、持續時間、遍歷、讀取字節數和響應大小限制。搜索和列表結果包含 `truncated` 和 `truncation_reason` 字段。當結果被截斷時，請縮小路徑、文件模式或搜索詞，而不是將結果視為完整。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 通過搜索源文件來回答有關當前行為、默認值、配置、功能開關、錯誤處理或未記錄細節的問題。結果包括周圍行、固定修訂版的源代碼連結和掃描統計信息。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，發現源子系統或附近的測試。列表具有有限的深度和結果數量。 | 無 |
| `read_tuist_file` | 在找到相關路徑後，檢查實現文件、調用點或測試中的特定行範圍。截斷的響應提供 `next_start_line` 以繼續。 | `path` |

#### 項目

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出經過認證的用戶可用的個人和組織帳戶 handle，包括每個帳戶是否可以創建項目。 | 無 |
| `get_organization` | 獲取組織的成員目錄。待處理的邀請需要與儀表板相同的管理員權限；永遠不會返回邀請接受令牌。 | `account_handle` |
| `create_organization` | 為經過認證的用戶創建 Tuist 組織。 | `handle` |
| `create_project` | 在經過認證的用戶可訪問的帳戶下創建 Tuist 項目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有的 Tuist 用戶添加到組織或更新現有成員的角色。接受 `user`（默認）、`admin` 或 `viewer`，其中查看者可以閱讀儀表板和運行記錄，但不能更改任何內容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有的 Tuist 用戶。Tuist 會發送一封包含接受連結的電子郵件，該連結在 14 天後過期；當服務器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製連結。接受 `user`（默認）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其連結不再能被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出經過認證的用戶可訪問的所有項目。 | 無 |
| `get_project` | 獲取項目的配置和連接的存儲庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將項目鏈接到帳戶的 GitHub App 安裝可訪問的 GitHub 存儲庫。項目採用存儲庫的默認分支。需要項目管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除項目與其 GitHub 存儲庫的鏈接。需要項目管理員權限。 | `account_handle`, `project_handle` |

#### 帳戶令牌

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳戶令牌元數據，不暴露令牌值。 | `account_handle` |
| `get_account_token` | 獲取帳戶令牌元數據，不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出項目令牌元數據，不暴露令牌值。 | `account_handle`, `project_handle` |

#### 通知規則

這些工具管理經過認證的用戶自己的通知規則：當事件（例如新預覽）發生在規則的項目中（或者在未列出任何項目時，發生在您可被通知的任何項目中）並滿足其條件時，執行其操作，例如向您的 Tuist 應用設備發送推送通知。沒有規則就不會收到通知。它們需要用戶認證，僅對您自己的規則起作用，並且僅接受您所屬帳戶的項目。它們不提供給儀表板頁面，因為規則跨越您所有的帳戶。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_notification_events` | 列出規則可以訂閱的事件類型，每個類型都帶有用於其條件的 JSON Schema。 | 無 |
| `list_notification_condition_options` | 建議項目中事件的條件值，例如其最近預覽的軌道和分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出您的規則。 | 無 |
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
| `list_runner_workflows` | 列出帳戶的持續集成工作流程匯總。 | `account_handle` |
| `list_runner_profiles` | 列出帳戶的持續集成運行器配置檔案，並包含每個配置檔案的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出運行器配置檔案可使用的機器型號和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 創建一個包含平台、機器型號以及（在 macOS 上）Xcode 版本的運行器配置檔案。可選擇設定哪些分支會儲存其快取卷。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改運行器配置檔案的機器型號、Xcode 版本，或哪些分支會儲存其自訂快取卷的變更。省略的欄位會保留其值。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 經用戶確認後刪除運行器配置檔案。預設配置檔案無法刪除。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

運行器卷工具公開與「卷」儀表板相同的數據。讀取工具需要運行器訪問權限；清除操作需要帳戶管理權限或 `account:runners:write` 範圍，以及用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名稱和存儲庫過濾、排序並分頁顯示卷。 | `account_handle` |
| `get_runner_volume` | 存儲庫、平台、容量、已用空間和最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁顯示作業和工作流程參考、快取狀態、命中結果和掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作業掛載的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存儲序列、作業運行次數、命中率和趨勢。可選 `volume_id`、`start` 和 `end`（ISO 8601）；預設為七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 刪除卷及其儲存的內容。正在運行的作業會保留其私人副本但無法儲存它們；後續使用相同密鑰的作業將從空狀態開始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷庫存還接受 `name` 和 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的測量和命中結果保持為 `null`。快取狀態描述卷變更是否已儲存，而非作業成功與否。

#### 沙盒

沙盒工具公開與「沙盒」儀表板相同的數據和操作，並具有與 [API](https://tuist.dev/api/docs) 相同的訪問權限：帳戶成員可以使用帳戶中每個沙盒的每個工具。只讀查看者無法使用它們。帳戶需要啟用沙盒功能。儀表板的沙盒頁面會註冊只讀工具。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_sandboxes` | 分頁顯示沙盒及其狀態、型號和時間戳。可選 `search`（沙盒中的文本、Amp Orb 或 Anthropic 會話 ID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）和 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的狀態、型號、節點、歸檔和時間戳。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小時數、創建的沙盒數量、會話、設置和啟動持續時間，以及相對於帳戶限制的峰值 vCPU、內存和磁盤使用量，並包含趨勢。可選 `start` 和 `end`（ISO 8601）；預設為 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 啟動一個空白沙盒並在其運行後返回。可選 `platform`（`linux` 或 `darwin`）、`xcode_version`（macOS 沙盒的確切 Xcode 版本，從工具描述中列出的版本中選擇；意味著 `darwin`）、`repository`（macOS 沙盒的 github.com `owner/name`，連接到帳戶的一個項目：當 Linux Claude Code 環境擁有 macOS 設置腳本時，Mac 會從其 <.localized_link href="/guides/features/sandboxes/claude#remote-mac-snapshots">就緒快照</.localized_link> 啟動，並在後台開始啟動映像中最新的 Pro iPhone 模擬器）、`template`、帶有 `memory_mb` 的 `vcpus`（Linux：2x4096、4x8192 或 8x16384，預設 2x4096；macOS：8x8192、8x16384 或 8x24576，預設 8x8192）、`workspace_gb` 和 `lifetime_seconds`（在取消運行的命令並暫停和歸檔之前可以運行的時間長度，同時保留其文件：預設兩小時，最多一天）。其描述告訴代理查找存儲庫構建所使用的 Xcode（`.xcode-version`、mise、CI 配置或文檔）並傳遞它，因為其他 Xcode 會錯過存儲庫的快取和快照，閱讀 Mac 位於 `/opt/tuist/agent-guide.md` 的指南，並使用下面的模擬器工具顯示在 iOS 模擬器中運行的應用程序。Mac 上的 Tuist，在存儲庫固定版本時，會自行 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">使用帳戶的快取</.localized_link>。 | `account_handle` |
| `pause_sandbox` | 將正在運行的沙盒快照保存到其節點的磁盤。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢復已暫停或歸檔的沙盒。 | `account_handle`, `sandbox_id` |
| `extend_sandbox` | 從現在開始重新開始沙盒的生命週期，可選 `lifetime_seconds`（最多一天）。集成擁有的沙盒沒有生命週期限制。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 排隊將已暫停沙盒的磁盤移動到對象存儲。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 經用戶確認後刪除沙盒及其磁盤。 | `account_handle`, `sandbox_id` |
| `list_sandbox_devices` | 沙盒的設備及其 `id`、`name`、`platform`、`runtime` 和 `state`（`Booted`、`Shutdown`）。目前這些是 macOS 沙盒的模擬器，例如 iOS；尚不支持 Android 模擬器。 | `account_handle`, `sandbox_id` |
| `boot_sandbox_device` | 按名稱或 ID 啟動設備並等待最多 40 秒；模擬器會顯示在模擬器應用程序中。啟動已啟動的設備會成功。 | `account_handle`, `sandbox_id`, `device` |
| `launch_sandbox_app` | 在已啟動的設備上啟動應用程序，如果正在運行則重新啟動。傳遞 `app_path`（在沙盒中構建的 .app）以先安裝它，或傳遞 `app_id`（在 iOS 上為捆綁包 ID）以啟動已安裝的應用程序。當有多個設備啟動時，可選 `device`。 | `account_handle`, `sandbox_id` |
| `open_sandbox_url` | 在瀏覽器（iOS 上的 Safari）中打開網頁或在已啟動的設備上打開應用程序的深層鏈接。可選 `device`。 | `account_handle`, `sandbox_id`, `url` |
| `get_sandbox_screenshot` | 返回已啟動的設備，或使用 `target: screen` 返回沙盒的整個屏幕作為圖像：JPEG 格式，較長邊最多 1600 像素，以便適應代理的上下文。可選 `device`。如需磁盤上的全尺寸 PNG，請使用 `tuist sandbox screenshot`。 | `account_handle`, `sandbox_id` |

設備工具在沙盒中運行固定命令；它們不運行您傳遞的命令，只有 CLI 的 `tuist sandbox exec` 可以執行。在 Linux 沙盒上它們回應 `devices_unsupported`，在設備啟動之前回應 `device_not_booted`，對於沙盒沒有的名稱或 ID 回應 `device_not_found`，對於缺失的 `app_path` 或未安裝的應用程序回應 `app_not_found`。

沙盒工具的錯誤以單獨一行上的穩定代碼開頭，例如 `code: fleet_busy`，隨後是需要執行的操作；帶有等待的代碼會添加一行 `retry_after_seconds:`。API 在其錯誤主體中發送相同的 `code`。當所有主機都繁忙時，`create_sandbox` 會等待最多 25 秒以獲取一個主機，然後才回應 `fleet_busy`。

#### Amp 工作區

呢啲工具管理 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 工作區連接</.localized_link>，讓 orb 無需令牌即可登入 Tuist。佢哋使用同儀表板「整合」頁面相同嘅僅限管理員權限。orb 入面嘅代理可以從 `$AMP_WORKSPACE_ID` 同 `$AMP_PROJECT_ID` 讀取自己嘅 ID。每個被連接允許嘅 orb 都會獲得帳戶中所有項目嘅 CI 存取權限，所以代理喺連接之前應該同用戶確認。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 列出帳戶已連接嘅 Amp 工作區，以及每個工作區限制到嘅項目（如有）。 | `account_handle` |
| `connect_amp_workspace` | 連接 Amp 工作區。可選 `project_id` 將登入限制為單一 Amp 項目嘅 orb。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 斷開工作區連接。其 orb 已有嘅會話仍然有效，直到過期為止。 | `account_handle`, `connection_id` |

#### Claude 環境

呢啲工具連接 Claude Managed Agents 自託管環境，令佢哋嘅會話喺 Tuist 沙盒中運行，就好似「設定」→「整合」→「Claude」咁。佢哋需要帳戶管理權限並啟用沙盒。代理可以使用 Anthropic 嘅 API 創建環境，但只有 Claude Console 會生成環境密鑰，所以代理需要向用戶索取。Tuist 使用 Anthropic API 金鑰或工作負載身份聯盟來啟動會話，並喺保存之前使用該憑證獲取環境。Anthropic 端嘅設置使用用戶自己嘅 Anthropic 憑證；Tuist 永遠不會接收佢哋。金鑰會通過客戶端同模型傳遞，所以只需明確提供佢哋。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_claude_environments` | 列出已連接嘅環境同每個環境使用嘅憑證，加上聯盟規則應該信任嘅發行者 URL 同主題前綴。 | `account_handle` |
| `connect_claude_environment` | 使用 `api_key` 連接環境，或者使用 `organization_id`、`workspace_id`、`service_account_id` 同 `federation_rule_id`。可選 `platform`、`vcpus` 同 `memory_mb` 用於設定沙盒規格。 | `account_handle`, `environment_id`, `environment_key` |

#### 組織 AI

呢啲工具管理組織服務器端 AI 任務使用嘅模型，好似「設定」→「AI」咁，並遵循相同規則：僅限組織管理員，且僅適用於設有 AI 設定嘅組織。每個任務，例如 `pulse_grouping` 或 `pulse_explanation`，如果有任務路由就使用佢，否則使用默認模型；如果兩者都沒有，就不會發送請求。每個工具都會返回完整配置，包括每個任務當前使用嘅模型，以及佢係來自路由、默認值還是無。添加或編輯提供者需要 API 金鑰，所以呢個操作要喺儀表板或 REST API（`/api/accounts/{handle}/ai`）中進行，而不能通過呢啲工具執行。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | 讀取提供者（不含金鑰）、模型、默認模型、任務路由同每個任務當前使用嘅模型。 | `account_handle` |
| `save_organization_ai_model` | 添加模型（`name`、`provider_id`、`upstream_model_id`），或按 `id` 更新模型。 | `account_handle` |
| `remove_organization_ai_model` | 刪除模型及其任務路由。 | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | 選擇默認模型，或使用 null 清除。 | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | 將 `task` 路由到已配置嘅 `model_id`，或按 `id` 更新路由。一個任務最多只有一個路由。 | `account_handle` |
| `remove_organization_ai_task_route` | 刪除路由，令任務重新使用默認模型。 | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | 刪除提供者及其金鑰、模型同佢哋嘅路由；解除已連結嘅 Claude 組織關聯。 | `account_handle`, `provider_id` |

#### Webhooks

Webhook 工具使用同儀表板相同嘅僅限管理員權限。傳送嘗試包含為端點記錄嘅請求同響應數據，但絕不包含端點簽名密鑰。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳戶嘅 webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 獲取 webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點嘅傳送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 獲取一次傳送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 構建

針對 Xcode、Gradle、Bazel、Mix 同 Cargo 嘅構建詳情工具暴露現有嘅 `custom_metadata: {tags, values}` 結構，包括基礎設施觀察數據（如果已報告）。值保持為字符串，不熟悉嘅鍵會被保留。例如，`tuist.cpu.available_processors` 描述運行時可用嘅邏輯處理器，而 `tuist.gradle.max_workers` 係 Gradle 工作線程限制，`tuist.jvm.max_heap_bytes` 係 JVM 堆內存限制，並非主機內存。呢啲係不受信任嘅客戶端觀察數據，並非經過驗證嘅運行器身份。缺失嘅觀察數據會保持缺失；導入嘅日誌同舊版客戶端可能沒有基礎設施元數據。Struo 元數據有待協調嘅客戶端/協議更新。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出項目嘅 Xcode 構建運行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 獲取特定 Xcode 構建運行嘅詳細資訊，包括儲存原始 `.xcactivitylog` 檔案嘅臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 構建運行嘅構建目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 構建運行嘅編譯檔案。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄嘅構建步驟，包含時間同結果，但不含日誌文字。 | `build_run_id` |
| `get_xcode_build_step` | 獲取一個記錄嘅構建步驟，包括其日誌同截斷標誌。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定構建運行嘅構建問題（警告同錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 構建運行嘅可緩存任務（緩存命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 構建運行嘅 [內容定址儲存](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 默認返回每頁 20 個步驟（透過 `page_size` 最多可設為 100），並提供 `page` 同 `pagination_metadata` 用於導航。使用 `search` 匹配標題、項目或目標，或過濾精確嘅 `project`、`target`、`category`（例如 `swiftCompilation`）同 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以優先顯示最慢嘅步驟（默認），或按 `start_ms` 按時間順序排序。步驟 ID 用於打破平局，並以十進制字符串形式返回以保留完整嘅 64 位精度。ID 僅限於單次構建，不應跨構建匹配。

可選嘅 `start_ms` 同 `end_ms` 選擇與從構建開始計算嘅毫秒時間範圍重疊嘅步驟；結束時間為exclusive。兩個工具都接受構建 UUID 或儀表板 URL 作為 `build_run_id`。將返回嘅步驟 `id` 原樣作為 `step_id` 傳遞以檢索其日誌。日誌每步最多保留 64 KiB，`log_truncated` 指示省略嘅輸出。

處理 Xcode 構建時默認會收集步驟。記錄嘅步驟數據保留 90 天。列表響應包括 `availability`：當存在記錄嘅步驟時為 `available`，即使過濾器無匹配項；當構建仍在處理中且尚未有步驟時為 `processing`；或者當步驟未被記錄或已過期時為 `unavailable`。

相同嘅操作可透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 同 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上使用，具有相同嘅過濾器同分頁功能。兩者都需要對構建項目具有讀取權限。

#### Gradle 構建

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整嘅身份驗證、項目設置、Gradle 插件、緩存策略同兩次構建驗證工作流程。Agent 應在編輯現有 Android 或 Gradle 項目之前調用此接口。 | 無 |
| `list_gradle_builds` | 列出項目嘅 Gradle 構建運行，包括自定義元數據。使用可選嘅 `tag` 參數按自定義標籤過濾。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 獲取構建元數據、任務/緩存計數同 `failures`：每個失敗任務同配置步驟嘅失敗消息。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任務結果、複合構建標識、可緩存性、增量狀態同失敗消息。 | `build_run_id` |
| `list_gradle_build_steps` | 列出帶計時嘅任務、配置同轉換，支持搜索、元數據同重疊時間過濾器。 | `build_run_id` |
| `get_gradle_build_step` | 透過不透明 ID 檢查記錄嘅步驟元數據；失敗任務或配置步驟嘅 `log` 即為其失敗消息。 | `build_run_id`, `step_id` |

Gradle 同 Bazel 步驟列表默認返回 20 個結果（最多 100 個），支持 `search`、精確嘅 `project`、`target`、`category` 同 `status`、重疊嘅 `start_ms` / `end_ms` 過濾器（結束時間 exclusive），以及 `duration_ms` 或 `start_ms` 排序。原樣傳遞返回嘅 ID；它們僅限於各自嘅構建。列表暴露 `time_origin` 同 `coverage`。舊版 Gradle 報告使用 `first_recorded_timestamp`，因為無上傳構建開始時間。Bazel 配置文件透過 `trace_profile` 覆蓋範圍同作為時間起點嘅 `profile_start` 暴露所有記錄嘅間隔。較舊嘅構建回退到保留嘅 BEP 摘要。源記錄在 90 天後過期。Bazel 詳情在發布時包括經清理嘅操作日誌。失敗任務或配置步驟嘅 Gradle 詳情包括 Tuist Gradle 插件作為 `log` 報告嘅失敗消息：異常消息及其原因鏈，如同 Gradle 控制台打印嘅那樣，無堆棧跟踪或任務輸出，項目內嘅路徑改為相對路徑，憑證同其他本地路徑被修飾，每步最多 16 KiB，每次構建最多 32 個失敗步驟。其他 Gradle 步驟、由舊版插件報告嘅構建同無憑證報告嘅 `log` 為 null。配置步驟在失敗時報告 `failure`，否則報告 `unknown`。`compare_builds` 提示使用此覆蓋範圍來區分完整嘅 Bazel 跟踪同保留嘅摘要，並指導 agent 在檢查更廣泛嘅調用輸出之前查看步驟詳情以獲取操作結果同日誌。

單步工具 `get_gradle_build_step` 同 `get_bazel_build_step` 透過 ID 檢索步驟，不接受時間過濾器；請使用相應嘅列表工具按時間範圍過濾步驟。

如果在列出同獲取步驟之間收到完整配置文件，則從保留摘要返回嘅 Bazel 步驟 ID 仍然可讀。步驟數據已過期嘅索引配置文件會報告為不可用。Gradle 步驟列表包括零持續時間嘅緩存同跳過操作。

#### Bazel 調用

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份驗證、項目設置、Bazel 配置同驗證工作流程。 | 無 |
| `list_bazel_invocations` | 按最新優先順序列出已完成嘅 [Bazel 構建事件協議](https://bazel.build/remote/bep) 調用，包括構建指標、有限執行時間線、關鍵路徑診斷同項目相關嘅遠程緩存總計。按 `status`、`git_branch`、`git_commit_sha`、`is_ci` 同 `command` 過濾。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 獲取一個已完成嘅 Bazel 調用，包括構建指標、有限執行時間線、關鍵路徑診斷同相關嘅遠程緩存總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄嘅 Bazel 配置文件間隔，帶有過濾器同明確嘅覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄嘅 Bazel 步驟及其發布嘅操作結果同經清理嘅日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_remote_actions` | 列出 Tuist 遠程執行為一次調用運行嘅操作，包括助記符、目標、操作摘要、退出代碼、執行路徑同階段計時。可選嘅 `sort_by`（`duration` 或 `queued_at`）、`failed` 同 `mnemonic` 過濾器。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_remote_action` | 獲取一個遠程操作嘅 argv、環境變量（類似密鑰嘅值被掩碼）、平台、工作目錄、輸出路徑、工作進程、退出代碼、stdout 同 stderr 嘅前 16 KiB、stderr 中識別嘅編譯器 `errors`、階段計時同操作摘要。 | `account_handle`, `project_handle`, `invocation_id`, `action_id` |
| `get_bazel_remote_action_log` | 按字節偏移量讀取遠程操作 stdout 或 stderr 最多 64 KiB，默認為流末尾。長流會整體複製，或者如果更長則保留前 16 KiB 同最後 16 MiB；`recorded` 列出可用範圍。 | `account_handle`, `project_handle`, `invocation_id`, `action_id`, `stream` |
| `list_bazel_invocation_logs` | 按執行順序列出為 Bazel 調用捕獲嘅經清理日誌：Bazel 進度輸出嘅有限尾部同 `test.log` 構件。可選嘅 `stream`（`stdout` 或 `stderr`）、`source`（`progress` 或 `test_log`）、`target_label` 同 `errors` 過濾器可縮小結果範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 獲取為 Bazel 調用捕獲嘅一個經清理日誌塊。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始 Bazel 遠程緩存觀察記錄，包括其操作、端點同觀察時間，可選擇縮小到特定調用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 獲取一條原始 Bazel 遠程緩存觀察記錄。 | `account_handle`, `project_handle`, `cache_event_id` |

#### 遠程執行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_remote_execution_activity` | 列出項目當前運行中嘅 Bazel 調用，以及正在運行或排隊中嘅遠程操作，包括每個操作嘅調用 ID、助記符、目標、操作摘要、機器大小同進入該狀態嘅時間。執行網關在預先準備好嘅 VM 上運行嘅操作，在完成之前不會列出。 | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | 獲取項目喺 `[from, to)` 期間嘅遠程執行同測量執行時間，包括總計、按機器大小、按分派模式以及按小時、日或月劃分。默認期間為過去 30 天，最多跨越 366 天。 | `account_handle`, `project_handle` |

`list_bazel_invocations` 過濾器為精確匹配，同一秒內完成嘅調用按調用 ID 排序。要查找分支上最新失敗嘅調用，請使用 `status: "failure"`、`git_branch` 同 `page_size: 1` 進行調用。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` 接受相同嘅過濾器。

喺 `list_bazel_build_steps` 上設置 `remote_execution: true` 以僅返回具有安全關聯服務器階段計時（來自索引配置文件）嘅操作。列表同詳細響應會顯示可選嘅可空值 `remote_queue_ms`、`remote_input_fetch_ms`、`remote_execution_ms` 同 `remote_output_upload_ms`。這些值係記錄階段嘅總和，包括操作內嘅重試；缺失或 null 值表示不可用，而非零。它們係配置文件觀察結果，並非計費用量或新鮮執行嘅證明，因為緩存嘅服務器結果可能攜帶執行元數據。客戶端上傳被排除在外。即使發生咗遠程工作，較舊或模糊嘅配置文件也可能返回無匹配操作。步驟 REST 端點接受相同嘅 `remote_execution=true` 過濾器。儀表板嘅「遠程執行」標籤頁使用相同嘅查詢同 90 天保留期。

測試日誌攜帶來源測試結果嘅 `target_label` 同嘗試 `status`，因此 `target_label: "//foo:bar_test"` 僅返回該目標嘅測試日誌。`errors: true` 返回失敗嘗試嘅測試日誌同包含 Bazel 報告器以 `ERROR:`、`FAIL:` 或 `TIMEOUT:` 開頭行嘅 stderr 進度塊。進度輸出未歸因於目標，且在記錄歸因之前寫入嘅日誌字段為空。失敗操作及其自身輸出可透過 `list_bazel_build_steps` 按目標獲取，而每個測試用例嘅失敗可從測試執行工具獲取。

#### Cargo 構建

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 按最新優先順序列出項目嘅 Cargo 構建。按 `git_branch`、`status`、`is_ci` 或 `command` 過濾。Cargo 測試執行結果可透過測試工具獲取，而非此構建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 獲取構建元數據、聚合緩存計數器，以及最多 500 個帶有診斷信息嘅記錄編譯作業。`compilations_truncated` 指示省略嘅作業；診斷信息僅涵蓋返回嘅作業。 | `account_handle`, `project_handle`, `build_id` |

喺 `get_cargo_build` 上設置 `include_cache_inspection: true` 以檢索經過驗證嘅任務決策同 CAS 操作，限制為 4 MB。默認情況下，以及當記錄缺失或無效時，`cache_inspection` 為 null。請尊重其部分捕獲嘅 `truncated` 標誌；傳輸並不能確定每個任務命中嘅本地/遠程來源。HTTP 詳細端點接受相同嘅查詢參數。

#### Mix 構建

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 按最新優先順序列出項目嘅 Mix (Elixir) 編譯構建，包括自定義元數據。按 `git_branch`、`status`、`is_ci` 或 `mix_env` 過濾。 | `account_handle`, `project_handle` |
| `get_mix_build` | 獲取構建元數據、診斷計數同依賴緩存摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 構建追蹤

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_build_trace` | 獲取 Xcode、Gradle、Bazel 或 Mix 構建時間線嘅下載鏈接，作為可在 [Perfetto](https://ui.perfetto.dev) 中打開嘅追蹤文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 係構建運行 ID（Bazel 嘅調用 ID）或構建嘅儀表板 URL。返回嘅 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有該鏈接嘅人都可以在 `expires_at`（調用後一小時）之前下載該構建嘅追蹤，無需其他憑證。代理可以使用 `curl` 下載，交比你喺 Perfetto 中打開，或使用 Perfetto 嘅 `trace_processor` 進行查詢。追蹤包含按並行性打包到軌道中嘅記錄步驟、跨越整個構建嘅軌道，以及當構建記錄機器指標時嘅 CPU 同內存計數器。它包含與上述步驟工具相同嘅數據，但無日誌。儀表板從每個構建嘅「時間線」標籤頁提供相同嘅文件。

#### Struo 運行

<a id="once-runs"></a>

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_once_runs` | 按最新優先順序列出項目嘅 Struo 運行。按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 過濾。未完成嘅運行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 獲取一次運行，包括其操作總計、緩存摘要，以及對於測試運行嘅測試總計。 | `account_handle`, `project_handle`, `run_id` |

Cargo 構建、Mix 構建同 Struo 運行 ID 喺項目內係唯一嘅。透過 HTTP API 喺 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 同 `.../once/runs` 可提供相同嘅讀取操作，每個都有一個用於單一 ID 嘅詳細端點。

#### 任務、操作、模塊同文件

呢啲項目範圍嘅工具會檢查跨運行嘅持久構建身份。首先使用 `list_build_entities`，然後將返回嘅穩定 `id` 連同相同嘅 `kind` 傳遞畀 `get_build_entity` 或 `list_build_entity_history`，並一併提供 `account_handle` 同 `project_handle`。無需構建或調用標識符。

| 工具 | 描述 | 必要參數 |
| --- | --- | --- |
| `list_build_entities` | 列出喺項目構建中見到嘅某一類任務、模塊、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 獲取一個構建實體，包括其本機身份同所選時段嘅分析數據。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 按最新優先順序列出一個構建實體嘅記錄執行、編譯或緩存事件。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 報告嘅操作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模塊 | 編譯同模塊緩存事件 |
| `once_actions` | Struo 操作 | 執行 |
| `mix_files` | Mix 編譯文件 | 編譯 |
| `mix_modules` | Mix 編譯模塊 | 編譯 |
| `cargo_crates` | Cargo crate | 記錄嘅 rustc 調用 |

呢啲工具正逐步推出，只返回已啟用它們嘅項目嘅數據；對於其他項目，它們會返回錯誤而非空結果。只有使用其構建工具鏈嘅項目才可使用某種類型。工具接受有限制嘅 `start_at`/`end_at` 過濾器、`environment`（`any`、`ci` 或 `local`）以及精確嘅 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明嘅 `after`/`before` 游標。未知嘅計時或緩存觀察結果保持不可用，而不會變成零或遺失。歷史記錄引用記錄嘅父級同本機執行，以便使用現有運行工具進行深入分析。

`get_build_entity` 指標包括 `duration_samples`，即具有記錄計時嘅觀察次數：真正嘅零持續時間會計入，缺失計時則不會。此計數可能低於觀察計數；不可用嘅持續時間統計數據保持為 null。

Xcode 模塊持續時間來自構建日誌中測量嘅目標編譯。模塊緩存解析同無編譯工作嘅目標不會貢獻持續時間樣本。編譯觀察引用 Xcode 構建；緩存事件引用生成或緩存命令。

Bazel 操作由目標標籤、助記符同配置嘅主要輸出標識，從而將不同操作同配置區分開來，而無需依賴輸入相關嘅緩存摘要。歷史記錄 BEP 報告嘅執行，而非緩存查找或追蹤配置文件階段。完整執行覆蓋需要 `--build_event_publish_all_actions`；工件交付係盡力而為，因此缺失觀察並非無工作運行嘅證據。較舊嘅 Kura 負載如果無穩定身份或執行開始，仍會被接受但未被索引。缺失嘅結束時間測量保持不可用，真正嘅零持續時間會計入。

Mix 模塊持續時間測量包含文件嘅編譯，而非獨立測量嘅模塊工作。當客戶端報告目標映射時，Struo 操作使用聲明嘅目標/能力/索引槽；僅診斷標籤並非穩定身份。現有客戶端同運行級別工具保持不變支持。

Cargo crate 按精確記錄嘅 crate 根、名稱同類型分組。檢出路徑更改可能會拆分歷史，並且構建配置文件、功能同目標三元組不會被區分。歷史測量 rustc 調用，而非每文件工作或緩存命中；缺失作業並不確立刪除或完整工作區清單。

分析讀取具有有限嘅內存同執行時間。如果查詢超出這些限制，工具會返回錯誤而非捏造空結果。

新觀察結果喺部署後被索引；此功能不會回填現有運行遙測數據。身份元數據喺 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link> 下比單個觀察結果更長久。

#### 測試

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出項目嘅測試執行，每個都帶有其 `selective_testing_strategy`。按 `selective_testing` 過濾（`coverage`，包括基於覆蓋率選擇嘅回退，或 `module_hash`）。`query` 字段係 `git_branch`、`scheme`、`status` 同 `selective_testing`：`field:"value"` 精確匹配，`field~"value"` 匹配不區分大小寫嘅子字符串（不適用於 `selective_testing`），前導 `-` 否定任一運算符。例如，`-git_branch~"gh-readonly-queue"` 排除合併隊列分支。空格分隔嘅查詢過濾器同顯式參數以 AND 語義組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 獲取測試執行嘅詳細指標，包括其自身嘅代碼覆蓋率（`coverage`：是否測量了任何內容、其行數同數值，以及是否係部分覆蓋或從骯髒檢出運行）、其選擇性測試摘要（`selective_testing`：策略、基準提交，以及請求、選擇、跳過同估計嘅測試計數，這些用於計算測試選擇有效性），以及其結果包（`.xcresult`）同運行它嘅命令會話存檔（CLI 日誌）嘅臨時下載 URL，或者當無命令鏈接到運行時為 `null`。分片運行嘅 `result_bundle_url` 係第一個報告分片嘅包；`shard_result_bundles` 列出每個分片報告嘅包，包括 CI 重試，帶有其分片索引同狀態，因此可以檢查失敗但無失敗測試嘅分片。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行嘅測試模塊運行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行嘅測試套件運行，可選按模塊過濾。 | `test_run_id` |
| `list_test_cases` | 列出項目嘅測試用例（支持如 `flaky` 等過濾器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 獲取測試案例嘅詳細指標，包括可靠性比率、不穩定比率同執行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例執行，可選按測試案例或測試執行過濾。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 獲取特定測試案例執行嘅失敗詳情同重複次數，如果其運行嘅基於覆蓋率選擇保留咗該測試，則解釋原因（`selective_testing`：決策、原因、匹配嘅變更文件同分片）。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例執行嘅附件。每個附件都包含一個臨時下載 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例嘅狀態變更，例如靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例嘅狀態或不穩定分類。變更可以向配置嘅 webhook 端點（包括外部服務）發送事件。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試執行嘅選擇性測試目標結果。 | `test_run_id` |
| `list_selective_testing_tests` | 列出測試執行嘅基於覆蓋率選擇所決定、選擇同跳過嘅測試，包括每個決策嘅原因、選擇它嘅變更文件、其分片同其在運行中嘅結果。按 `decision`、`reason` 或 `search` 過濾。 | `test_run_id` |
| `list_selective_testing_changed_files` | 列出自測試執行嘅基於覆蓋率選擇基準以來變更嘅文件，包括每個文件選擇咗幾多個測試，以及它是否係一個其變更會導致選擇回退嘅追蹤文件。 | `test_run_id` |
| `get_coverage` | 獲取項目嘅代碼覆蓋率及其目標，喺某個提交或分支嘅最新完整提交時。如果無 `git_commit_sha` 或 `branch`，則讀取默認分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出某個提交嘅代碼覆蓋率所測量嘅文件及其行覆蓋率，喺某個提交或分支嘅最新完整提交時。支持 `search`、排序同分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 獲取文件嘅代碼覆蓋率及其函數，喺某個提交或分支嘅最新完整提交時。設置 `include_lines` 以獲取每行嘅執行次數。 | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | 列出具有代碼覆蓋率嘅分支，默認分支排在前面。 | `account_handle`, `project_handle` |
| `list_coverage_commits` | 列出分支嘅提交及其覆蓋率狀態（`complete`、`incomplete`、`in_progress`、`not_measured`）、數值同與之前完整提交嘅變化，最新嘅排在前面。使用游標分頁。 | `account_handle`, `project_handle` |
| `list_coverage_runs` | 列出喺某個提交或分支後面具有代碼覆蓋率嘅測試執行，每個標記為 `full`、`partial` 或 `discarded`（骯髒檢出）。使用游標分頁。 | `account_handle`, `project_handle` |
| `list_coverage_targets` | 列出某個提交嘅每個目標嘅覆蓋率，然後係那些其運行從二進制緩存中獲取但無覆蓋率計數器嘅目標（`measured: false`）。支持 `search`、排序同分頁。 | `account_handle`, `project_handle` |

代碼覆蓋率工具僅對啟用咗代碼覆蓋率嘅帳戶可用。

#### 包

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出項目嘅包（應用二進制文件）。可選按 `git_branch` 同 `tags` 過濾（所有標籤必須精確匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 獲取特定包嘅詳細信息，包括自定義標籤。 | `bundle_id` |
| `get_bundle_artifact_tree` | 獲取包嘅完整構件樹，作為按路徑排序嘅平面列表。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以區分構建變體或環境。標籤係區分大小寫嘅標籤，包含字母、數字、連字符或下劃線，最多 10 個標籤，每個標籤最多 50 個字符。列表同詳細結果包括 `custom_metadata.tags`。分頁計數同分支過濾器適用於帶標籤嘅結果；省略 `tags` 會保留未過濾嘅行為。無效嘅標籤過濾器會返回錯誤而非擴大查詢範圍。

#### 生成

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_generations` | 列出項目嘅生成運行。 | `account_handle`, `project_handle` |
| `get_generation` | 獲取特定生成運行嘅詳細信息。 | `generation_id` |

#### 緩存運行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出項目嘅緩存運行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 獲取特定緩存運行嘅詳細信息，包括其會話存檔（CLI 日誌）嘅臨時下載 URL。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出某個生成或緩存運行嘅模塊緩存目標，顯示每個目標嘅緩存命中/未命中狀態同診斷組件哈希，包括額外嘅哈希輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_previews` | 列出項目可分享嘅應用程式預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 獲取預覽及其構建嘅臨時下載 URL。 | `preview_id` |
| `get_latest_preview` | 搵出運行中應用程式二進制文件嘅最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出項目嘅自動化警報。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 獲取自動化警報。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警報嘅修訂歷史。操作憑證會被遮蔽。 | `alert_id` |
| `list_project_notification_alerts` | 列出項目通知警報規則。需要同儀表板設置頁面相同嘅管理員權限。Webhook 地址會被遮蔽。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期嘅客戶端可以呼叫 `events/list` 來發現事件及其負載架構：

| 事件 | 發送時機 | 訂閱過濾器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例由穩定變為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持續集成嘅 Xcode、Gradle 或 Bazel 構建以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持續集成測試執行以失敗結束，包括合併嘅分片運行或被放棄嘅運行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist runner 作業以失敗完成。 | `account_handle` |
| `pulse_symptom.opened` | Pulse 喺看板或頁面層級打開或重新打開症狀。僅喺審計層級記錄嘅症狀，以及對已打開症狀嘅後續更改，唔會發送。 | `account_handle` |

要訂閱，客戶端呼叫 `events/subscribe`，帶上事件名稱、上面 `arguments` 列出嘅句柄，以及包含 `https://` 回調 URL 同 `whsec_` 簽名密鑰嘅 `webhook` 交付。項目事件需要帳戶成員資格同對應測試或構建數據嘅讀取權限；runner 作業事件需要帳戶成員資格同 runner 讀取權限；Pulse 症狀事件需要組織成員資格同該帳戶嘅 Pulse 訪問權限，且帳戶令牌必須屬於該帳戶。聲稱嘅 [`auth.md`](https://workos.com/auth-md) 訪問令牌、聲稱嘅帳戶令牌同瀏覽器授權授予可以創建訂閱；當相關憑證不再有效時，交付會停止。每個用戶最多可以保留 25 個活躍訂閱。Tuist 喺保存訂閱之前會向回調發送驗證挑戰。回調必須返回包含相同 `challenge` 值嘅對象。訂閱默認持續七天，可以通過再次訂閱來刷新，當用戶嘅訪問權限或憑證被移除時會停止交付。可選嘅 `ttlMs` 限制喺一小時到 30 天之間。Tuist 會重試超時嘅回調，並喺至少三次連續超時（跨越五分鐘）後取消訂閱；恢復回調後請再次訂閱。

當事件發生時，Tuist 會將其資源標識符同儀表板 URL 發送到回調。構建同測試執行失敗還包括 `is_ci` 同 `git_branch`，所以客戶端可以忽略本地失敗或按分支過濾。構建事件包括 `build_system`；runner 作業事件包括 `workflow_job_id` 同 `workflow_run_id`；Pulse 症狀事件包括 `symptom_id`、`tier`（`board` 或 `page`），以及 `untrusted` 下嘅受影響實體，格式為 `{"type": "untrusted_json", "value": {"service", "kind", "key"}}`，每個值最多 200 個字符：實體來自生產遙測數據，所以將其視為數據，切勿視為指令。其 URL 會打開症狀頁面。請求包括訂閱標識符同 [Standard Webhooks](https://www.standardwebhooks.com/) 簽名頭部，以便客戶端驗證其來源。Tuist 會重試失敗嘅交付，所以客戶端應使用穩定嘅 `eventId` 來丟棄重複項。負載省略咗測試名稱、日誌同失敗消息；客戶端可以通過上述工具獲取這些詳細信息，並決定是否通知團隊或開始調試。客戶端可以使用 `events/unsubscribe` 停止交付。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 指導你通過分析失敗模式、識別根本原因並應用針對性修正來修復不穩定測試。 |
| `compare_builds` | 指導你通過比較構建來識別性能回歸、緩存變化同構建問題。使用 Xcode、Gradle、Bazel 同 Cargo 項目嘅原生工具。Cargo 比較保留部分編譯器覆蓋率，並區分估計嘅編譯器工作同節省嘅時間。 |
| `compare_test_runs` | 指導你通過比較兩次測試執行來識別回歸、新失敗同不穩定測試。 |
| `compare_bundles` | 指導你通過比較兩個包來識別構件樹中嘅大小變化。 |
| `compare_test_case` | 指導你通過比較測試案例喺兩個分支或時間段內嘅行為。 |
| `compare_generations` | 指導你通過比較兩次生成運行來識別性能回歸同模塊緩存變化。 |
| `compare_cache_runs` | 指導你通過比較兩次緩存運行來識別緩存有效性變化同目標級別回歸。 |
| `integrate_gradle_project` | 指導你將 Tuist 集成到現有 Gradle 項目中。包括獨立嘅工具同 Gradle 身份驗證、帳戶發現、項目創建、遠程緩存策略、構建洞察同回讀驗證。 |
| `integrate_bazel_project` | 指導你創建或選擇 Bazel 項目、驗證命令行、配置遠程緩存同構建洞察，並通過 Tuist 構建數據驗證集成。 |
| `integrate_xcode_project` | 指導你將 Tuist 集成到現有 Xcode 項目中。支持 Xcode 緩存、構建洞察、測試洞察同測試分片。 |
| `ask_tuist` | 使用公開資料作為上下文，並以聚焦嘅實現同測試證據作為當前行為嘅事實來源，來回答 Tuist 問題。它需要一個 `question` 並引用修訂綁定嘅證據。 |

項目數據提示接受 `account_handle` 同 `project_handle`，將調查範圍限定於特定項目。比較提示亦接受 `base` 同 `head` 參數，以指定要比較嘅兩個項目（通過 ID、儀表板 URL 或分支名稱）。`ask_tuist` 接受 `question` 而非項目參數。`integrate_gradle_project` 亦接受 `features`，即要應用嘅 Gradle 集成逗號分隔列表：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 同 `test_sharding`。`integrate_bazel_project` 接受可選嘅 `server_url`，用於自託管或本地安裝。`integrate_xcode_project` 接受帶有 `xcode_cache`、`build_insights`、`test_insights` 同 `test_sharding` 嘅 `features`。

#### Gradle 集成提示功能

`integrate_gradle_project` 提示同 `get_gradle_integration_guide` 工具記錄咗完整嘅設置工作流程。該工具亦被伺服器嘅初始化指令引用，令未枚舉提示嘅代理能夠發現它。

| 功能 | 代理配置內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 嘅構建緩存，配置 Tuist 遠程緩存上傳策略，並建議僅從具有本地只讀用法嘅持續集成運行器進行上傳。 |
| `build_insights` | 應用 Tuist Gradle 插件，並在需要時配置構建分析上傳行為。 |
| `test_insights` | 應用 Tuist Gradle 插件，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 指導設置不穩定測試檢測、可選嘅 Gradle Test Retry 插件使用，以及測試隔離配置。 |
| `test_sharding` | 添加用於 `tuistPrepareTestShards`、分片矩陣生成同基於 `TUIST_SHARD_INDEX` 嘅測試執行嘅持續集成工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或從請求中推斷出最小有用集合，然後再編輯 Gradle 項目。

#### Xcode 集成提示功能

`integrate_xcode_project` 提示記錄咗 Tuist 支持嘅所有 Xcode 集成：

| 功能 | 代理配置內容 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成項目緩存設置、手動 Xcode 緩存構建設置，以及僅限於持續集成運行器嘅上傳策略。 |
| `build_insights` | 通過 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 同可選嘅機器指標。 |
| `test_insights` | 配置 `tuist inspect test`、方案測試後操作，以及為持續集成測試運行生成結果包。 |
| `test_sharding` | 添加帶有 `TUIST_SHARD_INDEX` 嘅 Xcode 或生成項目分片規劃同分片執行工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或從請求中推斷出最小有用集合，然後再編輯 Xcode 項目。
