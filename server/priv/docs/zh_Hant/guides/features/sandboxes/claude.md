---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · 功能 · Guides · Tuist",
  "description": "在 Tuist Sandboxes（Linux 或 macOS）上執行 Claude Managed Agents 工作階段與 Claude Code 雲端工作階段（claude.ai、桌面與行動應用程式，以及 claude --cloud）。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（Linux 與 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以請求為你的帳戶開啟存取權限。

Anthropic 執行 Claude 的代理迴圈，而*自託管環境*決定 Claude 的工具在哪裡執行。將一個環境連接到 Tuist，其中的每個工作階段都會獲得專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>，可在 Linux 或 macOS 上執行。Tuist 會執行這些環境所需的 worker 與 runner，因此你無需自行託管任何資源。

有兩種環境，每種對應一個 Claude 產品：

- **[Claude Managed Agents](#managed-agents)**：你透過 Claude API 或 Tuist 的 agent-sessions API 啟動的工作階段。你在 [Claude Console](https://platform.claude.com/environments) 中建立環境（`env_…`），每個工作階段皆可選擇 Linux 或 macOS。
- **[Claude Code](#claude-code)**：開發者從 claude.ai、Claude 桌面與行動應用程式，以及`claude --cloud`啟動的雲端工作階段。Claude Team 或 Enterprise 擁有者在 claude.ai 管理設定中建立環境（`ccpool_…`），每個平台各一個，開發者透過選擇環境來挑選 Linux 或 macOS。

兩者都由帳戶管理員透過 Tuist API 進行連接。使用`tuist auth login`進行驗證，然後：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 連接環境 {#managed-agents-connect}

從你帳戶的**Settings → Integrations → Claude**進行連接。表單會要求提供自託管環境，以及 Tuist 用來啟動工作階段的憑證：

1. **建立環境。** 在 Claude Console 的[Environments](https://platform.claude.com/environments)頁面建立自託管環境，開啟該環境並點擊**Generate environment key**。Anthropic 僅會在 Console 中產生環境金鑰。
2. 使用表單頂部的選擇器**選擇憑證**（見下文）。
3. **貼上環境 ID 與金鑰**，並選擇環境 sandbox 的平台與規格。

Tuist 在儲存任何資料之前，會先使用憑證抓取環境資訊，因此憑證、ID 或 workspace 錯誤時，表單會顯示失敗。它會以加密方式儲存金鑰，且不會再次顯示。在一分鐘內，Tuist 就會開始提供該環境的工作階段服務。關於規格，請參閱<.localized_link href="/guides/features/sandboxes#platforms">Linux 與 macOS</.localized_link>。

#### 使用 API 金鑰 {#managed-agents-connect-api-key}

這是預設選項，也是試用 sandbox 最快速的方式。貼上具備環境 workspace 中 developer 角色的 API 金鑰。整合功能會標記使用 API 金鑰的環境；在依賴此方式之前，請改用聯合身分進行連接，這樣 Tuist 就不會持有長期有效的金鑰。

#### 使用聯合身分 {#managed-agents-connect-federated}

Tuist 使用 Anthropic 的[Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)進行驗證，因此你無需提供 Anthropic API 金鑰給它。你需要在 Anthropic 組織中擁有 admin 角色。

1. **信任 Tuist。** 表單會顯示你帳戶的發行者 URL 與主體前綴。在 Claude Console 中，開啟[Workload identity](https://platform.claude.com/settings/workload-identity-federation)，點擊**Connect workload**，選擇**Custom OIDC**，並輸入它們，範圍設為`workspace:developer`。將精靈建立的服務帳戶加入環境的 workspace。
2. **輸入 ID。** 組織 ID 位於**Settings → Organization**下方，workspace ID 位於**Settings → Workspaces**下方。連接工作負載完成後，會顯示服務帳戶與聯邦規則 ID，而 Workload identity 中的規則頁面也會再次顯示這些 ID。它們都不是機密。如果 Anthropic 拒絕 Tuist 的令牌，Console 的[authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)會顯示原因。

#### 使用 API {#managed-agents-connect-api}

若要從自動化流程進行連接，請在[Claude Console](https://platform.claude.com/environments)中建立自託管環境、產生其金鑰，並將兩者傳送給 Tuist：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

若要透過 Tuist 的 API 啟動工作階段，還需傳送四個聯邦 ID（見[不使用 API 金鑰進行連接](#managed-agents-federation)）或`anthropic_api_key`。除非你傳遞`"platform": "darwin"`，否則環境會在 Linux 上執行；`vcpus`、`memory_mb`與`workspace_gb`會改變其 sandbox 的規格，而`xcode_version`則設定其 macOS sandbox 的[Xcode](#xcode)版本。

### 啟動工作階段 {#managed-agents-sessions}

除非工作階段要求其他平台，否則每個工作階段都會在環境的平台上執行。

**使用 Claude API**時，照常使用環境 ID 建立工作階段，並將工作階段中繼資料中的`tuist_platform`設為`macos`或`linux`：

```bash
curl https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "agent": "agent_...",
    "environment_id": "env_...",
    "metadata": {
      "tuist_platform": "macos",
      "repository_url": "https://github.com/my-org/my-app"
    }
  }'
```

`repository_url`與（可選的）`repository_ref`（分支或提交）會讓 Tuist 在代理的第一輪動作之前，將公開儲存庫複製到 sandbox 中。

**使用 Tuist 的 agent-sessions API**時，Tuist 會為你建立代理與工作階段，並複製已連接到你 Tuist 帳戶的私有 GitHub 儲存庫：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-sessions" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "prompt": "Fix the failing snapshot tests",
    "platform": "darwin",
    "repository_url": "https://github.com/my-org/my-app",
    "repository_ref": "main"
  }'
```

當帳戶有多個環境時，請傳遞`agent_environment_id`。你可以使用`GET /agent-sessions/{id}/events`追蹤工作階段，使用`POST /agent-sessions/{id}/messages`回覆，並使用`POST /agent-sessions/{id}/archive`結束工作階段。

在 Linux 上，儲存庫會檢出至`/workspace`；在 macOS 上則檢出至`/Users/runner/work`。工作階段的 sandbox 會在代理完成一輪動作後暫停，並在收到下一則訊息時恢復。

### 選擇工作階段的 Xcode {#managed-agents-xcode}

工作階段的 Mac 會在 Claude 執行任何工具之前開機，因此 Claude 無法自行選擇 Xcode。由建立工作階段的人選擇 Xcode，選擇方式與選擇 macOS 相同。Tuist 會採用以下第一個已設定的選項：

1. Tuist 的 agent-sessions API 中，與`platform`相鄰的`xcode_version`。若你選擇的版本 Tuist 未提供，建立工作階段時會被拒絕，並顯示你可選擇的版本清單。
2. 使用 Claude API 建立工作階段時，工作階段中繼資料中的`tuist_xcode_version`：

   ```json
   "metadata": { "tuist_platform": "macos", "tuist_xcode_version": "26.1.1" }
   ```

3. 當工作階段在環境的平台上執行時，使用環境的`xcode_version`。
4. 預設 Xcode。

未指定平台的 Xcode 會預設要求 macOS。注意事項：

- **工作階段會保留其 Xcode。** 其 sandbox 僅開機一次，後續訊息或變更的中繼資料不會改變它。若要使用另一個 Xcode，請建立新的工作階段。
- **Tuist 會在第一輪動作到達時檢查中繼資料。** 如果`tuist_xcode_version`指定的 Xcode 版本 Tuist 未提供，Tuist 會停止該輪動作且不啟動 sandbox，並記錄你可選擇的版本。使用 Tuist 的 agent-sessions API 可在建立工作階段時取得此錯誤。
- **在 macOS 環境中，Tuist 會等待而非猜測。** 如果 Tuist 無法讀取新工作階段的中繼資料，它會暫停該輪動作並重試，而不是啟動環境的 Xcode。

> [!WARNING]
> 任何能在擁有該環境的 Claude 工作區中建立工作階段的人，都可以在你的 Tuist 帳戶上執行工作階段，並透過工作階段中繼資料要求 macOS 及其 Xcode。請相應限制對該工作區的存取權限。

### 無需 API 金鑰即可連接 {#managed-agents-federation}

儀表板會為你設定此功能。透過 API，Tuist 的運作方式相同：每個帳戶在 Tuist 都有自己的 OpenID Connect 發行者 `https://tuist.dev/oidc/accounts/<account id>`，並為每次呼叫 Anthropic 簽署一個短期有效的權杖，然後將其交換為持續幾分鐘的 Anthropic 存取權杖。信任你發行者的聯合規則絕不會接受 Tuist 為其他帳戶簽署的權杖。

- 每個代理環境回應都包含 `federation_issuer_url` 和 `federation_subject`（`account:123:agent-environment:456`）。在控制台的自訂 OIDC 精靈中，使用發行者 URL 以及該確切的主體以僅允許此環境，或使用 `account:123:*` 以允許該帳戶的所有環境。儀表板的設定檢查使用主體 `account:123:setup`，僅前綴相符即可允許。使用範圍 `workspace:developer`。
- 在建立時或透過 `PATCH /agent-environments/{id}`，將組織、工作區、服務帳戶和規則 ID 作為 `anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id` 和 `anthropic_federation_rule_id` 傳送。當環境同時擁有這些 ID 和 API 金鑰時，Tuist 會使用聯合驗證。

> [!NOTE]
> Anthropic 會透過 HTTPS 從公開主機名稱的 443 埠取得發行者的金鑰。如果你的自託管 Tuist 伺服器無法從網際網路存取，請在控制台中選擇 **內嵌** JWKS 來源，並貼上你的伺服器在 `<issuer>/jwks.json` 提供的金鑰組。每當 Tuist 的簽署金鑰變更時（這發生在伺服器的 `TUIST_SECRET_KEY_TOKENS` 變更時，若未設定則為 `TUIST_SECRET_KEY_BASE`），請再次貼上。

## Claude Code {#claude-code}

Claude Code 雲端工作階段是開發人員從 [claude.ai/code](https://claude.ai/code)、Claude 桌面與行動應用程式，以及 `claude --cloud` 啟動的工作階段。他們透過環境選擇工作階段的執行位置，因此你需要為每個想要提供的平台連接一個環境。

### 連接環境 {#claude-code-connect}

1. Claude 組織擁有者在 [Cloud environments](https://claude.ai/admin-settings/cloud-environments) 管理頁面開啟 **Allow self-hosted environments**。這需要 Team 或 Enterprise 方案；請參閱 Anthropic 的 [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) 指南。
2. 在同一頁面上，為每個平台建立自託管環境，並使用開發人員將看到的名稱，例如 **Tuist Linux** 和 **Tuist macOS**。複製每個環境的 `ccpool_…` ID 及其環境金鑰，該金鑰僅顯示一次。
3. 將每個環境連接到你的 Tuist 帳戶，並將 `kind` 設為 `claude_code` 及其平台：

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "kind": "claude_code",
       "platform": "darwin",
       "name": "Tuist macOS",
       "anthropic_environment_id": "ccpool_...",
       "environment_key": "<environment key>"
     }'
   ```

   對另一個環境的 ID 和金鑰重複此操作，並將 `"platform": "linux"` 設為相應值。

一分鐘內，環境即可接受工作階段。閒置的工作階段會讓其 sandbox 繼續執行 30 分鐘，然後暫停；工作階段的下一則訊息會恢復相同的 sandbox。使用 `max_idle_seconds` 變更等待時間（最多 3600 秒）。

### 選擇 Linux 或 macOS {#claude-code-choose}

開發人員在啟動雲端工作階段時選擇環境，進而選擇平台：

- **claude.ai、桌面與行動應用程式：** 在新工作階段的環境選擇器中選擇 **Tuist Linux** 或 **Tuist macOS**。
- **Claude Code CLI：** 在 `claude` 中執行 `/remote-env` 並依名稱選擇環境。`claude --cloud "<task>"` 隨後會在該環境上執行。若要為單一工作階段選擇特定環境，請傳遞其 ID：`claude --cloud "<task>" --environment ccpool_...`。
- **整個團隊或儲存庫：** 在 Claude Code [settings](https://code.claude.com/docs/en/settings) 中設定預設環境的 ID，例如在儲存庫的 `.claude/settings.json` 中：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

這些環境中的工作階段會照常使用你組織的 Claude Code 用量，而其 sandbox 則計入你的 Tuist 帳戶。

### 選擇 Xcode {#xcode}

每個 macOS 環境都會啟動一個 <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>，除非你使用 `xcode_version` 連接它（例如 `"xcode_version": "26.1.1"`），否則會使用預設版本。若要提供多個版本，請為每個版本連接一個環境並以其命名，例如 **Tuist macOS · Xcode 26.1.1**。開發人員接著透過選擇環境來挑選 Xcode。

若要將環境切換至另一個 Xcode，請更新它：

```bash
curl -X PATCH "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments/<id>" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{ "xcode_version": "27.0" }'
```

新工作階段會獲得新的 Xcode，而已有 sandbox 的工作階段則保留原有的。`null` 會恢復為預設值。這同樣適用於 Managed Agents 環境，其工作階段也可以[自行選擇](#managed-agents-xcode)。

### 更快的工作階段啟動與建置 {#claude-code-caching}

- **Tuist 快取：** 工作階段會獲得 `TUIST_URL`，且當你的帳戶在同一機架中有快取時，還會獲得 `TUIST_CACHE_ENDPOINT`。工作階段中的 Tuist CLI 和 `tuist_ex` Mix 任務會使用工作階段的身份權杖自行登入。請參閱驗證指南中的 <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link>。
- **快取的檢出副本：** 當你帳戶的 Tuist GitHub 應用程式能夠讀取工作階段的儲存庫時，新工作階段會從 Tuist 執行器使用的相同快取檢出副本啟動，因此它只會抓取缺少的提交，而非完整複製。當工作階段結束時，它會傳回預設分支最新提交的物件，這使得即使未在 Tuist 上執行 CI 的儲存庫也能保持快取檢出副本為最新狀態。只有 GitHub 報告的預設分支提交會更新它；工作階段自身的分支永遠不會。停用 sandbox 或解除安裝應用程式以停止此行為。
- **macOS：** Mac 會與每個 VM 共用 Claude Code 建置工作階段的執行結果，因此新工作階段無需下載。

## 從任何 Claude Code 工作階段使用 Mac {#remote-mac}

在 Linux 上執行的 Claude Code 工作階段（例如 Anthropic 託管環境中的雲端工作階段）仍然可以在 Tuist macOS sandbox 上建置和測試 Apple 平台程式碼，如 <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link> 所述。與 **Tuist macOS** 環境不同，工作階段會保留其自身的環境。

在 **Tuist Linux** 環境中無需任何設定：Tuist CLI 和 Tuist MCP 伺服器已安裝完畢，並使用工作階段的身份登入。

對於 Anthropic 託管環境中的雲端工作階段：

1. 讓 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> 可供工作階段使用：在 claude.ai 中將 `https://tuist.dev/mcp` 添加為連接器並為工作階段啟用，或在儲存庫已提交的 `.mcp.json` 中宣告它。
2. 在環境的 [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) 中安裝 Tuist CLI，例如使用 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. 建立具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，並將其作為 `TUIST_TOKEN` 加入環境的 [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)。所有使用此環境的人都能讀取它，因此除非他們也需要使用你的快取，否則不要賦予其他範圍：Mac 上的指令僅能獲得權杖所允許的 <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link>，因此請添加 `ci` 以讓 Mac 上的建置能夠讀寫你的快取。
4. 讓環境能夠連線至 Tuist。Anthropic 預設的 **Trusted** 網路存取不包含 `tuist.dev`，因此請選擇 **Custom**，保留預設網域，並將 `tuist.dev` 加入 **Allowed domains**。CLI 會透過 `tuist.dev` 將工作階段的檔案上傳至 Mac，因此不需要其他網域。

Mac 上已安裝 Tuist CLI，並在專案透過 mise 鎖定版本時執行該版本；Tuist 4.218.0 及更新版本會在每個指令中自行登入你帳戶的快取。

### 就緒的 Mac {#remote-mac-snapshots}

**Tuist Linux** 環境可以預先準備這些 Mac。透過 API 設定其 macOS 設定腳本（在 `PATCH /api/accounts/{account}/sandboxes/agent-environments/{id}` 上使用 `macos_setup_script`），例如：

```bash
mise install
tuist install
tuist generate --no-open
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17'
```

當 Claude 為連接到你其中一個 Tuist 專案的儲存庫建立 Mac 時，`create_sandbox` 會取得該儲存庫，且 Mac 會從該儲存庫針對其 Xcode 的快照啟動：預設分支會被克隆至 `~/work/<name>`，腳本已在該處執行，且建置產物已就緒。首次 `tuist sandbox sync` 只會傳送與該提交不同的檔案，因此 Xcode 僅會重新建置受影響的部分。儲存庫和 Xcode 的第一台 Mac 會以空白狀態啟動，並在閒置的 Mac 上建置其快照（最多一小時），以供後續的 Mac 使用。變更腳本、Xcode 或映像檔會重新建置。快照會保留映像檔中的模擬器，並移除腳本建立的模擬器，且每台這類 Mac 在啟動後會立即開始啟動映像檔中最新的 Pro iPhone（Xcode 27.2 上的 iPhone 18 Pro），因此在首次建置結束時就已就緒；也在腳本中為該模擬器進行建置，以便工作階段針對該模擬器的建置能夠重複使用快照。

任務完成後，Claude 會刪除 Mac。遺留的 Mac 在閒置時會暫停，並在暫停 14 天後刪除。以此方式建立的 Mac 會像其他 sandbox 一樣計入你的 Tuist 帳戶。
