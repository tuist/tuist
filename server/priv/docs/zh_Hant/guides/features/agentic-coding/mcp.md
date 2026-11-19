---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 的 MCP 端點，讓 AI 代理存取測試洞察等資訊。"
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一項開放標準，讓人工智慧代理能夠與外部服務和資料來源互動。它使 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等應用程式，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等編輯器能夠與 Tuist 互通。

Tuist 在 `https://tuist.dev/mcp` 託管伺服器端的 Model Context Protocol 端點。將你的用戶端連線至此端點後，代理即可存取你的 Tuist 專案資料，包括測試洞察、不穩定測試分析等。大多數工具讀取的 Tuist 資料，是已通過驗證的使用者在儀表板中原本就能看見的資料。每個工具都會宣告註解，說明其是否為唯讀、是否可能導致難以復原的變更（`destructiveHint`），以及是否能接觸 Tuist 以外的資源（`openWorldHint`）。會變更狀態的工具如下，且每項工具都受限於使用者在帳號或專案上的權限：

- **組織與成員**：`create_organization`、`add_organization_member`（新增現有使用者或變更成員角色）、`invite_organization_member`（向任意地址發送邀請電子郵件），以及 `cancel_organization_invitation`。
- **專案**：`create_project`、`start_project_logo_upload` 與 `complete_project_logo_upload`（更換標誌）、`connect_project_repository` 與 `disconnect_project_repository`（GitHub 儲存庫連結）。
- **測試**：`update_test_case`（將測試案例設為靜音、跳過、重新啟用，或標記為不穩定；此變更可能會觸發帳號的 webhook 端點）。
- **通知規則**：`create_notification_rule`、`update_notification_rule`，以及 `delete_notification_rule`。
- **持續整合執行器**：`create_runner_profile`、`update_runner_profile`（縮小可儲存快取卷宗的工作範圍時，會捨棄待處理的儲存作業）、`delete_runner_profile`，以及 `delete_runner_volume`（刪除卷宗中已儲存的內容）。
- **沙箱**：`create_sandbox`、`pause_sandbox`、`resume_sandbox`、`archive_sandbox`，以及 `delete_sandbox`（刪除其磁碟）。
- **回饋**：`report_feedback`（向 Tuist 團隊傳送關於工具或提示的報告；僅限 tuist.dev）。
- **組織 AI**：`save_organization_ai_model`、`remove_organization_ai_model`、`set_organization_ai_default_model`、`save_organization_ai_task_route`、`remove_organization_ai_task_route`，以及 `remove_organization_ai_provider`（刪除供應商的金鑰與模型，並解除與 Anthropic 上已連結的 Claude 組織之關聯）。
- **代理整合**：`connect_amp_workspace`（授予工作區的 orbs CI 存取帳號的權限）、`disconnect_amp_workspace`，以及 `connect_claude_environment`（允許 Claude Managed Agents 環境在 Tuist 沙箱中執行工作階段）。

`add_organization_member`、`cancel_organization_invitation`、`complete_project_logo_upload`、`disconnect_project_repository`、`update_test_case`、`update_notification_rule`、`delete_notification_rule`、`update_runner_profile`、`delete_runner_profile`、`delete_runner_volume`、`delete_sandbox`、`disconnect_amp_workspace`、`remove_organization_ai_provider`、`remove_organization_ai_model` 與 `remove_organization_ai_task_route` 宣告 `destructiveHint: true`，因為它們會取代或移除現有狀態。`invite_organization_member`、`update_test_case`、`connect_claude_environment`、`remove_organization_ai_provider` 與 `report_feedback` 宣告 `openWorldHint: true`，因為它們會發送電子郵件、通知外部 webhook 端點、呼叫 Anthropic，或向 Tuist 團隊傳送報告。

個人 Claude 與 ChatGPT 訂閱僅在儀表板的 AI 設定中連線，因此訂閱權杖與登入程序絕不會經過 Model Context Protocol 用戶端。帳號設定工具需要使用者驗證。專案權杖或一般帳號權杖無法使用這些工具。當使用者在瀏覽器中授權用戶端或領取 `auth.md` 註冊時，Tuist 僅在 Model Context Protocol 端點將該憑證與使用者關聯，以便設定工具完成所請求的工作流程。

Tuist 實作了 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求是無狀態的：用戶端會在每次請求中傳送其協定中繼資料，並可直接呼叫工具而無需初始化。`server/discover` 會回傳伺服器的身份、能力、支援的版本與指示。不存在工作階段識別碼或獨立的事件串流。使用 2025-06-18 或 2025-03-26 初始化流程的用戶端仍受支援；它們同樣无需伺服器工作階段即可運作。

## Model Context Protocol 與技能比較

Model Context Protocol 工具與 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 的功能可能重疊。鑑於目前兩者的重疊情況，請為每個工作流程選擇一種方法並一致使用，避免在同一流程中混合兩者。

對於支援外掛安裝的用戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 同時安裝兩者。

## 設定

