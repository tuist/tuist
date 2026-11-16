---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · 功能 · Guides · Tuist",
  "description": "喺 Tuist Sandboxes（Linux 或 macOS）上面運行 Claude Managed Agents session 同 Claude Code cloud session（包括 claude.ai、桌面同流動應用程式，以及 claude --cloud）。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **只限邀請**
>
> Tuist Sandboxes（包括 Linux 同 macOS）目前只限邀請。[聯絡我哋](mailto:contact@tuist.dev)或喺[社區 Slack](https://slack.tuist.dev)通知我哋，為你嘅帳戶申請存取權限。

Anthropic 負責運行 Claude 嘅代理循環，而*自託管環境*決定 Claude 工具嘅運行位置。將一個環境連接至 Tuist，入面每個工作階段都會獲得自己專屬嘅 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>，可選擇 Linux 或 macOS。Tuist 會運行呢啲環境所需嘅 workers 同 runners，所以你唔需要自行託管任何東西。

有兩種類型嘅環境，每種對應一個 Claude 產品：

- **[Claude Managed Agents](#managed-agents)**：你透過 Claude API 或 Tuist 嘅 agent-sessions API 啟動嘅工作階段。你喺[Claude Console](https://platform.claude.com/environments)建立環境（`env_…`），每個工作階段都可以選擇 Linux 或 macOS。
- **[Claude Code](#claude-code)**：開發人員從 claude.ai、Claude 桌面同流動應用程式，以及`claude --cloud`啟動嘅雲端工作階段。Claude Team 或 Enterprise 擁有者喺 claude.ai 管理員設定中為每個平台建立環境（`ccpool_…`），開發人員透過選擇環境來揀選 Linux 或 macOS。

兩者均由帳戶管理員透過 Tuist API 進行連接。使用`tuist auth login`進行身份驗證，然後：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 連接環境 {#managed-agents-connect}

從你帳戶嘅**Settings → Integrations → Claude**進行連接。表單會要求提供自託管環境，以及 Tuist 啟動工作階段時使用嘅憑證：

1. **建立環境。** 喺 Claude Console 嘅[Environments](https://platform.claude.com/environments)頁面建立自託管環境，打開佢並點擊**Generate environment key**。Anthropic 只會喺 Console 生成環境金鑰。
2. 使用表單頂部嘅選擇器**揀選憑證**（見下文）。
3. **貼上環境 ID 同金鑰**，並選擇環境 sandbox 嘅平台同規格。

Tuist 喺儲存任何資料之前會使用憑證抓取環境，所以如果憑證、ID 或工作區錯誤，表單會顯示失敗。佢會加密儲存金鑰，之後不再顯示。一分鐘內，Tuist 就會開始為該環境嘅工作階段提供服務。請參閱<.localized_link href="/guides/features/sandboxes#platforms">Linux 同 macOS</.localized_link>了解規格。

#### 使用 API 金鑰 {#managed-agents-connect-api-key}

呢個係預設選項，亦係試用 sandbox 最快捷嘅方法。貼上具有環境工作區開發人員角色嘅 API 金鑰。整合功能會標記使用 API 金鑰嘅環境；喺依賴佢之前，請改用聯合身份連接，咁樣 Tuist 就唔會持有長期有效嘅金鑰。

#### 使用聯合身份 {#managed-agents-connect-federated}

Tuist 使用 Anthropic 嘅[Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation)進行身份驗證，所以你永遠唔需要提供 Anthropic API 金鑰。你需要喺 Anthropic 組織中擁有管理員角色。

1. **信任 Tuist。** 表單會顯示你帳戶嘅發行者 URL 同主體前綴。喺 Claude Console，打開[Workload identity](https://platform.claude.com/settings/workload-identity-federation)，點擊**Connect workload**，選擇**Custom OIDC**，並輸入佢哋，範圍設為`workspace:developer`。將精靈建立嘅服務帳戶添加到環境嘅工作區。
2. **輸入 ID。** 組織 ID 位於**Settings → Organization**下方，工作區 ID 位於**Settings → Workspaces**下方。連接工作負載完成後會顯示服務帳戶同聯合規則 ID，Workload identity 中規則嘅頁面亦會再次顯示佢哋。佢哋都唔係機密。如果 Anthropic 拒絕 Tuist 嘅令牌，Console 嘅[authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history)會顯示原因。

#### 使用 API {#managed-agents-connect-api}

要從自動化流程連接，請喺[Claude Console](https://platform.claude.com/environments)建立自託管環境，生成其金鑰，並將兩者發送俾 Tuist：

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

要透過 Tuist API 啟動工作階段，亦請發送四個聯合 ID（見[不使用 API 金鑰連接](#managed-agents-federation)）或`anthropic_api_key`。除非你傳遞`"platform": "darwin"`，否則環境會喺 Linux 上運行；`vcpus`、`memory_mb`同`workspace_gb`會改變其 sandbox 嘅規格。

### 啟動工作階段 {#managed-agents-sessions}

除非工作階段要求其他平台，否則每個工作階段都會喺環境嘅平台上運行。

**使用 Claude API**，照常使用環境 ID 建立工作階段，並將工作階段元數據中嘅`tuist_platform`設為`macos`或`linux`：

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

`repository_url`同（可選）`repository_ref`（分支或提交）會讓 Tuist 喺代理第一次輪詢之前，將公共儲存庫克隆到 sandbox 中。

**使用 Tuist 嘅 agent-sessions API**，Tuist 會為你建立代理同工作階段，並克隆已連接到你 Tuist 帳戶嘅私人 GitHub 儲存庫：

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

當帳戶有多個環境時，請傳遞`agent_environment_id`。你可以使用`GET /agent-sessions/{id}/events`追蹤工作階段，使用`POST /agent-sessions/{id}/messages`回覆，並使用`POST /agent-sessions/{id}/archive`結束佢。

儲存庫喺 Linux 上檢出到`/workspace`，喺 macOS 上檢出到`/Users/runner/work`。工作階段嘅 sandbox 會喺代理完成一輪後暫停，並喺收到下一條訊息時恢復。

> [!WARNING]
> 任何能夠喺擁有該環境嘅 Claude 工作區中建立工作階段嘅人，都可以喺你嘅 Tuist 帳戶上運行工作階段，並可以透過工作階段元數據請求 macOS。請相應限制對該工作區嘅訪問。

### 不使用 API 金鑰連接 {#managed-agents-federation}

儀表板會為你設定好呢一切。透過 API，Tuist 嘅運作方式相同：每個帳戶喺 Tuist 都有自己嘅 OpenID Connect 發行者`https://tuist.dev/oidc/accounts/<account id>`，並為每次調用 Anthropic 簽署一個短期令牌，然後將其交換為持續幾分鐘嘅 Anthropic 訪問令牌。信任你發行者嘅聯合規則永遠唔會接受 Tuist 為其他帳戶簽署嘅令牌。

- 每個代理環境回應都包括`federation_issuer_url`同`federation_subject`（`account:123:agent-environment:456`）。喺 Console 嘅 Custom OIDC 精靈中，使用發行者 URL，並使用該確切主體以僅允許此環境，或使用`account:123:*`以允許帳戶嘅所有環境。儀表板嘅設定檢查使用主體`account:123:setup`，只有前綴允許佢。使用範圍`workspace:developer`。
- 喺建立時或使用`PATCH /agent-environments/{id}`時，將組織、工作區、服務帳戶同規則 ID 作為`anthropic_organization_id`、`anthropic_workspace_id`、`anthropic_service_account_id`同`anthropic_federation_rule_id`發送。當環境同時擁有 ID 同 API 金鑰時，Tuist 會使用聯合身份。

> [!NOTE]
> Anthropic 會透過 HTTPS 喺端口 443 從公共主機名獲取發行者嘅金鑰。如果你自託管嘅 Tuist 伺服器無法從互聯網訪問，請喺 Console 中選擇**內聯** JWKS 來源，並貼上你伺服器喺`<issuer>/jwks.json`提供嘅金鑰集。每當 Tuist 嘅簽署金鑰更改時（即伺服器嘅`TUIST_SECRET_KEY_TOKENS`更改，或者如果未設置則為`TUIST_SECRET_KEY_BASE`更改），請再次貼上。

## Claude Code {#claude-code}

Claude Code 雲端工作階段係開發人員從[claude.ai/code](https://claude.ai/code)、Claude 桌面同移動應用程式，以及`claude --cloud`啟動嘅工作階段。佢哋透過環境嚟選擇工作階段運行嘅位置，因此你需要為你希望提供嘅每個平台連接一個環境。

### 連接環境 {#claude-code-connect}

1. Claude 組織擁有者喺[雲端環境](https://claude.ai/admin-settings/cloud-environments)管理頁面開啟**允許自託管環境**。這需要 Team 或 Enterprise 計劃；請參閱 Anthropic 嘅[自託管環境](https://code.claude.com/docs/en/self-hosted-environments)指南。
2. 喺同一頁面上，為每個平台建立一個自託管環境，使用開發人員將看到嘅名稱，例如**Tuist Linux**同**Tuist macOS**。複製每個環境嘅`ccpool_…` ID 同其環境金鑰，該金鑰僅顯示一次。
3. 將每個環境連接到你嘅 Tuist 帳戶，將`kind`設為`claude_code`及其平台：

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

   對另一個環境嘅 ID 同金鑰重複此操作，並將`"platform": "linux"`設為相應值。

一分鐘內，環境就準備好接受工作階段。閒置工作階段會保持其 sandbox 運行 30 分鐘，然後暫停；工作階段嘅下一條訊息會恢復同一個 sandbox。使用`max_idle_seconds`更改等待時間（最多 3600 秒）。

### 選擇 Linux 或 macOS {#claude-code-choose}

開發人員喺啟動雲端工作階段時選擇環境，從而選擇平台：

- **claude.ai、桌面同移動應用程式：** 喺新工作階段嘅環境選擇器中選擇**Tuist Linux**或**Tuist macOS**。
- **Claude Code CLI：** 喺`claude`中運行`/remote-env`並按名稱選擇環境。`claude --cloud "<task>"`隨後會喺其上運行。要為單個工作階段選擇一個環境，請傳遞其 ID：`claude --cloud "<task>" --environment ccpool_...`。
- **整個團隊或儲存庫：** 喺 Claude Code [設定](https://code.claude.com/docs/en/settings)中設置默認環境嘅 ID，例如喺儲存庫嘅`.claude/settings.json`中：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

呢啲環境中嘅工作階段照常使用你組織嘅 Claude Code 用量，並且佢哋嘅 sandboxes 會計入你嘅 Tuist 帳戶。

### 更快嘅工作階段啟動同構建 {#claude-code-caching}

- **Tuist 緩存：** 工作階段會獲得`TUIST_URL`，並且當你嘅帳戶喺同一機架中有緩存時，會獲得`TUIST_CACHE_ENDPOINT`。工作階段中嘅 Tuist CLI 同`tuist_ex` Mix 任務會使用工作階段嘅身份令牌自行登錄。請參閱認證指南中嘅<.localized_link href="/guides/server/authentication#claude-code-sessions">Claude Code 工作階段</.localized_link>。
- **緩存檢出：** 當你帳戶嘅 Tuist GitHub 應用程式可以讀取工作階段嘅儲存庫時，新工作階段會從你嘅 Tuist runners 使用嘅相同緩存檢出開始，因此它只會獲取缺少嘅提交，而唔係克隆。當工作階段結束時，它會返還默認分支最新提交嘅對象，這使得即使對於唔喺 Tuist 上運行 CI 嘅儲存庫，緩存檢出也保持最新。只有 GitHub 報告嘅默認分支提交會更新它；工作階段自己嘅分支永遠唔會。禁用 sandboxes 或卸載應用程式以停止此操作。
- **macOS：** Mac 會與每個 VM 共享 Claude Code 構建工作階段運行，因此新工作階段無需下載它。

## 喺任何 Claude Code 工作階段中使用 Mac {#remote-mac}

喺 Linux 上運行嘅 Claude Code 工作階段（例如 Anthropic 託管環境中嘅雲端工作階段）仍然可以喺 Tuist macOS sandbox 上構建同測試 Apple 平台代碼，如<.localized_link href="/guides/features/sandboxes#coding-agents">從編碼代理喺 Mac 上構建</.localized_link>中所述。與**Tuist macOS**環境不同，工作階段保留其自己嘅環境。

喺**Tuist Linux**環境中無需設置任何內容：Tuist CLI 同 Tuist MCP 伺服器已經安裝並使用工作階段嘅身份登錄。

對於 Anthropic 託管環境中嘅雲端工作階段：

1. 使 Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP 伺服器</.localized_link>可供工作階段使用：喺 claude.ai 中添加`https://tuist.dev/mcp`作為連接器並為工作階段啟用，或喺儲存庫已提交嘅`.mcp.json`中聲明它。
2. 喺環境嘅[設置腳本](https://code.claude.com/docs/en/cloud-environments#setup-scripts)中安裝 Tuist CLI，例如使用`curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`。
3. 建立一個具有`account:sandboxes:write`範圍嘅<.localized_link href="/guides/server/authentication#account-tokens">帳戶令牌</.localized_link>，並將其作為`TUIST_TOKEN`添加到環境嘅[環境變量](https://code.claude.com/docs/en/cloud-environments#set-environment-variables)中。每個使用該環境嘅人都可以讀取它，因此除非佢哋也可以使用你嘅緩存，否則唔好給予其他範圍：Mac 上嘅命令僅喺令牌具有<.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">緩存訪問權限</.localized_link>嘅範圍內獲得該權限，因此添加`ci`以便 Mac 上嘅構建可以讀寫你嘅緩存。
4. 讓環境能夠訪問 Tuist。Anthropic 默認嘅**受信任**網絡訪問唔包括`tuist.dev`，因此選擇**自定義**，保留默認域名，並將`tuist.dev`添加到**允許嘅域名**。CLI 透過`tuist.dev`將工作階段嘅文件上傳到 Mac，因此它無需其他域名。

第一次同步後，Claude 會喺 Mac 上嘅儲存庫根目錄運行`mise install`以安裝項目鎖定嘅 Tuist；Tuist 4.218.0 及更高版本隨後會喺每個命令中自行登錄到你帳戶嘅緩存。

Claude 會喺任務完成後刪除 Mac。遺留嘅 Mac 會喺閒置時暫停，並喺暫停 14 天後刪除。以這種方式建立嘅 Mac 會像任何其他 sandbox 一樣計入你嘅 Tuist 帳戶。
