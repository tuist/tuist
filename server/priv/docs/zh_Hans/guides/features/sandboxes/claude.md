---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · 功能 · 指南 · Tuist",
  "description": "在 Tuist Sandboxes（Linux 或 macOS）上运行 Claude Managed Agents 会话和 Claude Code 云端会话（claude.ai、桌面和移动应用，以及 claude --cloud）。"
}
---
# Claude {#claude}

> [!IMPORTANT]
> **仅限邀请**
>
> Tuist Sandboxes（包括 Linux 和 macOS）目前仅限受邀用户使用。[联系我们](mailto:contact@tuist.dev)或在[社区 Slack](https://slack.tuist.dev)中留言，为你的账户申请访问权限。

Anthropic 运行 Claude 的代理循环，而*自托管环境*决定 Claude 的工具在哪里运行。将一个环境连接到 Tuist，其中的每个会话都会获得一个专属的 Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>，可在 Linux 或 macOS 上运行。Tuist 会运行这些环境所需的工作器和 runner，因此你无需自行托管任何内容。

有两种类型的环境，每种 Claude 产品对应一种：

- **[Claude Managed Agents](#managed-agents)**：你通过 Claude API 或 Tuist 的 agent-sessions API 启动的会话。你在 [Claude Console](https://platform.claude.com/environments) 中创建环境（`env_…`），每个会话可以选择 Linux 或 macOS。
- **[Claude Code](#claude-code)**：开发者从 claude.ai、Claude 桌面和移动应用以及`claude --cloud`启动的云会话。Claude Team 或 Enterprise 所有者在 claude.ai 管理设置中为每个平台创建一个环境（`ccpool_…`），开发者通过选择环境来挑选 Linux 或 macOS。

两者均由账户管理员通过 Tuist API 进行连接。使用`tuist auth login`进行身份验证，然后：

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### 连接环境 {#managed-agents-connect}

1. 在[Claude Console](https://platform.claude.com/environments)中，点击**Create environment**，并在**Hosting**下选择**Self-hosted**。打开该环境，点击**Generate environment key**，并复制环境的`env_…` ID 和密钥。有关详细信息，请参阅 Anthropic 的[self-hosted sandboxes](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes)指南。
2. 将其连接到你的 Tuist 账户：

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "anthropic_environment_id": "env_...",
       "environment_key": "<environment key>",
       "anthropic_api_key": "<Anthropic API key>"
     }'
   ```

   `anthropic_api_key`是可选的。它允许你通过 Tuist 的 API 启动会话，如下所述。Tuist 会对这两个密钥进行加密存储，且永远不会返回它们。

在一分钟内，Tuist 开始为该环境的会话提供服务。除非你传入`"platform": "darwin"`，否则环境将在 Linux 上运行。你还可以传入`vcpus`、`memory_mb`和`workspace_gb`以更改其 sandbox 的配置；请参阅<.localized_link href="/guides/features/sandboxes#platforms">Linux and macOS</.localized_link>。

### 启动会话 {#managed-agents-sessions}

每个会话都在环境的平台上运行，除非会话请求其他平台。

**使用 Claude API**时，照常使用环境的 ID 创建会话，并将会话元数据中的`tuist_platform`设置为`macos`或`linux`：

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

`repository_url`以及可选的`repository_ref`（分支或提交）会让 Tuist 在代理的第一轮操作之前将公共仓库克隆到 sandbox 中。

**使用 Tuist 的 agent-sessions API**时，Tuist 会为你创建代理和会话，并克隆已连接到你的 Tuist 账户的私有 GitHub 仓库：

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

当账户拥有多个环境时，请传入`agent_environment_id`。你可以使用`GET /agent-sessions/{id}/events`跟踪会话，使用`POST /agent-sessions/{id}/messages`回复，并使用`POST /agent-sessions/{id}/archive`结束会话。

仓库在 Linux 上的检出路径为`/workspace`，在 macOS 上为`/Users/runner/work`。会话的 sandbox 会在代理完成一轮操作后暂停，并在收到下一条消息时恢复。

> [!WARNING]
> 任何能够在拥有该环境的 Claude 工作区中创建会话的人，都可以在你的 Tuist 账户上运行会话，并可以通过会话元数据请求 macOS。请相应地限制对该工作区的访问。

## Claude Code {#claude-code}

Claude Code 云会话是指开发者从[claude.ai/code](https://claude.ai/code)、Claude 桌面和移动应用以及`claude --cloud`启动的会话。他们通过环境来选择会话的运行位置，因此你需要为想要提供的每个平台连接一个环境。

### 连接环境 {#claude-code-connect}

1. Claude 组织的所有者在[Cloud environments](https://claude.ai/admin-settings/cloud-environments)管理页面上启用**Allow self-hosted environments**。这需要 Team 或 Enterprise 计划；请参阅 Anthropic 的[self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments)指南。
2. 在同一页面上，为每个平台创建一个自托管环境，并设置开发者将看到的名称，例如**Tuist Linux**和**Tuist macOS**。复制每个环境的`ccpool_…` ID 及其环境密钥，该密钥仅显示一次。
3. 将每个环境连接到你的 Tuist 账户，将`kind`设置为`claude_code`并指定其平台：

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

   对另一个环境的 ID 和密钥重复此操作，并将`"platform": "linux"`设置为相应值。

在一分钟内，环境即可接受会话。空闲会话会保持其 sandbox 运行 30 分钟，然后将其暂停；会话的下一条消息会恢复相同的 sandbox。使用`max_idle_seconds`更改等待时间（最多 3600 秒）。

### 选择 Linux 或 macOS {#claude-code-choose}

开发者在启动云会话时选择环境，从而选择平台：

- **claude.ai、桌面和移动应用：** 在新会话的环境选择器中选择**Tuist Linux**或**Tuist macOS**。
- **Claude Code CLI：** 在`claude`中运行`/remote-env`并按名称选择环境。`claude --cloud "<task>"`随后将在该环境中运行。要为单个会话选择一个环境，请传入其 ID：`claude --cloud "<task>" --environment ccpool_...`。
- **整个团队或仓库：** 在 Claude Code [settings](https://code.claude.com/docs/en/settings)中设置默认环境的 ID，例如在仓库的`.claude/settings.json`中：

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

这些环境中的会话会照常使用你组织的 Claude Code 用量，并且其 sandbox 计入你的 Tuist 账户。
