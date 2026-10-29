---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 MCP 端點，讓 AI 代理存取測試洞察同更多資訊。"
}
---
# 模型上下文協議

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 係一個開放標準，允許人工智能代理同外部服務同數據來源互動。佢令到好似 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 呢啲應用程式，同埋 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 呢啲編輯器可以同 Tuist 互通。

Tuist 喺 `https://tuist.dev/mcp` 提供伺服器端 Model Context Protocol 端點。將你嘅客戶端連接至該端點後，代理就可以存取你嘅 Tuist 項目數據，包括測試洞察、不穩定測試分析等等。大多數工具都係唯讀，並且範圍限於已驗證嘅 Tuist 項目數據。帳戶設定工具可以列出帳戶、建立組織、建立項目，以及將現有用戶加入組織（前提係已驗證用戶擁有所需權限）。每個工具都會標示註解，說明佢係咪唯讀、會唔會導致難以逆轉嘅變更，以及會唔會改變公共互聯網狀態。帳戶設定工具需要用戶驗證。專案令牌或普通帳戶令牌無法使用呢啲工具。當用戶喺瀏覽器中授權客戶端或聲明 `auth.md` 註冊時，Tuist 只會喺 Model Context Protocol 端點將該憑證同用戶關聯，以便設定工具完成請求嘅工作流程。

Tuist 實現咗 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求係無狀態嘅：客戶端每次請求都會發送協議元數據，並且可以直接調用工具而無需初始化。`server/discover` 會返回伺服器身份、功能、支援版本同指引。冇會話標識符或獨立事件流。使用 2025-06-18 或 2025-03-26 初始化流程嘅客戶端仍然受支援；佢哋亦都喺冇伺服器會話嘅情況下運作。

## Model Context Protocol 與 Skills 比較

Model Context Protocol 工具同 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 喺功能上可能有重疊。鑑於目前兩者之間嘅重疊情況，請為每個工作流程選擇一種方法並一致使用，而唔好喺同一個流程中混合使用兩者。

對於支援插件安裝嘅客戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 一併安裝兩者。

## 配置

