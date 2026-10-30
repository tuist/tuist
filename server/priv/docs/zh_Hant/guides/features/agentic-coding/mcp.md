---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · 代理式編碼 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 的 MCP 端點，讓 AI 代理存取測試洞察等資訊。"
}
---
# 模型上下文通訊協定

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一項開放標準，讓人工智慧代理能夠與外部服務和資料來源互動。它使 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等應用程式，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等編輯器能夠與 Tuist 互通。

Tuist 在 `https://tuist.dev/mcp` 託管伺服器端的 Model Context Protocol 端點。將你的用戶端連線至此端點後，代理即可存取你的 Tuist 專案資料，包括測試洞察、不穩定測試分析等。大多數工具為唯讀，且範圍限於已驗證的 Tuist 專案資料。帳戶設定工具可以在已驗證使用者具備所需權限時列出帳戶、建立組織、建立專案，並將現有使用者加入組織。每個工具都會標示註解，說明其是否為唯讀、是否可能導致難以復原的變更，以及是否會變更公開網際網路狀態。帳戶設定工具需要使用者驗證。它們不適用於專案權杖或一般帳戶權杖。當使用者在瀏覽器中授權用戶端或宣告 `auth.md` 註冊時，Tuist 僅在 Model Context Protocol 端點上將該憑證與使用者關聯，以便設定工具完成請求的工作流程。

Tuist 實作了 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求是無狀態的：用戶端會在每次請求中傳送其通訊協定中繼資料，並可直接呼叫工具而無需初始化。`server/discover` 會傳回伺服器的身分識別、功能、支援的版本以及指示。沒有工作階段識別碼或獨立的事件串流。使用 2025-06-18 或 2025-03-26 初始化流程的用戶端仍受支援；它們也無需伺服器工作階段即可運作。

## Model Context Protocol 與技能比較

Model Context Protocol 工具與 <.localized_link href="/guides/features/agentic-coding/skills">技能</.localized_link> 的功能可能重疊。鑑於目前兩者的重疊情況，請為每個工作流程選擇一種方法並一致使用，避免在同一流程中混合兩者。

對於支援外掛安裝的用戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 同時安裝兩者。

## 設定

