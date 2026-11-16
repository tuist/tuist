---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · 功能 · 指南 · Tuist",
  "description": "在 Tuist Sandboxes（Linux 或 macOS）上執行 Claude Managed Agents 工作階段與 Claude Code 雲端工作階段（claude.ai、桌面與行動應用程式，以及 claude --cloud）。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（Linux 與 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯繫我們，以請求為你的帳戶開通存取權限。

Anthropic 負責執行 Claude 的代理迴圈，而*自託管環境*則決定 Claude 的工具在哪裡執行。將一個環境連接至 Tuist，其中的每個工作階段都會獲得專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>，可運行於 Linux 或 macOS。Tuist 會執行這些環境所需的 worker 與 runner，因此你無需自行託管任何基礎設施。

共有兩種環境，分別對應不同的 Claude 產品：

- **[Claude Managed Agents](#managed-agents)**：你透過 Claude API 或 Tuist 的 agent-sessions API 啟動的工作階段。你在[Claude Console](https://platform.claude.com/environments)中建立環境（`env_…`），每個工作階段皆可選擇 Linux 或 macOS。
- **[Claude Code](#claude-code)**：開發者從 claude.ai、Claude 桌面與行動應用程式，以及`claude --cloud`啟動的雲端工作階段。Claude Team 或 Enterprise 擁有者在 claude.ai 管理設定中為每個平台各建立一個環境（`ccpool_…`），開發者則透過選擇環境來挑選 Linux 或 macOS。

兩者皆由帳戶管理員透過 Tuist API 進行連接。使用`tuist auth login`進行驗證，然後：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 連接環境 {#managed-agents-connect}

從你帳戶的**Settings → Integrations → Claude**進行連接。表單會要求提供自託管環境，以及 Tuist 用來啟動工作階段的憑證：

1. **建立環境。** 在 Claude Console 的[Environments](https://platform.claude.com/environments)頁面中建立自託管環境，開啟該環境並點擊**Generate environment key**。Anthropic 僅會在 Console 中產生環境金鑰。
2. 使用表單頂部的選擇器**選擇憑證**（見下文）。
3. **貼上環境 ID 與金鑰**，並選擇環境中 sandbox 的平台與規格。

Tuist 會在儲存任何資料前先使用憑證抓取環境資訊，因此若憑證、ID 或工作區錯誤，表單驗證將會失敗。金鑰會以加密方式儲存，且不會再次顯示。一分鐘內，Tuist 即會開始提供該環境的工作階段服務。關於規格詳情，請參閱<.localized_link href="/guides/features/sandboxes#platforms">Linux 與 macOS</.localized_link>。

#### 使用 API 金鑰 {#managed-agents-connect-api-key}

這是預設選項，也是試用 sandbox 最快速的方式。貼上具備環境工作區中 developer 角色的 API 金鑰。整合功能會標記使用 API 金鑰的環境；在依賴此方式之前，建議改用聯合身分進行連接，以免 Tuist 持有長期有效的金鑰。

#### 使用聯合身分 {#managed-agents-connect-federated}

Tuist 透過 Anthropic 的[Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)進行驗證，因此你無需提供 Anthropic API 金鑰。你需要在 Anthropic 組織中具備 admin 角色。

1. **信任 Tuist。** 表單會顯示你帳戶的發行者 URL 與主體前綴。在 Claude Console 中，開啟[Workload identity](https://platform.claude.com/settings/workload-identity-federation)，點擊**Connect workload**，選擇**Custom OIDC**，並輸入上述資訊，範圍設為`workspace:developer`。將精靈建立的服務帳戶加入環境的工作區。
2. **輸入 ID。** 組織 ID 位於**Settings → Organization**下方，工作區 ID 位於**Settings → Workspaces**下方。連接工作負載完成後，會顯示服務帳戶與聯合規則 ID；Workload identity 中的規則頁面也會再次顯示這些 ID。這些都不是機密。若 Anthropic 拒絕 Tuist 的權杖，Console 的[authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)會顯示原因。

#### 使用 API {#managed-agents-connect-api}

若要透過自動化流程進行連接，請在[Claude Console](https://platform.claude.com/environments)中建立自託管環境、產生其金鑰，並將兩者傳送給 Tuist：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

若要透過 Tuist API 啟動工作階段，還需傳送四個聯合 ID（參見[不使用 API 金鑰進行連接](#managed-agents-federation)）或`anthropic_api_key`。除非你傳遞`"platform": "darwin"`，否則環境將在 Linux 上運行；`vcpus`、`memory_mb`與`workspace_gb`則會改變其 sandbox 的規格。

### 啟動工作階段 {#managed-agents-sessions}

除非工作階段要求其他平台，否則每個工作階段都会在環境指定的平台上運行。

**使用 Claude API**時，照常使用環境 ID 建立工作階段，並將工作階段元資料中的`tuist_platform`設為`macos`或`linux`：

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

`repository_url`以及可選的`repository_ref`（分支或提交雜湊）會讓 Tuist 在代理執行第一個回合前，將公開儲存庫複製到 sandbox 中。

**使用 Tuist 的 agent-sessions API**時，Tuist 會為你建立代理與工作階段，並複製已連接至你 Tuist 帳戶的私有 GitHub 儲存庫：

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

當帳戶擁有多個環境時，請傳遞`agent_environment_id`。你可以透過`GET /agent-sessions/{id}/events`追蹤工作階段，使用`POST /agent-sessions/{id}/messages`回覆，並透過`POST /agent-sessions/{id}/archive`結束工作階段。

在 Linux 上，儲存庫會檢出至`/workspace`；在 macOS 上則檢出至`/Users/runner/work`。工作階段的 sandbox 會在代理完成一個回合後暫停，並在收到下一則訊息時恢復。

> [!WARNING]
> 任何能在擁有該環境的 Claude 工作區中建立工作階段的人，都可以在你的 Tuist 帳戶上運行工作階段，並可透過工作階段元資料要求 macOS。請相應限制對該工作區的存取權限。

### 不使用 API 金鑰進行連接 {#managed-agents-federation}

儀表板會為你完成此設定。透過 API 時，Tuist 的運作方式相同：每個帳戶在 Tuist 都有專屬的 OpenID Connect 發行者`https://tuist.dev/oidc/accounts/<account id>`，並為每次呼叫 Anthropic 簽署短期權杖，隨後將其交換為有效期僅數分鐘的 Anthropic 存取權杖。信任你發行者的聯合規則絕不會接受 Tuist 為其他帳戶簽署的權杖。

- 每個代理環境回應都包含`federation_issuer_url`與`federation_subject`（`account:123:agent-environment:456`）。在 Console 的 Custom OIDC 精靈中，使用發行者 URL，並選擇該確切主體以僅允許此環境，或選擇`account:123:*`以允許該帳戶下的所有環境。儀表板的設定檢查使用主體`account:123:setup`，僅前綴相符即可通過。使用範圍`workspace:developer`。
- 在建立時或使用`PATCH /agent-environments/{id}`時，將組織、工作區、服務帳戶與規則 ID 分別作為`anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id`與`anthropic_federation_rule_id`傳送。當環境同時具備這些 ID 與 API 金鑰時，Tuist 會使用聯合身分驗證。

> [!NOTE]
> Anthropic 會透過 HTTPS 從公開主機名稱的 443 埠取得發行者的金鑰。若你的自託管 Tuist 伺服器無法從網際網路存取，請在 Console 中選擇**inline** JWKS 來源，並貼上你的伺服器在`<issuer>/jwks.json`提供的金鑰組。每當 Tuist 的簽署金鑰變更時（即伺服器的`TUIST_SECRET_KEY_TOKENS`或在其未設定時的`TUIST_SECRET_KEY_BASE`變更），都需再次貼上。

## Claude Code {#claude-code}

Claude Code 雲端工作階段是開發者從[claude.ai/code](https://claude.ai/code)、Claude 桌面與行動應用程式，以及`claude --cloud`啟動的工作階段。他們透過環境選擇工作階段的執行位置，因此你應為每個想提供的平台連接一個環境。

### 連接環境 {#claude-code-connect}

1. Claude 組織擁有者在[Cloud environments](https://claude.ai/admin-settings/cloud-environments)管理頁面啟用**Allow self-hosted environments**。這需要 Team 或 Enterprise 方案；請參閱 Anthropic 的[self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments)指南。
2. 在同一頁面上，為每個平台建立自託管環境，並設定開發者將看到的名稱，例如**Tuist Linux**與**Tuist macOS**。複製每個環境的`ccpool_…` ID 及其環境金鑰，該金鑰僅顯示一次。
3. 將每個環境連接至你的 Tuist 帳戶，並將`kind`設為`claude_code`及其平台：

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

   使用`"platform": "linux"`以及其他環境的 ID 與金鑰重複上述步驟。

一分鐘內，環境即可接受工作階段。閒置工作階段會讓其 sandbox 持續運行 30 分鐘，然後暫停；工作階段的下一則訊息會恢復同一個 sandbox。你可以透過`max_idle_seconds`調整等待時間（最高 3600）。

### 選擇 Linux 或 macOS {#claude-code-choose}

開發者在啟動雲端工作階段時選擇環境，進而選擇平台：

- **claude.ai、桌面與行動應用程式：** 在新工作階段的環境選擇器中選擇**Tuist Linux**或**Tuist macOS**。
- **Claude Code CLI：** 在`claude`中執行`/remote-env`並依名稱選擇環境。`claude --cloud "<task>"`隨後會在該環境上執行。若要為單一工作階段選擇特定環境，請傳遞其 ID：`claude --cloud "<task>" --environment ccpool_...`。
- **整個團隊或儲存庫：** 在 Claude Code [settings](https://code.claude.com/docs/en/settings)中設定預設環境的 ID，例如在儲存庫的`.claude/settings.json`中：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

這些環境中的工作階段會照常使用你組織的 Claude Code 用量，而其 sandboxes 則計入你的 Tuist 帳戶。

### 更快的工作階段啟動與建置 {#claude-code-caching}

- **Tuist 快取：** 工作階段會獲得`TUIST_URL`，且當你的帳戶在同一機架中有快取時，還會獲得`TUIST_CACHE_ENDPOINT`。工作階段中的 Tuist CLI 與`tuist_ex` Mix 任務會使用工作階段的身份權杖自行登入。請參閱驗證指南中的<.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link>。
- **快取檢出：** 當你帳戶的 Tuist GitHub 應用程式能讀取工作階段的儲存庫時，新工作階段會從 Tuist runners 使用的相同快取檢出啟動，因此只會抓取缺少的提交，而非完整複製。當工作階段結束時，它會回傳預設分支最新提交的物件，讓快取檢出保持最新，即使該儲存庫未在 Tuist 上執行 CI 亦然。只有 GitHub 回報的預設分支提交會更新它；工作階段自身的分支永遠不會。停用 sandboxes 或解除安裝應用程式以停止此行為。
- **macOS：** Mac 會與每個 VM 共用 Claude Code 建置工作階段，因此新工作階段無需下載。

## 從任何 Claude Code 工作階段使用 Mac {#remote-mac}

在 Linux 上執行的 Claude Code 工作階段（例如 Anthropic 託管環境中的雲端工作階段）仍可在 Tuist macOS sandbox 上建置與測試 Apple 平台程式碼，如<.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link>所述。與**Tuist macOS**環境不同，此工作階段會保留其自身環境。

在**Tuist Linux**環境中無需設定：Tuist CLI 與 Tuist MCP 伺服器已安裝完畢，並使用工作階段身份登入。

對於 Anthropic 託管環境中的雲端工作階段：

1. 讓 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link>可供工作階段使用：在 claude.ai 中將`https://tuist.dev/mcp`新增為連接器並為工作階段啟用，或在儲存庫已提交的`.mcp.json`中宣告。
2. 在環境的[setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts)中安裝 Tuist CLI，例如使用`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. 建立具有`account:sandboxes:write`範圍的<.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，並將其作為`TUIST_TOKEN`加入環境的[environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)。所有使用該環境的人都能讀取它，因此除非他們也可能使用你的快取，否則不要賦予其他範圍：Mac 上的指令僅在權杖具備<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">cache access</.localized_link>時才能存取，因此請新增`ci`以便 Mac 上的建置讀寫你的快取。
4. 允許環境存取 Tuist。Anthropic 預設的**Trusted**網路存取不包含`tuist.dev`，因此請選擇**Custom**，保留預設網域，並將`tuist.dev`加入**Allowed domains**。CLI 會透過`tuist.dev`將工作階段檔案上傳至 Mac，因此不需要其他網域。

首次同步後，Claude 會在 Mac 上的儲存庫根目錄執行`mise install`以安裝專案指定的 Tuist 版本；Tuist 4.218.0 及更高版本隨後會在每個指令中自行登入你帳戶的快取。

任務完成後，Claude 會刪除 Mac。遺留的 Mac 在閒置時會暫停，並在暫停 14 天後刪除。以此方式建立的 Mac 會像其他 sandbox 一樣計入你的 Tuist 帳戶。