喺你嘅客戶端中添加 `https://tuist.dev/mcp` 作為遠程 Model Context Protocol 伺服器。伺服器嘅初始化指引同公開伺服器卡片描述咗帶有動態客戶端註冊嘅 OAuth 2.0 同標準瀏覽器授權流程，無需代理抓取或遵循外部驗證文檔。呢啲伺服器範圍內嘅指引保持工作流程指導嘅通用性：工具驗證並唔會驗證本地命令行工具或構建系統集成，代理應該透過相關嘅 Tuist 工具驗證請求嘅變更。構建系統特定嘅設置同驗證檢查記錄喺集成指南同提示中。Tuist 仍然分別宣傳 [Open Authorization](https://oauth.net/2/) 發現元數據同當前位於 `https://tuist.dev/auth.md` 嘅 [auth.md protocol](https://workos.com/auth-md)。

該端點接受無狀態嘅 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），同時亦支援較舊嘅基於會話嘅生命週期。現有客戶端可以繼續使用佢哋當前嘅連接方法。

支援 Model Context Protocol 事件嘅客戶端可以訂閱項目事件。請參閱 [Events](#events) 以了解可用事件同交付要求。

已經支援遠程瀏覽器驗證嘅客戶端可以繼續喺瀏覽器中進行驗證。支援 `auth.md` 嘅客戶端同代理可以匿名註冊、出示受信任嘅提供者身份斷言，或啟動服務驗證嘅電子郵件聲明。註冊會返回由 Tuist 簽署嘅身份斷言，代理可以喺標準令牌端點將其交換為一小時嘅訪問令牌。Tuist 發佈其公共簽名密鑰，並支援標準令牌撤銷同提供者安全事件交付。

未驗證嘅代理應該讀取 Model Context Protocol 端點返回嘅 `WWW-Authenticate` 標頭，獲取受保護資源元數據，獲取授權伺服器元數據，並遵循其 `agent_auth.skill` URL。Tuist 亦會喺未授權響應正文中返回相同嘅本地 `auth_md` URL，以便由語言模型驅動嘅客戶端可以發現該流程，而無需依賴本機客戶端集成。部署本地文檔係端點名稱、請求主體、聲明輪詢同斷言交換嘅真實來源。

喺代理啟動電子郵件聲明之前，必須要求用戶確認佢哋 Tuist 帳戶嘅電子郵件地址。佢唔可以從提供者個人資料、Git 配置、環境變量或會話元數據中推斷該地址。

該端點使用 `mcp` 範圍組。匿名預聲明憑證可以發現功能並閱讀公共集成指南，但唔會被視為已登錄用戶。喺瀏覽器授權或聲明之後，憑證係用戶範圍嘅，並且每個工具都會應用同儀表板相同嘅授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析為已驗證用戶已經可以讀取嘅項目。Xcode 同 Gradle 構建工具接受構建 UUID 或儀表板 URL。UUID 必須唯一標識一個項目；如果佢出現喺多個項目中，工具會返回未找到，而唔係選擇另一個項目嘅報告。項目範圍嘅儀表板同 API 讀取仍然可用。報告嘅參與者標識符係未經驗證嘅標籤，並唔係憑證或額外訪問權限。

Tuist 運營人員調查客戶帳戶時，係透過 Tuist 內部運營工具進行，該工具會記錄每次調用；直接連接到此端點不會獲得超出用戶自身成員資格之外嘅任何訪問權限。

<details>
<summary>Claude Code</summary>

運行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 客戶端未向模型公開失敗嘅本機伺服器連接時，要求代理喺搜尋託管文檔或編輯項目之前，檢查已配置端點嘅未經認證 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 響應。即使瀏覽器認證不可用，該響應亦會將模型指向部署本地嘅 `auth.md` 文檔。

</details>


<details>
<summary>Codex</summary>

運行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

喺開始新嘅 `codex exec` 運行之前完成瀏覽器登錄。Codex 喺初始化期間讀取 Tuist 伺服器指令，因此 Gradle 優化請求會自動接收認證同驗證工作流程。

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

Pi 唔包含 Model Context Protocol 客戶端。喺審查其源代碼同安全影響後，你可以安裝第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 擴展：

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

將 `auth` 設置為 `false` 可防止適配器嘅瀏覽器認證處理程序隱藏 Tuist 嘅未授權響應。無頭代理隨後可以讀取返回嘅 `auth_md` URL，並遵循 Tuist 嘅註冊、身份斷言交換同聲明輪詢流程。將交換嘅訪問令牌配置為 bearer token，或讓代理直接進行經過認證嘅 Model Context Protocol 調用。

如果你偏好瀏覽器認證，將 `auth` 設置為 `"oauth"`。對於該流程，喺認證完成期間保持一個進程通過 Pi 嘅 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 存活：

```bash
pi --mode rpc
```

唔好將待定嘅瀏覽器認證拆分到單獨嘅 `pi --print` 調用中，因為擁有回調狀態嘅進程已經退出。

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

使用 **Command Palette → MCP: Add Server**，然後配置具有以下設置嘅 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 伺服器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

打開 **Agent panel → Settings → Add Custom Server**，然後設置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果你嘅代理支持 `auth.md`，佢可以匿名啟動而無需打開瀏覽器。當提供者身份已經鏈接時，受信任嘅提供者身份亦可以無需瀏覽器即可完成。對於服務認證電子郵件、匿名聲明或首次提供者鏈接，代理會向你顯示 Tuist 驗證鏈接同六位數代碼。打開鏈接，登錄，並喺 Tuist 頁面上輸入代理嘅代碼。切勿將代碼發送回代理。Tuist 嘅授權伺服器元數據直接指向部署自己嘅 `/auth.md`，其中包含精確嘅請求同輪詢結構。

## 構建系統集成使用兩個憑證

用於 Model Context Protocol 工具嘅憑證唔會認證 Gradle 插件或 Bazel 嘅遠程服務。喺代理編輯或驗證 Gradle 或 Bazel 集成之前，佢應該運行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未經認證，代理必須停止並要求用戶運行：

```bash
tuist auth login --url https://tuist.dev
```

對於本地或自託管部署，替換兩個命令同 `tuist.toml` 中嘅 URL。保持主機名拼寫喺各處一致。例如，`localhost` 同 `127.0.0.1` 使用單獨存儲嘅憑證。


## 功能

### 工具

以下工具可通過 Tuist Model Context Protocol 伺服器使用：

每個工具都發布人類可讀嘅描述以及明確嘅輸入同輸出架構。成功調用返回符合所宣傳輸出架構嘅結構化內容，以及序列化為文本嘅相同結果，以供尚未消費結構化內容嘅客戶端使用。

接受單個記錄標識符（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）嘅工具亦接受該記錄嘅 Tuist 儀表板 URL。直接從瀏覽器粘貼 URL，而唔係從中提取標識符。

#### 文檔同社區搜索

呢個只讀工具通過驅動文檔網站嘅同一搜索引擎，搜索 Tuist 嘅文檔、[application programming interface](https://en.wikipedia.org/wiki/API) 參考、GitHub 發布版本、社區論壇同 GitHub issues。發布結果包括產品、版本、發布日期同預發布狀態。默認搜索穩定版本，可以使用 `include_prereleases` 包含預發布版本。該工具僅喺 `https://tuist.dev/mcp` 上嘅 Tuist 託管伺服器可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公開嘅 Tuist 文檔、application programming interface 參考、GitHub 發布版本、社區討論同 GitHub issues。可選限制為一個 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 基於源代碼嘅回答

呢啲只讀工具讓代理使用與託管伺服器一齊部署嘅精確公開 Tuist 源代碼修訂版本，作為依賴當前行為嘅回答嘅事實來源。它們僅喺 `https://tuist.dev/mcp` 可用。

兼容嘅客戶端喺初始化期間接收工具源代碼修訂版本、鏈接同結果限制嘅事實描述，以及內聯 OAuth 認證信息。呢啲描述唔規定回答風格或驗證工作流程。用戶可以直接提問而無需先調用 `ask_tuist` 提示；該提示仍然可用於明確嘅基於源代碼嘅工作流程。

每個操作都有固定嘅併發、持續時間、遍歷、讀取字節數同響應大小限制。搜索同列表結果包括 `truncated` 同 `truncation_reason` 字段。當結果被截斷時，縮小路徑、文件模式或搜索詞，而唔係將結果視為詳盡。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 通過搜索源文件回答關於當前行為、默認值、配置、功能開關、錯誤處理或未記錄細節嘅問題。結果包括周圍行、修訂綁定嘅源代碼鏈接同掃描統計信息。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，發現源子系統或附近嘅測試。列表具有有限嘅深度同結果數量。 | 無 |
| `read_tuist_file` | 喺找到相關路徑後，檢查實現文件、調用站點或測試中嘅聚焦行範圍。截斷嘅響應提供 `next_start_line` 以繼續。 | `path` |

#### 項目

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出 authenticated user 可用嘅個人同組織帳戶句柄，包括每個帳戶是否可以創建項目。 | 無 |
| `get_organization` | 獲取組織嘅成員目錄。待處理邀請需要與儀表板相同嘅管理員權限；邀請接受令牌永遠唔會返回。 | `account_handle` |
| `create_organization` | 為 authenticated user 創建 Tuist 組織。 | `handle` |
| `create_project` | 喺 authenticated user 可以訪問嘅帳戶下創建 Tuist 項目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有 Tuist 用戶添加到組織或更新現有成員嘅角色。接受 `user`（默認）、`admin` 或 `viewer`，其中 viewer 可以閱讀儀表板同運行但唔能更改任何內容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論其是否屬於現有 Tuist 用戶。Tuist 會發送一個 14 天後過期嘅接受鏈接；當伺服器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製鏈接。接受 `user`（默認）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理嘅組織邀請，使其鏈接無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出 authenticated user 可訪問嘅所有項目。 | 無 |
| `get_project` | 獲取項目嘅配置同連接嘅存儲庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將項目鏈接到帳戶嘅 GitHub App 安裝可以訪問嘅 GitHub 存儲庫。項目採用存儲庫嘅默認分支。需要項目管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 刪除項目與其 GitHub 存儲庫嘅鏈接。需要項目管理員權限。 | `account_handle`, `project_handle` |

#### 帳戶令牌

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳戶令牌元數據而唔暴露令牌值。 | `account_handle` |
| `get_account_token` | 獲取帳戶令牌元數據而唔暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出項目令牌元數據而唔暴露令牌值。 | `account_handle`, `project_handle` |

#### 持續集成 runner

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳戶嘅持續集成 runner 作業。 | `account_handle` |
| `get_runner_job` | 獲取一個持續集成 runner 作業。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續集成 runner 作業記錄嘅步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續集成 runner 作業記錄嘅機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續集成 runner 作業最多 500 條捕獲嘅日誌行。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳戶嘅持續集成工作流程匯總。 | `account_handle` |
| `list_runner_profiles` | 列出帳戶嘅持續集成 runner 配置文件，包括每個配置文件嘅 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出 runner 配置文件可以使用嘅機器規格同 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 創建一個包含平台、機器規格，以及喺 macOS 上嘅 Xcode 版本嘅 runner 配置文件。可選設置哪些分支保存其緩存卷。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改 runner 配置文件嘅機器規格、Xcode 版本，或哪些分支保存其自定義緩存卷更改。省略嘅字段保持其值。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 喺用戶確認後刪除 runner 配置文件。默認配置文件無法刪除。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

Runner 卷工具公開與 Volumes 儀表板相同嘅數據。讀取工具需要 runner 訪問權限；清除需要帳戶管理權限或 `account:runners:write` 範圍，以及用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名稱同存儲庫過濾，對卷進行排序同分頁。 | `account_handle` |
| `get_runner_volume` | 存儲庫、平台、容量、已用空間同最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁嘅作業同工作流程引用、緩存狀態、命中結果同掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作業掛載嘅卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存儲序列、作業運行、命中率同趨勢。可選 `volume_id`、`start` 同 `end`（ISO 8601）；默認為七天，最多 90 天。 | `account_handle` |
| `clear_runner_volume` | 清除已保存嘅內容。運行中嘅作業保留其私有副本但無法保存；後續作業將從空開始。 | `account_handle`, `volume_id` |

列表接受 `page` 同 `page_size`（最多 100）。卷庫存還接受 `name` 同 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）同 `sort_order`（`asc`、`desc`）。未知測量值同命中結果保持為 `null`。緩存狀態描述卷更改是否已保存，而非作業成功與否。

#### Webhooks

Webhook 工具使用與儀表板相同嘅僅管理員權限。交付嘗試包含為端點記錄嘅請求同響應數據，但永遠唔包含端點簽名密鑰。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳戶嘅 webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 獲取一個 webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點嘅交付嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 獲取一次交付嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 構建

用於 Xcode、Gradle、Bazel、Mix 同 Cargo 嘅構建詳情工具公開現有嘅 `custom_metadata: {tags, values}` 結構，包括報告時嘅基礎設施觀察結果。值保持為字符串，並保留不熟悉嘅鍵。例如，`tuist.cpu.available_processors` 描述運行時可用嘅邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作器限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆限制，而非主機內存。這些是未受信任嘅客戶端觀察結果，而非經過驗證嘅 runner 身份。缺失嘅觀察結果保持缺失；導入嘅日誌同較舊嘅客戶端可能沒有基礎設施元數據。元數據更新等待協調嘅客戶端/協議更新。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出項目嘅 Xcode 構建運行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 獲取特定 Xcode 構建運行嘅詳細信息，包括保存原始 `.xcactivitylog` 嘅歸檔文件嘅臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 構建運行嘅構建目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 構建運行嘅編譯文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄嘅構建步驟，包含時間同結果，但唔包含日誌文本。 | `build_run_id` |
| `get_xcode_build_step` | 獲取一個記錄嘅構建步驟，包括其日誌同截斷標誌。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定構建運行嘅構建問題（警告同錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 構建運行嘅可緩存任務（緩存命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 構建運行嘅 [內容尋址存儲](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 默認返回每頁 20 個步驟（通過 `page_size` 最多可設為 100），並提供 `page` 同 `pagination_metadata` 用於導航。使用 `search` 匹配標題、項目或目標，或過濾精確嘅 `project`、`target`、`category`（例如 `swiftCompilation`）同 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以最慢優先（默認），或按 `start_ms` 排序以獲得時間順序。步驟 ID 用於打破平局，並以十進制字符串形式返回以保留其完整嘅 64 位精度。ID 僅限於單一構建，不應跨構建匹配。

可選嘅 `start_ms` 同 `end_ms` 選擇與從構建開始計算嘅毫秒時間範圍重疊嘅步驟；結束時間為互斥。兩個工具都接受構建 UUID 或儀表板 URL 作為 `build_run_id`。將返回嘅步驟 `id` 原樣傳遞為 `step_id` 以檢索其日誌。日誌每步最多保留 64 KiB，`log_truncated` 表示已省略嘅輸出。

處理 Xcode 構建時默認會收集步驟。記錄嘅步驟數據保留 90 天。列表響應包括 `availability`：當存在記錄嘅步驟時為 `available`，即使過濾器無匹配項；當構建仍在處理且尚無步驟時為 `processing`；或當步驟未記錄或已過期時為 `unavailable`。

相同嘅操作可通過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 同 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上獲得，具有相同嘅過濾器同分頁功能。兩者都需要對構建項目嘅讀取權限。

#### Gradle 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整嘅身份驗證、項目設置、Gradle 插件、緩存策略同兩次構建驗證工作流程。代理應在編輯現有 Android 或 Gradle 項目之前調用此接口。 | 無 |
| `list_gradle_builds` | 列出項目嘅 Gradle 構建運行，包括自定義元數據。使用可選嘅 `tag` 參數按自定義標籤過濾。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 獲取構建元數據同任務/緩存計數。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任務結果、複合構建身份、可緩存性同增量狀態。 | `build_run_id` |
| `list_gradle_build_steps` | 列出帶時間嘅任務、配置同轉換，支持搜索、元數據同重疊時間過濾器。 | `build_run_id` |
| `get_gradle_build_step` | 通過不透明 ID 檢查記錄嘅步驟元數據；無法獲取每步日誌。 | `build_run_id`, `step_id` |

Gradle 同 Bazel 步驟列表默認為 20 個結果（最多 100），支持 `search`、精確嘅 `project`、`target`、`category` 同 `status`、重疊嘅 `start_ms` / `end_ms` 過濾器（結束互斥），以及 `duration_ms` 或 `start_ms` 排序。原樣傳遞返回嘅 ID；它們限於各自嘅構建。列表公開 `time_origin` 同 `coverage`。較舊嘅 Gradle 報告使用 `first_recorded_timestamp`，因為無上傳構建開始時間。Bazel 配置文件通過 `trace_profile` 覆蓋範圍同作為時間起點嘅 `profile_start` 公開所有記錄嘅間隔。較舊嘅構建回退到保留嘅 BEP 摘要。源記錄在 90 天後過期。Bazel 詳情在發布時包括清理後嘅操作日誌；Gradle 詳情 `log` 為 null。`compare_builds` 提示使用此覆蓋範圍來區分完整嘅 Bazel 追蹤同保留嘅摘要，並指導代理在檢查更廣泛嘅調用輸出之前查看步驟詳情以獲取操作結果同日誌。

如果在列出同獲取步驟之間到達了完整配置文件，則從保留摘要返回嘅 Bazel 步驟 ID 仍然可讀。如果步驟數據已過期，索引配置文件將報告為不可用。Gradle 步驟列表包括零持續時間嘅緩存同跳過操作。

#### Bazel 調用

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份驗證、項目設置、Bazel 配置同驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成嘅 [Bazel 構建事件協議](https://bazel.build/remote/bep) 調用，包括構建指標、有限執行時間線、關鍵路徑診斷同項目相關嘅遠程緩存總數。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 獲取一個已完成嘅 Bazel 調用，包括構建指標、有限執行時間線、關鍵路徑診斷同相關嘅遠程緩存總數。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄嘅 Bazel 配置文件間隔，帶有過濾器同明確嘅覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄嘅 Bazel 步驟及其發布嘅操作結果同清理後嘅日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按執行順序列出為 Bazel 調用捕獲嘅清理後測試日誌。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 獲取為 Bazel 調用捕獲嘅一個清理後測試日誌。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始 Bazel 遠程緩存觀察結果，包括其操作、端點同觀察時間，可選地縮小到特定調用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 獲取一個原始 Bazel 遠程緩存觀察結果。 | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargo 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出項目嘅 Cargo 構建，按最新排序。可按 `git_branch`、`status`、`is_ci` 或 `command` 過濾。個別測試運行可通過測試工具獲取，唔係通過此構建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 獲取構建元數據同聚合緩存計數器，包括命中、任務未命中同命中率。 | `account_handle`, `project_handle`, `build_id` |

#### Mix 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出項目嘅 Mix (Elixir) 編譯構建，按最新排序，包括自定義元數據。可按 `git_branch`、`status`、`is_ci` 或 `mix_env` 過濾。 | `account_handle`, `project_handle` |
| `get_mix_build` | 獲取構建元數據、診斷計數同依賴緩存摘要。 | `account_handle`, `project_handle`, `build_id` |

#### Once 運行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出項目嘅 Once 運行，按最新排序。可按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 過濾。未完成嘅運行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 獲取運行及其操作總數、緩存摘要，對於測試運行則包括測試總數。 | `account_handle`, `project_handle`, `run_id` |

Cargo 構建、Mix 構建同 Once 運行 ID 在項目內唯一。相同嘅讀取可通過 HTTP API 於 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 同 `.../once/runs` 獲取，每個都有一個用於單一 ID 嘅詳細端點。

#### 任務、操作、模塊同文件

呢啲項目範圍嘅工具檢查跨運行嘅持久構建身份。首先使用 `list_build_entities`，然後將返回嘅穩定 `id` 連同相同嘅 `kind` 傳遞畀 `get_build_entity` 或 `list_build_entity_history`，並加上 `account_handle` 同 `project_handle`。唔需要構建或調用標識符。

| 工具 | 描述 | 必需參數 |
| --- | --- | --- |
| `list_build_entities` | 列出在項目構建中看到嘅某一類任務、模塊、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 獲取一個構建實體及其本機身份同所選時期嘅分析數據。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個構建實體嘅記錄執行、編譯或緩存事件，按最新排序。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 報告嘅操作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模塊 | 編譯同模塊緩存事件 |
| `once_actions` | Once 操作 | 執行 |
| `mix_files` | Mix 編譯文件 | 編譯 |
| `mix_modules` | Mix 編譯模塊 | 編譯 |

呢啲工具正逐步推出，只返回已啟用佢哋嘅項目數據；對於其他項目，佢哋會返回錯誤而非空結果。某一類只適用於使用其構建工具鏈嘅項目。工具接受有界嘅 `start_at`/`end_at` 過濾器、`environment`（`any`、`ci` 或 `local`）同精確嘅 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支援不透明嘅 `after`/`before` 游標。未知嘅計時或緩存觀察結果保持不可用，而唔係變成零或未命中。歷史記錄引用記錄嘅父級同本機執行，以便使用現有運行工具進行深入分析。

`get_build_entity` 指標包括 `duration_samples`，即具有記錄計時嘅觀察次數：真實嘅零持續時間會計數，缺失計時則唔會。此計數可能低於觀察次數；不可用嘅持續時間統計數據保持為 null。

Xcode 模塊持續時間來自構建日誌中測量嘅目標編譯。模塊緩存解析同沒有編譯工作嘅目標唔會貢獻持續時間樣本。編譯觀察引用 Xcode 構建；緩存事件引用生成或緩存命令。

Bazel 操作由目標標籤、助記符同配置嘅主要輸出標識，保持單獨嘅操作同配置區分開來，而唔依賴於輸入相關嘅緩存摘要。歷史記錄 BEP 報告嘅執行，而唔係緩存查找或跟踪配置文件階段。完整嘅執行覆蓋需要 `--build_event_publish_all_actions`；工件交付係盡力而為，所以缺失觀察並唔係沒有工作運行嘅證據。較舊嘅 Kura 負載如果沒有穩定身份或執行開始仍然被接受但未被索引。缺少結束時間測量保持不可用，真實嘅零持續時間會計數。

Mix 模塊持續時間測量包含文件嘅編譯，而唔係獨立測量嘅模塊工作。Once 操作在客戶端報告目標映射時使用聲明嘅目標/能力/索引槽；僅診斷標籤並唔係穩定身份。現有客戶端同運行級別工具保持不變地受支援。

分析讀取具有有界嘅內存同執行時間。如果查詢超過這些限制，工具將返回錯誤而唔係憑空產生空結果。

新觀察在部署後被索引；此功能唔會回填現有運行遙測。身份元數據在 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link> 下比單個觀察更長久。

#### 測試

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出項目嘅測試運行。`query` 字段係 `git_branch`、`scheme` 同 `status`：`field:"value"` 精確匹配，`field~"value"` 匹配不區分大小寫嘅子字符串，前導 `-` 否定任一運算符。例如，`-git_branch~"gh-readonly-queue"` 排除合併隊列分支。空格分隔嘅查詢過濾器同顯式參數以 AND 語義組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 獲取測試運行嘅詳細指標，包括其結果包 (`.xcresult`) 同會話歸檔嘅臨時下載 URL。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試運行嘅測試模塊運行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試運行嘅測試套件運行，可選按模塊過濾。 | `test_run_id` |
| `list_test_cases` | 列出項目嘅測試案例（支援如 `flaky` 等過濾器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 獲取測試案例嘅詳細指標，包括可靠性率、不穩定率同運行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例運行，可選按測試案例或測試運行過濾。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 獲取特定測試案例運行嘅失敗詳情同重複次數。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例運行嘅附件。每個附件包括一個臨時下載 URL。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例嘅狀態更改，例如靜音或跳過它。 | `test_case_id` |
| `update_test_case` | 更新測試案例嘅狀態或不穩定分類。更改可以將事件分發到配置嘅 webhook 端點，包括外部服務。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試運行嘅選擇性測試目標結果。 | `test_run_id` |
| `get_coverage` | 獲取項目嘅代碼覆蓋率及其目標，在提交時或分支嘅最新完整提交時。沒有 `git_commit_sha` 或 `branch`，它會讀取默認分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出提交時代碼覆蓋率測量嘅文件及其行覆蓋率，在提交時或分支嘅最新完整提交時。支援 `search`、排序同分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 獲取文件嘅代碼覆蓋率及其函數，在提交時或分支嘅最新完整提交時。設置 `include_lines` 以獲取每行嘅執行計數。 | `account_handle`, `project_handle`, `path` |

代碼覆蓋率工具適用於已啟用代碼覆蓋率嘅帳戶。

#### 捆綁包

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出項目嘅捆綁包（應用二進製文件）。 | `account_handle`, `project_handle` |
| `get_bundle` | 獲取特定捆綁包嘅詳細信息。 | `bundle_id` |
| `get_bundle_artifact_tree` | 獲取捆綁包嘅完整工件樹，作為按路徑排序嘅平面列表。 | `bundle_id` |

#### 生成

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_generations` | 列出項目嘅生成運行。 | `account_handle`, `project_handle` |
| `get_generation` | 獲取特定生成運行嘅詳細信息。 | `generation_id` |

#### 快取運行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出項目嘅快取運行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 獲取特定快取運行嘅詳細信息。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出生成或快取運行嘅模塊快取目標，顯示每個目標嘅快取命中/未命中狀態同診斷組件哈希，包括額外嘅哈希輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_previews` | 列出項目嘅可共享應用預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 獲取預覽及其構建嘅臨時下載 URL。 | `preview_id` |
| `get_latest_preview` | 查找運行中應用二進製文件嘅最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出項目嘅自動化警報。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 獲取自動化警報。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警報嘅修訂歷史。操作憑證已被遮蔽。 | `alert_id` |
| `list_project_notification_alerts` | 列出項目通知警報規則。需要與儀表板設置頁面相同嘅管理員權限。Webhook 地址已被遮蔽。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期嘅客戶端可以調用 `events/list` 來發現事件及其負載架構：

| 事件 | 發送時機 | 訂閱過濾器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從穩定變為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持續集成嘅 Xcode、Gradle 或 Bazel 構建以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持續集成嘅測試運行以失敗結束，包括合併嘅分片運行或已放棄嘅運行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 運行器作業以失敗完成。 | `account_handle` |

要訂閱，客戶端調用 `events/subscribe`，帶上事件名稱、上面 `arguments` 中列出嘅句柄，以及包含 `https://` 回調 URL 同 `whsec_` 簽名密鑰嘅 `webhook` 交付。項目事件需要帳戶成員資格同對相應測試或構建數據嘅讀取權限；運行器作業事件需要帳戶成員資格同運行器讀取權限。聲稱嘅 [`auth.md`](https://workos.com/auth-md) 訪問令牌、聲稱嘅帳戶令牌同瀏覽器授權授予可以創建訂閱；當相關憑證不再有效時，交付停止。每個用戶最多可以保留 25 個活動訂閱。Tuist 在保存訂閱之前向回調發送驗證挑戰。回調必須返回包含相同 `challenge` 值嘅對象。訂閱默認持續七天，可以通過再次訂閱來刷新，當用戶嘅訪問權限或憑證被移除時停止交付。可選嘅 `ttlMs` 限制在一小時到 30 天之間。Tuist 會重試超時嘅回調，並在至少三次連續超時（跨越五分鐘）後取消訂閱；恢復回調後請再次訂閱。

當事件發生時，Tuist 將其資源標識符同儀表板 URL 發送到回調。構建同測試運行失敗還包括 `is_ci` 同 `git_branch`，因此客戶端可以忽略本地失敗或按分支過濾。構建事件包括 `build_system`；運行器作業事件包括 `workflow_job_id` 同 `workflow_run_id`。請求包括訂閱標識符同 [Standard Webhooks](https://www.standardwebhooks.com/) 簽名標頭，以便客戶端驗證其來源。Tuist 會重試失敗嘅交付，因此客戶端應使用穩定嘅 `eventId` 來丟棄重複項。負載省略測試名稱、日誌同失敗消息；客戶端可以通過上述工具獲取這些詳情，並決定是否通知團隊或開始調試。客戶端可以使用 `events/unsubscribe` 停止交付。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 引導你修復不穩定測試，包括分析失敗模式、識別根本原因並應用針對性修正。 |
| `compare_builds` | 引導你比較兩次構建運行，以識別性能回歸、緩存變更同構建問題。適用於 Xcode 同 Gradle 項目。 |
| `compare_test_runs` | 引導你比較兩次測試運行，以識別回歸、新出現嘅失敗同不穩定測試。 |
| `compare_bundles` | 引導你比較兩個捆綁包，以識別構件樹中嘅大小變化。 |
| `compare_test_case` | 引導你比較測試案例在兩個分支或時間段內嘅行為。 |
| `compare_generations` | 引導你比較兩次生成運行，以識別性能回歸同模塊緩存變更。 |
| `compare_cache_runs` | 引導你比較兩次緩存運行，以識別緩存效率變更同目標級別回歸。 |
| `integrate_gradle_project` | 引導你將 Tuist 集成到現有 Gradle 項目中。包括獨立工具同 Gradle 身份驗證、帳戶發現、項目創建、遠程緩存策略、構建洞察同讀回驗證。 |
| `integrate_bazel_project` | 引導你創建或選擇 Bazel 項目、驗證命令行、配置遠程緩存同構建洞察，並通過 Tuist 構建數據驗證集成。 |
| `integrate_xcode_project` | 引導你將 Tuist 集成到現有 Xcode 項目中。支持 Xcode 緩存、構建洞察、測試洞察同測試分片。 |
| `ask_tuist` | 使用公開材料作為上下文，並以聚焦嘅實現同測試證據作為當前行為嘅事實來源，來回答 Tuist 問題。它需要 `question` 並引用修訂鎖定嘅證據。 |

項目數據提示接受 `account_handle` 同 `project_handle`，將調查範圍限定於特定項目。比較提示還接受 `base` 同 `head` 參數，以指定要比較嘅兩個項目（按 ID、儀表板 URL 或分支名稱）。`ask_tuist` 接受 `question` 而非項目參數。`integrate_gradle_project` 還接受 `features`，即要應用嘅 Gradle 集成嘅逗號分隔列表：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 同 `test_sharding`。`integrate_bazel_project` 接受可選嘅 `server_url`，用於自託管或本地安裝。`integrate_xcode_project` 接受帶有 `xcode_cache`、`build_insights`、`test_insights` 同 `test_sharding` 嘅 `features`。

#### Gradle 集成提示功能

`integrate_gradle_project` 提示同 `get_gradle_integration_guide` 工具記錄咗完整嘅設置工作流程。該工具還被服務器嘅初始化指令引用，這使得未枚舉提示嘅代理也能發現它。

| 功能 | 代理配置內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 嘅構建緩存，配置 Tuist 遠程緩存上傳策略，並建議僅從具有本地只讀權限嘅持續集成運行器進行上傳。 |
| `build_insights` | 應用 Tuist Gradle 插件，並在需要時配置構建分析上傳行為。 |
| `test_insights` | 應用 Tuist Gradle 插件，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 引導設置不穩定測試檢測、可選嘅 Gradle Test Retry 插件使用同測試隔離配置。 |
| `test_sharding` | 添加 `tuistPrepareTestShards`、分片矩陣生成同基於 `TUIST_SHARD_INDEX` 嘅測試執行嘅持續集成工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或在編輯 Gradle 項目之前從請求中推斷出最小有用集。

#### Xcode 集成提示功能

`integrate_xcode_project` 提示記錄咗 Tuist 支持嘅每種 Xcode 集成：

| 功能 | 代理配置內容 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成項目緩存設置、手動 Xcode 緩存構建設置，以及僅限於持續集成運行器嘅上傳策略。 |
| `build_insights` | 通過 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 同可選嘅機器指標。 |
| `test_insights` | 為持續集成測試運行配置 `tuist inspect test`、方案測試後操作同結果捆綁包生成。 |
| `test_sharding` | 添加帶有 `TUIST_SHARD_INDEX` 嘅 Xcode 或生成項目分片規劃同分片執行工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或在編輯 Xcode 項目之前從請求中推斷出最小有用集。