在你的用戶端中將 `https://tuist.dev/mcp` 新增為遠端 Model Context Protocol 伺服器。伺服器的初始化指示與公開伺服器卡片內建描述了具備動態用戶端註冊功能的 OAuth 2.0 以及標準瀏覽器授權流程，無須要求代理抓取或遵循外部驗證文件。這些伺服器層級的指示保持工作流程指引的通用性：工具驗證不會驗證本機命令列工具或建置系統整合，代理應透過相關的 Tuist 工具驗證所請求的變更。特定建置系統的設定與驗證檢查記錄在整合指南與提示中。Tuist 仍分別宣傳 [Open Authorization](https://oauth.net/2/) 探索中繼資料與目前的 [auth.md protocol](https://workos.com/auth-md)，位於 `https://tuist.dev/auth.md`。

若你的其中一個組織強制實施單一登入，則在瀏覽器中授權用戶端需要透過該組織登入的工作階段，且在必要時 Tuist 會先將你導向至供應商。請參閱 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>。

該端點接受無狀態的 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），以及較舊的基於工作階段的生命週期。現有用戶端可以繼續使用目前的連線方式。

支援 Model Context Protocol 事件的用戶端可以訂閱專案事件。請參閱 [Events](#events) 以了解可用的事件與交付需求。

已支援遠端瀏覽器驗證的用戶端可以繼續在瀏覽器中進行驗證。支援 `auth.md` 的用戶端與代理可以匿名註冊、提供受信任的供應商身份斷言，或啟動服務驗證的電子郵件聲明。註冊會回傳由 Tuist 簽署的身份斷言，代理可在標準權杖端點將其交換為一小時的存取權杖。Tuist 會發布其公開簽章金鑰，並支援標準權杖撤銷與供應商安全事件交付。

未經驗證的代理應讀取 Model Context Protocol 端點回傳的 `WWW-Authenticate` 標頭，抓取受保護資源中繼資料與授權伺服器中繼資料，並遵循其 `agent_auth.skill` URL。Tuist 也會在未經授權的回應主體中回傳相同的本機 `auth_md` URL，讓由語言模型驅動的用戶端無需依賴原生用戶端整合即可探索流程。部署本機文件是端點名稱、請求主體、聲明輪詢與斷言交換的權威來源。

在代理啟動電子郵件聲明之前，必須要求使用者確認其 Tuist 帳號的電子郵件地址。不得從供應商設定檔、Git 設定、環境變數或工作階段中繼資料推斷該地址。

該端點使用 `mcp` 範圍群組。匿名預聲明憑證可以探索功能並讀取公開整合指引，但不會被視為已登入使用者。經過瀏覽器授權或聲明後，憑證將限定於使用者範圍，且每個工具會套用與儀表板相同的授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析為已驗證使用者可讀取的專案。Xcode 與 Gradle 建置工具接受建置 UUID 或儀表板 URL。UUID 必須精確識別一個專案；若出現在多個專案中，工具會回傳找不到，而非選擇另一個專案的報告。專案範圍的儀表板與 API 讀取仍可使用。回報的行為者識別碼是未經驗證的標籤，並非憑證或額外存取權限。

建置清單與詳細資訊工具會揭露選用的 `tuist_version` 中繼資料：用於 Xcode 與 Cargo 的回報 Tuist CLI、用於 Gradle 的 Tuist Gradle 外掛，以及用於 Mix 的 `tuist_ex` 函式庫。Xcode 也會從其連結的專案生成事件中揭露 `tuist_generation_version`，這可能與上傳的 CLI 不同。缺失的觀測值為 null，不會從伺服器或其他報告推斷。Bazel 使用其現有的 `bazel_version`；Once 執行詳細資訊則揭露 `once_version`。這些欄位描述回報的版本，並非經驗證的身份或線路協定版本。REST 建置端點會揭露相同的中繼資料。現有的整合與不穩定測試技能不依賴版本欄位，無需變更工作流程。

Tuist 營運人員調查客戶帳號時，會透過 Tuist 的內部營運工具進行，該工具會記錄每次呼叫；直接連線至此端點無法取得超出使用者自身成員資格以外的存取權限。

### Pulse

Pulse 揭露針對帳號營運指標、日誌、追蹤與錯誤的唯讀工具，皆以 `account_handle` 定址。前三者對應 Pulse 頁面及其 REST API；其餘五者讓代理直接探索遙測資料，且沒有對等的 REST 介面：

| 工具 | 用途 | `/api/accounts/:account_handle/pulse` 下的 REST 對等項目 |
| --- | --- | --- |
| `query_pulse` | Pulse 頁面表格 | `GET /:signal` |
| `get_pulse_analytics` | Pulse 頁面小工具 | `GET /:signal/analytics` |
| `get_pulse_error_issue` | 單一錯誤問題及其事件 | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | 即時或範圍 PromQL | 無 |
| `list_pulse_labels` | 標籤名稱，或單一標籤的值 | 無 |
| `search_pulse_logs` | 篩選過的日誌條目 | 無 |
| `search_pulse_traces` | 篩選過的跨度 | 無 |
| `get_pulse_trace` | 單一追蹤的所有跨度 | 無 |

Pulse 僅限伺服器設定組織的目前成員使用，即使帳號或專案為公開亦然。它需要使用者驗證或與使用者關聯的 `mcp` 憑證，以及帳號讀取授權。專案權杖、一般帳號權杖、匿名註冊，以及無組織成員資格的營運人員存取權，都不會授予 Pulse 存取權。憑證無法選擇其他後端或遙測租戶，且只有伺服器設定的帳號具備 Pulse 遙測資料，因此沒有任何工具可以讀取其他帳號的資料。瀏覽器代理僅在 Pulse 頁面內、該頁面的帳號範圍中接收這些工具。

REST 需要使用者憑證。OAuth 與 `auth.md` 使用者關聯僅在 `/mcp` 端點可用；不含目前使用者的帳號憑證會被拒絕，無論相關帳號的成員資格或可見性為何。

`query_pulse` 接受 `signal`（`metrics`、`logs`、`traces` 或 `errors`）、選用的 `query`，以及 `range`（`15m`、`1h`、`6h` 或 `24h`，預設 `1h`）。指標接受 PromQL 運算式。日誌、追蹤與錯誤接受字面、不區分大小寫的文字，並與日誌主體、跨度名稱及錯誤問題標題進行比對；`*`（預設）會選取所有項目。追蹤列是個別跨度。錯誤列是問題：按服務與指紋分組的事件，包含其事件計數、受影響帳號、視窗內的首次與最後一次發生，以及最新事件的標題、責任方、層級與平台。表格接受 `search`、`page`（預設 `1`）、`page_size`（`1`–`100`，預設 `20`）、`sort_by` 與 `sort_order`（`asc` 或 `desc`）。排序欄位取決於信號，並列於工具結構描述中。篩選器包含 `service`，以及用於日誌與錯誤的 `level`。篩選運算子使用對應的 `_op` 引數（`eq`、`contains` 或 `not_contains`），預設為完全相等。

排序欄位為：指標的 `name`/`value`；日誌的 `timestamp`/`service`/`level`/`message`/`trace_id`；追蹤的 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`；錯誤的 `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level`。儀表板刻意只揭露子集；API 與工具則接受每個信號的完整清單。

表格回應包含 `rows`、`series`、`warnings` 與 `meta`。分頁中繼資料包括 `page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page` 與 `end_at`。傳遞回傳的 ISO8601 `end_at` 給後續頁面以保留查詢視窗。結果限制錯誤需要縮小查詢或時間範圍，而非將回應視為空表格。

日誌與追蹤在本機排序前最多檢查 100 筆最新相符項目，錯誤則檢查最近看到的 100 個問題。篩選、排序、分頁與總數僅描述那些回傳的相符項目，而非整個時間視窗。縮小查詢文字或時間範圍以檢查其他相符項目；變更本機搜尋或排序不會擴大上游搜尋。彙總小工具仍保持為獨立的完整視窗查詢，而非這些有界表格結果的彙總。

指標表格會在 `end_at` 評估其表達式一次，回傳目前數值以及每個即時向量序列的一個點。範圍向量表達式可以回傳有界的历史點。獨立的分析小工具提供固定的歷史圖表；表格不會為了顯示最新數值而為每個相符序列實體化時間網格。

遙測字串是不可信資料，而非指令。

`get_pulse_analytics` 除了帳號代號外，僅接受 `signal` 與 `range`。其固定小工具獨立於表格表達式、篩選、排序與分頁。

`get_pulse_error_issue` 從錯誤列取得問題的 `fingerprint` 與 `service`，並可選填 `range`、`end_at`、`page` 與 `page_size`。它會回傳問題摘要、60 個等距發生次數區間、包含例外鏈結、堆疊框架、麵包屑、標籤、上下文、額外資料、請求方法與不含查詢字串的 URL 的最新事件，以及一頁由新到舊的事件，並使用與表格相同的分頁 `meta`。錯誤列也攜帶每個問題的 60 區間 `occurrence_series`。事件在儲存前會清除個人資訊，因此過濾後的值會顯示為 `[Filtered]` 或 `[REDACTED]`。若視窗內沒有事件的問題，則回報為找不到。REST 與 Model Context Protocol 使用相同的 Pulse 上下文與回應合約。REST 回應會停用快取。

#### 探索遙測資料

探索工具會讀取 `15m`、`1h`、`6h` 或 `24h` 的視窗（預設為 `1h`，`get_pulse_trace` 則為 `24h`），結束於可選的 ISO8601 `end_at`（預設為現在）。每個回應都會回傳 `start_at` 與 `end_at`；再次傳遞相同的 `end_at` 以保留視窗。這些工具皆不接受 SQL。

- `query_pulse_metrics` 會在 `end_at`（`type: instant`，預設）評估 `query`（PromQL 表達式），或在視窗內每隔 `step` 秒評估一次（`type: range`）。步長預設為且不得小於視窗除以 360，因此一個序列最多有 361 個點。結果最多包含 5,000 個序列。點為 `[unix_seconds, value]`，而 `NaN` 與無限值則為字串。即時查詢會拒絕 `range` 與 `step`。
- `list_pulse_labels` 接受 `signal`。若無 `label`，它會列出標籤名稱；若有 `label`，它會列出該標籤的值。對於指標，`__name__` 會列出指標名稱，而其他任何標籤的值都需要 `match`（系列選擇器，例如 `up`）。日誌與追蹤標籤值接受 `filters`；追蹤標籤名稱來自追蹤架構，因此不需要。日誌與追蹤值包含其在視窗內的項目計數，依頻率由高到低排列，因此也可作為細目分解，例如依服務劃分的錯誤。`search` 僅保留包含特定文字的名稱或值，而 `limit` 接受 `1`–`1000`（預設 `100`）。日誌標籤名稱發現最多檢查每種類型的一千個不同屬性集，並僅列出篩選器接受的鍵。
- `search_pulse_logs` 最多回傳 `limit` 筆項目（`1`–`100`，預設 `50`），依 `newest` 或 `oldest` 排序，其主體包含 `text` 且符合所有篩選條件。每筆項目包含其 `severity_text`、`body`、`trace_id`、`span_id`、`scope_name`，以及合併的資源與日誌 `attributes`。對於從 Kubernetes 收集的日誌（僅由 OTLP 日誌發送者設定），`span_id` 與 `scope_name` 為 `null`。
- `search_pulse_traces` 最多回傳 `limit` 個跨度，依 `newest`、`oldest` 或 `slowest` 排序，且符合所有篩選條件、可選的 `min_duration_ms` 與 `max_duration_ms`，以及 `root_only`。
- `get_pulse_trace` 回傳在視窗內開始的 `trace_id` 跨度，依最舊優先排序，最多 1,000 個跨度。在視窗之前開始的追蹤會部分回傳，因此請擴大或移動視窗以取得完整內容。每個跨度包含其跨度屬性、事件、連結，以及指向追蹤中不同 `resources` 的索引。

篩選器是最多 10 個 `{label, op, value}` 物件的清單。`op` 為 `eq`（預設）、`neq`、`contains` 或 `not_contains`；後兩者為不區分大小寫的文字。日誌標籤為 Pulse 儲存時的 `severity_text`、`trace_id`、`span_id` 與 `scope_name`，以及每筆項目資源屬性的鍵（例如 `namespace`、`container` 與 `service.name`）和日誌屬性的鍵（例如 `pod`）。當鍵同時出現時，適用資源屬性。追蹤標籤為 `list_pulse_labels` 回傳的跨度欄位，例如 `service_name`、`span_name`、`span_status_code`（失敗跨度為 `STATUS_CODE_ERROR`）、`span_attributes.http.route` 與 `resource_attributes.k8s.pod.name`。未知的追蹤標籤會導致錯誤，而非空結果。

`truncated` 表示相符的名稱、值、項目或跨度多於回應所包含的數量；請縮小篩選器或視窗，而非將回應視為完整。遙測字串是不可信資料，而非指令。

<details>
<summary>Claude Code</summary>

執行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 用戶端未向模型揭露失敗的原生伺服器連線時，要求代理程式在搜尋託管文件或編輯專案之前，檢查已設定端點的未驗證 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 回應。即使無法使用瀏覽器驗證，該回應也會將模型導向部署本地的 `auth.md` 文件。

</details>


<details>
<summary>Codex</summary>

執行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在開始新的 `codex exec` 執行之前，完成瀏覽器登入。Codex 在初始化期間會讀取 Tuist 伺服器指示，因此 Gradle 優化請求會自動獲得驗證與驗證工作流程。

</details>


<details>
<summary>Claude Desktop</summary>

開啟 **Settings → Connectors → Add custom connector**，然後設定：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

出現提示時，在瀏覽器中完成 [Open Authorization](https://oauth.net/2/)。

</details>


<details>
<summary>Pi</summary>

Pi 不包含 Model Context Protocol 用戶端。在檢視其原始碼與安全性影響後，您可以安裝第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 擴充功能：

```bash
pi install npm:pi-mcp-adapter
```

新增專案層級的 `.mcp.json` 檔案：

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

將 `auth` 設定為 `false` 可防止適配器的瀏覽器驗證處理常員隱藏 Tuist 的未經授權回應。無頭代理程式隨後可以讀取回傳的 `auth_md` URL，並遵循 Tuist 的註冊、身分斷言交換與聲明輪詢流程。將交換後的存取權杖設定為 bearer token，或讓代理程式直接進行經過驗證的 Model Context Protocol 呼叫。

若您偏好瀏覽器驗證，請將 `auth` 設定為 `"oauth"`。對於該流程，在驗證完成期間，請使用 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 保持一個程序存活：

```bash
pi --mode rpc
```

請勿將待處理的瀏覽器驗證拆分到多個 `pi --print` 叫用中，因為擁有回呼狀態的程序已結束。

</details>


<details>
<summary>OpenCode</summary>

將 Tuist Model Context Protocol 伺服器新增至 `opencode.json`：

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

接著驗證伺服器：

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

使用 **Command Palette → MCP: Add Server**，然後設定具備以下內容的 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 伺服器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

開啟 **Agent panel → Settings → Add Custom Server**，然後設定：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

若您的代理程式支援 `auth.md`，它可以在不開啟瀏覽器的情況下以匿名方式啟動。當提供者身分已連結時，受信任的提供者身分也可以在不使用瀏覽器的情況下完成驗證。對於服務驗證電子郵件、匿名聲明或首次提供者連結，代理程式會顯示 Tuist 驗證連結與六位數代碼。請開啟該連結、登入，並在 Tuist 頁面上輸入代理程式的代碼。切勿將代碼回傳給代理程式。Tuist 的授權伺服器中繼資料直接指向部署本身的 `/auth.md`，其中包含確切的請求與輪詢結構。

## Amp orbs 與 Claude Code 雲端工作階段中的代理程式

在連接至 Tuist 帳戶的沙盒中執行的編碼代理程式，可以使用其自身的身分權杖向端點進行驗證，無需瀏覽器或儲存的 Tuist 憑證：

- 透過 **Settings → Integrations → Amp** 連接帳戶的 Amp 工作區或專案之 **Amp orbs** 會傳送 orb 的身分權杖。在 Amp 中，將伺服器的 `Authorization` 標頭設定為 `Bearer ${amp:id-token}`。Amp 會針對伺服器 URL 的來源簽發權杖，因此 URL 必須是此 Tuist 執行個體自身的位址，並會在過期前重新整理。為其他來源簽發的權杖會被拒絕。
- 已連接 Claude Code 環境的 **Claude Code cloud sessions** 會傳送 Tuist 以 `TUIST_OIDC_TOKEN` 傳遞給它們的工作階段權杖。將標頭設定為 `Bearer ${TUIST_OIDC_TOKEN}`。

Tuist 的 Linux 沙盒不會為您新增伺服器：它們附帶 Tuist CLI（使用相同身分登入）以及一項技能，用於告知代理程式何時應根據專案歷史記錄檢查其結果。若要讓代理程式也能使用 MCP 工具，請使用上述標頭將伺服器新增至您的 Amp 或 Claude Code 設定，或新增至專案的 `.mcp.json`。

這些權杖提供對已連接帳戶中每個專案的唯讀存取權：它們攜帶 `mcp` 群組的讀取範圍，但不包含建立、變更或刪除資料（例如靜音或跳過測試）的範圍。中斷工作區或環境連線會在下一個請求時停止存取，且存取權永遠不會超過權杖本身的有效期。連接至多個 Tuist 帳戶的 Amp 工作區會被拒絕，因為其權杖未指定單一帳戶。當缺少連線時，未經授權回應的 `error_description` 會說明此情況。

此唯讀存取權僅適用於 Model Context Protocol 端點。同一沙盒中的命令列工具與建置系統整合仍會交換權杖以取得連線的 CI 存取權。

## WebMCP

在支援 [WebMCP](https://webmachinelearning.github.io/webmcp) 的瀏覽器中，Tuist 的頁面會使用 `document.modelContext` 註冊工具，因此內建於瀏覽器的代理程式無需任何額外設定即可呼叫它們。這些呼叫會在 Tuist 伺服器上執行。

- **Website and documentation pages** 會註冊文件與原始碼工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 與 `read_tuist_file`）。它們不需要您登入。
- 當您登入時，**An account's dashboard pages** 會為該帳戶註冊 Tuist 的唯讀工具。每個頁面僅註冊與其顯示內容及專案建置系統相關的工具：Gradle 專案的建置頁面會取得 Gradle 建置工具，其測試頁面會取得測試與涵蓋率工具，執行器頁面會取得執行器工具，沙盒頁面會取得沙盒工具。每個頁面也會取得文件工具 `list_projects` 與 `get_project`。這些工具以已登入使用者的身分執行，因此它們只能存取您在儀表板中可讀取的資料，且僅限於您正在檢視的帳戶。當您移至另一個頁面或帳戶時，工具會替換為該頁面的工具。

建立、變更或刪除資料的工具無法透過 WebMCP 使用，因為瀏覽器代理程式會在您未新增工具的情況下接收它們，並讀取建置與測試產生的內容。請將 MCP 用戶端連接至 `/mcp` 端點以使用這些工具。

若組織強制實施單一登入，請使用其提供者登入儀表板以使用其工具。

## 建置系統整合使用兩種憑證

用於 Model Context Protocol 工具的憑證不會驗證 Gradle 外掛程式或 Bazel 的遠端服務。在代理程式編輯或驗證 Gradle 或 Bazel 整合之前，它應執行：

```bash
tuist auth whoami --url https://tuist.dev
```

若該命令未通過驗證，代理程式必須停止並要求使用者執行：

```bash
tuist auth login --url https://tuist.dev
```

對於本機或自託管部署，請替換兩個命令與 `tuist.toml` 中的 URL。在所有地方保持主機名稱拼寫一致。例如，`localhost` 與 `127.0.0.1` 使用 separate 儲存的憑證。


## 功能

### 工具

以下工具可透過 Tuist Model Context Protocol 伺服器使用：

每個工具都會發布人類可讀的描述，以及明確的輸入與輸出結構定義。成功的呼叫會傳回符合所宣告輸出結構定義的結構化內容，並將相同結果序列化為文字，供尚未使用結構化內容的用戶端使用。

接受單一記錄識別符（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）的工具，也接受該記錄的 Tuist 儀表板 URL。請直接從瀏覽器貼上 URL，而非從中提取識別符。

`get_xcode_build`、`get_test_run`、`get_gradle_build` 與 `get_project` 可以包含 `side_quests`：記錄顯示專案未使用但會有幫助的 Tuist 功能。每個功能都有一個 `id`、一個說明其依據證據的 `tip`，以及一個 `docs` 連結。系統會要求代理程式先完成使用者的請求，提及適用的支線任務，並僅在使用者同意時才執行其中一項。這些資訊僅會回傳給專案帳戶的成員，無論他們是使用使用者工作階段、MCP 權杖或代理程式身分進行連線：

| ID | 工具 | 建議時機 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | 使用 Xcode 26 或更新版本執行的已處理乾淨建置，未執行任何可快取的編譯任務。 |
| `gradle_build_cache` | `get_gradle_build` | 建置執行了可快取的任務，但 Gradle 的建置快取未為其中任何任務計算金鑰，表示建置快取已關閉。 |
| `flaky_test_quarantine` | `get_test_run` | 一次執行包含不穩定測試，且專案中沒有啟用的自動化機制將它們靜音或跳過。不建議用於 Once 專案。 |
| `test_sharding` | `get_test_run` | 在 Tuist 支援分片的建置系統中，一次未分片的 CI 執行耗時 10 分鐘或更久。提示會說明選擇性測試已跳過多少個測試（若有）。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | 一次 CI 執行使用了 GitHub Actions、Bitrise、GitLab CI 或 Buildkite 機器，且該帳戶從未在 Tuist Runners 上執行過作業。僅適用於 tuist.dev。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | 一次 GitHub Actions 執行屬於未與其 GitHub 儲存庫連結的專案。 |
| `other_build_systems` | `get_project` | 該帳戶並未在所有支援的建置系統中使用 Tuist。提示會列出識別其他系統的檔案，以便代理程式檢查儲存庫。 |

#### 文件與社群搜尋

此唯讀工具透過驅動文件網站的相同搜尋引擎，搜尋 Tuist 的文件、[應用程式介面](https://en.wikipedia.org/wiki/API)參考、GitHub 發行版、社群論壇與 GitHub 問題。發行結果包含產品、版本、發布日期與預釋狀態。預設搜尋穩定發行版，並可使用 `include_prereleases` 包含預釋版。此工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜尋公開的 Tuist 文件、應用程式介面參考、GitHub 發行版、社群討論與 GitHub 問題。可選擇限制為單一 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 回饋

當 Tuist 工具或提示未按預期運作時（例如結果令人困惑、發生錯誤、資料缺失或缺少功能），代理程式可以向 Tuist 團隊回報。系統會要求代理程式建議一份回報，並僅在您同意後傳送。每份回報都會開啟與 Tuist 支援的對話，他們可能會透過電子郵件回覆您。回報內容包含代理程式的預期、實際發生的情況、選填建議、您的 Tuist 使用者 ID、帳號與電子郵件，以及您所屬的組織。代理程式也可以指名問題發生的帳戶與專案，讓團隊知道要跟進哪個組織；僅接受您所屬的帳戶。只有以 Tuist 使用者身分登入的代理程式才能傳送回報，且每位使用者每小時最多可開啟 10 份回報。此工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `report_feedback` | 回報 Tuist 工具或提示的問題。可選填指名 `tool_name`、問題發生的 `account_handle` 與 `project_handle`，並新增 `suggestion`。 | `category`, `expected`, `actual` |

#### 原始碼佐證的答案

這些唯讀工具讓代理程式使用與託管伺服器一同部署的確切公開 Tuist 原始碼修訂版本，作為依賴目前行為之答案的事實依據。它們僅在 `https://tuist.dev/mcp` 可用。

相容的用戶端在初始化期間會收到工具原始碼修訂版本的事實描述、連結與結果限制，以及內嵌 OAuth 驗證資訊。這些描述不會規定答案風格或驗證工作流程。使用者可以直接提問，無需先叫用 `ask_tuist` 提示；該提示仍可供明確的原始碼佐證工作流程使用。

每項作業對並行、持續時間、遍歷、讀取位元組數與回應大小都有固定限制。搜尋與清單結果包含 `truncated` 與 `truncation_reason` 欄位。當結果被截斷時，請縮小路徑、檔案模式或搜尋詞彙，而非將結果視為完整。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 透過搜尋原始碼檔案，回答關於目前行為、預設值、設定、功能開關、錯誤處理或未記錄細節的問題。結果包含周邊行數、綁定修訂版本的原始碼連結，以及掃描統計資料。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，探索原始碼子系統或鄰近測試。清單具有有限的深度與結果數量。 | 無 |
| `read_tuist_file` | 在找到相關路徑後，檢查實作檔案、呼叫位置或測試中的特定行範圍。截斷的回應會提供 `next_start_line` 以便繼續。 | `path` |

#### 專案

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出已驗證使用者可用的個人與組織帳戶帳號，包括每個帳戶是否能建立專案。 | 無 |
| `get_organization` | 取得組織的成員目錄。待處理的邀請需要與儀表板相同的管理員權限；永遠不會傳回邀請接受權杖。 | `account_handle` |
| `create_organization` | 為已驗證使用者建立 Tuist 組織。 | `handle` |
| `create_project` | 在已驗證使用者可存取的帳戶下建立 Tuist 專案。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有的 Tuist 使用者新增至組織，或更新現有成員的角色。接受 `user`（預設）、`admin` 或 `viewer`，其中檢視者可以讀取儀表板與執行紀錄，但無法進行任何變更。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有的 Tuist 使用者。Tuist 會傳送一封有效期為 14 天的接受連結郵件；當伺服器無法傳送郵件時，`email_sent` 為 `false`，必須從儀表板複製該連結。接受 `user`（預設）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其連結無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出已驗證使用者可存取的所有專案。 | 無 |
| `get_project` | 取得專案的設定與連接的儲存庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將專案連結至帳戶的 GitHub App 安裝可存取的 GitHub 儲存庫。專案會採用儲存庫的預設分支。需要專案管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除專案與其 GitHub 儲存庫的連結。需要專案管理員權限。 | `account_handle`, `project_handle` |

#### 帳戶權杖

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳戶權杖中繼資料，而不揭露權杖值。 | `account_handle` |
| `get_account_token` | 取得帳戶權杖中繼資料，而不揭露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出專案權杖中繼資料，而不揭露權杖值。 | `account_handle`, `project_handle` |

#### 通知規則

這些工具管理已驗證使用者自己的通知規則：當事件（例如新的預覽）發生在規則所屬的專案中（若未列出任何專案，則為你可收到通知的任何專案），且符合其條件時，便會執行其動作，例如向你的 Tuist 應用程式裝置發送推播通知。若沒有規則，你將不會收到任何通知。它們需要使用者驗證，僅對你自己的規則生效，且只接受你所屬帳戶的專案。它們不提供給儀表板頁面，因為規則涵蓋你所有的帳戶。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_notification_events` | 列出規則可訂閱的事件類型，每個類型都附有用於其條件的 JSON Schema。 | 無 |
| `list_notification_condition_options` | 建議專案中事件的條件值，例如其近期預覽的軌道與分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出你的規則。 | 無 |
| `create_notification_rule` | 根據事件、可選的專案與條件，以及至少一個動作來建立規則。 | `event`, `actions` |
| `update_notification_rule` | 變更規則的啟用狀態、專案、條件或動作。 | `rule_id` |
| `delete_notification_rule` | 刪除規則。 | `rule_id` |

#### 持續整合執行器

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳戶的持續整合執行器作業。 | `account_handle` |
| `get_runner_job` | 取得持續整合執行器作業，包括其機器是否記憶體不足、停止原因以及需要變更的內容。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出持續整合執行器作業所記錄的步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出持續整合執行器作業所記錄的機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續整合執行器作業最多 500 行擷取的日誌。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳戶的持續整合工作流程匯總。 | `account_handle` |
| `list_runner_profiles` | 列出帳戶的持續整合執行器設定檔，並包含每個設定檔的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出執行器設定檔可使用的機器規格與 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 建立執行器設定檔，需指定平台、機器規格，以及在 macOS 上指定 Xcode 版本。可選擇設定哪些分支會儲存其快取磁碟區。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 變更執行器設定檔的機器規格、Xcode 版本，或哪些分支會儲存其自訂快取磁碟區的變更。未指定的欄位將保留原值。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 經使用者確認後刪除執行器設定檔。預設設定檔無法刪除。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

執行器磁碟區工具公開與磁碟區儀表板相同的資料。讀取工具需要執行器存取權限；清除則需要帳戶管理權限或 `account:runners:write` 範圍，以及使用者確認。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 依名稱與儲存庫篩選，並對磁碟區進行排序與分頁。 | `account_handle` |
| `get_runner_volume` | 儲存庫、平台、容量、已用空間與最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁顯示作業與工作流程參考、快取狀態、命中結果與掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作業掛載的磁碟區。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 儲存序列、作業執行次數、命中率與趨勢。可選 `volume_id`、`start` 與 `end`（ISO 8601）；預設為七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 刪除磁碟區及其儲存的內容。執行中的作業會保留其私人副本，但無法儲存；後續使用相同金鑰的作業將從空白狀態開始。 | `account_handle`, `volume_id` |

列表接受 `page` 與 `page_size`（最多 100）。磁碟區清單也接受 `name` 與 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）與 `sort_order`（`asc`、`desc`）。未知的測量值與命中結果保持為 `null`。快取狀態描述磁碟區變更是否已儲存，而非作業成功與否。

#### 沙盒

沙盒工具公開與沙盒儀表板相同的資料與動作，並具有與 [API](https://tuist.dev/api/docs) 相同的存取權限：帳戶成員可以使用帳戶中每個沙盒的每項工具。唯讀檢視者無法使用它們。帳戶需啟用沙盒功能。儀表板的沙盒頁面會註冊唯讀工具。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_sandboxes` | 分頁顯示沙盒，包含其狀態、規格與時間戳記。可選 `search`（沙盒、Amp Orb 或 Anthropic 工作階段 ID 中的文字）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）與 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的狀態、規格、節點、封存與時間戳記。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小時數、建立的沙盒數量、工作階段、設定與啟動持續時間，以及相對於帳戶限制的 vCPU、記憶體與磁碟峰值，並包含趨勢。可選 `start` 與 `end`（ISO 8601）；預設為 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 啟動一個空白沙盒，並在運作後回傳。可選 `platform`（`linux` 或 `darwin`）、`xcode_version`（macOS 沙盒的確切 Xcode 版本，來自工具描述所列的版本；暗示 `darwin`）、`template`、`vcpus` 搭配 `memory_mb`（Linux：2x4096、4x8192 或 8x16384，預設 2x4096；macOS：8x8192、8x16384 或 8x24576，預設 8x8192）與 `workspace_gb`。其描述指示代理程式在 Mac 上使用 `mise install` 安裝儲存庫中固定的 Tuist，隨後會自行 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">使用帳戶的快取</.localized_link>。 | `account_handle` |
| `pause_sandbox` | 將運作中的沙盒快照至其節點的磁碟。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢復已暫停或封存的沙盒。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 將已暫停沙盒的磁碟排隊移至物件儲存。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 經使用者確認後刪除沙盒及其磁碟。 | `account_handle`, `sandbox_id` |

#### Amp 工作區

這些工具管理 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 工作區連線</.localized_link>，讓 Orbs 無需權杖即可登入 Tuist。它們使用與儀表板整合頁面相同的管理員專用權限。Orb 中的代理程式可以從 `$AMP_WORKSPACE_ID` 與 `$AMP_PROJECT_ID` 讀取其自身的 ID。連線允許的每個 Orb 都能取得帳戶中所有專案的 CI 存取權，因此代理程式應在連線前與使用者確認。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 列出帳戶已連線的 Amp 工作區，以及每個工作區限制的專案（若有）。 | `account_handle` |
| `connect_amp_workspace` | 連線 Amp 工作區。可選 `project_id` 將登入限制為單一 Amp 專案的 Orbs。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 中斷工作區連線。其 Orbs 已擁有的工作階段仍有效，直到過期為止。 | `account_handle`, `connection_id` |

#### Claude 環境

這些工具連線 Claude Managed Agents 自託管環境，使其工作階段在 Tuist 沙盒中執行，如同「設定」→「整合」→「Claude」。它們需要帳戶管理權限並啟用沙盒。代理程式可以使用 Anthropic 的 API 建立環境，但只有 Claude Console 會產生其環境金鑰，因此代理程式會向使用者索取該金鑰。Tuist 使用 Anthropic API 金鑰或工作負載身分聯合來啟動工作階段，並在儲存前使用该憑證抓取環境。Anthropic 端的設定使用使用者自己的 Anthropic 憑證；Tuist 從未接收它們。金鑰會透過用戶端與模型傳遞，因此僅在明確提供時才使用。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_claude_environments` | 列出已連線的環境及其使用的憑證，以及聯合規則應信任的發行者 URL 與主體前綴。 | `account_handle` |
| `connect_claude_environment` | 使用 `api_key`，或使用 `organization_id`、`workspace_id`、`service_account_id` 與 `federation_rule_id` 連線環境。可選的 `platform`、`vcpus` 與 `memory_mb` 用於設定沙盒規格。 | `account_handle`, `environment_id`, `environment_key` |

#### 組織 AI

這些工具管理組織伺服器端 AI 工作所使用的模型，如同「設定」→「AI」，並遵循相同規則：僅限組織管理員，且僅適用於已啟用 AI 設定的組織。每個工作（例如 `pulse_grouping` 或 `pulse_explanation`）會在其擁有工作路由時使用該路由，否則使用預設模型；若兩者皆無，則不會傳送任何請求。每個工具都會回傳完整設定，包括每個工作的目前模型，以及該模型是來自其路由、預設值，或無。新增或編輯提供者需要 API 金鑰，因此需透過儀表板或 REST API（`/api/accounts/{handle}/ai`）進行，而非透過這些工具。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | 讀取提供者（不含金鑰）、模型、預設模型、工作路由以及每個工作的目前模型。 | `account_handle` |
| `save_organization_ai_model` | 新增模型（`name`、`provider_id`、`upstream_model_id`），或依 `id` 更新模型。 | `account_handle` |
| `remove_organization_ai_model` | 移除模型及其工作路由。 | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | 選擇預設模型，或以 null 清除。 | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | 將 `task` 路由至已設定的 `model_id`，或依 `id` 更新路由。一個工作最多擁有一條路由。 | `account_handle` |
| `remove_organization_ai_task_route` | 移除路由，使工作再次使用預設模型。 | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | 移除提供者及其金鑰、模型與相關路由；解除已連結的 Claude 組織。 | `account_handle`, `provider_id` |

#### Webhook

Webhook 工具使用與儀表板相同的管理員專用權限。遞送嘗試包含為端點記錄的請求與回應資料，但絕不包含端點簽署密鑰。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳戶的 Webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 取得 Webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點的遞送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 取得遞送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 建置

針對 Xcode、Gradle、Bazel、Mix 與 Cargo 的建置詳細資訊工具會揭露現有的 `custom_metadata: {tags, values}` 結構，並在回報時包含基礎設施觀察結果。值維持為字串，且不熟悉的鍵會被保留。例如，`tuist.cpu.available_processors` 描述執行階段可用的邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆積限制，並非主機記憶體。這些是不可信的用戶端觀察結果，而非經過驗證的執行器身分。未提供的觀察結果仍保持缺失；匯入的日誌與較舊的用戶端可能沒有基礎設施中繼資料。一次性中繼資料有待協調的用戶端/協定更新。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出專案的 Xcode 建置執行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 取得特定 Xcode 建置執行的詳細資訊，包括保存原始 `.xcactivitylog` 的封存檔之臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 建置執行的建置目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 建置執行的已編譯檔案。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄的建置步驟及其時間與結果，不含日誌文字。 | `build_run_id` |
| `get_xcode_build_step` | 取得單一記錄的建置步驟，包括其日誌與截斷旗標。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定建置執行的建置問題（警告與錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 建置執行的可快取工作（快取命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 建置執行的 [內容定址儲存](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 預設回傳每頁 20 個步驟（透過 `page_size` 最多 100 個），並提供 `page` 與 `pagination_metadata` 以便導覽。使用 `search` 比對標題、專案或目標，或篩選確切的 `project`、`target`、`category`（例如 `swiftCompilation`）與 `status`（`success` 或 `failure`）。依 `duration_ms` 排序以最慢者優先（預設），或依 `start_ms` 排序以獲得時間順序。步驟 ID 用於打破平手，並以十進位字串形式回傳，以保留完整的 64 位元精確度。ID 限定於單一建置，不應跨建置比對。

可選的 `start_ms` 與 `end_ms` 可選取與從建置開始起算之毫秒時間範圍重疊的步驟；結束時間為exclusive。兩種工具皆接受建置 UUID 或儀表板 URL 作為 `build_run_id`。將回傳的步驟 `id` 原樣傳遞為 `step_id` 以擷取其日誌。日誌每步驟最多保留 64 KiB，並以 `log_truncated` 指示省略的輸出。

處理 Xcode 建置時預設會收集步驟。記錄的步驟資料保留 90 天。列表回應包含 `availability`：當存在記錄的步驟時為 `available`，即使篩選條件未比對到任何項目；當建置仍在處理且尚無步驟時為 `processing`；或當步驟未記錄或已過期時為 `unavailable`。

相同的操作可透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 與 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上使用，並支援相同的篩選條件與分頁。兩者皆需要對建置所屬專案具有讀取權限。

#### Gradle 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 回傳完整的認證、專案設定、Gradle 外掛程式、快取政策，以及雙建置驗證工作流程。代理程式在編輯現有的 Android 或 Gradle 專案前應呼叫此工具。 | 無 |
| `list_gradle_builds` | 列出專案的 Gradle 建置執行，包含自訂中繼資料。使用可選的 `tag` 參數依自訂標籤篩選。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 取得建置中繼資料、工作/快取計數，以及 `failures`：每個失敗工作與設定步驟的失敗訊息。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出工作結果、複合建置身分、可快取性、增量狀態與失敗訊息。 | `build_run_id` |
| `list_gradle_build_steps` | 列出計時工作、設定與轉換，支援搜尋、中繼資料與重疊時間篩選。 | `build_run_id` |
| `get_gradle_build_step` | 透過不透明 ID 檢查記錄的步驟中繼資料；失敗工作或設定步驟的 `log` 即為其失敗訊息。 | `build_run_id`, `step_id` |

Gradle 與 Bazel 步驟列表預設回傳 20 筆結果（最多 100 筆），支援 `search`、確切的 `project`、`target`、`category` 與 `status`、重疊的 `start_ms` / `end_ms` 篩選（結束時間為 exclusive），以及依 `duration_ms` 或 `start_ms` 排序。請原樣傳遞回傳的 ID；它們限定於其所属建置。列表會揭露 `time_origin` 與 `coverage`。較舊的 Gradle 報告使用 `first_recorded_timestamp`，因為未上傳建置開始時間。Bazel 設定檔透過 `trace_profile` 覆蓋範圍與作為時間起點的 `profile_start` 揭露所有記錄的區間。較舊的建置會退回至保留的 BEP 摘要。來源記錄在 90 天後過期。Bazel 詳細資訊在發布時包含經淨化的動作日誌。失敗工作或設定步驟的 Gradle 詳細資訊包含 Tuist Gradle 外掛程式以 `log` 回報的失敗訊息：例外訊息及其原因鏈，如同 Gradle 主控台所印出的內容，不含堆疊追蹤或工作輸出，專案內的路徑已轉為相對路徑，憑證與其他本機路徑已遮蔽，每步驟最多 16 KiB，每建置最多 32 個失敗步驟。其他 Gradle 步驟、由較舊外掛版本回報的建置，以及不含憑證的報告，其 `log` 為 null。設定步驟在失敗時回報 `failure`，否則回報 `unknown`。`compare_builds` 提示使用此覆蓋範圍來區分完整的 Bazel 追蹤與保留的摘要，並引導代理程式先查看步驟詳細資訊以取得動作結果與日誌，再檢查更廣泛的叫用輸出。

單一步驟工具 `get_gradle_build_step` 與 `get_bazel_build_step` 會依 ID 擷取步驟，且不接受時間篩選；請使用對應的列表工具依時間範圍篩選步驟。

若在列出步驟與擷取步驟之間收到完整設定檔，則從保留摘要回傳的 Bazel 步驟 ID 仍可讀取。若索引設定檔的步驟資料已過期，則回報為不可用。Gradle 步驟列表包含持續時間為零的快取與略過操作。

#### Bazel 叫用

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 回傳認證、專案設定、Bazel 設定與驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成的 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 叫用，依最新順序排列，包含建置指標、有界執行時間軸、關鍵路徑診斷，以及專案相關的遠端快取總計。可依 `status`、`git_branch`、`git_commit_sha`、`is_ci` 與 `command` 篩選。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 取得單一已完成的 Bazel 叫用，包含建置指標、有界執行時間軸、關鍵路徑診斷，以及相關的遠端快取總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄的 Bazel 設定檔區間，支援篩選與明確的覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄的 Bazel 步驟及其發布的動作結果與淨化日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 依執行順序列出為 Bazel 叫用擷取的淨化日誌：Bazel 進度輸出的有界尾部與 `test.log` 產物。可選的 `stream`（`stdout` 或 `stderr`）、`source`（`progress` 或 `test_log`）、`target_label` 與 `errors` 篩選可縮小結果範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 取得為 Bazel 叫用擷取的單一淨化日誌區塊。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 遠端快取觀察結果，包含其操作、端點與觀察時間，可選擇性地縮小到特定叫用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 取得單一原始的 Bazel 遠端快取觀察結果。 | `account_handle`, `project_handle`, `cache_event_id` |

#### 遠端執行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_remote_execution_activity` | 列出專案目前執行中的 Bazel 叫用，以及正在執行與排隊中的遠端動作，包含每個動作的叫用、助記符、目標、動作摘要、機器大小，以及進入該狀態的時間。執行閘道在其預先準備的 VM 上執行的動作，在完成前不會列入清單。 | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | 取得專案在 `[from, to)` 期間的遠端執行與測量的執行時間，包含總計、依機器大小、依分派模式，以及依小時、天或月劃分。期間預設為最近 30 天，最多涵蓋 366 天。 | `account_handle`, `project_handle` |

`list_bazel_invocations` 篩選為精確比對，且在同一秒內完成的叫用會依叫用 ID 排序。若要找出分支上最新的失敗叫用，請使用 `status: "failure"`、`git_branch` 與 `page_size: 1` 呼叫。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` 接受相同的篩選條件。

在 `list_bazel_build_steps` 上設定 `remote_execution: true`，僅回傳來自索引設定檔且安全關聯伺服器階段計時的動作。列表與詳細回應會揭露可為 null 的 `remote_queue_ms`、`remote_input_fetch_ms`、`remote_execution_ms` 與 `remote_output_upload_ms`。這些值為記錄階段的總和，包含動作內的重試；缺失或 null 值表示不可用，而非零。這些是設定檔觀察結果，並非可計費的使用量或全新執行的證明，因為快取的伺服器結果可能攜帶執行中繼資料。用戶端上傳已排除。較舊或模糊的設定檔即使發生遠端工作，也可能不回傳相符的動作。步驟 REST 端點接受相同的 `remote_execution=true` 篩選。儀表板的「Remote execution」分頁使用相同的查詢與 90 天保留期。

測試日誌攜帶其所來源測試結果的 `target_label` 與嘗試 `status`，因此 `target_label: "//foo:bar_test"` 僅回傳該目標的測試日誌。`errors: true` 回傳失敗嘗試的測試日誌，以及包含 Bazel 回報器以 `ERROR:`、`FAIL:` 或 `TIMEOUT:` 開頭之行的 stderr 進度區塊。進度輸出未歸因於目標，且在記錄歸因前寫入的日誌欄位為空。失敗動作及其輸出可透過 `list_bazel_build_steps` 依目標取得，而每個測試案例的失敗則可從測試執行工具取得。

#### Cargo 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出專案的 Cargo 建置，依最新順序排列。可依 `git_branch`、`status`、`is_ci` 或 `command` 篩選。Cargo 測試執行結果可透過測試工具取得，而非此建置清單。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 取得建置中繼資料、彙總快取計數器，以及最多 500 筆帶有診斷資訊的已記錄編譯工作。`compilations_truncated` 表示已省略的工作；診斷資訊僅涵蓋回傳的工作。 | `account_handle`, `project_handle`, `build_id` |

在 `get_cargo_build` 上設定 `include_cache_inspection: true` 以取得經驗證的工作決策與 CAS 操作，上限為 4 MB。預設情況下，以及在記錄缺失或無效時，`cache_inspection` 為 null。請尊重其部分擷取的 `truncated` 旗標；傳輸不會確立每個工作命中的本機/遠端來源。HTTP 詳細資訊端點接受相同的查詢參數。

#### Mix 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出專案的 Mix (Elixir) 編譯建置，依最新順序排列，包含自訂中繼資料。可依 `git_branch`、`status`、`is_ci` 或 `mix_env` 篩選。 | `account_handle`, `project_handle` |
| `get_mix_build` | 取得建置中繼資料、診斷計數，以及相依性快取摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 建置追蹤

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_build_trace` | 取得 Xcode、Gradle、Bazel 或 Mix 建置時間軸的下載連結，格式為可在 [Perfetto](https://ui.perfetto.dev) 中開啟的追蹤檔案。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 是建置執行 ID（Bazel 的叫用 ID）或建置的儀表板 URL。回傳的 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 檔案。任何持有該連結的人均可在 `expires_at`（呼叫後一小時）之前，無需其他憑證即可下載該建置的追蹤。代理程式可以使用 `curl` 下載，交給您在 Perfetto 中開啟，或使用 Perfetto 的 `trace_processor` 進行查詢。該追蹤包含依平行處理原則打包到軌道的已記錄步驟、涵蓋整個建置的軌道，以及在建置記錄機器指標時的 CPU 與記憶體計數器。它包含與上述步驟工具相同的資料，但不含日誌。儀表板從每個建置的「Timeline」分頁提供相同的檔案。

#### Once 執行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出專案的 Once 執行，依最新順序排列。可依 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 篩選。尚未完成的執行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 取得執行及其動作總計、快取摘要，若是測試執行則包含測試總計。 | `account_handle`, `project_handle`, `run_id` |

Cargo 建置、Mix 建置與 Once 執行 ID 在專案內具有唯一性。相同的讀取操作可透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 與 `.../once/runs` 取得，每個端點皆提供針對單一 ID 的詳細資訊端點。

#### 工作、動作、模組與檔案

這些專案範圍的工具會檢查跨執行的持久化建置身分識別。請從 `list_build_entities` 開始，然後將回傳的穩定 `id` 與相同的 `kind` 傳遞給 `get_build_entity` 或 `list_build_entity_history`，並同時提供 `account_handle` 與 `project_handle`。不需要建置或叫用識別碼。

| 工具 | 描述 | 必要參數 |
| --- | --- | --- |
| `list_build_entities` | 列出在專案建置中看到的某一類型的任務、模組、動作或檔案。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 取得一個建置實體，包含其原生身分識別與所選期間的分析資料。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個建置實體的已記錄執行、編譯或快取事件，依最新順序排列。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史清單 |
| --- | --- | --- |
| `bazel_actions` | Bazel 動作 | BEP 回報的動作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模組 | 編譯與模組快取事件 |
| `once_actions` | Once 動作 | 執行 |
| `mix_files` | Mix 編譯檔案 | 編譯 |
| `mix_modules` | Mix 編譯模組 | 編譯 |
| `cargo_crates` | Cargo crate | 已記錄的 rustc 叫用 |

這些工具正逐步推出，僅回傳已啟用工具的專案資料；其他專案則回傳錯誤而非空結果。某一類型僅適用於使用其建置工具鏈的專案。工具接受有界的 `start_at`/`end_at` 篩選器、`environment`（`any`、`ci` 或 `local`）以及精確的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支援不透明的 `after`/`before` 遊標。未知的計時或快取觀察結果仍為不可用，不會變成零或遺漏。歷史記錄會參考已記錄的父項與原生執行，以便使用現有的執行工具進行深入分析。

`get_build_entity` 指標包含 `duration_samples`，即具有記錄計時的觀察次數：真正的零持續時間會計入，缺少計時則不計入。此計數可能低於觀察次數；不可用的持續時間統計資料仍為 null。

Xcode 模組持續時間來自建置日誌中測量的目標編譯。模組快取解析與沒有編譯工作的目標不會貢獻持續時間樣本。編譯觀察參考 Xcode 建置；快取事件參考生成或快取命令。

Bazel 動作由目標標籤、助記符與設定的主要輸出識別，在不依賴輸入相依快取摘要的情況下，保持不同動作與設定的區別。歷史記錄 BEP 回報的執行，而非快取查詢或追蹤設定檔階段。完整執行覆蓋率需要 `--build_event_publish_all_actions`；構件交付為尽力而為，因此缺少的觀察結果並非沒有執行工作的證據。較舊的 Kura 負載若缺乏穩定身分識別或執行開始時間，仍會被接受但不建立索引。缺少的結束時間測量仍為不可用，真正的零持續時間會計入。

Mix 模組持續時間測量的是包含檔案的編譯，而非獨立測量的模組工作。當用戶端回報目標對應時，Once 動作會使用宣告的目標/能力/索引槽；僅靠診斷標籤並非穩定的身分識別。現有用戶端與執行層級工具仍維持原有支援。

Cargo crate 依精確記錄的 crate 根目錄、名稱與種類分組。檢出路徑變更可能會分割歷史記錄，且不會區分建置設定檔、功能與目標三元組。歷史記錄測量 rustc 叫用，而非每個檔案的工作或快取命中；缺少的工作不會確立移除或完整的工作區清單。

分析讀取具有有限的記憶體與執行時間。若查詢超過這些限制，工具會回傳錯誤而非捏造空結果。

新的觀察結果會在部署後建立索引；此功能不會回填現有的執行遙測資料。在 <.localized_link href="/guides/server/data-retention">資料保留政策</.localized_link> 下，身分識別中繼資料的保存期限長於個別觀察結果。

#### 測試

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出專案的測試執行，每個執行皆包含其 `selective_testing_strategy`。可依 `selective_testing`（`coverage`，包含基於涵蓋率選擇的回退機制，或 `module_hash`）進行篩選。`query` 欄位為 `git_branch`、`scheme`、`status` 與 `selective_testing`：`field:"value"` 為精確匹配，`field~"value"` 為不分大小寫的子字串匹配（不適用於 `selective_testing`），前導 `-` 則否定任一運算子。例如，`-git_branch~"gh-readonly-queue"` 會排除合併佇列分支。以空白分隔的查詢篩選器與明確引數會以 AND 語意組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 取得測試執行的詳細指標，包括其自身的程式碼涵蓋率（`coverage`：是否測量了任何涵蓋率、行數與數值，以及是否為部分涵蓋或從髒檢出執行）、選擇性測試摘要（`selective_testing`：策略、基準提交，以及請求、選取、跳過與預估的測試計數，這些是用來計算測試選擇有效性的數據），以及其結果套件（`.xcresult`）與工作階段封存檔的暫時下載 URL。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行的測試模組執行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行的測試套件執行，可選擇依模組篩選。 | `test_run_id` |
| `list_test_cases` | 列出專案的測試案例（支援如 `flaky` 等篩選器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 取得測試案例的詳細指標，包括可靠度比率、不穩定比率與執行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例執行，可選擇依測試案例或測試執行篩選。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 取得特定測試案例執行的失敗詳細資訊與重複次數，以及當其執行的涵蓋率基礎選擇保留了該測試時的原因（`selective_testing`：決策、原因、匹配的變更檔案與分片）。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例執行的附件。每個附件皆包含一個暫時下載 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例的狀態變更，例如將其靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例的狀態或不穩定分類。變更可以將事件派送至設定的 Webhook 端點，包括外部服務。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試執行的選擇性測試目標結果。 | `test_run_id` |
| `list_selective_testing_tests` | 列出測試執行的涵蓋率基礎選擇所決定、選取與跳過的測試，包含每個決策的原因、選取它的變更檔案、其分片以及在執行中的結果。可依 `decision`、`reason` 或 `search` 篩選。 | `test_run_id` |
| `list_selective_testing_changed_files` | 列出自測試執行的涵蓋率基礎選擇基準以來變更的檔案，包含每個檔案選取的測試數量，以及它是否為追蹤檔案（其變更會導致選擇回退）。 | `test_run_id` |
| `get_coverage` | 取得專案在其提交或分支最新完整提交時的程式碼涵蓋率與目標。若未提供 `git_commit_sha` 或 `branch`，則讀取預設分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出在提交或分支最新完整提交時，由程式碼涵蓋率測量的檔案及其行涵蓋率。支援 `search`、排序與分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 取得在提交或分支最新完整提交時，檔案的程式碼涵蓋率與其函式。設定 `include_lines` 以取得每行的執行計數。 | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | 列出具有程式碼涵蓋率的分支，預設分支排在前面。 | `account_handle`, `project_handle` |
| `list_coverage_commits` | 列出分支的提交及其涵蓋率狀態（`complete`、`incomplete`、`in_progress`、`not_measured`）、數值，以及與前一個完整提交的差異，依最新優先排序。使用游標分頁。 | `account_handle`, `project_handle` |
| `list_coverage_runs` | 列出在提交或分支後方具有程式碼涵蓋率的測試執行，每個皆標記為 `full`、`partial` 或 `discarded`（髒检出）。使用游標分頁。 | `account_handle`, `project_handle` |
| `list_coverage_targets` | 列出提交的每個目標涵蓋率，接著列出其執行從二進位快取取得但未含涵蓋率計數器的目標（`measured: false`）。支援 `search`、排序與分頁。 | `account_handle`, `project_handle` |

程式碼涵蓋率工具僅提供給已啟用程式碼涵蓋率的帳號。

#### 套件

| 工具 | 說明 | 必要參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出專案的套件（應用程式二進位檔）。可選擇依 `git_branch` 和 `tags` 篩選（所有標籤必須完全相符）。 | `account_handle`, `project_handle` |
| `get_bundle` | 取得特定套件的詳細資訊，包括自訂標籤。 | `bundle_id` |
| `get_bundle_artifact_tree` | 取得套件的完整構件樹，以路徑排序的扁平清單呈現。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以區分建置變體或環境。標籤為區分大小寫的標籤，包含字母、數字、連字號或底線，最多 10 個標籤，每個標籤最多 50 個字元。列表與詳細結果包含 `custom_metadata.tags`。分頁計數與分支篩選器適用於帶標籤的結果；省略 `tags` 則保留未篩選的行為。無效的標籤篩選器會回傳錯誤，而非擴大查詢範圍。

#### 世代

| 工具 | 說明 | 必要參數 |
|------|-------------|---------------------|
| `list_generations` | 列出專案的世代執行。 | `account_handle`, `project_handle` |
| `get_generation` | 取得特定世代執行的詳細資訊。 | `generation_id` |

#### 快取執行

| 工具 | 說明 | 必要參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出專案的快取執行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 取得特定快取執行的詳細資訊。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出世代或快取執行的模組快取目標，顯示每個目標的快取命中/未命中狀態與診斷元件雜湊，包括額外的雜湊輸入。 | `run_id` |

#### 預覽

| 工具 | 說明 | 必要參數 |
|------|-------------|---------------------|
| `list_previews` | 列出專案的可共用應用程式預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 取得預覽及其建置的暫時下載 URL。 | `preview_id` |
| `get_latest_preview` | 找出正在運行的應用程式二進位檔的最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 說明 | 必要參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出專案的自動化警示。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 取得自動化警示。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警示的修訂歷史。動作憑證已遮蔽。 | `alert_id` |
| `list_project_notification_alerts` | 列出專案通知警示規則。需要與儀表板設定頁面相同的管理員權限。Webhook 位址已遮蔽。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期的用戶端可以呼叫 `events/list` 來探索事件及其負載結構：

| 事件 | 傳送時機 | 訂閱篩選器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從穩定變為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本機或持續整合的 Xcode、Gradle 或 Bazel 建置以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本機或持續整合測試執行以失敗結束，包括合併的分片執行或已放棄的執行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 執行者作業以失敗完成。 | `account_handle` |

若要訂閱，用戶端會呼叫 `events/subscribe`，並提供事件名稱、上述列於 `arguments` 的控制代碼，以及包含 `https://` 回呼 URL 與 `whsec_` 簽署金鑰的 `webhook` 傳遞方式。專案事件需要帳號成員資格及對應測試或建置資料的讀取權限；執行者作業事件需要帳號成員資格及執行者讀取權限。已聲明的 [`auth.md`](https://workos.com/auth-md) 存取權杖、已聲明的帳號權杖，以及瀏覽器授權授予均可建立訂閱；當相關憑證不再有效時，傳遞就會停止。每位使用者最多可保留 25 個有效訂閱。Tuist 會在儲存訂閱前向回呼傳送驗證挑戰。回呼必須回傳包含相同 `challenge` 值的物件。訂閱預設持續七天，可透過再次訂閱來更新，並在使用者的存取權或憑證被移除時停止傳遞。選用參數 `ttlMs` 的上限介於一小時至 30 天之間。Tuist 會重試逾時的回呼，並在至少連續三次逾時（橫跨五分鐘）後取消訂閱；請在恢復回呼後再次訂閱。

當事件發生時，Tuist 會將其資源識別碼與儀表板 URL 傳送至回呼。建置與測試執行失敗也會包含 `is_ci` 和 `git_branch`，因此用戶端可以忽略本機失敗或依分支篩選。建置事件包含 `build_system`；執行者作業事件同時包含 `workflow_job_id` 和 `workflow_run_id`。請求包含訂閱識別碼與 [Standard Webhooks](https://www.standardwebhooks.com/) 簽章標頭，以便用戶端驗證其來源。Tuist 會重試失敗的傳遞，因此用戶端應使用穩定的 `eventId` 來捨棄重複項目。負載省略測試名稱、日誌與失敗訊息；用戶端可以透過上述工具取得這些詳細資訊，並決定是否通知團隊或開始除錯。用戶端可以使用 `events/unsubscribe` 停止傳遞。

### 提示

| 提示 | 說明 |
|--------|-------------|
| `fix_flaky_test` | 引導你修復不穩定測試，方法包括分析失敗模式、找出根本原因，並套用針對性的修正。 |
| `compare_builds` | 引導你比較建置以識別效能衰退、快取變更與建置問題。針對 Xcode、Gradle、Bazel 和 Cargo 專案使用原生工具。Cargo 比較會保留部分編譯器涵蓋率，並將預估的編譯器工作與實際節省的時間區分開來。 |
| `compare_test_runs` | 引導你比較兩次測試執行以識別衰退、新失敗與不穩定測試。 |
| `compare_bundles` | 引導你比較兩個套件以識別構件樹中的大小變更。 |
| `compare_test_case` | 引導你比較測試案例在兩個分支或時間段之間的行為。 |
| `compare_generations` | 引導你比較兩次世代執行以識別效能衰退與模組快取變更。 |
| `compare_cache_runs` | 引導你比較兩次快取執行以識別快取效率變更與目標層級的衰退。 |
| `integrate_gradle_project` | 引導你將 Tuist 整合到現有的 Gradle 專案中。內容包括獨立的工具與 Gradle 驗證、帳號探索、專案建立、遠端快取政策、建置洞察，以及回讀驗證。 |
| `integrate_bazel_project` | 引導你建立或選擇 Bazel 專案、驗證命令列、設定遠端快取與建置洞察，並透過 Tuist 建置資料驗證整合結果。 |
| `integrate_xcode_project` | 引導你將 Tuist 整合到現有的 Xcode 專案中。支援 Xcode 快取、建置洞察、測試洞察與測試分片。 |
| `ask_tuist` | 使用公開材料作為脈絡，並以聚焦的實作與測試證據作為目前行為的事實依據，來回答 Tuist 相關問題。它需要一個 `question`，並引用修訂綁定的證據。 |

專案資料提示接受 `account_handle` 和 `project_handle`，將調查範圍限定於特定專案。比較提示也接受 `base` 和 `head` 引數，以指定要比較的兩個項目（依 ID、儀表板 URL 或分支名稱）。`ask_tuist` 接受 `question` 而非專案參數。`integrate_gradle_project` 也接受 `features`，這是要套用的 Gradle 整合清單（以逗號分隔）：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受選用的 `server_url`，適用於自託管或本機安裝。`integrate_xcode_project` 接受包含 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding` 的 `features`。

#### Gradle 整合提示功能

`integrate_gradle_project` 提示與 `get_gradle_integration_guide` 工具記錄了完整的設定工作流程。伺服器的初始化指示也會參考此工具，讓未列舉提示的代理程式也能發現它。

| 功能 | 代理程式設定的內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 的建置快取、設定 Tuist 遠端快取上傳政策，並建議僅從具有本機唯讀使用权的持續整合執行者進行上傳。 |
| `build_insights` | 套用 Tuist Gradle 外掛程式，並在需要時設定建置分析上傳行為。 |
| `test_insights` | 套用 Tuist Gradle 外掛程式，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 引導設定不穩定測試偵測、選用的 Gradle Test Retry 外掛程式用法，以及測試隔離設定。 |
| `test_sharding` | 新增持續整合工作流程，用於 `tuistPrepareTestShards`、分片矩陣產生，以及基於 `TUIST_SHARD_INDEX` 的測試執行。 |

當省略 `features` 時，提示會要求代理程式釐清使用者想要的整合項目，或在編輯 Gradle 專案之前從請求中推斷出最小的實用組合。

#### Xcode 整合提示功能

`integrate_xcode_project` 提示記錄了 Tuist 支援的每一種 Xcode 整合：

| 功能 | 代理程式設定的內容 |
|---------|---------------------------|
| `xcode_cache` | 設定 `tuist setup cache`、產生專案的快取設定、手動 Xcode 快取建置設定，以及僅限持續整合執行者使用的上傳政策。 |
| `build_insights` | 透過 `tuist setup insights` 設定 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 與選用的機器指標。 |
| `test_insights` | 設定 `tuist inspect test`、Scheme 測試後置動作，以及用於持續整合測試執行的結果套件產生。 |
| `test_sharding` | 新增 Xcode 或產生專案的分片規劃與分片執行工作流程，並使用 `TUIST_SHARD_INDEX`。 |

當省略 `features` 時，提示會要求代理程式釐清使用者想要的整合項目，或在編輯 Xcode 專案之前從請求中推斷出最小的實用組合。
