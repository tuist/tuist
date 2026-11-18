---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · 功能 · Guides · Tuist",
  "description": "喺 Tuist Sandboxes（Linux 或 macOS）上執行 Claude Managed Agents 會話同埋 Claude Code 雲端會話（claude.ai、桌面及流動應用程式，以及 claude --cloud）。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **僅限邀請**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)或在[社區 Slack](https://slack.tuist.dev)中聯繫我們，以申請帳戶存取權限。

Anthropic 負責運行 Claude 的代理循環，而*自託管環境*則決定 Claude 工具的运行位置。將一個環境連接到 Tuist，其中的每個工作階段都會獲得專屬的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>，可在 Linux 或 macOS 上運行。Tuist 會運行這些環境所需的 worker 和 runner，因此你無需自行託管任何基礎設施。

有兩種類型的環境，每種對應一個 Claude 產品：

- **[Claude Managed Agents](#managed-agents)**：你透過 Claude API 或 Tuist 的 agent-sessions API 啟動的工作階段。你在[Claude Console](https://platform.claude.com/environments)中建立環境（`env_…`），每個工作階段均可選擇 Linux 或 macOS。
- **[Claude Code](#claude-code)**：開發人員從 claude.ai、Claude 桌面和移動應用程式以及`claude --cloud`啟動的雲端工作階段。Claude Team 或 Enterprise 擁有者在 claude.ai 管理設定中為每個平台建立環境（`ccpool_…`），開發人員透過選擇環境來挑選 Linux 或 macOS。

兩者均由帳戶管理員透過 Tuist API 進行連接。使用`tuist auth login`進行身份驗證，然後：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 連接環境 {#managed-agents-connect}

1. 在[Claude Console](https://platform.claude.com/environments)中，點擊**Create environment**，並在**Hosting**下選擇**Self-hosted**。打開環境，點擊**Generate environment key**，並複製環境的`env_…` ID 和金鑰。詳情請參閱 Anthropic 的[self-hosted sandboxes](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes)指南。
2. 將其連接到你的 Tuist 帳戶：

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "anthropic_environment_id": "env_...",
       "environment_key": "<environment key>",
       "anthropic_api_key": "<Anthropic API key>"
     }'
   ```

   `anthropic_api_key`為可選項目。它允許你透過 Tuist 的 API 啟動工作階段，如下所述。Tuist 會加密儲存這兩個金鑰，且絕不會返回它們。

在一分鐘內，Tuist 開始為該環境的工作階段提供服務。除非你傳遞`"platform": "darwin"`，否則環境將在 Linux 上運行。你也可以傳遞`vcpus`、`memory_mb`和`workspace_gb`來更改其 sandbox 的配置；詳見<.localized_link href="/guides/features/sandboxes#platforms">Linux and macOS</.localized_link>。

### 啟動工作階段 {#managed-agents-sessions}

除非工作階段要求其他平台，否則每個工作階段都在環境的平台上運行。

**使用 Claude API**時，照常使用環境 ID 建立工作階段，並將工作階段元數據中的`tuist_platform`設定為`macos`或`linux`：

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

`repository_url`以及可選的`repository_ref`（分支或提交）會讓 Tuist 在代理的第一輪操作之前，將公共存儲庫克隆到 sandbox 中。

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

當帳戶擁有多個環境時，請傳遞`agent_environment_id`。你可以透過`GET /agent-sessions/{id}/events`追蹤工作階段，透過`POST /agent-sessions/{id}/messages`回覆，並透過`POST /agent-sessions/{id}/archive`結束工作階段。

存儲庫在 Linux 上的`/workspace`和 macOS 上的`/Users/runner/work`中签出。工作階段的 sandbox 會在代理完成一輪操作後暫停，並在收到下一條訊息時恢復。

> [!WARNING]
> 任何能在擁有該環境的 Claude 工作區中建立工作階段的人，都可以在你的 Tuist 帳戶上運行工作階段，並可以透過工作階段元數據請求 macOS。請相應地限制對該工作區的存取權限。

## Claude Code {#claude-code}

Claude Code 雲端工作階段是指開發人員從[claude.ai/code](https://claude.ai/code)、Claude 桌面和移動應用程式以及`claude --cloud`啟動的工作階段。他們透過環境選擇工作階段的運行位置，因此你需要為每個想提供的平台連接一個環境。

### 連接環境 {#claude-code-connect}

1. Claude 組織擁有者在[Cloud environments](https://claude.ai/admin-settings/cloud-environments)管理頁面開啟**Allow self-hosted environments**。這需要 Team 或 Enterprise 計劃；詳見 Anthropic 的[self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments)指南。
2. 在同一頁面上，為每個平台建立一個自託管環境，並設定開發人員將看到的名稱，例如**Tuist Linux**和**Tuist macOS**。複製每個環境的`ccpool_…` ID 及其環境金鑰，該金鑰僅顯示一次。
3. 將每個環境連接到你的 Tuist 帳戶，將`kind`設定為`claude_code`並指定其平台：

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

   使用`"platform": "linux"`以及其他環境的 ID 和金鑰重複上述步驟。

在一分鐘內，環境即可接收工作階段。閒置工作階段會保持其 sandbox 運行 30 分鐘，然後暫停；工作階段的下一條訊息會恢復同一個 sandbox。透過`max_idle_seconds`更改等待時間（最多 3600 秒）。

### 選擇 Linux 或 macOS {#claude-code-choose}

開發人員在啟動雲端工作階段時選擇環境，從而選擇平台：

- **claude.ai、桌面和移動應用程式：** 在新工作階段的環境選擇器中選擇**Tuist Linux**或**Tuist macOS**。
- **Claude Code CLI：** 在`claude`中運行`/remote-env`並按名稱選擇環境。`claude --cloud "<task>"`隨後將在該環境上運行。若要為單個工作階段選擇環境，請傳遞其 ID：`claude --cloud "<task>" --environment ccpool_...`。
- **整個團隊或存儲庫：** 在 Claude Code [settings](https://code.claude.com/docs/en/settings)中設定默認環境的 ID，例如在存儲庫的`.claude/settings.json`中：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

這些環境中的工作階段會照常使用你組織的 Claude Code 用量，而其 sandbox 則計入你的 Tuist 帳戶。
