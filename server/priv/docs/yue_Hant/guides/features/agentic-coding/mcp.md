---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 嘅 MCP 端點，讓 AI 代理存取測試洞察等功能。"
}
---
# 模型上下文協議

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一項開放標準，讓人工智能代理能夠與外部服務及數據來源互動。它令 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等應用程式，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等編輯器都能與 Tuist 互通。

Tuist 在 `https://tuist.dev/mcp` 託管伺服器端的 Model Context Protocol 端點。將你的客戶端連接至此端點後，代理即可存取你的 Tuist 專案數據，包括測試洞察、不穩定測試分析等。大部分工具皆為唯讀，且範圍限於已驗證的 Tuist 專案數據。帳戶設定工具可在已驗證使用者具備所需權限時，列出帳戶、建立組織、建立專案，以及將現有使用者加入組織。每個工具都會標示註解，說明其是否為唯讀、是否可能導致難以復原的變更，以及是否會改變公開網際網路狀態。帳戶設定工具需要使用者驗證。它們不適用於專案權杖或一般帳戶權杖。當使用者在瀏覽器中授權客戶端或聲明 `auth.md` 註冊時，Tuist 僅在 Model Context Protocol 端點上將該憑證與使用者關聯，以便設定工具完成所請求的工作流程。

Tuist 實作了 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求為無狀態：客戶端會在每次請求中傳送其協議元數據，並可直接呼叫工具而無需初始化。`server/discover` 會傳回伺服器的身份、功能、支援的版本及指示。沒有工作階段識別碼或獨立的事件串流。使用 2025-06-18 或 2025-03-26 初始化流程的客戶端仍受支援；它們同樣無需伺服器工作階段即可運作。

## Model Context Protocol 與技能比較

Model Context Protocol 工具與 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 的功能可能重疊。鑑於目前兩者存在重疊，請為每個工作流程選擇其中一種方法並一致使用，避免在同一流程中混合使用兩者。

對於支援外掛安裝的客戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 一併安裝兩者。

## 設定

