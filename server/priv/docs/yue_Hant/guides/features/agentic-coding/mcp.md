---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 MCP 端點，讓 AI 代理存取測試洞察等功能。"
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 係一個開放標準，讓人工智能代理可以同外部服務同數據來源互動。佢令到好似 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 呢啲應用程式，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 呢啲編輯器，可以同 Tuist 互通。

Tuist 喺 `https://tuist.dev/mcp` 提供伺服器端 Model Context Protocol 端點。將你嘅客戶端連接到此端點後，代理就可以存取你嘅 Tuist 項目數據，包括測試洞察、不穩定測試分析等等。大多數工具都係唯讀，並且範圍限於已驗證嘅 Tuist 項目數據。帳戶設定工具可以列出帳戶、建立組織、建立項目，以及將現有用戶加入組織（前提係已驗證用戶擁有所需權限）。每個工具都會標註佢係咪唯讀、會唔會導致難以逆轉嘅變更，以及會唔會改變公開互聯網狀態。帳戶設定工具需要用戶驗證。項目令牌或普通帳戶令牌無法使用呢啲工具。當用戶喺瀏覽器中授權客戶端或聲明 `auth.md` 註冊時，Tuist 只會喺 Model Context Protocol 端點將該憑證同用戶關聯，以便設定工具完成請求嘅工作流程。

Tuist 實現咗 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求係無狀態嘅：客戶端每次請求都會發送協議元數據，並且可以直接調用工具而無需初始化。`server/discover` 會返回伺服器身份、功能、支持嘅版本同說明。冇會話標識符或獨立事件流。使用 2025-06-18 或 2025-03-26 初始化流程嘅客戶端仍然受支持；佢哋亦都係喺冇伺服器會話嘅情況下運作。

## Model Context Protocol 與 skills 比較

Model Context Protocol 工具同 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 喺功能上可能有重疊。鑑於目前兩者之間存在重疊，請為每個工作流程選擇一種方法並一致使用，而唔好喺同一個流程中混合使用兩者。

對於支持插件安裝嘅客戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 一併安裝兩者。

## 配置

