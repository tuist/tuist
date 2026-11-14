---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · 功能 · Guides · Tuist",
  "description": "喺 Tuist Sandboxes（Linux 或 macOS）上執行 Claude Managed Agents 工作階段同 Claude Code 雲端工作階段（claude.ai、桌面同流動應用程式，以及 claude --cloud）。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社群 Slack](https://slack.tuist.dev)中聯絡我們，為你的帳戶申請存取權限。

Anthropic 負責執行 Claude 的代理迴圈，而*自託管環境*則決定 Claude 的工具在哪裡運行。將一個環境連接到 Tuist，其中的每個工作階段都會獲得自己的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>，可在 Linux 或 macOS 上運行。Tuist 會運行這些環境所需的 worker 和 runner，因此你無需託管任何東西。

有兩種環境，每種對應一個 Claude 產品：

- **[Claude Managed Agents](#managed-agents)**：你透過 Claude API 或 Tuist 的 agent-sessions API 啟動的工作階段。你在 [Claude Console](https://platform.claude.com/environments) 中建立環境（`env_…`），每個工作階段均可選擇 Linux 或 macOS。
- **[Claude Code](#claude-code)**：開發人員從 claude.ai、Claude 桌面和流動應用程式，以及 `claude --cloud` 啟動的雲端工作階段。Claude Team 或 Enterprise 擁有者在 claude.ai 管理設定中建立環境（`ccpool_…`），每個平台一個，開發人員透過選擇環境來挑選 Linux 或 macOS。

兩者均由帳戶管理員透過 Tuist API 連接。使用 `tuist auth login` 進行驗證，然後：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 連接環境 {#managed-agents-connect}

從你帳戶的 **Settings → Integrations → Claude** 進行連接。表單會要求提供自託管環境以及 Tuist 用來啟動工作階段的憑證：

1. **建立環境。** 在 Claude Console 的 [Environments](https://platform.claude.com/environments) 頁面建立自託管環境，開啟它並點擊 **Generate environment key**。Anthropic 僅在 Console 中產生環境金鑰。
2. 使用表單頂部的選擇器**選擇憑證**（見下文）。
3. **貼上環境 ID 和金鑰**，並選擇環境 sandbox 的平台和規格。

Tuist 在儲存任何資料之前會使用憑證抓取環境，因此如果憑證、ID 或工作區錯誤，表單會顯示失敗。它會加密儲存金鑰，且不會再次顯示。一分鐘內，Tuist 開始為該環境的工作階段提供服務。有關規格，請參閱 <.localized_link href="/guides/features/sandboxes#platforms">Linux 和 macOS</.localized_link>。

#### 使用 API 金鑰 {#managed-agents-connect-api-key}

這是預設選項，也是試用 sandbox 最快速的方法。貼上具有環境工作區開發者角色的 API 金鑰。整合功能會標記使用 API 金鑰的環境；在依賴它之前，請改用聯合身分連接，這樣 Tuist 就不會持有長期有效的金鑰。

#### 使用聯合身分 {#managed-agents-connect-federated}

Tuist 使用 Anthropic 的 [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) 進行驗證，因此你永遠不需要向它提供 Anthropic API 金鑰。你需要在 Anthropic 組織中擁有管理員角色。

1. **信任 Tuist。** 表單會顯示你帳戶的發行者 URL 和主體前綴。在 Claude Console 中，開啟 [Workload identity](https://platform.claude.com/settings/workload-identity-federation)，點擊 **Connect workload**，選擇 **Custom OIDC**，並輸入它們，範圍設為 `workspace:developer`。將精靈建立的服務帳戶添加到環境的工作區。
2. **輸入 ID。** 組織 ID 位於 **Settings → Organization** 下，工作區 ID 位於 **Settings → Workspaces** 下。連接工作負載完成後會顯示服務帳戶和聯合規則 ID，Workload identity 中的規則頁面也會再次顯示它們。這些都不是機密。如果 Anthropic 拒絕 Tuist 的令牌，Console 的 [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history) 會顯示原因。

#### 使用 API {#managed-agents-connect-api}

若要從自動化流程連接，請在 [Claude Console](https://platform.claude.com/environments) 中建立自託管環境，產生其金鑰，並將兩者發送給 Tuist：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

若要透過 Tuist 的 API 啟動工作階段，還需發送四個聯合 ID（參見 [不使用 API 金鑰連接](#managed-agents-federation)）或 `anthropic_api_key`。除非你傳遞 `"platform": "darwin"`，否則環境會在 Linux 上運行；`vcpus`、`memory_mb` 和 `workspace_gb` 會改變其 sandbox 的規格。

### 啟動工作階段 {#managed-agents-sessions}

除非工作階段要求其他平台，否則每個工作階段都在環境的平台上運行。

**使用 Claude API**時，照常使用環境 ID 建立工作階段，並將工作階段元數據中的 `tuist_platform` 設為 `macos` 或 `linux`：

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

`repository_url` 以及可選的 `repository_ref`（分支或提交）會讓 Tuist 在代理第一次輪詢之前將公共存儲庫克隆到 sandbox 中。

**使用 Tuist 的 agent-sessions API**時，Tuist 會為你建立代理和工作階段，並克隆連接到你 Tuist 帳戶的私有 GitHub 存儲庫：

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

當帳戶有多個環境時，請傳遞 `agent_environment_id`。你可以使用 `GET /agent-sessions/{id}/events` 追蹤工作階段，使用 `POST /agent-sessions/{id}/messages` 回覆，並使用 `POST /agent-sessions/{id}/archive` 結束它。

存儲庫在 Linux 上簽出到 `/workspace`，在 macOS 上簽出到 `/Users/runner/work`。工作階段的 sandbox 會在代理完成一輪後暫停，並在下一條訊息時恢復。

> [!WARNING]
> 任何能在擁有該環境的 Claude 工作區中建立工作階段的人，都可以在你的 Tuist 帳戶上運行工作階段，並可以透過工作階段元數據請求 macOS。請相應限制對該工作區的存取權限。

### 不使用 API 金鑰連接 {#managed-agents-federation}

儀表板會為你設置此功能。透過 API，Tuist 的工作方式相同：每個帳戶在 Tuist 都有自己的 OpenID Connect 發行者 `https://tuist.dev/oidc/accounts/<account id>`，並為每次呼叫 Anthropic 簽署一個短期令牌，然後將其交換為持續幾分鐘的 Anthropic 存取令牌。信任你發行者的聯合規則永遠不會接受 Tuist 為其他帳戶簽署的令牌。

- 每個代理環境響應都包含 `federation_issuer_url` 和 `federation_subject`（`account:123:agent-environment:456`）。在 Console 的 Custom OIDC 精靈中，使用發行者 URL 以及該確切主體（僅允許此環境）或 `account:123:*`（允許帳戶的所有環境）。儀表板的設置檢查使用主體 `account:123:setup`，只有前綴允許它。使用範圍 `workspace:developer`。
- 在建立時或使用 `PATCH /agent-environments/{id}` 時，將組織、工作區、服務帳戶和規則 ID 作為 `anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id` 和 `anthropic_federation_rule_id` 發送。當環境同時擁有 ID 和 API 金鑰時，Tuist 會使用聯合身分。

> [!NOTE]
> Anthropic 會透過 HTTPS 在端口 443 從公共主機名獲取發行者的金鑰。如果你的自託管 Tuist 伺服器無法從互聯網訪問，請在 Console 中選擇 **inline** JWKS 來源，並貼上你的伺服器在 `<issuer>/jwks.json` 提供的金鑰集。每當 Tuist 的簽署金鑰更改時（即伺服器的 `TUIST_SECRET_KEY_TOKENS` 更改，或在未設置時 `TUIST_SECRET_KEY_BASE` 更改），請再次貼上。

## Claude Code {#claude-code}

Claude Code 雲端工作階段是開發人員從 [claude.ai/code](https://claude.ai/code)、Claude 桌面和移動應用程式以及 `claude --cloud` 啟動的工作階段。他們透過環境選擇工作階段的運行位置，因此你需要為每個想要提供的平台連接一個環境。

### 連接環境 {#claude-code-connect}

1. Claude 組織所有者在 [Cloud environments](https://claude.ai/admin-settings/cloud-environments) 管理頁面上開啟 **Allow self-hosted environments**。這需要 Team 或 Enterprise 計劃；請參閱 Anthropic 的 [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) 指南。
2. 在同一頁面上，為每個平台建立一個自託管環境，使用開發人員將看到的名稱，例如 **Tuist Linux** 和 **Tuist macOS**。複製每個環境的 `ccpool_…` ID 及其環境金鑰，該金鑰僅顯示一次。
3. 將每個環境連接到你的 Tuist 帳戶，將 `kind` 設為 `claude_code` 並指定其平台：

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

   重複上述步驟，使用 `"platform": "linux"` 以及另一個環境的 ID 和金鑰。

一分鐘內，環境即可接受工作階段。閒置工作階段會保持其 sandbox 運行 30 分鐘，然後暫停；工作階段的下一條訊息會恢復同一個 sandbox。使用 `max_idle_seconds` 更改等待時間（最多 3600）。

### 選擇 Linux 或 macOS {#claude-code-choose}

開發人員在啟動雲端工作階段時選擇環境，從而選擇平台：

- **claude.ai、桌面和移動應用程式：** 在新工作階段的環境選擇器中選擇 **Tuist Linux** 或 **Tuist macOS**。
- **Claude Code CLI：** 在 `claude` 中運行 `/remote-env` 並按名稱選擇環境。`claude --cloud "<task>"` 隨後在其上運行。要為單個工作階段選擇一個環境，請傳遞其 ID：`claude --cloud "<task>" --environment ccpool_...`。
- **整個團隊或存儲庫：** 在 Claude Code [settings](https://code.claude.com/docs/en/settings) 中設置默認環境的 ID，例如在存儲庫的 `.claude/settings.json` 中：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

這些環境中的工作階段照常使用你組織的 Claude Code 用量，其 sandboxes 計入你的 Tuist 帳戶。

### 更快的工作階段啟動和構建 {#claude-code-caching}

- **Tuist 緩存：** 工作階段會獲得 `TUIST_URL`，並且當你的帳戶在同一機架中有緩存時，還會獲得 `TUIST_CACHE_ENDPOINT`。工作階段中的 Tuist CLI 和 `tuist_ex` Mix 任務會使用工作階段的身份令牌自行登錄。請參閱身份驗證指南中的 <.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code sessions</.localized_link>。
- **緩存簽出：** 當你帳戶的 Tuist GitHub 應用程式可以讀取工作階段的存儲庫時，新工作階段會從你的 Tuist runners 使用的相同緩存簽出開始，因此它只獲取缺少的提交而不是克隆。當工作階段結束時，它會返回默認分支最新提交的對象，這使得即使對於不在 Tuist 上運行 CI 的存儲庫，緩存簽出也能保持最新。只有 GitHub 報告的默認分支提交會更新它；工作階段自己的分支永遠不會。禁用 sandboxes 或卸載應用程式以停止此功能。
- **macOS：** Mac 與每個 VM 共享運行的 Claude Code 構建工作階段，因此新工作階段無需下載它。

## 從任何 Claude Code 工作階段使用 Mac {#remote-mac}

在 Linux 上運行的 Claude Code 工作階段（例如 Anthropic 託管環境中的雲端工作階段）仍然可以在 Tuist macOS sandbox 上構建和測試 Apple 平台代碼，如 <.localized_link href="/guides/features/sandboxes#coding-agents">Build on a Mac from a coding agent</.localized_link> 中所述。與 **Tuist macOS** 環境不同，工作階段保留其自己的環境。

在 **Tuist Linux** 環境中無需設置任何內容：Tuist CLI 和 Tuist MCP 伺服器已安裝並使用工作階段的身份登錄。

對於 Anthropic 託管環境中的雲端工作階段：

1. 使 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link> 對工作階段可用：在 claude.ai 中將 `https://tuist.dev/mcp` 添加為連接器並為工作階段啟用它，或在存儲庫的已提交 `.mcp.json` 中聲明它。
2. 在環境的 [setup script](https://code.claude.com/docs/en/cloud-environments#setup-scripts) 中安裝 Tuist CLI，例如使用 `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. 建立具有 `account:sandboxes:write` 範圍的 <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link>，並將其作為 `TUIST_TOKEN` 添加到環境的 [environment variables](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) 中。每個使用該環境的人都可以讀取它，因此不要賦予其他範圍。
4. 讓環境能夠訪問 Tuist。Anthropic 的默認 **Trusted** 網絡訪問不包括 `tuist.dev`，因此請選擇 **Custom**，保留默認域，並將 `tuist.dev` 添加到 **Allowed domains**。CLI 透過 `tuist.dev` 將工作階段的文件上傳到 Mac，因此不需要其他域。

Claude 會在任務完成後刪除 Mac。遺留的 Mac 在閒置時暫停，並在暫停 14 天後刪除。以這種方式創建的 Mac 像其他 sandbox 一樣計入你的 Tuist 帳戶。