在客戶端中將 `https://tuist.dev/mcp` 新增為遠端 Model Context Protocol 伺服器。伺服器的初始化指示及公開伺服器卡片會內嵌描述採用動態客戶端註冊的 OAuth 2.0 及標準瀏覽器授權流程，無須要求代理擷取或遵循外部驗證文件。這些伺服器層級的指示保持工作流程指引的通用性：工具驗證不會驗證本機命令列工具或建構系統整合，代理應透過相關的 Tuist 工具驗證所請求的變更。特定建構系統的設定及驗證檢查記錄於整合指南及提示中。Tuist 仍分別宣傳 [Open Authorization](https://oauth.net/2/) 探索元數據及位於 `https://tuist.dev/auth.md` 的當前 [auth.md protocol](https://workos.com/auth-md)。

如果你的其中一個組織強制執行單一登入，則在瀏覽器中授權客戶端需要透過該組織簽署的工作階段，且在必要時 Tuist 會先將你導向至提供者。參閱 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>。

該端點接受無狀態的 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），以及較舊的基於工作階段的生命週期。現有客戶端可以繼續使用目前的連線方法。

支援 Model Context Protocol 事件的客戶端可以訂閱專案事件。有關可用事件及交付要求的詳情，請參閱 [Events](#events)。

已支援遠端瀏覽器驗證的客戶端可以繼續在瀏覽器中進行驗證。支援 `auth.md` 的客戶端及代理可以匿名註冊、出示受信任的提供者身份斷言，或啟動服務驗證的電子郵件聲明。註冊會傳回由 Tuist 簽署的身份斷言，代理可在標準權杖端點將其交換為一小時的存取權杖。Tuist 會發布其公開簽章金鑰，並支援標準權杖撤銷及提供者安全事件交付。

未經驗證的代理應讀取 Model Context Protocol 端點傳回的 `WWW-Authenticate` 標頭，擷取受保護資源元數據，擷取授權伺服器元數據，並遵循其 `agent_auth.skill` URL。Tuist 也會在未授權回應主體中傳回相同的本地 `auth_md` URL，讓語言模型驅動的客戶端無需依賴原生客戶端整合即可發現該流程。部署本地文件是端點名稱、請求主體、聲明輪詢及斷言交換的真實來源。

在代理啟動電子郵件聲明之前，必須要求使用者確認其 Tuist 帳戶的電子郵件地址。不得從提供者個人資料、Git 設定、環境變數或工作階段元數據推斷該地址。

該端點使用 `mcp` 範圍群組。匿名的預聲明憑證可以探索功能及讀取公開整合指引，但不會被視為已登入使用者。經過瀏覽器授權或聲明後，該憑證將限定於使用者範圍，且每個工具都會套用與儀表板相同的授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析至已驗證使用者已有權讀取的專案。Xcode 及 Gradle 建構工具接受建構 UUID 或儀表板 URL。UUID 必須唯一識別一個專案；如果它出現在多個專案中，工具會傳回找不到，而不會選擇另一個專案的報告。專案範圍的儀表板及 API 讀取仍然可用。回報的行為者識別碼是未經驗證的標籤，並非憑證或額外的存取權限。

建構清單及詳細資訊工具會公開可選的 `tuist_version` 元數據：用於 Xcode 及 Cargo 的回報 Tuist CLI、用於 Gradle 的 Tuist Gradle 外掛程式，以及用於 Mix 的 `tuist_ex` 函式庫。Xcode 亦會從其連結的專案生成事件中公開 `tuist_generation_version`，該版本可能與上傳用的 CLI 不同。缺失的觀測值為 null，不會從伺服器或其他報告推斷。Bazel 使用其現有的 `bazel_version`；Once 執行詳細資訊則公開 `once_version`。這些欄位描述回報的版本，並非已驗證的身份或線路協定版本。REST 建構端點會公開相同的元數據。現有的整合及不穩定測試技能不依賴版本欄位，無需變更工作流程。

Tuist 營運人員透過 Tuist 的內部營運工具調查客戶帳戶，該工具會記錄每次呼叫；直接連線至此端點不會獲得超出使用者自身成員資格以外的存取權限。

<details>
<summary>Claude Code</summary>

執行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 客戶端未向模型公開失敗的原生伺服器連線時，要求代理在搜尋託管文件或編輯專案之前，檢查已設定端點的未經驗證 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 回應。該回應會將模型指向部署本地的 `auth.md` 文件，即使瀏覽器驗證不可用亦然。

</details>


<details>
<summary>Codex</summary>

執行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在開始新的 `codex exec` 執行之前完成瀏覽器登入。Codex 會在初始化期間讀取 Tuist 伺服器指示，因此 Gradle 優化請求會自動接收驗證及驗證工作流程。

</details>


<details>
<summary>Claude Desktop</summary>

開啟 **Settings → Connectors → Add custom connector**，然後設定：

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

在提示時於瀏覽器中完成 [Open Authorization](https://oauth.net/2/)。

</details>


<details>
<summary>Pi</summary>

Pi 不包含 Model Context Protocol 客戶端。你可以在檢視其原始碼及安全影響後安裝第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 擴充功能：

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

將 `auth` 設定為 `false` 可防止適配器的瀏覽器驗證處理程序隱藏 Tuist 的未授權回應。無頭代理隨後可以讀取傳回的 `auth_md` URL，並遵循 Tuist 的註冊、身份斷言交換及聲明輪詢流程。將交換後的存取權杖設定為 bearer token，或讓代理直接進行已驗證的 Model Context Protocol 呼叫。

如果你偏好瀏覽器驗證，請將 `auth` 設定為 `"oauth"`。對於該流程，請在驗證完成期間使用 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 保持一個行程活躍：

```bash
pi --mode rpc
```

不要將待處理的瀏覽器驗證分割到多個 `pi --print` 呼叫中，因為擁有回呼狀態的行程已結束。

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

如果你的代理支援 `auth.md`，它可以匿名啟動而無需開啟瀏覽器。當提供者身份已連結時，受信任的提供者身份也可以在無需瀏覽器的情況下完成。對於服務驗證的電子郵件、匿名聲明或首次提供者連結，代理會向你顯示 Tuist 驗證連結及六位數代碼。開啟連結，登入，並在 Tuist 頁面上輸入代理的代碼。切勿將代碼傳回給代理。Tuist 的授權伺服器元數據直接指向部署自身的 `/auth.md`，其中包含確切的請求及輪詢結構。

## WebMCP

在支援 [WebMCP](https://webmachinelearning.github.io/webmcp) 的瀏覽器中，Tuist 的頁面會使用 `document.modelContext` 註冊工具，因此內建於瀏覽器的代理可以在無需額外設定的情況下呼叫它們。這些呼叫在 Tuist 伺服器上執行。

- **Website and documentation pages** 會註冊文件及原始碼工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 及 `read_tuist_file`）。它們不需要你登入。
- **An account's dashboard pages** 在你登入時，會為該帳戶註冊 Tuist 的唯讀工具。每個頁面僅註冊其顯示內容所需的工具，針對專案的建構系統：Gradle 專案的建構頁面會取得 Gradle 建構工具，其測試頁面會取得測試及涵蓋率工具，而執行器頁面會取得執行器工具。每個頁面也會取得文件工具、`list_projects` 及 `get_project`。這些工具以已登入使用者的身份執行，因此它們只能存取你在儀表板中可讀取的資料，且僅限於你正在檢視的帳戶。當你移至另一個頁面或帳戶時，工具會被該頁面的工具取代。

建立、變更或刪除資料的工具無法透過 WebMCP 使用，因為瀏覽器代理會在無需你新增的情況下接收這些工具，並讀取建構及測試產生的內容。將 MCP 客戶端連線至 `/mcp` 端點以使用這些工具。

如果組織強制使用單一登入，請使用其提供者登入儀表板以使用其工具。

## 建構系統整合使用兩種憑證

用於 Model Context Protocol 工具的憑證不會驗證 Gradle 外掛程式或 Bazel 的遠端服務。在代理編輯或驗證 Gradle 或 Bazel 整合之前，它應執行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未通過驗證，代理必須停止並要求使用者執行：

```bash
tuist auth login --url https://tuist.dev
```

對於本機或自託管部署，請替換兩個命令及 `tuist.toml` 中的 URL。在所有地方保持主機名稱拼寫一致。例如，`localhost` 和 `127.0.0.1` 使用單獨儲存的憑證。


## 功能

### 工具

以下工具可透過 Tuist Model Context Protocol 伺服器使用：

每個工具都會發布人類可讀的描述以及明確的輸入和輸出架構。成功的呼叫會返回符合所宣告輸出架構的結構化內容，並將相同結果序列化為文字，供尚未使用結構化內容的客戶端使用。

接受單個記錄識別符的工具（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）也接受該記錄的 Tuist 儀表板 URL。直接從瀏覽器貼上 URL，而不是從中提取識別符。

#### 文件和社群搜尋

此唯讀工具透過支援文件網站的同一個搜尋引擎，搜尋 Tuist 的文件、[application programming interface](https://en.wikipedia.org/wiki/API) 參考、GitHub 發行版、社群論壇和 GitHub issue。發行版結果包括產品、版本、發布日期和預發布狀態。預設搜尋穩定發行版，可以使用 `include_prereleases` 包含預發布版。此工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜尋公開的 Tuist 文件、application programming interface 參考、GitHub 發行版、社群討論和 GitHub issue。可選擇限制為一個 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 回饋

當 Tuist 工具或提示未按預期運作時（例如結果令人困惑、錯誤、資料缺失或功能缺失），代理可以告知 Tuist 團隊。系統會要求代理建議一份報告，並僅在你同意後發送。每份報告都會開啟與 Tuist 支援的對話，他們可能會透過電子郵件回覆你。報告包括代理的預期、實際發生的情況、可選建議、你的 Tuist 使用者 ID、帳號和電子郵件，以及你所屬的組織。代理還可以命名問題發生的帳戶和專案，以便團隊知道要跟進哪個組織；僅接受你所屬的帳戶。只有以 Tuist 使用者身份登入的代理才能發送報告，且每個使用者每小時最多可以開啟 10 份報告。此工具僅在 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `report_feedback` | 報告 Tuist 工具或提示的問題。可選命名 `tool_name`、問題發生的 `account_handle` 和 `project_handle`，並添加 `suggestion`。 | `category`, `expected`, `actual` |

#### 基於原始碼的回答

這些唯讀工具讓代理使用與託管伺服器一起部署的確切公開 Tuist 原始碼修訂版，作為依賴當前行為的答案的事實來源。它們僅在 `https://tuist.dev/mcp` 可用。

相容的客戶端在初始化期間會收到工具原始碼修訂版的事實描述、連結和結果限制，以及內聯 OAuth 驗證資訊。這些描述不規定回答風格或驗證工作流程。使用者可以直接提問，無需先呼叫 `ask_tuist` 提示；該提示仍可用於明確的基於原始碼的工作流程。

每個操作都有固定的併發、持續時間、遍歷、讀取位元組數和回應大小限制。搜尋和列表結果包括 `truncated` 和 `truncation_reason` 欄位。當結果被截斷時，請縮小路徑、檔案模式或搜尋詞，而不是將結果視為詳盡無遺。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 透過搜尋原始碼檔案來回答有關當前行為、預設值、設定、功能開關、錯誤處理或未記錄細節的問題。結果包括周圍的行、修訂版固定的原始碼連結和掃描統計數據。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，發現原始碼子系統或附近的測試。列表具有有限的深度和結果數量。 | 無 |
| `read_tuist_file` | 在找到相關路徑後，檢查實現檔案、呼叫站點或測試中的特定行範圍。截斷的回應提供 `next_start_line` 以繼續。 | `path` |

#### 專案

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出已驗證使用者可用的個人和組織帳戶帳號，包括每個帳戶是否可以建立專案。 | 無 |
| `get_organization` | 獲取組織的成員目錄。待處理的邀請需要與儀表板相同的管理員權限；永遠不會返回邀請接受令牌。 | `account_handle` |
| `create_organization` | 為已驗證使用者建立 Tuist 組織。 | `handle` |
| `create_project` | 在已驗證使用者可存取的帳戶下建立 Tuist 專案。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有 Tuist 使用者加入組織，或更新現有成員的角色。接受 `user`（預設）、`admin` 或 `viewer`，其中檢視者可以閱讀儀表板和執行記錄，但無法更改任何內容。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有 Tuist 使用者。Tuist 會發送一個有效期為 14 天的接受連結；當伺服器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製連結。接受 `user`（預設）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其連結無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出已驗證使用者可存取的所有專案。 | 無 |
| `get_project` | 獲取專案的配置和連接的儲存庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將專案連結到帳戶的 GitHub App 安裝可存取的 GitHub 儲存庫。專案會採用儲存庫的預設分支。需要專案管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除專案與其 GitHub 儲存庫的連結。需要專案管理員權限。 | `account_handle`, `project_handle` |

#### 帳戶令牌

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳戶令牌元數據，而不暴露令牌值。 | `account_handle` |
| `get_account_token` | 獲取帳戶令牌元數據，而不暴露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出專案令牌元數據，而不暴露令牌值。 | `account_handle`, `project_handle` |

#### 持續整合執行器

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳戶的持續整合執行器作業。 | `account_handle` |
| `get_runner_job` | 獲取持續整合執行器作業。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續整合執行器作業記錄的步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續整合執行器作業記錄的機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續整合執行器作業最多 500 條捕獲的日誌行。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳戶的持續整合工作流程匯總。 | `account_handle` |
| `list_runner_profiles` | 列出帳戶的持續整合執行器設定檔，並包含每個設定檔的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出執行器設定檔可使用的機器規格和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 建立具有平台、機器規格以及在 macOS 上的 Xcode 版本的執行器設定檔。可選設定哪些分支保存其快取卷。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 更改執行器設定檔的機器規格、Xcode 版本，或哪些分支保存其自訂快取卷更改。省略的欄位保持其值。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 在使用者確認後刪除執行器設定檔。預設設定檔無法刪除。需要帳戶管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

執行器卷工具公開與卷儀表板相同的數據。讀取工具需要執行器存取權限；清除需要帳戶管理權限或 `account:runners:write` 範圍，以及使用者確認。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 按名稱和儲存庫過濾，排序和分頁卷。 | `account_handle` |
| `get_runner_volume` | 儲存庫、平台、容量、已用空間和最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁的作業和工作流程參考、快取狀態、命中結果和掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由作業掛載的卷。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 儲存趨勢、作業執行次數、命中率及趨勢。可選 `volume_id`、`start` 和 `end`（ISO 8601）；預設為七天，最多 90 天。 | `account_handle` |
| `clear_runner_volume` | 清除已儲存的內容。執行中的作業會保留其私人副本但無法儲存；後續作業將從空白狀態開始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。卷庫存還接受 `name` 和 `repository`（精確匹配，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的測量值和命中結果保持為 `null`。快取狀態描述卷更改是否已儲存，而非作業成功與否。

#### Webhook

Webhook 工具使用與儀表板相同的管理員專用權限。傳送嘗試包含為端點記錄的請求和回應數據，但絕不包含端點簽名密鑰。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳戶的 Webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 獲取 Webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點的傳送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 獲取一次傳送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 建構

適用於 Xcode、Gradle、Bazel、Mix 和 Cargo 的建構詳細資訊工具公開現有的 `custom_metadata: {tags, values}` 結構，包括基礎設施觀察結果（如有報告）。值保持為字串，並保留不熟悉的鍵。例如，`tuist.cpu.available_processors` 描述執行時可用的邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作器限制，`tuist.jvm.max_heap_bytes` 是 JVM 堆積限制，而非主機記憶體。這些是不可信的客戶端觀察結果，而非經過驗證的執行器身份。缺失的觀察結果仍保持缺失；匯入的日誌和較舊的客戶端可能沒有基礎設施元數據。一次性元數據等待協調的客戶端/協議更新。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出專案的 Xcode 建構執行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 獲取特定 Xcode 建構執行的詳細資訊，包括保存原始 `.xcactivitylog` 的歸檔文件的臨時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 建構執行的建構目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 建構執行的編譯文件。 | `build_run_id` |
| `list_xcode_build_steps` | 列出記錄的建構步驟，包含時間和結果，但不含日誌文本。 | `build_run_id` |
| `get_xcode_build_step` | 獲取一個記錄的建構步驟，包括其日誌和截斷標誌。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定建構執行的建構問題（警告和錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 建構執行的可快取任務（快取命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 建構執行的 [內容定址儲存](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 預設返回每頁 20 個步驟（透過 `page_size` 最多 100 個），並提供 `page` 和 `pagination_metadata` 用於導航。使用 `search` 匹配標題、專案或目標，或過濾精確的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。按 `duration_ms` 排序以最慢優先（預設），或按 `start_ms` 排序以獲得時間順序。步驟 ID 用於打破平局，並作為十進位字串返回以保留其完整的 64 位精度。ID 僅限於單一建構，不應跨建構匹配。

可選的 `start_ms` 和 `end_ms` 選擇與從建構開始起算的毫秒時間範圍重疊的步驟；結束時間為exclusive。兩個工具都接受建構 UUID 或儀表板 URL 作為 `build_run_id`。將返回的步驟 `id` 原樣作為 `step_id` 傳遞以檢索其日誌。每個步驟的日誌最多保留 64 KiB，`log_truncated` 表示省略的輸出。

處理 Xcode 建構時預設會收集步驟。記錄的步驟數據保留 90 天。列表回應包括 `availability`：當存在記錄的步驟時為 `available`，即使過濾器沒有匹配項；當建構仍在處理且尚無步驟時為 `processing`；或者當步驟未記錄或已過期時為 `unavailable`。

相同的操作可透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 上使用，具有相同的過濾器和分頁功能。兩者都需要對建構專案的讀取權限。

#### Gradle 建構

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 返回完整的身份驗證、專案設置、Gradle 插件、快取策略和兩次建構驗證工作流程。代理在編輯現有的 Android 或 Gradle 專案之前應調用此接口。 | 無 |
| `list_gradle_builds` | 列出專案的 Gradle 建構執行，包括自訂元數據。使用可選的 `tag` 參數按自訂標籤過濾。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 獲取建構元數據和任務/快取計數。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出任務結果、複合建構身份、可快取性和增量狀態。 | `build_run_id` |
| `list_gradle_build_steps` | 列出定時任務、配置和轉換，支援搜索、元數據和重疊時間過濾器。 | `build_run_id` |
| `get_gradle_build_step` | 透過不透明 ID 檢查記錄的步驟元數據；每個步驟的日誌不可用。 | `build_run_id`, `step_id` |

Gradle 和 Bazel 步驟列表預設返回 20 個結果（最多 100 個），支援 `search`、精確的 `project`、`target`、`category` 和 `status`、重疊的 `start_ms` / `end_ms` 過濾器（結束時間為 exclusive），以及按 `duration_ms` 或 `start_ms` 排序。原樣傳遞返回的 ID；它們僅限於其所属的建構。列表公開 `time_origin` 和 `coverage`。較舊的 Gradle 報告使用 `first_recorded_timestamp`，因為沒有上傳建構開始時間。Bazel 配置文件公開所有記錄的間隔，覆蓋範圍為 `trace_profile`，時間起點為 `profile_start`。較舊的建構回退到保留的 BEP 摘要。源記錄在 90 天後過期。Bazel 詳情在發布時包含經過清理的操作日誌；Gradle 詳情 `log` 為 null。`compare_builds` 提示使用此覆蓋範圍來區分完整的 Bazel 追蹤與保留的摘要，並指引代理在檢查更廣泛的調用輸出之前，查看步驟詳情以獲取操作結果和日誌。

如果在列出步驟和獲取步驟之間到達了完整的配置文件，則從保留摘要返回的 Bazel 步驟 ID 仍然可讀。如果步驟數據已過期，索引配置文件會報告為不可用。Gradle 步驟列表包括零持續時間的快取和跳過操作。

#### Bazel 調用

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 返回身份驗證、專案設置、Bazel 配置和驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成的 [Bazel Build Event Protocol](https://bazel.build/remote/bep) 調用，包括建構指標、有界的執行時間線、關鍵路徑診斷以及專案相關的遠程快取總計。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 獲取一個已完成的 Bazel 調用，包括建構指標、有界的執行時間線、關鍵路徑診斷以及相關的遠程快取總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出記錄的 Bazel 配置文件間隔，帶有過濾器和明確的覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查記錄的 Bazel 步驟及其發布的操作結果和經過清理的日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 按執行順序列出為 Bazel 調用捕獲的經過清理的測試日誌。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 獲取為 Bazel 調用捕獲的一個經過清理的測試日誌。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 遠程快取觀察結果，包括其操作、端點和觀察時間，可選擇縮小到特定調用、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 獲取一個原始的 Bazel 遠程快取觀察結果。 | `account_handle`, `project_handle`, `cache_event_id` |

#### Cargo 建構

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出專案的 Cargo 建構，最新的排在前面。按 `git_branch`、`status`、`is_ci` 或 `command` 過濾。Cargo 測試執行結果可透過測試工具獲得，而非此建構列表。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 獲取建構元數據、聚合快取計數器，以及最多 500 個帶有診斷信息的記錄編譯器作業。`compilations_truncated` 表示省略的作業；診斷信息僅涵蓋返回的作業。 | `account_handle`, `project_handle`, `build_id` |

在 `get_cargo_build` 上設置 `include_cache_inspection: true` 以檢索經過驗證的任務決策和 CAS 操作，限制為 4 MB。預設情況下，以及當記錄缺失或無效時，`cache_inspection` 為 null。請尊重其部分捕獲的 `truncated` 標誌；傳輸不會確定每個任務命中的本地/遠程來源。HTTP 詳情端點接受相同的查詢參數。

#### Mix 建構

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出專案的 Mix (Elixir) 編譯建構，最新的排在前面，包括自訂元數據。按 `git_branch`、`status`、`is_ci` 或 `mix_env` 過濾。 | `account_handle`, `project_handle` |
| `get_mix_build` | 獲取建構元數據、診斷計數和依賴快取摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 建構追蹤

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_build_trace` | 獲取 Xcode、Gradle、Bazel 或 Mix 建構時間線的下載鏈接，作為可在 [Perfetto](https://ui.perfetto.dev) 中打開的追蹤文件。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 是建構運行 ID（Bazel 的調用 ID）或建構的儀表板 URL。返回的 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 文件。任何持有該鏈接的人都可以下載該建構的追蹤，無需其他憑證，直到 `expires_at`，即調用後一小時。代理可以使用 `curl` 下載它，交給你並在 Perfetto 中打開，或使用 Perfetto 的 `trace_processor` 進行查詢。追蹤包含按並行性打包到通道中的記錄步驟、跨越整個建構的軌道，以及在建構記錄機器指標時的 CPU 和內存計數器。它包含與上述步驟工具相同的數據，但沒有日誌。儀表板從每個建構的時間線標籤頁提供相同的文件。

#### Once 運行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出專案的 Once 運行，最新的排在前面。按 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 過濾。未完成的運行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 獲取一次運行的數據，包括其操作總數、快取摘要，以及測試運行的測試總數。 | `account_handle`, `project_handle`, `run_id` |

Cargo 建構、Mix 建構和 Once 運行的 ID 在專案內是唯一的。透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 和 `.../once/runs` 提供相同的讀取功能，每個端點都有一個用於單一 ID 的詳情端點。

#### 任務、操作、模組和文件

這些專案範圍的工具檢查跨運行的持久建構身份。首先使用 `list_build_entities`，然後將返回的穩定 `id` 與相同的 `kind` 傳遞給 `get_build_entity` 或 `list_build_entity_history`，並連同 `account_handle` 和 `project_handle`。不需要建構或調用標識符。

| 工具 | 描述 | 必要參數 |
| --- | --- | --- |
| `list_build_entities` | 列出在專案建構中看到的某一類型的任務、模組、操作或文件。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 獲取一個建構實體，包括其本機身份和所選時期的分析數據。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個建構實體的記錄執行、編譯或快取事件，最新的排在前面。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史列表 |
| --- | --- | --- |
| `bazel_actions` | Bazel 操作 | BEP 報告的操作執行 |
| `gradle_tasks` | Gradle 任務 | 任務執行 |
| `xcode_modules` | Xcode 模組 | 編譯和模組快取事件 |
| `once_actions` | Once 操作 | 執行 |
| `mix_files` | Mix 編譯文件 | 編譯 |
| `mix_modules` | Mix 編譯模組 | 編譯 |
| `cargo_crates` | Cargo crates | 記錄的 rustc 調用 |

這些工具正在逐步推出，僅返回已啟用的專案數據；對於其他專案，它們返回錯誤而不是空結果。某種類型僅對使用其建構工具鏈的專案可用。工具接受有界的 `start_at`/`end_at` 過濾器、`environment`（`any`、`ci` 或 `local`）和精確的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支持不透明的 `after`/`before` 游標。未知的計時或快取觀察結果保持不可用，而不是變成零或遺失。歷史記錄引用記錄的父級和本機執行，以便使用現有的運行工具進行深入分析。

`get_build_entity` 指標包括 `duration_samples`，即具有記錄計時的觀察次數：真正的零持續時間計入，缺少計時則不計入。此計數可能低於觀察次數；不可用的持續時間統計信息保持為 null。

Xcode 模組的持續時間來自建構日誌中測量的目標編譯。模組快取解析和沒有編譯工作的目標不會貢獻持續時間樣本。編譯觀察結果引用 Xcode 建構；快取事件引用生成或快取命令。

Bazel 操作由目標標籤、助記符和配置的主要輸出標識，使單獨的操作和配置保持區別，而不依賴於輸入依賴的快取摘要。歷史記錄 BEP 報告的執行，而不是快取查找或追蹤配置文件階段。完整的執行覆蓋需要 `--build_event_publish_all_actions`；工件交付是盡力而為，因此缺少觀察結果並不證明沒有工作運行。較舊的 Kura 負載如果沒有穩定的身份或執行開始，仍然被接受但未編入索引。缺少結束時間測量保持不可用，真正的零持續時間計入。

Mix 模組的持續時間測量包含文件的編譯，而不是獨立測量的模組工作。Once 操作在客戶端報告目標映射時使用聲明的目標/能力/索引槽；僅診斷標籤不是穩定的身份。現有的客戶端和運行級別工具保持不變的支持。

Cargo crates 按精確記錄的 crate 根、名稱和類型分組。檢出路徑更改可能會分割歷史，並且建構配置文件、功能和目標三元組不會區分。歷史測量 rustc 調用，而不是每個文件的工作或快取命中；缺少的作業不會確定刪除或完整的工作區清單。

分析讀取具有有限的內存和執行時間。如果查詢超過這些限制，工具將返回錯誤，而不是發明一個空結果。

新觀察結果在部署後編入索引；此功能不會回填現有的運行遙測數據。身份元數據在 <.localized_link href="/guides/server/data-retention">數據保留政策</.localized_link>下比單個觀察結果更長久。

#### 測試

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出專案的測試運行。`query` 字段是 `git_branch`、`scheme` 和 `status`：`field:"value"` 精確匹配，`field~"value"` 匹配不區分大小寫的子字符串，前導 `-` 否定任一運算符。例如，`-git_branch~"gh-readonly-queue"` 排除合併隊列分支。空格分隔的查詢過濾器和顯式參數與 AND 語義結合。 | `account_handle`, `project_handle` |
| `get_test_run` | 取得測試執行的詳細指標，包括其結果套件（`.xcresult`）和會話存檔的臨時下載網址。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行的測試模組運行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行的測試套件運行，可選擇按模組篩選。 | `test_run_id` |
| `list_test_cases` | 列出專案的測試案例（支援如 `flaky` 等篩選器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 取得測試案例的詳細指標，包括可靠性比率、不穩定性比率和執行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例運行，可選擇按測試案例或測試執行篩選。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 取得特定測試案例運行的失敗詳情和重複次數。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例運行的附件。每個附件都包含一個臨時下載網址。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例的狀態變更，例如將其靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例的狀態或不穩定分類。變更可以將事件分派到已配置的 webhook 端點，包括外部服務。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試執行的選擇性測試目標結果。 | `test_run_id` |
| `get_coverage` | 取得專案在特定提交或分支最新完整提交的程式碼覆蓋率及其目標。如果沒有 `git_commit_sha` 或 `branch`，則讀取預設分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出在特定提交或分支最新完整提交時，程式碼覆蓋率所測量的文件及其行覆蓋率。支援 `search`、排序和分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 取得檔案在特定提交或分支最新完整提交時的程式碼覆蓋率及其函數。設定 `include_lines` 以取得每行的執行次數。 | `account_handle`, `project_handle`, `path` |

程式碼覆蓋率工具僅供已啟用程式碼覆蓋率的帳戶使用。

#### 套件

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出專案的套件（應用程式二進位檔）。可選擇按 `git_branch` 和 `tags` 篩選（所有標籤必須精確匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 取得特定套件的詳細資訊，包括自訂標籤。 | `bundle_id` |
| `get_bundle_artifact_tree` | 以按路徑排序的平面清單形式取得套件的完整工件樹。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以區分建構變體或環境。標籤是區分大小寫的標籤，包含字母、數字、連字號或底線，最多 10 個標籤，每個標籤最多 50 個字符。清單和詳細結果包括 `custom_metadata.tags`。分頁計數和分支篩選器適用於帶標籤的結果；省略 `tags` 會保留未篩選的行為。無效的標籤篩選器會返回錯誤，而不是擴大查詢範圍。

#### 世代

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_generations` | 列出專案的世代運行。 | `account_handle`, `project_handle` |
| `get_generation` | 取得特定世代運行的詳細資訊。 | `generation_id` |

#### 快取運行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cache_runs` | 列出專案的快取運行。 | `account_handle`, `project_handle` |
| `get_cache_run` | 取得特定快取運行的詳細資訊。 | `cache_run_id` |
| `list_xcode_module_cache_targets` | 列出世代或快取運行的模組快取目標，顯示每個目標的快取命中/未命中狀態和診斷組件哈希值，包括額外的哈希輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_previews` | 列出專案的可共用應用程式預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 取得預覽及其建構的臨時下載 URL。 | `preview_id` |
| `get_latest_preview` | 尋找執行中應用程式二進位檔的最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出專案的自動化警示。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 取得自動化警示。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警示的修訂歷史記錄。動作憑證已遮蔽。 | `alert_id` |
| `list_project_notification_alerts` | 列出專案通知警示規則。需要與儀表板設定頁面相同的管理員權限。Webhook 位址已遮蔽。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期的用戶端可以呼叫 `events/list` 來探索事件及其負載結構：

| 事件 | 發送時機 | 訂閱篩選器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從不穩定變更為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本機或持續整合 Xcode、Gradle 或 Bazel 建構以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本機或持續整合測試執行以失敗結束，包括合併的分片執行或已放棄的執行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist runner 工作以失敗完成。 | `account_handle` |

要訂閱，用戶端會呼叫 `events/subscribe`，並提供事件名稱、上述列於 `arguments` 的控制代碼，以及包含 `https://` 回呼 URL 和 `whsec_` 簽署金鑰的 `webhook` 傳遞。專案事件需要帳戶成員資格和對應測試或建構資料的讀取權限；runner 工作事件需要帳戶成員資格和 runner 讀取權限。已聲明的 [`auth.md`](https://workos.com/auth-md) 存取權杖、已聲明的帳戶權杖和瀏覽器授權授予可以建立訂閱；當相關憑證不再有效時，傳遞會停止。每個用戶最多可以保留 25 個作用中訂閱。Tuist 會在儲存訂閱之前向回呼發送驗證挑戰。回呼必須傳回包含相同 `challenge` 值的物件。訂閱預設持續七天，可以透過再次訂閱來續期，並在移除用戶的存取權或憑證時停止傳遞。可選的 `ttlMs` 限制在一小時到 30 天之間。Tuist 會重試超時的回呼，並在至少三次連續超時（橫跨五分鐘）後取消訂閱；在恢復回呼後請再次訂閱。

當事件發生時，Tuist 會將其資源識別碼和儀表板 URL 發送到回呼。建構和測試執行失敗還包括 `is_ci` 和 `git_branch`，因此用戶端可以忽略本機失敗或按分支篩選。建構事件包括 `build_system`；runner 工作事件包括 `workflow_job_id` 和 `workflow_run_id`。請求包括訂閱識別碼和 [Standard Webhooks](https://www.standardwebhooks.com/) 簽名標頭，以便用戶端驗證其來源。Tuist 會重試失敗的傳遞，因此用戶端應使用穩定的 `eventId` 來丟棄重複項。負載省略測試名稱、日誌和失敗訊息；用戶端可以透過上述工具取得這些詳細資訊，並決定是否通知團隊或開始除錯。用戶端可以使用 `events/unsubscribe` 停止傳遞。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 引導你透過分析失敗模式、識別根本原因並應用針對性修正來修復不穩定測試。 |
| `compare_builds` | 引導你透過比較建構來識別效能回歸、快取變更和建構問題。對 Xcode、Gradle、Bazel 和 Cargo 專案使用原生工具。Cargo 比較保留部分編譯器覆蓋率，並將估計的編譯器工作與經過時間節省區分開來。 |
| `compare_test_runs` | 引導你透過比較兩次測試執行來識別回歸、新失敗和不穩定測試。 |
| `compare_bundles` | 引導你透過比較兩個套件來識別工件樹中的大小變更。 |
| `compare_test_case` | 引導你透過比較測試案例在兩個分支或時間段內的行為。 |
| `compare_generations` | 引導你透過比較兩次世代運行來識別效能回歸和模組快取變更。 |
| `compare_cache_runs` | 引導你透過比較兩次快取運行來識別快取有效性變更和目標層級回歸。 |
| `integrate_gradle_project` | 引導你將 Tuist 整合到現有的 Gradle 專案中。它包括獨立的工具和 Gradle 驗證、帳戶探索、專案建立、遠端快取政策、建構洞察力和讀回驗證。 |
| `integrate_bazel_project` | 引導你建立或選擇 Bazel 專案、驗證命令列、配置遠端快取和建構洞察力，並透過 Tuist 建構資料驗證整合。 |
| `integrate_xcode_project` | 引導你將 Tuist 整合到現有的 Xcode 專案中。支援 Xcode 快取、建構洞察力、測試洞察力和測試分片。 |
| `ask_tuist` | 使用公開材料作為上下文，並以專注的實作和測試證據作為當前行為的事實來源，來回答 Tuist 問題。它需要 `question` 並引用修訂綁定的證據。 |

專案資料提示接受 `account_handle` 和 `project_handle` 以將調查範圍限定為特定專案。比較提示還接受 `base` 和 `head` 參數以指定要比較的兩個項目（按 ID、儀表板 URL 或分支名稱）。`ask_tuist` 接受 `question` 而不是專案參數。`integrate_gradle_project` 還接受 `features`，這是一個逗號分隔的 Gradle 整合清單以應用：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可選的 `server_url` 用於自託管或本機安裝。`integrate_xcode_project` 接受帶有 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding` 的 `features`。

#### Gradle 整合提示功能

`integrate_gradle_project` 提示和 `get_gradle_integration_guide` 工具記錄了完整的設定工作流程。伺服器的初始化指示也引用了該工具，令未枚舉提示的代理也能發現它。

| 功能 | 代理會配置什麼 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 的建構快取、配置 Tuist 遠端快取上傳政策，並建議只從具有本機唯讀用法的持續整合執行器進行上傳。 |
| `build_insights` | 應用 Tuist Gradle 外掛程式，並在需要時配置建構分析上傳行為。 |
| `test_insights` | 應用 Tuist Gradle 外掛程式，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 引導設定不穩定測試偵測、可選的 Gradle Test Retry 外掛程式用法，以及測試隔離配置。 |
| `test_sharding` | 新增持續整合工作流程，包括 `tuistPrepareTestShards`、分片矩陣生成，以及基於 `TUIST_SHARD_INDEX` 的測試執行。 |

當省略 `features` 時，提示會要求代理釐清用戶想要哪些整合，或在編輯 Gradle 專案之前從請求中推斷出最小的有用集合。

#### Xcode 整合提示功能

`integrate_xcode_project` 提示記錄了 Tuist 支援的每個 Xcode 整合：

| 功能 | 代理會配置什麼 |
|---------|---------------------------|
| `xcode_cache` | 配置 `tuist setup cache`、生成專案的快取設定、手動 Xcode 快取建構設定，以及僅限於持續整合執行器的上傳政策。 |
| `build_insights` | 透過 `tuist setup insights` 配置 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 和可選的機器指標。 |
| `test_insights` | 配置 `tuist inspect test`、方案測試後置動作，以及為持續整合測試運行生成結果套件。 |
| `test_sharding` | 新增 Xcode 或生成專案的分片規劃和分片執行工作流程，並使用 `TUIST_SHARD_INDEX`。 |

當省略 `features` 時，提示會要求代理釐清用戶想要哪些整合，或在編輯 Xcode 專案之前從請求中推斷出最小的有用集合。