喺你嘅客戶端中添加 `https://tuist.dev/mcp` 作為遠程 Model Context Protocol 伺服器。伺服器嘅初始化說明同公開伺服器卡片描述咗帶有動態客戶端註冊嘅 OAuth 2.0 同標準瀏覽器授權流程，無需代理去獲取或跟隨外部驗證文檔。呢啲伺服器範圍嘅說明保持工作流程指引嘅通用性：工具驗證並唔會驗證本地命令行工具或構建系統集成，代理應該通過相關嘅 Tuist 工具驗證請求嘅變更。特定構建系統嘅設置同驗證檢查記錄喺集成指南同提示中。Tuist 仍然分別宣傳 [Open Authorization](https://oauth.net/2/) 發現元數據同當前位於 `https://tuist.dev/auth.md` 嘅 [auth.md protocol](https://workos.com/auth-md)。

如果你嘅其中一個組織強制執行單一登錄，喺瀏覽器中授權客戶端需要通過該組織登入嘅會話，必要時 Tuist 會先將你轉發到提供者。請參閱 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>。

該端點接受無狀態嘅 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），同時亦支持較舊嘅基於會話嘅生命週期。現有客戶端可以繼續使用佢哋當前嘅連接方法。

支持 Model Context Protocol 事件嘅客戶端可以訂閱項目事件。有關可用事件同交付要求，請參閱 [Events](#events)。

已經支持遠程瀏覽器驗證嘅客戶端可以繼續喺瀏覽器中進行驗證。支持 `auth.md` 嘅客戶端同代理可以匿名註冊、提交受信任嘅提供者身份斷言，或者啟動服務驗證嘅電子郵件聲明。註冊會返回一個由 Tuist 簽署嘅身份斷言，代理可以喺標準令牌端點將其交換為一小時有效嘅訪問令牌。Tuist 發布其公開簽名密鑰，並支持標準令牌撤銷同提供者安全事件交付。

未經驗證嘅代理應該讀取 Model Context Protocol 端點返回嘅 `WWW-Authenticate` 標頭，獲取受保護資源元數據，獲取授權伺服器元數據，並跟隨其 `agent_auth.skill` URL。Tuist 亦會喺未授權響應正文中返回相同嘅本地 `auth_md` URL，以便由語言模型驅動嘅客戶端可以發現該流程，而無需依賴原生客戶端集成。部署本地文檔係端點名稱、請求主體、聲明輪詢同斷言交換嘅事實來源。

喺代理開始電子郵件聲明之前，必須要求用戶確認其 Tuist 帳戶嘅電子郵件地址。代理不得從提供者個人資料、Git 配置、環境變量或會話元數據中推斷該地址。

該端點使用 `mcp` 範圍組。匿名預聲明憑證可以發現功能並閱讀公開集成指南，但唔會被視為已登入用戶。喺瀏覽器授權或聲明之後，憑證具有用戶範圍，並且每個工具都會應用同儀表板相同嘅授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析到已驗證用戶已經可以讀取嘅項目。Xcode 同 Gradle 構建工具接受構建 UUID 或儀表板 URL。UUID 必須唯一標識一個項目；如果佢出現喺多個項目中，工具會返回未找到，而唔係選擇另一個項目嘅報告。項目範圍嘅儀表板同 API 讀取仍然可用。報告嘅參與者標識符係未經驗證嘅標籤，並唔係憑證或額外訪問權限。

構建列表同詳細工具會公開可選嘅 `tuist_version` 元數據：針對 Xcode 同 Cargo 嘅報告 Tuist CLI、針對 Gradle 嘅 Tuist Gradle 插件，以及針對 Mix 嘅 `tuist_ex` 庫。Xcode 亦會從其關聯嘅項目生成事件中公開 `tuist_generation_version`，該值可能與上傳 CLI 不同。缺失嘅觀察值為 null，唔會從伺服器或其他報告中推斷。Bazel 使用其現有嘅 `bazel_version`；Once 運行詳情會公開 `once_version`。這些字段描述報告嘅版本，並唔係已驗證身份或線路合約版本。REST 構建端點公開相同嘅元數據。現有集成同不穩定測試技能唔依賴版本字段，無需更改工作流程。

Tuist 運營人員通過 Tuist 內部運營工具調查客戶帳戶，該工具會記錄每次調用；直接連接到此端點無法獲得超出用戶自身成員資格之外嘅訪問權限。

<details>
<summary>Claude Code</summary>

運行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 客戶端未向模型暴露失敗嘅原生伺服器連接時，要求代理喺搜索託管文檔或編輯項目之前，檢查配置端點嘅未經驗證 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 響應。即使瀏覽器驗證不可用，該響應亦會將模型指向部署本地嘅 `auth.md` 文檔。

</details>


<details>
<summary>Codex</summary>

運行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

喺開始新嘅 `codex exec` 運行之前完成瀏覽器登入。Codex 喺初始化期間讀取 Tuist 伺服器指令，因此 Gradle 優化請求會自動接收驗證同核實工作流程。

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

將 `auth` 設置為 `false` 可以防止適配器嘅瀏覽器驗證處理程序隱藏 Tuist 嘅未授權響應。無頭代理隨後可以讀取返回嘅 `auth_md` URL，並跟隨 Tuist 嘅註冊、身份斷言交換同聲明輪詢流程。將交換後嘅訪問令牌配置為 bearer token，或者讓代理直接進行經過驗證嘅 Model Context Protocol 調用。

如果你偏好瀏覽器驗證，請將 `auth` 設置為 `"oauth"`。對於該流程，喺驗證完成期間保持一個進程通過 Pi 嘅 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 存活：

```bash
pi --mode rpc
```

唔好將待定嘅瀏覽器驗證拆分到單獨嘅 `pi --print` 調用中，因為擁有回調狀態嘅進程已經退出。

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

然後驗證伺服器：

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

使用 **Command Palette → MCP: Add Server**，然後配置具有以下內容嘅 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 伺服器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

打開 **Agent panel → Settings → Add Custom Server**，然後設置：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果你嘅代理支持 `auth.md`，佢可以匿名啟動而無需打開瀏覽器。當提供者身份已經鏈接時，受信任嘅提供者身份亦可以無需瀏覽器即可完成。對於服務驗證電子郵件、匿名聲明或首次提供者鏈接，代理會向你顯示 Tuist 驗證鏈接同六位數代碼。打開鏈接，登入，並喺 Tuist 頁面上輸入代理嘅代碼。切勿將代碼發送回代理。Tuist 嘅授權伺服器元數據直接指向部署自己嘅 `/auth.md`，其中包含確切嘅請求同輪詢結構。

## WebMCP

喺支持 [WebMCP](https://webmachinelearning.github.io/webmcp) 嘅瀏覽器中，Tuist 嘅頁面會使用 `document.modelContext` 註冊工具，因此內置於瀏覽器嘅代理可以無需任何額外配置即可調用它們。調用喺 Tuist 伺服器上運行。

- **Website and documentation pages** 註冊文檔同源代碼工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 同 `read_tuist_file`）。它們唔需要你登入。
- 當你登入時，**An account's dashboard pages** 會為該帳戶註冊 Tuist 嘅只讀工具。每個頁面僅註冊其顯示內容對應嘅工具，即項目嘅構建系統：Gradle 項目嘅構建頁面獲得 Gradle 構建工具，其測試頁面獲得測試同覆蓋率工具，運行器頁面獲得運行器工具，沙盒頁面獲得沙盒工具。你個人帳戶 AI 設置頁面嘅訂閱部分獲得 `list_ai_subscriptions`，它僅回答關於你自己帳戶嘅問題。每個頁面亦會獲得文檔工具 `list_projects` 同 `get_project`。工具以登入用戶身份運行，因此它們只能訪問你可以喺儀表板中讀取嘅數據，並且僅限於你正在查看嘅帳戶。當你移動到另一個頁面或帳戶時，工具會被該頁面嘅工具替換。

創建、更改或刪除數據嘅工具無法通過 WebMCP 使用，因為瀏覽器代理無需你添加即可接收工具，並讀取構建同測試產生嘅內容。連接 MCP 客戶端到 `/mcp` 端點以使用這些工具。

如果組織強制使用單一登入，請使用其提供者登入儀表板以使用其工具。

## 構建系統集成使用兩組憑證

用於模型上下文協議工具的憑證不會驗證 Gradle 插件或 Bazel 的遠程服務。在代理編輯或驗證 Gradle 或 Bazel 集成之前，它應運行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未通過身份驗證，代理必須停止並要求用戶運行：

```bash
tuist auth login --url https://tuist.dev
```

對於本地或自託管部署，請替換兩個命令中同 `tuist.toml` 中的 URL。確保所有地方的主機名拼寫完全一致。例如，`localhost` 同 `127.0.0.1` 使用分開存儲的憑證。


## 功能

### 工具

以下工具可通過 Tuist 模型上下文協議伺服器使用：

每個工具都會發布人類可讀的描述以及明確的輸入和輸出模式。成功的調用會返回符合所宣傳輸出模式的結構化內容，並將相同結果序列化為文本，供尚未使用結構化內容的客戶端使用。

接受單個記錄標識符（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）的工具，亦接受該記錄的 Tuist 儀表板 URL。直接從瀏覽器複製 URL，而唔係從中提取標識符。

#### 文檔和社區搜索

此只讀工具通過驅動文檔網站的同一搜索引擎搜索 Tuist 的文檔、[應用程式編程接口](https://en.wikipedia.org/wiki/API)參考、GitHub 發布、社區論壇和 GitHub 問題。發布結果包括產品、版本、發布日期和預發布狀態。默認情況下搜索穩定版本，可以通過 `include_prereleases` 包含預發布版本。該工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜索公開的 Tuist 文檔、應用程式編程接口參考、GitHub 發布、社區討論和 GitHub 問題。可選限制為一個 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 反饋

當 Tuist 工具或提示未按預期工作時（例如結果令人困惑、出錯、數據缺失或功能缺失），代理可以告知 Tuist 團隊。系統會要求代理建議一份報告，並僅在你同意後發送。每份報告都會開啟與 Tuist 支持的對話，他們可能會通過電子郵件回覆你。報告包括代理的預期、實際發生的情況、可選建議、你的 Tuist 用戶 ID、句柄和電子郵件，以及你所屬的組織。代理還可以命名發生問題的帳戶和項目，以便團隊知道要跟進哪個組織；僅接受你所屬的帳戶。只有以 Tuist 用戶身份登入的代理才能發送報告，每個用戶每小時最多可以提交 10 份報告。該工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `report_feedback` | 報告 Tuist 工具或提示的問題。可選命名 `tool_name`、發生問題的 `account_handle` 同 `project_handle`，並添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基於源代碼的回答

這些只讀工具讓代理使用與託管伺服器一起部署的精確公共 Tuist 源代碼修訂版作為事實來源，用於取決於當前行為的回答。它們僅在 `https://tuist.dev/mcp` 可用。

兼容的客戶端在初始化期間會收到關於工具源代碼修訂版、鏈接和結果限制的實際描述，以及內聯 OAuth 身份驗證信息。這些描述不規定回答風格或驗證工作流程。用戶可以直接提問，而無需先調用 `ask_tuist` 提示；該提示仍可用於明確的基於源代碼的工作流程。

每個操作都有固定的併發、持續時間、遍歷、讀取字節數和響應大小限制。搜索和列表結果包括 `truncated` 同 `truncation_reason` 字段。當結果被截斷時，請縮小路徑、文件模式或搜索詞，而唔係將結果視為詳盡無遺。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 通過搜索源代碼文件來回答有關當前行為、默認值、配置、功能開關、錯誤處理或未記錄細節的問題。結果包括周圍的行、綁定修訂版的源代碼鏈接和掃描統計信息。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，發現源代碼子系統或附近的測試。列表具有有限的深度和結果數量。 | 無 |
| `read_tuist_file` | 在找到相關路徑後，檢查實現文件、調用站點或測試中的特定行範圍。截斷的響應提供 `next_start_line` 以繼續。 | `path` |

#### 項目

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出經過身份驗證的用戶可用的個人和組織帳戶句柄，包括每個帳戶是否可以創建項目。 | 無 |
| `get_organization` | 獲取組織的成員目錄。待處理的邀請需要與儀表板相同的管理員權限；永遠不會返回邀請接受令牌。 | `account_handle` |
| `create_organization` | 為經過身份驗證的用戶創建 Tuist 組織。 | `handle` |
| `create_project` | 在經過身份驗證的用戶可以訪問的帳戶下創建 Tuist 項目。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有的 Tuist 用戶添加到組織或更新現有成員的角色。接受 `user`（默認）、`admin` 或 `viewer`，其中查看者可以閱讀儀表板和運行記錄，但不能更改任何內容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有的 Tuist 用戶。Tuist 會發送一個有效期為 14 天的接受鏈接；當伺服器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製該鏈接。接受 `user`（默認）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其鏈接無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出經過身份驗證的用戶可以訪問的所有項目。 | 無 |
| `get_project` | 獲取項目的配置和連接的存儲庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將項目鏈接到帳戶的 GitHub App 安裝可以訪問的 GitHub 存儲庫。項目採用存儲庫的默認分支。需要項目管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 刪除項目與其 GitHub 存儲庫的鏈接。需要項目管理員權限。 | `account_handle`, `project_handle` |

#### 帳戶令牌

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳戶令牌元數據，而不暴露令牌值。 | `account_handle` |
| `get_account_token` | 獲取帳戶令牌元數據，而不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出項目令牌元數據，而不暴露令牌值。 | `account_handle`, `project_handle` |

#### AI 訂閱

這些工具管理經過身份驗證的用戶自己的 Claude 和 ChatGPT 訂閱，用於線程等 AI 功能。它們需要用戶身份驗證和對 AI 功能的訪問權限，並且只返回連接元數據，從不返回憑據。斷開連接會刪除保存的憑據，但不會撤銷提供商處的授權。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_ai_subscriptions` | 列出每個訂閱是否已連接，以及伺服器是否可以連接它。 | 無 |
| `connect_claude_subscription` | 保存 `claude setup-token` 打印的訂閱令牌。該令牌是一個機密，會通過客戶端和模型傳遞，因此請明確提供；將其粘貼到儀表板的 AI 設置中可以使其不出現在對話中。 | `token` |
| `start_chatgpt_subscription_login` | 啟動 OpenAI 設備登錄並返回驗證 URL 和用戶在那裡輸入的代碼，以及 `login_id`。15 分鐘後過期。 | 無 |
| `poll_chatgpt_subscription_login` | 檢查待處理的登錄：`pending` 直到用戶批准代碼，然後變為 `connected`。 | `login_id` |
| `cancel_chatgpt_subscription_login` | 取消待處理的登錄。已連接的訂閱保持連接狀態。 | `login_id` |
| `disconnect_ai_subscription` | 刪除訂閱的保存憑據和任何待處理的登錄。 | `provider` |

#### 通知規則

這些工具管理經過身份驗證的用戶自己的通知規則：當事件（例如新預覽）發生在規則的項目中（或者在未列出任何項目時，發生在您可被通知的任何項目中）並滿足其條件時，執行其操作，例如向您的 Tuist 應用設備發送推送通知。沒有規則就不會收到通知。它們需要用戶身份驗證，僅對您自己的規則生效，並且僅接受您所屬帳戶的項目。它們不提供給儀表板頁面，因為規則涵蓋您所有的帳戶。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_notification_events` | 列出規則可以訂閱的事件類型，每個類型都有一個用於其條件的 JSON Schema。 | 無 |
| `list_notification_condition_options` | 建議項目中事件的條件值，例如其最近預覽的軌道和分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出您的規則。 | 無 |
| `create_notification_rule` | 從事件、可選項目和條件，以及至少一個操作建立規則。 | `event`, `actions` |
| `update_notification_rule` | 更改規則的啟用狀態、項目、條件或操作。 | `rule_id` |
| `delete_notification_rule` | 刪除規則。 | `rule_id` |

#### 持續整合執行器

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳戶的持續整合執行器工作。 | `account_handle` |
| `get_runner_job` | 獲取持續整合執行器工作。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續整合執行器工作記錄的步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續整合執行器工作記錄的機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續整合執行器工作最多 500 條捕獲的日誌行。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳戶的持續整合工作流程匯總。 | `account_handle` |
| `list_runner_profiles` | 列出帳戶的持續整合執行器設定檔，並包含每個設定檔的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出執行器設定檔可以使用的機器形狀和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 建立具有平台、機器形狀以及在 macOS 上的 Xcode 版本的執行器設定檔。可選擇設定哪些分支保存其快取卷。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改執行器設定檔的機器形狀、Xcode 版本，或哪些分支保存其自訂快取卷變更。省略的欄位保持其值不變。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 在用戶確認後刪除執行器設定檔。無法刪除預設設定檔。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

執行器卷工具公開與卷儀表板相同的數據。讀取工具需要執行器訪問權限；清除需要帳戶管理權限或 `account:runners:write` 範圍，以及用戶確認。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名稱和存儲庫過濾，對卷進行排序和分頁。 | `account_handle` |
| `get_runner_volume` | 存儲庫、平台、容量、已用空間和最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁的工作和工作流程參考、快取狀態、命中結果和掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由工作掛載的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 存儲序列、工作運行、命中率和趨勢。可選 `volume_id`、`start` 和 `end`（ISO 8601）；預設為七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 刪除卷及其保存的內容。正在運行的工作保留其私有副本但無法保存它們；具有相同密鑰的後續工作將從空開始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷庫存還接受 `name` 和 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的測量和命中結果保持為 `null`。快取狀態描述卷變更是否已保存，而非工作成功與否。

#### 沙盒

沙盒工具公開與沙盒儀表板相同的數據和操作。沙盒運行任意命令，因此每個工具（包括只讀工具）都需要帳戶管理權限，並且帳戶需要啟用沙盒。儀表板的沙盒頁面註冊只讀工具。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_sandboxes` | 對沙盒進行分頁，顯示其狀態、形狀和時間戳。可選 `search`（沙盒中的文本、Amp Orb 或 Anthropic 會話 ID）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）和 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的狀態、形狀、節點、歸檔和時間戳。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小時、創建的沙盒數量、會話、設置和啟動持續時間，以及相對於帳戶限制的峰值 vCPU、內存和磁盤，並帶有趨勢。可選 `start` 和 `end`（ISO 8601）；預設為 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 啟動一個空白沙盒並在運行後返回它。可選 `platform`（`linux` 或 `darwin`）、`template`、帶 `memory_mb` 的 `vcpus`（Linux：2x4096、4x8192 或 8x16384，預設 2x4096；macOS：8x8192、8x16384 或 8x24576，預設 8x8192）和 `workspace_gb`。 | `account_handle` |
| `pause_sandbox` | 將正在運行的沙盒快照保存到其節點的磁盤。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢復暫停或歸檔的沙盒。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 將暫停沙盒的磁碟排隊移至物件儲存空間。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 經用戶確認後，刪除沙盒及其磁碟。 | `account_handle`, `sandbox_id` |

#### Webhooks

Webhook 工具使用與儀表板相同的管理員專用權限。傳送嘗試包含為端點記錄的請求和回應數據，但絕不包含端點簽署密鑰。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳戶的 Webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 獲取 Webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點的傳送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 獲取傳送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 構建

用於 Xcode、Gradle、Bazel、Mix 和 Cargo 的構建詳情工具公開現有的 `custom_metadata: {tags, values}` 結構，包括基礎設施觀察結果（如有報告）。值保持為字符串，並保留不熟悉的鍵。例如，`tuist.cpu.available_processors` 描述運行時可用的邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作器限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆限制，而非主機內存。這些是不可信的客戶端觀察結果，而非經過驗證的 runner 身份。缺失的觀察結果仍保持缺失；導入的日誌和較舊的客戶端可能沒有基礎設施元數據。元數據更新有待協調的客戶端/協議更新。

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出項目的 Xcode 構建運行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 獲取特定 Xcode 構建運行的詳細信息，包括保存原始 `.xcactivitylog` 的歸檔文件的臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 構建運行的構建目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 構建運行的編譯文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄的構建步驟，包含時間和結果，但不含日誌文本。 | `build_run_id` |
| `get_xcode_build_step` | 獲取一個記錄的構建步驟，包括其日誌和截斷標誌。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定構建運行的構建問題（警告和錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 構建運行的可快取任務（快取命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 構建運行的 [內容定址儲存](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 預設返回每頁 20 個步驟（通過 `page_size` 最多可達 100），並提供 `page` 和 `pagination_metadata` 用於導航。使用 `search` 匹配標題、項目或目標，或過濾精確的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以最慢優先（預設），或按 `start_ms` 按時間順序排序。步驟 ID 用於打破平局，並作為十進制字符串返回以保留其完整的 64 位精度。ID 僅限於單次構建，不應跨構建匹配。

可選的 `start_ms` 和 `end_ms` 選擇與從構建開始計算的毫秒時間範圍重疊的步驟；結束時間為互斥。兩個工具都接受構建 UUID 或儀表板 URL 作為 `build_run_id`。將返回的步驟 `id` 原樣作為 `step_id` 傳遞以檢索其日誌。每個步驟的日誌最多保留 64 KiB，`log_truncated` 表示省略的輸出。

處理 Xcode 構建時，預設會收集步驟。記錄的步驟數據保留 90 天。列表響應包括 `availability`：當存在記錄的步驟時為 `available`，即使過濾器未匹配任何內容；當構建仍在處理且尚無步驟時為 `processing`；或者當步驟未記錄或已過期時為 `unavailable`。

相同的操作可通過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上使用，具有相同的過濾器和分頁功能。兩者都需要對構建項目的讀取訪問權限。

#### Gradle 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整的身份驗證、項目設置、Gradle 插件、快取策略和兩次構建驗證工作流程。Agent 在編輯現有的 Android 或 Gradle 項目之前應調用此接口。 | 無 |
| `list_gradle_builds` | 列出項目的 Gradle 構建運行，包括自定義元數據。使用可選的 `tag` 參數按自定義標籤過濾。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 獲取構建元數據以及任務/快取計數。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任務結果、複合構建身份、可快取性和增量狀態。 | `build_run_id` |
| `list_gradle_build_steps` | 列出定時任務、配置和轉換，支持搜索、元數據和重疊時間過濾器。 | `build_run_id` |
| `get_gradle_build_step` | 通過不透明 ID 檢查記錄的步驟元數據；無法獲取每步驟日誌。 | `build_run_id`, `step_id` |

Gradle 和 Bazel 步驟列表預設返回 20 個結果（最多 100 個），支持 `search`、精確的 `project`、`target`、`category` 和 `status`、重疊的 `start_ms` / `end_ms` 過濾器（結束時間互斥），以及按 `duration_ms` 或 `start_ms` 排序。請原樣傳遞返回的 ID；它們僅限於其對應的構建。列表會顯示 `time_origin` 和 `coverage`。較舊的 Gradle 報告使用 `first_recorded_timestamp`，因為沒有上傳構建開始時間。Bazel 配置文件通過 `trace_profile` 覆蓋範圍和以 `profile_start` 為時間起點，顯示所有記錄的時間間隔。較舊的構建會回退到保留的 BEP 摘要。源記錄在 90 天後過期。Bazel 詳情在發布時包括經淨化的操作日誌；Gradle 詳情的 `log` 為 null。`compare_builds` 提示利用此覆蓋範圍來區分完整的 Bazel 追蹤與保留的摘要，並引導 Agent 在檢查更廣泛的調用輸出之前，先查看步驟詳情以獲取操作結果和日誌。

單步工具 `get_gradle_build_step` 和 `get_bazel_build_step` 通過 ID 檢索步驟，不接受時間過濾器；請使用相應的列表工具按時間範圍過濾步驟。

如果在列出步驟和獲取步驟之間收到了完整的配置文件，則從保留摘要返回的 Bazel 步驟 ID 仍然可讀。如果索引配置文件的步驟數據已過期，則會報告為不可用。Gradle 步驟列表包括持續時間為零的快取和跳過的操作。

#### Bazel 調用

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份驗證、項目設置、Bazel 配置和驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成的 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 調用，包括構建指標、有界的執行時間線、關鍵路徑診斷以及項目的相關遠程快取總計。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 獲取一個已完成的 Bazel 調用，包括構建指標、有界的執行時間線、關鍵路徑診斷以及相關的遠程快取總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄的 Bazel 配置文件時間間隔，帶有過濾器和明確的覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄的 Bazel 步驟及其發布的操作結果和淨化日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按執行順序列出為 Bazel 調用捕獲的淨化測試日誌。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 獲取為 Bazel 調用捕獲的一個淨化測試日誌。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 遠程快取觀察記錄，包括其操作、端點和觀察時間，可選擇縮小到特定調用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 獲取一個原始的 Bazel 遠程快取觀察記錄。 | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargo 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出項目的 Cargo 構建，最新的排在前面。按 `git_branch`、`status`、`is_ci` 或 `command` 過濾。Cargo 測試執行結果可通過測試工具獲取，而非此構建列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 獲取構建元數據、聚合快取計數，以及最多 500 個帶有診斷信息的記錄編譯作業。`compilations_truncated` 表示省略的作業；診斷信息僅涵蓋返回的作業。 | `account_handle`, `project_handle`, `build_id` |

在 `get_cargo_build` 上設置 `include_cache_inspection: true` 以檢索經過驗證的任務決策和 CAS 操作，限制為 4 MB。預設情況下，以及當記錄缺失或無效時，`cache_inspection` 為 null。請遵守其部分捕獲的 `truncated` 標誌；傳輸不會確定每個任務命中的本地/遠程來源。HTTP 詳情端點接受相同的查詢參數。

#### Mix 構建

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出項目的 Mix (Elixir) 編譯構建，最新的排在前面，包括自定義元數據。按 `git_branch`、`status`、`is_ci` 或 `mix_env` 過濾。 | `account_handle`, `project_handle` |
| `get_mix_build` | 獲取構建元數據、診斷計數和依賴快取摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 構建追蹤

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `get_build_trace` | 獲取 Xcode、Gradle、Bazel 或 Mix 構建時間線的下載鏈接，作為可在 [Perfetto](https://ui.perfetto.dev) 中打開的追蹤文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 是構建運行 ID（Bazel 的調用 ID）或構建的儀表板 URL。返回的 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有該鏈接的人都可以在 `expires_at`（調用後一小時）之前下載該構建的追蹤，無需其他憑證。Agent 可以使用 `curl` 下載它，交給你並在 Perfetto 中打開，或使用 Perfetto 的 `trace_processor` 進行查詢。追蹤包含按並行性打包到通道中的記錄步驟、跨越整個構建的軌道，以及當構建記錄機器指標時的 CPU 和內存計數器。它包含與上述步驟工具相同的數據，但不包括日誌。儀表板從每個構建的「時間線」標籤頁提供相同的文件。

#### Once 運行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出項目的 Once 運行，最新的排在前面。按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 過濾。尚未完成的運行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 獲取一次運行的數據，包括其操作總數、快取摘要，以及測試運行的測試總數。 | `account_handle`, `project_handle`, `run_id` |

Cargo 構建、Mix 構建和 Once 運行 ID 在項目內是唯一的。通過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 和 `.../once/runs` 也可進行相同的讀取操作，每個端點都支持針對單個 ID 的詳情查詢。

#### 任務、操作、模塊和文件

這些項目範圍的工具檢查跨運行的持久構建身份。首先使用 `list_build_entities`，然後將返回的穩定 `id` 與相同的 `kind` 一起傳遞給 `get_build_entity` 或 `list_build_entity_history`，並附上 `account_handle` 和 `project_handle`。無需構建或調用標識符。

| 工具 | 描述 | 必需參數 |
| --- | --- | --- |
| `list_build_entities` | 列出在項目構建中看到的某一類型的任務、模塊、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 獲取一個構建實體，包括其本機身份和所選時期的分析數據。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個構建實體的記錄執行、編譯或快取事件，最新的排在前面。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 報告的操作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模塊 | 編譯和模塊快取事件 |
| `once_actions` | Once 操作 | 執行 |
| `mix_files` | Mix 編譯文件 | 編譯 |
| `mix_modules` | Mix 編譯模塊 | 編譯 |
| `cargo_crates` | Cargo crate | 記錄的 rustc 調用 |

這些工具正在逐步推出，僅返回已啟用它們的項目的數據；對於其他項目，它們返回錯誤而非空結果。某種類型僅適用於使用其構建工具鏈的項目。工具接受有界的 `start_at`/`end_at` 過濾器、`environment`（`any`、`ci` 或 `local`）和精確的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明的 `after`/`before` 遊標。未知的計時或快取觀察結果保持不可用，而不是變成零或錯過。歷史記錄引用記錄的父級和本機執行，以便使用現有的運行工具進行下鑽。

`get_build_entity` 指標包括 `duration_samples`，即具有記錄計時的觀察次數：真實的零持續時間計入，缺失的計時不計入。此計數可能低於觀察計數；不可用的持續時間統計信息保持為 null。

Xcode 模塊持續時間來自構建日誌中測量的目標編譯。模塊快取解析和沒有編譯工作的目標不會貢獻持續時間樣本。編譯觀察引用 Xcode 構建；快取事件引用生成或快取命令。

Bazel 操作通過目標標籤、助記符和配置的主要輸出來識別，保持單獨的操作和配置區別，而不依賴於輸入相關的快取摘要。歷史記錄 BEP 報告的執行，而不是快取查找或追蹤配置文件階段。完整的執行覆蓋需要 `--build_event_publish_all_actions`；工件交付是盡力而為，因此缺失的觀察結果並非沒有運行工作的證據。較舊的沒有穩定身份或執行開始的 Kura 負載仍然被接受但未編入索引。缺少結束時間測量保持不可用，真實的零持續時間計入。

Mix 模塊持續時間測量包含文件的編譯，而不是獨立測量的模塊工作。當客戶端報告目標映射時，Once 操作使用聲明的目標/能力/索引槽；僅診斷標籤不是穩定的身份。現有客戶端和運行級別工具保持不變地支持。

Cargo crate 按精確記錄的 crate 根、名稱和類型分組。檢出路徑更改可能會分割歷史記錄，並且構建配置文件、功能和目標三元組不會區分。歷史測量 rustc 調用，而不是每個文件的工作或快取命中；缺失的作業不會確立刪除或完整的工作區清單。

分析讀取具有有限的內存和執行時間。如果查詢超過這些限制，工具將返回錯誤，而不是發明一個空結果。

新觀察結果在部署後編入索引；此功能不會回填現有的運行遙測數據。身份元數據在 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link> 下比單個觀察結果更長久。

#### 測試

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出項目的測試運行。`query` 字段為 `git_branch`、`scheme` 和 `status`：`field:"value"` 精確匹配，`field~"value"` 匹配不區分大小寫的子字符串，前導 `-` 否定任一運算符。例如，`-git_branch~"gh-readonly-queue"` 排除合併隊列分支。空格分隔的查詢過濾器和顯式參數以 AND 語義組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 取得測試執行的詳細指標，包括其結果套件（`.xcresult`）和會話存檔的臨時下載網址。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行的測試模塊運行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行的測試套件運行，可選擇按模塊過濾。 | `test_run_id` |
| `list_test_cases` | 列出項目的測試案例（支持如 `flaky` 等過濾器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 取得測試案例的詳細指標，包括可靠性比率、不穩定性比率和執行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例運行，可選擇按測試案例或測試執行過濾。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 取得特定測試案例運行的失敗詳情和重複次數。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例運行的附件。每個附件都包含一個臨時下載網址。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例的狀態變更，例如將其靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例的狀態或不穩定分類。變更可以向配置的 webhook 端點（包括外部服務）分派事件。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試運行的選擇性測試目標結果。 | `test_run_id` |
| `get_coverage` | 取得項目的代碼覆蓋率及其目標，基於某個提交或分支的最新完整提交。如果沒有 `git_commit_sha` 或 `branch`，則讀取默認分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出某個提交的代碼覆蓋率所測量的文件及其行覆蓋率，基於某個提交或分支的最新完整提交。支持 `search`、排序和分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 取得文件的代碼覆蓋率及其函數，基於某個提交或分支的最新完整提交。設置 `include_lines` 以取得每行的執行次數。 | `account_handle`, `project_handle`, `path` |

代碼覆蓋率工具僅適用於已啟用代碼覆蓋率的帳戶。

#### 捆綁包

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出項目的捆綁包（應用二進製文件）。可選擇按 `git_branch` 和 `tags` 過濾（所有標籤必須精確匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 取得特定捆綁包的詳細信息，包括自定義標籤。 | `bundle_id` |
| `get_bundle_artifact_tree` | 以按路徑排序的平面列表形式取得捆綁包的完整工件樹。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以區分構建變體或環境。標籤是區分大小寫的標籤，包含字母、數字、連字符或下劃線，最多 10 個標籤，每個標籤最多 50 個字符。列表和詳細結果包括 `custom_metadata.tags`。分頁計數和分支過濾器適用於帶標籤的結果；省略 `tags` 將保留未過濾的行為。無效的標籤過濾器將返回錯誤，而不是擴大查詢範圍。

#### 生成

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_generations` | 列出項目的生成運行。 | `account_handle`, `project_handle` |
| `get_generation` | 取得特定生成運行的詳細信息。 | `generation_id` |

#### 快取運行

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出項目的快取運行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 取得特定快取運行的詳細信息。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出生成或快取運行的模塊快取目標，顯示每個目標的快取命中/未命中狀態和診斷組件哈希，包括額外的哈希輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_previews` | 列出項目的可分享應用預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 取得預覽及其構建的臨時下載 URL。 | `preview_id` |
| `get_latest_preview` | 尋找正在運行的應用二進製文件的最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 必需參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出項目的自動化警報。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 取得自動化警報。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警報的修訂歷史。操作憑證已脫敏。 | `alert_id` |
| `list_project_notification_alerts` | 列出項目通知警報規則。需要與儀表板設置頁面相同的管理員權限。Webhook 地址已脫敏。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期的客戶端可以調用 `events/list` 來發現事件及其負載架構：

| 事件 | 發送時機 | 訂閱過濾器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從非不穩定變為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本地或持續集成的 Xcode、Gradle 或 Bazel 構建以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本地或持續集成測試運行以失敗結束，包括合併的分片運行或放棄的運行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist runner 作業以失敗完成。 | `account_handle` |

要訂閱，客戶端需調用 `events/subscribe`，並提供事件名稱、上述 `arguments` 中列出的句柄，以及包含 `https://` 回調 URL 和 `whsec_` 簽名密鑰的 `webhook` 交付。項目事件需要帳戶成員資格以及對相應測試或構建數據的讀取權限；runner 作業事件需要帳戶成員資格和 runner 讀取權限。聲明的 [`auth.md`](https://workos.com/auth-md) 訪問令牌、聲明的帳戶令牌和瀏覽器授權授予可以創建訂閱；當相關憑證不再有效時，交付將停止。每個用戶最多可以保留 25 個活動訂閱。Tuist 在保存訂閱之前會向回調發送驗證挑戰。回調必須返回包含相同 `challenge` 值的對象。訂閱默認持續七天，可以通過再次訂閱來刷新，並且在刪除用戶的訪問權限或憑證時停止交付。可選的 `ttlMs` 限制在一小時到 30 天之間。Tuist 會重試超時的回調，並在至少三次連續超時（跨越五分鐘）後取消訂閱；恢復回調後請再次訂閱。

當事件發生時，Tuist 會將其資源標識符和儀表板 URL 發送到回調。構建和測試運行失敗還包括 `is_ci` 和 `git_branch`，因此客戶端可以忽略本地失敗或按分支過濾。構建事件包括 `build_system`；runner 作業事件包括 `workflow_job_id` 和 `workflow_run_id`。請求包括訂閱標識符和 [Standard Webhooks](https://www.standardwebhooks.com/) 簽名頭，以便客戶端驗證其來源。Tuist 會重試失敗的交付，因此客戶端應使用穩定的 `eventId` 來丟棄重複項。負載省略了測試名稱、日誌和失敗消息；客戶端可以通過上述工具獲取這些詳細信息，並決定是否通知團隊或開始調試。客戶端可以使用 `events/unsubscribe` 停止交付。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 指導你通過分析失敗模式、識別根本原因並應用針對性修正來修復不穩定測試。 |
| `compare_builds` | 指導你通過比較構建來識別性能回歸、快取變更和構建問題。為 Xcode、Gradle、Bazel 和 Cargo 項目使用原生工具。Cargo 比較保留部分編譯器覆蓋率，並將估計的編譯器工作與經過時間節省區分開來。 |
| `compare_test_runs` | 指導你通過比較兩次測試執行來識別回歸、新故障和不穩定測試。 |
| `compare_bundles` | 指導你通過比較兩個捆綁包來識別工件樹中的大小變化。 |
| `compare_test_case` | 指導你通過比較測試案例在兩個分支或時間段內的行為。 |
| `compare_generations` | 指導你通過比較兩次生成運行來識別性能回歸和模塊快取變更。 |
| `compare_cache_runs` | 指導你通過比較兩次快取運行來識別快取效率變更和目標級別回歸。 |
| `integrate_gradle_project` | 指導你將 Tuist 集成到現有的 Gradle 項目中。它包括獨立的工具和 Gradle 身份驗證、帳戶發現、項目創建、遠程快取策略、構建洞察和回讀驗證。 |
| `integrate_bazel_project` | 指導你創建或選擇 Bazel 項目、對命令行進行身份驗證、配置遠程快取和構建洞察，並通過 Tuist 構建數據驗證集成。 |
| `integrate_xcode_project` | 指導你將 Tuist 集成到現有的 Xcode 項目中。支持 Xcode 快取、構建洞察、測試洞察和測試分片。 |
| `ask_tuist` | 使用公開材料作為上下文，並以專注的實現和測試證據作為當前行為的事實來源，來回答 Tuist 問題。它需要一個 `question` 並引用修訂固定的證據。 |

項目數據提示接受 `account_handle` 和 `project_handle` 以將調查範圍限定在特定項目。比較提示還接受 `base` 和 `head` 參數以指定要比較的兩個項目（通過 ID、儀表板 URL 或分支名稱）。`ask_tuist` 接受 `question` 而不是項目參數。`integrate_gradle_project` 還接受 `features`，這是一個要應用的 Gradle 集成的逗號分隔列表：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可選的 `server_url` 用於自託管或本地安裝。`integrate_xcode_project` 接受帶有 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding` 的 `features`。

#### Gradle 集成提示功能

`integrate_gradle_project` 提示和 `get_gradle_integration_guide` 工具記錄了完整的設置工作流程。伺服器的初始化說明也會引用此工具，讓不枚舉提示的代理也能發現它。

| 功能 | 代理配置的內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 的構建快取，配置 Tuist 遠程快取上傳策略，並建議僅從具有本地只讀權限的持續集成運行器上傳。 |
| `build_insights` | 應用 Tuist Gradle 插件，並在需要時配置構建分析上傳行為。 |
| `test_insights` | 應用 Tuist Gradle 插件，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 指導設置不穩定測試檢測、可選的 Gradle Test Retry 插件使用，以及測試隔離配置。 |
| `test_sharding` | 添加用於 `tuistPrepareTestShards`、分片矩陣生成和基於 `TUIST_SHARD_INDEX` 的測試執行的持續集成工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或在編輯 Gradle 項目之前從請求中推斷出最小的有用集合。

#### Xcode 集成提示功能

`integrate_xcode_project` 提示記錄了 Tuist 支持的每種 Xcode 集成：

| 功能 | 代理配置的內容 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成項目的快取設置、手動 Xcode 快取構建設置，以及僅限於持續集成運行器的上傳策略。 |
| `build_insights` | 通過 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 和可選的機器指標。 |
| `test_insights` | 配置 `tuist inspect test`、方案測試後操作，以及為持續集成測試運行生成結果捆綁包。 |
| `test_sharding` | 添加帶有 `TUIST_SHARD_INDEX` 的 Xcode 或生成項目分片規劃和分片執行工作流程。 |

當省略 `features` 時，提示會要求代理澄清用戶想要哪些集成，或在編輯 Xcode 項目之前從請求中推斷出最小的有用集合。
