---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · 代理程式編碼 · 功能 · 指南 · Tuist",
  "description": "透過 Tuist 的 MCP 端點，讓 AI 代理程式存取測試洞察等資訊。"
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) 是一項開放標準，讓人工智慧代理能夠與外部服務和資料來源互動。它使 [Claude](https://claude.ai/)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code)、[Codex](https://developers.openai.com/codex/) 等應用程式，以及 [Zed](https://zed.dev)、[Cursor](https://www.cursor.com) 或 [Visual Studio Code](https://code.visualstudio.com) 等編輯器能夠與 Tuist 互通。

Tuist 在 `https://tuist.dev/mcp` 託管伺服器端的 Model Context Protocol 端點。將用戶端連接至此端點後，代理即可存取你的 Tuist 專案資料，包括測試洞察、不穩定測試分析等。大多數工具為唯讀，且範圍限於已通過驗證的 Tuist 專案資料。帳戶設定工具可列出帳戶、建立組織、建立專案，並在已驗證使用者具備所需權限時將現有使用者加入組織。每個工具都會宣告註解，說明其是否為唯讀、是否可能導致難以復原的變更，以及是否可能改變公開網際網路狀態。`update_runner_profile`、`update_notification_rule` 和 `connect_claude_subscription` 會宣告 `destructiveHint: true`，因為它們可能會取代現有設定或憑證。帳戶設定工具需要使用者驗證。專案權杖或一般帳戶權杖無法使用這些工具。當使用者在瀏覽器中授權用戶端或聲明 `auth.md` 註冊時，Tuist 僅在 Model Context Protocol 端點上將該憑證與使用者關聯，以便設定工具完成請求的工作流程。

Tuist 實作了 [2026-07-28 protocol](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)。請求是無狀態的：用戶端會在每次請求中傳送其協定中繼資料，並可直接呼叫工具而無需初始化。`server/discover` 會傳回伺服器的身分、功能、支援的版本及指示。沒有工作階段識別碼或獨立的事件串流。使用 2025-06-18 或 2025-03-26 初始化流程的用戶端仍受支援；它們也在無伺服器工作階段的情況下運作。

## Model Context Protocol 與技能比較

Model Context Protocol 工具與 <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> 的功能可能重疊。鑑於目前兩者的重疊情況，請針對每個工作流程選擇一種方法並一致使用，避免在同一流程中混合使用兩者。

對於支援外掛安裝的用戶端，請使用 <.localized_link href="/guides/features/agentic-coding/plugins">Tuist plugins</.localized_link> 同時安裝兩者。

## 設定

在用戶端中將 `https://tuist.dev/mcp` 新增為遠端 Model Context Protocol 伺服器。伺服器的初始化指示和公開伺服器卡片描述了具有動態用戶端註冊功能的 OAuth 2.0 以及標準瀏覽器授權流程，無需代理擷取或遵循外部驗證文件。這些伺服器範圍的指示保持工作流程指導的通用性：工具驗證不會驗證本機命令列工具或建置系統整合，代理應透過相關的 Tuist 工具驗證請求的變更。建置系統特定的設定和驗證檢查記錄在整合指南和提示中。Tuist 仍然分別宣傳 [Open Authorization](https://oauth.net/2/) 探索中繼資料和目前的 [auth.md protocol](https://workos.com/auth-md)（位於 `https://tuist.dev/auth.md`）。

如果你的其中一個組織強制執行單一登入，則在瀏覽器中授權用戶端需要透過該組織登入的工作階段，且在必要時 Tuist 會先將你導向提供者。請參閱 <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">single sign-on</.localized_link>。

該端點接受無狀態的 `2026-07-28` Model Context Protocol 請求生命週期（包括 `server/discover`），以及較舊的基於工作階段的生命週期。現有用戶端可以繼續使用其目前的連線方法。

支援 Model Context Protocol 事件的用戶端可以訂閱專案事件。請參閱 [Events](#events) 以了解可用的事件和傳遞需求。

已支援遠端瀏覽器驗證的用戶端可以繼續在瀏覽器中進行驗證。支援 `auth.md` 的用戶端和代理可以匿名註冊、呈現受信任的提供者身分斷言，或啟動服務驗證的電子郵件聲明。註冊會傳回由 Tuist 簽署的身分斷言，代理會在標準權杖端點將其交換為一小時的存取權杖。Tuist 會發布其公開簽章金鑰，並支援標準權杖撤銷和提供者安全事件傳遞。

未經驗證的代理應讀取 Model Context Protocol 端點傳回的 `WWW-Authenticate` 標頭，擷取受保護資源的中繼資料，擷取授權伺服器的中繼資料，並遵循其 `agent_auth.skill` URL。Tuist 也會在未授權回應主體中傳回相同的本機 `auth_md` URL，以便語言模型驅動的用戶端無需依賴原生用戶端整合即可發現該流程。部署本機文件是端點名稱、請求主體、聲明輪詢和斷言交換的真實來源。

在代理啟動電子郵件聲明之前，必須要求使用者確認其 Tuist 帳戶的電子郵件地址。不得從提供者設定檔、Git 設定、環境變數或工作階段中繼資料推斷該地址。

該端點使用 `mcp` 範圍群組。匿名的預聲明憑證可以探索功能並閱讀公開整合指導，但不會被視為已登入使用者。在瀏覽器授權或聲明後，憑證將限定於使用者範圍，且每個工具會套用與儀表板相同的授權檢查。詳情請參閱 <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link>。

工具會解析為已驗證使用者已有權讀取的專案。Xcode 和 Gradle 建置工具接受建置 UUID 或儀表板 URL。UUID 必須唯一識別一個專案；如果它出現在多個專案中，工具會傳回找不到，而不是選擇另一個專案的報告。專案範圍的儀表板和 API 讀取仍然可用。報告的行為者識別碼是未經驗證的標籤，而非憑證或額外存取權限。

建置清單與詳細資訊工具會公開選擇性的 `tuist_version` 中繼資料：針對 Xcode 和 Cargo 回報的 Tuist CLI、針對 Gradle 的 Tuist Gradle 外掛程式，以及針對 Mix 的 `tuist_ex` 函式庫。Xcode 也會從其連結的專案產生事件中公開 `tuist_generation_version`，該版本可能與上傳用的 CLI 不同。缺失的觀測值為 null，不會從伺服器或其他報告推斷。Bazel 使用其現有的 `bazel_version`；Once 執行詳細資訊則公開 `once_version`。這些欄位描述的是回報的版本，而非經過驗證的身分或線路協定版本。REST 建置端點會公開相同的中繼資料。現有的整合與不穩定測試技能不依賴版本欄位，無需變更工作流程。

Tuist 營運人員調查客戶帳戶時，是透過 Tuist 的內部營運工具進行，該工具會記錄每次呼叫；直接連線至此端點無法獲得超出使用者自身成員資格以外的存取權限。

### Pulse

Pulse 公開兩個唯讀工具，兩者皆由 `account_handle` 定址：

| 工具 | `/api/accounts/:account_handle/pulse` 下的 REST 對應項目 |
| --- | --- |
| `query_pulse` | `GET /:signal` |
| `get_pulse_analytics` | `GET /:signal/analytics` |

Pulse 僅限伺服器設定組織的目前成員使用，即使帳戶或專案是公開的亦然。它需要使用者驗證或與使用者關聯的 `mcp` 憑證，以及帳戶讀取授權。專案權杖、一般帳戶權杖、匿名註冊，以及沒有組織成員資格的營運人員存取權，都不會授予 Pulse 存取權。憑證無法選擇其他後端或遙測租戶。瀏覽器代理僅在 Pulse 頁面中，且在該頁面的帳戶範圍內接收這些工具。

REST 需要使用者憑證。OAuth 和 `auth.md` 使用者關聯僅在 `/mcp` 端點上可用；沒有目前使用者的帳戶憑證會被拒絕，無論相關帳戶的成員資格或可見性為何。

`query_pulse` 接受 `signal`（`metrics`、`logs` 或 `traces`）、選擇性的 `query`，以及 `range`（`15m`、`1h`、`6h` 或 `24h`，預設為 `1h`）。指標接受 PromQL 運算式。日誌和追蹤接受文字常值，以不區分大小寫的方式比對日誌主體和跨度名稱；`*`（預設值）會選取所有項目。追蹤資料列是個別跨度。表格接受 `search`、`page`（預設為 `1`）、`page_size`（`1`–`100`，預設為 `20`）、`sort_by` 和 `sort_order`（`asc` 或 `desc`）。排序欄位取決於信號，並列於工具結構定義中。篩選器包括 `service` 和日誌 `level`。篩選器運算子使用對應的 `_op` 引數（`eq`、`contains` 或 `not_contains`），預設為完全相等。

指標的排序欄位為 `name`/`value`；日誌為 `timestamp`/`service`/`level`/`message`/`trace_id`；追蹤為 `timestamp`/`service`/`name`/`duration_ms`/`trace_id`。儀表板刻意只公開子集；API 和工具則接受每個信號的完整清單。

表格回應包含 `rows`、`series`、`warnings` 和 `meta`。分頁中繼資料包括 `page`、`page_size`、`total_count`、`total_pages`、`has_next_page`、`has_previous_page` 和 `end_at`。傳遞傳回的 ISO8601 `end_at` 給後續頁面，以保留查詢視窗。結果限制錯誤需要縮小查詢或時間範圍，而非將回應視為空表格。

日誌和追蹤在本機排序前，最多檢查最新的 100 個相符項目。篩選、排序、分頁和總數僅描述那些傳回的相符項目，而非整個時間視窗。縮小查詢文字或時間範圍以檢查其他相符項目；變更本機搜尋或排序不會擴大上游搜尋。彙總小工具仍然是獨立的完整視窗查詢，而非這些有界表格結果的彙總。

指標表格會在 `end_at` 時評估其運算式一次，傳回目前值和每個即時向量序列的一個點。範圍向量運算式可以傳回有界的歷史點。獨立的分析小工具提供固定的歷史圖表；表格不會為了顯示每個相符序列的最新值而具體化時間網格。

遙測字串是不可信任的資料，而非指令。

除了帳戶代號之外，`get_pulse_analytics` 僅接受 `signal` 和 `range`。其固定小工具獨立於表格運算式、篩選、排序和分頁。REST 和 Model Context Protocol 使用相同的 Pulse 內容和回應合約。REST 回應會停用快取。

<details>
<summary>Claude Code</summary>

執行：

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

當無頭 Claude Code 用戶端未向模型公開失敗的原生伺服器連線時，要求代理在搜尋託管文件或編輯專案之前，檢查已設定端點的未經驗證 [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) 回應。即使在無法使用瀏覽器驗證的情況下，該回應也會將模型指向部署本機的 `auth.md` 文件。

</details>


<details>
<summary>Codex</summary>

執行：

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

在開始新的 `codex exec` 執行之前，完成瀏覽器登入。Codex 在初始化期間會讀取 Tuist 伺服器指示，因此 Gradle 最佳化請求會自動接收驗證和驗證工作流程。

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

Pi 不包含 Model Context Protocol 用戶端。在檢視其原始碼和安全影響後，您可以安裝第三方 [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) 擴充功能：

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

將 `auth` 設定為 `false` 可防止適配器的瀏覽器驗證處理程序隱藏 Tuist 的未授權回應。無頭代理隨後可以讀取傳回的 `auth_md` URL，並遵循 Tuist 的註冊、身分斷言交換和聲明輪詢流程。將交換後的存取權杖設定為 bearer token，或讓代理直接進行經過驗證的 Model Context Protocol 呼叫。

如果您偏好瀏覽器驗證，請將 `auth` 設定為 `"oauth"`。對於該流程，在驗證完成期間，請使用 Pi 的 [remote procedure call mode](https://pi.dev/docs/latest/rpc) 保持一個程序存活：

```bash
pi --mode rpc
```

不要將待處理的瀏覽器驗證分割到不同的 `pi --print` 叫用中，因為擁有回呼狀態的程序已結束。

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

如果您的代理支援 `auth.md`，它可以匿名啟動而無需開啟瀏覽器。當提供者身分已連結時，受信任的提供者身分也可以在沒有瀏覽器的情況下完成驗證。對於服務驗證電子郵件、匿名聲明或首次提供者連結，代理會向您顯示 Tuist 驗證連結和六位數代碼。開啟連結、登入，並在 Tuist 頁面上輸入代理的代碼。切勿將代碼傳回給代理。Tuist 的授權伺服器中繼資料直接指向部署本機的 `/auth.md`，其中包含精確的請求和輪詢結構。

## Amp orbs 和 Claude Code 雲端工作階段中的代理

在連接到 Tuist 帳號的沙箱中運行的編碼代理可以使用其自身的身分權杖向端點進行驗證，而無需瀏覽器或儲存的 Tuist 憑證：

- 帳號在 **Settings → Integrations → Amp** 下連接的 Amp 工作區或專案的 **Amp orbs** 會傳送 orb 的身分權杖。在 Amp 中，將伺服器的 `Authorization` 標頭設定為 `Bearer ${amp:id-token}`。Amp 會為伺服器 URL 的來源鑄造權杖，因此 URL 必須是此 Tuist 實例本身的位址，並會在過期前重新整理它。為其他來源鑄造的權杖會被拒絕。
- 已連接 Claude Code 環境的 **Claude Code cloud sessions** 會傳送 Tuist 作為 `TUIST_OIDC_TOKEN` 傳遞給它們的工作階段權杖。將標頭設定為 `Bearer ${TUIST_OIDC_TOKEN}`。

Tuist 的 Linux 沙箱已預先設定好此項配置：在 Amp 的使用者設定和 Claude Code 的使用者組態中都有一個 `tuist` 伺服器，兩者都指向 `${TUIST_URL}/mcp`，並附帶 Tuist CLI 和一個技能，該技能會告訴代理何時根據專案歷史記錄檢查其結果。在其他地方，請自行使用上述標頭新增伺服器。

這些權杖提供對已連接帳號每個專案的唯讀存取權限：它們攜帶 `mcp` 群組的讀取範圍，但不包含建立、變更或刪除資料（例如靜音或跳過測試）的權限。斷開工作區或環境的連線會在下一個請求時停止存取，且存取權限永遠不會超過權杖本身的有效期。連接到多個 Tuist 帳號的 Amp 工作區會被拒絕，因為其權杖未指定單一帳號。當缺少連線時，未授權回應的 `error_description` 會說明此情況。

此唯讀存取權僅適用於 Model Context Protocol 端點。同一沙箱中的命令列工具和建置系統整合仍然會交換權杖以取得連線的 CI 存取權。

## WebMCP

在支援 [WebMCP](https://webmachinelearning.github.io/webmcp) 的瀏覽器中，Tuist 的頁面會使用 `document.modelContext` 註冊工具，因此內建於瀏覽器的代理可以在無需任何額外組態的情況下呼叫它們。這些呼叫在 Tuist 伺服器上執行。

- **Website and documentation pages** 會註冊文件和原始碼工具（`search_tuist`、`search_tuist_code`、`list_tuist_files` 和 `read_tuist_file`）。它們不需要您登入。
- 當您登入時，**An account's dashboard pages** 會為該帳號註冊 Tuist 的唯讀工具。每個頁面僅註冊其顯示內容所需的工具，針對專案的建置系統：Gradle 專案的建置頁面會取得 Gradle 建置工具，其測試頁面會取得測試和涵蓋率工具，執行器頁面會取得執行器工具，沙箱頁面會取得沙箱工具。您個人帳號的 AI 設定頁面的「訂閱」部分會取得 `list_ai_subscriptions`，它僅回答您自己帳號的問題。每個頁面也會取得文件工具 `list_projects` 和 `get_project`。這些工具以登入使用者的身分執行，因此它們只能存取您在儀表板中可以讀取的資料，且僅限於您正在檢視的帳號。當您移至另一個頁面或帳號時，工具會替換為該頁面的工具。

建立、變更或刪除資料的工具無法透過 WebMCP 使用，因為瀏覽器代理會在您未新增它們的情況下接收工具，並讀取建置和測試產生的內容。將 MCP 用戶端連接到 `/mcp` 端點以使用這些工具。

如果組織強制執行單一登入，請使用其提供者登入儀表板以使用其工具。

## 建置系統整合使用兩種憑證

用於 Model Context Protocol 工具的憑證不會驗證 Gradle 外掛程式或 Bazel 的遠端服務。在代理編輯或驗證 Gradle 或 Bazel 整合之前，它應該執行：

```bash
tuist auth whoami --url https://tuist.dev
```

如果該命令未經過驗證，代理必須停止並要求使用者執行：

```bash
tuist auth login --url https://tuist.dev
```

對於本機或自託管部署，請替換兩個命令和 `tuist.toml` 中的 URL。在各處保持主機名稱拼寫一致。例如，`localhost` 和 `127.0.0.1` 使用單獨儲存的憑證。


## 功能

### 工具

以下工具可透過 Tuist Model Context Protocol 伺服器使用：

每個工具都會發布人類可讀的描述以及明確的輸入和輸出結構定義。成功的呼叫會傳回符合所宣傳輸出結構定義的結構化內容，以及序列化為文字的相同結果，供尚未使用結構化內容的用戶端使用。

接受單一記錄識別碼（例如 `build_run_id`、`test_run_id`、`test_case_id`、`bundle_id`、`run_id`、`generation_id` 或 `cache_run_id`）的工具也接受該記錄的 Tuist 儀表板 URL。直接從瀏覽器貼上 URL，而不是從中提取識別碼。

`get_xcode_build`、`get_test_run`、`get_gradle_build` 和 `get_project` 可以包含 `side_quests`：記錄顯示專案未使用但會有幫助的 Tuist 功能。每個功能都有一個 `id`、一個說明其依據證據的 `tip`，以及一個 `docs` 連結。要求代理先完成使用者的請求，提及適用的支線任務，並僅在使用者同意時對其中一個採取行動。它們僅傳回給專案帳號的成員，無論他們是使用使用者工作階段、MCP 權杖還是代理身分進行連接：

| ID | 工具 | 建議時機 |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | 使用 Xcode 26 或更高版本處理的乾淨建置未執行任何可快取的編譯任務。 |
| `gradle_build_cache` | `get_gradle_build` | 建置執行了可快取的任務，但 Gradle 的建置快取未為其中任何任務計算金鑰，這表示建置快取已關閉。 |
| `flaky_test_quarantine` | `get_test_run` | 一次執行包含不穩定測試，且專案中沒有啟用的自動化功能將其靜音或跳過。不建議用於 Once 專案。 |
| `test_sharding` | `get_test_run` | 在 Tuist 支援分片的建置系統中，一次未分片的 CI 執行耗時 10 分鐘或更長。提示會說明選擇性測試已跳過了多少個測試（如果有的話）。 |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | CI 執行使用了 GitHub Actions、Bitrise、GitLab CI 或 Buildkite 機器，且該帳號從未在 Tuist Runners 上執行過作業。僅適用於 tuist.dev。 |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | GitHub Actions 執行屬於一個未連接到其 GitHub 儲存庫的專案。 |
| `other_build_systems` | `get_project` | 該帳號並未在所有支援的建置系統中使用 Tuist。提示列出了識別其他系統的檔案，以便代理檢查儲存庫。 |

#### 文件與社群搜尋

此唯讀工具透過驅動文件網站的相同搜尋引擎，搜尋 Tuist 的文件、[應用程式介面](https://en.wikipedia.org/wiki/API)參考、GitHub 發行版、社群論壇和 GitHub 問題。發行結果包括產品、版本、發布日期和預發行狀態。預設搜尋穩定發行版，並可使用 `include_prereleases` 包含預發行版。此工具僅在位於 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `search_tuist` | 搜尋公開的 Tuist 文件、應用程式介面參考、GitHub 發行版、社群討論和 GitHub 問題。可選擇限制為單一 `source`（`docs`、`api_reference`、`releases`、`forum`、`issues`）。 | `query` |

#### 回饋

當 Tuist 工具或提示未按預期運作時（例如結果令人困惑、發生錯誤、資料遺失或缺少功能），代理可以向 Tuist 團隊回報。要求代理建議回報，並僅在您同意後發送。每份回報都會開啟與 Tuist 支援的對話，他們可能會透過電子郵件回覆您。回報包括代理的預期、實際發生的情況、可選建議、您的 Tuist 使用者 ID、帳號名稱和電子郵件，以及您所屬的組織。代理也可以指名問題發生的帳號和專案，以便團隊知道要跟進哪個組織；僅接受您所屬的帳號。只有以 Tuist 使用者身分登入的代理才能發送回報，且每位使用者每小時最多可開啟 10 份回報。此工具僅在位於 `https://tuist.dev/mcp` 的 Tuist 託管伺服器上可用。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `report_feedback` | 回報 Tuist 工具或提示的問題。可選擇指名 `tool_name`、問題發生的 `account_handle` 和 `project_handle`，並新增 `suggestion`。 | `category`, `expected`, `actual` |

#### 原始碼支援的答案

這些唯讀工具讓代理使用與託管伺服器一同部署的確切公開 Tuist 原始碼修訂版，作為依賴當前行為之答案的事實依據。它們僅在 `https://tuist.dev/mcp` 可用。

相容的用戶端在初始化期間會收到關於工具原始碼修訂版、連結和結果限制的事實描述，以及內嵌 OAuth 驗證資訊。這些描述並不規定回答風格或驗證工作流程。使用者可以直接提問，無需先叫用 `ask_tuist` 提示；該提示仍可用於明確的原始碼支援工作流程。

每個作業都有固定的並行、持續時間、遍歷、讀取位元組數和回應大小限制。搜尋和列出結果包含 `truncated` 和 `truncation_reason` 欄位。當結果被截斷時，請縮小路徑、檔案模式或搜尋詞，而不是將結果視為詳盡無遺。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `search_tuist_code` | 透過搜尋原始碼檔案來回答有關當前行為、預設值、設定、功能開關、錯誤處理或未記錄細節的問題。結果包括周圍的行、固定修訂版的原始碼連結和掃描統計資料。 | `pattern` |
| `list_tuist_files` | 當相關路徑未知時，發現原始碼子系統或附近的測試。列表具有有限的深度和結果數量。 | 無 |
| `read_tuist_file` | 在找到相關路徑後，檢查實作檔案、呼叫點或測試中的特定行範圍。截斷的回應提供 `next_start_line` 以便繼續。 | `path` |

#### 專案

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_accounts` | 列出經過驗證的使用者可使用的個人和組織帳號名稱，包括每個帳號是否可以建立專案。 | 無 |
| `get_organization` | 取得組織的成員目錄。待處理的邀請需要與儀表板相同的管理員權限；永遠不會傳回邀請接受權杖。 | `account_handle` |
| `create_organization` | 為經過驗證的使用者建立 Tuist 組織。 | `handle` |
| `create_project` | 在經過驗證的使用者可存取的帳號下建立 Tuist 專案。 | `account_handle`, `project_handle` |
| `add_organization_member` | 將現有的 Tuist 使用者新增至組織，或更新現有成員的角色。接受 `user`（預設）、`admin` 或 `viewer`，其中檢視者可以閱讀儀表板和執行記錄，但無法進行任何變更。 | `organization_handle`, `email` |
| `invite_organization_member` | 邀請電子郵件地址加入組織，無論該地址是否屬於現有的 Tuist 使用者。Tuist 會發送一封有效期為 14 天的接受連結電子郵件；當伺服器無法發送電子郵件時，`email_sent` 為 `false`，必須從儀表板複製連結。接受 `user`（預設）、`admin` 或 `viewer`。需要組織管理員權限。 | `organization_handle`, `email` |
| `cancel_organization_invitation` | 取消待處理的組織邀請，使其連結無法再被接受。需要組織管理員權限。 | `organization_handle`, `email` |
| `list_projects` | 列出經過驗證的使用者可存取的所有專案。 | 無 |
| `get_project` | 取得專案的設定和已連線的儲存庫 URL。 | `account_handle`, `project_handle` |
| `connect_project_repository` | 將專案連結至帳號的 GitHub App 安裝可存取的 GitHub 儲存庫。專案會採用儲存庫的預設分支。需要專案管理員權限。 | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | 移除專案與其 GitHub 儲存庫的連結。需要專案管理員權限。 | `account_handle`, `project_handle` |

#### 帳號權杖

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_account_tokens` | 列出帳號權杖中繼資料，而不揭露權杖值。 | `account_handle` |
| `get_account_token` | 取得帳號權杖中繼資料，而不揭露其值。 | `account_handle`, `token_id` |
| `list_project_tokens` | 列出專案權杖中繼資料，而不揭露權杖值。 | `account_handle`, `project_handle` |

#### AI 訂閱

這些工具管理經過驗證的使用者自己的 Claude 和 ChatGPT 訂閱，用於執行緒等 AI 功能。它們需要使用者驗證和 AI 功能存取權，並且只傳回連線中繼資料，絕不傳回憑證。斷開連線會刪除儲存的憑證，但不會撤銷提供端的授權。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_ai_subscriptions` | 列出每個訂閱是否已連線，以及伺服器是否可以連線。 | 無 |
| `connect_claude_subscription` | 儲存 `claude setup-token` 列印的訂閱權杖。該權杖是透過用戶端和模型傳遞的機密，因此請明確提供；將其貼到儀表板的 AI 設定中可避免其出現在對話中。 | `token` |
| `start_chatgpt_subscription_login` | 啟動 OpenAI 裝置登入，並傳回使用者在該處輸入的驗證 URL 和代碼，以及 `login_id`。15 分鐘後過期。 | 無 |
| `poll_chatgpt_subscription_login` | 檢查待處理的登入：在使用者核准代碼之前為 `pending`，之後為 `connected`。 | `login_id` |
| `cancel_chatgpt_subscription_login` | 取消待處理的登入。已連線的訂閱保持連線狀態。 | `login_id` |
| `disconnect_ai_subscription` | 刪除訂閱的儲存憑證和任何待處理的登入。 | `provider` |

#### 通知規則

這些工具管理經過驗證的使用者自己的通知規則：當事件（例如新的預覽）在規則的專案中發生（或在未列出任何專案時，在你可收到通知的任何專案中發生）並符合其條件時，執行其動作，例如向你的 Tuist App 裝置發送推播通知。如果沒有規則，你將不會收到任何通知。它們需要使用者驗證，僅針對你自己的規則運作，並且只接受你所屬帳號的專案。它們不提供給儀表板頁面，因為規則涵蓋你所有的帳號。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_notification_events` | 列出規則可以訂閱的事件類型，每個類型都附帶其條件的 JSON Schema。 | 無 |
| `list_notification_condition_options` | 建議專案中事件的條件值，例如其近期預覽的軌道和分支。 | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | 列出你的規則。 | 無 |
| `create_notification_rule` | 從事件、可選專案和條件，以及至少一個動作建立規則。 | `event`, `actions` |
| `update_notification_rule` | 變更規則的啟用狀態、專案、條件或動作。 | `rule_id` |
| `delete_notification_rule` | 刪除規則。 | `rule_id` |

#### 持續整合執行器

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_runner_jobs` | 列出帳號的持續整合執行器工作。 | `account_handle` |
| `get_runner_job` | 取得持續整合執行器工作，包括其機器是否記憶體不足、停止原因以及需要變更的內容。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | 列出為持續整合執行器工作記錄的步驟。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | 列出為持續整合執行器工作記錄的機器指標。 | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | 列出持續整合執行器工作擷取的最多 500 行日誌。 | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | 列出帳號的持續整合工作流程彙總。 | `account_handle` |
| `list_runner_profiles` | 列出帳號的持續整合執行器設定檔，並包含每個設定檔的 `runs-on` 標籤。 | `account_handle` |
| `get_runner_catalog` | 列出執行器設定檔可使用的機器規格和 Xcode 版本。 | `account_handle` |
| `create_runner_profile` | 建立包含平台、機器規格以及在 macOS 上的 Xcode 版本的執行器設定檔。可選擇設定哪些分支儲存其快取磁碟區。需要帳號管理權限或 `account:runners:write` 範圍。 | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | 變更執行器設定檔的機器規格、Xcode 版本，或哪些分支儲存其自訂快取磁碟區變更。省略的欄位會保留其值。需要帳號管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |
| `delete_runner_profile` | 在使用者確認後刪除執行器設定檔。無法刪除預設設定檔。需要帳號管理權限或 `account:runners:write` 範圍。 | `account_handle`, `profile_name` |

執行器磁碟區工具公開與「磁碟區」儀表板相同的資料。讀取工具需要執行器存取權；清除需要帳號管理權限或 `account:runners:write` 範圍，以及使用者確認。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_runner_volumes` | 依名稱和儲存庫篩選，並對磁碟區進行排序和分頁。 | `account_handle` |
| `get_runner_volume` | 儲存庫、平台、容量、已用空間和最後使用時間。 | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | 分頁的工作和工作流程參考、快取狀態、命中結果和掛載時間。 | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | 由工作掛載的磁碟區。 | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | 儲存序列、工作執行次數、命中率及趨勢。可選 `volume_id`、`start` 和 `end`（ISO 8601）；預設為七天，最多 90 天。 | `account_handle` |
| `delete_runner_volume` | 刪除磁碟區及其儲存的內容。執行中的工作會保留其私人副本但無法儲存；後續使用相同金鑰的工作將從空白開始。 | `account_handle`, `volume_id` |

列表接受 `page` 和 `page_size`（最多 100）。磁碟區庫存也接受 `name` 和 `repository`（完全相符，以 AND 組合）、`sort_by`（`volume`、`repository`、`used_space`、`capacity`、`last_used`）和 `sort_order`（`asc`、`desc`）。未知的測量值和命中結果保持為 `null`。快取狀態描述磁碟區變更是否已儲存，而非工作成功與否。

#### 沙盒

沙盒工具公開與「沙盒」儀表板相同的資料和動作，並具有與 [API](https://tuist.dev/api/docs) 相同的存取權：帳號成員可以列出、取得、建立、暫停、恢復和刪除沙盒，但提供代理環境、Amp 或遠端執行的沙盒，以及分析和封存工具，需要帳號管理權限。唯讀檢視者無法使用它們。帳號需要啟用沙盒功能。儀表板的沙盒頁面會註冊唯讀工具。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_sandboxes` | 對沙盒進行分頁，顯示其狀態、規格和時間戳記。可選 `search`（沙盒、Amp Orb 或 Anthropic 工作階段 ID 中的文字）、`status`、`vcpus`、`sort_by`（`created`、`last_active`、`identifier`）和 `sort_order`。 | `account_handle` |
| `get_sandbox` | 沙盒的狀態、規格、節點、封存和時間戳記。 | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | vCPU 小時數、建立的沙盒數量、工作階段、設定和啟動所需時間，以及相對於帳號限制的峰值 vCPU、記憶體和磁碟使用量，並包含趨勢。可選 `start` 和 `end`（ISO 8601）；預設為 30 天，最多 90 天。 | `account_handle` |
| `create_sandbox` | 啟動一個空白沙盒，並在執行後傳回。可選 `platform`（`linux` 或 `darwin`）、`template`、`vcpus` 搭配 `memory_mb`（Linux：2x4096、4x8192 或 8x16384，預設 2x4096；macOS：8x8192、8x16384 或 8x24576，預設 8x8192）和 `workspace_gb`。 | `account_handle` |
| `pause_sandbox` | 將執行中的沙盒快照儲存至其節點的磁碟。 | `account_handle`, `sandbox_id` |
| `resume_sandbox` | 恢復已暫停或封存的沙盒。 | `account_handle`, `sandbox_id` |
| `archive_sandbox` | 將已暫停沙盒的磁碟排隊移至物件儲存。 | `account_handle`, `sandbox_id` |
| `delete_sandbox` | 在使用者確認後刪除沙盒及其磁碟。 | `account_handle`, `sandbox_id` |

#### Amp 工作區

這些工具管理 <.localized_link href="/guides/server/authentication#amp-orbs">Amp 工作區連線</.localized_link>，讓 orbs 無需權杖即可登入 Tuist。它們使用與儀表板「整合」頁面相同的管理員專用權限。orb 中的代理可以從 `$AMP_WORKSPACE_ID` 和 `$AMP_PROJECT_ID` 讀取其自己的 ID。連線允許的每個 orb 都能獲得帳號中所有專案的 CI 存取權，因此代理應在連線前與使用者確認。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | 列出帳號已連線的 Amp 工作區，以及每個工作區限制的專案（若有）。 | `account_handle` |
| `connect_amp_workspace` | 連線 Amp 工作區。可選 `project_id` 將登入限制為單一 Amp 專案的 orbs。 | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | 中斷工作區連線。orbs 已有的工作階段仍有效，直到過期為止。 | `account_handle`, `connection_id` |

#### Claude 環境

這些工具會連線 Claude Managed Agents 自託管環境，讓其工作階段在 Tuist 沙盒中執行，如同「設定」→「整合」→「Claude」。它們需要帳號管理權限並啟用沙盒。代理可以使用 Anthropic 的 API 建立環境，但只有 Claude Console 能產生環境金鑰，因此代理會向使用者索取。Tuist 使用 Anthropic API 金鑰或工作負載身分聯合來啟動工作階段，並在儲存前使用该憑證取得環境。Anthropic 端的設定使用使用者自己的 Anthropic 憑證；Tuist 永遠不會收到這些憑證。金鑰會透過用戶端和模型傳遞，因此請僅在明確需要時提供。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_claude_environments` | 列出已連線的環境及其使用的憑證，以及聯合規則應信任的發行者 URL 和主體前綴。 | `account_handle` |
| `connect_claude_environment` | 使用 `api_key` 連線環境，或使用 `organization_id`、`workspace_id`、`service_account_id` 和 `federation_rule_id`。可選 `platform`、`vcpus` 和 `memory_mb` 用於設定沙盒規格。 | `account_handle`, `environment_id`, `environment_key` |

#### Webhook

Webhook 工具使用與儀表板相同的管理員專用權限。傳送嘗試包含為端點記錄的要求和回應資料，但絕不包含端點簽署金鑰。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_webhook_endpoints` | 列出帳號的 Webhook 端點。 | `account_handle` |
| `get_webhook_endpoint` | 取得 Webhook 端點。 | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | 列出端點的傳送嘗試。 | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | 取得一次傳送嘗試。 | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Xcode 建置

適用於 Xcode、Gradle、Bazel、Mix 和 Cargo 的建置詳細資訊工具會公開現有的 `custom_metadata: {tags, values}` 結構，包括基礎設施觀察結果（若已回報）。值保持為字串，並保留不熟悉的鍵。例如，`tuist.cpu.available_processors` 描述執行階段可用的邏輯處理器，而 `tuist.gradle.max_workers` 是 Gradle 工作執行緒上限，`tuist.jvm.max_heap_bytes` 是 JVM 堆積上限，而非主機記憶體。這些是不受信任的用戶端觀察結果，並非經過驗證的執行器身分。缺少的觀察結果仍會缺少；匯入的日誌和較舊的用戶端可能沒有基礎設施中繼資料。中繼資料更新有待協調的用戶端/通訊協定更新。

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_xcode_builds` | 列出專案的 Xcode 建置執行。 | `account_handle`, `project_handle` |
| `get_xcode_build` | 取得特定 Xcode 建置執行的詳細資訊，包括保存原始 `.xcactivitylog` 的封存檔案之暫時下載 URL。 | `build_run_id` |
| `list_xcode_build_targets` | 列出特定 Xcode 建置執行的建置目標。 | `build_run_id` |
| `list_xcode_build_files` | 列出特定 Xcode 建置執行的已編譯檔案。 | `build_run_id` |
| `list_xcode_build_steps` | 列出已記錄的建置步驟及其時間和結果，不含日誌文字。 | `build_run_id` |
| `get_xcode_build_step` | 取得一個已記錄的建置步驟，包括其日誌和截斷旗標。 | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | 列出特定建置執行的建置問題（警告和錯誤）。 | `build_run_id` |
| `list_xcode_build_cache_tasks` | 列出特定 Xcode 建置執行的可快取工作（快取命中/未命中）。 | `build_run_id` |
| `list_xcode_build_cas_outputs` | 列出特定 Xcode 建置執行的 [內容定址儲存](https://en.wikipedia.org/wiki/Content-addressable_storage) 輸出。 | `build_run_id` |

`list_xcode_build_steps` 預設傳回每頁 20 個步驟（透過 `page_size` 最多 100 個），並提供 `page` 和 `pagination_metadata` 用於導覽。使用 `search` 比對標題、專案或目標，或篩選確切的 `project`、`target`、`category`（例如 `swiftCompilation`）和 `status`（`success` 或 `failure`）。依 `duration_ms` 排序以最慢者優先（預設），或依 `start_ms` 排序以取得時間順序。步驟 ID 用於打破平局，並以十進位字串形式傳回，以保留完整的 64 位元精度。ID 限定於單一建置，不應跨建置之比對。

可選 `start_ms` 和 `end_ms` 可選取與從建置開始起算的毫秒時間範圍重疊的步驟；結束時間為互斥。兩種工具都接受建置 UUID 或儀表板 URL 作為 `build_run_id`。將傳回的步驟 `id` 原封不動地作為 `step_id` 傳遞，以取得其日誌。每個步驟的日誌最多保留 64 KiB，`log_truncated` 表示省略的輸出。

處理 Xcode 建置時，預設會收集步驟。已記錄的步驟資料會保留 90 天。列表回應包含 `availability`：`available` 表示存在已記錄的步驟，即使篩選條件未比對到任何項目；`processing` 表示建置仍在處理中且尚無步驟；或 `unavailable` 表示步驟未記錄或已過期。

相同的操作可透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` 和 `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}` 使用，具有相同的篩選器和分頁功能。兩者都需要對建置專案的讀取權限。

#### Gradle 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | 傳回完整的驗證、專案設定、Gradle 外掛程式、快取政策，以及兩次建置驗證工作流程。代理程式在編輯現有的 Android 或 Gradle 專案之前應呼叫此工具。 | 無 |
| `list_gradle_builds` | 列出專案的 Gradle 建置執行，包括自訂中繼資料。使用可選的 `tag` 參數依自訂標籤篩選。 | `account_handle`, `project_handle` |
| `get_gradle_build` | 取得建置之中繼資料、工作/快取計數，以及 `failures`：每個失敗工作和設定步驟的失敗訊息。 | `build_run_id` |
| `list_gradle_build_tasks` | 列出工作結果、複合建置身分識別、可快取性、增量狀態和失敗訊息。 | `build_run_id` |
| `list_gradle_build_steps` | 列出計時工作、設定和轉換，支援搜尋、中繼資料和重疊時間篩選器。 | `build_run_id` |
| `get_gradle_build_step` | 透過不透明 ID 檢查已記錄的步驟中繼資料；失敗工作或設定步驟的 `log` 即為其失敗訊息。 | `build_run_id`, `step_id` |

Gradle 和 Bazel 步驟清單預設傳回 20 個結果（最多 100 個），支援 `search`、確切的 `project`、`target`、`category` 和 `status`、重疊的 `start_ms` / `end_ms` 篩選器（結束時間互斥），以及 `duration_ms` 或 `start_ms` 排序。原封不動地傳遞傳回的 ID；它們限定於其建置。清單公開 `time_origin` 和 `coverage`。較舊的 Gradle 報告使用 `first_recorded_timestamp`，因為未上傳建置開始時間。Bazel 設定檔透過 `trace_profile` 覆蓋範圍和作為時間起點的 `profile_start` 公開所有已記錄的間隔。較舊的建置會退回到保留的 BEP 摘要。來源記錄在 90 天後過期。Bazel 詳細資訊在發布時包含經淨化的動作日誌。失敗工作或設定步驟的 Gradle 詳細資訊包含 Tuist Gradle 外掛程式作為 `log` 報告的失敗訊息：例外訊息及其原因鏈，如同 Gradle 主控台所列印，不含堆疊追蹤或工作輸出，專案內的路徑改為相對路徑，並遮蔽憑證和其他本機路徑，每個步驟最多 16 KiB，每次建置最多 32 個失敗步驟。其他 Gradle 步驟、由較舊外掛程式版本報告的建置，以及無憑證報告的 `log` 為 null。設定步驟在失敗時回報 `failure`，否則回報 `unknown`。`compare_builds` 提示使用此覆蓋範圍來區分完整的 Bazel 追蹤與保留的摘要，並指引代理程式在檢查更廣泛的呼叫輸出之前，先查看步驟詳細資訊以取得動作結果和日誌。

單一步驟工具 `get_gradle_build_step` 和 `get_bazel_build_step` 依 ID 擷取步驟，且不接受時間篩選器；請使用對應的清單工具依時間範圍篩選步驟。

若在列出與擷取步驟之間收到完整設定檔，則從保留摘要傳回的 Bazel 步驟 ID 仍可讀取。若已索引設定檔的步驟資料已過期，則回報為不可用。Gradle 步驟清單包含持續時間為零的快取和略過操作。

#### Bazel 呼叫

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | 傳回驗證、專案設定、Bazel 設定和驗證工作流程。 | 無 |
| `list_bazel_invocations` | 列出已完成的 [Bazel 建置事件協定](https://bazel.build/remote/bep) 呼叫，由新到舊排序，包含建置指標、有界的執行時間軸、關鍵路徑診斷，以及專案的相關遠端快取總計。依 `status`、`git_branch`、`git_commit_sha`、`is_ci` 和 `command` 篩選。 | `account_handle`, `project_handle` |
| `get_bazel_invocation` | 取得一個已完成的 Bazel 呼叫，包含建置指標、有界的執行時間軸、關鍵路徑診斷，以及相關的遠端快取總計。 | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | 列出已記錄的 Bazel 設定檔間隔，包含篩選器和明確的覆蓋範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | 檢查已記錄的 Bazel 步驟及其發布的動作結果和經淨化的日誌。 | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | 依執行順序列出為 Bazel 呼叫擷取的經淨化日誌：Bazel 進度輸出的有界尾部，以及 `test.log` 構件。可選的 `stream`（`stdout` 或 `stderr`）、`source`（`progress` 或 `test_log`）、`target_label` 和 `errors` 篩選器可縮小結果範圍。 | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | 取得為 Bazel 呼叫擷取的一個經淨化日誌區塊。 | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | 列出原始的 Bazel 遠端快取觀察結果，包含其操作、端點和觀察時間，可選擇縮小到特定呼叫、結果或操作。 | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | 取得一個原始的 Bazel 遠端快取觀察結果。 | `account_handle`, `project_handle`, `cache_event_id` |

`list_bazel_invocations` 篩選器為精確比對，且在同一秒內完成的呼叫依呼叫 ID 排序。若要尋找分支上最新的失敗呼叫，請使用 `status: "failure"`、`git_branch` 和 `page_size: 1` 呼叫它。REST 端點 `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` 接受相同的篩選器。

測試日誌攜帶其來源測試結果的 `target_label` 和嘗試 `status`，因此 `target_label: "//foo:bar_test"` 僅傳回該目標的測試日誌。`errors: true` 傳回失敗嘗試的測試日誌，以及包含 Bazel 報告器以 `ERROR:`、`FAIL:` 或 `TIMEOUT:` 開頭之行的 stderr 進度區塊。進度輸出未歸因於目標，且在記錄歸因之前寫入的日誌欄位為空。失敗動作及其輸出可透過 `list_bazel_build_steps` 依目標取得，而每個測試案例的失敗則可從測試執行工具取得。

#### Cargo 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_cargo_builds` | 列出專案的 Cargo 建置，由新到舊排序。依 `git_branch`、`status`、`is_ci` 或 `command` 篩選。Cargo 測試執行結果可透過測試工具取得，而非此建置清單。 | `account_handle`, `project_handle` |
| `get_cargo_build` | 取得建置之中繼資料、彙總快取計數器，以及最多 500 個帶有診斷資訊的已記錄編譯器工作。`compilations_truncated` 表示省略的工作；診斷資訊僅涵蓋傳回的工作。 | `account_handle`, `project_handle`, `build_id` |

在 `get_cargo_build` 上設定 `include_cache_inspection: true` 以擷取经驗證的工作決策和 CAS 操作，上限為 4 MB。預設情況下，以及當記錄遺失或無效時，`cache_inspection` 為 null。請尊重其部分擷取的 `truncated` 旗標；傳輸不會確定每個工作命中的本機/遠端來源。HTTP 詳細資訊端點接受相同的查詢參數。

#### Mix 建置

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_mix_builds` | 列出專案的 Mix (Elixir) 編譯建置，由新到舊排序，包含自訂中繼資料。依 `git_branch`、`status`、`is_ci` 或 `mix_env` 篩選。 | `account_handle`, `project_handle` |
| `get_mix_build` | 取得建置之中繼資料、診斷計數，以及相依性快取摘要。 | `account_handle`, `project_handle`, `build_id` |

#### 建置追蹤記錄

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `get_build_trace` | 取得 Xcode、Gradle、Bazel 或 Mix 建置時間軸的下載連結，格式為可在 [Perfetto](https://ui.perfetto.dev) 中開啟的追蹤檔案。 | `account_handle`, `project_handle`, `build_id` |

`build_id` 是建置執行 ID（Bazel 則為呼叫 ID）或建置的儀表板 URL。傳回的 `trace_url` 提供 [Chrome Trace Event](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU) JSON 檔案。任何持有該連結的人均可在 `expires_at`（呼叫後一小時）之前，無需其他憑證即可下載該建置的追蹤記錄。代理程式可以使用 `curl` 下載，交給你在 Perfetto 中開啟，或使用 Perfetto 的 `trace_processor` 進行查詢。追蹤記錄包含依平行處理方式打包至通道的已記錄步驟、涵蓋整個建置的軌跡，以及在建置記錄機器指標時的 CPU 和記憶體計數器。它包含與上述步驟工具相同的資料，但不含日誌。儀表板從每個建置的「時間軸」分頁提供相同的檔案。

#### Once 執行

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_once_runs` | 列出專案的 Once 執行，由新到舊排序。依 `kind`（`build`、`test` 或 `generic`）、`status`、`is_ci` 或 `git_branch` 篩選。尚未完成的執行狀態為 `in_progress`。 | `account_handle`, `project_handle` |
| `get_once_run` | 取得執行及其動作總數、快取摘要，若是測試執行則包含測試總數。 | `account_handle`, `project_handle`, `run_id` |

Cargo 建置、Mix 建置和 Once 執行 ID 在專案內具有唯一性。透過 HTTP API 在 `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`、`.../mix/builds` 和 `.../once/runs` 可提供相同的讀取操作，每個端點皆支援針對單一 ID 的詳細資訊端點。

#### 工作、動作、模組和檔案

這些專案範圍的工具會檢查跨執行的持久建置身分識別。請先使用 `list_build_entities`，然後將傳回的穩定 `id` 與相同的 `kind` 傳遞給 `get_build_entity` 或 `list_build_entity_history`，並同時提供 `account_handle` 和 `project_handle`。不需要建置或呼叫識別碼。

| 工具 | 描述 | 必要參數 |
| --- | --- | --- |
| `list_build_entities` | 列出在專案建置中看到的一種類型的工作、模組、動作或檔案。 | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | 取得一個建置實體，包含其原生身分識別和所選期間的分析資料。 | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | 列出一個建置實體的已記錄執行、編譯或快取事件，由新到舊排序。 | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | 工具鏈 | 歷史清單 |
| --- | --- | --- |
| `bazel_actions` | Bazel 動作 | BEP 回報的動作執行 |
| `gradle_tasks` | Gradle 工作 | 工作執行 |
| `xcode_modules` | Xcode 模組 | 編譯和模組快取事件 |
| `once_actions` | Once 動作 | 執行 |
| `mix_files` | Mix 編譯檔案 | 編譯 |
| `mix_modules` | Mix 編譯模組 | 編譯 |
| `cargo_crates` | Cargo crate | 已記錄的 rustc 呼叫 |

這些工具正逐步推出，僅回傳已啟用該功能的專案資料；其他專案會回傳錯誤而非空結果。一種類型僅適用於使用其建置工具鏈的專案。工具接受有範圍的 `start_at`/`end_at` 篩選器、`environment`（`any`、`ci` 或 `local`）以及精確的 `branch`。`list_build_entities` 接受 `q`；`list_build_entity_history` 支援不透明的 `after`/`before` 游標。未知的計時或快取觀測值仍維持不可用，不會變成零或遺漏。歷史記錄會參考已記錄的父項和原生執行，以便使用現有的執行工具進行深入分析。

`get_build_entity` 指標包含 `duration_samples`，即具有記錄計時的觀測數量：真實的零持續時間會被計入，缺少計時則不會。此計數可能低於觀測總數；不可用的持續時間統計資料仍為 null。

Xcode 模組的持續時間來自建置日誌中測量的目標編譯。模組快取解析和沒有編譯工作的目標不會貢獻持續時間樣本。編譯觀測值參考 Xcode 建置；快取事件參考生成或快取指令。

Bazel 動作由目標標籤、助記符和設定的主要輸出識別，在不依賴輸入相依的快取摘要的情況下，保持不同的動作和設定區分開來。歷史記錄 BEP 回報的執行，而非快取查找或追蹤設定檔階段。完整的執行覆蓋率需要 `--build_event_publish_all_actions`；構件交付採最大努力原則，因此缺少的觀測值並非沒有執行工作的證據。較舊的 Kura 負載若無穩定身分識別或執行開始時間，仍會被接受但不建立索引。缺少的結束時間測量仍維持不可用，且真實的零持續時間會被計入。

Mix 模組持續時間測量的是包含檔案的編譯，而非獨立測量的模組工作。當用戶端回報目標對應時，Once 動作會使用宣告的目標/能力/索引槽位；僅靠診斷標籤並非穩定的身分識別。現有用戶端和執行層級工具仍維持不變地支援。

Cargo crate 依精確記錄的 crate 根目錄、名稱和種類分組。檢出路徑變更可能會分割歷史記錄，且不會區分建置設定檔、功能和目標三元組。歷史記錄測量 rustc 呼叫，而非每個檔案的工作或快取命中；缺少的工作不會確立移除或完整的工作區清單。

分析讀取具有記憶體和執行時間的限制。若查詢超過這些限制，工具會回傳錯誤而非捏造空結果。

新的觀測值會在部署後建立索引；此功能不會回填現有的執行遙測資料。在 <.localized_link href="/guides/server/data-retention">資料保留政策</.localized_link> 下，身分識別中繼資料的保存期限長於個別觀測值。

#### 測試

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_test_runs` | 列出專案的測試執行。`query` 欄位為 `git_branch`、`scheme` 和 `status`：`field:"value"` 為精確匹配，`field~"value"` 為不分大小寫的子字串匹配，前置 `-` 則否定任一運算子。例如，`-git_branch~"gh-readonly-queue"` 會排除合併佇列分支。以空白分隔的查詢篩選器和明確引數會以 AND 語意組合。 | `account_handle`, `project_handle` |
| `get_test_run` | 取得測試執行的詳細指標，包括其結果套件 (`.xcresult`) 和工作階段封存檔的暫時下載網址。 | `test_run_id` |
| `list_test_module_runs` | 列出特定測試執行的測試模組執行。 | `test_run_id` |
| `list_test_suite_runs` | 列出特定測試執行的測試套件執行，可選擇依模組篩選。 | `test_run_id` |
| `list_test_cases` | 列出專案的測試案例（支援如 `flaky` 等篩選器）。 | `account_handle`, `project_handle` |
| `get_test_case` | 取得測試案例的詳細指標，包括可靠度比率、不穩定比率和執行次數。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | 列出測試案例執行，可選擇依測試案例或測試執行篩選。 | `account_handle`, `project_handle` |
| `get_test_case_run` | 取得特定測試案例執行的失敗詳細資訊和重複次數。 | `test_case_run_id` |
| `list_test_case_run_attachments` | 列出測試案例執行的附件。每個附件都包含一個暫時下載網址。 | `test_case_run_id` |
| `list_test_case_events` | 列出測試案例的狀態變更，例如將其靜音或跳過。 | `test_case_id` |
| `update_test_case` | 更新測試案例的狀態或不穩定分類。變更可以將事件派送至設定的 webhook 端點，包括外部服務。 | `test_case_id` 或 `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | 列出測試執行的選擇性測試目標結果。 | `test_run_id` |
| `get_coverage` | 取得專案及其目標的代码覆蓋率，可在某個提交或分支的最新完整提交時取得。若沒有 `git_commit_sha` 或 `branch`，則讀取預設分支。 | `account_handle`, `project_handle` |
| `list_coverage_files` | 列出某個提交的代碼覆蓋率所測量的檔案及其行覆蓋率，可在某個提交或分支的最新完整提交時取得。支援 `search`、排序和分頁。 | `account_handle`, `project_handle` |
| `get_coverage_file` | 取得檔案的代碼覆蓋率及其函式，可在某個提交或分支的最新完整提交時取得。設定 `include_lines` 以取得每一行的執行次數。 | `account_handle`, `project_handle`, `path` |

代碼覆蓋率工具僅供已啟用代碼覆蓋率的帳戶使用。

#### 套件

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_bundles` | 列出專案的套件（應用程式二進位檔）。可選擇依 `git_branch` 和 `tags` 篩選（所有標籤必須精確匹配）。 | `account_handle`, `project_handle` |
| `get_bundle` | 取得特定套件的詳細資訊，包括自訂標籤。 | `bundle_id` |
| `get_bundle_artifact_tree` | 以依路徑排序的平面清單形式取得套件的完整構件樹。 | `bundle_id` |

`list_bundles` 接受 `tags: ["paid", "production"]` 以區分建置變體或環境。標籤是區分大小寫的標籤，包含字母、數字、連字號或底線，最多 10 個標籤，每個標籤最多 50 個字元。清單和詳細結果包含 `custom_metadata.tags`。分頁計數和分支篩選器適用於帶標籤的結果；省略 `tags` 則保留未篩選的行為。無效的標籤篩選器會回傳錯誤，而非擴大查詢範圍。

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
| `list_xcode_module_cache_targets` | 列出生成或快取執行的模組快取目標，顯示每個目標的快取命中/未命中狀態和診斷元件雜湊，包括額外的雜湊輸入。 | `run_id` |

#### 預覽

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_previews` | 列出專案的可共用應用程式預覽。 | `account_handle`, `project_handle` |
| `get_preview` | 取得預覽及其建置的暫時下載網址。 | `preview_id` |
| `get_latest_preview` | 找出正在運行的應用程式二進位檔的最新預覽。 | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### 自動化

| 工具 | 描述 | 必要參數 |
|------|-------------|---------------------|
| `list_automation_alerts` | 列出專案的自動化警示。 | `account_handle`, `project_handle` |
| `get_automation_alert` | 取得自動化警示。 | `alert_id` |
| `list_automation_alert_revisions` | 列出自動化警示的修訂歷史。動作憑證已遮蔽。 | `alert_id` |
| `list_project_notification_alerts` | 列出專案通知警示規則。需要與儀表板設定頁面相同的管理員權限。Webhook 位址已遮蔽。 | `account_handle`, `project_handle` |

### 事件

使用無狀態 `2026-07-28` Model Context Protocol 生命週期的用戶端可以呼叫 `events/list` 來探索事件及其負載結構：

| 事件 | 傳送時機 | 訂閱篩選器 |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | 測試案例從非不穩定變更為不穩定。 | `account_handle`, `project_handle` |
| `build.failed` | 本機或持續整合 Xcode、Gradle 或 Bazel 建置以失敗結束。 | `account_handle`, `project_handle` |
| `test_run.failed` | 本機或持續整合測試執行以失敗結束，包括合併的分片執行或放棄的執行。 | `account_handle`, `project_handle` |
| `ci_job.failed` | Tuist runner 工作以失敗完成。 | `account_handle` |

若要訂閱，用戶端會呼叫 `events/subscribe`，並傳入事件名稱、上述 `arguments` 中列出的控制代碼，以及包含 `https://` 回呼網址和 `whsec_` 簽署金鑰的 `webhook` 傳遞。專案事件需要帳戶成員資格以及對應測試或建置資料的讀取權限；runner 工作事件需要帳戶成員資格和 runner 讀取權限。已聲明的 [`auth.md`](https://workos.com/auth-md) 存取權杖、已聲明的帳戶權杖和瀏覽器授權授予可以建立訂閱；當相關憑證不再有效時，傳遞就會停止。每位用戶最多可保留 25 個有效訂閱。Tuist 會在儲存訂閱前向回呼發送驗證挑戰。回呼必須回傳包含相同 `challenge` 值的物件。訂閱預設持續七天，可以透過再次訂閱來續訂，並在移除用戶的存取權或憑證時停止傳遞。可選的 `ttlMs` 上限為一小時至 30 天。Tuist 會重試逾時的回呼，並在至少三次連續逾時（橫跨五分鐘）後取消訂閱；在恢復回呼後請再次訂閱。

當事件發生時，Tuist 會將其資源識別碼和儀表板網址傳送至回呼。建置和測試執行失敗也包含 `is_ci` 和 `git_branch`，因此用戶端可以忽略本機失敗或依分支篩選。建置事件包含 `build_system`；runner 工作事件同時包含 `workflow_job_id` 和 `workflow_run_id`。請求包含訂閱識別碼和 [Standard Webhooks](https://www.standardwebhooks.com/) 簽章標頭，以便用戶端驗證其來源。Tuist 會重試失敗的傳遞，因此用戶端應使用穩定的 `eventId` 來捨棄重複項目。負載省略測試名稱、日誌和失敗訊息；用戶端可以透過上述工具取得這些詳細資訊，並決定是否通知團隊或開始除錯。用戶端可以使用 `events/unsubscribe` 停止傳遞。

### 提示

| 提示 | 描述 |
|--------|-------------|
| `fix_flaky_test` | 引導你修復不穩定測試，透過分析失敗模式、找出根本原因，並套用針對性的修正。 |
| `compare_builds` | 引導你比較建置，以識別效能衰退、快取變更和建置問題。針對 Xcode、Gradle、Bazel 和 Cargo 專案使用原生工具。Cargo 比較會保留部分編譯器涵蓋範圍，並區分預估的編譯器工作與經過時間所節省的成本。 |
| `compare_test_runs` | 引導你比較兩次測試執行，以識別衰退、新失敗和不穩定測試。 |
| `compare_bundles` | 引導你比較兩個套件，以識別構件樹中的大小變更。 |
| `compare_test_case` | 引導你比較測試案例在兩個分支或時間段之間的行為。 |
| `compare_generations` | 引導你比較兩次產生執行，以識別效能衰退和模組快取變更。 |
| `compare_cache_runs` | 引導你比較兩次快取執行，以識別快取效率變更和目標層級的衰退。 |
| `integrate_gradle_project` | 引導你將 Tuist 整合至現有的 Gradle 專案。包括獨立的工具和 Gradle 驗證、帳戶探索、專案建立、遠端快取政策、建置洞察以及讀回驗證。 |
| `integrate_bazel_project` | 引導你建立或選擇 Bazel 專案、驗證命令列、設定遠端快取和建置洞察，並透過 Tuist 建置資料驗證整合。 |
| `integrate_xcode_project` | 引導你將 Tuist 整合至現有的 Xcode 專案。支援 Xcode 快取、建置洞察、測試洞察和測試分片。 |
| `ask_tuist` | 回答 Tuist 問題，使用公開材料作為背景，並以聚焦的實作和測試證據作為目前行為的真實來源。它需要 `question` 並引用修訂版本固定的證據。 |

專案資料提示接受 `account_handle` 和 `project_handle`，將調查範圍限定於特定專案。比較提示也接受 `base` 和 `head` 引數，以指定要比較的兩個項目（依 ID、儀表板網址或分支名稱）。`ask_tuist` 接受 `question` 而非專案參數。`integrate_gradle_project` 也接受 `features`，這是一個逗號分隔的 Gradle 整合清單：`remote_cache`、`build_insights`、`test_insights`、`flaky_tests` 和 `test_sharding`。`integrate_bazel_project` 接受可選的 `server_url`，適用於自託管或本機安裝。`integrate_xcode_project` 接受 `features`，包含 `xcode_cache`、`build_insights`、`test_insights` 和 `test_sharding`。

#### Gradle 整合提示功能

`integrate_gradle_project` 提示和 `get_gradle_integration_guide` 工具記錄完整的設定工作流程。伺服器初始化指示也會參考此工具，讓未列舉提示的代理程式也能發現它。

| 功能 | 代理程式設定的內容 |
|---------|---------------------------|
| `remote_cache` | 啟用 Gradle 的建置快取、設定 Tuist 遠端快取上傳政策，並建議僅從具有本機唯讀用法的持續整合 runner 上傳。 |
| `build_insights` | 套用 Tuist Gradle 外掛程式，並在需要時設定建置分析上傳行為。 |
| `test_insights` | 套用 Tuist Gradle 外掛程式，以便自動上傳 Gradle `Test` 任務結果。 |
| `flaky_tests` | 引導設定不穩定測試偵測、可選的 Gradle Test Retry 外掛程式用法，以及測試隔離設定。 |
| `test_sharding` | 新增持續整合工作流程，用於 `tuistPrepareTestShards`、分片矩陣產生，以及基於 `TUIST_SHARD_INDEX` 的測試執行。 |

當省略 `features` 時，提示會要求代理程式釐清用戶想要哪些整合，或在編輯 Gradle 專案前從請求中推斷最小的有用集合。

#### Xcode 整合提示功能

`integrate_xcode_project` 提示記錄 Tuist 支援的每種 Xcode 整合：

| 功能 | 代理程式設定的內容 |
|---------|---------------------------|
| `xcode_cache` | 設定 `tuist setup cache`、產生專案的快取設定、手動 Xcode 快取建置設定，以及僅限持續整合 runner 的上傳政策。 |
| `build_insights` | 透過 `tuist setup insights` 設定 `tuist inspect build`、`tuist xcodebuild`、`-resultBundlePath` 和可選的機器指標。 |
| `test_insights` | 設定 `tuist inspect test`、方案測試後動作，以及持續整合測試執行的結果套件產生。 |
| `test_sharding` | 新增使用 `TUIST_SHARD_INDEX` 的 Xcode 或生成專案分片規劃與分片執行工作流程。 |

當省略 `features` 時，提示會要求代理釐清使用者想要哪些整合，或從請求中推斷出最小且實用的組合，再編輯 Xcode 專案。
