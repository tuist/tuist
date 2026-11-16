---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 MCP 端點，畀 AI 代理存取測試洞察同更多資訊。"
}
---
# 模型上下文協定

[模型上下文協定 (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 係一個開放標準，俾人工智能代理可以同外部服務同數據來源互動。佢令到好似 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等應用程式，以及好似 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等編輯器，可以同 Tuist 互相操作。

Tuist 喺 `https://tuist.dev/mcp` 提供伺服器端嘅模型上下文協定端點。將你嘅客戶端連接到此端點後，代理就可以存取你嘅 Tuist 項目數據，包括測試洞察、不穩定測試分析等等。大多數工具讀取嘅 Tuist 數據，係已驗證用戶已經可以喺儀表板看到嘅。每個工具都會標註佢係咪只讀、會唔會導致難以復原嘅變更（`destructiveHint`），以及會唔會存取 Tuist 以外嘅資源（`openWorldHint`）。會改變狀態嘅工具如下，每個都受用戶喺帳戶或項目上嘅權限限制：

- **組織同成員**：`create_organization`、`add_organization_member`（新增現有用戶或更改成員角色）、`invite_organization_member`（向任何地址發送邀請電郵）同 `cancel_organization_invitation`。
- **項目**：`create_project`、`start_project_logo_upload` 同 `complete_project_logo_upload`（更換標誌）、`connect_project_repository` 同 `disconnect_project_repository`（GitHub 儲存庫連結）。
- **測試**：`update_test_case`（靜音、跳過、重新啟用或將測試案例標記為不穩定；此變更可能會觸發帳戶嘅 webhook 端點）。
- **通知規則**：`create_notification_rule`、`update_notification_rule` 同 `delete_notification_rule`。
- **持續整合執行器**：`create_runner_profile`、`update_runner_profile`（縮小儲存快取卷宗嘅工作範圍會丟棄待處理嘅儲存）、`delete_runner_profile` 同 `delete_runner_volume`（刪除卷宗嘅已儲存內容）。
- **沙盒**：`create_sandbox`、`pause_sandbox`、`resume_sandbox`、`archive_sandbox` 同 `delete_sandbox`（刪除其磁碟）。
- **反饋**：`report_feedback`（向 Tuist 團隊發送關於工具或提示嘅報告；僅限 tuist.dev）。
- **代理整合**：`connect_amp_workspace`（賦予工作空間嘅 orbs CI 存取帳戶嘅權限）、`disconnect_amp_workspace` 同 `connect_claude_environment`（允許 Claude Managed Agents 環境喺 Tuist 沙盒中運行會話）。

`add_organization_member`、`cancel_organization_invitation`、`complete_project_logo_upload`、`disconnect_project_repository`、`update_test_case`、`update_notification_rule`、`delete_notification_rule`、`update_runner_profile`、`delete_runner_profile`、`delete_runner_volume`、`delete_sandbox` 同 `disconnect_amp_workspace` 標註 `destructiveHint: true`，因為佢哋會取代或移除現有狀態。`invite_organization_member`、`update_test_case`、`connect_claude_environment` 同 `report_feedback` 標註 `openWorldHint: true`，因為佢哋會發送電郵、通知外部 webhook 端點、呼叫 Anthropic 或向 Tuist 團隊發送報告。

個人 Claude 同 ChatGPT 訂閱只係喺儀表板嘅 AI 設定中連接，所以訂閱令牌同登入憑證永遠唔會經過模型上下文協定客戶端。帳戶設置工具需要用戶驗證。項目令牌或普通帳戶令牌無法使用呢啲工具。當用戶喺瀏覽器中授權客戶端或聲明 `auth.md` 註冊時，Tuist 只會喺模型上下文協定端點將該憑證與用戶關聯，以便設置工具可以完成請求嘅工作流程。

Tuist 實現咗 [2026-07-28 協定](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求係無狀態嘅：客戶端每次請求都會發送協定元數據，並且可以直接呼叫工具而無需初始化。`server/discover` 返回伺服器嘅身份、功能、支援版本同說明。冇會話識別符號或獨立事件流。使用 2025-06-18 或 2025-03-26 初始化流程嘅客戶端仍然受支援；佢哋亦都係喺冇伺服器會話嘅情況下運作。

## 模型上下文協定對比技能

模型上下文協定工具同 <.localized_link href="/guides/features/agentic-coding/skills">技能</.localized_link> 喺功能上可能有重疊。鑑於目前兩者之間嘅重疊，請為每個工作流程選擇一種方法並一致使用，而唔好喺同一流程中混合使用兩者。

對於支援插件安裝嘅客戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist 插件</.localized_link> 一併安裝兩者。

## 設定

喺你嘅客戶端中將 `https://tuist.dev/mcp` 添加為遠程模型上下文協定伺服器。伺服器嘅初始化說明同公開伺服器卡片描述咗帶有動態客戶端註冊嘅 OAuth 2.0 同標準瀏覽器授權流程，無需代理獲取或跟隨外部驗證文件。呢啲伺服器範圍嘅說明保持工作流程指引嘅通用性：工具驗證唔會驗證本地命令行工具或構建系統整合，代理應該通過相關嘅 Tuist 工具驗證請求嘅變更。構建系統特定嘅設置同驗證檢查記錄喺整合指南同提示中。Tuist 仍然分別宣傳 [Open Authorization](https://oauth.net/2/) 發現元數據同當前位於 `https://tuist.dev/auth.md` 嘅 [auth.md 協定](https://workos.com/auth-md)。

如果你嘅其中一個組織強制執行單一登入，喺瀏覽器中授權客戶端需要通過該組織登入嘅會話，必要時 Tuist 會先將你轉發到提供者。請參閱 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">單一登入</.localized_link>。

該端點接受無狀態嘅 `2026-07-28` 模型上下文協定請求生命週期，包括 `server/discover`，同時亦支援較舊嘅基於會話嘅生命週期。現有客戶端可以繼續使用佢哋當前嘅連接方法。

支援模型上下文協定事件嘅客戶端可以訂閱項目事件。請參閱 [事件](#events) 以了解可用事件同交付要求。

已經支援遠程瀏覽器驗證嘅客戶端可以繼續喺瀏覽器中進行驗證。支援 `auth.md` 嘅客戶端同代理可以匿名註冊、出示受信任嘅提供者身份斷言，或啟動服務驗證嘅電郵聲明。註冊會返回一個由 Tuist 簽署嘅身份斷言，代理可以喺標準令牌端點交換為一小時嘅訪問令牌。Tuist 發布其公共簽名密鑰，並支援標準令牌撤銷同提供者安全事件交付。

未驗證嘅代理應該讀取模型上下文協定端點返回嘅 `WWW-Authenticate` 標頭，獲取受保護資源元數據，獲取授權伺服器元數據，並跟隨其 `agent_auth.skill` URL。Tuist 亦會喺未經授權嘅響應主體中返回相同嘅本地 `auth_md` URL，以便由語言模型驅動嘅客戶端可以發現流程而無需依賴本機客戶端整合。部署本地文檔係端點名稱、請求主體、聲明輪詢同斷言交換嘅唯一真實來源。

喺代理開始電郵聲明之前，必須要求用戶確認佢哋 Tuist 帳戶嘅電郵地址。唔可以從提供者個人資料、Git 配置、環境變量或會話元數據中推斷該地址。

端點使用 `mcp` 範圍組。匿名預聲明憑證可以發現功能並閱讀公開整合指南，但唔會被視為已登入用戶。經過瀏覽器授權或聲明後，憑證將限定於用戶範圍，每個工具都會應用與儀表板相同嘅授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">範圍組文檔</.localized_link>。

工具會解析到已驗證用戶已經可以讀取嘅項目。Xcode 同 Gradle 構建工具接受構建 UUID 或儀表板 URL。UUID 必須精確識別一個項目；如果出現喺多個項目中，工具會返回未找到，而唔係選擇另一個項目嘅報告。項目範圍嘅儀表板同 API 讀取仍然可用。報告嘅參與者標識符係未經驗證嘅標籤，唔係憑證或額外訪問權限。

構建列表同詳細信息工具暴露可選嘅 `tuist_version` 元數據：用於 Xcode 同 Cargo 嘅報告 Tuist CLI、用於 Gradle 嘅 Tuist Gradle 插件，以及用於 Mix 嘅 `tuist_ex` 庫。Xcode 亦會從其鏈接嘅項目生成事件中暴露 `tuist_generation_version`，這可能與上傳 CLI 不同。缺失嘅觀察值為 null，唔會從伺服器或其他報告中推斷。Bazel 使用其現有嘅 `bazel_version`；Once 運行詳細信息暴露 `once_version`。呢啲字段描述報告嘅版本，唔係經過驗證嘅身份或線路協定版本。REST 構建端點暴露相同嘅元數據。現有整合同不穩定測試技能唔依賴版本字段，無需更改工作流程。

Tuist 運營人員通過 Tuist 內部運營工具調查客戶帳戶，該工具記錄每次調用；直接連接到此端點無法獲得超出用戶自身成員資格嘅訪問權限。

### Pulse

Pulse 暴露只讀工具，用於帳戶嘅運營指標、日誌、追蹤同錯誤，全部通過 `account_handle` 尋址。前三個鏡像 Pulse 頁面同其 REST API；其他五個讓代理直接探索遙測數據，沒有 REST 等效項：

| 工具 | 用途 | `/api/accounts/:account_handle/pulse` 下嘅 REST 等效項 |
| --- | --- | --- |
| `query_pulse` | Pulse 頁面表格 | `GET /:signal` |
| `get_pulse_analytics` | Pulse 頁面小部件 | `GET /:signal/analytics` |
| `get_pulse_error_issue` | 一個錯誤問題及其事件 | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | 即時或範圍 PromQL | 無 |
| `list_pulse_labels` | 標籤名稱，或一個標籤嘅值 | 無 |
| `search_pulse_logs` | 過濾後嘅日誌條目 | 無 |
| `search_pulse_traces` | 過濾後嘅跨度 | 無 |
| `get_pulse_trace` | 一個追蹤嘅每個跨度 | 無 |

Pulse 僅限於伺服器配置組織嘅當前成員，即使帳戶或項目係公開嘅。它需要用戶驗證或與用戶關聯嘅 `mcp` 憑證同帳戶讀取授權。項目令牌、普通帳戶令牌、匿名註冊同沒有組織成員資格嘅運營人員訪問權限唔授予 Pulse 訪問權限。憑證無法選擇另一個後端或遙測租戶，並且只有伺服器配置嘅帳戶擁有 Pulse 遙測數據，因此沒有工具可以讀取另一個帳戶嘅數據。瀏覽器代理僅喺 Pulse 頁面上，喺該頁面嘅帳戶範圍內接收呢啲工具。

REST 需要用戶憑證。OAuth 同 `auth.md` 用戶關聯僅喺 `/mcp` 端點上可用；沒有當前用戶嘅帳戶憑證會被拒絕，無論關聯帳戶嘅成員資格或可見性如何。

`query_pulse` 接受 `signal`（`metrics`、`logs`、`traces` 或 `errors`）、可選嘅 `query` 同 `range`（`15m`、`1h`、`6h` 或 `24h`，默認 `1h`）。指標接受 PromQL 表達式。日誌、追蹤同錯誤接受文字、不區分大小寫嘅文本，與日誌主體、跨度名稱同錯誤問題標題匹配；`*`（默認）選擇所有內容。追蹤行係單個跨度。錯誤行係問題：按服務同指紋分組嘅事件，包括其事件計數、受影響帳戶、窗口中嘅首次同最後一次出現，以及最新事件嘅標題、責任方、級別同平台。表格接受 `search`、`page`（默認 `1`）、`page_size`（`1`–`100`，默認 `20`）、`sort_by` 同 `sort_order`（`asc` 或 `desc`）。排序列取決於信號並列喺工具模式中。過濾器包括 `service`，以及用於日誌同錯誤嘅 `level`。過濾器運算符使用相應嘅 `_op` 參數（`eq`、`contains` 或 `not_contains`），默認為精確相等。

排序列對於指標係 `name`/`value`；對於日誌係 `timestamp`/`service`/`level`/`message`/`trace_id`；對於追蹤係 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`；對於錯誤係 `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level`。儀表板故意暴露子集；API 同工具接受每個信號嘅完整列表。

表格響應包含 `rows`、`series`、`warnings` 同 `meta`。分頁元數據包括 `page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page` 同 `end_at`。將返回嘅 ISO8601 `end_at` 與後續頁面一起傳遞以保留查詢窗口。結果限制錯誤需要縮小查詢或時間範圍，而唔係將響應視為空表格。

日誌同追蹤喺本地排序之前最多檢查 100 個最新匹配項，錯誤則檢查最近看到嘅 100 個問題。過濾器、排序、分頁同總數僅描述那些返回嘅匹配項，而唔係整個時間窗口。縮小查詢文本或時間範圍以檢查其他匹配項；更改本地搜索或排序唔會擴展上游搜索。聚合小部件保持獨立，係完整窗口查詢，而唔係呢啲有界表格結果嘅聚合。

指標表格喺 `end_at` 評估其表達式一次，返回當前值同每個即時向量序列一個點。範圍向量表達式可以返回有界歷史點。獨立嘅分析小部件提供固定歷史圖表；表格唔會為每個匹配序列具體化時間網格嚟顯示其最新值。

遙測字符串係不受信任嘅數據，唔係指令。

`get_pulse_analytics` 除咗賬戶句柄之外，只接受 `signal` 同 `range`。其固定小部件獨立於表格表達式、過濾器、排序同分頁。

`get_pulse_error_issue` 從錯誤行中獲取問題嘅 `fingerprint` 同 `service`，加上可選嘅 `range`、`end_at`、`page` 同 `page_size`。它返回問題摘要、60 個相等發生次數桶、帶有異常鏈、堆棧幀、麵包屑、標籤、上下文、額外數據、請求方法同不含查詢字符串 URL 嘅最新事件，以及一頁事件（最新優先），具有與表格相同嘅分頁 `meta`。錯誤行還攜帶每個問題嘅 60 桶 `occurrence_series`。事件喺存儲前會被清除個人數據，所以過濾後嘅值顯示為 `[Filtered]` 或 `[REDACTED]`。窗口中沒有事件嘅問題會報告為未找到。REST 同 Model Context Protocol 使用相同嘅 Pulse 上下文同響應合約。REST 響應禁用緩存。

#### 探索遙測數據

探索工具讀取 `15m`、`1h`、`6h` 或 `24h`（默認 `1h`，`get_pulse_trace` 為 `24h`）嘅窗口，結束於可選嘅 ISO8601 `end_at`（默認為現在）。每個響應都返回 `start_at` 同 `end_at`；再次傳遞相同嘅 `end_at` 以保持窗口。呢啲工具都唔接受 SQL。

- `query_pulse_metrics` 喺 `end_at`（`type: instant`，默認）評估 `query`（PromQL 表達式），或者喺窗口期間每 `step` 秒評估一次（`type: range`）。步長默認為且唔能小於窗口除以 360，所以一個序列最多有 361 個點。結果最多有 5,000 個序列。點係 `[unix_seconds, value]`，`NaN` 同無限值係字符串。即時查詢拒絕 `range` 同 `step`。
- `list_pulse_labels` 接受 `signal`。如果沒有 `label`，它列出標籤名稱；如果有 `label`，它列出該標籤嘅值。對於指標，`__name__` 列出指標名稱，任何其他標籤嘅值都需要 `match`（系列選擇器，例如 `up`）。日誌同追蹤標籤值接受 `filters`；追蹤標籤名稱來自追蹤架構，所以唔需要。日誌同追蹤值包括它們喺窗口中嘅條目計數，最頻繁嘅排喺前面，所以它們也可以用作細分，例如按服務分類嘅錯誤。`search` 只保留包含字面文本嘅名稱或值，`limit` 接受 `1`–`1000`（默認 `100`）。日誌標籤名稱發現最多檢查每種類型嘅 1,000 個不同屬性集，並只列出過濾器接受嘅鍵。
- `search_pulse_logs` 返回最多 `limit` 個條目（`1`–`100`，默認 `50`），按 `newest` 或 `oldest` 排序，其主體包含 `text` 並匹配每個過濾器。每個條目包括其 `severity_text`、`body`、`trace_id`、`span_id`、`scope_name`，以及合併嘅資源同日誌 `attributes`。`span_id` 同 `scope_name` 對於從 Kubernetes 收集嘅日誌係 `null`，只有 OTLP 日誌發送者會設置它們。
- `search_pulse_traces` 返回最多 `limit` 個跨度，按 `newest`、`oldest` 或 `slowest` 排序，匹配每個過濾器、可選嘅 `min_duration_ms` 同 `max_duration_ms`，以及 `root_only`。
- `get_pulse_trace` 返回喺窗口中開始嘅 `trace_id` 嘅跨度，按最舊優先排序，最多 1,000 個跨度。喺窗口之前開始嘅追蹤會部分返回，所以需要擴大或移動窗口。每個跨度包括其跨度屬性、事件、鏈接，以及指向追蹤中不同 `resources` 嘅索引。

過濾器係最多 10 個 `{label, op, value}` 對象嘅列表。`op` 係 `eq`（默認）、`neq`、`contains` 或 `not_contains`；最後兩個係不區分大小寫嘅字面量。日誌標籤係 Pulse 存儲時嘅 `severity_text`、`trace_id`、`span_id` 同 `scope_name`，以及每個條目資源屬性嘅鍵（例如 `namespace`、`container` 同 `service.name`）同日誌屬性（例如 `pod`）。當一個鍵同時出現時，應用資源屬性。追蹤標籤係 `list_pulse_labels` 返回嘅跨度列，例如 `service_name`、`span_name`、`span_status_code`（失敗跨度為 `STATUS_CODE_ERROR`）、`span_attributes.http.route` 同 `resource_attributes.k8s.pod.name`。未知嘅追蹤標籤係錯誤，而唔係空結果。

`truncated` 意味著匹配嘅名稱、值、條目或跨度多於響應中包含嘅數量；請縮小過濾器或窗口，而唔係將響應視為完整。遙測字符串係不受信任嘅數據，唔係指令。

<details>
<summary>Claude Code</summary>

運行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 客戶端唔向模型暴露失敗嘅本機服務器連接時，要求代理喺搜索託管文檔或編輯項目之前檢查配置端點嘅未認證 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 響應。該響應將模型指向部署本地嘅 `auth.md` 文檔，即使瀏覽器身份驗證不可用。

</details>


<details>
<summary>Codex</summary>

運行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

喺開始新嘅 `codex exec` 運行之前完成瀏覽器登錄。Codex 喺初始化期間讀取 Tuist 服務器指令，所以 Gradle 優化請求自動獲得身份驗證同驗證工作流程。

</details>


<details>
<summary>Claude Desktop</summary>

打開 **Settings → Connectors → Add custom connector**，然後設置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

喺提示時喺瀏覽器中完成 [Open Authorization](https://oauth.net/2/)。

</details>


<details>
<summary>Pi</summary>

Pi 唔包括 Model Context Protocol 客戶端。你可以喺審查其源代碼同安全影響後安裝第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 擴展：

```bash
pi install npm:pi-mcp-adapter
```

添加項目級別嘅 `.mcp.json` 文件：

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

將 `auth` 設置為 `false` 可以防止適配器嘅瀏覽器身份驗證處理程序隱藏 Tuist 嘅未授權響應。無頭代理然後可以讀取返回嘅 `auth_md` URL 並遵循 Tuist 嘅註冊、身份斷言交換同聲明輪詢流程。將交換嘅訪問令牌配置為 bearer 令牌，或者讓代理直接進行經過身份驗證嘅 Model Context Protocol 調用。

如果你更喜欢瀏覽器身份驗證，將 `auth` 設置為 `"oauth"`。對於該流程，喺身份驗證完成期間保持一個進程活躍，使用 Pi 嘅 [remote procedure call mode](https://pi.dev/docs/latest/rpc)：

```bash
pi --mode rpc
```

唔好將待定嘅瀏覽器身份驗證拆分到單獨嘅 `pi --print` 調用中，因為擁有回調狀態嘅進程已經退出。

</details>


<details>
<summary>OpenCode</summary>

將 Tuist Model Context Protocol 服務器添加到 `opencode.json`：

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

然後驗證服務器：

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

使用 **Command Palette → MCP: Add Server**，然後配置一個 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 服務器，設置如下：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

打開 **Agent panel → Settings → Add Custom Server**，然後設置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果你嘅代理支援 `auth.md`，它可以匿名啟動而唔使打開瀏覽器。當供應商身份已經關聯時，可信嘅供應商身份亦可以唔使瀏覽器完成驗證。對於服務認證電子郵件、匿名聲明或首次供應商連結，代理會顯示一個 Tuist 驗證連結同六位數代碼。打開連結，登入，然後喺 Tuist 頁面輸入代理嘅代碼。切勿將代碼發送返俾代理。Tuist 嘅授權服務器元數據直接指向部署自身嘅 `/auth.md`，其中包含精確嘅請求同輪詢結構。

## Amp orbs 同 Claude Code 雲端會話中嘅代理

喺連接到 Tuist 帳戶嘅沙盒中運行嘅編碼代理可以使用自己嘅身份令牌對端點進行身份驗證，而唔需要瀏覽器或存儲嘅 Tuist 憑證：

- 通過 **Settings → Integrations → Amp** 連接帳戶嘅 Amp 工作區或項目嘅 **Amp orbs** 會發送 orb 嘅 ID 令牌。喺 Amp 中，將服務器嘅 `Authorization` 標頭設置為 `Bearer ${amp:id-token}`。Amp 為服務器 URL 嘅來源鑄造令牌，所以 URL 必須係此 Tuist 實例自身嘅地址，並喺過期前刷新它。為其他來源鑄造嘅令牌會被拒絕。
- 已連接 Claude Code 環境嘅 **Claude Code cloud sessions** 會發送 Tuist 作為 `TUIST_OIDC_TOKEN` 傳遞俾佢哋嘅會話令牌。將標頭設置為 `Bearer ${TUIST_OIDC_TOKEN}`。

Tuist 嘅 Linux 沙盒唔會為你添加服務器：佢哋附帶 Tuist CLI（使用相同身份登入）同一個技能，告訴代理何時根據項目歷史檢查其結果。要俾代理亦擁有 MCP 工具，請將服務器添加到你嘅 Amp 或 Claude Code 設置中，或者添加到項目嘅 `.mcp.json`，並使用上述標頭。

這些令牌提供對連接帳戶每個項目嘅只讀訪問權限：佢哋攜帶 `mcp` 組嘅讀取範圍，而唔包含創建、更改或刪除數據（例如靜音或跳過測試）嘅任何權限。斷開工作區或環境連接會喺下一次請求時停止訪問，且訪問權限永遠唔會超過令牌本身嘅有效期。連接到多個 Tuist 帳戶嘅 Amp 工作區會被拒絕，因為其令牌未指定單一帳戶。當缺少連接時，未授權響應嘅 `error_description` 會說明這一點。

這種只讀訪問權限僅適用於 Model Context Protocol 端點。同一沙盒中嘅命令行工具同構建系統集成仍然交換令牌以獲取連接嘅 CI 訪問權限。

## WebMCP

喺支援 [WebMCP](https://webmachinelearning.github.io/webmcp) 嘅瀏覽器中，Tuist 嘅頁面使用 `document.modelContext` 註冊工具，所以內置於瀏覽器嘅代理可以調用佢哋而唔需要任何額外配置。調用喺 Tuist 服務器上運行。

- **Website and documentation pages** 註冊文檔同源代碼工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 同 `read_tuist_file`）。佢哋唔需要你登入。
- 當你登入時，**An account's dashboard pages** 會為該帳戶註冊 Tuist 嘅只讀工具。每個頁面僅註冊其顯示內容對應嘅工具，針對項目嘅構建系統：Gradle 項目嘅構建頁面獲得 Gradle 構建工具，其測試頁面獲得測試同覆蓋率工具，運行器頁面獲得運行器工具，沙盒頁面獲得沙盒工具。每個頁面亦獲得文檔工具 `list_projects` 同 `get_project`。工具以登入用戶身份運行，所以佢哋只能訪問你可以喺儀表板中讀取嘅數據，且僅限於你正在查看嘅帳戶。當你轉到另一個頁面或帳戶時，工具會被該頁面嘅工具替換。

創建、更改或刪除數據嘅工具唔可通過 WebMCP 使用，因為瀏覽器代理喺你唔添加佢哋嘅情況下接收工具，並讀取構建同測試產生嘅內容。連接 MCP 客戶端到 `/mcp` 端點以使用這些工具。

如果組織強制單點登入，請使用其供應商登入儀表板以使用其工具。

## 構建系統集成使用兩個憑證

用於 Model Context Protocol 工具嘅憑證唔會驗證 Gradle 插件或 Bazel 嘅遠程服務。喺代理編輯或驗證 Gradle 或 Bazel 集成之前，它應該運行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未經過身份驗證，代理必須停止並要求用戶運行：

```bash
tuist auth login --url https://tuist.dev
```

對於本地或自託管部署，請替換兩個命令中同 `tuist.toml` 中嘅 URL。喺所有地方保持主機名拼寫一致。例如，`localhost` 同 `127.0.0.1` 使用單獨存儲嘅憑證。


## 功能

### 工具

以下工具可通過 Tuist Model Context Protocol 服務器使用：

每個工具都發布人類可讀嘅描述，以及明確嘅輸入同輸出模式。成功調用返回符合廣告輸出模式嘅結構化內容，加上序列化為文本嘅相同結果，供尚未消費結構化內容嘅客戶端使用。

接受單個記錄標識符（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）嘅工具亦接受該記錄嘅 Tuist 儀表板 URL。直接從瀏覽器粘貼 URL，而唔係從中提取標識符。

`get_xcode_build`、`get_test_run`、`get_gradle_build` 同 `get_project` 可以包括 `side_quests`：項目未使用但記錄顯示會有幫助嘅 Tuist 功能。每個都有一個 `id`、一個說明其基於證據嘅 `tip` 同一個 `docs` 連結。要求代理首先完成用戶嘅請求，提及適用嘅側線任務，並僅喺用戶同意時執行其中一個。佢哋僅返回給項目帳戶嘅成員，無論佢哋係通過用戶會話、MCP 令牌還是代理身份連接：

| ID | 工具 | 建議時機 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | 使用 Xcode 26 或更高版本嘅乾淨構建處理後，冇運行任何可緩存嘅編譯任務。 |
| `gradle_build_cache` | `get_gradle_build` | 構建執行咗可緩存任務，但 Gradle 嘅構建緩存冇為其中任何一個計算密鑰，即表示構建緩存已關閉。 |
| `flaky_test_quarantine` | `get_test_run` | 一次運行包含不穩定測試，而項目中冇啟用自動化來靜音或跳過佢哋。唔建議用於 Once 項目。 |
| `test_sharding` | `get_test_run` | 喺 Tuist 可以分片嘅構建系統中，一次未分片嘅 CI 運行耗時 10 分鐘或更長。提示會說明選擇性測試已跳過咗幾多個測試（如果有的話）。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI 運行使用咗 GitHub Actions、Bitrise、GitLab CI 或 Buildkite 機器，而該帳戶從未喺 Tuist Runners 上運行過作業。僅限 tuist.dev。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actions 運行屬於一個未連接到其 GitHub 倉庫嘅項目。 |
| `other_build_systems` | `get_project` | 該帳戶冇將 Tuist 與每個受支持嘅構建系統一起使用。提示列出咗識別其他系統嘅文件，以便代理可以檢查倉庫。 |

#### 文檔同社區搜索

呢個只讀工具通過驅動文檔網站嘅同一搜索引擎，搜索 Tuist 嘅文檔、[應用程序編程接口](https://en.wikipedia.org/wiki/API)參考、GitHub 發布、社區論壇同 GitHub issues。發布結果包括產品、版本、發布日期同預發布狀態。默認搜索穩定發布，可以通過 `include_prereleases` 包含預發布。該工具僅喺 `https://tuist.dev/mcp` 上嘅 Tuist 託管服務器可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公開嘅 Tuist 文檔、應用程序編程接口參考、GitHub 發布、社區討論同 GitHub issues。可選限制為一個 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 反饋

當 Tuist 工具或提示未按預期工作時（例如結果令人困惑、出現錯誤、數據缺失或功能缺失），代理可以告知 Tuist 團隊。要求代理建議提交報告，並僅喺你同意後發送。每份報告都會開啟與 Tuist 支持團隊嘅對話，佢哋可能會通過電子郵件回覆你。報告包括代理嘅預期、實際發生嘅情況、可選建議、你嘅 Tuist 用戶 ID、handle 同電子郵件，以及你所屬嘅組織。代理還可以命名問題發生嘅帳戶同項目，以便團隊知道跟進哪個組織；僅接受你所屬嘅帳戶。只有以 Tuist 用戶身份登入嘅代理才能發送報告，每個用戶每小時最多可以提交 10 份報告。該工具僅喺 `https://tuist.dev/mcp` 上嘅 Tuist 託管服務器可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `report_feedback` | 報告 Tuist 工具或提示嘅問題。可選指定 `tool_name`、問題發生嘅 `account_handle` 同 `project_handle`，並添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基於源代碼嘅答案

呢啲只讀工具讓代理使用與託管服務器一起部署嘅確切公開 Tuist 源代碼修訂版，作為依賴當前行為嘅答案嘅真實來源。佢哋僅喺 `https://tuist.dev/mcp` 可用。

兼容嘅客戶端喺初始化期間會收到關於工具源代碼修訂版、連結同結果限制嘅事實描述，以及內聯 OAuth 身份驗證信息。呢啲描述唔規定答案風格或驗證工作流程。用戶可以直接提問，而唔需要先調用 `ask_tuist` 提示；該提示仍然可用於明確嘅基於源代碼嘅工作流程。

每個操作都有固定嘅併發、持續時間、遍歷、讀取字節數同響應大小限制。搜索同列表結果包括 `truncated` 同 `truncation_reason` 字段。當結果被截斷時，請縮小路徑、文件模式或搜索詞，而唔係將結果視為完整。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 通過搜索源代碼文件來回答關於當前行為、默認值、配置、功能開關、錯誤處理或未記錄細節嘅問題。結果包括周圍行、修訂版鎖定嘅源代碼連結同掃描統計信息。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，發現源子系統或附近嘅測試。列表具有有限嘅深度同結果數量。 | 無 |
| `read_tuist_file` | 喺找到相關路徑後，檢查實現文件、調用站點或測試中嘅特定行範圍。截斷嘅響應提供 `next_start_line` 以便繼續。 | `path` |

#### 項目

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出認證用戶可用嘅個人同組織帳戶 handle，包括每個帳戶是否可以創建項目。 | 無 |
| `get_organization` | 獲取組織嘅成員目錄。待處理嘅邀請需要與儀表板相同嘅管理員權限；永遠唔會返回邀請接受令牌。 | `account_handle` |
| `create_organization` | 為認證用戶創建 Tuist 組織。 | `handle` |
| `create_project` | 喺認證用戶可以訪問嘅帳戶下創建 Tuist 項目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有 Tuist 用戶添加到組織，或更新現有成員嘅角色。接受 `user`（默認）、`admin` 或 `viewer`，其中檢視者可以閱讀儀表板同運行記錄，但唔能更改任何內容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有 Tuist 用戶。Tuist 會發送一個有效期為 14 天嘅接受連結；當服務器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製連結。接受 `user`（默認）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理嘅組織邀請，使其連結無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出認證用戶可訪問嘅所有項目。 | 無 |
| `get_project` | 獲取項目嘅配置同連接嘅存儲庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將項目連結到帳戶嘅 GitHub App 安裝可以訪問嘅 GitHub 存儲庫。項目會採用存儲庫嘅默認分支。需要項目管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除項目與其 GitHub 存儲庫嘅連結。需要項目管理員權限。 | `account_handle`, `project_handle` |

#### 帳戶令牌

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳戶令牌元數據，而唔暴露令牌值。 | `account_handle` |
| `get_account_token` | 獲取帳戶令牌元數據，而唔暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出項目令牌元數據，而唔暴露令牌值。 | `account_handle`, `project_handle` |

#### 通知規則

呢啲工具管理認證用戶自己嘅通知規則：當事件（例如新預覽）喺規則所屬項目（或者當未列出項目時，任何你可以收到通知嘅項目）中發生並滿足其條件時，執行其操作，例如向你嘅 Tuist 應用設備發送推送通知。如果沒有規則，你將收唔到任何通知。佢哋需要用戶身份驗證，僅作用於你自己嘅規則，並且僅接受你所属帳戶嘅項目。佢哋唔提供畀儀表板頁面，因為規則跨越你嘅所有帳戶。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_notification_events` | 列出規則可以訂閱嘅事件類型，每個類型都有一個用於其條件嘅 JSON Schema。 | 無 |
| `list_notification_condition_options` | 建議項目中事件嘅條件值，例如其最近預覽嘅軌道同分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出你嘅規則。 | 無 |
| `create_notification_rule` | 從事件、可選項目同條件以及至少一個操作創建規則。 | `event`, `actions` |
| `update_notification_rule` | 更改規則嘅啟用狀態、項目、條件或操作。 | `rule_id` |
| `delete_notification_rule` | 刪除規則。 | `rule_id` |

#### 持續集成運行器

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳戶嘅持續集成運行器作業。 | `account_handle` |
| `get_runner_job` | 獲取持續集成運行器作業，包括其機器是否記憶體不足、停止咗乜嘢以及需要更改乜嘢。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續集成運行器作業記錄嘅步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續集成運行器作業記錄嘅機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續集成運行器作業最多 500 條捕獲嘅日誌行。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳戶嘅持續集成工作流程匯總。 | `account_handle` |
| `list_runner_profiles` | 列出帳戶嘅持續集成運行器配置文件，包括每個文件嘅 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出運行器配置文件可以使用嘅機器形狀同 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 創建包含平台、機器形狀以及 macOS 上 Xcode 版本嘅運行器配置文件。可選設置哪些分支保存其緩存卷。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改運行器配置文件嘅機器形狀、Xcode 版本，或者哪些分支保存其自定義緩存卷更改。省略嘅字段保持其值不變。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 經用戶確認後刪除運行器配置文件。默認配置文件無法刪除。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

運行器卷工具公開與 Volumes 儀表板相同嘅數據。讀取工具需要運行器訪問權限；清除需要帳戶管理權限或 `account:runners:write` 範圍，以及用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名稱同存儲庫過濾，對卷進行排序同分頁。 | `account_handle` |
| `get_runner_volume` | 存儲庫、平台、容量、已用空間同最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁嘅作業同工作流程參考、緩存狀態、命中結果同掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作業掛載嘅卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存儲序列、作業運行、命中率同趨勢。可選 `volume_id`、`start` 同 `end`（ISO 8601）；默認為七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 刪除卷及其保存嘅內容。運行中嘅作業保留其私有副本但無法保存；之後使用相同密鑰嘅作業將從空開始。 | `account_handle`, `volume_id` |

列表接受 `page` 同 `page_size`（最多 100）。卷庫存還接受 `name` 同 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）同 `sort_order`（`asc`、`desc`）。未知測量值同命中結果保持為 `null`。緩存狀態描述卷更改是否已保存，而非作業成功與否。

#### 沙盒

沙盒工具公開與 Sandboxes 儀表板相同嘅數據同操作，並具有與 [API](https://tuist.dev/api/docs) 相同嘅訪問權限：帳戶成員可以列出、獲取、創建、暫停、恢復同刪除沙盒，但服務於代理環境、Amp 或遠程執行嘅沙盒，以及分析同歸檔工具，需要帳戶管理權限。只讀查看者無法使用佢哋。帳戶需要啟用沙盒。儀表板嘅沙盒頁面註冊咗只讀工具。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_sandboxes` | 對沙盒進行分頁，顯示其狀態、形狀同時間戳。可選 `search`（沙盒中嘅文本、Amp Orb 或 Anthropic 會話 ID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）同 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒嘅狀態、形狀、節點、歸檔同時間戳。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小時、創建嘅沙盒數量、會話、設置同啟動持續時間，以及相對於帳戶限制嘅峰值 vCPU、記憶體同磁盤，連同趨勢。可選 `start` 同 `end`（ISO 8601）；默認為 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 啟動一個空白沙盒並喺其運行後返回。可選 `platform`（`linux` 或 `darwin`）、`xcode_version`（macOS 沙盒嘅精確 Xcode 版本，來自工具描述中列出嘅版本；暗示 `darwin`）、`template`、帶 `memory_mb` 嘅 `vcpus`（Linux：2x4096、4x8192 或 8x16384，默認 2x4096；macOS：8x8192、8x16384 或 8x24576，默認 8x8192）同 `workspace_gb`。其描述指示代理使用 `mise install` 喺 Mac 上安裝存儲庫中鎖定嘅 Tuist，然後自行 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">使用帳戶嘅緩存</.localized_link>。 | `account_handle` |
| `pause_sandbox` | 將運行中嘅沙盒快照保存到其節點嘅磁盤。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢復已暫停或歸檔嘅沙盒。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 排隊將已暫停沙盒嘅磁盤移動到對象存儲。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 經用戶確認後刪除沙盒及其磁盤。 | `account_handle`, `sandbox_id` |

#### Amp 工作區

呢啲工具管理 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 工作區連接</.localized_link>，允許 orbs 無需令牌即可登錄 Tuist。佢哋使用與儀表板 Integrations 頁面相同嘅僅管理員權限。Orb 中嘅代理可以從 `$AMP_WORKSPACE_ID` 同 `$AMP_PROJECT_ID` 讀取其自身 ID。連接允許嘅每個 orb 都會獲得對帳戶中所有項目嘅 CI 訪問權限，因此代理應喺連接前與用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 列出帳戶連接嘅 Amp 工作區，以及每個工作區限制嘅項目（如果有）。 | `account_handle` |
| `connect_amp_workspace` | 連接 Amp 工作區。可選 `project_id` 將登錄限制為一個 Amp 項目嘅 orbs。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 斷開工作區連接。其 orbs 已有嘅會話保持有效直到過期。 | `account_handle`, `connection_id` |

#### Claude 環境

呢啲工具連接 Claude Managed Agents 自託管環境，以便佢哋嘅會話喺 Tuist 沙盒中運行，就像 Settings → Integrations → Claude 所做嘅那樣。佢哋需要帳戶管理權限並啟用沙盒。代理可以使用 Anthropic 嘅 API 創建環境，但只有 Claude Console 生成其環境密鑰，因此代理會向用戶索取。Tuist 使用 Anthropic API 密鑰或工作負載身份聯合啟動會話，並喺保存之前使用該憑證獲取環境。Anthropic 端嘅設置使用用戶自己嘅 Anthropic 憑證；Tuist 永遠不會接收佢哋。密鑰通過客戶端同模型傳遞，因此請明確提供佢哋。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_claude_environments` | 列出已連接嘅環境同佢哋各自使用嘅憑證，以及聯合規則應信任嘅發行者 URL 同主體前綴。 | `account_handle` |
| `connect_claude_environment` | 使用 `api_key` 連接環境，或者使用 `organization_id`、`workspace_id`、`service_account_id` 同 `federation_rule_id`。可選嘅 `platform`、`vcpus` 同 `memory_mb` 用於設定沙盒規格。 | `account_handle`, `environment_id`, `environment_key` |

#### Webhooks

Webhook 工具使用與儀表板相同嘅僅管理員權限。傳送嘗試包含為端點記錄嘅請求同響應數據，但絕不包含端點簽名密鑰。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳戶嘅 webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 獲取一個 webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點嘅傳送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 獲取一次傳送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 構建

適用於 Xcode、Gradle、Bazel、Mix 同 Cargo 嘅構建詳情工具會公開現有嘅 `custom_metadata: {tags, values}` 結構，包括基礎設施觀察數據（如果有報告）。值保持為字符串，不熟悉嘅鍵會被保留。例如，`tuist.cpu.available_processors` 描述運行時可用嘅邏輯處理器，而 `tuist.gradle.max_workers` 係 Gradle 工作器限制，`tuist.jvm.max_heap_bytes` 係 JVM 堆限制，而非主機內存。呢啲係不受信任嘅客戶端觀察數據，並非經過驗證嘅運行器身份。缺失嘅觀察數據會保持缺失；導入嘅日誌同舊版客戶端可能沒有基礎設施元數據。元數據更新有待客戶端/協議嘅協調更新。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出項目嘅 Xcode 構建運行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 獲取特定 Xcode 構建運行嘅詳細信息，包括保存原始 `.xcactivitylog` 嘅歸檔文件嘅臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 構建運行嘅構建目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 構建運行嘅編譯文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄嘅構建步驟，包含計時同結果，但不包含日誌文本。 | `build_run_id` |
| `get_xcode_build_step` | 獲取一個記錄嘅構建步驟，包括其日誌同截斷標誌。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定構建運行嘅構建問題（警告同錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 構建運行嘅可緩存任務（緩存命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 構建運行嘅 [內容尋址存儲](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 默認返回每頁 20 個步驟（通過 `page_size` 最多可設為 100），並提供 `page` 同 `pagination_metadata` 用於導航。使用 `search` 匹配標題、項目或目標，或者過濾精確嘅 `project`、`target`、`category`（例如 `swiftCompilation`）同 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以先顯示最慢嘅（默認），或按 `start_ms` 排序以顯示時間順序。步驟 ID 用於打破平局，並作為十進制字符串返回以保留完整嘅 64 位精度。ID 限定於單次構建，不應跨構建匹配。

可選嘅 `start_ms` 同 `end_ms` 選擇與從構建開始計算嘅毫秒時間範圍重疊嘅步驟；結束時間係exclusive。兩個工具都接受構建 UUID 或儀表板 URL 作為 `build_run_id`。將返回嘅步驟 `id` 原樣作為 `step_id` 傳遞以檢索其日誌。日誌每個步驟最多保留 64 KiB，`log_truncated` 表示省略嘅輸出。

處理 Xcode 構建時默認會收集步驟。記錄嘅步驟數據保留 90 天。列表響應包括 `availability`：當存在記錄嘅步驟時為 `available`，即使過濾器無匹配項；當構建仍在處理且尚未有步驟時為 `processing`；或者當步驟未被記錄或已過期時為 `unavailable`。

HTTP API 喺 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 同 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 提供相同嘅操作，具有相同嘅過濾器同分頁。兩者都需要對構建項目嘅讀取權限。

#### Gradle 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整嘅身份驗證、項目設置、Gradle 插件、緩存策略同兩次構建驗證工作流程。代理喺編輯現有 Android 或 Gradle 項目之前應調用此接口。 | 無 |
| `list_gradle_builds` | 列出項目嘅 Gradle 構建運行，包括自定義元數據。使用可選嘅 `tag` 參數按自定義標籤過濾。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 獲取構建元數據、任務/緩存計數，以及 `failures`：每個失敗任務同配置步驟嘅失敗消息。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任務結果、複合構建標識、可緩存性、增量狀態同失敗消息。 | `build_run_id` |
| `list_gradle_build_steps` | 列出帶計時嘅任務、配置同轉換，支持搜索、元數據同重疊時間過濾器。 | `build_run_id` |
| `get_gradle_build_step` | 通過不透明 ID 檢查記錄嘅步驟元數據；失敗任務或配置步驟嘅 `log` 係其失敗消息。 | `build_run_id`, `step_id` |

Gradle 同 Bazel 步驟列表默認返回 20 個結果（最多 100 個），支持 `search`、精確匹配 `project`、`target`、`category` 同 `status`、重疊嘅 `start_ms` / `end_ms` 過濾器（結束時間為 exclusive），以及按 `duration_ms` 或 `start_ms` 排序。請原樣傳遞返回嘅 ID；佢哋係限定於各自構建嘅。列表會顯示 `time_origin` 同 `coverage`。較舊嘅 Gradle 報告使用 `first_recorded_timestamp`，因為無上傳構建開始時間。Bazel 配置文件通過 `trace_profile` 覆蓋範圍同作為時間起點嘅 `profile_start` 顯示所有記錄嘅間隔。較舊嘅構建會回退到保留嘅 BEP 摘要。源記錄喺 90 天後過期。Bazel 詳情喺發布時包括經清理嘅操作日誌。失敗任務或配置步驟嘅 Gradle 詳情包括 Tuist Gradle 插件作為 `log` 報告嘅失敗消息：即異常消息及其原因鏈，如同 Gradle 控制台打印嘅那樣，無堆棧跟蹤或任務輸出，項目內嘅路徑已轉為相對路徑，憑證同其他本地路徑已脫敏，每個步驟最多 16 KiB，每次構建最多 32 個失敗步驟。其他 Gradle 步驟、由較舊插件版本報告嘅構建，以及無憑證嘅報告，其 `log` 為 null。配置步驟喺失敗時報告 `failure`，否則報告 `unknown`。`compare_builds` 提示使用此覆蓋範圍來區分完整嘅 Bazel 跟踪同保留嘅摘要，並指導代理喺檢查更廣泛嘅調用輸出之前，查看步驟詳情以獲取操作結果同日誌。

單步工具 `get_gradle_build_step` 同 `get_bazel_build_step` 通過 ID 檢索步驟，不接受時間過濾器；請使用相應嘅列表工具按時間範圍過濾步驟。

如果喺列出步驟同獲取步驟之間收到完整配置文件，則從保留摘要返回嘅 Bazel 步驟 ID 仍然可讀。如果索引配置文件嘅步驟數據已過期，則報告為不可用。Gradle 步驟列表包括零持續時間嘅緩存同跳過操作。

#### Bazel 調用

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份驗證、項目設置、Bazel 配置同驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成嘅 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 調用，按最新優先排序，包括構建指標、有界執行時間線、關鍵路徑診斷同項目相關嘅遠程緩存總計。按 `status`、`git_branch`、`git_commit_sha`、`is_ci` 同 `command` 過濾。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 獲取一個已完成嘅 Bazel 調用，包括構建指標、有界執行時間線、關鍵路徑診斷同相關嘅遠程緩存總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄嘅 Bazel 配置文件間隔，帶有過濾器同明確嘅覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄嘅 Bazel 步驟及其發布嘅操作結果同經清理嘅日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按執行順序列出為 Bazel 調用捕獲嘅經清理日誌：Bazel 進度輸出嘅有界尾部同 `test.log` 構件。可選嘅 `stream`（`stdout` 或 `stderr`）、`source`（`progress` 或 `test_log`）、`target_label` 同 `errors` 過濾器可縮小結果範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 獲取為 Bazel 調用捕獲嘅一個經清理日誌塊。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始 Bazel 遠程緩存觀察記錄，包括其操作、端點同觀察時間，可選擇縮小到特定調用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 獲取一個原始 Bazel 遠程緩存觀察記錄。 | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations` 過濾器為精確匹配，同一秒內完成嘅調用按調用 ID 排序。要查找分支上最新嘅失敗調用，請使用 `status: "failure"`、`git_branch` 同 `page_size: 1` 調用。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` 接受相同嘅過濾器。

測試日誌攜帶來自測試結果嘅 `target_label` 同嘗試 `status`，因此 `target_label: "//foo:bar_test"` 僅返回該目標嘅測試日誌。`errors: true` 返回失敗嘗試嘅測試日誌同包含 Bazel 報告器以 `ERROR:`、`FAIL:` 或 `TIMEOUT:` 開頭嘅行嘅 stderr 進度塊。進度輸出未歸因於目標，喺記錄歸因之前寫入嘅日誌字段為空。失敗操作及其輸出可通過 `list_bazel_build_steps` 按目標獲取，每個測試用例嘅失敗可通過測試運行工具獲取。

#### Cargo 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出項目嘅 Cargo 構建，按最新優先排序。按 `git_branch`、`status`、`is_ci` 或 `command` 過濾。Cargo 測試執行結果可通過測試工具獲取，而非此構建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 獲取構建元數據、聚合緩存計數，以及最多 500 個帶有診斷信息嘅記錄編譯作業。`compilations_truncated` 表示省略嘅作業；診斷信息僅涵蓋返回嘅作業。 | `account_handle`, `project_handle`, `build_id` |

喺 `get_cargo_build` 上設置 `include_cache_inspection: true` 以檢索經過驗證嘅任務決策同 CAS 操作，限制為 4 MB。默認情況下，以及當記錄缺失或無效時，`cache_inspection` 為 null。請尊重其部分捕獲嘅 `truncated` 標誌；傳輸不會確定每個任務命中嘅本地/遠程來源。HTTP 詳情端點接受相同嘅查詢參數。

#### Mix 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出項目嘅 Mix (Elixir) 編譯構建，按最新優先排序，包括自定義元數據。按 `git_branch`、`status`、`is_ci` 或 `mix_env` 過濾。 | `account_handle`, `project_handle` |
| `get_mix_build` | 獲取構建元數據、診斷計數同依賴緩存摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 構建跟踪

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_build_trace` | 獲取 Xcode、Gradle、Bazel 或 Mix 構建時間線嘅下載鏈接，作為可在 [Perfetto](https://ui.perfetto.dev) 中打開嘅跟踪文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 係構建運行 ID（Bazel 嘅調用 ID）或構建嘅儀表板 URL。返回嘅 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有該鏈接嘅人都可以喺 `expires_at`（調用後一小時）之前下載該構建嘅跟踪，無需其他憑證。代理可以使用 `curl` 下載，交俾你喺 Perfetto 中打開，或使用 Perfetto 嘅 `trace_processor` 進行查詢。跟踪包含按並行性打包到通道中嘅記錄步驟、跨越整個構建嘅軌道，以及當構建記錄機器指標時嘅 CPU 同內存計數器。它包含與上述步驟工具相同嘅數據，但無日誌。儀表板喺每個構建嘅「時間線」標籤頁提供相同嘅文件。

#### Once 運行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出項目嘅 Once 運行，按最新優先排序。按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 過濾。未完成嘅運行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 獲取運行及其操作總數、緩存摘要，以及測試運行嘅測試總數。 | `account_handle`, `project_handle`, `run_id` |

Cargo 構建、Mix 構建同 Once 運行 ID 喺項目內係唯一嘅。通過 HTTP API 喺 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 同 `.../once/runs` 提供相同嘅讀取功能，每個 ID 都有一個詳情端點。

#### 任務、操作、模組同文件

呢啲項目範圍嘅工具檢查跨運行嘅持久構建身份。首先使用 `list_build_entities`，然後將返回嘅穩定 `id` 連同相同嘅 `kind` 傳遞給 `get_build_entity` 或 `list_build_entity_history`，並連同 `account_handle` 同 `project_handle`。無需構建或調用標識符。

| 工具 | 描述 | 必需參數 |
| --- | --- | --- |
| `list_build_entities` | 列出喺項目構建中看到嘅某一類任務、模組、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 獲取一個構建實體及其原生身份同所選時期嘅分析數據。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個構建實體嘅記錄執行、編譯或緩存事件，按最新優先排序。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 報告嘅操作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模組 | 編譯同模組緩存事件 |
| `once_actions` | Once 操作 | 執行 |
| `mix_files` | Mix 編譯文件 | 編譯 |
| `mix_modules` | Mix 編譯模組 | 編譯 |
| `cargo_crates` | Cargo crates | 記錄嘅 rustc 調用 |

呢啲工具正逐步推出，僅返回已啟用它們嘅項目嘅數據；對於其他項目，它們返回錯誤而非空結果。某種類型僅適用於使用其構建工具鏈嘅項目。工具接受有界嘅 `start_at`/`end_at` 過濾器、`environment`（`any`、`ci` 或 `local`）同精確嘅 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明嘅 `after`/`before` 游標。未知嘅計時或緩存觀察仍然不可用，而不會變成零或錯過。歷史記錄引用記錄嘅父級同原生執行，以便使用現有嘅運行工具進行深入分析。

`get_build_entity` 指標包括 `duration_samples`，即具有記錄計時嘅觀察數量：真實嘅零持續時間計入，缺失嘅計時不計入。此計數可能低於觀察計數；不可用嘅持續時間統計信息保持為 null。

Xcode 模組持續時間來自構建日誌中測量嘅目標編譯。模組緩存解析同無編譯工作嘅目標不會貢獻持續時間樣本。編譯觀察引用 Xcode 構建；緩存事件引用生成或緩存命令。

Bazel 操作由目標標籤、助記符同配置嘅主要輸出標識，保持單獨嘅操作同配置區分開來，而唔依賴於輸入依賴嘅緩存摘要。歷史記錄 BEP 報告嘅執行，而非緩存查找或跟踪配置文件階段。完整嘅執行覆蓋需要 `--build_event_publish_all_actions`；工件交付係盡力而為，因此缺失嘅觀察並非無工作運行嘅證據。較舊嘅 Kura 負載如果無穩定身份或執行開始，仍然被接受但未被索引。缺少結束時間測量仍然不可用，真實嘅零持續時間計入。

Mix 模組持續時間測量包含文件嘅編譯，而非獨立測量嘅模組工作。Once 操作喺客戶端報告目標映射時使用聲明嘅目標/能力/索引槽；僅診斷標籤並非穩定身份。現有客戶端同運行級別工具繼續得到支持，保持不變。

Cargo crates 按精確記錄嘅 crate 根、名稱同類型分組。檢出路徑更改可能會分割歷史記錄，並且構建配置文件、功能同目標三元組未被區分。歷史測量 rustc 調用，而非每文件工作或緩存命中；缺失嘅作業並未確立刪除或完整嘅工作區清單。

分析讀取具有有限嘅內存同執行時間。如果查詢超過呢啲限制，工具將返回錯誤而非憑空創造一個空結果。

新觀察喺部署後被索引；此功能不會回填現有嘅運行遙測數據。身份元數據喺 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link> 下比單個觀察更長久。

#### 測試

| 工具 | 描述 | 所需參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出項目嘅測試執行。`query` 欄位包括 `git_branch`、`scheme` 同 `status`：`field:"value"` 為精確匹配，`field~"value"` 為不區分大小寫嘅子字符串匹配，而前置 `-` 則對任一運算符取反。例如，`-git_branch~"gh-readonly-queue"` 會排除合併隊列分支。以空格分隔嘅查詢過濾器同明確參數會以 AND 語義組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 獲取測試執行嘅詳細指標，包括其結果捆綁包 (`.xcresult`) 同會話存檔嘅臨時下載 URL。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行嘅測試模組運行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行嘅測試套件運行，可選按模組過濾。 | `test_run_id` |
| `list_test_cases` | 列出項目嘅測試案例（支持如 `flaky` 等過濾器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 獲取測試案例嘅詳細指標，包括可靠性比率、不穩定比率同運行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例運行，可選按測試案例或測試執行過濾。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 獲取特定測試案例運行嘅失敗詳情同重複次數。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例運行嘅附件。每個附件都包含一個臨時下載 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例嘅狀態變更，例如將其靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例嘅狀態或不穩定分類。變更可以向配置嘅 webhook 端點（包括外部服務）發送事件。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試執行嘅選擇性測試目標結果。 | `test_run_id` |
| `get_coverage` | 獲取項目喺某個提交或分支最新完整提交時嘅代碼覆蓋率及其目標。如果無 `git_commit_sha` 或 `branch`，則讀取默認分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出某個提交或分支最新完整提交時代碼覆蓋率測量嘅文件及其行覆蓋率。支持 `search`、排序同分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 獲取某個提交或分支最新完整提交時文件嘅代碼覆蓋率及其函數。設置 `include_lines` 以獲取每行嘅執行次數。 | `account_handle`, `project_handle`, `path` |

代碼覆蓋率工具僅適用於已啟用代碼覆蓋率嘅帳戶。

#### 捆綁包

| 工具 | 描述 | 所需參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出項目嘅捆綁包（應用二進制文件）。可選按 `git_branch` 同 `tags` 過濾（所有標籤必須精確匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 獲取特定捆綁包嘅詳細信息，包括自定義標籤。 | `bundle_id` |
| `get_bundle_artifact_tree` | 獲取捆綁包嘅完整工件樹，作為按路徑排序嘅平面列表。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以區分構建變體或環境。標籤係區分大小寫嘅標籤，包含字母、數字、連字符或下劃線，最多 10 個標籤，每個標籤最多 50 個字符。列表同詳細結果包括 `custom_metadata.tags`。分頁計數同分支過濾器應用於帶標籤嘅結果；省略 `tags` 將保留未過濾嘅行為。無效嘅標籤過濾器將返回錯誤而非擴大查詢範圍。

#### 生成

| 工具 | 描述 | 所需參數 |
|------|-------------|---------------------|
| `list_generations` | 列出項目嘅生成運行。 | `account_handle`, `project_handle` |
| `get_generation` | 獲取特定生成運行嘅詳細信息。 | `generation_id` |

#### 緩存運行

| 工具 | 描述 | 所需參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出項目嘅緩存運行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 獲取特定緩存運行嘅詳細信息。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出某個生成或緩存運行嘅模組緩存目標，顯示每個目標嘅緩存命中/未命中狀態同診斷組件哈希，包括額外嘅哈希輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 所需參數 |
|------|-------------|---------------------|
| `list_previews` | 列出項目可分享嘅應用預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 獲取預覽及其構建嘅臨時下載 URL。 | `preview_id` |
| `get_latest_preview` | 查找運行中應用二進制文件嘅最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 所需參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出項目嘅自動化警報。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 獲取自動化警報。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警報嘅修訂歷史。操作憑證會被遮蔽。 | `alert_id` |
| `list_project_notification_alerts` | 列出項目通知警報規則。需要與儀表板設置頁面相同嘅管理員權限。Webhook 地址會被遮蔽。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期嘅客戶端可以調用 `events/list` 來發現事件及其負載架構：

| 事件 | 發送時機 | 訂閱過濾器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從穩定變為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持續集成嘅 Xcode、Gradle 或 Bazel 構建以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持續集成測試執行以失敗結束，包括合併嘅分片執行或已放棄嘅執行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 運行器作業以失敗完成。 | `account_handle` |

要訂閱，客戶端需調用 `events/subscribe`，並提供事件名稱、上述 `arguments` 中列出嘅句柄，以及包含 `https://` 回調 URL 同 `whsec_` 簽名密鑰嘅 `webhook` 交付。項目事件需要帳戶成員資格及對相應測試或構建數據嘅讀取權限；運行器作業事件需要帳戶成員資格及運行器讀取權限。已聲明嘅 [`auth.md`](https://workos.com/auth-md) 訪問令牌、已聲明嘅帳戶令牌同瀏覽器授權授予可以創建訂閱；當相關憑證不再有效時，交付將停止。每個用戶最多可以保留 25 個活躍訂閱。Tuist 會在保存訂閱之前向回調發送驗證挑戰。回調必須返回包含相同 `challenge` 值嘅對象。訂閱默認持續七天，可以通過再次訂閱來刷新，當用戶嘅訪問權限或憑證被移除時，交付將停止。可選嘅 `ttlMs` 限制在一小時到 30 天之間。Tuist 會重試超時嘅回調，並在至少三次連續超時（跨越五分鐘）後取消訂閱；恢復回調後請再次訂閱。

當事件發生時，Tuist 會將其資源標識符同儀表板 URL 發送到回調。構建同測試執行失敗還包括 `is_ci` 同 `git_branch`，因此客戶端可以忽略本地失敗或按分支過濾。構建事件包括 `build_system`；運行器作業事件包括 `workflow_job_id` 同 `workflow_run_id`。請求包括訂閱標識符同 [Standard Webhooks](https://www.standardwebhooks.com/) 簽名頭部，以便客戶端驗證其來源。Tuist 會重試失敗嘅交付，因此客戶端應使用穩定嘅 `eventId` 來丟棄重複項。負載省略測試名稱、日誌同失敗消息；客戶端可以通過上述工具獲取這些詳細信息，並決定是否通知團隊或開始調試。客戶端可以使用 `events/unsubscribe` 停止交付。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 引導你通過分析失敗模式、識別根本原因並應用針對性修正來修復不穩定測試。 |
| `compare_builds` | 引導你通過比較構建來識別性能回歸、緩存變更同構建問題。使用 Xcode、Gradle、Bazel 同 Cargo 項目嘅原生工具。Cargo 比較保留部分編譯器覆蓋率，並區分估計嘅編譯器工作量同已節省嘅時間。 |
| `compare_test_runs` | 引導你通過比較兩次測試執行來識別回歸、新失敗同不穩定測試。 |
| `compare_bundles` | 引導你通過比較兩個捆綁包來識別工件樹中嘅大小變化。 |
| `compare_test_case` | 引導你通過比較測試案例在兩個分支或時間段內嘅行為。 |
| `compare_generations` | 引導你通過比較兩次生成運行來識別性能回歸同模組緩存變更。 |
| `compare_cache_runs` | 引導你通過比較兩次緩存運行來識別緩存有效性變更同目標級別回歸。 |
| `integrate_gradle_project` | 引導你將 Tuist 集成到現有 Gradle 項目中。包括獨立嘅工具同 Gradle 身份驗證、帳戶發現、項目創建、遠程緩存策略、構建洞察同回讀驗證。 |
| `integrate_bazel_project` | 引導你創建或選擇 Bazel 項目、驗證命令行、配置遠程緩存同構建洞察，並通過 Tuist 構建數據驗證集成。 |
| `integrate_xcode_project` | 引導你將 Tuist 集成到現有 Xcode 項目中。支持 Xcode 緩存、構建洞察、測試洞察同測試分片。 |
| `ask_tuist` | 使用公開材料作為上下文，並以聚焦嘅實現同測試證據作為當前行為嘅事實來源，來回答 Tuist 問題。它需要一個 `question` 並引用修訂固定嘅證據。 |

項目數據提示接受 `account_handle` 同 `project_handle`，將調查範圍限定於特定項目。比較提示亦接受 `base` 同 `head` 參數，以指定要比較嘅兩個項目（通過 ID、儀表板 URL 或分支名稱）。`ask_tuist` 接受 `question` 而非項目參數。`integrate_gradle_project` 亦接受 `features`，即要應用嘅 Gradle 集成逗號分隔列表：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 同 `test_sharding`。`integrate_bazel_project` 接受可選嘅 `server_url`，用於自託管或本地安裝。`integrate_xcode_project` 接受包含 `xcode_cache`、`build_insights`、`test_insights` 同 `test_sharding` 嘅 `features`。

#### Gradle 集成提示功能

`integrate_gradle_project` 提示同 `get_gradle_integration_guide` 工具記錄咗完整嘅設置工作流程。伺服器嘅初始化說明亦引用咗該工具，令未枚舉提示嘅代理能夠發現它。

| 功能 | 代理配置嘅內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 嘅構建緩存，配置 Tuist 遠程緩存上傳策略，並建議僅從具有本地只讀權限嘅持續集成運行器進行上傳。 |
| `build_insights` | 應用 Tuist Gradle 插件，並在需要時配置構建分析上傳行為。 |
| `test_insights` | 應用 Tuist Gradle 插件，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 引導設置不穩定測試檢測、可選嘅 Gradle Test Retry 插件使用，以及測試隔離配置。 |
| `test_sharding` | 添加用於 `tuistPrepareTestShards`、分片矩陣生成同基於 `TUIST_SHARD_INDEX` 嘅測試執行嘅持續集成工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或者在編輯 Gradle 項目之前從請求中推斷出最小嘅有用集合。

#### Xcode 集成提示功能

`integrate_xcode_project` 提示記錄咗 Tuist 支持嘅所有 Xcode 集成：

| 功能 | 代理配置嘅內容 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成項目嘅緩存設置、手動 Xcode 緩存構建設置，以及僅限於持續集成運行器嘅上傳策略。 |
| `build_insights` | 通過 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 同可選嘅機器指標。 |
| `test_insights` | 配置 `tuist inspect test`、方案測試後置動作，以及為持續集成測試運行生成結果捆綁包。 |
| `test_sharding` | 添加帶有 `TUIST_SHARD_INDEX` 嘅 Xcode 或生成項目分片規劃同分片執行工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或者在編輯 Xcode 項目之前從請求中推斷出最小嘅有用集合。