在用戶端中將 `https://tuist.dev/mcp` 新增為遠端 Model Context Protocol 伺服器。伺服器的初始化指示與公開伺服器卡片內嵌描述了具備動態用戶端註冊功能的 OAuth 2.0 以及標準瀏覽器授權流程，無需代理抓取或遵循外部驗證文件。這些伺服器層級的指示保持工作流程指引的通用性：工具驗證不會驗證本機命令列工具或建置系統整合，代理應透過相關的 Tuist 工具驗證請求的變更。建置系統特定的設定與驗證檢查記錄在整合指南與提示中。Tuist 仍分別宣傳 [Open Authorization](https://oauth.net/2/) 探索中繼資料與目前的 [auth.md protocol](https://workos.com/auth-md)（位於 `https://tuist.dev/auth.md`）。

此端點接受無狀態的 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），以及較舊的基於工作階段的生命週期。現有用戶端可以繼續使用目前的連線方式。

支援 Model Context Protocol 事件的用戶端可以訂閱專案事件。如需可用的事件與傳遞需求，請參閱 [Events](#events)。

已支援遠端瀏覽器驗證的用戶端可以繼續在瀏覽器中進行驗證。支援 `auth.md` 的用戶端與代理可以匿名註冊、提供受信任的提供者身分斷言，或啟動服務驗證的電子郵件宣告。註冊會傳回由 Tuist 簽署的身分斷言，代理可在標準權杖端點將其交換為一小時的存取權杖。Tuist 會發布其公開簽章金鑰，並支援標準權杖撤銷與提供者安全事件傳遞。

未經驗證的代理應讀取 Model Context Protocol 端點傳回的 `WWW-Authenticate` 標頭，抓取受保護資源的中繼資料、授權伺服器中繼資料，並遵循其 `agent_auth.skill` URL。Tuist 也會在未授權回應主體中傳回相同的本機 `auth_md` URL，讓語言模型驅動的用戶端無需依賴原生用戶端整合即可發現該流程。部署本機文件是端點名稱、請求主體、宣告輪詢與斷言交換的真實來源。

在代理啟動電子郵件宣告之前，必須要求使用者確認其 Tuist 帳戶的電子郵件地址。不得從提供者設定檔、Git 設定、環境變數或工作階段中繼資料推斷該地址。

此端點使用 `mcp` 範圍群組。匿名的預宣告憑證可以探索功能並閱讀公開整合指南，但不會被視為已登入使用者。經過瀏覽器授權或宣告後，該憑證具有使用者範圍，且每個工具都會套用與儀表板相同的授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析為已驗證使用者已有權讀取的專案。Xcode 與 Gradle 建置工具接受建置 UUID 或儀表板 URL。UUID 必須唯一識別一個專案；如果出現在多個專案中，工具會傳回找不到，而不會選擇另一個專案的報告。專案範圍的儀表板與 API 讀取仍然可用。回報的行為者識別碼是未經驗證的標籤，並非憑證或額外的存取權限。

建置清單與詳細資訊工具會公開選擇性的 `tuist_version` 中繼資料：用於 Xcode 與 Cargo 的回報 Tuist CLI、用於 Gradle 的 Tuist Gradle 外掛，以及用於 Mix 的 `tuist_ex` 函式庫。Xcode 也會從其連結的專案產生事件中公開 `tuist_generation_version`，該值可能與上傳用的 CLI 不同。遺漏的觀測值為 null，不會從伺服器或其他報告推斷。Bazel 使用其現有的 `bazel_version`；Once 執行詳細資訊則公開 `once_version`。這些欄位描述回報的版本，並非已驗證的身分或線路協定版本。REST 建置端點會公開相同的中繼資料。現有的整合與不穩定測試技能不依賴版本欄位，無需變更工作流程。

Tuist 營運人員透過 Tuist 內部營運工具調查客戶帳戶，並記錄每次呼叫；直接連線至此端點不會取得超出使用者自身成員資格以外的存取權限。

<details>
<summary>Claude Code</summary>

執行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 用戶端未向模型揭露失敗的原生伺服器連線時，請要求代理在搜尋託管文件或編輯專案之前，檢查所設定端點的未經驗證 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 回應。即使無法使用瀏覽器驗證，該回應也會將模型指向部署本機的 `auth.md` 文件。

</details>


<details>
<summary>Codex</summary>

執行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在開始新的 `codex exec` 執行之前，先完成瀏覽器登入。Codex 會在初始化期間讀取 Tuist 伺服器指示，因此 Gradle 最佳化請求會自動獲得驗證與驗證工作流程。

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

Pi 不包含 Model Context Protocol 用戶端。在檢視其原始碼與安全性影響後，你可以安裝第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 擴充功能：

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

將 `auth` 設為 `false` 可防止轉接器的瀏覽器驗證處理常式隱藏 Tuist 的未授權回應。無頭代理隨後可以讀取傳回的 `auth_md` URL，並遵循 Tuist 的註冊、身分斷言交換與宣告輪詢流程。將交換後的存取權杖設定為 bearer token，或讓代理直接進行已驗證的 Model Context Protocol 呼叫。

若你偏好瀏覽器驗證，請將 `auth` 設為 `"oauth"`。對於該流程，請在驗證完成期間保持一個程序以 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 運作：

```bash
pi --mode rpc
```

不要將待處理的瀏覽器驗證拆分到多個 `pi --print` 叫用中，因為擁有回呼狀態的程序已結束。

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

使用 **Command Palette → MCP: Add Server**，然後設定 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 伺服器：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

開啟 **Agent panel → Settings → Add Custom Server**，然後設定：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

如果你的代理支援 `auth.md`，它可以匿名啟動而無需開啟瀏覽器。當提供者身分已連結時，受信任的提供者身分也可以在不使用瀏覽器的情況下完成。對於服務驗證的電子郵件、匿名宣告或首次提供者連結，代理會顯示 Tuist 驗證連結與六位數代碼。開啟連結、登入，並在 Tuist 頁面上輸入代理的代碼。切勿將代碼傳回給代理。Tuist 的授權伺服器中繼資料直接指向部署本身的 `/auth.md`，其中包含精確的請求與輪詢結構。

## 建置系統整合使用兩組憑證

用於 Model Context Protocol 工具的憑證不會驗證 Gradle 外掛或 Bazel 的遠端服務。在代理編輯或驗證 Gradle 或 Bazel 整合之前，應執行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未通過驗證，代理必須停止並要求使用者執行：

```bash
tuist auth login --url https://tuist.dev
```

對於本機或自託管部署，請替換兩個命令與 `tuist.toml` 中的 URL。在所有地方保持主機名稱拼寫一致。例如，`localhost` 與 `127.0.0.1` 使用分開儲存的憑證。


## 功能

### 工具

以下工具可透過 Tuist Model Context Protocol 伺服器使用：

每個工具都會發布人類可讀的描述，以及明確的輸入與輸出結構定義。成功的呼叫會回傳符合所宣告輸出結構的結構化內容，並將相同結果序列化為文字，供尚未支援結構化內容的用戶端使用。

接受單一記錄識別碼的工具（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）也接受該記錄的 Tuist 儀表板 URL。請直接從瀏覽器貼上 URL，而非從中擷取識別碼。

#### 文件與社群搜尋

此唯讀工具透過驅動文件網站的同一個搜尋引擎，搜尋 Tuist 的文件、[application programming interface](https://en.wikipedia.org/wiki/API) 參考、GitHub 發行版本、社群論壇與 GitHub Issues。發行結果包含產品、版本、發布日期與預覽狀態。預設搜尋穩定版本，並可使用 `include_prereleases` 納入預覽版本。此工具僅在 Tuist 託管的伺服器 `https://tuist.dev/mcp` 上提供。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜尋公開的 Tuist 文件、應用程式介面參考、GitHub 發行版本、社群討論與 GitHub Issues。可選擇限制為單一 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 以原始碼為依據的回答

這些唯讀工具讓代理程式使用與託管伺服器一同部署的確切公開 Tuist 原始碼修訂版本，作為依賴目前行為之答案的事實來源。它們僅在 `https://tuist.dev/mcp` 提供。

相容的用戶端在初始化期間會收到關於工具原始碼修訂版本、連結與結果限制的事實描述，以及內嵌 OAuth 驗證資訊。這些描述不會規定回答風格或驗證工作流程。使用者可以直接提問，無需先叫用 `ask_tuist` 提示；該提示仍可用於明確的原始碼支援工作流程。

每項作業對並行、持續時間、遍歷、讀取位元組數與回應大小都有固定限制。搜尋與列出結果包含 `truncated` 與 `truncation_reason` 欄位。當結果被截斷時，請縮小路徑、檔案模式或搜尋詞彙，而非將結果視為完整。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 透過搜尋原始碼檔案，回答關於目前行為、預設值、設定、功能開關、錯誤處理或未記錄細節的問題。結果包含周圍行數、綁定修訂版本的原始碼連結，以及掃描統計資料。 | `pattern` |
| `list_tuist_files` | 在相關路徑未知時，探索原始碼子系統或鄰近測試。列出結果具有有限的深度與結果數量。 | 無 |
| `read_tuist_file` | 在找到相關路徑後，檢查實作檔案、呼叫位置或測試中的特定行範圍。截斷的回應會提供 `next_start_line` 以便繼續。 | `path` |

#### 專案

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出可供已驗證使用者使用的個人與組織帳號代號，包括每個帳號是否能建立專案。 | 無 |
| `get_organization` | 取得組織的成員目錄。待處理的邀請需要與儀表板相同的管理員權限；永遠不會回傳邀請接受權杖。 | `account_handle` |
| `create_organization` | 為已驗證的使用者建立 Tuist 組織。 | `handle` |
| `create_project` | 在已驗證使用者可存取的帳號下建立 Tuist 專案。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有的 Tuist 使用者加入組織，或更新現有成員的角色。接受 `user`（預設）、`admin` 或 `viewer`，其中檢視者可以讀取儀表板與執行記錄，但無法進行任何變更。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有的 Tuist 使用者。Tuist 會寄送一個 14 天後過期的接受連結；當伺服器無法傳送電子郵件時，`email_sent` 為 `false`，且必須從儀表板複製連結。接受 `user`（預設）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其連結無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出所有可供已驗證使用者存取的專案。 | 無 |
| `get_project` | 取得專案的設定與已連接的儲存庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將專案連結至帳號的 GitHub App 安裝可存取的 GitHub 儲存庫。專案會採用儲存庫的預設分支。需要專案管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除專案與其 GitHub 儲存庫的連結。需要專案管理員權限。 | `account_handle`, `project_handle` |

#### 帳號權杖

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳號權杖的中繼資料，而不揭露權杖值。 | `account_handle` |
| `get_account_token` | 取得帳號權杖的中繼資料，而不揭露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出專案權杖的中繼資料，而不揭露權杖值。 | `account_handle`, `project_handle` |

#### 持續整合執行器

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳號的持續整合執行器工作。 | `account_handle` |
| `get_runner_job` | 取得持續整合執行器工作。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續整合執行器工作記錄的步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續整合執行器工作記錄的機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續整合執行器工作最多 500 筆擷取的記錄行。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳號的持續整合工作流程彙總。 | `account_handle` |
| `list_runner_profiles` | 列出帳號的持續整合執行器設定檔，並包含每個設定檔的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出執行器設定檔可使用的機器規格與 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 建立包含平台、機器規格，以及在 macOS 上包含 Xcode 版本的執行器設定檔。可選擇設定哪些分支會儲存其快取磁碟區。需要帳號管理員權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 變更執行器設定檔的機器規格、Xcode 版本，或哪些分支會儲存其自訂快取磁碟區的變更。未提供的欄位會保留其值。需要帳號管理員權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 在使用者確認後刪除執行器設定檔。無法刪除預設設定檔。需要帳號管理員權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

執行器磁碟區工具公開與磁碟區儀表板相同的資料。讀取工具需要執行器存取權；清除需要帳號管理員權限或 `account:runners:write` 範圍，以及使用者確認。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 依名稱與儲存庫篩選，並對磁碟區進行排序與分頁。 | `account_handle` |
| `get_runner_volume` | 儲存庫、平台、容量、已用空間與最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁的工作與工作流程參考、快取狀態、命中結果與掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由工作掛載的磁碟區。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 儲存序列、工作執行次數、命中率與趨勢。可選的 `volume_id`、`start` 與 `end`（ISO 8601）；預設為七天，最多 90 天。 | `account_handle` |
| `clear_runner_volume` | 清除已儲存的內容。執行中的工作會保留其私有副本，但無法儲存；後續工作將從空白開始。 | `account_handle`, `volume_id` |

列表接受 `page` 與 `page_size`（最多 100）。磁碟區清單也接受 `name` 與 `repository`（完全相符，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）與 `sort_order`（`asc`、`desc`）。未知的測量值與命中結果會保持為 `null`。快取狀態說明磁碟區變更是否已儲存，而非工作成功與否。

#### Webhook

Webhook 工具使用與儀表板相同的管理員專用權限。傳送嘗試包含為端點記錄的要求與回應資料，但絕不包含端點簽署密鑰。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳號的 Webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 取得 Webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點的傳送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 取得傳送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 建置

針對 Xcode、Gradle、Bazel、Mix 與 Cargo 的建置詳細資訊工具，會公開現有的 `custom_metadata: {tags, values}` 結構，並在回報時包含基礎設施觀察資料。值保持為字串，且不熟悉的鍵會被保留。例如，`tuist.cpu.available_processors` 描述執行階段可用的邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作限制，`tuist.jvm.max_heap_bytes` 則是 JVM 堆積限制，並非主機記憶體。這些是不可信的用戶端觀察資料，而非經過驗證的執行器身分。缺少的觀察資料仍會保持缺少；匯入的日誌與較舊的用戶端可能沒有基礎設施中繼資料。Once 中繼資料等待協調一致的用戶端／通訊協定更新。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出專案的 Xcode 建置執行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 取得特定 Xcode 建置執行的詳細資訊，包括保存原始 `.xcactivitylog` 的封存檔之暫時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 建置執行的建置目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 建置執行的已編譯檔案。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄的建置步驟及其時間與結果，不含日誌文字。 | `build_run_id` |
| `get_xcode_build_step` | 取得單一記錄的建置步驟，包括其日誌與截斷旗標。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定建置執行的建置問題（警告與錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 建置執行的可快取工作（快取命中／未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 建置執行的 [內容定址儲存](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 預設傳回每頁 20 個步驟（透過 `page_size` 最多 100 個），並提供 `page` 與 `pagination_metadata` 以供導覽。使用 `search` 來比對標題、專案或目標，或篩選確切的 `project`、`target`、`category`（例如 `swiftCompilation`）與 `status`（`success` 或 `failure`）。依 `duration_ms` 排序以最慢者優先（預設），或依 `start_ms` 排序以取得時間順序。步驟 ID 用於打破平手，並以十進位字串形式傳回，以保留完整的 64 位元精確度。ID 範圍限於單一建置，不應跨建置比對。

可選的 `start_ms` 與 `end_ms` 可選取與從建置開始起算的毫秒時間範圍重疊的步驟；結束時間為互斥。兩種工具皆接受建置 UUID 或儀表板 URL 作為 `build_run_id`。將傳回的步驟 `id` 原封不動地作為 `step_id` 傳遞，以擷取其日誌。每個步驟的日誌最多保留 64 KiB，並以 `log_truncated` 指示省略的輸出。

處理 Xcode 建置時，預設會收集步驟。記錄的步驟資料會保留 90 天。列表回應包含 `availability`：`available` 表示存在記錄的步驟，即使篩選條件未符合任何項目；`processing` 表示建置仍在處理中且尚無步驟；或 `unavailable` 表示步驟未被記錄或已過期。

相同的操作也可透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 與 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上使用，並具有相同的篩選與分頁功能。兩者皆需要對建置所屬專案的讀取存取權。

#### Gradle 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 傳回完整的認證、專案設定、Gradle 外掛程式、快取政策，以及雙建置驗證工作流程。代理程式應在編輯現有的 Android 或 Gradle 專案前呼叫此工具。 | 無 |
| `list_gradle_builds` | 列出專案的 Gradle 建置執行，包括自訂中繼資料。使用可選的 `tag` 參數依自訂標籤篩選。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 取得建置之中繼資料與工作／快取計數。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出工作結果、複合建置身分、可快取性與增量狀態。 | `build_run_id` |
| `list_gradle_build_steps` | 列出計時工作、設定與轉換，並支援搜尋、中繼資料與重疊時間篩選。 | `build_run_id` |
| `get_gradle_build_step` | 透過不透明 ID 檢查記錄的步驟中繼資料；無法提供每步驟日誌。 | `build_run_id`, `step_id` |

Gradle 與 Bazel 步驟清單預設為 20 筆結果（最多 100 筆），支援 `search`、確切的 `project`、`target`、`category` 與 `status`、重疊的 `start_ms` / `end_ms` 篩選（結束互斥），以及 `duration_ms` 或 `start_ms` 排序。原封不動地傳遞傳回的 ID；它們的範圍限於其建置。清單公開 `time_origin` 與 `coverage`。較舊的 Gradle 報告使用 `first_recorded_timestamp`，因為未上傳建置開始時間。Bazel 設定檔透過 `trace_profile` 覆蓋範圍與作為時間起點的 `profile_start`，公開所有記錄的間隔。較舊的建置會退回到保留的 BEP 摘要。來源記錄在 90 天後過期。Bazel 詳細資訊在發布時包含經淨化的動作日誌；Gradle 詳細資訊 `log` 為 null。`compare_builds` 提示使用此覆蓋範圍來區分完整的 Bazel 追蹤與保留的摘要，並指引代理程式在檢查更廣泛的叫用輸出之前，先查看步驟詳細資訊以取得動作結果與日誌。

若在列出與擷取步驟之間收到完整設定檔，則從保留摘要傳回的 Bazel 步驟 ID 仍可讀取。若索引設定檔的步驟資料已過期，則會回報為不可用。Gradle 步驟清單包含持續時間為零的快取與略過作業。

#### Bazel 叫用

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 傳回認證、專案設定、Bazel 設定與驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成的 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 叫用，包含建置指標、有界的執行時間軸、關鍵路徑診斷，以及專案的相關遠端快取總計。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 取得單一已完成的 Bazel 叫用，包含建置指標、有界的執行時間軸、關鍵路徑診斷，以及相關的遠端快取總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄的 Bazel 設定檔間隔，並提供篩選與明確的覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄的 Bazel 步驟及其發布的動作結果與淨化日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 依執行順序列出為 Bazel 叫用擷取的淨化測試日誌。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 取得單一為 Bazel 叫用擷取的淨化測試日誌。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 遠端快取觀察記錄，包含其作業、端點與觀察時間，並可選擇縮小到特定叫用、結果或作業。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 取得單一原始的 Bazel 遠端快取觀察記錄。 | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargo 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出專案的 Cargo 建置，由新到舊排列。可依 `git_branch`、`status`、`is_ci` 或 `command` 篩選。個別測試執行需透過測試工具取得，而非此建置清單。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 取得建置之中繼資料與彙總快取計數，包含命中、工作未命中與命中率。 | `account_handle`, `project_handle`, `build_id` |

#### Mix 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出專案的 Mix（Elixir）編譯建置，由新到舊排列，並包含自訂中繼資料。可依 `git_branch`、`status`、`is_ci` 或 `mix_env` 篩選。 | `account_handle`, `project_handle` |
| `get_mix_build` | 取得建置之中繼資料、診斷計數與相依性快取摘要。 | `account_handle`, `project_handle`, `build_id` |

#### Once 執行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出專案的 Once 執行，由新到舊排列。可依 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 篩選。尚未完成的執行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 取得執行的動作總計、快取摘要，以及測試執行的測試總計。 | `account_handle`, `project_handle`, `run_id` |

Cargo 建置、Mix 建置與 Once 執行 ID 在專案內具有唯一性。相同的讀取也可透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 與 `.../once/runs` 取得，每個端點都提供針對單一 ID 的詳細資訊端點。

#### 工作、動作、模組與檔案

這些專案範圍的工具會檢查跨執行的持久建置身分。請先從 `list_build_entities` 開始，然後將傳回的穩定 `id` 與相同的 `kind` 傳遞至 `get_build_entity` 或 `list_build_entity_history`，並同時提供 `account_handle` 與 `project_handle`。不需要建置或叫用識別碼。

| 工具 | 描述 | 必要參數 |
| --- | --- | --- |
| `list_build_entities` | 列出在專案建置中見到的某一類工作、模組、動作或檔案。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 取得單一建置身分，包含其原身身分與所選期間的分析資料。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出單一建置身分的記錄執行、編譯或快取事件，由新到舊排列。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史清單 |
| --- | --- | --- |
| `bazel_actions` | Bazel 動作 | BEP 回報的動作執行 |
| `gradle_tasks` | Gradle 工作 | 工作執行 |
| `xcode_modules` | Xcode 模組 | 編譯與模組快取事件 |
| `once_actions` | Once 動作 | 執行 |
| `mix_files` | Mix 編譯檔案 | 編譯 |
| `mix_modules` | Mix 編譯模組 | 編譯 |

這些工具正逐步推出，僅回傳已啟用該功能的專案資料；其他專案則會回傳錯誤，而非空結果。只有使用對應建置工具鏈的專案才能使用特定種類。工具接受有範圍的 `start_at`/`end_at` 篩選器、`environment`（`any`、`ci` 或 `local`）以及精確的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支援不透明的 `after`/`before` 游標。未知的時間或快取觀察記錄仍維持不可用，不會變成零或未命中。歷史記錄會參考已記錄的父項與原身執行，以便使用現有的執行工具進行深入分析。

`get_build_entity` 指標包含 `duration_samples`，即具有記錄時間的觀察數量：真正的零持續時間會計入，缺少時間記錄則不計入。此計數可能低於觀察總數；無法取得的持續時間統計資料仍為 null。

Xcode 模組持續時間來自建置日誌中測量的目標編譯。模組快取解析與沒有編譯工作的目標不會貢獻持續時間樣本。編譯觀察記錄參考 Xcode 建置；快取事件參考產生或快取指令。

Bazel 動作透過目標標籤、助記符與設定的主要輸出進行識別，在不依賴輸入相關快取摘要的情況下，區分不同的動作與設定。歷史記錄會記錄 BEP 回報的執行，而非快取查詢或追蹤設定檔階段。完整的執行涵蓋需要 `--build_event_publish_all_actions`；構件交付採盡力而為原則，因此缺少觀察記錄不代表沒有工作執行。較舊且缺乏穩定身分或執行開始資訊的 Kura 負載仍會被接受但不建立索引。缺少的結束時間測量仍維持不可用，真正的零持續時間會計入。

Mix 模組持續時間測量的是包含檔案的編譯，而非獨立測量的模組工作。當客戶端回報目標對應時，Once 動作會使用宣告的目標/能力/索引槽位；僅靠診斷標籤並非穩定的身分。現有客戶端與執行層級工具仍維持不變地受到支援。

分析讀取具有記憶體與執行時間上限。若查詢超過這些限制，工具將回傳錯誤，而非捏造空結果。

新的觀察記錄會在部署後建立索引；此功能不會回填現有的執行遙測資料。在 <.localized_link href="/guides/server/data-retention">資料保留政策</.localized_link> 下，身分中繼資料的保存期限長於個別觀察記錄。

#### 測試

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出專案的測試執行。`query` 欄位為 `git_branch`、`scheme` 與 `status`：`field:"value"` 進行精確比對，`field~"value"` 進行不分大小寫的子字串比對，前置的 `-` 則否定任一運算子。例如，`-git_branch~"gh-readonly-queue"` 會排除合併佇列分支。以空白分隔的查詢篩選器與明確引數會以 AND 語意組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 取得測試執行的詳細指標，包含其結果套件（`.xcresult`）與工作階段封存檔的暫時下載網址。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行的測試模組執行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行的測試套件執行，可選擇依模組篩選。 | `test_run_id` |
| `list_test_cases` | 列出專案的測試案例（支援如 `flaky` 等篩選器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 取得測試案例的詳細指標，包含可靠性比率、不穩定性比率與執行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例執行，可選擇依測試案例或測試執行篩選。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 取得特定測試案例執行的失敗詳情與重複次數。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例執行的附件。每個附件都包含暫時下載網址。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例的狀態變更，例如將其靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例的狀態或不穩定分類。變更可以將事件分派至設定的 webhook 端點，包括外部服務。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試執行的選擇性測試目標結果。 | `test_run_id` |
| `get_coverage` | 取得專案的程式碼涵蓋率及其目標，可在特定提交或分支的最新完整提交時取得。若未提供 `git_commit_sha` 或 `branch`，則讀取預設分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出在特定提交或分支的最新完整提交時，由程式碼涵蓋率測量的檔案及其行涵蓋率。支援 `search`、排序與分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 取得在特定提交或分支的最新完整提交時，檔案的程式碼涵蓋率及其函式。設定 `include_lines` 以取得每行的執行次數。 | `account_handle`, `project_handle`, `path` |

程式碼涵蓋率工具僅供已啟用程式碼涵蓋率的帳號使用。

#### 套件

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出專案的套件（應用程式二進位檔）。 | `account_handle`, `project_handle` |
| `get_bundle` | 取得特定套件的詳細資訊。 | `bundle_id` |
| `get_bundle_artifact_tree` | 以依路徑排序的平面清單取得套件的完整構件樹。 | `bundle_id` |

#### 生成執行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_generations` | 列出專案的生成執行。 | `account_handle`, `project_handle` |
| `get_generation` | 取得特定生成執行的詳細資訊。 | `generation_id` |

#### 快取執行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出專案的快取執行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 取得特定快取執行的詳細資訊。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出生成或快取執行的模組快取目標，顯示每個目標的快取命中／未命中狀態與診斷元件雜湊，包含額外的雜湊輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_previews` | 列出專案的可分享應用程式預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 取得預覽及其建置的暫時下載網址。 | `preview_id` |
| `get_latest_preview` | 找出正在運行的應用程式二進位檔的最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出專案的自動化警示。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 取得自動化警示。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警示的修訂歷史。動作憑證會經過遮罩處理。 | `alert_id` |
| `list_project_notification_alerts` | 列出專案通知警示規則。需要與儀表板設定頁面相同的管理員權限。Webhook 位址會經過遮罩處理。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期的用戶端可以呼叫 `events/list` 來探索事件及其負載結構：

| 事件 | 發送時機 | 訂閱篩選器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從非不穩定變更為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本機或持續整合的 Xcode、Gradle 或 Bazel 建置以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本機或持續整合的測試執行以失敗結束，包含合併的分片執行或已放棄的執行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist 執行器作業以失敗完成。 | `account_handle` |

若要訂閱，用戶端需呼叫 `events/subscribe`，並提供事件名稱、上述 `arguments` 中列出的帳號代號，以及包含 `https://` 回呼網址與 `whsec_` 簽署金鑰的 `webhook` 遞送設定。專案事件需要帳號成員資格與對應測試或建置資料的讀取權限；執行器作業事件需要帳號成員資格與執行器讀取權限。已聲明的 [`auth.md`](https://workos.com/auth-md) 存取權杖、已聲明的帳號權杖，以及瀏覽器授權授予均可建立訂閱；當相關憑證不再有效時，遞送將停止。每位使用者最多可保留 25 個作用中的訂閱。Tuist 會在儲存訂閱前向回呼網址發送驗證挑戰。回呼必須傳回包含相同 `challenge` 值的物件。訂閱預設持續七天，可透過再次訂閱來續期，並在使用者存取權或憑證被移除時停止遞送。可選的 `ttlMs` 限制在一小時至 30 天之間。Tuist 會對超時的回呼進行重試，並在至少三次連續超時（橫跨五分鐘）後取消訂閱；請在恢復回呼後重新訂閱。

當事件發生時，Tuist 會將其資源識別碼和儀表板網址傳送至回呼。建置與測試執行失敗也包含 `is_ci` 和 `git_branch`，因此用戶端可以忽略本機失敗或依分支篩選。建置事件包含 `build_system`；執行器作業事件則同時包含 `workflow_job_id` 和 `workflow_run_id`。請求包含訂閱識別碼與 [Standard Webhooks](https://www.standardwebhooks.com/) 簽章標頭，以便用戶端驗證其來源。Tuist 會重試失敗的遞送，因此用戶端應使用穩定的 `eventId` 來捨棄重複項目。負載省略了測試名稱、日誌和失敗訊息；用戶端可以透過上述工具取得這些詳細資訊，並決定是否通知團隊或開始除錯。用戶端可以使用 `events/unsubscribe` 停止遞送。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 引導你修復不穩定測試，包括分析失敗模式、識別根本原因，並套用針對性的修正。 |
| `compare_builds` | 引導你比較兩次建置執行，以識別效能衰退、快取變更和建置問題。適用於 Xcode 和 Gradle 專案。 |
| `compare_test_runs` | 引導你比較兩次測試執行，以識別衰退、新失敗和不穩定測試。 |
| `compare_bundles` | 引導你比較兩個套件，以識別構件樹中的大小變更。 |
| `compare_test_case` | 引導你比較測試案例在兩個分支或時間段內的行為。 |
| `compare_generations` | 引導你比較兩次生成執行，以識別效能衰退和模組快取變更。 |
| `compare_cache_runs` | 引導你比較兩次快取執行，以識別快取效率變更和目標層級的衰退。 |
| `integrate_gradle_project` | 引導你將 Tuist 整合至現有的 Gradle 專案。內容包含獨立的工具與 Gradle 驗證、帳號探索、專案建立、遠端快取政策、建置洞察，以及讀回驗證。 |
| `integrate_bazel_project` | 引導你建立或選擇 Bazel 專案、驗證命令列、設定遠端快取與建置洞察，並透過 Tuist 建置資料驗證整合結果。 |
| `integrate_xcode_project` | 引導你將 Tuist 整合至現有的 Xcode 專案。支援 Xcode 快取、建置洞察、測試洞察和測試分片。 |
| `ask_tuist` | 使用公開材料作為背景脈絡，並以聚焦的實作與測試證據作為目前行為的真實依據，來回答 Tuist 相關問題。它需要一個 `question`，並引用修訂綁定的證據。 |

專案資料提示接受 `account_handle` 和 `project_handle`，以將調查範圍限定於特定專案。比較提示也接受 `base` 和 `head` 引數，以指定要比較的兩個項目（依 ID、儀表板網址或分支名稱）。`ask_tuist` 接受 `question` 而非專案參數。`integrate_gradle_project` 也接受 `features`，這是一個以逗號分隔的 Gradle 整合清單：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可選的 `server_url`，用於自託管或本機安裝。`integrate_xcode_project` 接受包含 `features`、`xcode_cache`、`build_insights` 和 `test_insights` 的 `test_sharding`。

#### Gradle 整合提示功能

`integrate_gradle_project` 提示和 `get_gradle_integration_guide` 工具記錄了完整的設定工作流程。伺服器的初始化指示也會參考此工具，讓未列舉提示的代理程式也能發現它。

| 功能 | 代理程式設定的內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 的建置快取、設定 Tuist 遠端快取上傳政策，並建議僅從具有本機唯讀使用权的持續整合執行器進行上傳。 |
| `build_insights` | 套用 Tuist Gradle 外掛程式，並在需要時設定建置分析上傳行為。 |
| `test_insights` | 套用 Tuist Gradle 外掛程式，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 引導設定不穩定測試偵測、可選的 Gradle Test Retry 外掛程式用法，以及測試隔離設定。 |
| `test_sharding` | 新增 `tuistPrepareTestShards` 的持續整合工作流程、分片矩陣生成，以及基於 `TUIST_SHARD_INDEX` 的測試執行。 |

當省略 `features` 時，提示會要求代理程式釐清使用者想要的整合項目，或在編輯 Gradle 專案前從請求中推斷出最小的實用組合。

#### Xcode 整合提示功能

`integrate_xcode_project` 提示記錄了 Tuist 支援的每項 Xcode 整合：

| 功能 | 代理程式設定的內容 |
|---------|---------------------------|
| `xcode_cache` | 設定 `tuist setup cache`、生成專案的快取設定、手動 Xcode 快取建置設定，以及限制為僅限持續整合執行器的上傳政策。 |
| `build_insights` | 透過 `tuist setup insights` 設定 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 以及可選的機器指標。 |
| `test_insights` | 設定 `tuist inspect test`、方案測試後動作，以及持續整合測試執行的結果套件生成。 |
| `test_sharding` | 新增 Xcode 或生成專案的分片規劃與分片執行工作流程，並使用 `TUIST_SHARD_INDEX`。 |

當省略 `features` 時，提示會要求代理程式釐清使用者想要的整合項目，或在編輯 Xcode 專案前從請求中推斷出最小的實用組合。
